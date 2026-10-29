import 'dart:convert';

import 'package:deferred_links_server/deferred_links_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

const iosUa =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1';
const androidUa =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36';
const desktopUa = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/124.0 Safari/537.36';

void main() {
  for (final entry in <String, LinkStore Function()>{
    'MemoryStore': MemoryStore.new,
    'SqliteStore': () => SqliteStore(':memory:'),
  }.entries) {
    group(entry.key, () => _suite(entry.value));
  }
  group('matcher (pure)', _matcherTests);
}

class Harness {
  Harness(this.store, {ServerConfig? config})
      : config = config ??
            ServerConfig(
              baseUrl: Uri.parse('https://go.example.com'),
              apiKeys: ['secret'],
              androidPackage: 'com.example.app',
              androidSha256: ['AA:BB'],
              iosAppIds: ['TEAM123.com.example.app'],
              androidStoreUrl: 'https://play.google.com/store/apps/details?id=com.example.app',
              iosStoreUrl: 'https://apps.apple.com/app/id123',
              trustProxy: true,
              ipHashSalt: 'test-salt',
              clipboardTokens: true,
            ) {
    app = DeferredLinksServer(this.config, store, clock: () => now);
    handler = app.handler;
  }

  final LinkStore store;
  final ServerConfig config;
  late final DeferredLinksServer app;
  late final Handler handler;
  int now = 1700000000000;

  Future<Response> send(
    String method,
    String path, {
    Object? json,
    String? ua,
    String ip = '203.0.113.7',
    bool auth = false,
    Map<String, String> headers = const {},
  }) =>
      Future.value(handler(Request(
        method,
        Uri.parse('https://go.example.com$path'),
        body: json == null ? null : jsonEncode(json),
        headers: {
          'x-forwarded-for': ip,
          if (ua != null) 'user-agent': ua,
          if (auth) 'authorization': 'Bearer secret',
          if (json != null) 'content-type': 'application/json',
          ...headers,
        },
      )));

  Future<Map<String, Object?>> body(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, Object?>;

  Future<String> createLink({Map<String, Object?> extra = const {}}) async {
    final r = await send('POST', '/v1/links',
        json: {'deepLink': 'https://go.example.com/product/42', ...extra}, auth: true);
    expect(r.statusCode, 201);
    return (await body(r))['id']! as String;
  }

  /// Simulates the landing page JS reporting its signals for a click.
  Future<String> iosClick(String linkId, {String ip = '203.0.113.7', Map<String, Object?>? fp, String lang = 'en-US'}) async {
    final r = await send('GET', '/$linkId',
        ua: iosUa, ip: ip, headers: {'accept-language': '$lang,fr;q=0.8'});
    expect(r.statusCode, 200);
    final html = await r.readAsString();
    final id = RegExp(r"encodeURIComponent\(d\.click\)").hasMatch(html)
        ? RegExp(r'"click":"([A-Za-z0-9_-]+)"').firstMatch(html)!.group(1)!
        : throw StateError('no click id in page');
    if (fp != null) {
      final res = await send('POST', '/c/$id/fp', json: fp, ip: ip);
      expect(res.statusCode, 204);
    }
    return id;
  }

  Map<String, Object?> deviceSignals({int w = 390, int h = 844, int tz = 330, String lang = 'en-US'}) => {
        'platform': 'ios',
        'osVersion': '17.4',
        'screenWidth': w,
        'screenHeight': h,
        'language': lang,
        'timezoneOffsetMinutes': tz,
      };

  Map<String, Object?> fp({int w = 390, int h = 844, int tz = 330}) =>
      {'screenWidth': w, 'screenHeight': h, 'timezoneOffsetMinutes': tz, 'language': 'en-US'};
}

void _suite(LinkStore Function() make) {
  late Harness h;
  setUp(() async {
    final store = make();
    await store.init();
    h = Harness(store);
  });
  tearDown(() => h.store.close());

  test('CORE-1 create + serve: short link, well-known files, auth', () async {
    expect((await h.send('POST', '/v1/links', json: {'deepLink': 'https://x.test/a'})).statusCode, 401);
    final id = await h.createLink(extra: {'data': {'promo': 'SPRING'}, 'alias': 'spring-sale'});
    expect(id, 'spring-sale');
    expect((await h.send('POST', '/v1/links',
            json: {'deepLink': 'https://x.test/a', 'alias': 'spring-sale'}, auth: true))
        .statusCode, 409);
    expect((await h.send('POST', '/v1/links',
            json: {'deepLink': 'javascript:alert(1)'}, auth: true))
        .statusCode, 400);

    final al = jsonDecode(await (await h.send('GET', '/.well-known/assetlinks.json')).readAsString()) as List;
    expect((al.first as Map)['target'], containsPair('package_name', 'com.example.app'));
    final aasa = await h.body(await h.send('GET', '/.well-known/apple-app-site-association'));
    expect(jsonEncode(aasa), contains('TEAM123.com.example.app'));

    final resolved = await h.body(await h.send('GET', '/v1/resolve/$id'));
    expect(resolved['deepLink'], 'https://go.example.com/product/42');
    expect(resolved['data'], {'promo': 'SPRING'});
    expect((await h.send('GET', '/v1/resolve/nope1234')).statusCode, 404);
  });

  test('CORE-2 android: store redirect carries click id and link in the Play referrer', () async {
    final id = await h.createLink();
    final r = await h.send('GET', '/$id', ua: androidUa);
    expect(r.statusCode, 302);
    final loc = Uri.parse(r.headers['location']!);
    expect(loc.host, 'play.google.com');
    expect(loc.queryParameters['id'], 'com.example.app');
    final referrer = Uri.splitQueryString(loc.queryParameters['referrer']!);
    expect(referrer['dl_click'], hasLength(12));
    expect(referrer['dl_link'], 'https://go.example.com/product/42');

    // The app confirms the install with the click id; retry is idempotent.
    final click = referrer['dl_click']!;
    final a = await h.send('POST', '/v1/clicks/$click/install');
    expect(a.statusCode, 200);
    expect((await h.body(a))['deepLink'], 'https://go.example.com/product/42');
    expect((await h.send('POST', '/v1/clicks/$click/install')).statusCode, 200);
    final stats = await h.body(await h.send('GET', '/v1/links/$id/stats', auth: true));
    expect(stats['installs'], 1); // counted once
  });

  test('CORE-3 ios: matching click + device signals -> high confidence, single use', () async {
    final id = await h.createLink(extra: {'data': {'promo': 'X'}});
    await h.iosClick(id, fp: h.fp());
    h.now += 5 * 60 * 1000;
    final r = await h.body(await h.send('POST', '/v1/match', json: {'signals': h.deviceSignals()}));
    expect(r['matched'], true);
    expect(r['method'], 'fingerprint');
    expect(r['confidence'], 'high');
    expect((r['link']! as Map)['deepLink'], 'https://go.example.com/product/42');
    // A second install on the same network must not receive the same link.
    final again = await h.body(await h.send('POST', '/v1/match', json: {'signals': h.deviceSignals()}));
    expect(again['matched'], false);
  });

  test('CORE-3 ios honesty: different IP (Wi-Fi vs cellular, VPN) -> no match', () async {
    final id = await h.createLink();
    await h.iosClick(id, fp: h.fp());
    final r = await h.body(await h.send('POST', '/v1/match',
        json: {'signals': h.deviceSignals()}, ip: '198.51.100.9'));
    expect(r['matched'], false);
  });

  test('CORE-3 ios: outside the match window -> no match', () async {
    final id = await h.createLink();
    await h.iosClick(id, fp: h.fp());
    h.now += 31 * 60 * 1000;
    expect((await h.body(await h.send('POST', '/v1/match', json: {'signals': h.deviceSignals()})))['matched'], false);
  });

  test('CORE-3 ios: shared NAT, different devices -> screen size picks the right click', () async {
    final a = await h.createLink(extra: {'alias': 'link-aaaa'});
    final b = await h.createLink(extra: {'alias': 'link-bbbb'});
    await h.iosClick(a, fp: h.fp(w: 390, h: 844));
    await h.iosClick(b, fp: h.fp(w: 430, h: 932));
    final r = await h.body(await h.send('POST', '/v1/match',
        json: {'signals': h.deviceSignals(w: 430, h: 932)}));
    expect(r['matched'], true);
    expect(((r['link']! as Map)['id']), 'link-bbbb');
  });

  test('CORE-3 ios: shared NAT, identical devices, different links -> refuses to guess', () async {
    final a = await h.createLink(extra: {'alias': 'link-aaaa'});
    final b = await h.createLink(extra: {'alias': 'link-bbbb'});
    await h.iosClick(a, fp: h.fp());
    await h.iosClick(b, fp: h.fp());
    final r = await h.body(await h.send('POST', '/v1/match', json: {'signals': h.deviceSignals()}));
    expect(r['matched'], false);
  });

  test('CORE-3 ios: no JS fingerprint (blocked script) -> low confidence only', () async {
    final id = await h.createLink();
    await h.iosClick(id); // landing page script never reported signals
    final r = await h.body(await h.send('POST', '/v1/match', json: {'signals': h.deviceSignals()}));
    expect(r['matched'], true);
    expect(r['confidence'], 'low');
  });

  test('CORE-3 ios: contradicting time zone rejects the candidate', () async {
    final id = await h.createLink();
    await h.iosClick(id, fp: h.fp(tz: 0));
    final r = await h.body(await h.send('POST', '/v1/match', json: {'signals': h.deviceSignals(tz: 330)}));
    expect(r['matched'], false);
  });

  test('CORE-3 ios clipboard token is exact and works across IPs', () async {
    final id = await h.createLink();
    final click = await h.iosClick(id, fp: h.fp());
    final r = await h.body(await h.send('POST', '/v1/match',
        json: {'signals': h.deviceSignals(), 'clipboard': 'deferredlinks:$click'}, ip: '198.51.100.9'));
    expect(r['matched'], true);
    expect(r['method'], 'clipboard');
    expect(r['confidence'], 'exact');
  });

  test('clipboard token ignored when the server has it disabled', () async {
    final cfg = ServerConfig(
      baseUrl: Uri.parse('https://go.example.com'),
      apiKeys: ['secret'],
      trustProxy: true,
      ipHashSalt: 's',
    );
    final store = make();
    await store.init();
    final h2 = Harness(store, config: cfg);
    final id = await h2.createLink();
    final r = await h2.send('GET', '/$id', ua: iosUa);
    final click = RegExp(r'"click":"([A-Za-z0-9_-]+)"').firstMatch(await r.readAsString())!.group(1)!;
    final m = await h2.body(await h2.send('POST', '/v1/match',
        json: {'signals': h2.deviceSignals(), 'clipboard': 'deferredlinks:$click'}, ip: '198.51.100.9'));
    expect(m['matched'], false);
    await store.close();
  });

  test('analytics counters, purge of expired clicks keeps counts', () async {
    final id = await h.createLink();
    await h.send('GET', '/$id', ua: androidUa);
    await h.send('GET', '/$id', ua: androidUa, ip: '203.0.113.8');
    await h.iosClick(id);
    await h.send('GET', '/$id', ua: desktopUa);
    await h.send('GET', '/v1/resolve/$id');
    var s = await h.body(await h.send('GET', '/v1/links/$id/stats', auth: true));
    expect(s['clicks'], 4);
    expect(s['clicksByPlatform'], {'ios': 1, 'android': 2, 'other': 1});
    expect(s['opens'], 1);

    h.now += 8 * 24 * 3600 * 1000; // past every click TTL
    expect(await h.app.purge(), greaterThan(0));
    s = await h.body(await h.send('GET', '/v1/links/$id/stats', auth: true));
    expect(s['clicks'], 4);
    // fingerprints are gone
    expect((await h.body(await h.send('POST', '/v1/match', json: {'signals': h.deviceSignals()})))['matched'], false);
  });

  test('link previews (bots) are not counted as clicks and get OG tags', () async {
    final id = await h.createLink(extra: {'title': 'Spring <sale>', 'imageUrl': 'https://img.test/a.png'});
    final r = await h.send('GET', '/$id', ua: 'facebookexternalhit/1.1');
    final html = await r.readAsString();
    expect(html, contains('og:title" content="Spring &lt;sale&gt;"'));
    expect(html, isNot(contains('<sale>')));
    final s = await h.body(await h.send('GET', '/v1/links/$id/stats', auth: true));
    expect(s['clicks'], 0);
  });

  test('expiry: expired links 404 and cannot be resolved', () async {
    final id = await h.createLink(extra: {'ttlSeconds': 60});
    h.now += 61000;
    expect((await h.send('GET', '/$id', ua: iosUa)).statusCode, 404);
    expect((await h.send('GET', '/v1/resolve/$id')).statusCode, 404);
  });

  test('desktop is redirected to the link fallback', () async {
    final id = await h.createLink(extra: {'fallbackUrl': 'https://www.example.com/p/42'});
    final r = await h.send('GET', '/$id', ua: desktopUa);
    expect(r.statusCode, 302);
    expect(r.headers['location'], 'https://www.example.com/p/42');
  });

  test('stored click holds a hash, never the raw IP', () async {
    final id = await h.createLink();
    final clickId = await h.iosClick(id);
    final click = await h.store.getClick(clickId);
    expect(click!.ipHash, isNot(contains('203.0.113.7')));
    expect(click.ipHash, hasLength(32));
  });
}

void _matcherTests() {
  ClickRecord click({int? w, int? h, int? tz, String? lang, String link = 'a', int at = 0}) =>
      ClickRecord(
        id: 'c$at$link',
        linkId: link,
        platform: 'ios',
        createdAt: at,
        expiresAt: 1 << 40,
        ipHash: 'x',
        screenWidth: w,
        screenHeight: h,
        timezoneOffsetMinutes: tz,
        language: lang,
        osMajor: 17,
      );

  test('screen orientation is ignored', () {
    final s = DeviceSignals(screenWidth: 844, screenHeight: 390, timezoneOffsetMinutes: 0, language: 'en', osVersion: '17.1');
    expect(scoreCandidate(click(w: 390, h: 844, tz: 0, lang: 'en-GB'), s), closeTo(1.0, 1e-9));
  });

  test('os mismatch does not penalise (Safari freezes its UA version)', () {
    final s = DeviceSignals(screenWidth: 390, screenHeight: 844, timezoneOffsetMinutes: 0, language: 'en', osVersion: '26.0');
    expect(scoreCandidate(click(w: 390, h: 844, tz: 0, lang: 'en'), s), closeTo(0.95, 1e-9));
  });

  test('same-link duplicates are not ambiguous', () {
    final s = DeviceSignals(screenWidth: 390, screenHeight: 844, timezoneOffsetMinutes: 0);
    final m = pickMatch([click(w: 390, h: 844, tz: 0, at: 1), click(w: 390, h: 844, tz: 0, at: 2)], s);
    expect(m, isNotNull);
    expect(m!.click.createdAt, 2);
  });

  test('confidence tiers', () {
    expect(confidenceFor(1.0), Confidence.high);
    expect(confidenceFor(0.85), Confidence.medium);
    expect(confidenceFor(0.6), Confidence.low);
  });
}
