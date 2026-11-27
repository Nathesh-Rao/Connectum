import 'package:get/get.dart';

import 'package:connectum/core/tour/tour.dart';
import 'package:connectum/data/models/models.dart';
import 'models/inbox_row.dart';

/// The sample of the Inbox tour: two record cards for the Records tab (when
/// the person has no record) and two requests for the Approvals tab (when
/// they have none). Plain in-memory objects that only the screen reads while
/// the tour runs: never put into a repository, SQLite, the socket, a count,
/// a tab badge or a saved view. Sample ids are negative, so they never meet a
/// real one.
class InboxTourDemo {
  static const fileId = 'a1b2c3d4e5f6a1b2c3d4e5f6';
  static const sampleForm = 'tour-sample-leave';

  /// True from the seed to the restore, whatever was sampled: the screen's
  /// own reactions (a tab change ends a tour) keep still while the tour
  /// drives it.
  bool isDriving = false;

  /// Sample cards may show on the Records tab (the person has no record).
  final isRecordsSample = false.obs;

  /// Sample requests may show on the Approvals tab.
  final isApprovalsSample = false.obs;

  /// The Records filter popup is drawn over the screen (not a route: a route
  /// would end the tour).
  final isFilterOpen = false.obs;

  /// The sample cards that are open (their keys).
  final expanded = <String>{}.obs;

  List<InboxRow> rows = const [];
  List<Approval> approvals = const [];

  bool isOpen(String key) => expanded.contains(key);

  void toggle(String key) {
    if (!expanded.remove(key)) expanded.add(key);
  }

  void begin({
    required bool isRecords,
    required bool isApprovals,
    required int now,
  }) {
    isDriving = true;
    isRecordsSample.value = isRecords;
    isApprovalsSample.value = isApprovals;
    rows = isRecords ? _rows(now) : const [];
    approvals = isApprovals ? _approvals(now) : const [];
  }

  /// Everything off. Safe to call again.
  void end() {
    isFilterOpen.value = false;
    isRecordsSample.value = false;
    isApprovalsSample.value = false;
    expanded.clear();
    isDriving = false;
    rows = const [];
    approvals = const [];
  }

  static List<InboxRow> _rows(int now) => [
    InboxRow(
      id: -101,
      formId: sampleForm,
      form: 'Leave request',
      subject: 'Leave request',
      holder: 'maya',
      raiser: 'maya',
      ts: now - const Duration(hours: 3).inMilliseconds,
      statusField: 'stage',
      state: 'In review',
      isWaiting: true,
      fields: const {
        'stage': 'Stage',
        'reason': 'Reason',
        'from': 'From',
        'to': 'To',
        'note': 'Medical note',
      },
      values: {
        'stage': 'In review',
        'reason': 'Family event',
        'from': '2026-12-02',
        'to': '2026-12-04',
        'note': [fileId],
      },
      files: {
        'note': [
          {
            'id': fileId,
            'name': 'Medical-note.pdf',
            'mime': 'application/pdf',
            'size': 96256,
          },
        ],
      },
    ),
    InboxRow(
      id: -102,
      formId: sampleForm,
      form: 'Purchase request',
      subject: 'Purchase request',
      holder: 'ravi',
      raiser: 'ravi',
      ts: now - const Duration(days: 1).inMilliseconds,
      statusField: 'stage',
      state: 'Approved',
      isFinal: true,
      fields: const {'stage': 'Stage', 'item': 'Item', 'amount': 'Amount'},
      values: const {
        'stage': 'Approved',
        'item': 'Office chairs',
        'amount': 1250,
      },
    ),
  ];

  static List<Approval> _approvals(int now) => [
    Approval(
      id: -201,
      type: 'membership',
      from: 'maya',
      fromName: TourTexts.inboxSampleName,
      fromUser: 'maya',
      direction: Approval.incoming,
      canRespond: true,
      createdTs: now - const Duration(hours: 1).inMilliseconds,
      message: 'Hi, I would like to connect with you.',
      approvers: const ['me'],
    ),
    Approval(
      id: -202,
      type: Approval.submissionType,
      from: 'ravi',
      fromName: 'Ravi Menon',
      fromUser: 'ravi',
      direction: Approval.incoming,
      canRespond: true,
      createdTs: now - const Duration(hours: 5).inMilliseconds,
      formId: 'tour-sample-expense',
      caption: 'Expense claim',
      lines: const [
        ApprovalLine('Amount', '4200'),
        ApprovalLine('Reason', 'Client visit'),
      ],
      stage: 1,
      stages: 2,
      approvers: const ['me'],
    ),
  ];
}
