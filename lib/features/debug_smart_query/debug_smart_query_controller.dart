import 'package:get/get.dart';

import '../../core/debug/seed_smart_view.dart';
import '../../data/repositories/smart_view_repository.dart';
import '../smart_view/smart_view_controller.dart';

/// The Smart View controls (search, filter, sort, chips, cards and table) on
/// 120 sample Leave request records, no server. Debug builds only (see
/// "Before release" in CLAUDE.md).
class DebugSmartQueryController extends GetxController {
  DebugSmartQueryController({required this.view}) {
    final source = SeedSmartView.leaveSource();
    final t = SvTable(source)
      ..rows.assignAll(SeedSmartView.leaveRows())
      ..phase.value = SvPhase.ready;
    view
      ..current.value = source
      ..table.value = t;
  }

  /// The tab's own controller, filled with the sample rows.
  final SmartViewController view;

  @override
  void onClose() {
    view.onClose();
    super.onClose();
  }
}
