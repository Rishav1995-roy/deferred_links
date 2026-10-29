# deferred_links

[![pub version](https://img.shields.io/pub/v/deferred_links.svg)](https://pub.dev/packages/deferred_links)
[![pub points](https://img.shields.io/pub/points/deferred_links)](https://pub.dev/packages/deferred_links/score)
[![likes](https://img.shields.io/pub/likes/deferred_links)](https://pub.dev/packages/deferred_links)
[![popularity](https://img.shields.io/pub/popularity/deferred_links)](https://pub.dev/packages/deferred_links)
[![CI](https://github.com/Rishav1995-roy/deferred_links/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Rishav1995-roy/deferred_links/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platforms](https://img.shields.io/badge/platforms-android%20%7C%20ios-informational)

An open-source, self-hostable replacement for Firebase Dynamic Links (shut down on 2025-08-25): short links, App Links / Universal Links, and **deferred deep links** (open the right screen after the user installs), with a small server you run yourself.

![Demo](https://raw.githubusercontent.com/Rishav1995-roy/deferred_links/main/doc/demo.gif)

*The GIF is an illustrated walkthrough of the example app flow, drawn by a test script. It is not a device capture.*

<p>
  <img src="https://raw.githubusercontent.com/Rishav1995-roy/deferred_links/main/doc/screenshot_light.png" width="260" alt="Light mode">
  <img src="https://raw.githubusercontent.com/Rishav1995-roy/deferred_links/main/doc/screenshot_dark.png" width="260" alt="Dark mode">
</p>

The repository has two parts:

1. **The Flutter plugin** (this package): receives links (cold start and while running), resolves short links, creates short links, and recovers the deferred link on first launch.
2. **`server/`**: a reference server in Dart (shelf) with a Dockerfile: short links, redirect and landing page, `assetlinks.json` and `apple-app-site-association` hosting, fingerprint storage with a TTL, a match endpoint and analytics counts. See [server/README.md](https://github.com/Rishav1995-roy/deferred_links/blob/main/server/README.md).

## How reliable is deferred matching? Read this first

| | Android | iOS |
|---|---|---|
| Mechanism | Google Play **Install Referrer**: the click puts the link id into the Play Store URL and Play hands it back to the app after install | The click records the visitor's network address (as a salted hash) and coarse device settings; the app asks the server to match on first launch |
| Reliability | **Deterministic** when the app was installed from Google Play after tapping the link | **Best effort. It is a guess, not a guarantee.** |
| Fails when | Sideloaded or non-Play installs, Play Store not present, referrer older than 90 days | The IP address differs between the click and the first launch (Wi-Fi to cellular, VPN, iCloud Private Relay, dual-stack IPv4 vs IPv6), the install takes longer than the match window (30 min by default), or two different people behind one network click different links with identical devices |
| Confidence | always `exact` | `high`, `medium` or `low`; the server refuses to answer when two different links are equally plausible |

Things worth knowing about iOS:

* Apple provides **no install referrer** and no supported way to pass data through the App Store. Every iOS solution, including the retired Firebase Dynamic Links, relies on matching signals or the clipboard.
* This package never reads the clipboard by default. The opt-in clipboard token (`useClipboard: true` plus `CLIPBOARD_TOKENS=true` on the server) is deterministic but needs the user to tap "Get the app" on the landing page and shows the iOS paste prompt.
* A match returned with `low` confidence is dropped by default (`minConfidence: MatchConfidence.medium`). Navigate automatically only on `high` or `exact`; offer the link otherwise.
* Expect real-world iOS match rates to depend heavily on your audience's network behaviour. We make no accuracy claim and you should measure it on your own traffic (the server's `installs` counter against your install count is a good start).
* If the app always has to land at the right place for iOS (for example paid acquisition attribution), use a deterministic path such as a referral code typed or pasted by the user, in addition to this package.

## Why this package

| | `firebase_dynamic_links` | `stack_deferred_link`, `dynalinks`, `flinku_sdk`, `urlynk_flutter`, `vela_links` | `app_links` + `play_install_referrer` | **`deferred_links`** |
|---|---|---|---|---|
| Status | [Discontinued](https://pub.dev/packages/firebase_dynamic_links), the backend shut down 2025-08-25 | Maintained, but thin clients for a paid or hosted service | Maintained building blocks | Maintained here |
| You own the server and the data | No | No (hosted service) | n/a, no server | **Yes, MIT server with Docker** |
| Short links | Was supported | Via the vendor | No | **Yes** |
| Landing page, store fallback, `assetlinks.json` and AASA hosting | Was supported | Via the vendor | No | **Yes, from config** |
| Android deferred link | Was supported | Varies | Raw referrer string only, you parse and route it | **Parsed, confirmed against the server, tested** |
| iOS deferred link | Was supported | Varies | No | **Best effort with honest confidence** |
| Analytics counts | Was supported | Via the vendor | No | **Clicks, opens, installs per link** |
| One widget for launch + stream + deferred | n/a | Varies | You write it | **`DeepLinkScope`** |

`app_links` and `play_install_referrer` are good packages; if you only need to receive links or read the referrer, use them. This package exists because there was no open-source, self-hostable server plus client pair after the shutdown. A search of GitHub and pub.dev at the time of writing found only tiny repositories and hosted-service clients (see the repository history for the search notes).

## Features

* App Links / Universal Links: initial link and stream, handled natively (no extra dependency)
* Short link resolution through your server (data attached to the link is returned with it)
* Short link creation (`createShortLink`) with custom data, social preview tags, alias, expiry
* Deferred deep link on first launch with an honest `DeferredStatus` and `MatchConfidence`
* `DeepLinkScope` widget, `DeepLinkRouter` and `DeepLinkPattern` (`/product/:id`)
* Plain data models, injectable HTTP client and platform, no global state beyond one optional singleton
* Server: SQLite or in-memory store behind one interface, link expiry, rate limiting, hashed IPs, CSP-protected landing page
* Android: AGP 8 namespace, `minSdk 21`. iOS: **Swift Package Manager and CocoaPods** (CocoaPods trunk becomes read-only on 2026-12-02)

## Platform support

| Android | iOS | Web | macOS | Windows | Linux |
|---|---|---|---|---|---|
| Yes | Yes | No | No | No | No |

## Installation

```sh
flutter pub add deferred_links
```

### 1. Run the server

```sh
cd server
docker build -t deferred-links-server .
docker run -p 8080:8080 -v dl-data:/data \
  -e BASE_URL=https://links.example.com \
  -e API_KEYS=change-me \
  -e ANDROID_PACKAGE=com.example.app \
  -e ANDROID_SHA256=AA:BB:... \
  -e IOS_APP_IDS=TEAMID.com.example.app \
  -e IOS_STORE_URL=https://apps.apple.com/app/id123456789 \
  deferred-links-server
```

Put it behind HTTPS on your link domain (App Links and Universal Links require it). Full configuration: [server/README.md](https://github.com/Rishav1995-roy/deferred_links/blob/main/server/README.md).

### 2. Android

Add the intent filter to the launcher activity in `AndroidManifest.xml`, and turn off Flutter's own deep-link handling so it does not push the URL as a route:

```xml
<intent-filter android:autoVerify="true">
  <action android:name="android.intent.action.VIEW"/>
  <category android:name="android.intent.category.DEFAULT"/>
  <category android:name="android.intent.category.BROWSABLE"/>
  <data android:scheme="https" android:host="links.example.com"/>
</intent-filter>
<meta-data android:name="flutter_deeplinking_enabled" android:value="false"/>
```

Also add `<uses-permission android:name="android.permission.INTERNET"/>` if you do not have it. The server serves `/.well-known/assetlinks.json` from `ANDROID_PACKAGE` and `ANDROID_SHA256`.

### 3. iOS

Add the **Associated Domains** capability with `applinks:links.example.com`, and disable Flutter's own handling in `Info.plist`:

```xml
<key>FlutterDeepLinkingEnabled</key>
<false/>
```

The server serves `/.well-known/apple-app-site-association` from `IOS_APP_IDS`. The plugin handles links through both the app delegate and the UIScene lifecycle (new Flutter templates). The scene path is registered at runtime so the plugin still builds on older Flutter; it has been compiled but not exercised on a device.

## Quick start

```dart
import 'package:deferred_links/deferred_links.dart';

void main() {
  DeferredLinks.instance.configure(
    DeferredLinksConfig(serverUrl: Uri.parse('https://links.example.com')),
  );
  runApp(const MyApp());
}

// Above your navigator:
DeepLinkScope(
  onLink: (link) {
    if (link.isDeferred && !(link.confidence!.atLeast(MatchConfidence.high))) {
      // iOS guess: confirm with the user instead of jumping.
      return;
    }
    router.route(link);
  },
  child: MaterialApp(...),
);

final router = DeepLinkRouter({
  '/product/:id': (link, p) => openProduct(p['id']!),
  '/invite/:code': (link, p) => openInvite(p['code']!),
});
```

Without the widget:

```dart
final first = await DeferredLinks.instance.getInitialLink();      // cold start
DeferredLinks.instance.linkStream.listen(handle);                  // while running
final result = await DeferredLinks.instance.checkDeferredLink();   // first launch only
switch (result.status) {
  case DeferredStatus.matched:      handle(result.link!);
  case DeferredStatus.noMatch:      break; // organic install or no match
  case DeferredStatus.notFirstLaunch: break;
  case DeferredStatus.error:        break; // retried on next launch
}
```

Create a link:

```dart
final link = await DeferredLinks.instance.createShortLink(ShortLinkRequest(
  deepLink: Uri.parse('https://links.example.com/product/42'),
  data: {'promo': 'SPRING'},
  title: 'Linen chair',
  ttl: const Duration(days: 30),
));
share(link.shortUrl);
```

Prefer creating links from your own backend with the server API (`POST /v1/links`). An API key shipped inside an app can be extracted.

## API

| Member | Description |
|---|---|
| `DeferredLinks.instance` | Shared instance. `DeferredLinks(platform:, targetPlatform:, clipboardReader:)` for tests |
| `configure(DeferredLinksConfig)` | Server URL, key, options |
| `getInitialLink()` | Launch link, stable across calls |
| `linkStream` | Links while running, short links resolved |
| `checkDeferredLink()` | First-launch check, returns `DeferredLinkResult` |
| `createShortLink(ShortLinkRequest)` | Creates a link on your server |

| `DeferredLinksConfig` | Default | Description |
|---|---|---|
| `serverUrl` | required | Your server |
| `apiKey` | `null` | Bearer key for creating links in-app (prefer your backend) |
| `shortLinkHosts` | server host | Hosts whose `/<id>` paths are short links to resolve |
| `useClipboard` | `false` | iOS only: read a `deferredlinks:` token from the clipboard (paste prompt) |
| `minConfidence` | `medium` | Weaker deferred matches are reported as `noMatch` |
| `requestTimeout` | 10 s | Per request |
| `httpClient` | internal | Inject a client |

| Model | Fields |
|---|---|
| `DeepLink` | `uri`, `data`, `linkId`, `source`, `method`, `confidence`, `isDeferred`, `path`, `queryParameters` |
| `DeferredLinkResult` | `status`, `link`, `error` |
| `MatchConfidence` | `low`, `medium`, `high`, `exact`, `atLeast()` |
| `DeferredMethod` | `installReferrer`, `clipboard`, `fingerprint` |
| `ShortLinkRequest` | `deepLink`, `data`, `title`, `description`, `imageUrl`, `fallbackUrl`, `alias`, `ttl`, store URL overrides |
| `DeepLinkScope` | `onLink`, `child`, `links`, `checkDeferred`, `onDeferredResult` |

## Privacy

What the package and the reference server collect, and for how long:

| Data | Where | Purpose | Retention |
|---|---|---|---|
| Salted HMAC of the visitor's IP (IPv6 reduced to /64). The raw IP is never stored | Server, per click | iOS match | iOS click records 24 h (`CLICK_TTL_HOURS`), Android click records 7 days (`ANDROID_CLICK_TTL_DAYS`), then deleted; a purge runs every 10 minutes |
| Screen size, time zone offset, primary language, iOS major version | Server, per iOS click, reported by the landing page script | iOS match | Same as above |
| Device signals (OS version, model, screen size in points, language, time zone offset) | Sent from the app to the server on the first launch of an iOS app, only to your server | iOS match | Not stored, used for the single match request |
| Per-link counters (clicks by platform, opens, installs) | Server | Analytics | Kept with the link, contain no personal data |
| Clipboard | Read only when `useClipboard` is true, only text starting with `deferredlinks:` is sent | Deterministic iOS match | Not stored |
| Link previews (Facebook, Slack and similar bots) | Not counted as clicks | | |

There is no advertising identifier, no cross-app tracking and no third-party service. `PrivacyInfo.xcprivacy` ships with the plugin (UserDefaults, reason `CA92.1`, for the once-per-install flag). You are the data controller for your server: link to your privacy policy with `PRIVACY_URL` and describe the IP-hash matching in it. The landing page already tells visitors what it keeps. Whether this needs consent in your jurisdiction (for example under GDPR) is a decision for you and your counsel; the opt-in clipboard path and the ability to disable the fingerprint (do not run `/v1/match`) are there for strict setups.

## Coming from `firebase_dynamic_links`

| Firebase Dynamic Links | `deferred_links` |
|---|---|
| `FirebaseDynamicLinks.instance.getInitialLink()` returned `PendingDynamicLinkData` | `DeferredLinks.instance.getInitialLink()` returns a `DeepLink` (`link.uri` replaces `data.link`) |
| `onLink.listen(...)` | `DeferredLinks.instance.linkStream.listen(...)` |
| Deferred link arrived through `getInitialLink()` after install | Call `checkDeferredLink()` once at startup; `DeepLinkScope` does both |
| `buildLink(DynamicLinkParameters(uriPrefix, link, androidParameters, iosParameters))` | `createShortLink(ShortLinkRequest(deepLink: ...))`; store URLs and package ids are in the server config |
| `buildShortLink` | The server always returns a short link (`ShortLink.shortUrl`) |
| Social meta tags (`socialMetaTagParameters`) | `title`, `description`, `imageUrl` on `ShortLinkRequest` |
| `utm` parameters, `link.queryParameters` | Put them in the deep link query or in `data` |
| Console analytics | `GET /v1/links/<id>/stats` |
| `uriPrefix` (`example.page.link`) | Your own domain pointing at the server, `shortLinkHosts` |

Steps: deploy the server, point your link domain at it, move the `assetlinks.json` and AASA entries to the server config, add the manifest and entitlement entries above, replace the Firebase calls, and re-create important links (existing `page.link` URLs stop working with the service). Old `page.link` URLs cannot be migrated.

## Customization

```dart
DeferredLinksConfig(
  serverUrl: Uri.parse('https://links.example.com'),
  shortLinkHosts: ['links.example.com', 'go.example.com'],
  minConfidence: MatchConfidence.high,     // stricter iOS policy
  useClipboard: true,                      // opt-in, shows the paste prompt
  requestTimeout: const Duration(seconds: 5),
  httpClient: myProxyAwareClient,
);
```

`DeepLinkScope(links: myInstance, checkDeferred: false, onDeferredResult: log, ...)` lets you run the check yourself, log outcomes and use a custom `DeferredLinks` instance.

## FAQ

**Does it work without my server?** Receiving plain App Links works. On Android the deferred link also works without a server if the link was created by the reference server (it embeds the target in the referrer). Short links, analytics and iOS matching need the server.

**Can I use another backend?** Yes. The client needs `POST /v1/links`, `GET /v1/resolve/<id>`, `POST /v1/clicks/<id>/install` and `POST /v1/match`; the formats are in [server/README.md](https://github.com/Rishav1995-roy/deferred_links/blob/main/server/README.md).

**Why not read the clipboard by default?** iOS 16+ shows a paste prompt on every read and users find it alarming. It is opt-in.

**Does `checkDeferredLink` run again after an app update?** No. It runs until a conclusive outcome once per install (Android auto-backup can restore the flag after a reinstall on some devices; exclude `dev.rishav.deferred_links` from backup if that matters to you).

**Where do I report a mismatch?** Open an issue with the confidence and method you saw.

## What is verified

* Flutter and server logic, including client and server against each other in-process (iOS and Android flows), are covered by tests.
* The Android and iOS native code compiles (APK and iOS simulator builds). Receiving a link on a real device, and the Play Install Referrer on a real Play install, cannot be tested from CI; use the manual checks in the example's README.

## Contributing

Issues and pull requests are welcome. Run `flutter analyze --fatal-infos` and `flutter test`; for the server `cd server && dart test`.

## License

MIT, see [LICENSE](LICENSE).
