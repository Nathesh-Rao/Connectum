import 'dart:async';

import 'package:get/get.dart';

import '../../core/debug/seed_smart_view.dart';
import '../../core/debug/seed_tickets.dart';
import '../../core/routes/app_routes.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/repositories/repositories.dart';

/// Smart View on the sample server, no connection needed: four structures
/// (120 records, empty, `not_found`, fails once), live changes after 10 s and
/// 20 s, with or without `data.record`. Debug builds only (see "Before
/// release" in CLAUDE.md).
class DebugSmartViewController extends GetxController {
  DebugSmartViewController({required this.repo, required this.tickets});

  final SmartViewRepository repo;
  final TicketRepository tickets;

  final isSample = false.obs;
  final isLoading = false.obs;
  final isRecordMode = SeedSmartView.isRecordMode.obs;
  final liveMode = RxnString();

  @override
  void onInit() {
    super.onInit();
    isSample.value = SeedSmartView.isActive;
    if (!isSample.value) unawaited(toggleSample(true));
  }

  Future<void> toggleSample(bool value) async {
    isLoading.value = true;
    try {
      if (value) {
        await SeedTickets.start();
        await SeedSmartView.start();
      } else {
        SeedSmartView.stop();
        SeedTickets.stop();
      }
      isSample.value = value;
      tickets.scheduleRefresh();
    } finally {
      isLoading.value = false;
    }
  }

  void setRecordMode(bool value) {
    isRecordMode.value = value;
    SeedSmartView.isRecordMode = value;
  }

  /// The Smart view tab, which reads the sample data while it is on.
  void open(String name) => Get.toNamed(AppRoutes.smartView);

  bool _needsSample() {
    if (isSample.value) return false;
    AppNotices.info('Turn on the sample data first.');
    return true;
  }

  void changeNow() {
    if (_needsSample()) return;
    SeedSmartView.changeStatus();
    liveMode.value = repo.liveMode;
  }

  void addNow() {
    if (_needsSample()) return;
    SeedSmartView.addRecord();
    liveMode.value = repo.liveMode;
  }

  /// Starts the 10 s and 20 s timers again.
  void restartTimers() {
    if (_needsSample()) return;
    SeedSmartView.startLive();
    AppNotices.info('A status changes in 10 s, a record appears in 20 s.');
  }

  void showMode() => liveMode.value = repo.liveMode ?? 'no event yet';
}
