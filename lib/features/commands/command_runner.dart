import 'package:get/get.dart';

import '../../core/crash/crash_breadcrumbs.dart';
import '../../core/routes/app_routes.dart';
import '../../data/commands/command_line.dart';
import '../../core/routes/conversation_route.dart';
import '../../core/widgets/app_notices.dart';
import '../../data/repositories/command_repository.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/smart_view_repository.dart';
import '../../data/repositories/submission_repository.dart';
import '../../data/smart_view/models/sv_source.dart';
import '../../data/socket/socket_service.dart';
import '../smart_view/models/smart_view_entry.dart';
import '../forms/models/form_launch.dart';
import '../struct_records/models/struct_records_launch.dart';
import '../home_shell/home_shell_controller.dart';
import '../conversation/models/command_prompt.dart';
import 'widgets/command_sheets.dart';
import '../../core/log/safe.dart';

/// Runs a `#` line from a message box and shows what came back: a notice, a
/// screen, a sheet, or a chat opened with a draft. One per composer; the
/// controller that owns it holds the text and clears it when [run] says so.
class CommandRunner {
  CommandRunner(
    this._commands,
    this._prompt, {
    this.activeConvId,
    this.applyDraft,
    this.submissions,
    this.smartView,
    this.shell,
    this.chatConvId,
    this.chatTitle,
  });

  final CommandRepository _commands;
  final CommandPrompt _prompt;

  /// The open chat, for a bare `#leavegroup`.
  final String? activeConvId;

  /// Puts a draft into this composer when the chat it names is the open one.
  final void Function(String text)? applyDraft;

  /// Opens the structure a `#tstruct` / `#tstruct-add` line names.
  final SubmissionRepository? submissions;

  /// Opens `#view`; null: it says "coming soon".
  final SmartViewRepository? smartView;
  final HomeShellController? shell;

  /// The open chat when a form may be posted into it (a direct message or a
  /// group); null in the Work Space and in the other kinds.
  final String? chatConvId;
  final String Function()? chatTitle;

  /// True while a command waits for its answer; the send button is off.
  final isRunning = false.obs;

  /// Runs [body]; true when the message box should be cleared.
  Future<bool> run(String body, {bool isConfirmed = false}) async {
    if (isRunning.value) return false;
    isRunning.value = true;
    final name = CommandLine.parse(body)?.name;
    if (name != null) CrashBreadcrumbs.add(Crumb.command, code: name);
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
      case HashKind.form:
      case HashKind.records:
        return _openStructure(r);
      case HashKind.smartView:
        return _openSmartView(r.target);
      case HashKind.screen:
        _openScreen(r.target);
      case HashKind.rows:
        fireAndLog('command_runner', () async => CommandSheets.showRows(
          title: r.text,
          rows: r.rows,
          onOpen: ConversationRoute.open,
        ));
      case HashKind.confirm:
        final isSure = await CommandSheets.confirmLeave(r.target);
        if (isSure) return run(body, isConfirmed: true);
      case HashKind.directQueued:
      case HashKind.done:
        break;
    }
    return r.isFinished;
  }

  /// The web sends the line and opens what the server answers (the fill-in
  /// form, or the person's records of it). Nothing is posted to the chat. A
  /// form opened in a direct message or a group offers the web's "also post
  /// this to the chat" box (unticked; ticked in a care thread; encrypted chats
  /// included, as on the web: the server posts the card); from the Work Space nothing is posted and the saved
  /// record shows there.
  Future<bool> _openStructure(HashResult r) async {
    final open = await submissions?.openStructure(r.target);
    if (open == null || !open.isOpen) {
      final text = open == null
          ? CommandRepository.comingSoon
          : open.isOffline
          ? 'Needs a connection'
          : open.code == 'rate_limited'
          ? 'Too many requests. Try again in a moment.'
          : open.message.isNotEmpty && open.code == 'not_found'
          ? open.message
          : "Couldn't open that structure. Try again.";
      AppNotices.warning(text);
      return false;
    }
    if (r.kind == HashKind.records) {
      fireAndLog('command_runner', () async => Get.toNamed(
        AppRoutes.structRecords,
        arguments: StructRecordsLaunch(
          name: open.name,
          scope: open.scope,
          caption: open.caption,
          convId: _postableChat,
        ),
      ));
    } else {
      fireAndLog('command_runner', () async => Get.toNamed(
        AppRoutes.form,
        arguments: FormLaunch(
          name: open.name,
          scope: open.scope,
          caption: open.caption,
          convId: _postableChat,
        ),
      ));
    }
    return true;
  }

  /// `#view [name]`: nothing is posted and nothing is sent. No name: the
  /// Smart view tab with its drawer open. A name: the first structure that matches it (exact name or
  /// caption, else the first that contains it); no match keeps the text.
  Future<bool> _openSmartView(String typed) async {
    final repo = smartView;
    final home = shell;
    if (repo == null || home == null) {
      AppNotices.info(CommandRepository.comingSoon);
      return false;
    }
    if (typed.isEmpty) {
      home.openSmartView(const SmartViewEntry.drawer());
      return true;
    }
    final List<SvSource> all;
    try {
      all = await repo.sources();
    } on SocketCallError catch (e) {
      AppNotices.warning(
        e.isConnectionGap
            ? 'Needs a connection'
            : "Couldn't open that. Try again.",
      );
      return false;
    }
    final hit = SvSources.find(all, typed);
    if (hit == null) {
      AppNotices.warning('Nothing is called “$typed” that you can open.');
      return false;
    }
    home.openSmartView(SmartViewEntry.named(hit.name));
    return true;
  }

  String? get _postableChat {
    final id = chatConvId;
    if (id == null) return null;
    final kind = ConversationRepository.kindOf(id);
    if (kind != 'dm' && kind != 'group') return null;
    return id;
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
        final home = shell;
        if (home != null) {
          home.openInbox();
        } else {
          Get.until((route) => route.isFirst);
        }
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
