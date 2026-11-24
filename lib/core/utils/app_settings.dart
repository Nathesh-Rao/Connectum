import 'package:flutter/services.dart';
import '../log/app_log.dart';

/// Opens this app's page in the system settings (camera permission), through
/// the existing `connectum/device` channel.
class AppSettings {
  AppSettings._();

  static const _channel = MethodChannel('connectum/device');

  static Future<void> open() async {
    try {
      await _channel.invokeMethod<bool>('openSettings');
    } catch (e, st) {
      AppLog.e('app_settings', e, st);
    }
  }

  /// "0.1.0 (1)" from the installed app, or null when it cannot be read.
  static Future<String?> version() async {
    try {
      return await _channel.invokeMethod<String>('appVersion');
    } catch (e, st) {
      AppLog.e('app_settings', e, st);
      return null;
    }
  }
}
