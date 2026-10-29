import 'package:deferred_links/deferred_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('DeepLinkPattern', () {
    test('captures path params and merges query params', () {
      final m = DeepLinkPattern('/product/:id')
          .match(Uri.parse('https://x.test/product/42?ref=a'));
      expect(m, {'id': '42', 'ref': 'a'});
    });
    test('rejects other shapes', () {
      final p = DeepLinkPattern('/product/:id');
      expect(p.match(Uri.parse('https://x.test/product')), isNull);
      expect(p.match(Uri.parse('https://x.test/product/1/2')), isNull);
      expect(p.match(Uri.parse('https://x.test/other/1')), isNull);
    });
    test('wildcard and trailing slash', () {
      expect(
          DeepLinkPattern('/docs/*')
              .match(Uri.parse('https://x.test/docs/a/b'))!['*'],
          'a/b');
      expect(DeepLinkPattern('/a/b').match(Uri.parse('https://x.test/a/b/')),
          isNotNull);
    });
  });

  test('DeepLinkRouter first match wins and reports misses', () {
    final calls = <String>[];
    final r = DeepLinkRouter({
      '/p/:id': (l, p) => calls.add('p${p['id']}'),
      '/*': (l, p) => calls.add('any'),
    });
    expect(r.route(DeepLink(uri: Uri.parse('https://x.test/p/9'))), isTrue);
    expect(calls, ['p9']);
    expect(
        DeepLinkRouter({'/a': (l, p) {}})
            .route(DeepLink(uri: Uri.parse('https://x.test/b'))),
        isFalse);
  });

  test('MatchConfidence ordering', () {
    expect(MatchConfidence.exact.atLeast(MatchConfidence.high), isTrue);
    expect(MatchConfidence.low.atLeast(MatchConfidence.medium), isFalse);
  });

  test('DeepLink equality and copyWith', () {
    final a =
        DeepLink(uri: Uri.parse('https://x.test/a'), data: const {'k': 'v'});
    expect(a,
        DeepLink(uri: Uri.parse('https://x.test/a'), data: const {'k': 'v'}));
    expect(a.copyWith(linkId: 'z').linkId, 'z');
    expect(
        a.hashCode,
        DeepLink(uri: Uri.parse('https://x.test/a'), data: const {'k': 'v'})
            .hashCode);
  });

  testWidgets(
      'DeepLinkScope: launch link wins over deferred; stream links keep coming',
      (tester) async {
    final p = FakePlatform(
      initialLink: 'https://x.test/p/1',
      referrer: const InstallReferrerResult('ok',
          referrer: 'dl_link=https%3A%2F%2Fx.test%2Fp%2F2'),
    );
    final dl =
        DeferredLinks(platform: p, targetPlatform: TargetPlatform.android);
    final got = <DeepLink>[];
    DeferredLinkResult? observed;
    await tester.pumpWidget(DeepLinkScope(
      links: dl,
      onLink: got.add,
      onDeferredResult: (r) => observed = r,
      child: const SizedBox(),
    ));
    await tester.pump();
    await tester.pump();
    expect(got.map((l) => l.uri.path), ['/p/1']);
    expect(observed!.status, DeferredStatus.matched);

    p.controller.add('https://x.test/p/3');
    await tester.pump();
    await tester.pump();
    expect(got.map((l) => l.uri.path), ['/p/1', '/p/3']);
  });

  testWidgets('DeepLinkScope delivers the deferred link when launched normally',
      (tester) async {
    final p = FakePlatform(
      referrer: const InstallReferrerResult('ok',
          referrer: 'dl_link=https%3A%2F%2Fx.test%2Fp%2F2'),
    );
    final dl =
        DeferredLinks(platform: p, targetPlatform: TargetPlatform.android);
    final got = <DeepLink>[];
    await tester.pumpWidget(
        DeepLinkScope(links: dl, onLink: got.add, child: const SizedBox()));
    await tester.pump();
    await tester.pump();
    expect(got.single.isDeferred, isTrue);
    expect(got.single.uri.path, '/p/2');
  });
}
