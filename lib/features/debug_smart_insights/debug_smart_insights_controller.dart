import 'package:get/get.dart';

import '../../core/debug/seed_smart_view.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/features/smart_view/smart_view.dart';

/// The speed dial, the KPI sheet and the Charts sheet on 120 sample Leave
/// request records, no server. Debug builds only (see "Before release" in
/// CLAUDE.md).
class DebugSmartInsightsController extends GetxController {
  DebugSmartInsightsController({required this.view}) {
    final source = SeedSmartView.leaveSource();
    final t = SvTable(source)
      ..rows.assignAll(SeedSmartView.leaveRows())
      ..phase.value = SvPhase.ready;
    view
      ..current.value = source
      ..table.value = t;
  }

  final SmartViewController view;

  @override
  void onClose() {
    view.onClose();
    super.onClose();
  }
}
