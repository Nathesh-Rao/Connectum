import 'dart:ui';

import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';

class DebugRefreshController extends GetxController {
  static const colorNames = ['kPullRefreshColor', 'Primary blue', 'Violet'];
  static const colors = <Color>[
    kPullRefreshColor,
    AppColors.primary,
    AppColors.violet,
  ];

  final size = AppSpacing.spinnerPull.obs;
  final colorIndex = 0.obs;
  final isFailing = false.obs;
  final isReducedMotion = false.obs;
  final refreshCount = 0.obs;

  Future<void> fakeRefresh() async {
    refreshCount.value++;
    if (isFailing.value) {
      await Future<void>.delayed(const Duration(seconds: 1));
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
}
