import 'package:flutter/services.dart';

/// Device helpers on `sus/device`: camera permission, the app's page in iOS
/// Settings, keep-awake, thermal state and the share sheet.
abstract class DeviceApi {
  /// granted | denied | restricted | undetermined
  Future<String> cameraPermission();
  Future<bool> requestCameraPermission();
  Future<void> openAppSettings();

  /// Opens physiology.presagetech.com (the only URL the app opens).
  Future<void> openPortal();
  Future<void> setKeepAwake(bool on);

  /// nominal | fair | serious | critical
  Future<String> thermalState();

  /// Shares a PNG from memory through the iOS share sheet.
  Future<void> shareImage(Uint8List png, {String? text});
}

class MethodChannelDevice implements DeviceApi {
  MethodChannelDevice({
    MethodChannel method = const MethodChannel('sus/device'),
  }) : _method = method;

  final MethodChannel _method;

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _method.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<String> cameraPermission() async =>
      await _call<String>('cameraPermission') ?? 'unknown';

  @override
  Future<bool> requestCameraPermission() async =>
      await _call<bool>('requestCameraPermission') ?? false;

  @override
  Future<void> openAppSettings() => _call<void>('openAppSettings');

  @override
  Future<void> openPortal() => _call<void>('openPortal');

  @override
  Future<void> setKeepAwake(bool on) => _call<void>('setKeepAwake', {'on': on});

  @override
  Future<String> thermalState() async =>
      await _call<String>('thermalState') ?? 'nominal';

  @override
  Future<void> shareImage(Uint8List png, {String? text}) =>
      _call<void>('shareImage', {'png': png, 'text': ?text});
}
