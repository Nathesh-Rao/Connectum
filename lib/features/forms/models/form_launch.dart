import 'dart:convert';

import '../../../data/models/form_card.dart';
import '../../../data/models/form_submission.dart';
import '../../../data/models/ids.dart';

enum FormMode { create, edit, resubmit, resend }

/// What the form screen is opened for. Passed as the route argument; [tag]
/// is unique per opening, so two forms never share a controller.
class FormLaunch {
  FormLaunch({
    required this.name,
    required this.scope,
    required this.caption,
    this.mode = FormMode.create,
    this.convId,
    this.submissionId,
    this.savedValues,
    this.errorDetails,
    this.isEncryptedChat = false,
  }) : tag = 'form-${newCid()}';

  /// An edit of a submission of mine, or its resubmit when it was declined
  /// and the approver allowed a fix.
  factory FormLaunch.forSubmission(
    FormCardData card,
    FormSubmission saved, {
    required String me,
    String scope = '',
    String? convId,
    bool isEncryptedChat = false,
  }) {
    Object? decoded;
    try {
      decoded = jsonDecode(saved.valuesJson);
    } on FormatException {
      decoded = null;
    }
    return FormLaunch(
      name: card.structure,
      scope: card.scope.isNotEmpty ? card.scope : scope,
      caption: card.caption,
      mode: card.canFix(me) ? FormMode.resubmit : FormMode.edit,
      convId: convId,
      submissionId: card.id,
      savedValues: decoded is Map ? decoded.cast<String, dynamic>() : {},
      isEncryptedChat: isEncryptedChat,
    );
  }

  final String tag;

  /// The form's name (what `tstruct.get` takes) and its scope, `user` or
  /// `admin`.
  final String name;
  final String scope;
  final String caption;
  final FormMode mode;

  /// The conversation the form message should land in; null from the
  /// workspace.
  final String? convId;

  /// The submission being edited or resubmitted (a server id), or the local
  /// temp id of one that failed and is being fixed.
  final String? submissionId;

  /// The saved answers an edit starts from.
  final Map<String, dynamic>? savedValues;

  /// The server's complaint about a submission being fixed (`details`).
  final Object? errorDetails;

  /// The conversation is end-to-end encrypted: the form says its message is
  /// not.
  final bool isEncryptedChat;

  bool get isEdit => mode != FormMode.create;

  String get title => isEdit ? 'Edit - $caption' : caption;

  String get buttonLabel => switch (mode) {
    FormMode.create => 'Done',
    FormMode.edit => 'Save',
    FormMode.resubmit => 'Resubmit',
    FormMode.resend => 'Resend',
  };
}
