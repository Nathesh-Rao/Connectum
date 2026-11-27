import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/log/log.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/models/models.dart';
import 'package:connectum/data/repositories/repositories.dart';

/// The state of the "Share to Connectum" sheet: the chats, the search, the
/// choice, and the send. Created for one sheet; the sending that follows the
/// sheet's closing needs nothing from the sheet and keeps going.
class ShareToConnectumController extends GetxController {
  ShareToConnectumController({required this.repo, required this.files});

  final ShareRepository repo;
  final List<ShareFile> files;

  final viewState = AppViewState.loading.obs;
  final targets = <ShareTarget>[].obs;
  final query = ''.obs;

  /// Chosen conversation ids, in the order they were chosen.
  final selected = <String>[].obs;
  final problem = RxnString();
  final isChecking = false.obs;

  /// The optional note's field is shown (a button until then, to keep the
  /// list tall on small screens).
  final isNoteOpen = false.obs;
  final search = TextEditingController();
  final caption = TextEditingController();

  @override
  void onClose() {
    search.dispose();
    caption.dispose();
    super.onClose();
  }

  List<ShareTarget> get visible {
    final q = query.value.trim().toLowerCase();
    if (q.isEmpty) return targets.toList();
    return [
      for (final t in targets)
        if (t.chat.title.toLowerCase().contains(q)) t,
    ];
  }

  List<Conversation> get chosen => [
    for (final id in selected)
      for (final t in targets)
        if (t.chat.convId == id) t.chat,
  ];

  String get sendLabel =>
      selected.isEmpty ? 'Send' : 'Send to ${selected.length}';

  /// The file's name on one line: a long name keeps its start and its end.
  String get fileLine {
    if (files.length != 1) return '${files.length} files';
    final name = files.first.name;
    if (name.length <= 34) return name;
    return '${name.substring(0, 20)}…${name.substring(name.length - 12)}';
  }

  Future<void> load() async {
    viewState.value = AppViewState.loading;
    try {
      final list = await repo.loadTargets();
      targets.assignAll(list);
      selected.removeWhere((id) => !list.any((t) => t.chat.convId == id));
      viewState.value = list.isEmpty
          ? AppViewState.empty
          : AppViewState.content;
    } catch (e, st) {
      AppLog.e('share_to_connectum_controller', e, st);
      viewState.value = AppViewState.error;
    }
  }

  void onSearch(String value) => query.value = value;

  void toggle(ShareTarget t) {
    if (!t.isEnabled) return;
    problem.value = null;
    final id = t.chat.convId;
    if (!selected.remove(id)) selected.add(id);
  }

  void remove(String convId) => selected.remove(convId);

  /// Checks the files and the connection, then sends in the background.
  /// True when the sheet may close; false leaves it open with [problem].
  Future<bool> submit() async {
    if (selected.isEmpty || isChecking.value) return false;
    isChecking.value = true;
    try {
      if (!repo.isOnline) {
        problem.value = 'Sharing needs a connection.';
        return false;
      }
      final picked = await repo.prepare(files);
      final chats = chosen;
      final note = isNoteOpen.value ? caption.text : '';
      problem.value = null;
      AppNotices.info(
        chats.length == 1
            ? 'Sending to 1 chat…'
            : 'Sending to ${chats.length} chats…',
      );
      fireAndLog(
        'share_to_connectum_controller',
        () => deliver(picked, chats, note),
      );
      return true;
    } on AttachmentException catch (e) {
      problem.value = e.message;
      return false;
    } catch (e, st) {
      AppLog.e('share_to_connectum_controller', e, st);
      problem.value = "That couldn't be shared. Try again.";
      return false;
    } finally {
      isChecking.value = false;
    }
  }

  /// Runs the send and tells the result. Public so a test can await it.
  Future<void> deliver(
    List<PickedAttachment> picked,
    List<Conversation> chats,
    String note,
  ) async {
    final results = await repo.send(files: picked, chats: chats, caption: note);
    final failed = [
      for (final r in results)
        if (!r.isOk) r,
    ];
    final done = results.length - failed.length;
    if (failed.isEmpty) {
      AppNotices.success(_shared(done));
      return;
    }
    final retry = [
      for (final r in failed)
        if (r.isRetryable) r.chat,
    ];
    AppNotices.show(
      done == 0
          ? "Couldn't share with ${_chats(failed.length)}"
          : '${_shared(done)}, ${failed.length} failed',
      variant: AppNoticeVariant.error,
      isPersistent: retry.isNotEmpty,
      actionLabel: retry.isEmpty ? null : 'Retry',
      onAction: retry.isEmpty
          ? null
          : () => fireAndLog(
              'share_to_connectum_controller',
              () => deliver(picked, retry, note),
            ),
    );
  }

  static String _chats(int n) => n == 1 ? '1 chat' : '$n chats';

  static String _shared(int n) => 'Shared with ${_chats(n)}';
}
