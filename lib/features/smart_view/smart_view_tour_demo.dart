import 'package:get/get.dart';

import 'package:connectum/core/tour/tour.dart';
import 'package:connectum/data/repositories/repositories.dart';
import '../../data/smart_view/models/sv_row.dart';
import '../../data/smart_view/models/sv_source.dart';
import '../../data/smart_view/sv_prefs.dart';
import '../../data/smart_view/sv_query.dart';

/// The sample of the Smart view tour: one sample view for the drawer (only
/// when the person has none) and sample records for the body (only when no
/// view with records is open). Plain in-memory objects that only the screen
/// reads while the tour runs: never read from or written to a repository,
/// SQLite, the socket or the read gate. Sample record numbers are negative,
/// so they never meet a real one in the screen's sets.
class SvTourDemo {
  static const sourceName = 'tour-sample-requests';
  static const fileId = 'a1b2c3d4e5f6a1b2c3d4e5f6';

  /// True from the moment the tour is seeded to its restore, whatever was
  /// sampled: the screen's own reactions (a drawer that opens ends a tour)
  /// keep still while the tour drives it.
  bool isDriving = false;

  /// The drawer lists the sample view (the person has no view of their own).
  final isListSample = false.obs;

  /// The body may show sample records (no open view has records).
  final isRecordsSample = false.obs;

  /// The filter sheet is drawn over the screen (not a route: a route would
  /// end the tour).
  final isFilterOpen = false.obs;

  SvSource? source;
  SvTable? table;

  /// What the screen held before the sample records went in.
  SvTourSaved? saved;

  bool isSampleTable(SvTable? t) => t != null && identical(t, table);

  bool isSampleSource(SvSource? s) => s != null && s.name == sourceName;

  /// The first sample record number (the one the tour expands).
  int get firstRowId => -1;

  /// Builds the sample view and its records. [now] is epoch ms.
  void begin({
    required bool isList,
    required bool isRecords,
    required int now,
  }) {
    isDriving = true;
    isListSample.value = isList;
    isRecordsSample.value = isRecords;
    if (!isList && !isRecords) return;
    final s = source = _source();
    final t = SvTable(s);
    t.rows.assignAll(_rows(now));
    t.total.value = t.rows.length;
    t.phase.value = SvPhase.ready;
    table = t;
  }

  /// Everything off. Safe to call again.
  void end() {
    isFilterOpen.value = false;
    isListSample.value = false;
    isRecordsSample.value = false;
    isDriving = false;
    saved = null;
    table = null;
    source = null;
  }

  static SvSource _source() => const SvSource(
    name: sourceName,
    caption: TourTexts.svSampleViewCaption,
    keyField: 'subject',
    canAdd: false,
    fields: [
      SvField(name: 'subject', caption: 'Subject'),
      SvField(name: 'attachment', caption: 'Attachment', type: 'file'),
      SvField(name: 'kind', caption: 'Kind', type: 'selection'),
      SvField(name: 'amount', caption: 'Amount', type: 'number'),
      SvField(name: 'due', caption: 'Due date', type: 'date'),
      SvField(name: 'owner', caption: 'Owner'),
      SvField(name: 'priority', caption: 'Priority', type: 'selection'),
      SvField(name: 'note', caption: 'Note'),
    ],
  );

  static List<SvRow> _rows(int now) {
    final day = DateTime.fromMillisecondsSinceEpoch(now);
    String due(int days) {
      final d = day.add(Duration(days: days));
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
    }

    return [
      SvRow(
        id: -1,
        tstruct: sourceName,
        by: 'maya',
        byName: TourTexts.sampleSender,
        ts: now - const Duration(hours: 2).inMilliseconds,
        values: {
          'subject': 'Office chairs',
          'kind': 'Purchase',
          'amount': 1250,
          'due': due(6),
          'owner': 'Maya',
          'priority': 'High',
          'note': 'Four chairs for the new desks.',
          'attachment': [fileId],
        },
        files: {
          'attachment': [
            {
              'id': fileId,
              'name': 'Quote-1042.pdf',
              'mime': 'application/pdf',
              'size': 184320,
            },
          ],
        },
      ),
      SvRow(
        id: -2,
        tstruct: sourceName,
        by: 'maya',
        byName: TourTexts.sampleSender,
        ts: now - const Duration(days: 1).inMilliseconds,
        values: {
          'subject': 'Team lunch',
          'kind': 'Expense',
          'amount': 86,
          'due': due(2),
          'owner': 'Ravi',
          'priority': 'Low',
          'note': 'Friday, after the review.',
        },
      ),
      SvRow(
        id: -3,
        tstruct: sourceName,
        by: 'maya',
        byName: TourTexts.sampleSender,
        ts: now - const Duration(days: 3).inMilliseconds,
        values: {
          'subject': 'Laptop battery',
          'kind': 'Repair',
          'amount': 140,
          'due': due(10),
          'owner': 'Anil',
          'priority': 'Medium',
          'note': 'Replace under warranty.',
        },
      ),
    ];
  }
}

/// The screen's own state while the sample records are in its place.
class SvTourSaved {
  SvTourSaved({
    required this.table,
    required this.current,
    required this.query,
    required this.groupBy,
    required this.hidden,
    required this.order,
    required this.selectedViewId,
    required this.mode,
  });

  final SvTable? table;
  final SvSource? current;
  final SmartViewQuery query;
  final List<String> groupBy;
  final List<String> hidden;
  final List<String> order;
  final String? selectedViewId;
  final SvViewMode mode;
}
