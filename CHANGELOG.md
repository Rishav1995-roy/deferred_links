## 0.0.2

* Server: when two clicks of the same link score equally on an iOS deferred match, the older click is now used, as documented (the code took the newer one). The matched destination was the same either way.

## 0.0.1

Initial release.

* Flutter plugin: App Link / Universal Link receiving (cold start and stream), short link creation and resolution through your own server, deferred deep link on first launch.
* Android deferred links through the Play Install Referrer API (deterministic).
* iOS deferred links through server-side device-signal matching (best effort, confidence reported) with an optional, off-by-default clipboard token.
* `DeepLinkScope` widget and `DeepLinkRouter` / `DeepLinkPattern` helpers.
* Reference server in `server/` (Dart, shelf, Dockerfile): link creation, landing page, assetlinks.json and apple-app-site-association, fingerprint TTL, match endpoint, analytics counts, in-memory and SQLite stores.
* SwiftPM and CocoaPods support on iOS, AGP 8 namespace on Android.
