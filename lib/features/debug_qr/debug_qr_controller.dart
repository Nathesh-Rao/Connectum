import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_qr.dart';
import '../../data/repositories/qr_repository.dart';
import '../qr/qr_sheet.dart';

class DebugQrController extends GetxController {
  DebugQrController({required this.real});

  /// The real `connect.my` source, to compare with the samples.
  final QrRepository real;

  Future<void> open(SeedQrScenario scenario, [BuildContext? context]) {
    final target = context ?? Get.context;
    if (target == null) return Future.value();
    return QrSheet.show(target, repository: scenario.repository());
  }

  Future<void> openReal(BuildContext context) =>
      QrSheet.show(context, repository: real);
}
