import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_messages.dart';
import '../../core/debug/seed_ui.dart';
import '../../core/routes/app_routes.dart';
import '../../core/utils/chat_time.dart';
import '../../core/widgets/app_state_view.dart';
import '../../core/theme/app_motion.dart';
import '../../core/widgets/app_form_card.dart';
import '../../data/models/form_card.dart';
import '../../data/models/ids.dart';
import '../../data/repositories/smart_view_repository.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../data/repositories/workspace_repository.dart';
import '../../data/models/record_state.dart';
import '../tickets/models/card_menu.dart';
import '../tickets/models/record_card_rule.dart';
import '../tickets/ticket_detail_controller.dart';
import '../../data/commands/command_line.dart';
import '../../data/commands/command_reply.dart';
import '../../data/models/hash_command.dart';
import '../../data/models/message.dart';
import '../../data/repositories/command_repository.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/repositories/form_options_repository.dart';
import '../forms/forms_picker_controller.dart';
import '../forms/models/form_launch.dart';
import '../home_shell/home_shell_controller.dart';

import '../../data/repositories/submission_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../commands/command_runner.dart';
import '../conversation/models/command_prompt.dart';
import 'models/workspace_note.dart';
import 'models/workspace_row.dart';

/// My Work Space: the submissions I made as sent-style cards, newest at the
/// bottom. It reads the cache; opening it refreshes the list when online.
class WorkspaceController extends GetxController {
  WorkspaceController({
    required this.submissions,
    required this.store,
    required this.connectivity,
    required this.formOptions,
    required this.shell,
    required this.commands,
    required this.messages,
    required this.workspace,
    required this.tickets,
    required this.newTicketDetail,
    this.smartView,
  });

  final SubmissionRepository submissions;
  final SessionStore store;
  final ConnectivityService connectivity;
  final FormOptionsRepository formOptions;
  final HomeShellController? shell;
  final CommandRepository commands;
  final MessageRepository messages;
  final WorkspaceRepository workspace;
  final TicketRepository tickets;
  final SmartViewRepository? smartView;
  final TicketDetailController Function(int id) newTicketDetail;

  /// The latest own records shown as cards (the web's `MWS_CARDS`); older
  /// ones are in My submissions.
  static const ownCards = 100;

  static const placeholder = 'Type #<commands> or @<name>';
  static const nudgeText =
      'Start with # for commands or @name to message someone.';

  final text = TextEditingController();
  final focus = FocusNode();
  final length = 0.obs;

  /// The gentle line under the field for text that is sent nowhere.
  final nudge = RxnString();
  late final prompt = CommandPrompt(commands);
  late final runner = CommandRunner(
    commands,
    prompt,
    submissions: submissions,
    smartView: smartView,
    shell: shell,
  );
  final _notes = <WorkspaceNote>[];
  final _noteWorkers = <Worker>[];
  int _noteSeq = 0;
  bool _wasFailing = false;
  bool _isRunning = false;

  /// The forms button's sheet. A form filled in here has no conversation.
  late final picker = FormsPickerController(
    options: formOptions,
    connectivity: connectivity,
    shell: shell,
  );

  final notice = RxnString();
  final highlighted = <String>{}.obs;
  final _signatures = <String, String>{};
  Worker? _noticeWorker;
  Timer? _noticeTimer;

  /// Newest first, for a list that is reversed.
  final rows = <WorkspaceRow>[].obs;
  final viewState = AppViewState.loading.obs;

  Worker? _submissionsWorker;
  Worker? _definitionsWorker;
  Worker? _loadedWorker;
  Worker? _failuresWorker;
  Worker? _draftsWorker;
  Worker? _receivedWorker;
  Worker? _workspaceStateWorker;
  Worker? _connectivityWorker;
  final _details = <int, TicketDetailController>{};

  String get me => store.userId ?? SeedMessages.me;

  void openTasks() => Get.toNamed(AppRoutes.tasks);

  void openApprovals() => Get.toNamed(AppRoutes.approvals);

  /// The workspace's greeting, word for word as the web app builds it.
  String get welcome {
    final name = store.identity.value?.name ?? '';
    final who = name.isNotEmpty
        ? name
        : (store.userId ?? '').isNotEmpty
        ? store.userId!
        : 'User';
    return 'Welcome $who. This is your personal workspace for direct tasks, enterprise updates, and automation commands. You can type hash commands in the composer below to trigger actions, or use the sliders on the left and right to navigate conversations and priority notifications.';
  }

  @override
  void onInit() {
    super.onInit();
    _submissionsWorker = ever(submissions.submissions, (_) => _apply());
    _definitionsWorker = ever(submissions.definitions, (_) => _apply());
    _loadedWorker = ever(submissions.isLoaded, (_) => _apply());
    _failuresWorker = ever(submissions.failures, (_) => _apply());
    _draftsWorker = ever(submissions.drafts, (_) => _apply());
    _noticeWorker = ever(submissions.notice, (message) {
      if (message == null) return;
      notice.value = message;
      submissions.notice.value = null;
      _noticeTimer?.cancel();
      _noticeTimer = Timer(
        const Duration(seconds: 4),
        () => notice.value = null,
      );
    });
    _receivedWorker = ever(workspace.received, (_) => _apply());
    _workspaceStateWorker = everAll([
      workspace.isLoaded,
      workspace.hasError,
      workspace.reads,
      workspace.isSyncing,
    ], (_) => _apply());
    _connectivityWorker = ever(connectivity.state, (_) => _apply());
    _apply();
    if (connectivity.state.value == AppConnectivity.online) {
      workspace.request(now: true);
    }
  }

  /// The read failed and there is nothing to show: an error with Retry, never
  /// an empty list. Offline is not an error: the cache is shown.
  void retry() {
    viewState.value = AppViewState.loading;
    workspace.request(now: true);
  }

  void _apply() {
    final all = submissions.submissions
        .where((s) => s.byUser.toLowerCase() == me.toLowerCase())
        .toList();
    // Not yet on the server: always shown. The rest: the latest [ownCards].
    final pending = [
      for (final s in all)
        if (s.isPending) s,
    ];
    final synced = [
      for (final s in all)
        if (!s.isPending) s,
    ]..sort((a, b) => b.ts.compareTo(a.ts));
    final mine = [...pending, ...synced.take(ownCards)];
    final ownIds = {for (final s in mine) s.submissionId};
    final got = [
      for (final t in workspace.received)
        if (!ownIds.contains('${t.id}')) t,
    ];
    final now = DateTime.now();
    final entries = <({int ts, WorkspaceRow row})>[
      for (final s in mine)
        (
          ts: s.ts,
          row: WorkspaceRow.card(
            FormCardData.fromSubmission(
              s,
              definition: submissions.definitions[s.tstruct],
            ),
          ),
        ),
      for (final t in got)
        (
          ts: t.editedTs > 0 ? t.editedTs : t.ts,
          row: WorkspaceRow.received(FormCardData.fromTicket(t)),
        ),
      for (final n in _notes) (ts: n.ts, row: WorkspaceRow.note(n)),
    ]..sort((a, b) => a.ts.compareTo(b.ts));
    final asc = <WorkspaceRow>[];
    int? prevTs;
    for (final e in entries) {
      if (prevTs == null || !ChatTime.isSameDay(prevTs, e.ts)) {
        asc.add(WorkspaceRow.day(ChatTime.day(e.ts, now)));
      }
      asc.add(e.row);
      prevTs = e.ts;
    }
    rows.assignAll(asc.reversed);
    for (final s in mine) {
      final sig = '${s.valuesJson.hashCode}|${s.editedTs}|${s.status}';
      final before = _signatures[s.submissionId];
      _signatures[s.submissionId] = sig;
      if (before != null && before != sig && !s.isPending) {
        highlighted.add(s.submissionId);
        Timer(AppDurations.slow * 3, () => highlighted.remove(s.submissionId));
      }
    }
    final isOnline = connectivity.state.value == AppConnectivity.online;
    final hasCards = entries.any((e) => e.row.card != null);
    if (!submissions.isLoaded.value) {
      viewState.value = AppViewState.loading;
    } else if (!hasCards &&
        isOnline &&
        !workspace.isLoaded.value &&
        workspace.isSyncing.value) {
      viewState.value = AppViewState.loading;
    } else if (!hasCards && isOnline && workspace.hasError.value) {
      viewState.value = AppViewState.error;
    } else {
      viewState.value = AppViewState.content;
    }
    final isFailing = workspace.hasError.value && hasCards && isOnline;
    if (isFailing && !_wasFailing) {
      _say("Couldn't refresh your workspace. Showing what was saved.");
    }
    _wasFailing = isFailing;
  }

  // ---- composing -----------------------------------------------------------

  void onChanged(String value) {
    length.value = value.characters.length;
    nudge.value = null;
    final caret = text.selection;
    prompt.onTextChanged(value, caret: caret.isValid ? caret.baseOffset : null);
  }

  /// Puts `#name ` into the field; nothing runs until send.
  void pickCommand(HashCommand command) => _setText('#${command.name} ');

  void pickCommandItem(CommandSuggestion item) => _setText(prompt.insert(item));

  void renameCommand(String name) =>
      _setText(CommandPrompt.rename(text.text, name));

  void _setText(String value) {
    text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    onChanged(value);
    focus.requestFocus();
  }

  void _say(String message) {
    notice.value = message;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 4), () => notice.value = null);
  }

  /// `#` lines run as commands, `@name text` is a direct message; anything
  /// else is kept in the field with a hint and sent nowhere.
  Future<void> send() async {
    if (_isRunning || runner.isRunning.value) return;
    final body = text.text.trim();
    if (body.isEmpty) return;
    nudge.value = null;
    final at = RegExp(r'^@(\S+)\s+([\s\S]+)$').firstMatch(body);
    final isCommand =
        CommandRepository.isHashLine(body) || CommandLine.isEscape(body);
    if (!isCommand && at == null) {
      nudge.value = body.startsWith('@') && !body.contains(RegExp(r'\s'))
          ? 'Add a message after $body.'
          : nudgeText;
      return;
    }
    if (isCommand) {
      if (await runner.run(body) && text.text.trim() == body) {
        text.clear();
        length.value = 0;
        prompt.close();
      }
      return;
    }
    _isRunning = true;
    try {
      final result = await commands.sendDirect(
        at!.group(1)!,
        at.group(2)!.trim(),
      );
      switch (result.kind) {
        case HashKind.info:
          _addNote(
            WorkspaceNote(
              id: 'n${_noteSeq++}',
              text: result.text,
              ts: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        case HashKind.directQueued:
          final note = WorkspaceNote(
            id: 'n${_noteSeq++}',
            text: 'Sent to @${result.user}',
            ts: DateTime.now().millisecondsSinceEpoch,
            convId: result.convId,
            user: result.user,
          );
          _addNote(note);
          unawaited(_watch(note, result.cid));
        case HashKind.done:
          break;
        default:
          _say(result.text);
      }
      if (result.isFinished) {
        text.clear();
        length.value = 0;
        prompt.close();
      }
    } finally {
      _isRunning = false;
    }
  }

  void _addNote(WorkspaceNote note) {
    _notes.add(note);
    _apply();
  }

  /// Turns the "Sent to" row into the reason when the message fails.
  Future<void> _watch(WorkspaceNote note, String cid) async {
    final convId = note.convId!;
    final list = SeedUi.isActive
        ? SeedMessages.of(convId)
        : await messages.open(convId);
    void sync() {
      final m = list.where((m) => m.cid == cid).firstOrNull;
      if (m == null) return;
      final isFailed = m.status == MessageStatus.failed;
      note.isProblem.value = isFailed;
      final secure = m.secureFailure;
      note.text.value = !isFailed
          ? 'Sent to @${note.user}'
          : secure != null
          ? "Couldn't send to @${note.user}: $secure"
          : CommandRepository.failureText(m.failReason, note.user);
    }

    sync();
    _noteWorkers.add(ever(list, (_) => sync()));
  }

  void openChat(WorkspaceNote note) {
    final id = note.convId;
    if (id != null) Get.toNamed(AppRoutes.conversationOf(id));
  }

  /// A record someone sent me opens as a record; my own submission as before.
  void open(FormCardData d, {bool isReceived = false}) {
    final id = idNumber(d.id);
    if (isReceived && id != null) {
      Get.toNamed(AppRoutes.ticketOf(id));
      return;
    }
    Get.toNamed(AppRoutes.submissionDetailOf(d.id));
  }

  /// The record menu of a card opened: `record.actions`, read once (cached
  /// 60 s), never while cards are drawn. Null for a card that is no record.
  int? recordIdOf(FormCardData d) => RecordCardRule.of(d).id;

  void openRecordMenu(FormCardData d) {
    final id = recordIdOf(d);
    if (id != null) unawaited(tickets.ensureMenu(id));
  }

  TicketDetailController? detailOf(FormCardData d) {
    final id = recordIdOf(d);
    if (id == null) return null;
    return _details.putIfAbsent(id, () {
      final c = newTicketDetail(id);
      c.onInit();
      return c;
    });
  }

  bool canEdit(FormCardData d) => d.canEdit(me) || d.canFix(me);

  /// The rows of a card's menu: the record's actions and the card's own
  /// Edit, History and Delete (nothing of a chat message: there is none).
  List<CardMenuItem> cardMenuOf(FormCardData d, RecordState? state) {
    final isSettled = !d.isPending;
    return CardMenu.build(
      record: state,
      canEdit: isSettled && canEdit(d),
      isFix: d.canFix(me),
      canOpenHistory:
          isSettled &&
          recordIdOf(d) != null &&
          d.by.toLowerCase() == me.toLowerCase(),
      canDelete: isSettled && d.canDelete(me),
    );
  }

  void openHistory(FormCardData d) {
    final id = recordIdOf(d);
    if (id != null) Get.toNamed(AppRoutes.ticketOf(id));
  }

  /// Asks, then deletes the submission on the server (online only).
  Future<void> deleteCard(
    FormCardData d,
    Future<bool> Function() confirm,
  ) async {
    if (!d.canDelete(me) || !await confirm()) return;
    final problem = await submissions.deleteSubmission(d.id);
    _say(problem ?? 'Submission deleted');
  }

  AppFormCardState stateOf(FormCardData d) {
    if (!d.isPending) return AppFormCardState.sent;
    return submissions.failures.containsKey(d.id)
        ? AppFormCardState.failed
        : AppFormCardState.waiting;
  }

  bool isInvalidFailure(FormCardData d) =>
      submissions.failures[d.id] == SubmissionRepository.invalidReason;

  bool isDraft(FormCardData d) => submissions.drafts.containsKey(d.id);

  /// A refused record is kept and waits for the person.
  String? stripLabelOf(FormCardData d) {
    if (isDraft(d)) return 'Draft';
    return isInvalidFailure(d) && stateOf(d) == AppFormCardState.failed
        ? 'Needs your attention'
        : null;
  }

  String? noteOf(FormCardData d) {
    if (!isDraft(d)) return null;
    return connectivity.state.value == AppConnectivity.online
        ? 'Connection is back. Open to finish and send'
        : 'Waiting for connection to finish';
  }

  String problemOf(FormCardData d) => isInvalidFailure(d)
      ? 'Some answers need fixing. Tap to review and resend'
      : 'Not sent. Tap to retry';

  /// A draft is finished; a failed card is fixed or sent again; any other
  /// opens.
  void tap(FormCardData d, {bool isReceived = false}) {
    if (isReceived) return open(d, isReceived: true);
    if (isDraft(d)) return unawaited(editAndResend(d));
    if (stateOf(d) != AppFormCardState.failed) return open(d);
    if (isInvalidFailure(d)) {
      unawaited(editAndResend(d));
    } else {
      unawaited(submissions.retry(d.id));
    }
  }

  Future<void> editAndResend(FormCardData d) async {
    final pending = await submissions.pendingFor(d.id);
    if (pending == null) return;
    await Get.toNamed(
      AppRoutes.form,
      arguments: FormLaunch(
        name: pending.name,
        scope: pending.scope,
        caption: pending.caption,
        mode: FormMode.resend,
        convId: null,
        submissionId: d.id,
        savedValues: pending.values,
        errorDetails: pending.errors,
        isDraft: pending.isDraft,
      ),
    );
  }

  Future<void> discard(FormCardData d) => submissions.discardPending(d.id);

  Future<void> edit(FormCardData d) async {
    final saved = submissions.submissionById(d.id);
    if (saved == null) return;
    await Get.toNamed(
      AppRoutes.form,
      arguments: FormLaunch.forSubmission(
        d,
        saved,
        me: me,
        scope: submissions.definitions[d.structure]?.scope ?? '',
      ),
    );
  }

  @override
  void onClose() {
    prompt.dispose();
    _submissionsWorker?.dispose();
    _definitionsWorker?.dispose();
    _loadedWorker?.dispose();
    _failuresWorker?.dispose();
    _draftsWorker?.dispose();
    _receivedWorker?.dispose();
    _workspaceStateWorker?.dispose();
    _connectivityWorker?.dispose();
    for (final c in _details.values) {
      c.onClose();
    }
    _noticeWorker?.dispose();
    _noticeTimer?.cancel();
    for (final w in _noteWorkers) {
      w.dispose();
    }
    text.dispose();
    focus.dispose();
    picker.onClose();
    super.onClose();
  }
}
