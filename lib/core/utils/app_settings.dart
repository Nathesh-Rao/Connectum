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

  /// "0.1.0 (1)" from the installed app, or null when it cannot be read.
  static Future<String?> version() async {
    try {
      return await _channel.invokeMethod<String>('appVersion');
    } catch (_) {
      return null;
    }
  }
}
