import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'models/qr_models.dart';
import 'qr_binding.dart';
import 'qr_controller.dart';
import 'qr_view.dart';

/// The QR codes as a bottom sheet: the one entry point other screens call.
class QrSheet {
  QrSheet._();

  static bool _isOpen = false;

  static Future<void> show(
    BuildContext context, {
    required QrRepository repository,
    QrKind initialKind = QrKind.person,
  }) {
    if (_isOpen) return Future.value();
    _isOpen = true;
    QrBinding(repository: repository, initialKind: initialKind).dependencies();
    return AppBottomSheet.showFixed<void>(
      context,
      child: const QrView(),
    ).whenComplete(
      // The route future completes when the sheet starts to close; the view
      // still reads the controller while it animates out. The sheet counts as
      // open until then, so a new one never meets the old controller.
      () => Future<void>.delayed(AppDurations.slow, () {
        Get.delete<QrController>(force: true);
        _isOpen = false;
      }),
    );
  }
}
