import 'package:get/get.dart';

import '../../core/widgets/app_notices.dart';
import '../../data/models/thread_names.dart';
import '../../data/socket/socket_service.dart';

/// The rename of one record conversation. Made by the Chats controller for one
/// sheet. [onRename] shows the title at once, sends it and throws the server's
/// refusal; the sheet owns the text field.
class RecordRenameController {
  RecordRenameController({required this.onRename, required this.isOffline});

  final Future<void> Function(String name) onRename;
  final bool Function() isOffline;

  static const needsConnection =
      'This needs a connection. Try again when you are online.';
  static const failed = "Couldn't rename it. Try again.";

  final isSaving = false.obs;

  /// What is wrong with the typed name (shown under the field).
  final error = RxnString();

  /// The last text told through [AppNotices]: the server's refusal, or no
  /// connection.
  String? lastNotice;

  /// True when the conversation was renamed and the sheet may close.
  Future<bool> save(String name) async {
    if (isSaving.value) return false;
    final problem = RecordRename.problemWith(name);
    if (problem != null) {
      error.value = problem;
      return false;
    }
    if (isOffline()) {
      _tell(needsConnection);
      return false;
    }
    error.value = null;
    isSaving.value = true;
    try {
      await onRename(name);
      return true;
    } on SocketCallError catch (e) {
      _tell(
        e.isConnectionGap
            ? needsConnection
            : e.message.isEmpty
            ? failed
            : e.message,
      );
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  void _tell(String text) {
    lastNotice = text;
    AppNotices.error(text);
  }

  void clearError() => error.value = null;
}
