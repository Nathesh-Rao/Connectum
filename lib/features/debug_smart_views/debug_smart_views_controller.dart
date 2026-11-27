import 'package:get/get.dart';

import '../../core/debug/seed_saved_views.dart';
import '../../core/debug/seed_smart_view.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/features/smart_view/smart_view.dart';

/// The saved views of the Leave request demo (Pending only, By status with
/// two group levels, Compact) over 120 sample rows with a fake repository:
/// save, rename, delete and one remote change that shows the overwrite
/// question. No server. Debug builds only (see "Before release").
class DebugSmartViewsController extends GetxController {
  DebugSmartViewsController({required this.view, required this.fake});

  final SmartViewController view;
  final SeedSavedViews fake;

  static DebugSmartViewsController create(
    SmartViewController Function(SvSavedViewsRepository) make,
  ) {
    final fake = SeedSavedViews()..armConflict();
    return DebugSmartViewsController(
      view: make(SvSavedViewsRepository(call: fake.callWithConflict)),
      fake: fake,
    );
  }

  @override
  void onInit() {
    super.onInit();
    final source = SeedSmartView.leaveSource();
    final t = SvTable(source)
      ..rows.assignAll(SeedSmartView.leaveRows())
      ..phase.value = SvPhase.ready;
    view
      ..current.value = source
      ..table.value = t;
    view.openViews(source);
  }

  @override
  void onClose() {
    view.onClose();
    super.onClose();
  }
}
