import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import '../../core/routes/conversation_route.dart';
import '../../core/widgets/app_notices.dart';
import '../../data/repositories/command_repository.dart';
import '../conversation/models/command_prompt.dart';
import 'widgets/command_sheets.dart';

/// Runs a `#` line from a message box and shows what came back: a notice, a
/// screen, a sheet, or a chat opened with a draft. One per composer; the
/// controller that owns it holds the text and clears it when [run] says so.
class CommandRunner {
  CommandRunner(
    this._commands,
    this._prompt, {
    this.activeConvId,
    this.applyDraft,
  });

  final CommandRepository _commands;
  final CommandPrompt _prompt;

  /// The open chat, for a bare `#leavegroup`.
  final String? activeConvId;

  /// Puts a draft into this composer when the chat it names is the open one.
  final void Function(String text)? applyDraft;

  /// True while a command waits for its answer; the send button is off.
  final isRunning = false.obs;

  /// Runs [body]; true when the message box should be cleared.
  Future<bool> run(String body, {bool isConfirmed = false}) async {
    if (isRunning.value) return false;
    isRunning.value = true;
    try {
      final result = await _commands.run(
        body,
        activeConvId: activeConvId,
        isConfirmed: isConfirmed,
      );
      return await _show(result, body);
    } finally {
      isRunning.value = false;
    }
  }

  Future<bool> _show(HashResult r, String body) async {
    switch (r.kind) {
      case HashKind.success:
        AppNotices.success(r.text);
      case HashKind.notice:
      case HashKind.soon:
      case HashKind.info:
        AppNotices.info(r.text);
      case HashKind.usage:
      case HashKind.invalid:
      case HashKind.blocked:
      case HashKind.needsConnection:
        AppNotices.warning(r.text);
      case HashKind.unknown:
        _prompt.unknownNames.assignAll(r.suggestions);
        AppNotices.warning(r.text);
      case HashKind.error:
        AppNotices.error(r.text);
      case HashKind.draft:
        _openDraft(r);
      case HashKind.screen:
        _openScreen(r.target);
      case HashKind.rows:
        CommandSheets.showRows(
          title: r.text,
          rows: r.rows,
          onOpen: ConversationRoute.open,
        );
      case HashKind.confirm:
        final isSure = await CommandSheets.confirmLeave(r.target);
        if (isSure) return run(body, isConfirmed: true);
      case HashKind.directQueued:
      case HashKind.done:
        break;
    }
    return r.isFinished;
  }

  void _openDraft(HashResult r) {
    if (r.convId == activeConvId) {
      applyDraft?.call(r.text);
      return;
    }
    ConversationRoute.setDraft(r.convId, r.text);
    ConversationRoute.open(r.convId);
  }

  void _openScreen(String target) {
    switch (target) {
      case 'inbox':
        Get.until((route) => route.isFirst);
      case 'tasks':
        Get.toNamed(AppRoutes.tasks);
      default:
        CommandSheets.showHelp(
          _commands,
          name: target.startsWith('help:') ? target.substring(5) : null,
        );
    }
  }
}
