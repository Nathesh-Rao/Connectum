import 'dart:async';

import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../core/widgets/app_notice_card.dart' show AppNoticeVariant;
import '../../core/widgets/app_notices.dart';
import '../../data/ai/ai_models.dart';
import '../../data/ai/ai_repository.dart';
import '../../data/ai/ai_setup_cache.dart';
import '../../data/ai/care_summary_text.dart';
import '../../data/ai/ai_answer.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/message_repository.dart' show SendResult;
import 'ai_summary_message_format.dart';
import 'ai_texts.dart';

enum AiPhase { menu, setup, loading, result, error, cancelled }

/// The icon is for every chat with a window. A care thread
/// (`group:care-<person>`) summarises from `care.summary`, so it needs the
/// person's username in its name: without one the icon is hidden. My Work
/// Space has its own screen.
bool aiAvailableIn(String convId) {
  final kind = ConversationRepository.kindOf(convId);
  if (kind == 'group') {
    final target = ConversationRepository.targetOf(convId);
    return !target.startsWith('care-') ||
        CareSummaryText.personOf(convId) != null;
  }
  return kind == 'dm' || kind == 'host' || kind == 'global';
}

/// What a tap on the header icon leads to.
enum AiEntry { sheet, notSetUp, problem }

/// What [AiSummaryController.summarize] did.
enum AiSummarizeResult { started, busy }

/// The AI sheet of one chat. A summary can be read, copied or posted into the
/// chat as an ordinary text message through [post].
class AiSummaryController extends GetxController {
  AiSummaryController({
    required this.ai,
    required this.setup,
    required this.chatId,
    required this.title,
    required this.isOnline,
    required this.post,
    required this.isAdmin,
    this.carePerson,
  });

  final AiRepository ai;
  final AiSetupCache setup;
  final String chatId;
  final String Function() title;
  final bool Function() isOnline;

  /// Sends one plain text message into this chat.
  final Future<SendResult> Function(String text) post;

  /// From `me` (`permissions.isAdmin`): an administrator is told to set AI up
  /// in the web app, anyone else to ask the administrator.
  final bool Function() isAdmin;

  /// The username of a care thread's person, or null in any other chat.
  final String? carePerson;

  bool get isCare => carePerson != null;

  final phase = AiPhase.menu.obs;
  final range = AiRange.everything.obs;
  final text = ''.obs;
  final usedLabel = ''.obs;
  final messageCount = RxnInt();

  /// A care summary left older messages out.
  final isTruncated = false.obs;

  /// The answer is for the person the thread is about: a line says they
  /// see only the parts of the thread they have access to.
  final isPatientView = false.obs;

  /// The typed question being answered, or null for the one-tap summary.
  String? _question;
  bool get isAnswer => _question != null;
  final error = Rxn<AiErrorKind>();
  String? errorDetail;
  final date = Rxn<DateTime>();
  final agents = <AiAgent>[].obs;
  final agent = Rxn<AiAgent>();

  /// Set when the setup state is not ready, so the view shows a dialog.
  final blocked = Rxn<AiSetup>();

  /// True from the moment Post is tapped until the send result is known; it
  /// stays true after a full success, so a second tap cannot post again.
  final isSharing = false.obs;

  List<String> _parts = const [];
  int _posted = 0;

  StreamSubscription<AiSummaryChunk>? _sub;
  int _run = 0;

  /// The setup the dialog describes.
  AiSetup lastSetup = const AiSetup(AiSetupState.notSetUp);

  /// Why the setup could not be read, for [AiEntry.problem].
  AiErrorKind lastProblem = AiErrorKind.failed;

  /// What the not-set-up dialog says.
  String get setupText => AiTexts.setupText(isAdmin: isAdmin());

  /// The words of an error for this person.
  String errorText(AiErrorKind kind, [String? detail]) =>
      AiTexts.errorBody(kind, detail: detail, isAdmin: isAdmin());

  Future<AiEntry> resolveEntry() async {
    try {
      final state = await setup.get();
      _take(state);
      return state.isReady ? AiEntry.sheet : AiEntry.notSetUp;
    } on AiError catch (e) {
      lastProblem = e.kind;
      return AiEntry.problem;
    }
  }

  /// Called when the sheet opens: refreshes the setup state and reports it.
  Future<void> onSheetOpened() async {
    reset();
    try {
      final state = await setup.get(isRefresh: true);
      _take(state);
      if (!state.isReady) blocked.value = state;
    } on AiError catch (e) {
      _fail(e.kind);
    }
  }

  void _take(AiSetup state) {
    lastSetup = state;
    agents.assignAll(state.agents);
    final current = agent.value;
    if (state.agents.isEmpty) {
      agent.value = null;
    } else if (current == null ||
        !state.agents.any((a) => a.id == current.id)) {
      agent.value = state.agents.first;
    }
  }

  void reset() {
    _stop();
    _question = null;
    _forgetShare();
    phase.value = AiPhase.menu;
    text.value = '';
    error.value = null;
    blocked.value = null;
  }

  void openSetup() => phase.value = AiPhase.setup;
  void backToMenu() => phase.value = AiPhase.menu;
  void pick(AiRange value) => range.value = value;
  void pickDate(DateTime value) {
    date.value = value;
    range.value = AiRange.date;
  }

  void pickAgent(AiAgent value) => agent.value = value;

  /// The Summarize button waits for a date when "A date" is chosen.
  bool get canSummarize =>
      agent.value != null &&
      (isCare || range.value != AiRange.date || date.value != null);

  /// The caption under the range step.
  String get privacyText => AiTexts.privacy;

  /// Summarises. An end-to-end chat is read from the messages this phone has
  /// opened, like the web.
  Future<AiSummarizeResult> summarize() => _start(null);

  /// A typed question about a care thread, answered from the whole thread.
  /// An empty question does nothing; other chats have no questions.
  Future<AiSummarizeResult> ask(String question) {
    final q = question.trim();
    if (!isCare || q.isEmpty) return Future.value(AiSummarizeResult.busy);
    return _start(q);
  }

  /// Runs the last request again (Regenerate, Retry).
  Future<AiSummarizeResult> retry() => _start(_question);

  Future<AiSummarizeResult> _start(String? question) async {
    if (phase.value == AiPhase.loading) return AiSummarizeResult.busy;
    _question = question;
    final id = ++_run;
    _stop();
    final picked = range.value;
    final day = date.value;
    usedLabel.value = question != null
        ? AiTexts.questionLabel
        : isCare
        ? 'Whole thread'
        : picked == AiRange.date && day != null
        ? 'From ${day.year}-${day.month.toString().padLeft(2, '0')}-'
              '${day.day.toString().padLeft(2, '0')}'
        : picked.label;
    messageCount.value = null;
    isTruncated.value = false;
    isPatientView.value = false;
    text.value = '';
    error.value = null;
    _forgetShare();
    phase.value = AiPhase.loading;
    if (!isOnline()) {
      _fail(AiErrorKind.offline);
      return AiSummarizeResult.started;
    }
    final Stream<AiSummaryChunk> stream;
    try {
      stream = ai.summarize(
        AiSummaryRequest(
          chatId: chatId,
          title: title(),
          range: picked,
          date: date.value,
          agent: agent.value,
          carePerson: carePerson,
          question: question,
        ),
      );
    } on Object {
      _fail(AiErrorKind.failed);
      return AiSummarizeResult.started;
    }
    _sub = stream.listen(
      (chunk) {
        if (id != _run) return;
        text.value = chunk.text;
        messageCount.value = chunk.messageCount ?? messageCount.value;
        isTruncated.value = chunk.isTruncated;
        isPatientView.value = chunk.isPatientView;
        if (chunk.isFinal) phase.value = AiPhase.result;
      },
      onError: (Object e) {
        if (id != _run) return;
        _fail(
          e is AiError ? e.kind : AiErrorKind.failed,
          detail: e is AiError ? e.message : null,
        );
      },
      onDone: () {
        if (id != _run || phase.value != AiPhase.loading) return;
        if (AiAnswer.plain(text.value).isEmpty) {
          _fail(AiErrorKind.failed);
        } else {
          phase.value = AiPhase.result;
        }
      },
    );
    return AiSummarizeResult.started;
  }

  void cancel() {
    if (phase.value != AiPhase.loading) return;
    _run++;
    _stop();
    ai.cancel();
    phase.value = AiPhase.cancelled;
  }

  void _fail(AiErrorKind kind, {String? detail}) {
    _stop();
    if (kind == AiErrorKind.notSetUp ||
        kind == AiErrorKind.noPermission ||
        kind == AiErrorKind.agentGone) {
      setup.clear();
    }
    errorDetail = detail;
    error.value = kind;
    phase.value = AiPhase.error;
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
  }

  /// Back to the range step, for "nothing to summarize" and "too many".
  void changeRange() => phase.value = AiPhase.setup;

  void _forgetShare() {
    _parts = const [];
    _posted = 0;
    isSharing.value = false;
  }

  /// Exactly what Share will post, for the preview before posting.
  String get sharePreview =>
      AiSummaryMessageFormat.build(AiAnswer.plain(text.value)).join('\n\n');

  /// A typed answer stays on this person's screen (the web never posts it).
  bool get canShare =>
      phase.value == AiPhase.result && !isSharing.value && !isAnswer;

  /// Posts the summary, one message per part and in order. Parts already sent
  /// are never sent again: a retry carries on with the first one that failed.
  /// Returns true once everything is queued.
  Future<bool> share() async {
    if (!canShare) return false;
    isSharing.value = true;
    if (_parts.isEmpty) {
      _parts = AiSummaryMessageFormat.build(AiAnswer.plain(text.value));
    }
    while (_posted < _parts.length) {
      final SendResult result;
      try {
        result = await post(_parts[_posted]);
      } on Object {
        return _postFailed();
      }
      if (result != SendResult.queued) return _postFailed();
      _posted++;
    }
    AppNotices.success(AiTexts.posted);
    return true;
  }

  bool _postFailed() {
    isSharing.value = false;
    AppNotices.show(
      AiTexts.postFailed,
      variant: AppNoticeVariant.error,
      actionLabel: 'Retry',
      isPersistent: true,
      onAction: share,
    );
    return false;
  }

  Future<void> copy() async {
    await Clipboard.setData(ClipboardData(text: AiAnswer.plain(text.value)));
    AppNotices.info(AiTexts.copied);
  }

  @override
  void onClose() {
    _stop();
    super.onClose();
  }
}
