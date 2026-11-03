import 'dart:io';

import 'package:flutter/services.dart';

/// The label this phone registers under: `Connectum mobile (model)`. The
/// model comes from a small platform channel (Android `Build.MODEL`, iOS
/// `UIDevice.model`), so no plugin is needed.
class E2eDeviceLabel {
  E2eDeviceLabel._();

  static const _channel = MethodChannel('connectum/device');

  static Future<String> current() async {
    var model = '';
    try {
      model = (await _channel.invokeMethod<String>('model') ?? '').trim();
    } catch (_) {}
    if (model.isEmpty) model = Platform.isIOS ? 'iOS' : 'Android';
    return 'Connectum mobile ($model)';
  }
}
