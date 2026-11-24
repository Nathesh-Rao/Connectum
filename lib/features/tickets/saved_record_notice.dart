import 'dart:async';

import 'package:get/get.dart';

import '../../core/widgets/app_notices.dart';
import '../../data/repositories/submission_repository.dart';
import '../../data/repositories/ticket_repository.dart';
import 'tickets_texts.dart';
import '../../core/log/safe.dart';

/// After a new submission is accepted: "Saved", or "Waiting for approval".
/// A form with auto-send rules has already sent it on by then; one read of
/// `record.actions` says who holds it, and that is told too. There is no
/// draft: a saved record is a record.
class SavedRecordNotice extends GetxService {
  SavedRecordNotice(this._submissions, this._tickets);

  final SubmissionRepository _submissions;
  final TicketRepository _tickets;
  StreamSubscription<SavedRecord>? _sub;

  @override
  void onInit() {
    super.onInit();
    _sub = _submissions.saved.listen((r) => fireAndLog('saved_record_notice', () => handle(r)), onError: streamOnError('saved_record_notice'));
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }

  Future<void> handle(SavedRecord r) async {
    if (r.isPending) {
      AppNotices.info(TicketsTexts.savedWaiting);
      return;
    }
    if (r.isNotPosted) {
      AppNotices.warning(TicketsTexts.savedNotPosted);
    } else {
      AppNotices.success(TicketsTexts.saved);
    }
    final state = await _tickets.afterSave(r.id);
    if (state == null) return;
    final holders = state.claimants.isNotEmpty
        ? state.claimants
        : [if (state.holder.isNotEmpty) state.holder];
    final others = [
      for (final h in holders)
        if (!_tickets.isMe(h)) _tickets.nameOf(h),
    ];
    if (others.isNotEmpty) {
      AppNotices.info(TicketsTexts.sentOn(others));
    }
  }
}
