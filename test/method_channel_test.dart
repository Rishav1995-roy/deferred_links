import 'package:deferred_links/deferred_links.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.rishav/deferred_links');
  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'getInitialLink':
          return 'https://x.test/p/1';
        case 'getInstallReferrer':
          return <String, Object?>{
            'status': 'ok',
            'referrer': 'dl_click=abcd1234'
          };
        case 'isFirstLaunch':
          return true;
        case 'getDeviceSignals':
          return <String, Object?>{
            'platform': 'ios',
            'screenWidth': 390,
            'screenHeight': 844,
            'timezoneOffsetMinutes': 330,
            'language': 'en-US',
            'osVersion': '17.4',
          };
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('method channel platform maps native replies', () async {
    final p = MethodChannelDeferredLinksPlatform();
    expect(await p.getInitialLink(), 'https://x.test/p/1');
    final ref = await p.getInstallReferrer();
    expect(ref.status, 'ok');
    expect(ref.referrer, 'dl_click=abcd1234');
    expect(await p.isFirstLaunch(), isTrue);
    await p.markDeferredChecked();
    final s = await p.getDeviceSignals();
    expect(s.screenWidth, 390);
    expect(s.toJson()['timezoneOffsetMinutes'], 330);
    expect(calls, contains('markDeferredChecked'));
  });
}
