# deferred_links example

A small app showing `DeepLinkScope`, `DeepLinkRouter` (opens `/product/:id` and `/invite/:code`), short link creation and a settings screen (theme, server URL, clipboard matching, minimum confidence).

```sh
# terminal 1: server (from ../server)
STORE=memory API_KEYS=k BASE_URL=http://localhost:8080 dart run bin/server.dart
# terminal 2
flutter run
```

The Android emulator reaches the host as `10.0.2.2:8080` (the default in Settings).

## Manual checks on a device (cannot be run in CI)

1. **Cold start link (Android):** `adb shell am start -a android.intent.action.VIEW -c android.intent.category.BROWSABLE -d "https://links.example.com/product/42" dev.rishav.deferred_links_example/.MainActivity` with the app closed: the product screen opens.
2. **Warm link:** run it again with the app open: the product screen is pushed and the link appears in the list.
3. **Android deferred link:** create a short link, upload a build to a Play internal testing track, uninstall the app, open the short link on the phone, install from Play, open: the first launch lands on the product screen, listed as "Deferred via installReferrer, confidence exact". For a quick test without Play: `adb shell am broadcast -a com.android.vending.INSTALL_REFERRER -p dev.rishav.deferred_links_example --es referrer "dl_link=https%3A%2F%2Flinks.example.com%2Fproduct%2F42"` only reaches apps that read the legacy broadcast, so use Play for the real check.
4. **iOS deferred link:** open a short link in Safari on the device, install through TestFlight, open the app on the same network: expect `fingerprint` with `high` or `medium`; switch to cellular between click and launch to see it not match.

The example's Associated Domains entitlement is not included because it needs your team id and domain; add `applinks:<your domain>` in Xcode.
