/// A short link.
class StoredLink {
  StoredLink({
    required this.id,
    required this.deepLink,
    required this.createdAt,
    this.expiresAt,
    this.data = const {},
    this.title,
    this.description,
    this.imageUrl,
    this.fallbackUrl,
    this.androidStoreUrl,
    this.iosStoreUrl,
  });

  final String id;
  final String deepLink;
  final int createdAt; // epoch ms
  final int? expiresAt; // epoch ms
  final Map<String, String> data;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? fallbackUrl;
  final String? androidStoreUrl;
  final String? iosStoreUrl;

  bool isExpired(int now) => expiresAt != null && now >= expiresAt!;
}

/// Coarse request signals of one click. Raw IPs are never stored, only a
/// salted hash used for equality.
class ClickRecord {
  ClickRecord({
    required this.id,
    required this.linkId,
    required this.platform,
    required this.createdAt,
    required this.expiresAt,
    this.ipHash,
    this.osMajor,
    this.language,
    this.screenWidth,
    this.screenHeight,
    this.timezoneOffsetMinutes,
    this.matchedAt,
  });

  final String id;
  final String linkId;

  /// `ios`, `android` or `other`.
  final String platform;
  final int createdAt;
  final int expiresAt;
  final String? ipHash;
  final int? osMajor;
  final String? language;
  final int? screenWidth;
  final int? screenHeight;
  final int? timezoneOffsetMinutes;
  final int? matchedAt;

  ClickRecord copyWith({
    int? screenWidth,
    int? screenHeight,
    int? timezoneOffsetMinutes,
    String? language,
    int? matchedAt,
  }) =>
      ClickRecord(
        id: id,
        linkId: linkId,
        platform: platform,
        createdAt: createdAt,
        expiresAt: expiresAt,
        ipHash: ipHash,
        osMajor: osMajor,
        language: language ?? this.language,
        screenWidth: screenWidth ?? this.screenWidth,
        screenHeight: screenHeight ?? this.screenHeight,
        timezoneOffsetMinutes:
            timezoneOffsetMinutes ?? this.timezoneOffsetMinutes,
        matchedAt: matchedAt ?? this.matchedAt,
      );
}

/// Aggregate counters for a link. They survive click purging.
class LinkStats {
  const LinkStats({
    this.clicks = 0,
    this.clicksIos = 0,
    this.clicksAndroid = 0,
    this.clicksOther = 0,
    this.opens = 0,
    this.installs = 0,
  });

  final int clicks;
  final int clicksIos;
  final int clicksAndroid;
  final int clicksOther;

  /// Times the installed app resolved the link (App Link opens).
  final int opens;

  /// Deferred matches (Android confirmations + iOS matches).
  final int installs;

  Map<String, Object?> toJson() => {
        'clicks': clicks,
        'clicksByPlatform': {
          'ios': clicksIos,
          'android': clicksAndroid,
          'other': clicksOther,
        },
        'opens': opens,
        'installs': installs,
      };
}

/// Pluggable persistence. Implementations must make [markMatched] atomic so a
/// click can be consumed only once.
abstract class LinkStore {
  Future<void> init();

  /// Returns false when the id already exists.
  Future<bool> createLink(StoredLink link);
  Future<StoredLink?> getLink(String id);

  /// Stores the click and increments the link's counters.
  Future<void> recordClick(ClickRecord click);
  Future<ClickRecord?> getClick(String id);

  /// Adds JS-reported fields to a click that is still open.
  Future<void> updateClickSignals(
    String clickId, {
    int? screenWidth,
    int? screenHeight,
    int? timezoneOffsetMinutes,
    String? language,
  });

  /// Unmatched, unexpired iOS clicks with the same IP hash created at or after
  /// [since].
  Future<List<ClickRecord>> candidateClicks({
    required String ipHash,
    required String platform,
    required int since,
    required int now,
  });

  /// Atomically consumes a click. True when this call consumed it.
  Future<bool> markMatched(String clickId, int now);

  Future<void> incrementOpens(String linkId);
  Future<LinkStats> stats(String linkId);

  /// Deletes expired clicks and expired links. Returns rows removed.
  Future<int> purgeExpired(int now);
  Future<void> close();
}
