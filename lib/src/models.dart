import 'package:flutter/foundation.dart';

/// How trustworthy a deferred-link match is.
///
/// The order is meaningful: later values are more trustworthy. Use
/// [MatchConfidenceX.atLeast] to compare.
enum MatchConfidence {
  /// Matched on a weak signal set (for example IP + language only). Do not
  /// auto-navigate on this; offer the link instead.
  low,

  /// Matched on IP plus several device signals. Reasonable to navigate.
  medium,

  /// Matched on IP plus every device signal and no competing candidate.
  high,

  /// Matched by an unforgeable token handed over by the store (Android
  /// Install Referrer) or by an explicit user-copied token (iOS clipboard).
  exact,
}

/// Comparison helpers for [MatchConfidence].
extension MatchConfidenceX on MatchConfidence {
  /// Whether this confidence is [other] or better.
  bool atLeast(MatchConfidence other) => index >= other.index;
}

/// The mechanism that produced a deferred link.
enum DeferredMethod {
  /// Google Play Install Referrer (Android). Deterministic.
  installReferrer,

  /// A token the user copied from the landing page (iOS, opt-in). Deterministic
  /// but needs the user to interact with the landing page and shows the iOS
  /// paste prompt.
  clipboard,

  /// Server-side matching of device signals (iOS). Probabilistic.
  fingerprint,
}

/// Where a [DeepLink] came from.
enum LinkSource {
  /// An App Link / Universal Link / custom scheme opened the running or
  /// launching app.
  incoming,

  /// A link recovered after installing the app.
  deferred,
}

/// A resolved deep link.
@immutable
class DeepLink {
  /// Creates a deep link.
  const DeepLink({
    required this.uri,
    this.data = const <String, String>{},
    this.linkId,
    this.source = LinkSource.incoming,
    this.method,
    this.confidence,
  });

  /// The target URI the app should navigate to.
  final Uri uri;

  /// Custom key/values attached to the link when it was created.
  final Map<String, String> data;

  /// The short link id on the server, if the link came from one.
  final String? linkId;

  /// Whether this arrived directly or after an install.
  final LinkSource source;

  /// For deferred links, how it was matched.
  final DeferredMethod? method;

  /// For deferred links, how trustworthy the match is. `null` for
  /// [LinkSource.incoming].
  final MatchConfidence? confidence;

  /// Whether this link was recovered after install.
  bool get isDeferred => source == LinkSource.deferred;

  /// The URI path, e.g. `/product/42`.
  String get path => uri.path;

  /// The URI query parameters.
  Map<String, String> get queryParameters => uri.queryParameters;

  /// Returns a copy with some fields replaced.
  DeepLink copyWith({
    Uri? uri,
    Map<String, String>? data,
    String? linkId,
    LinkSource? source,
    DeferredMethod? method,
    MatchConfidence? confidence,
  }) =>
      DeepLink(
        uri: uri ?? this.uri,
        data: data ?? this.data,
        linkId: linkId ?? this.linkId,
        source: source ?? this.source,
        method: method ?? this.method,
        confidence: confidence ?? this.confidence,
      );

  @override
  bool operator ==(Object other) =>
      other is DeepLink &&
      other.uri == uri &&
      mapEquals(other.data, data) &&
      other.linkId == linkId &&
      other.source == source &&
      other.method == method &&
      other.confidence == confidence;

  @override
  int get hashCode => Object.hash(
        uri,
        Object.hashAll(data.entries.map((e) => Object.hash(e.key, e.value))),
        linkId,
        source,
        method,
        confidence,
      );

  @override
  String toString() =>
      'DeepLink($uri, source: ${source.name}, method: ${method?.name}, '
      'confidence: ${confidence?.name})';
}

/// Why [DeferredLinks.checkDeferredLink] returned what it did.
enum DeferredStatus {
  /// A deferred link was found; see [DeferredLinkResult.link].
  matched,

  /// Not the first launch after install; nothing was checked.
  notFirstLaunch,

  /// The check ran and there is no deferred link (organic install, no
  /// matching click, or the match was ambiguous).
  noMatch,

  /// The check could not complete (network or Play service problem). It will
  /// be retried on the next launch.
  error,
}

/// The outcome of the first-launch deferred link check.
@immutable
class DeferredLinkResult {
  /// Creates a result.
  const DeferredLinkResult(this.status, {this.link, this.error});

  /// What happened.
  final DeferredStatus status;

  /// The recovered link when [status] is [DeferredStatus.matched].
  final DeepLink? link;

  /// The failure when [status] is [DeferredStatus.error].
  final Object? error;

  @override
  String toString() => 'DeferredLinkResult(${status.name}, $link)';
}

/// Device signals sent to the server for iOS best-effort matching.
///
/// Only coarse values are collected. Nothing here is a persistent identifier.
@immutable
class DeviceSignals {
  /// Creates signals.
  const DeviceSignals({
    required this.platform,
    this.osVersion,
    this.model,
    this.screenWidth,
    this.screenHeight,
    this.language,
    this.timezoneOffsetMinutes,
  });

  /// Builds signals from the native method-channel map.
  factory DeviceSignals.fromMap(Map<Object?, Object?> map) => DeviceSignals(
        platform: (map['platform'] as String?) ?? 'unknown',
        osVersion: map['osVersion'] as String?,
        model: map['model'] as String?,
        screenWidth: (map['screenWidth'] as num?)?.toInt(),
        screenHeight: (map['screenHeight'] as num?)?.toInt(),
        language: map['language'] as String?,
        timezoneOffsetMinutes: (map['timezoneOffsetMinutes'] as num?)?.toInt(),
      );

  /// `ios` or `android`.
  final String platform;

  /// OS version string, e.g. `17.4`.
  final String? osVersion;

  /// Hardware model identifier, e.g. `iPhone15,2`.
  final String? model;

  /// Screen width in points (logical pixels).
  final int? screenWidth;

  /// Screen height in points (logical pixels).
  final int? screenHeight;

  /// Preferred language tag, e.g. `en-US`.
  final String? language;

  /// UTC offset of the device time zone in minutes (east is positive).
  final int? timezoneOffsetMinutes;

  /// JSON body for the server's `/v1/match`.
  Map<String, Object?> toJson() => <String, Object?>{
        'platform': platform,
        if (osVersion != null) 'osVersion': osVersion,
        if (model != null) 'model': model,
        if (screenWidth != null) 'screenWidth': screenWidth,
        if (screenHeight != null) 'screenHeight': screenHeight,
        if (language != null) 'language': language,
        if (timezoneOffsetMinutes != null)
          'timezoneOffsetMinutes': timezoneOffsetMinutes,
      };
}

/// A request to create a short link on your server.
@immutable
class ShortLinkRequest {
  /// Creates a request. [deepLink] is where the link should open in the app.
  const ShortLinkRequest({
    required this.deepLink,
    this.data = const <String, String>{},
    this.title,
    this.description,
    this.imageUrl,
    this.fallbackUrl,
    this.alias,
    this.ttl,
    this.androidStoreUrl,
    this.iosStoreUrl,
  });

  /// Target the app opens, e.g. `https://example.com/product/42`.
  final Uri deepLink;

  /// Custom key/values returned to the app with the link.
  final Map<String, String> data;

  /// Social preview title.
  final String? title;

  /// Social preview description.
  final String? description;

  /// Social preview image URL.
  final String? imageUrl;

  /// Where desktop browsers are sent.
  final String? fallbackUrl;

  /// Custom short id (letters, digits, `-`, `_`; 4 to 64 chars).
  final String? alias;

  /// Time after which the link stops working.
  final Duration? ttl;

  /// Overrides the server default Play Store URL for this link.
  final String? androidStoreUrl;

  /// Overrides the server default App Store URL for this link.
  final String? iosStoreUrl;

  /// JSON body for the server's `POST /v1/links`.
  Map<String, Object?> toJson() => <String, Object?>{
        'deepLink': deepLink.toString(),
        if (data.isNotEmpty) 'data': data,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (fallbackUrl != null) 'fallbackUrl': fallbackUrl,
        if (alias != null) 'alias': alias,
        if (ttl != null) 'ttlSeconds': ttl!.inSeconds,
        if (androidStoreUrl != null) 'androidStoreUrl': androidStoreUrl,
        if (iosStoreUrl != null) 'iosStoreUrl': iosStoreUrl,
      };
}

/// A short link created on the server.
@immutable
class ShortLink {
  /// Creates a short link.
  const ShortLink({
    required this.id,
    required this.shortUrl,
    required this.deepLink,
    this.expiresAt,
  });

  /// Parses the server response.
  factory ShortLink.fromJson(Map<String, Object?> json) => ShortLink(
        id: json['id']! as String,
        shortUrl: Uri.parse(json['shortUrl']! as String),
        deepLink: Uri.parse(json['deepLink']! as String),
        expiresAt: json['expiresAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (json['expiresAt']! as num).toInt(),
                isUtc: true,
              ),
      );

  /// Short id, the last path segment of [shortUrl].
  final String id;

  /// The URL to share.
  final Uri shortUrl;

  /// The in-app target.
  final Uri deepLink;

  /// Expiry, if any.
  final DateTime? expiresAt;
}
