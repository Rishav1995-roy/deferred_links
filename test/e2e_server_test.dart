// End to end: the real Dart client against the real reference server running
// in this process on a loopback port. Proves the client and server agree on
// the wire format for every flow.
import 'dart:convert';
import 'dart:io';

import 'package:deferred_links/deferred_links.dart';
import 'package:deferred_links_server/deferred_links_server.dart' as srv;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as io;

import 'support.dart';

void main() {
  late HttpServer server;
  late Uri base;
  late srv.MemoryStore store;

  setUp(() async {
    store = srv.MemoryStore();
    final app = srv.DeferredLinksServer(
      srv.ServerConfig(
        baseUrl: Uri.parse('http://127.0.0.1'),
        apiKeys: ['secret'],
        androidPackage: 'com.example.app',
        androidStoreUrl:
            'https://play.google.com/store/apps/details?id=com.example.app',
        iosStoreUrl: 'https://apps.apple.com/app/id1',
        ipHashSalt: 's',
      ),
      store,
    );
    server = await io.serve(app.handler, InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
  });

  tearDown(() => server.close(force: true));

  DeferredLinksConfig config() =>
      DeferredLinksConfig(serverUrl: base, apiKey: 'secret');

  Future<String> clickAs(String ua, String shortUrl,
      {Map<String, Object?>? fp, bool follow = false}) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(shortUrl))
        ..followRedirects = false
        ..headers['user-agent'] = ua
        ..headers['accept-language'] = 'en-US';
      final res = await http.Response.fromStream(await client.send(req));
      if (res.statusCode == 302) return res.headers['location']!;
      final id =
          RegExp(r'"click":"([A-Za-z0-9_-]+)"').firstMatch(res.body)!.group(1)!;
      if (fp != null) {
        final post = await client.post(
            Uri.parse(
                '${shortUrl.substring(0, shortUrl.lastIndexOf('/'))}/c/$id/fp'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(fp));
        expect(post.statusCode, 204);
      }
      return id;
    } finally {
      client.close();
    }
  }

  test('create -> installed app opens short link -> resolved with data',
      () async {
    final dl = DeferredLinks(
        platform: FakePlatform(initialLink: null),
        targetPlatform: TargetPlatform.android)
      ..configure(config());
    final short = await dl.createShortLink(ShortLinkRequest(
      deepLink: Uri.parse('https://example.com/product/42'),
      data: const {'promo': 'SPRING'},
    ));
    final p = FakePlatform(
        initialLink: short.shortUrl
            .replace(host: '127.0.0.1', port: server.port)
            .toString());
    final app = DeferredLinks(
        platform: p, targetPlatform: TargetPlatform.android)
      ..configure(
          DeferredLinksConfig(serverUrl: base, shortLinkHosts: ['127.0.0.1']));
    final link = (await app.getInitialLink())!;
    expect(link.uri.toString(), 'https://example.com/product/42');
    expect(link.data, {'promo': 'SPRING'});
  });

  test(
      'ANDROID full flow: click -> Play redirect -> referrer -> first launch -> right link',
      () async {
    final creator = DeferredLinks(
        platform: FakePlatform(), targetPlatform: TargetPlatform.android)
      ..configure(config());
    final short = await creator.createShortLink(ShortLinkRequest(
      deepLink: Uri.parse('https://example.com/product/42'),
      data: const {'promo': 'SPRING'},
    ));
    final shortUrl =
        short.shortUrl.replace(host: '127.0.0.1', port: server.port).toString();
    final location =
        await clickAs('Mozilla/5.0 (Linux; Android 14) Chrome/124', shortUrl);
    final referrer = Uri.parse(location)
        .queryParameters['referrer']!; // what Play hands the app

    final p =
        FakePlatform(referrer: InstallReferrerResult('ok', referrer: referrer));
    final fresh =
        DeferredLinks(platform: p, targetPlatform: TargetPlatform.android)
          ..configure(config());
    final r = await fresh.checkDeferredLink();
    expect(r.status, DeferredStatus.matched);
    expect(r.link!.uri.path, '/product/42');
    expect(r.link!.data['promo'], 'SPRING');
    expect(r.link!.confidence, MatchConfidence.exact);
  });

  test(
      'IOS full flow: click + landing-page signals -> first launch -> right link (high)',
      () async {
    final creator = DeferredLinks(
        platform: FakePlatform(), targetPlatform: TargetPlatform.iOS)
      ..configure(config());
    final short = await creator.createShortLink(ShortLinkRequest(
        deepLink: Uri.parse('https://example.com/product/42')));
    final shortUrl =
        short.shortUrl.replace(host: '127.0.0.1', port: server.port).toString();
    await clickAs(
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1',
      shortUrl,
      fp: {
        'screenWidth': 390,
        'screenHeight': 844,
        'timezoneOffsetMinutes': 330,
        'language': 'en-US'
      },
    );
    final app = DeferredLinks(
        platform: FakePlatform(), targetPlatform: TargetPlatform.iOS)
      ..configure(config());
    final r = await app.checkDeferredLink();
    expect(r.status, DeferredStatus.matched);
    expect(r.link!.uri.path, '/product/42');
    expect(r.link!.method, DeferredMethod.fingerprint);
    expect(r.link!.confidence, MatchConfidence.high);
  });

  test('IOS with no prior click -> noMatch', () async {
    final app = DeferredLinks(
        platform: FakePlatform(), targetPlatform: TargetPlatform.iOS)
      ..configure(config());
    expect((await app.checkDeferredLink()).status, DeferredStatus.noMatch);
  });
}
