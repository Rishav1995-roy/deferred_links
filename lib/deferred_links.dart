/// Self-hostable replacement for Firebase Dynamic Links: App Links, short
/// links and deferred deep links for Flutter.
library;

export 'src/client.dart'
    show DeferredLinksClient, DeferredLinksException, MatchResponse;
export 'src/config.dart' show DeferredLinksConfig;
export 'src/deep_link_pattern.dart'
    show DeepLinkHandler, DeepLinkPattern, DeepLinkRouter;
export 'src/deep_link_scope.dart' show DeepLinkScope;
export 'src/deferred_links_base.dart' show DeferredLinks, clipboardTokenPrefix;
export 'src/install_referrer.dart' show ParsedReferrer, parseInstallReferrer;
export 'src/models.dart';
export 'src/platform.dart'
    show
        DeferredLinksPlatform,
        InstallReferrerResult,
        MethodChannelDeferredLinksPlatform;
