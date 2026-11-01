import 'package:flutter/services.dart';

/// Opens this app's page in the system settings (camera permission), through
/// the existing `connectum/device` channel.
class AppSettings {
  AppSettings._();

  static const _channel = MethodChannel('connectum/device');

  static Future<void> open() async {
    try {
      await _channel.invokeMethod<bool>('openSettings');
    } catch (_) {}
  }
}
