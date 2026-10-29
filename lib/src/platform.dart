import 'package:flutter/services.dart';

import 'models.dart';

/// Result of asking the OS store for the install referrer.
class InstallReferrerResult {
  /// Creates a result.
  const InstallReferrerResult(this.status, {this.referrer});

  /// `ok`, `unavailable` (no Play Store / unsupported, final) or `transient`
  /// (service disconnected, retry later).
  final String status;

  /// The raw referrer string when [status] is `ok`.
  final String? referrer;
}

/// Native bridge. Replace in tests with a fake.
abstract class DeferredLinksPlatform {
  /// The link that launched the app, if any.
  Future<String?> getInitialLink();

  /// Links received while the app is running.
  Stream<String> get linkStream;

  /// Reads the Play Install Referrer (Android only; iOS returns `unavailable`).
  Future<InstallReferrerResult> getInstallReferrer();

  /// Whether the deferred-link check has not completed since install.
  Future<bool> isFirstLaunch();

  /// Records that the check reached a final outcome.
  Future<void> markDeferredChecked();

  /// Coarse device signals for iOS matching.
  Future<DeviceSignals> getDeviceSignals();
}

/// The real implementation over a [MethodChannel] and an [EventChannel].
class MethodChannelDeferredLinksPlatform implements DeferredLinksPlatform {
  /// Creates the channel-backed platform.
  MethodChannelDeferredLinksPlatform();

  static const MethodChannel _method =
      MethodChannel('dev.rishav/deferred_links');
  static const EventChannel _events =
      EventChannel('dev.rishav/deferred_links/events');

  Stream<String>? _stream;

  @override
  Future<String?> getInitialLink() =>
      _method.invokeMethod<String>('getInitialLink');

  @override
  Stream<String> get linkStream => _stream ??=
      _events.receiveBroadcastStream().where((e) => e is String).cast<String>();

  @override
  Future<InstallReferrerResult> getInstallReferrer() async {
    final map =
        await _method.invokeMapMethod<String, Object?>('getInstallReferrer');
    return InstallReferrerResult(
      (map?['status'] as String?) ?? 'unavailable',
      referrer: map?['referrer'] as String?,
    );
  }

  @override
  Future<bool> isFirstLaunch() async =>
      (await _method.invokeMethod<bool>('isFirstLaunch')) ?? false;

  @override
  Future<void> markDeferredChecked() =>
      _method.invokeMethod<void>('markDeferredChecked');

  @override
  Future<DeviceSignals> getDeviceSignals() async {
    final map =
        await _method.invokeMapMethod<Object?, Object?>('getDeviceSignals');
    return DeviceSignals.fromMap(map ?? const <Object?, Object?>{});
  }
}
