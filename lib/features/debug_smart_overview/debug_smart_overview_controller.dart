import 'package:get/get.dart';

import '../../core/debug/seed_smart_view.dart';
import '../../data/smart_view/models/sv_row.dart';
import '../../data/smart_view/models/sv_source.dart';
import '../../data/smart_view/overview/sv_overview.dart';
import '../smart_view/models/sv_overview_model.dart';

/// The Smart View Overview on a fake source, no server: Leave request with
/// 120 records over a month, an empty structure, one that cannot be read and
/// one that fails the first time. Debug builds only (see "Before release" in
/// CLAUDE.md).
class DebugSmartOverviewController extends GetxController {
  late final SvOverviewModel model;
  late final List<SvSource> sources;
  bool _isFlakyDone = false;

  @override
  void onInit() {
    super.onInit();
    final leave = SeedSmartView.leaveSource();
    sources = [
      leave,
      const SvSource(
        name: 'expense',
        caption: 'Expense claim',
        fields: [SvField(name: 'title', caption: 'Title')],
      ),
      const SvSource(
        name: 'help_ticket',
        caption: 'Ticket',
        fields: [SvField(name: 'title', caption: 'Title')],
      ),
      const SvSource(
        name: 'help_task',
        caption: 'Work order',
        fields: [SvField(name: 'title', caption: 'Title')],
      ),
    ];
    model = SvOverviewModel(read: _read);
    model.start(sources);
  }

  Future<SvOverviewRead> _read(SvSource s) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    switch (s.name) {
      case SeedSmartView.leave:
        final now = DateTime.now().millisecondsSinceEpoch;
        final rows = [
          for (final r in SeedSmartView.leaveRows())
            r.copyWith(ts: now - (r.id - 1000) * 5 * 3600000 - 3 * 3600000),
        ];
        return SvOverviewRead(isOk: true, rows: rows, total: rows.length);
      case 'expense':
        return const SvOverviewRead(isOk: true);
      case 'help_task':
        if (!_isFlakyDone) {
          _isFlakyDone = true;
          return const SvOverviewRead(isOk: false);
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        final rows = <SvRow>[
          for (var i = 0; i < 9; i++)
            SvRow(
              id: 5000 + i,
              tstruct: s.name,
              by: SeedSmartView.me,
              ts: now - i * 9 * 3600000,
            ),
        ];
        return SvOverviewRead(isOk: true, rows: rows, total: rows.length);
    }
    return const SvOverviewRead(isOk: false);
  }

  Future<void> reload() => model.start(sources);
}
