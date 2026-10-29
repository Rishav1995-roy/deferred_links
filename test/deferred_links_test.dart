import 'dart:convert';

import 'package:deferred_links/deferred_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support.dart';

DeferredLinksConfig cfg(http.Client client,
        {bool clipboard = false,
        MatchConfidence min = MatchConfidence.medium}) =>
    DeferredLinksConfig(
      serverUrl: Uri.parse('https://go.example.com'),
      httpClient: client,
      useClipboard: clipboard,
      minConfidence: min,
    );

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

void main() {
  group('CORE-4 incoming links (cold start + while running)', () {
    test('cold start link is returned and stable across calls', () async {
      final p = FakePlatform(initialLink: 'https://example.com/product/7');
      final dl =
          DeferredLinks(platform: p, targetPlatform: TargetPlatform.android);
      final a = await dl.getInitialLink();
      expect(a!.uri.path, '/product/7');
      expect(a.isDeferred, isFalse);
      expect(identical(await dl.getInitialLink(), a), isTrue);
    });

    test('no launch link -> null', () async {
      final dl = DeferredLinks(
          platform: FakePlatform(), targetPlatform: TargetPlatform.android);
      expect(await dl.getInitialLink(), isNull);
    });

    test('links delivered while running arrive on the stream in order',
        () async {
      final p = FakePlatform();
      final dl =
          DeferredLinks(platform: p, targetPlatform: TargetPlatform.android);
      final got = <String>[];
      final sub = dl.linkStream.listen((l) => got.add(l.uri.path));
      p.controller.add('https://example.com/a');
      p.controller.add('https://example.com/b');
      await pumpEventQueue();
      expect(got, ['/a', '/b']);
      await sub.cancel();
    });

    test('short link is resolved through the server (data included)', () async {
      final p = FakePlatform(initialLink: 'https://go.example.com/aB3dEf9h');
      final dl =
          DeferredLinks(platform: p, targetPlatform: TargetPlatform.android)
            ..configure(cfg(MockClient((req) async {
              expect(req.url.path, '/v1/resolve/aB3dEf9h');
              return json({
                'id': 'aB3dEf9h',
                'deepLink': 'https://go.example.com/product/42',
                'data': {'promo': 'SPRING'},
              });
            })));
      final link = (await dl.getInitialLink())!;
      expect(link.uri.path, '/product/42');
      expect(link.data['promo'], 'SPRING');
      expect(link.linkId, 'aB3dEf9h');
    });

    test('server down: the raw short URL still reaches the app', () async {
      final p = FakePlatform(initialLink: 'https://go.example.com/aB3dEf9h');
      final dl = DeferredLinks(
          platform: p, targetPlatform: TargetPlatform.android)
        ..configure(cfg(
            MockClient((_) async => throw http.ClientException('offline'))));
      final link = (await dl.getInitialLink())!;
      expect(link.uri.toString(), 'https://go.example.com/aB3dEf9h');
      expect(link.linkId, 'aB3dEf9h');
    });

    test('unknown/expired short id (404) falls back to the raw URL', () async {
      final p = FakePlatform(initialLink: 'https://go.example.com/gone1234');
      final dl = DeferredLinks(
          platform: p, targetPlatform: TargetPlatform.android)
        ..configure(
            cfg(MockClient((_) async => json({'error': 'not_found'}, 404))));
      expect((await dl.getInitialLink())!.uri.path, '/gone1234');
    });

    test('non short-link URLs are not sent to the server', () async {
      var calls = 0;
      final p = FakePlatform(initialLink: 'https://go.example.com/product/42');
      final dl =
          DeferredLinks(platform: p, targetPlatform: TargetPlatform.android)
            ..configure(cfg(MockClient((_) async {
              calls++;
              return json({});
            })));
      await dl.getInitialLink();
      expect(calls, 0);
    });
  });

  group('CORE-2 Android deferred link via Install Referrer', () {
    InstallReferrerResult ok(String r) =>
        InstallReferrerResult('ok', referrer: r);

    test('server confirms the click and returns data', () async {
      final p = FakePlatform(
          referrer:
              ok('dl_click=abcd1234efgh&dl_link=https%3A%2F%2Fx.test%2Fp%2F1'));
      final dl =
          DeferredLinks(platform: p, targetPlatform: TargetPlatform.android)
            ..configure(cfg(MockClient((req) async {
              expect(req.url.path, '/v1/clicks/abcd1234efgh/install');
              return json({
                'id': 'L1',
                'deepLink': 'https://x.test/p/1',
                'data': {'k': 'v'}
              });
            })));
      final r = await dl.checkDeferredLink();
      expect(r.status, DeferredStatus.matched);
      expect(r.link!.isDeferred, isTrue);
      expect(r.link!.method, DeferredMethod.installReferrer);
      expect(r.link!.confidence, MatchConfidence.exact);
      expect(r.link!.data, {'k': 'v'});
      expect(p.markCount, 1);
    });

    test('works without any server round trip (dl_link inside the referrer)',
        () async {
      final p = FakePlatform(
          referrer:
              ok('dl_click=abcd1234efgh&dl_link=https%3A%2F%2Fx.test%2Fp%2F1'));
      final dl =
          DeferredLinks(platform: p, targetPlatform: TargetPlatform.android);
      final r = await dl.checkDeferredLink();
      expect(r.link!.uri.toString(), 'https://x.test/p/1');
    });

    test('server error with dl_link present -> still matched from the referrer',
        () async {
      final p = FakePlatform(
          referrer:
              ok('dl_click=abcd1234efgh&dl_link=https%3A%2F%2Fx.test%2Fp%2F1'));
      final dl =
          DeferredLinks(platform: p, targetPlatform: TargetPlatform.android)
            ..configure(cfg(MockClient((_) async => json({}, 500))));
      expect((await dl.checkDeferredLink()).link!.uri.path, '/p/1');
    });

    test('click expired on the server -> fall back to dl_link', () async {
      final p = FakePlatform(
          referrer:
              ok('dl_click=abcd1234efgh&dl_link=https%3A%2F%2Fx.test%2Fp%2F1'));
      final dl = DeferredLinks(
          platform: p, targetPlatform: TargetPlatform.android)
        ..configure(
            cfg(MockClient((_) async => json({'error': 'not_found'}, 404))));
      expect((await dl.checkDeferredLink()).link!.uri.path, '/p/1');
    });

    test('organic install -> noMatch, and the check is marked done', () async {
      final p = FakePlatform(
          referrer: ok('utm_source=google-play&utm_medium=organic'));
      final dl =
          DeferredLinks(platform: p, targetPlatform: TargetPlatform.android);
      final r = await dl.checkDeferredLink();
      expect(r.status, DeferredStatus.noMatch);
      expect(p.markCount, 1);
      expect(
          (await dl.checkDeferredLink()).status, DeferredStatus.notFirstLaunch);
    });

    test('transient Play service failure -> error, retried next launch',
        () async {
      final p =
          FakePlatform(referrer: const InstallReferrerResult('transient'));
      final dl =
          DeferredLinks(platform: p, targetPlatform: TargetPlatform.android);
      final r = await dl.checkDeferredLink();
      expect(r.status, DeferredStatus.error);
      expect(p.markCount, 0);
      expect(p.firstLaunch, isTrue);
    });

    test('network failure with no dl_link -> error, not marked', () async {
      final p = FakePlatform(referrer: ok('dl_click=abcd1234efgh'));
      final dl = DeferredLinks(
          platform: p, targetPlatform: TargetPlatform.android)
        ..configure(cfg(
            MockClient((_) async => throw http.ClientException('offline'))));
      final r = await dl.checkDeferredLink();
      expect(r.status, DeferredStatus.error);
      expect(p.markCount, 0);
    });

    test('not the first launch -> nothing is checked', () async {
      final p = FakePlatform(
          firstLaunch: false, referrer: ok('dl_click=abcd1234efgh'));
      final dl =
          DeferredLinks(platform: p, targetPlatform: TargetPlatform.android);
      expect(
          (await dl.checkDeferredLink()).status, DeferredStatus.notFirstLaunch);
    });

    test('parseInstallReferrer ignores garbage and invalid ids', () {
      expect(parseInstallReferrer(null).isEmpty, isTrue);
      expect(parseInstallReferrer('%%%').isEmpty, isTrue);
      expect(parseInstallReferrer('dl_click=<script>').clickId, isNull);
      expect(parseInstallReferrer('dl_link=javascript').deepLink, isNull);
      expect(parseInstallReferrer('dl_click=abcd1234').clickId, 'abcd1234');
    });
  });

  group('CORE-3 iOS best-effort deferred link', () {
    final matchBody = <String, Object?>{
      'matched': true,
      'method': 'fingerprint',
      'confidence': 'high',
      'score': 1.0,
      'link': <String, Object?>{
        'id': 'L1',
        'deepLink': 'https://x.test/p/1',
        'data': <String, String>{}
      },
    };

    test(
        'sends coarse signals to the server and reports the confidence honestly',
        () async {
      late Map<String, Object?> sent;
      final p = FakePlatform();
      final dl = DeferredLinks(platform: p, targetPlatform: TargetPlatform.iOS)
        ..configure(cfg(MockClient((req) async {
          sent = jsonDecode(req.body) as Map<String, Object?>;
          return json(matchBody);
        })));
      final r = await dl.checkDeferredLink();
      expect(r.link!.method, DeferredMethod.fingerprint);
      expect(r.link!.confidence, MatchConfidence.high);
      final signals = sent['signals']! as Map<String, Object?>;
      expect(signals.keys.toSet(), {
        'platform',
        'osVersion',
        'screenWidth',
        'screenHeight',
        'language',
        'timezoneOffsetMinutes',
      });
      expect(sent.containsKey('clipboard'), isFalse);
    });

    test('a low-confidence match is NOT returned under the default policy',
        () async {
      final p = FakePlatform();
      final dl = DeferredLinks(platform: p, targetPlatform: TargetPlatform.iOS)
        ..configure(cfg(MockClient((_) async =>
            json(<String, Object?>{...matchBody, 'confidence': 'low'}))));
      expect((await dl.checkDeferredLink()).status, DeferredStatus.noMatch);
    });

    test('...but is returned when the app opts into low confidence', () async {
      final p = FakePlatform();
      final dl = DeferredLinks(platform: p, targetPlatform: TargetPlatform.iOS)
        ..configure(cfg(
            MockClient((_) async =>
                json(<String, Object?>{...matchBody, 'confidence': 'low'})),
            min: MatchConfidence.low));
      final r = await dl.checkDeferredLink();
      expect(r.link!.confidence, MatchConfidence.low);
    });

    test('server says no match -> noMatch, marked done', () async {
      final p = FakePlatform();
      final dl = DeferredLinks(platform: p, targetPlatform: TargetPlatform.iOS)
        ..configure(cfg(MockClient((_) async => json({'matched': false}))));
      expect((await dl.checkDeferredLink()).status, DeferredStatus.noMatch);
      expect(p.markCount, 1);
    });

    test('network failure -> error and retried next launch', () async {
      final p = FakePlatform();
      final dl = DeferredLinks(platform: p, targetPlatform: TargetPlatform.iOS)
        ..configure(cfg(
            MockClient((_) async => throw http.ClientException('offline'))));
      expect((await dl.checkDeferredLink()).status, DeferredStatus.error);
      expect(p.firstLaunch, isTrue);
    });

    test('clipboard is NEVER read unless useClipboard is true', () async {
      var reads = 0;
      final dl = DeferredLinks(
        platform: FakePlatform(),
        targetPlatform: TargetPlatform.iOS,
        clipboardReader: () async {
          reads++;
          return 'deferredlinks:abcd1234';
        },
      )..configure(cfg(MockClient((_) async => json({'matched': false}))));
      await dl.checkDeferredLink();
      expect(reads, 0);
    });

    test('with opt-in, only a deferredlinks: token is sent', () async {
      Map<String, Object?>? sent;
      Future<DeferredLinkResult> run(String clip) {
        final dl = DeferredLinks(
          platform: FakePlatform(),
          targetPlatform: TargetPlatform.iOS,
          clipboardReader: () async => clip,
        )..configure(cfg(MockClient((req) async {
            sent = jsonDecode(req.body) as Map<String, Object?>;
            return json(
                {...matchBody, 'method': 'clipboard', 'confidence': 'exact'});
          }), clipboard: true));
        return dl.checkDeferredLink();
      }

      final r = await run('deferredlinks:abcd1234');
      expect(sent!['clipboard'], 'deferredlinks:abcd1234');
      expect(r.link!.method, DeferredMethod.clipboard);
      expect(r.link!.confidence, MatchConfidence.exact);

      sent = null;
      await run('my bank password');
      expect(sent!.containsKey('clipboard'),
          isFalse); // unrelated text never leaves the device
    });
  });

  group('short link creation', () {
    test('posts the request with the API key and parses the response',
        () async {
      late http.Request seen;
      final dl = DeferredLinks(
          platform: FakePlatform(), targetPlatform: TargetPlatform.android)
        ..configure(DeferredLinksConfig(
          serverUrl: Uri.parse('https://go.example.com'),
          apiKey: 'k',
          httpClient: MockClient((req) async {
            seen = req;
            return json({
              'id': 'abc12345',
              'shortUrl': 'https://go.example.com/abc12345',
              'deepLink': 'https://go.example.com/p/1',
              'expiresAt': 1700000000000,
            }, 201);
          }),
        ));
      final link = await dl.createShortLink(ShortLinkRequest(
        deepLink: Uri.parse('https://go.example.com/p/1'),
        data: const {'a': 'b'},
        ttl: const Duration(days: 1),
        title: 'T',
      ));
      expect(seen.headers['authorization'], 'Bearer k');
      final body = jsonDecode(seen.body) as Map<String, Object?>;
      expect(body['ttlSeconds'], 86400);
      expect(body['data'], {'a': 'b'});
      expect(link.shortUrl.path, '/abc12345');
      expect(link.expiresAt!.isUtc, isTrue);
    });

    test('server rejection surfaces as DeferredLinksException', () async {
      final dl = DeferredLinks(
          platform: FakePlatform(), targetPlatform: TargetPlatform.android)
        ..configure(
            cfg(MockClient((_) async => json({'error': 'unauthorized'}, 401))));
      expect(
        () => dl.createShortLink(
            ShortLinkRequest(deepLink: Uri.parse('https://x.test/'))),
        throwsA(isA<DeferredLinksException>()
            .having((e) => e.statusCode, 'status', 401)),
      );
    });

    test('before configure -> StateError', () {
      final dl = DeferredLinks(
          platform: FakePlatform(), targetPlatform: TargetPlatform.android);
      expect(
          () => dl.createShortLink(
              ShortLinkRequest(deepLink: Uri.parse('https://x.test/'))),
          throwsStateError);
    });
  });
}
