import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'package:connectum/data/models/models.dart';
import '../forms/models/field_input.dart';
import 'models/ticket_input.dart';
import 'tickets_texts.dart';

/// What the person types for one action (`status` or `send`): only the inputs
/// that action has. It outlives a failed send (stale, forbidden, busy), so
/// nothing typed is lost; [requestId] is kept while a retry is the same
/// intent and dropped once the server has answered for good.
class TicketActionForm {
  TicketActionForm(this.kind, {required this.state, String status = ''})
    : statusPick = (status.isEmpty ? state.status : status).obs {
    if (kind == RecordActionItem.status) percent.value = _startPercent();
  }

  final String kind;

  /// What `record.actions` said when the sheet opened; replaced when the
  /// record is read again, so required flags and statuses follow the server.
  RecordState state;

  bool get isStatus => kind == RecordActionItem.status;
  bool get isSend => kind == RecordActionItem.send;

  // status
  final RxString statusPick;
  final comments = TextEditingController();
  final commentsText = ''.obs;
  final percent = RxnInt();

  /// An administrator picked a non-final status for a closed record and has
  /// not chosen a percentage: the control shows 99 and says so.
  final isReopening = false.obs;

  /// The server's refusal about the completion, shown under the slider.
  final percentError = RxnString();

  /// The last change of [percent] came from a rule (animate it), not a drag.
  final isPercentJump = false.obs;

  bool _isHeldAtFloor = false;
  final hours = TextEditingController();
  final hoursText = ''.obs;

  // send
  final via = SendInput.viaUser.obs;
  final person = Rxn<RecordPerson>();
  final value = ''.obs;
  final reason = TextEditingController();
  final reasonText = ''.obs;
  final remarks = TextEditingController();
  final remarksText = ''.obs;

  /// The completion rules (final status 100, 99 otherwise) apply only when
  /// the form has a final status.
  bool get hasFinalRules => state.finalStatuses.isNotEmpty;

  bool get isFinalPicked => state.finalStatuses.contains(statusPick.value);

  /// The lowest completion the person may set. A member: the larger of the
  /// server's `minCompletion` and the current completion. An administrator:
  /// 0 in a form with a closing status; in a form without one the server's
  /// own `minCompletion` stays (it does not let anyone lower it).
  int get minPercent {
    final floor = state.minCompletion ?? 0;
    if (state.isAdmin) return hasFinalRules ? 0 : floor;
    final now = state.completion ?? 0;
    return floor > now ? floor : now;
  }

  /// The highest completion: 99 on a status that does not close (only a
  /// closing status ends a record), else 100.
  int get maxPercent {
    if (!hasFinalRules || isFinalPicked) return 100;
    return minPercent > 99 ? minPercent : 99;
  }

  /// The completion before the person's change, shown as "Was 40%"; null when
  /// nothing is locked.
  int? get lockedBelow => minPercent > 0 ? minPercent : null;

  /// A final status is picked: completion is 100 and cannot move.
  bool get isPercentLocked => hasFinalRules && isFinalPicked;

  /// An older record that holds 100 on a status that does not close: the
  /// control stays at the current value and no percentage is sent.
  bool get isPercentFixed =>
      hasFinalRules && !isFinalPicked && minPercent >= 100;

  int? _startPercent() {
    final now = state.completion;
    if (now == null || !hasFinalRules || isFinalPicked) return now;
    if (isPercentFixed) return now;
    return now > maxPercent ? maxPercent : now;
  }

  /// Picks [name] by hand and applies the rules.
  void pickStatus(String name) {
    final wasFinal = isFinalPicked;
    statusPick.value = name;
    isReopening.value = false;
    percentError.value = null;
    if (!isStatus || !hasFinalRules) return;
    if (isFinalPicked) {
      _jump(100);
    } else if (isPercentFixed) {
      _jump(state.completion ?? 100);
    } else if (state.isFinal) {
      final now = state.completion;
      if (now == null || now > 99) {
        _jump(99);
        isReopening.value = state.isAdmin;
      } else {
        _jump(now);
      }
    } else if (wasFinal || (percent.value ?? 0) > 99) {
      final before = state.completion;
      _jump(before != null && before < 100 ? before : 99);
    }
  }

  /// The slider moved to [raw]: held between the lowest and the highest
  /// allowed. Reaching the end of a non-closing status stops at 99.
  void setPercent(int raw) {
    if (isPercentLocked || isPercentFixed) return;
    final v = raw.clamp(minPercent, maxPercent);
    final isHeld = raw < minPercent && minPercent > 0;
    if (isHeld && !_isHeldAtFloor) HapticFeedback.lightImpact();
    _isHeldAtFloor = isHeld;
    isPercentJump.value = false;
    isReopening.value = false;
    percentError.value = null;
    percent.value = v;
  }

  void _jump(int v) {
    isPercentJump.value = true;
    percent.value = v;
  }

  final files = <FormFileItem>[].obs;
  final error = RxnString();

  /// Set at the first send and kept for retries of a lost answer; null again
  /// once the server has answered for good.
  String? requestId;

  /// The busy retry has already been used for this intent.
  bool hasRetriedBusy = false;

  List<String> get fileIds => [
    for (final f in files)
      if (f.id != null && f.state.value == FormFileState.done) f.id!,
  ];

  StatusInput get statusInput => StatusInput(
    status: statusPick.value,
    comments: commentsText.value,
    percent: isPercentFixed ? null : percent.value,
    hours: hoursText.value,
    files: fileIds,
  );

  SendInput get sendInput => SendInput(
    via: via.value,
    person: person.value?.username ?? '',
    value: value.value,
    reason: reasonText.value,
    remarks: remarksText.value,
    files: fileIds,
  );

  /// Why Send is not ready yet; null when it is. Only the phone's own checks.
  String? get problem {
    if (files.any((f) => f.state.value == FormFileState.uploading)) {
      return TicketsTexts.attachWait;
    }
    if (files.any((f) => f.state.value == FormFileState.failed)) {
      return TicketsTexts.attachFailed;
    }
    return isStatus
        ? RecordValidation.status(state, statusInput)
        : RecordValidation.send(sendInput);
  }

  void dispose() {
    comments.dispose();
    hours.dispose();
    reason.dispose();
    remarks.dispose();
    for (final f in files) {
      f.cancel.cancel();
    }
  }
}
