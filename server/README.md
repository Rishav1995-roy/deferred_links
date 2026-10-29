# deferred_links server

Reference server for the [`deferred_links`](https://pub.dev/packages/deferred_links) Flutter package. Dart, `shelf`, one binary, SQLite or in-memory storage.

## Run

```sh
docker build -t deferred-links-server .
docker run -p 8080:8080 -v dl-data:/data -e BASE_URL=https://links.example.com -e API_KEYS=change-me deferred-links-server
```

or `dart run bin/server.dart` (needs `libsqlite3`). `STORE=memory` runs without a database for trials.

## Configuration (environment)

| Variable | Default | Meaning |
|---|---|---|
| `PORT` | 8080 | Listen port |
| `BASE_URL` | `http://localhost:8080` | Public origin of short links |
| `API_KEYS` | empty | Comma separated bearer keys for link creation and stats. Empty disables both |
| `STORE` / `DB_PATH` | `sqlite` / `deferred_links.db` | `memory` or `sqlite` |
| `ANDROID_PACKAGE`, `ANDROID_SHA256` | | Served as `/.well-known/assetlinks.json` (SHA-256 cert fingerprints, comma separated; include the Play app-signing key) |
| `IOS_APP_IDS`, `IOS_PATHS` | `/*` | Served as `/.well-known/apple-app-site-association` (`TEAMID.bundle.id`) |
| `ANDROID_STORE_URL` | Play URL from the package | Redirect target for Android |
| `IOS_STORE_URL` | | Button target on the iOS landing page |
| `FALLBACK_URL` | | Desktop destination |
| `MATCH_WINDOW_MINUTES` | 30 | How long after a click an iOS first launch can match |
| `CLICK_TTL_HOURS` / `ANDROID_CLICK_TTL_DAYS` | 24 / 7 | Retention of click records |
| `DEFAULT_LINK_TTL_DAYS` | none | Default link expiry |
| `TRUST_PROXY` | false | Read the client IP from `X-Forwarded-For`. Only enable behind a proxy you control, otherwise clients can spoof it |
| `IP_HASH_SALT` | random per start | Salt for the IP hash. Set it to survive restarts and multiple instances |
| `CLIPBOARD_TOKENS` | false | Landing page copies a `deferredlinks:<id>` token on "Get the app" |
| `PRIVACY_URL` | | Linked from the landing page |

SQLite is a single-writer store: run one instance, or implement `LinkStore` for Postgres/Redis (the interface is `lib/src/store.dart`, about 10 methods).

## HTTP API

| Endpoint | Auth | Description |
|---|---|---|
| `POST /v1/links` | key | `{deepLink, data?, title?, description?, imageUrl?, fallbackUrl?, alias?, ttlSeconds?, androidStoreUrl?, iosStoreUrl?}` returns `201 {id, shortUrl, deepLink, expiresAt?}` |
| `GET /v1/links/<id>/stats` | key | `{clicks, clicksByPlatform{ios,android,other}, opens, installs}` |
| `GET /v1/resolve/<id>` | none | `{id, deepLink, data}`; counts an open; 404 if unknown or expired |
| `POST /v1/clicks/<id>/install` | none | Android confirmation, returns the link; idempotent |
| `POST /v1/match` | none | `{signals{platform,osVersion,screenWidth,screenHeight,language,timezoneOffsetMinutes}, clipboard?}` returns `{matched, method, confidence, score, link}` |
| `GET /<id>` | none | Short link: Android 302 to the Play Store with `referrer=dl_click=<id>&dl_link=<url>`, iOS landing page, desktop fallback. Link-preview bots get Open Graph tags and are not counted |
| `POST /c/<clickId>/fp` | none | Landing page script reports screen size, time zone, language |
| `GET /.well-known/assetlinks.json`, `GET /.well-known/apple-app-site-association` | none | Verification files from config |

Rate limits (60 per minute per hashed IP) apply to the public endpoints. Deep links with `javascript:`, `data:`, `file:` schemes are rejected; fallback, image and store URLs must be http(s).

## iOS matching rules

Same hashed IP (required) within the window; consistent screen size and time zone when both sides reported them (a contradiction rejects the candidate); score IP 0.50, screen 0.20, time zone 0.15, language 0.10, iOS major 0.05. Confidence: `>= 0.9` high, `>= 0.75` medium, below that low; minimum 0.6. Two equally plausible candidates for different links return no match. A click is consumed by one match. These rules are covered by `test/server_test.dart`.

## Tests

```sh
dart test
```
