import 'package:get/get.dart';

import '../../core/debug/seed_smart_view.dart';
import '../../data/smart_view/models/sv_row.dart';
import '../../data/smart_view/models/sv_source.dart';
import '../smart_view/widgets/smart_view_table.dart';

/// The Smart View table on 120 sample Leave request records, no server.
/// Debug builds only (see "Before release" in CLAUDE.md).
class DebugSmartTableController extends GetxController {
  final SvSource source = SeedSmartView.leaveSource();
  final List<SvRow> rows = SeedSmartView.leaveRows();
  final cache = SmartViewTableCache();

  Future<void> reload() async {}
}
