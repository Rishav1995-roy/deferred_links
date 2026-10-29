import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'client.dart';
import 'config.dart';
import 'install_referrer.dart';
import 'models.dart';
import 'platform.dart';

/// Prefix of the token the iOS landing page copies when clipboard matching is
/// enabled on the server.
const String clipboardTokenPrefix = 'deferredlinks:';

final RegExp _shortId = RegExp(r'^[A-Za-z0-9_-]{4,64}$');

/// Entry point: incoming links, deferred links and short-link creation.
///
/// ```dart
/// DeferredLinks.instance.configure(
///   DeferredLinksConfig(serverUrl: Uri.parse('https://links.example.com')),
/// );
/// final first = await DeferredLinks.instance.getInitialLink();
/// DeferredLinks.instance.linkStream.listen(handle);
/// final deferred = await DeferredLinks.instance.checkDeferredLink();
/// ```
class DeferredLinks {
  /// Creates an instance. Use [DeferredLinks.instance] in apps; the
  /// parameters exist so tests can inject fakes.
  DeferredLinks({
    DeferredLinksPlatform? platform,
    TargetPlatform? targetPlatform,
    Future<String?> Function()? clipboardReader,
  })  : _platform = platform ?? MethodChannelDeferredLinksPlatform(),
        _targetPlatform = targetPlatform,
        _clipboardReader = clipboardReader ?? _readSystemClipboard;

  /// The shared instance.
  static final DeferredLinks instance = DeferredLinks();

  final DeferredLinksPlatform _platform;
  final TargetPlatform? _targetPlatform;
  final Future<String?> Function() _clipboardReader;

  DeferredLinksConfig? _config;
  DeferredLinksClient? _client;
  Future<DeepLink?>? _initial;

  /// The active configuration, or `null` before [configure].
  DeferredLinksConfig? get config => _config;

  /// Sets the server configuration. Call once at startup, before
  /// [getInitialLink] if you use short links.
  void configure(DeferredLinksConfig config) {
    _client?.close();
    _config = config;
    _client = DeferredLinksClient(config);
  }

  static Future<String?> _readSystemClipboard() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  TargetPlatform get _target => _targetPlatform ?? defaultTargetPlatform;

  /// The link that launched the app, or `null`. The same value is returned on
  /// repeated calls within one process.
  Future<DeepLink?> getInitialLink() => _initial ??= _loadInitial();

  Future<DeepLink?> _loadInitial() async {
    final raw = await _platform.getInitialLink();
    return raw == null ? null : _resolveIncoming(raw);
  }

  /// Links received while the app is running (warm start). Short links are
  /// resolved through the server; if that fails the raw URL is delivered.
  Stream<DeepLink> get linkStream =>
      _platform.linkStream.asyncMap(_resolveIncoming);

  Future<DeepLink> _resolveIncoming(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null) return DeepLink(uri: Uri(path: raw));
    final client = _client;
    final cfg = _config;
    if (client != null &&
        cfg != null &&
        cfg.shortLinkHosts.contains(uri.host) &&
        uri.pathSegments.length == 1 &&
        _shortId.hasMatch(uri.pathSegments.first)) {
      final id = uri.pathSegments.first;
      try {
        final resolved = await client.resolve(id);
        if (resolved != null) return resolved;
      } on Object {
        // Offline or server down: hand the raw URL to the app.
      }
      return DeepLink(uri: uri, linkId: id);
    }
    return DeepLink(uri: uri);
  }

  /// Runs the once-per-install check for a deferred link.
  ///
  /// Call it on every launch; it returns [DeferredStatus.notFirstLaunch] after
  /// the first conclusive check. Inconclusive failures (offline, Play service
  /// busy) are retried on the next launch.
  ///
  /// Android is deterministic (Install Referrer). iOS is best effort: see
  /// [DeepLink.confidence] and the README before navigating automatically.
  Future<DeferredLinkResult> checkDeferredLink() async {
    if (!await _platform.isFirstLaunch()) {
      return const DeferredLinkResult(DeferredStatus.notFirstLaunch);
    }
    try {
      return switch (_target) {
        TargetPlatform.android => await _checkAndroid(),
        TargetPlatform.iOS => await _checkIos(),
        _ => await _conclude(null),
      };
    } on Object catch (e) {
      return DeferredLinkResult(DeferredStatus.error, error: e);
    }
  }

  Future<DeferredLinkResult> _conclude(DeepLink? link) async {
    await _platform.markDeferredChecked();
    return link == null
        ? const DeferredLinkResult(DeferredStatus.noMatch)
        : DeferredLinkResult(DeferredStatus.matched, link: link);
  }

  Future<DeferredLinkResult> _checkAndroid() async {
    final ref = await _platform.getInstallReferrer();
    if (ref.status == 'transient') {
      return DeferredLinkResult(DeferredStatus.error,
          error: StateError('Play Install Referrer service not ready'));
    }
    if (ref.status != 'ok') return _conclude(null);
    final parsed = parseInstallReferrer(ref.referrer);
    if (parsed.isEmpty) return _conclude(null);

    DeepLink? link;
    final client = _client;
    if (client != null && parsed.clickId != null) {
      try {
        link = await client.confirmInstall(parsed.clickId!);
      } on Object {
        if (parsed.deepLink == null) rethrow;
      }
    }
    if (link == null && parsed.deepLink != null) {
      link = DeepLink(
        uri: parsed.deepLink!,
        source: LinkSource.deferred,
        method: DeferredMethod.installReferrer,
        confidence: MatchConfidence.exact,
      );
    }
    return _conclude(link);
  }

  Future<DeferredLinkResult> _checkIos() async {
    final client = _client;
    final cfg = _config;
    if (client == null || cfg == null) {
      // Nothing to match against; keep the check open until configured.
      return const DeferredLinkResult(DeferredStatus.noMatch);
    }
    String? token;
    if (cfg.useClipboard) {
      final text = (await _clipboardReader())?.trim();
      if (text != null && text.startsWith(clipboardTokenPrefix)) token = text;
    }
    final signals = await _platform.getDeviceSignals();
    final res = await client.match(signals, clipboard: token);
    if (!res.matched ||
        res.link == null ||
        !(res.confidence ?? MatchConfidence.low).atLeast(cfg.minConfidence)) {
      return _conclude(null);
    }
    return _conclude(res.link);
  }

  /// Creates a short link on your server.
  ///
  /// Throws [StateError] before [configure] and [DeferredLinksException] when
  /// the server rejects the request.
  Future<ShortLink> createShortLink(ShortLinkRequest request) {
    final client = _client;
    if (client == null) {
      throw StateError('Call DeferredLinks.configure() first.');
    }
    return client.createShortLink(request);
  }
}
