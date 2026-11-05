import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import '../../core/widgets/app_notice_card.dart';
import '../../core/widgets/app_notices.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/models/ids.dart';
import '../../data/models/ticket.dart';
import '../../data/repositories/attachment_repository.dart';
import '../../data/repositories/form_file_repository.dart';
import '../../data/repositories/group_repository.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../data/socket/call_problem.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';
import '../chats/models/chat_person.dart';
import '../forms/models/field_input.dart';
import '../forms/models/form_launch.dart';
import '../tasks/task_people_controller.dart';
import 'models/ticket_actions.dart';
import 'models/ticket_input.dart';
import 'ticket_action_form.dart';
import 'tickets_texts.dart';

/// One ticket in full: its header, record, the actions this person may take
/// and its history. It reads `status.get` and `status.history`, shows the
/// server's own words when an action is refused, and reads again on every
/// ticket event.
class TicketDetailController extends GetxController {
  TicketDetailController({
    required this.ticketId,
    required this.tickets,
    required this.people,
    required this.files,
    required this.connectivity,
  });

  final int ticketId;
  final TicketRepository tickets;
  final GroupRepository people;
  final FormFileRepository files;
  final ConnectivityService connectivity;

  static const maxFiles = 10;

  final ticket = Rxn<Ticket>();
  final isAdmin = false.obs;
  final inPool = Rxn<bool>();
  final viewState = AppViewState.loading.obs;

  /// The ticket is gone (not found) or the record has no status.
  final isGone = false.obs;
  final isNotTicket = false.obs;

  final history = <TicketHistoryEntry>[].obs;
  final historyState = AppViewState.loading.obs;

  /// An update is in flight: no second one starts.
  final isBusy = false.obs;

  StreamSubscription<void>? _refreshes;
  int _seq = 0;

  String get me => tickets.me;

  /// The actions this person may take now.
  List<TicketAction> get actions {
    final t = ticket.value;
    if (t == null) return const [];
    return TicketActions.of(
      t,
      me,
      isAdmin: isAdmin.value,
      inPool: inPool.value,
    );
  }

  bool get canEdit {
    final t = ticket.value;
    return t != null && TicketActions.canEdit(t, me);
  }

  @override
  void onInit() {
    super.onInit();
    final known = tickets.known(ticketId);
    if (known != null) {
      ticket.value = known;
      viewState.value = AppViewState.content;
    }
    _refreshes = tickets.refreshes.listen((_) => unawaited(reload()));
    unawaited(reload(isQuiet: known != null));
  }

  @override
  void onClose() {
    _refreshes?.cancel();
    super.onClose();
  }

  // ---- reading ---------------------------------------------------------------

  /// The ticket and its history again. [isQuiet]: what is shown stays when a
  /// read fails.
  Future<void> reload({bool isQuiet = true}) async {
    final seq = ++_seq;
    if (ticket.value == null) viewState.value = AppViewState.loading;
    await Future.wait([_readTicket(seq, isQuiet), _readHistory(seq)]);
  }

  Future<void> _readTicket(int seq, bool isQuiet) async {
    try {
      final detail = await tickets.get(ticketId);
      if (seq != _seq) return;
      if (!detail.ticket.isTicket) {
        isNotTicket.value = true;
        viewState.value = AppViewState.empty;
        return;
      }
      ticket.value = detail.ticket;
      isAdmin.value = detail.isAdmin;
      inPool.value = detail.inPool;
      isGone.value = false;
      isNotTicket.value = false;
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

  Future<void> _readHistory(int seq) async {
    try {
      final rows = await tickets.history(ticketId);
      if (seq != _seq) return;
      history.assignAll(rows);
      historyState.value = AppViewState.content;
    } on SocketCallError {
      if (seq != _seq) return;
      if (history.isEmpty) historyState.value = AppViewState.error;
    }
  }

  // ---- actions ---------------------------------------------------------------

  TicketActionForm newForm(TicketAction action) =>
      TicketActionForm(action, completion: ticket.value?.completion ?? 0);

  /// Sends [form]'s action. True when it is done (the sheet closes). A failure
  /// is told with the server's text; what was typed stays in the form.
  Future<bool> submit(TicketActionForm form) async {
    final t = ticket.value;
    if (t == null || isBusy.value) return false;
    final problem = form.problem;
    if (problem != null) {
      form.error.value = problem;
      return false;
    }
    form.error.value = null;
    isBusy.value = true;
    final requestId = form.requestId ??= _newRequestId();
    final payload = TicketPayload.build(
      id: t.id,
      action: form.action,
      input: form.input,
      requestId: requestId,
      expectedStatus: t.status,
      expectedAssignee: t.withWhom,
    );
    try {
      final result = await tickets.update(payload);
      form.requestId = null;
      _succeed(t, form, result);
      return true;
    } on SocketCallError catch (e) {
      final failure = CallProblem.of(e, isWrite: true);
      final outcome = TicketOutcome.of(failure);
      if (outcome.isSuccess) {
        form.requestId = null;
        _succeed(t, form, null);
        return true;
      }
      if (!outcome.shouldKeepRequestId) form.requestId = null;
      _tell(
        failure,
        retry: outcome.canRetry ? () => unawaited(submit(form)) : null,
      );
      if (outcome.shouldRemoveRow) {
        isGone.value = true;
        tickets.scheduleRefresh();
      } else if (outcome.shouldReload) {
        unawaited(reload());
      }
      return false;
    } finally {
      isBusy.value = false;
    }
  }

  void _succeed(Ticket before, TicketActionForm form, TicketUpdateResult? r) {
    if (r != null) ticket.value = before.applying(r);
    final status = r?.status ?? form.action.to;
    AppNotices.success(
      TicketsTexts.done(
        status: status,
        sentTo: form.action.asksSendTo ? form.input.sendTo : null,
      ),
    );
    unawaited(reload());
    tickets.scheduleRefresh();
  }

  /// A UUID v4 for one press of Send.
  static String _newRequestId() => newCid().substring(2);

  void _tell(CallProblem problem, {VoidCallback? retry}) {
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
  /// through the outbox (`submissions.update`); the ticket is read again when
  /// the screen closes and when the server's change event arrives.
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
    unawaited(reload());
  }

  // ---- people and files ------------------------------------------------------

  TaskPeopleController newPeople() => TaskPeopleController(people);

  void picked(TicketActionForm form, ChatPerson person) {
    form.sendTo.value = person;
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
    final item = FormFileItem(
      name: picked.name,
      size: picked.bytes,
      path: picked.path,
      mime: picked.mime,
    );
    form.files.add(item);
    unawaited(_upload(form, item));
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
    unawaited(_upload(form, item));
  }

  void removeFile(TicketActionForm form, FormFileItem item) {
    item.cancel.cancel();
    form.files.remove(item);
    form.error.value = null;
  }
}
