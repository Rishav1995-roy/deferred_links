import 'dart:async';

import 'package:deferred_links/deferred_links.dart';

/// In-memory stand-in for the native side.
class FakePlatform implements DeferredLinksPlatform {
  FakePlatform({
    this.initialLink,
    this.referrer = const InstallReferrerResult('unavailable'),
    DeviceSignals? signals,
    this.firstLaunch = true,
  }) : signals = signals ??
            const DeviceSignals(
              platform: 'ios',
              osVersion: '17.4',
              screenWidth: 390,
              screenHeight: 844,
              language: 'en-US',
              timezoneOffsetMinutes: 330,
            );

  String? initialLink;
  InstallReferrerResult referrer;
  DeviceSignals signals;
  bool firstLaunch;
  int markCount = 0;
  final StreamController<String> controller =
      StreamController<String>.broadcast();

  @override
  Future<String?> getInitialLink() async => initialLink;

  @override
  Stream<String> get linkStream => controller.stream;

  @override
  Future<InstallReferrerResult> getInstallReferrer() async => referrer;

  @override
  Future<bool> isFirstLaunch() async => firstLaunch;

  @override
  Future<void> markDeferredChecked() async {
    markCount++;
    firstLaunch = false;
  }

  @override
  Future<DeviceSignals> getDeviceSignals() async => signals;
}
