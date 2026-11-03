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
  });

  final SubmissionRepository submissions;
  final SessionStore store;
  final ConnectivityService connectivity;
  final FormOptionsRepository formOptions;
  final HomeShellController? shell;
  final CommandRepository commands;
  final MessageRepository messages;

  static const placeholder = 'Type # for commands or @name to message…';
  static const nudgeText =
      'Start with # for commands or @name to message someone.';

  final text = TextEditingController();
  final focus = FocusNode();
  final length = 0.obs;

  /// The gentle line under the field for text that is sent nowhere.
  final nudge = RxnString();
  late final prompt = CommandPrompt(commands);
  final _notes = <WorkspaceNote>[];
  final _noteWorkers = <Worker>[];
  int _noteSeq = 0;
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

  String get me => store.userId ?? SeedMessages.me;

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
    _apply();
    if (connectivity.state.value == AppConnectivity.online) {
      unawaited(submissions.syncFromServer());
    }
  }

  void _apply() {
    final mine =
        submissions.submissions
            .where((s) => s.byUser.toLowerCase() == me.toLowerCase())
            .toList()
          ..sort((a, b) => a.ts.compareTo(b.ts));
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
    viewState.value = submissions.isLoaded.value
        ? AppViewState.content
        : AppViewState.loading;
  }

  // ---- composing -----------------------------------------------------------

  void onChanged(String value) {
    length.value = value.characters.length;
    nudge.value = null;
    prompt.onTextChanged(value);
  }

  /// Puts `#name ` into the field; nothing runs until send.
  void pickCommand(HashCommand command) {
    final value = '#${command.name} ';
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
    if (_isRunning) return;
    final body = text.text.trim();
    if (body.isEmpty) return;
    nudge.value = null;
    final at = RegExp(r'^@(\S+)\s+([\s\S]+)$').firstMatch(body);
    if (!CommandRepository.isHashLine(body) && at == null) {
      nudge.value = body.startsWith('@') && !body.contains(RegExp(r'\s'))
          ? 'Add a message after $body.'
          : nudgeText;
      return;
    }
    _isRunning = true;
    try {
      final result = CommandRepository.isHashLine(body)
          ? await commands.run(body)
          : await commands.sendDirect(at!.group(1)!, at.group(2)!.trim());
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

  void open(FormCardData d) => Get.toNamed(AppRoutes.submissionDetailOf(d.id));

  bool canEdit(FormCardData d) => d.canEdit(me) || d.canFix(me);

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
  void tap(FormCardData d) {
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
    _submissionsWorker?.dispose();
    _definitionsWorker?.dispose();
    _loadedWorker?.dispose();
    _failuresWorker?.dispose();
    _draftsWorker?.dispose();
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
