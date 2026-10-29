/// Server settings. [ServerConfig.fromEnv] reads environment variables.
class ServerConfig {
  ServerConfig({
    required this.baseUrl,
    this.apiKeys = const [],
    this.androidPackage,
    this.androidSha256 = const [],
    this.iosAppIds = const [],
    this.iosPaths = const ['/*'],
    this.androidStoreUrl,
    this.iosStoreUrl,
    this.fallbackUrl,
    this.matchWindow = const Duration(minutes: 30),
    this.iosClickTtl = const Duration(hours: 24),
    this.androidClickTtl = const Duration(days: 7),
    this.trustProxy = false,
    this.ipHashSalt,
    this.clipboardTokens = false,
    this.defaultLinkTtl,
    this.minMatchScore = 0.6,
    this.rateLimitPerMinute = 60,
    this.privacyUrl,
  });

  factory ServerConfig.fromEnv(Map<String, String> env) {
    List<String> list(String? v) => (v ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    int? intOf(String? v) => v == null ? null : int.tryParse(v);
    final days = intOf(env['DEFAULT_LINK_TTL_DAYS']);
    final pkg = env['ANDROID_PACKAGE'];
    return ServerConfig(
      baseUrl: Uri.parse(env['BASE_URL'] ?? 'http://localhost:8080'),
      apiKeys: list(env['API_KEYS']),
      androidPackage: pkg,
      androidSha256: list(env['ANDROID_SHA256']),
      iosAppIds: list(env['IOS_APP_IDS']),
      iosPaths: list(env['IOS_PATHS']).isEmpty ? const ['/*'] : list(env['IOS_PATHS']),
      androidStoreUrl: env['ANDROID_STORE_URL'] ??
          (pkg == null ? null : 'https://play.google.com/store/apps/details?id=$pkg'),
      iosStoreUrl: env['IOS_STORE_URL'],
      fallbackUrl: env['FALLBACK_URL'],
      matchWindow: Duration(minutes: intOf(env['MATCH_WINDOW_MINUTES']) ?? 30),
      iosClickTtl: Duration(hours: intOf(env['CLICK_TTL_HOURS']) ?? 24),
      androidClickTtl: Duration(days: intOf(env['ANDROID_CLICK_TTL_DAYS']) ?? 7),
      trustProxy: env['TRUST_PROXY'] == 'true',
      ipHashSalt: env['IP_HASH_SALT'],
      clipboardTokens: env['CLIPBOARD_TOKENS'] == 'true',
      defaultLinkTtl: days == null ? null : Duration(days: days),
      privacyUrl: env['PRIVACY_URL'],
    );
  }

  /// Public origin that serves short links, e.g. `https://links.example.com`.
  final Uri baseUrl;

  /// Bearer keys allowed to create links and read stats. Empty disables both.
  final List<String> apiKeys;

  final String? androidPackage;
  final List<String> androidSha256;
  final List<String> iosAppIds;
  final List<String> iosPaths;
  final String? androidStoreUrl;
  final String? iosStoreUrl;

  /// Desktop and unknown-device destination.
  final String? fallbackUrl;

  /// How long after a click an iOS first launch can still be matched.
  final Duration matchWindow;

  /// Retention of iOS click fingerprints.
  final Duration iosClickTtl;

  /// Retention of Android click ids (the Play referrer itself carries the link
  /// as a fallback after this).
  final Duration androidClickTtl;

  /// Read the client IP from `X-Forwarded-For` (only behind a proxy you trust).
  final bool trustProxy;

  /// Secret salt for IP hashing. Random per process when omitted.
  final String? ipHashSalt;

  /// Make the iOS landing page copy a `deferredlinks:<id>` token to the
  /// clipboard on the "Get the app" tap.
  final bool clipboardTokens;

  final Duration? defaultLinkTtl;
  final double minMatchScore;
  final int rateLimitPerMinute;

  /// Linked from the landing page privacy line.
  final String? privacyUrl;
}
