import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../data/models/record_state.dart';
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
    if (kind == RecordActionItem.status) percent.value = state.completion;
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

  /// The final status picked for the person because the slider reached 100;
  /// empty when the person picked it or none was picked for them.
  final autoFinal = ''.obs;

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

  /// The lowest completion the person may set: what the record has now, or 0
  /// for an administrator or a record with none yet.
  int get minPercent => state.isAdmin ? 0 : (state.completion ?? 0);

  /// The completion before the person's change, shown as "Was 40%"; null when
  /// nothing is locked.
  int? get lockedBelow => minPercent > 0 ? minPercent : null;

  /// A final status is picked: completion is 100 and cannot move.
  bool get isPercentLocked => hasFinalRules && isFinalPicked;

  /// Picks [name] by hand and applies the rules.
  void pickStatus(String name) {
    final wasFinal = isFinalPicked;
    statusPick.value = name;
    autoFinal.value = '';
    if (!isStatus || !hasFinalRules) return;
    if (isFinalPicked) {
      _jump(100);
    } else if (wasFinal || (percent.value ?? 0) >= 100) {
      final before = state.completion;
      _jump(before != null && before < 100 ? before : 99);
    }
  }

  /// The slider moved to [raw]: clamped to what is allowed. 100 always means
  /// closed: on a non-final status the first final status is picked.
  void setPercent(int raw) {
    if (isPercentLocked) return;
    final v = raw.clamp(minPercent, 100);
    final isHeld = raw < minPercent && !state.isAdmin;
    if (isHeld && !_isHeldAtFloor) HapticFeedback.lightImpact();
    _isHeldAtFloor = isHeld;
    isPercentJump.value = false;
    percent.value = v;
    if (hasFinalRules && v >= 100 && !isFinalPicked) {
      final first = _firstFinal;
      if (first != null) {
        statusPick.value = first;
        autoFinal.value = first;
      }
    }
  }

  String? get _firstFinal {
    for (final name in state.statuses) {
      if (state.finalStatuses.contains(name)) return name;
    }
    return state.finalStatuses.isEmpty ? null : state.finalStatuses.first;
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
    percent: percent.value,
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
