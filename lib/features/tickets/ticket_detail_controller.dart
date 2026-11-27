import 'dart:async';

import 'package:dio/dio.dart';
import 'package:get/get.dart';

import '../../core/log/app_log.dart';
import '../../core/routes/app_routes.dart';
import '../../core/widgets/app_notice_card.dart';
import '../../core/widgets/app_notices.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/models/approval.dart';
import '../../data/models/ids.dart';
import '../../data/models/record_state.dart';
import '../../data/models/ticket.dart';
import '../../data/records/record_commands.dart';
import '../../data/repositories/approval_repository.dart';
import '../../data/repositories/attachment_repository.dart';
import '../../data/repositories/form_file_repository.dart';
import '../../data/repositories/inbox_field_kinds.dart';
import '../../data/repositories/inbox_repository.dart';
import '../../data/repositories/sv_file_repository.dart';
import '../../data/smart_view/sv_file.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../data/socket/call_problem.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';
import '../forms/models/field_input.dart';
import '../forms/models/form_launch.dart';
import '../inbox/models/approval_rules.dart';
import '../inbox/models/inbox_card_rows.dart';
import '../inbox/models/inbox_field_kind.dart';
import '../inbox/models/inbox_record_tone.dart';
import '../inbox/models/inbox_row.dart';
import '../inbox/widgets/inbox_card_frame.dart';
import '../smart_view/sv_file_preview_controller.dart';
import '../tasks/task_people_controller.dart';
import '../../data/models/group_add.dart';
import '../chats/models/chat_person.dart';
import 'models/record_kind.dart';
import 'models/ticket_detail_row.dart';
import 'models/ticket_input.dart';
import 'models/ticket_rows.dart';
import 'ticket_action_form.dart';
import 'tickets_texts.dart';
import '../../core/log/safe.dart';

/// How an action ended, for the sheet that asked.
enum ActionResult { done, failed, gone }

/// One record in full: its header, values, the actions this person may take
/// (`record.actions`) and its history. The server judges who may do what;
/// this shows its words when an action is refused and reads again after every
/// action (only a patch comes back) and on every record event.
class TicketDetailController extends GetxController {
  TicketDetailController({
    required this.ticketId,
    required this.tickets,
    required this.files,
    required this.connectivity,
    this.inbox,
    this.approvals,
    this.fieldKinds,
    this.svFiles,
    this.busyDelay = const Duration(seconds: 2),
    this.coolDown = const Duration(seconds: 3),
  });

  final int ticketId;
  final TicketRepository tickets;
  final FormFileRepository files;
  final ConnectivityService connectivity;

  /// `record.card` (`fileMeta:2`) and the people cards; null: the screen
  /// shows the values `submission.get` gave, files as "n files".
  final InboxRepository? inbox;

  /// The requests of the person, for the approval of a record.
  final ApprovalRepository? approvals;
  final InboxFieldKinds? fieldKinds;

  /// Opens a file in the preview; null: file chips stay plain.
  final SvFileRepository? svFiles;

  /// `busy`: the one automatic retry waits this long.
  final Duration busyDelay;

  /// `rate_limited` (no `retryAfter`): the buttons wait this long.
  final Duration coolDown;

  static const maxFiles = RecordLimits.maxFiles;

  final ticket = Rxn<Ticket>();
  final state = Rxn<RecordState>();
  final viewState = AppViewState.loading.obs;

  /// The record is gone (not found, or this person may no longer see it).
  final isGone = false.obs;

  /// The record opens but `record.actions` is `not_found` (an approver of an
  /// open stage, a notified person): details and history, no actions.
  final isReadOnly = false.obs;

  /// The list showed this record but `submission.get` refuses it (a person who
  /// sees every record of the form): the list row, a calm notice, no history.
  final isUnopenable = false.obs;

  /// The record as the Inbox card reads it (`record.card`, `fileMeta:2`):
  /// labels of choices, file details, the form's field names.
  final card = Rxn<InboxRow>();

  final history = Rxn<RecordHistory>();
  final historyState = AppViewState.loading.obs;

  /// An action is in flight: no second one starts.
  final isBusy = false.obs;

  /// `rate_limited`: actions wait a little.
  final isCooling = false.obs;

  StreamSubscription<void>? _refreshes;
  int _seq = 0;
  bool _isReading = false;
  bool _wantsAgain = false;

  String get me => tickets.me;

  /// The menu of `record.actions`: `send` and `status`, each with its own
  /// enabled flag and `why`.
  List<RecordActionItem> get items => state.value?.items ?? const [];

  RecordActionItem? item(String id) => state.value?.item(id);

  /// The status as the screen shows it: the server's, else the first one.
  String get status => state.value?.status ?? ticket.value?.status ?? '';

  /// A real person to show for the holder: the claimants when it is shared.
  List<String> get holders {
    final s = state.value;
    if (s == null) return [ticket.value?.withWhom ?? ''];
    if (s.claimants.isNotEmpty) return s.claimants;
    return [s.holder.isNotEmpty ? s.holder : ticket.value?.withWhom ?? ''];
  }

  /// Edit is the author's own form screen (`submissions.update`); the server
  /// refuses it while the record waits for approval or is approved.
  bool get canEdit {
    final t = ticket.value;
    return t != null && !t.isAwaitingApproval && t.isRaisedBy(me);
  }

  // ---- what the screen shows -------------------------------------------------

  /// The request (`req.*`) that decides this record, when the person has it.
  Approval? get approval {
    final list = approvals?.all;
    if (list == null) return null;
    Approval? found;
    for (final a in list) {
      if (a.submissionId != ticketId || !a.isSubmission) continue;
      if (a.isPending) return a;
      found ??= a;
    }
    return found;
  }

  RecordKind get kind {
    final t = ticket.value;
    if (t == null) return RecordKind.submission;
    return RecordKind.of(
      t,
      hasRequest: approval != null,
      hasStatus: _hasStatusTable,
    );
  }

  /// The form has a status table: its structure says so, or the server
  /// lists statuses for this record.
  bool get _hasStatusTable =>
      (ticket.value?.hasStatus ?? false) ||
      (state.value?.statuses.isNotEmpty ?? false) ||
      (card.value?.statusField.isNotEmpty ?? false);

  /// The approval answers this person may give (the server stays the judge).
  List<ApprovalAction> get approvalActions {
    final a = approval;
    return a == null ? const [] : ApprovalRules.actionsFor(a);
  }

  /// The status as the strip says it: the live status, else the card's chip,
  /// else the record's own words.
  String get statusText {
    final live = state.value?.status ?? '';
    if (live.trim().isNotEmpty) return live;
    final t = ticket.value;
    final c = card.value;
    if (c != null && c.chipText(null).isNotEmpty) return c.chipText(null);
    if (t == null) return '';
    if (t.isAwaitingApproval) return 'Waiting for approval';
    if (t.status.isNotEmpty) return t.status;
    return switch (t.recordStatus.toLowerCase()) {
      'approved' => 'Approved',
      'rejected' => 'Declined',
      _ => '',
    };
  }

  /// The colour and icon of the strip, by the card's own rule.
  InboxCardStatus get cardStatus {
    final t = ticket.value;
    final c = card.value;
    if (c != null) return InboxCardStatus.of(c.stateFor(me));
    if (t == null) return InboxCardStatus.closed;
    final isFinal = state.value?.isFinal ?? t.isFinal;
    return InboxCardStatus.of(
      recordStateOf(
        isFinal: isFinal || (t.recordStatus == 'approved' && !_hasStatusTable),
        isWaiting: t.isAwaitingApproval,
        isDeclined: t.recordStatus.toLowerCase() == 'rejected',
        statusText: statusText,
        holder: holders.join(', '),
        me: me,
      ),
    );
  }

  /// The person the header is about: who raised it.
  String get raiser => ticket.value?.by ?? card.value?.raiser ?? '';

  String nameOfUser(String user) {
    inbox?.cardRevision.value;
    final u = user.replaceFirst('@', '').trim();
    if (tickets.isMe(u)) return TicketsTexts.youCapital;
    final name = inbox?.cardOf(u)?.name.trim() ?? '';
    return name.isNotEmpty ? name : tickets.nameOf(u);
  }

  String? pictureOf(String user) {
    inbox?.cardRevision.value;
    final a = inbox?.cardOf(user.replaceFirst('@', '').trim())?.avatar ?? '';
    return a.isEmpty ? null : a;
  }

  String? fieldTypeOf(String field) {
    final c = card.value;
    return c == null ? null : fieldKinds?.typeOf(c.formId, field);
  }

  /// Every answer as a typed line, in the form's order: from `record.card`
  /// (labels, files with details), else from the values `submission.get`
  /// gave.
  List<InboxCardRow> get rows {
    final c = card.value;
    if (c != null) return inboxCardRows(c, typeOf: fieldTypeOf);
    final t = ticket.value;
    if (t == null) return const [];
    return [
      for (final r in ticketValueRows(t, status: state.value?.status ?? ''))
        _plainRow(r),
    ];
  }

  static InboxCardRow _plainRow(TicketDetailRow r) => InboxCardRow(
    name: r.label,
    value: r.value,
    kind: InboxFieldKind.of(name: r.label, key: '', raw: r.value),
  );

  bool get hasFiles => svFiles != null;

  /// File lines whose chips are all shown ("+N more"), by field name.
  final openFiles = <String>{}.obs;

  void toggleFiles(String name) {
    if (!openFiles.remove(name)) openFiles.add(name);
  }

  SvFilePreviewController newFilePreview(List<SvFile> list, int index) =>
      SvFilePreviewController(files: list, repo: svFiles!, index: index);

  /// People to look up: who raised it, who holds it, and the people in the
  /// answers.
  Set<String> get _peopleNames => {
    if (raiser.isNotEmpty) raiser,
    for (final h in holders)
      if (h.isNotEmpty) h,
    for (final r in rows)
      if (r.kind == InboxFieldKind.person) ...peopleOf(r.value),
  };

  /// "@a, b" as usernames or names.
  static List<String> peopleOf(String value) => [
    for (final p in value.split(','))
      if (p.replaceFirst('@', '').trim().isNotEmpty)
        p.replaceFirst('@', '').trim(),
  ];

  @override
  void onInit() {
    super.onInit();
    final known = tickets.known(ticketId);
    if (known != null) {
      ticket.value = known;
      state.value = tickets.stateOf(ticketId);
      viewState.value = AppViewState.content;
    }
    _refreshes = tickets.refreshes.listen(
      (_) => fireAndLog('ticket_detail_controller', () => reload()),
      onError: streamOnError('ticket_detail_controller'),
    );
    fireAndLog(
      'ticket_detail_controller',
      () => reload(isQuiet: known != null),
    );
  }

  @override
  void onClose() {
    _refreshes?.cancel();
    super.onClose();
  }

  // ---- reading ---------------------------------------------------------------

  /// The record, its actions and its history again; one read at a time (an
  /// event during a read asks for one more after it). [isQuiet]: what is
  /// shown stays when a read fails.
  Future<void> reload({bool isQuiet = true}) async {
    if (_isReading) {
      _wantsAgain = true;
      return;
    }
    _isReading = true;
    try {
      do {
        _wantsAgain = false;
        final seq = ++_seq;
        if (ticket.value == null) viewState.value = AppViewState.loading;
        await Future.wait([
          _readRecord(seq, isQuiet),
          _readHistory(seq),
          _readCard(seq),
          _readApprovals(),
        ]);
        final names = _peopleNames;
        if (names.isNotEmpty) {
          await inbox?.loadCards(names.map((n) => n.toLowerCase()));
        }
      } while (_wantsAgain);
    } finally {
      _isReading = false;
    }
  }

  Future<void> _readRecord(int seq, bool isQuiet) async {
    try {
      final detail = await tickets.get(ticketId);
      if (seq != _seq) return;
      ticket.value = tickets.known(ticketId) ?? detail.ticket;
      state.value = detail.state;
      isReadOnly.value = detail.isReadOnly;
      isUnopenable.value = detail.isUnopenable;
      isGone.value = false;
      viewState.value = AppViewState.content;
    } on SocketCallError catch (e) {
      if (seq != _seq) return;
      if (e.code == 'not_found') {
        isGone.value = true;
        viewState.value = AppViewState.empty;
        return;
      }
      if (ticket.value != null) {
        viewState.value = AppViewState.content;
        if (!isQuiet) _tell(CallProblem.of(e));
      } else {
        viewState.value = connectivity.state.value == AppConnectivity.online
            ? AppViewState.error
            : AppViewState.offline;
      }
    }
  }

  /// `record.card` with `fileMeta:2`: the labels and the file details the
  /// card shows. A refusal keeps the plain values; it is not an error here.
  Future<void> _readCard(int seq) async {
    final repo = inbox;
    if (repo == null) return;
    try {
      final row = await repo.loadCard(ticketId);
      if (seq != _seq) return;
      card.value = row;
    } on SocketCallError catch (e) {
      AppLog.w('ticket_detail_controller', 'record.card ${e.code}');
    }
  }

  /// The requests, once, so a record that waits for this person shows its
  /// answer buttons.
  Future<void> _readApprovals() async {
    final repo = approvals;
    if (repo == null || repo.hasRead.value) return;
    try {
      await repo.start();
    } on SocketCallError catch (e) {
      AppLog.w('ticket_detail_controller', 'approvals ${e.code}');
    }
  }

  /// One answer to the request of this record. True when the server took it;
  /// a refusal shows the server's own words.
  Future<bool> respond(
    ApprovalAction action, {
    String reason = '',
    String comment = '',
    bool allowResubmit = false,
  }) async {
    final a = approval;
    final repo = approvals;
    if (a == null || repo == null || isBusy.value) return false;
    final answer = ApprovalRules.answerFor(
      a,
      action,
      reason: reason,
      comment: comment,
      allowResubmit: allowResubmit,
    );
    if (answer == null) return false;
    isBusy.value = true;
    try {
      await repo.respond(
        a.id,
        action.wire,
        reason: answer.reason,
        comment: answer.comment,
        allowResubmit: answer.allowResubmit,
      );
      fireAndLog('ticket_detail_controller', () => reload());
      tickets.scheduleRefresh();
      return true;
    } on SocketCallError catch (e) {
      final problem = CallProblem.of(e, isWrite: true);
      AppNotices.error(problem.text);
      if (problem.shouldRefresh) {
        fireAndLog('ticket_detail_controller', () => reload());
      }
      return false;
    } finally {
      isBusy.value = false;
    }
  }

  Future<void> _readHistory(int seq) async {
    try {
      final read = await tickets.history(ticketId);
      if (seq != _seq) return;
      history.value = read;
      final t = tickets.known(ticketId);
      if (t != null) ticket.value = t;
      historyState.value = AppViewState.content;
    } on SocketCallError catch (e) {
      if (seq != _seq) return;
      if (e.code == 'not_found') {
        // Not allowed to read it (a BE gap for some roles): quiet, no retry.
        history.value = null;
        historyState.value = AppViewState.empty;
        return;
      }
      if (history.value == null) historyState.value = AppViewState.error;
    }
  }

  // ---- actions ---------------------------------------------------------------

  TicketActionForm newForm(String kind) {
    final s = state.value;
    if (s == null) {
      throw StateError('The record has not been read yet.');
    }
    return TicketActionForm(kind, state: s);
  }

  /// Sends the form's action. The sheet closes on [ActionResult.done] and
  /// [ActionResult.gone]. A failure is told with the server's text and what
  /// was typed stays in the form.
  Future<ActionResult> submit(TicketActionForm form) async {
    if (isBusy.value || isCooling.value) return ActionResult.failed;
    final offered = item(form.kind);
    if (offered == null || !offered.isEnabled) {
      form.error.value = offered?.why.isNotEmpty == true
          ? offered!.why
          : TicketsTexts.actionGone;
      return ActionResult.failed;
    }
    final problem = form.problem;
    if (problem != null) {
      form.error.value = problem;
      return ActionResult.failed;
    }
    form.error.value = null;
    isBusy.value = true;
    final requestId = form.requestId ??= newRequestId();
    final expected = (state.value ?? form.state).expected;
    try {
      while (true) {
        try {
          final patch = form.isStatus
              ? await tickets.setStatus(
                  RecordPayload.status(
                    id: ticketId,
                    input: form.statusInput,
                    requestId: requestId,
                    expected: expected,
                  ),
                )
              : await tickets.send(
                  RecordPayload.send(
                    id: ticketId,
                    input: form.sendInput,
                    requestId: requestId,
                    expected: expected,
                  ),
                );
          _succeed(form, patch);
          return ActionResult.done;
        } on SocketCallError catch (e) {
          final failure = CallProblem.of(e, isWrite: true);
          final outcome = TicketOutcome.of(failure);
          if (outcome.isSuccess) {
            _succeed(form, null);
            return ActionResult.done;
          }
          if (outcome.shouldRetryOnce && !form.hasRetriedBusy) {
            form.hasRetriedBusy = true;
            await Future<void>.delayed(busyDelay);
            continue;
          }
          return _failed(form, failure, outcome);
        }
      }
    } finally {
      isBusy.value = false;
    }
  }

  ActionResult _failed(
    TicketActionForm form,
    CallProblem failure,
    TicketOutcome outcome,
  ) {
    if (!outcome.shouldKeepRequestId) form.requestId = null;
    if (form.isStatus && failure.text.contains('100% completion is only')) {
      form.percentError.value = failure.text;
      form.error.value = null;
    } else {
      form.error.value = failure.text;
    }
    _tell(
      failure,
      retry: outcome.canRetry
          ? () => fireAndLog('ticket_detail_controller', () => submit(form))
          : null,
    );
    if (outcome.shouldBackOff) _coolDown();
    if (outcome.shouldLeave) {
      isGone.value = true;
      tickets.scheduleRefresh();
      return ActionResult.gone;
    }
    if (outcome.shouldReload)
      fireAndLog('ticket_detail_controller', () => _refreshForm(form));
    return ActionResult.failed;
  }

  /// After a stale or refused action: the record and its actions again, and
  /// the sheet follows them (required flags, statuses) with its input kept.
  Future<void> _refreshForm(TicketActionForm form) async {
    await reload();
    final s = state.value;
    if (s != null) form.state = s;
  }

  void _coolDown() {
    isCooling.value = true;
    Future<void>.delayed(coolDown, () => isCooling.value = false);
  }

  void _succeed(TicketActionForm form, RecordPatch? patch) {
    form.requestId = null;
    if (patch != null) {
      final next = tickets.applied(ticketId, patch);
      if (next != null) ticket.value = next;
    }
    final sentTo = form.isSend
        ? (form.person.value?.name ?? form.via.value)
        : null;
    AppNotices.success(
      TicketsTexts.done(
        status: patch?.status.isNotEmpty == true
            ? patch!.status
            : form.statusPick.value,
        sentTo: sentTo,
      ),
    );
    // Only a patch comes back: the record and its history are read again.
    fireAndLog('ticket_detail_controller', () => reload());
    tickets.scheduleRefresh();
  }

  /// A UUID v4 for one intent (well under 100 bytes).
  static String newRequestId() => newCid().substring(2);

  /// Leaves the record screen when the record is gone; a chat card that
  /// shares this controller stays where it is.
  void leave() {
    if (Get.currentRoute == AppRoutes.ticketOf(ticketId)) Get.back<void>();
  }

  void _tell(CallProblem problem, {void Function()? retry}) {
    AppNotices.show(
      problem.text,
      variant: retry != null || problem.kind == CallProblemKind.unknownOutcome
          ? AppNoticeVariant.warning
          : AppNoticeVariant.error,
      actionLabel: retry != null ? TicketsTexts.retry : null,
      onAction: retry,
    );
  }

  // ---- edit ------------------------------------------------------------------

  /// The form screen again, filled in with the record's values. The save goes
  /// through the outbox (`submissions.update`, one cid per save; it replaces
  /// every value); the record is read again when the screen closes and when
  /// the server's change event arrives.
  Future<void> edit() async {
    final t = ticket.value;
    if (t == null) return;
    await Get.toNamed(
      AppRoutes.form,
      arguments: FormLaunch(
        name: t.tstruct,
        scope: t.scope.isEmpty ? 'user' : t.scope,
        caption: t.caption,
        mode: FormMode.edit,
        submissionId: '${t.id}',
        savedValues: t.values,
      ),
    );
    fireAndLog('ticket_detail_controller', () => reload());
  }

  // ---- people and files ------------------------------------------------------

  /// The people this record can be sent to (`record.people`, searched by
  /// name; the sender and the holder are left out by the server).
  TaskPeopleController newPeople() => TaskPeopleController(
    null,
    source: (q) async {
      final rows = await tickets.people(ticketId, q: q);
      return GroupPeoplePage([
        for (final p in rows)
          ChatPerson(
            username: p.username,
            name: p.name,
            source: 'colleague',
            detail: p.designation,
          ),
      ]);
    },
  );

  void picked(TicketActionForm form, ChatPerson person) {
    form.via.value = SendInput.viaUser;
    form.person.value = RecordPerson(
      username: person.username,
      name: person.name,
      designation: person.detail,
    );
    tickets.rememberName(person.username, person.name);
  }

  Future<void> addFile(TicketActionForm form, AttachSource source) async {
    form.error.value = null;
    if (connectivity.state.value != AppConnectivity.online) {
      form.error.value = TicketsTexts.attachNeedsConnection;
      return;
    }
    if (form.files.length >= maxFiles) {
      form.error.value = TicketsTexts.attachMax;
      return;
    }
    final PickedAttachment? picked;
    try {
      picked = await files.pick(source);
    } on AttachmentException catch (e) {
      form.error.value = e.message;
      return;
    }
    if (picked == null) return;
    if (picked.bytes > RecordLimits.maxFileBytes) {
      form.error.value = TicketsTexts.fileTooLarge;
      return;
    }
    final item = FormFileItem(
      name: picked.name,
      size: picked.bytes,
      path: picked.path,
      mime: picked.mime,
    );
    form.files.add(item);
    fireAndLog('ticket_detail_controller', () => _upload(form, item));
  }

  Future<void> _upload(TicketActionForm form, FormFileItem item) async {
    item.state.value = FormFileState.uploading;
    item.error.value = null;
    item.progress.value = 0;
    try {
      final done = await files.upload(
        PickedAttachment(
          kind: 'file',
          path: item.path ?? '',
          name: item.name,
          mime: item.mime,
          bytes: item.size,
        ),
        onProgress: (p) => item.progress.value = p,
        cancel: item.cancel,
        deleteAfter: true,
      );
      if (!form.files.contains(item)) return;
      item.id = done.id;
      item.state.value = FormFileState.done;
    } on AttachmentException catch (e) {
      if (!form.files.contains(item)) return;
      item.error.value = e.message;
      item.state.value = FormFileState.failed;
    }
    form.files.refresh();
  }

  void retryFile(TicketActionForm form, FormFileItem item) {
    item.cancel = CancelToken();
    fireAndLog('ticket_detail_controller', () => _upload(form, item));
  }

  void removeFile(TicketActionForm form, FormFileItem item) {
    item.cancel.cancel();
    form.files.remove(item);
    form.error.value = null;
  }
}
