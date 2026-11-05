import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../data/models/ticket.dart';
import '../chats/models/chat_person.dart';
import '../forms/models/field_input.dart';
import 'models/ticket_input.dart';
import 'tickets_texts.dart';

/// What the person types for one action: only the inputs the action asks
/// for. It outlives a failed send (stale, forbidden, busy), so nothing typed
/// is lost; [requestId] is kept while a retry is the same update.
class TicketActionForm {
  TicketActionForm(this.action, {int completion = 0})
    : percent = completion.clamp(0, 100).obs;

  final TicketAction action;

  final remarks = TextEditingController();
  final reasonText = TextEditingController();
  final reason = ''.obs;
  final remarksText = ''.obs;
  final sendTo = Rxn<ChatPerson>();
  final RxInt percent;
  final files = <FormFileItem>[].obs;
  final error = RxnString();

  /// Set at the first send and kept for retries of a lost answer; null again
  /// once the server has answered for good.
  String? requestId;

  TicketActionInput get input => TicketActionInput(
    reason: reason.value,
    remarks: remarksText.value,
    sendTo: sendTo.value?.username ?? '',
    percent: percent.value,
    files: [
      for (final f in files)
        if (f.id != null && f.state.value == FormFileState.done) f.id!,
    ],
  );

  /// Why Send is not ready yet; null when it is.
  String? get problem {
    if (files.any((f) => f.state.value == FormFileState.uploading)) {
      return TicketsTexts.attachWait;
    }
    if (files.any((f) => f.state.value == FormFileState.failed)) {
      return TicketsTexts.attachFailed;
    }
    return TicketValidation.check(action, input);
  }

  void dispose() {
    remarks.dispose();
    reasonText.dispose();
    for (final f in files) {
      f.cancel.cancel();
    }
  }
}
