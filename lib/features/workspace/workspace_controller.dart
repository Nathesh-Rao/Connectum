import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_messages.dart';
import 'package:connectum/core/log/log.dart';
import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/tour/tour.dart';
import 'package:connectum/core/utils/utils.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/models/models.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import 'package:connectum/features/commands/commands.dart';
import 'package:connectum/features/conversation/conversation.dart';
import 'package:connectum/features/forms/forms.dart';
import 'package:connectum/features/home_shell/home_shell.dart';
import 'package:connectum/features/tickets/tickets.dart';
import 'workspace_tour.dart';
import '../../core/debug/seed_ui.dart';
import '../../core/routes/app_routes.dart';
import '../../core/selection/message_selection.dart';
import '../../core/selection/selection_rules.dart';
import '../../data/commands/command_line.dart';
import '../../data/commands/command_reply.dart';

import '../../data/session_store.dart';
import 'models/pinned_line.dart';
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
    required this.marks,
    required this.workspace,
    required this.tickets,
    required this.newTicketDetail,
    this.smartView,
    this.tour,
    this.commandsTour,
  });

  final SubmissionRepository submissions;
  final SessionStore store;
  final ConnectivityService connectivity;
  final FormOptionsRepository formOptions;
  final HomeShellController? shell;
  final CommandRepository commands;
  final MessageRepository messages;
  final MarksRepository marks;
  final WorkspaceRepository workspace;
  final TicketRepository tickets;
  final SmartViewRepository? smartView;

  /// The first-run tours of this screen; null where tours are not set up.
  final WorkspaceTour? tour;
  final CommandsTour? commandsTour;
  late final TourTrigger _tourTrigger = TourTrigger(
    canTry: _canTryTour,
    start: _startTour,
  );
  final _tourWorkers = <Worker>[];
  final TicketDetailController Function(int id) newTicketDetail;

  /// The latest own records shown as cards (the web's `MWS_CARDS`); older
  /// ones are in My submissions.
  static const ownCards = 100;

  static const placeholder = 'Note, #command or @name';
  static const tooLongText =
      'A note can have at most ${SelfConversation.maxLength} characters.';

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
  Worker? _selfWorker;
  StreamSubscription<String>? _noticesSub;
  StreamSubscription<String>? _marksNoticesSub;

  /// My notes kept on the server, read from SQLite (shown with no network).
  final selfNotes = <Message>[].obs;
  final _details = <int, TicketDetailController>{};

  String get me => store.userId ?? SeedMessages.me;

  void openTasks() => Get.toNamed(AppRoutes.tasks);

  /// The existing encryption setup (devices and recovery).
  void openEncryptionSetup() => Get.toNamed(AppRoutes.security);

  /// Notes written before this phone was set up that it cannot open yet.
  bool get hasLockedNotes =>
      rows.any((r) => r.message?.unreadableCode == 'not_for_this_device');

  /// The Inbox with its Approvals pane open.
  void openApprovals() => shell?.openInbox(approvals: true);

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
    if (tour != null) {
      _tourWorkers.add(ever(viewState, (_) => _tourTrigger.schedule()));
      _tourWorkers.add(ever(selection.ids, (_) => _tourTrigger.schedule()));
    }
    final cmdTour = commandsTour;
    if (cmdTour != null) {
      _tourWorkers.add(ever(prompt.query, (_) => cmdTour.onListChanged()));
      _tourWorkers.add(ever(prompt.command, (_) => cmdTour.onListChanged()));
    }
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
    _noticesSub = messages.notices.listen(
      _say,
      onError: streamOnError('workspace_controller'),
    );
    _marksNoticesSub = marks.notices.listen(
      _say,
      onError: streamOnError('workspace_controller'),
    );
    _apply();
    fireAndLog('workspace_controller', _openNotes);
    if (connectivity.state.value == AppConnectivity.online) {
      workspace.request(now: true);
    }
  }

  /// Reads the stored notes first; the network fills them in the background.
  Future<void> _openNotes() async {
    if (SeedUi.isActive) return;
    try {
      final list = await messages.openSelf();
      selfNotes.assignAll(list);
      _selfWorker = ever(list, (items) {
        selfNotes.assignAll(items);
        _apply();
      });
      _apply();
      await marks.open();
    } catch (e, st) {
      AppLog.e('workspace_controller', e, st, 'open notes');
    }
  }

  /// The note a reply points to, when it is loaded.
  Message? originalOf(Message m) => m.replyTo == null
      ? null
      : selfNotes.where((n) => n.msgId == m.replyTo).firstOrNull;

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
      for (final m in selfNotes)
        if (!m.isDeleted) (ts: m.ts, row: WorkspaceRow.message(m)),
    ];
    // Same time keeps the order the rows were added (a pending note after the
    // one before it).
    final order = {for (var i = 0; i < entries.length; i++) entries[i].row: i};
    entries.sort((a, b) {
      final byTime = a.ts.compareTo(b.ts);
      return byTime != 0 ? byTime : order[a.row]!.compareTo(order[b.row]!);
    });
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
    selection.prune({
      for (final r in asc)
        if (r.message != null) r.message!.msgId,
    });
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
    commandsTour?.onTyped();
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

  /// `#` lines run as commands (not stored), `@name text` is a direct
  /// message; any other text is a note of mine, kept on the server.
  Future<void> send() async {
    if (_isRunning || runner.isRunning.value) return;
    final body = text.text.trim();
    if (body.isEmpty) return;
    nudge.value = null;
    final edited = editing.value;
    if (edited != null) {
      await _saveEdit(edited, body);
      return;
    }
    final at = RegExp(r'^@(\S+)\s+([\s\S]+)$').firstMatch(body);
    final isCommand =
        CommandRepository.isHashLine(body) || CommandLine.isEscape(body);
    if (!isCommand && at == null) {
      if (body.startsWith('@') && !body.contains(RegExp(r'\s'))) {
        nudge.value = 'Add a message after $body.';
        return;
      }
      await _sendNote(body);
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
          fireAndLog('workspace_controller', () => _watch(note, result.cid));
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

  /// The text becomes a note: it shows at once as pending and goes out
  /// through the outbox (offline too). It stays in the field when refused.
  Future<void> _sendNote(String body) async {
    if (body.length > SelfConversation.maxLength) {
      nudge.value = tooLongText;
      return;
    }
    _isRunning = true;
    try {
      final quoted = replying.value;
      final result = await messages.sendText(
        SelfConversation.id,
        body,
        replyTo: quoted?.msgId,
      );
      switch (result) {
        case SendResult.queued:
          replying.value = null;
          text.clear();
          length.value = 0;
          prompt.close();
        case SendResult.tooLong:
          nudge.value = tooLongText;
        case SendResult.blocked:
          nudge.value = messages.lastBlock;
        case SendResult.invalid:
          if (quoted != null) {
            replying.value = null;
            nudge.value = 'That note is no longer there.';
          }
        case SendResult.noSession:
          break;
      }
    } finally {
      _isRunning = false;
    }
  }

  // ---- selection -----------------------------------------------------------

  /// The notes picked with a long press, then taps. Notes take no reaction.
  final selection = MessageSelection();

  /// The selected notes, oldest first.
  List<Message> get selectedNotes => [
    for (final r in rows)
      if (r.message != null && selection.isSelected(r.message!.msgId))
        r.message!,
  ]..sort((a, b) => a.ts.compareTo(b.ts));

  bool isUnsent(Message m) => m.isLocalTemp || m.status == MessageStatus.failed;

  /// What one note allows from the selection bar. A note that was not sent
  /// only keeps retry (when it failed) and remove.
  SelectionTarget targetOf(Message m) {
    final isSent = !isUnsent(m);
    return SelectionTarget(
      id: m.msgId,
      canReply: isSent && canReplyNote(m),
      canStar: isSent && canMarkNote(m),
      canPin: isSent && canMarkNote(m),
      canEdit: isSent && canEditNote(m),
      canCopy: isSent && canCopyNote(m),
      canDelete: isSent ? canDeleteNote(m) : true,
      canRetry: m.status == MessageStatus.failed,
    );
  }

  /// Saves every selected note, or takes them all off the saved list when
  /// each one is saved already.
  Future<void> toggleSaveMany(List<Message> list) async {
    final isAllSaved = list.every(isSaved);
    for (final m in list) {
      if (isSaved(m) == isAllSaved) await toggleSave(m);
    }
  }

  Future<void> copyMany(List<Message> list) => Clipboard.setData(
    ClipboardData(text: list.map((m) => m.text).join('\n')),
  );

  Future<void> deleteMany(List<Message> list) async {
    for (final m in list) {
      await deleteNote(m);
    }
  }

  // ---- edit, reply, delete a note ------------------------------------------

  /// The note being edited (the composer shows its text and an "Editing note"
  /// bar), or null.
  final editing = Rxn<Message>();

  /// The note a new note quotes (the composer shows it above the field).
  final replying = Rxn<Message>();

  bool canEditNote(Message m) => messages.canEditNote(m);

  bool canReplyNote(Message m) => messages.canReplyToNote(m);

  /// A sent note can be deleted at any age; one that never reached the server
  /// keeps its retry and remove actions instead.
  bool canDeleteNote(Message m) =>
      m.isMine && !m.isLocalTemp && m.status != MessageStatus.failed;

  bool canCopyNote(Message m) =>
      !m.isEncryptedUnsupported && AttachmentTag.parse(m.text) == null;

  // ---- save and pin a note -------------------------------------------------

  /// The thread's scroll, so a pinned or saved note can be shown.
  final scroll = ScrollController();

  /// The note that flashes after it was shown from the pinned bar or the
  /// saved list.
  final flashId = RxnString();

  /// The list of every pinned note is open under the bar.
  final isPinListOpen = false.obs;
  final _noteKeys = <String, GlobalKey>{};
  Timer? _flashTimer;

  static const olderNoteText =
      'That note is older than what is loaded. Scroll up to find it.';

  GlobalKey keyForNote(String id) => _noteKeys.putIfAbsent(id, GlobalKey.new);

  /// A sent note (it has a server id) can be saved or pinned.
  bool canMarkNote(Message m) =>
      m.isMine &&
      !m.isLocalTemp &&
      numericId(m.msgId) != null &&
      m.status != MessageStatus.failed &&
      !m.isDeleted &&
      m.kind == 'chat';

  bool isSaved(Message m) => marks.isSaved(m.msgId);

  bool isPinned(Message m) => marks.isPinned(m.msgId);

  Future<void> toggleSave(Message m) =>
      safeCall<void>('workspace_controller', () => marks.toggleSave(m.msgId));

  Future<void> togglePin(Message m) =>
      safeCall<void>('workspace_controller', () => marks.togglePin(m.msgId));

  Future<void> unpinNote(String id) =>
      safeCall<void>('workspace_controller', () => marks.unpin(id));

  void togglePinList() => isPinListOpen.value = !isPinListOpen.value;

  /// The words of a note in one line (the bar, the saved list).
  String noteLine(Message m) {
    if (m.isEncryptedUnsupported) return 'Encrypted note';
    if (AttachmentTag.parse(m.text) != null) return 'Attachment';
    final line = m.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return line.isEmpty ? 'Note' : line;
  }

  /// The pinned notes, newest pin first. A note on the phone gives its own
  /// words; one that is not loaded gives the server's (an envelope shows as
  /// "Encrypted note"). A note deleted here is left out.
  List<PinnedLine> pinLines() {
    final notes = {for (final n in selfNotes) n.msgId: n};
    final out = <PinnedLine>[];
    for (final p in marks.pinned) {
      final note = notes[p.msgId];
      if (note != null && note.isDeleted) continue;
      out.add(PinnedLine(id: p.msgId, text: _pinWords(note, p.preview)));
    }
    return out;
  }

  String _pinWords(Message? note, String preview) {
    if (note != null) return noteLine(note);
    if (preview.isEmpty) return 'Encrypted note';
    if (AttachmentTag.parse(preview) != null) return 'Attachment';
    return preview.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// The notes I saved that are on the phone, newest first.
  List<Message> savedNotes() => [
    for (final m in selfNotes)
      if (!m.isDeleted && marks.isSaved(m.msgId)) m,
  ]..sort((a, b) => b.ts.compareTo(a.ts));

  /// Scrolls to the note and flashes it. A note older than what is loaded
  /// says so.
  Future<void> openNote(String id) async {
    isPinListOpen.value = false;
    final target = rows.firstWhereOrNull((r) => r.message?.msgId == id);
    if (target == null) {
      _say(olderNoteText);
      return;
    }
    final key = keyForNote(id);
    if (key.currentContext == null &&
        scroll.hasClients &&
        scroll.position.pixels > 0) {
      scroll.jumpTo(0);
      await WidgetsBinding.instance.endOfFrame;
    }
    for (var tries = 0; tries < 60; tries++) {
      final ctx = key.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.4,
          duration: AppDurations.base,
          curve: AppCurves.out,
        );
        flashId.value = id;
        _flashTimer?.cancel();
        _flashTimer = Timer(AppDurations.slow * 3, () => flashId.value = null);
        return;
      }
      if (!scroll.hasClients) return;
      final p = scroll.position;
      if (p.pixels >= p.maxScrollExtent) return;
      scroll.jumpTo(
        math.min(p.maxScrollExtent, p.pixels + p.viewportDimension * 0.8),
      );
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  void startEdit(Message m) {
    if (!canEditNote(m)) return;
    replying.value = null;
    editing.value = m;
    _setText(m.text);
  }

  void cancelEdit() {
    if (editing.value == null) return;
    editing.value = null;
    text.clear();
    onChanged('');
  }

  void startReply(Message m) {
    if (!canReplyNote(m)) return;
    cancelEdit();
    replying.value = m;
    focus.requestFocus();
  }

  void cancelReply() => replying.value = null;

  Future<void> copyNote(Message m) =>
      Clipboard.setData(ClipboardData(text: m.text));

  /// Removes the note at once; it is sent to the server by the outbox.
  Future<void> deleteNote(Message m) async {
    if (editing.value?.msgId == m.msgId) cancelEdit();
    if (replying.value?.msgId == m.msgId) cancelReply();
    await safeCall<void>('workspace_controller', () async {
      await messages.deleteMessage(m);
    });
  }

  Future<void> _saveEdit(Message note, String body) async {
    if (body.length > SelfConversation.maxLength) {
      nudge.value = tooLongText;
      return;
    }
    _isRunning = true;
    try {
      final isDone = await messages.editText(note.msgId, body);
      if (isDone) {
        editing.value = null;
        text.clear();
        length.value = 0;
        prompt.close();
      } else if (messages.lastBlock.isNotEmpty) {
        nudge.value = messages.lastBlock;
        messages.lastBlock = '';
      }
    } finally {
      _isRunning = false;
    }
  }

  /// Tap on a note that was not sent.
  void retryNote(Message note) {
    fireAndLog('workspace_controller', () => messages.retry(note.msgId));
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

  /// A record or ticket opens the record screen, mine or received; a plain
  /// submission opens its detail.
  void open(FormCardData d, {bool isReceived = false}) {
    final route = CardDestination.of(d);
    if (route != null) Get.toNamed(route);
  }

  /// The record menu of a card opened: `record.actions`, read once (cached
  /// 60 s), never while cards are drawn. Null for a card that is no record.
  int? recordIdOf(FormCardData d) => RecordCardRule.of(d).id;

  void openRecordMenu(FormCardData d) {
    final id = recordIdOf(d);
    if (id != null)
      fireAndLog('workspace_controller', () => tickets.ensureMenu(id));
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

  /// The form behind a card, when its definition is stored.
  FormDefinition? formOf(FormCardData d) =>
      submissions.definitions[d.structure];

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
      canDelete: isSettled && d.canDelete(me, form: formOf(d)),
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
    if (!d.canDelete(me, form: formOf(d)) || !await confirm()) return;
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
    if (isDraft(d))
      return fireAndLog('workspace_controller', () => editAndResend(d));
    if (stateOf(d) != AppFormCardState.failed) return open(d);
    if (isInvalidFailure(d)) {
      fireAndLog('workspace_controller', () => editAndResend(d));
    } else {
      fireAndLog('workspace_controller', () => submissions.retry(d.id));
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

  // ---- first-run tour -----------------------------------------------------

  bool _canTryTour() =>
      tour != null &&
      !isClosed &&
      viewState.value == AppViewState.content &&
      !selection.isActive;

  Future<TourStart> _startTour() async {
    final tour = this.tour;
    if (tour == null || isClosed) return TourStart.failed;
    await WidgetsBinding.instance.endOfFrame;
    if (isClosed) return TourStart.failed;
    final notes = [
      for (final r in rows)
        if (r.message != null) r.message!,
    ];
    final hold = WorkspaceTour.holdNote(notes);
    return tour.start(
      hasNote: hold != null,
      holdId: hold?.msgId,
      target: hold == null ? null : targetOf(hold),
      select: selection.onLongPress,
      clear: selection.clear,
    );
  }

  bool get isTourActive => tour?.service.isActive.value ?? false;

  /// Back while a tour shows ends the tour and stays on the screen.
  void cancelTour() => tour?.service.cancel();

  @override
  void onClose() {
    _tourTrigger.dispose();
    for (final w in _tourWorkers) {
      w.dispose();
    }
    tour?.cancel();
    commandsTour?.dispose();
    prompt.dispose();
    _submissionsWorker?.dispose();
    _definitionsWorker?.dispose();
    _loadedWorker?.dispose();
    _failuresWorker?.dispose();
    _draftsWorker?.dispose();
    _receivedWorker?.dispose();
    _workspaceStateWorker?.dispose();
    _connectivityWorker?.dispose();
    _selfWorker?.dispose();
    _noticesSub?.cancel();
    _marksNoticesSub?.cancel();
    _flashTimer?.cancel();
    selection.clear();
    scroll.dispose();
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
