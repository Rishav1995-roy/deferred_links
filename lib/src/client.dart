import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

/// Thrown when the server answers with an error status or garbage.
class DeferredLinksException implements Exception {
  /// Creates the exception.
  DeferredLinksException(this.message, {this.statusCode});

  /// What went wrong.
  final String message;

  /// HTTP status, if the server answered.
  final int? statusCode;

  @override
  String toString() => 'DeferredLinksException($statusCode): $message';
}

/// The result of a server-side match.
class MatchResponse {
  /// Creates a match response.
  const MatchResponse({
    required this.matched,
    this.link,
    this.method,
    this.confidence,
    this.score,
  });

  /// Whether the server found a click for this device.
  final bool matched;

  /// The matched link.
  final DeepLink? link;

  /// How it was matched.
  final DeferredMethod? method;

  /// How trustworthy it is.
  final MatchConfidence? confidence;

  /// The raw 0..1 score the server computed (fingerprint matches).
  final double? score;
}

/// Thin HTTP client for the reference server's API.
class DeferredLinksClient {
  /// Creates a client for [config].
  DeferredLinksClient(this.config) : _http = config.httpClient ?? http.Client();

  /// The configuration in use.
  final DeferredLinksConfig config;
  final http.Client _http;

  Uri _url(String path) {
    final base = config.serverUrl;
    final prefix = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(path: '$prefix$path', query: null);
  }

  Map<String, String> get _jsonHeaders => <String, String>{
        'content-type': 'application/json',
        if (config.apiKey != null) 'authorization': 'Bearer ${config.apiKey}',
      };

  Future<Map<String, Object?>> _send(
    Future<http.Response> Function() call, {
    Set<int> allow = const <int>{},
  }) async {
    final http.Response res;
    try {
      res = await call().timeout(config.requestTimeout);
    } on TimeoutException {
      throw DeferredLinksException('Request timed out');
    }
    if (res.statusCode >= 400 && !allow.contains(res.statusCode)) {
      throw DeferredLinksException('Server error ${res.body}',
          statusCode: res.statusCode);
    }
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, Object?>) {
        return <String, Object?>{...decoded, '_status': res.statusCode};
      }
    } on FormatException {
      // fall through
    }
    throw DeferredLinksException('Unexpected response',
        statusCode: res.statusCode);
  }

  /// `POST /v1/links`.
  Future<ShortLink> createShortLink(ShortLinkRequest request) async {
    final json = await _send(() => _http.post(_url('/v1/links'),
        headers: _jsonHeaders, body: jsonEncode(request.toJson())));
    return ShortLink.fromJson(json);
  }

  /// `GET /v1/resolve/<id>`: the link behind a short id (an App Link open).
  /// Returns `null` when the link is unknown or expired.
  Future<DeepLink?> resolve(String id) async {
    final json = await _send(
      () => _http.get(_url('/v1/resolve/${Uri.encodeComponent(id)}')),
      allow: const <int>{404},
    );
    if (json['_status'] == 404) return null;
    return _linkFromJson(json, LinkSource.incoming);
  }

  /// `POST /v1/clicks/<id>/install`: confirms an Android install and returns
  /// the link. `null` when the click is unknown or expired.
  Future<DeepLink?> confirmInstall(String clickId, {String? platform}) async {
    final json = await _send(
      () => _http.post(
        _url('/v1/clicks/${Uri.encodeComponent(clickId)}/install'),
        headers: _jsonHeaders,
        body: jsonEncode(<String, Object?>{'platform': platform ?? 'android'}),
      ),
      allow: const <int>{404},
    );
    if (json['_status'] == 404) return null;
    return _linkFromJson(json, LinkSource.deferred,
        method: DeferredMethod.installReferrer,
        confidence: MatchConfidence.exact);
  }

  /// `POST /v1/match`: iOS best-effort match.
  Future<MatchResponse> match(DeviceSignals signals,
      {String? clipboard}) async {
    final json = await _send(() => _http.post(_url('/v1/match'),
        headers: _jsonHeaders,
        body: jsonEncode(<String, Object?>{
          'signals': signals.toJson(),
          if (clipboard != null) 'clipboard': clipboard,
        })));
    if (json['matched'] != true) return const MatchResponse(matched: false);
    final method = switch (json['method']) {
      'clipboard' => DeferredMethod.clipboard,
      _ => DeferredMethod.fingerprint,
    };
    final confidence = MatchConfidence.values.firstWhere(
      (c) => c.name == json['confidence'],
      orElse: () => MatchConfidence.low,
    );
    final link = _linkFromJson(
      (json['link']! as Map<Object?, Object?>).cast<String, Object?>(),
      LinkSource.deferred,
      method: method,
      confidence: confidence,
    );
    return MatchResponse(
      matched: true,
      link: link,
      method: method,
      confidence: confidence,
      score: (json['score'] as num?)?.toDouble(),
    );
  }

  DeepLink _linkFromJson(
    Map<String, Object?> json,
    LinkSource source, {
    DeferredMethod? method,
    MatchConfidence? confidence,
  }) {
    final data = <String, String>{
      for (final e
          in ((json['data'] as Map<Object?, Object?>?) ?? const {}).entries)
        '${e.key}': '${e.value}',
    };
    return DeepLink(
      uri: Uri.parse(json['deepLink']! as String),
      data: data,
      linkId: json['id'] as String?,
      source: source,
      method: method,
      confidence: confidence,
    );
  }

  /// Closes the underlying HTTP client when this client created it.
  void close() {
    if (config.httpClient == null) _http.close();
  }
}
