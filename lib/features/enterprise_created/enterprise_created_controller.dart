import 'dart:async';

import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../core/routes/home_reload.dart';
import '../../core/theme/app_motion.dart';

class EnterpriseCreatedController extends GetxController {
  EnterpriseCreatedController({required this.name, required this.enterpriseId});

  final String name;
  final String enterpriseId;

  final isCopied = false.obs;
  Timer? _timer;

  Future<void> copyId() async {
    await Clipboard.setData(ClipboardData(text: enterpriseId));
    isCopied.value = true;
    _timer?.cancel();
    _timer = Timer(AppDurations.copiedHold, () => isCopied.value = false);
  }

  Future<void> continueToChats() => HomeReload.run();

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }
}
