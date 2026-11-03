import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_messages.dart';
import '../../core/debug/seed_ui.dart';
import '../../core/routes/app_routes.dart';
import '../../core/routes/home_reload.dart';
import '../../core/utils/attachment_tag.dart';
import '../../core/theme/app_motion.dart';
import '../../core/utils/chat_time.dart';
import '../../data/models/conversation.dart';
import '../../data/models/hash_command.dart';
import '../../data/models/form_card.dart';
import '../../core/widgets/app_form_card.dart';
import '../forms/forms_picker_controller.dart';
import '../forms/models/form_launch.dart';
import '../home_shell/home_shell_controller.dart';
import '../../data/models/form_submission.dart';
import '../../data/repositories/form_options_repository.dart';
import '../../data/socket/connectivity_service.dart';

import '../../data/attachment_cache.dart';
import '../../data/e2e/e2e_models.dart';
import '../../data/models/message.dart';
import '../../data/models/reaction.dart';
import '../../data/repositories/attachment_repository.dart';
import '../../data/repositories/command_repository.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/e2e_repository.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/repositories/presence_repository.dart';
import '../../data/repositories/submission_repository.dart';
import '../../data/repositories/typing_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/socket_service.dart';
import '../../core/widgets/app_avatar.dart';
import 'models/chat_item.dart';
import 'models/command_prompt.dart';
import 'models/file_download.dart';
import 'models/pending_upload.dart';

/// One conversation. A controller exists per conversation id (the binding puts
/// it under that id as its tag), so one route's disposal can never delete
/// another conversation's controller. It owns its text controller, focus node,
/// scroll controller and timers and disposes them with the route.
class ConversationController extends GetxController
    with WidgetsBindingObserver {
  ConversationController({
    required this.conversationId,
    required this.messages,
    required this.conversations,
    required this.presence,
    required this.typing,
    required this.submissions,
    required this.formOptions,
    required this.connectivity,
    required this.shell,
    required this.socket,
    required this.store,
    required this.e2e,
    required this.commands,
    required this.attachments,
    required this.attachmentCache,
  });

  static const maxLength = 2000;
  static const _nearBottom = 120.0;
  static const _typingEvery = Duration(seconds: 3);
  static const _readDelay = Duration(milliseconds: 400);
  static const _runGap = Duration(minutes: 5);

  final String conversationId;
  final MessageRepository messages;
  final ConversationRepository conversations;
  final PresenceRepository presence;
  final TypingRepository typing;
  final SubmissionRepository submissions;
  final FormOptionsRepository formOptions;
  final ConnectivityService connectivity;
  final HomeShellController? shell;
  final SocketService socket;
  final SessionStore store;
  final E2eRepository e2e;
  final CommandRepository commands;
  final AttachmentRepository attachments;
  final AttachmentCache attachmentCache;

  /// The "#" commands list of the composer.
  late final prompt = CommandPrompt(commands);

  /// The forms button's sheet. A form is posted into this conversation only
  /// where the server takes one (a direct message or a group).
  late final picker = FormsPickerController(
    options: formOptions,
    connectivity: connectivity,
    shell: shell,
    convId: kind == 'dm' || kind == 'group' ? conversationId : null,
    isEncrypted: () => isLocked.value,
  );

  final highlighted = <String>{}.obs;
  final _formJson = <String, String>{};
  Worker? _noticeWorker;

  final text = TextEditingController();
  final focus = FocusNode();
  final scroll = ScrollController();
  final listKey = GlobalKey();
  final unreadKey = GlobalKey();

  final items = <ChatItem>[].obs;
  final isLoaded = false.obs;
  final isLoadingOlder = false.obs;
  final hasOlderError = false.obs;
  final hasMore = RxnBool();
  final isRetired = false.obs;

  /// The composer is closed (the send can never work); [blockReason] says why.
  final isBlocked = false.obs;
  final blockReason = RxnString();

  /// The blocked reason is a changed security key the person can review.
  final isKeyChange = false.obs;

  /// Messages here are end-to-end encrypted (lock and hint in the composer).
  final isLocked = false.obs;
  final isReviewing = false.obs;
  final isAway = false.obs;
  final newAway = 0.obs;
  final length = 0.obs;
  final reply = Rxn<Message>();

  /// Photos being uploaded, newest last; shown after the last message.
  final uploads = <PendingUpload>[].obs;

  /// Bumped to make an image that failed to load try again.
  final imageRetries = <String, int>{}.obs;

  /// Images already in the attachment cache, by tag url.
  final imageFiles = <String, File>{}.obs;

  /// Images the cache could not get; they fall back to a plain network image.
  final imageGaveUp = <String>{}.obs;
  final _imageStarted = <String>{};

  /// Decrypted pictures of encrypted attachments, by tag url. Memory only;
  /// the oldest go once [_secureKeep] are held.
  final secureImages = <String, Uint8List>{}.obs;
  final _secureOrder = <String>[];
  static const _secureKeep = 12;

  /// Why an encrypted attachment could not be opened, by tag url.
  final secureFailures = <String, String>{}.obs;
  final _imageCancel = CancelToken();

  /// Documents being downloaded (or that failed), by tag url.
  final downloads = <String, FileDownload>{}.obs;
  final _openingFiles = <String>{};
  final _seedCached = <String>{};
  int _uploadSeq = 0;
  bool _hasSeedFailed = false;
  final notice = RxnString();

  final _notes = <({String id, String text, int ts})>[];
  int _noteSeq = 0;
  bool _isRunning = false;
  final _byId = <String, Message>{};
  final _seen = <String>{};
  final _fresh = <String>{};
  RxList<Message>? _list;
  Worker? _listWorker;
  Worker? _onlineWorker;
  Worker? _setupWorker;
  Timer? _readTimer;
  Timer? _noticeTimer;
  Timer? _seedTimer;
  DateTime _lastTyping = DateTime.fromMillisecondsSinceEpoch(0);
  String? _firstUnreadId;
  int _unreadCount = 0;
  bool _isUnreadMore = false;
  bool _isForeground = true;

  // ---- who this is ---------------------------------------------------------

  String get kind => ConversationRepository.kindOf(conversationId);
  String get target => ConversationRepository.targetOf(conversationId);
  bool get isDirect => kind == 'dm';
  bool get isTeam => kind == 'host';
  bool get canReply => isDirect || kind == 'group';
  bool get canDelete => kind != 'host';
  bool get canType => kind != 'host';
  bool get isOnline => socket.isOnline;
  String get me => (store.userId ?? SeedMessages.me).toLowerCase();

  Conversation? get conversation {
    final rows = SeedUi.isActive
        ? SeedUi.conversations()
        : conversations.conversations;
    for (final c in rows) {
      if (c.convId == conversationId) return c;
    }
    return null;
  }

  String get title {
    final t = conversation?.title ?? '';
    return t.isEmpty ? (kind == 'global' ? 'Everyone' : target) : t;
  }

  /// The header's second line. A direct message shows "Active now" only while
  /// presence is live and the socket is online; a group shows its member
  /// count when known. Reads Rx values: call it inside an Obx.
  String? get status {
    if (isDirect) {
      final dot = SeedUi.isActive
          ? (SeedUi.online.contains(target)
                ? AppPresenceDot.online
                : AppPresenceDot.none)
          : switch (presence.dotFor(target)) {
              PresenceDot.online => AppPresenceDot.online,
              _ => AppPresenceDot.none,
            };
      return dot == AppPresenceDot.online ? 'Active now' : null;
    }
    final count = conversation?.memberCount ?? 0;
    return kind == 'group' && count > 0 ? '$count members' : null;
  }

  /// A group's members from the stored list, empty when not known.
  List<String> get members => conversation?.members ?? const [];

  AppPresenceDot get presenceDot {
    if (!isDirect) return AppPresenceDot.none;
    if (SeedUi.isActive) {
      return SeedUi.online.contains(target)
          ? AppPresenceDot.online
          : AppPresenceDot.none;
    }
    return switch (presence.dotFor(target)) {
      PresenceDot.online => AppPresenceDot.online,
      PresenceDot.offline => AppPresenceDot.offline,
      PresenceDot.none => AppPresenceDot.none,
    };
  }

  /// A key that is unique across open conversations: message ids repeat
  /// between conversations, and two can be mounted at once.
  GlobalKey keyFor(ChatItem item) =>
      _itemKeys.putIfAbsent(item.key, () => GlobalKey());

  final _itemKeys = <String, GlobalKey>{};

  final _cards = <String, FormCardData?>{};

  /// The card for a form message, or null when it is not one that can be
  /// shown as a card (then it stays an ordinary bubble). A message that
  /// carries no fields falls back to the stored submission and captions.
  FormCardData? formCardOf(Message m) {
    if (m.kind != 'form' || m.isDeleted || m.formJson == null) return null;
    final first = FormCardData.fromMessage(m);
    if (first == null) return null;
    // Reads the stored submission, so a card follows its status (waiting for
    // approval, declined) without a new message.
    final sub = submissions.submissionById(first.id);
    return _cards.putIfAbsent(
      '${m.msgId}|${m.formJson.hashCode}|${sub?.status}|${sub?.canResubmit}',
      () => FormCardData.fromMessage(
        m,
        submission: first.entries.isEmpty ? sub : null,
        definition: submissions.definitions[first.structure],
        status: (sub?.status ?? '').isEmpty ? null : sub!.status,
        canResubmit: sub?.canResubmit ?? false,
      ),
    );
  }

  AppFormCardState formStateOf(Message m) => switch (m.status) {
    MessageStatus.failed => AppFormCardState.failed,
    MessageStatus.pending || MessageStatus.sending => AppFormCardState.waiting,
    _ => AppFormCardState.sent,
  };

  /// What a failed card says under its fields.
  String formProblemOf(Message m) => isInvalidFailure(m)
      ? 'Not sent. Some answers need fixing. Tap to edit and resend'
      : 'Not sent. ${m.failReason == SubmissionRepository.couldNotConfirm ? "Couldn't confirm delivery. " : ""}Tap to retry';

  bool isInvalidFailure(Message m) =>
      m.failReason == SubmissionRepository.invalidReason;

  bool isSentForm(FormCardData d) => d.by.toLowerCase() == me;

  bool canEditForm(Message m, FormCardData d) =>
      m.status != MessageStatus.failed &&
      m.status != MessageStatus.pending &&
      m.status != MessageStatus.sending &&
      (d.canEdit(me) || d.canFix(me));

  /// Tapping a card opens it; a failed one is fixed or sent again instead.
  void tapForm(Message m, FormCardData d) {
    if (m.status != MessageStatus.failed) return openForm(m, d);
    if (isInvalidFailure(m)) {
      unawaited(editAndResend(m));
    } else {
      unawaited(retryForm(m));
    }
  }

  Future<void> retryForm(Message m) async {
    if (SeedUi.isActive) {
      SeedMessages.retry(conversationId, m.msgId);
    } else {
      await submissions.retry(m.msgId);
    }
  }

  /// A submission the server refused, opened with what was typed and the
  /// server's complaint on the fields.
  Future<void> editAndResend(Message m) async {
    final pending = await submissions.pendingFor(m.msgId);
    if (pending == null) {
      _say("That form can't be opened. Delete it and fill it in again.");
      return;
    }
    await Get.toNamed(
      AppRoutes.form,
      arguments: FormLaunch(
        name: pending.name,
        scope: pending.scope,
        caption: pending.caption,
        mode: FormMode.resend,
        convId: conversationId,
        submissionId: m.msgId,
        savedValues: pending.values,
        errorDetails: pending.errors,
        isEncryptedChat: isBlocked.value,
      ),
    );
  }

  /// The pencil on my own card: the form again, filled in with what was
  /// saved. A declined card allowed to be fixed is resubmitted instead.
  Future<void> editForm(Message m, FormCardData d) async {
    FormSubmission? saved = submissions.submissionById(d.id);
    if (saved == null && socket.isOnline) {
      await submissions.syncFromServer();
      saved = submissions.submissionById(d.id);
    }
    if (saved == null) {
      _say("That submission can't be opened right now. Try again online.");
      return;
    }
    await Get.toNamed(
      AppRoutes.form,
      arguments: FormLaunch.forSubmission(
        d,
        saved,
        me: me,
        scope: submissions.definitions[d.structure]?.scope ?? '',
        convId: conversationId,
        isEncryptedChat: isBlocked.value,
      ),
    );
  }

  void openForm(Message m, FormCardData d) {
    Get.toNamed(
      AppRoutes.submissionDetailOf(
        d.id,
        convId: conversationId,
        msgId: m.msgId,
      ),
    );
  }

  Message? originalOf(Message m) => m.replyTo == null ? null : _byId[m.replyTo];

  /// "Priya is typing", "Priya and Ravi are typing", or null.
  String? get typingLabel {
    final list = typing.typingIn(conversationId);
    if (list.isEmpty) return null;
    final names = [
      for (var i = 0; i < list.length; i++)
        if (list[i].toLowerCase() != me) list[i],
    ];
    if (names.isEmpty) return null;
    if (names.length == 1) return '${names.first} is typing';
    return '${names.take(2).join(' and ')} are typing';
  }

  // ---- lifecycle -----------------------------------------------------------

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    scroll.addListener(_onScroll);
    _noticeWorker = ever(submissions.notice, (message) {
      if (message == null) return;
      _say(message);
      submissions.notice.value = null;
    });
    _onlineWorker = ever(socket.connection, (state) {
      if (state == SocketState.online && !SeedUi.isActive) {
        _sync();
        unawaited(_refreshGate(isLookup: true));
      }
    });
    _setupWorker = ever(e2e.phase, (_) {
      if (SeedUi.isActive) {
        _applySeedGate();
      } else {
        unawaited(_refreshGate());
      }
    });
    _load();
  }

  Future<void> _load() async {
    final unread = conversation;
    _unreadCount = unread?.unread ?? 0;
    _isUnreadMore = unread?.unreadMore ?? false;
    if (SeedUi.isActive) {
      _list = SeedMessages.of(conversationId);
      hasMore.value = false;
      _applySeedGate();
      _startSeedTimers();
    } else {
      _list = await messages.open(conversationId);
      await _refreshGate();
    }
    final list = _list!;
    _firstUnreadId = _firstUnread(list.toList());
    _rebuild(isFirst: true);
    isLoaded.value = true;
    _listWorker = ever(list, (_) => _rebuild());
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialScroll());
    if (!SeedUi.isActive) {
      unawaited(_checkEncryptedOnline());
      unawaited(_sync());
    }
  }

  Future<void> _checkEncryptedOnline() async {
    if (!socket.isOnline) return;
    await _refreshGate(isLookup: true);
  }

  /// Asks what a send would do (caches only, unless [isLookup]) and sets the
  /// composer state from the answer. An unknown answer does not block typing.
  Future<void> _refreshGate({bool isLookup = false}) async {
    final gate = await messages.sendGate(conversationId, isLookup: isLookup);
    final hasHistory = await messages.hasEncryptedHistory(conversationId);
    final isClosed = gate.isBlocked && !gate.isTransient;
    isBlocked.value = isClosed;
    blockReason.value = isClosed ? gate.message : null;
    isKeyChange.value = isClosed && gate.isKeyChange;
    keyChangeMember = gate.keyChangeUser;
    isLocked.value = gate.isEncrypt || hasHistory;
  }

  void _applySeedGate() {
    final seed = SeedUi.e2eGate(conversationId);
    isLocked.value = conversation?.isEncrypted ?? false;
    isBlocked.value = seed != null;
    blockReason.value = seed?.reason;
    isKeyChange.value = seed?.isKeyChange ?? false;
  }

  /// The member whose key changed, for the review sheet (set with the gate).
  String? keyChangeMember;

  Future<void> recheckGate() => _refreshGate(isLookup: true);

  /// Reads the keys for the key-changed sheet. Null when they cannot be read.
  Future<E2eKeyReview?> loadKeyReview() async {
    if (isReviewing.value) return null;
    isReviewing.value = true;
    try {
      if (SeedUi.isActive) return SeedUi.keyReview(target);
      return kind == 'group'
          ? await e2e.reviewKeys(keyChangeMember ?? '', group: target)
          : await e2e.reviewKeys(target);
    } on SocketCallError catch (_) {
      _say("Couldn't check the security keys right now.");
      return null;
    } finally {
      isReviewing.value = false;
    }
  }

  /// "Trust new key": pins what the sheet showed, then opens the composer
  /// again if nothing else stands in the way.
  Future<void> trustKey(E2eKeyReview review) async {
    if (SeedUi.isActive) {
      SeedUi.trust(conversationId);
      _applySeedGate();
      return;
    }
    await e2e.trust(review);
    await _refreshGate(isLookup: true);
  }

  /// The light sync on entering: the latest page, when online.
  Future<void> _sync() async {
    if (!socket.isOnline) return;
    await messages.syncConversation(conversationId);
    final state = await messages.olderState(conversationId);
    hasMore.value = state.hasMore;
    _rebuild();
  }

  void _startSeedTimers() {
    if (conversationId != 'dm:priya') return;
    typing.simulate(conversationId, 'Priya');
    var n = 0;
    _seedTimer = Timer.periodic(const Duration(seconds: 4), (t) {
      n++;
      if (n == 3) {
        SeedMessages.incoming(conversationId, 'priya', 'Sounds good, thanks!');
      } else if (n < 3) {
        typing.simulate(conversationId, 'Priya');
      } else {
        t.cancel();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (_isForeground) _scheduleRead();
  }

  /// Takes this screen down before its controller closes (a home reload).
  void retire() => isRetired.value = true;

  // ---- building the rows ---------------------------------------------------

  String? _firstUnread(List<Message> asc) {
    if (_unreadCount <= 0) return null;
    final others = asc.where((m) => !m.isMine && !m.isLocalTemp).toList();
    if (others.isEmpty) return null;
    return others[math.max(0, others.length - _unreadCount)].msgId;
  }

  String get _unreadLabel => _isUnreadMore || _unreadCount > 99
      ? '99+ new messages'
      : _unreadCount == 1
      ? '1 new message'
      : '$_unreadCount new messages';

  void _rebuild({bool isFirst = false}) {
    final list = _list;
    if (list == null) return;
    final asc = list.toList();
    final now = DateTime.now();
    _byId
      ..clear()
      ..addEntries(asc.map((m) => MapEntry(m.msgId, m)));
    final near = !isAway.value;
    for (final m in asc) {
      final key = m.cid ?? m.msgId;
      if (_seen.add(key) && !isFirst) {
        if (near || m.isMine) {
          _fresh.add(key);
        } else if (!m.isMine) {
          newAway.value++;
        }
      }
    }
    for (final m in asc) {
      final json = m.formJson;
      if (m.kind != 'form' || json == null) continue;
      final before = _formJson[m.msgId];
      _formJson[m.msgId] = json;
      if (before != null && before != json && !isFirst) _highlight(m.msgId);
    }
    final out = <ChatItem>[];
    Message? prev;
    var noteAt = 0;
    for (var i = 0; i < asc.length; i++) {
      final m = asc[i];
      while (noteAt < _notes.length && _notes[noteAt].ts <= m.ts) {
        out.add(ChatItem.system(_notes[noteAt].text, refId: _notes[noteAt].id));
        noteAt++;
      }
      final isNewDay = prev == null || !ChatTime.isSameDay(prev.ts, m.ts);
      if (isNewDay) out.add(ChatItem.day(ChatTime.day(m.ts, now)));
      final isUnreadStart = m.msgId == _firstUnreadId;
      if (isUnreadStart) out.add(ChatItem.unread(_unreadLabel));
      final next = i + 1 < asc.length ? asc[i + 1] : null;
      final startsRun =
          prev == null || isNewDay || isUnreadStart || _breaks(prev, m);
      final endsRun =
          next == null ||
          !ChatTime.isSameDay(m.ts, next.ts) ||
          next.msgId == _firstUnreadId ||
          _breaks(m, next);
      out.add(
        ChatItem.message(
          m,
          isFirstOfRun: startsRun,
          isLastOfRun: endsRun,
          showName: !m.isMine && !isDirect && startsRun,
          isFresh: _fresh.contains(m.cid ?? m.msgId),
        ),
      );
      prev = m;
    }
    for (; noteAt < _notes.length; noteAt++) {
      out.add(ChatItem.system(_notes[noteAt].text, refId: _notes[noteAt].id));
    }
    final reversed = out.reversed.toList();
    if (isLoadingOlder.value) {
      reversed.add(const ChatItem.status(ChatItemKind.loadingOlder));
    } else if (hasOlderError.value) {
      reversed.add(const ChatItem.status(ChatItemKind.olderError));
    } else if (hasMore.value == false && asc.isNotEmpty) {
      reversed.add(const ChatItem.status(ChatItemKind.start));
    }
    items.assignAll(reversed);
    _scheduleRead();
  }

  /// A card that an edit just rewrote flashes once.
  void _highlight(String msgId) {
    highlighted.add(msgId);
    Timer(AppDurations.slow * 3, () => highlighted.remove(msgId));
  }

  bool _breaks(Message a, Message b) =>
      a.isMine != b.isMine ||
      a.sender != b.sender ||
      (b.ts - a.ts) > _runGap.inMilliseconds;

  // ---- scrolling -----------------------------------------------------------

  void _onScroll() {
    if (!scroll.hasClients) return;
    final p = scroll.position;
    final away = p.pixels > _nearBottom;
    if (away != isAway.value) isAway.value = away;
    if (!away) newAway.value = 0;
    if (p.maxScrollExtent - p.pixels < 400) unawaited(loadOlder());
    _scheduleRead();
  }

  void scrollToLatest() {
    if (!scroll.hasClients) return;
    scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// Opens at the "new messages" divider when there is unread, otherwise at
  /// the newest message (offset 0 of the reversed list).
  Future<void> _initialScroll() async {
    if (_firstUnreadId == null || !scroll.hasClients) return;
    for (var i = 0; i < 40; i++) {
      final context = unreadKey.currentContext;
      if (context != null && context.mounted) {
        await Scrollable.ensureVisible(context, alignment: 0.25);
        return;
      }
      final p = scroll.position;
      if (p.pixels >= p.maxScrollExtent) return;
      scroll.jumpTo(
        math.min(p.maxScrollExtent, p.pixels + p.viewportDimension * 0.8),
      );
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<void> loadOlder() async {
    if (SeedUi.isActive ||
        isLoadingOlder.value ||
        hasMore.value == false ||
        !socket.isOnline ||
        !isLoaded.value) {
      return;
    }
    isLoadingOlder.value = true;
    hasOlderError.value = false;
    _rebuild();
    final page = await messages.loadOlder(conversationId);
    isLoadingOlder.value = false;
    if (page == null) {
      hasOlderError.value = socket.isOnline;
    } else {
      hasMore.value = page.hasMore;
    }
    _rebuild();
  }

  Future<void> retryOlder() {
    hasOlderError.value = false;
    return loadOlder();
  }

  // ---- read ----------------------------------------------------------------

  /// Reports the newest message from someone else that is on screen, only
  /// while the app is in the foreground and this is the conversation on top.
  /// Going back, backgrounding or being offline never reports a message that
  /// was not seen; the position is only ever moved forward by the repository.
  void _scheduleRead() {
    _readTimer?.cancel();
    _readTimer = Timer(_readDelay, _markVisibleRead);
  }

  void _markVisibleRead() {
    if (!_isForeground || !isLoaded.value || isRetired.value) return;
    if (Get.currentRoute != AppRoutes.conversationOf(conversationId)) return;
    final box = listKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final top = items.take(40).toList();
    for (final item in top) {
      final m = item.message;
      if (m == null || m.isMine || m.isLocalTemp) continue;
      final ctx = keyFor(item).currentContext;
      final render = ctx?.findRenderObject();
      if (render is! RenderBox || !render.attached) continue;
      final y = render.localToGlobal(Offset.zero, ancestor: box).dy;
      final visible =
          math.min(y + render.size.height, box.size.height) - math.max(y, 0);
      if (visible >= render.size.height * 0.6) {
        if (SeedUi.isActive) return;
        unawaited(conversations.markRead(conversationId, m.msgId));
        return;
      }
    }
  }

  // ---- composing -----------------------------------------------------------

  void onChanged(String value) {
    length.value = value.characters.length;
    prompt.onTextChanged(value);
    if (value.trim().isEmpty || !canType || !socket.isOnline) return;
    final now = DateTime.now();
    if (now.difference(_lastTyping) < _typingEvery) return;
    _lastTyping = now;
    final command = switch (kind) {
      'dm' => '/typing dm $target',
      'group' => '/typing group $target',
      'global' => '/typing global',
      _ => null,
    };
    if (command != null) unawaited(socket.sendCommand(command));
  }

  bool get canSend {
    final n = length.value;
    return text.text.trim().isNotEmpty && n <= maxLength;
  }

  void _say(String message) {
    notice.value = message;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 4), () => notice.value = null);
  }

  /// Puts `#name ` into the composer; nothing runs until send.
  void pickCommand(HashCommand command) {
    final value = '#${command.name} ';
    text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    length.value = value.characters.length;
    prompt.onTextChanged(value);
    focus.requestFocus();
  }

  /// A `#` line: online only, shown as a notice, a small row, or the normal
  /// events of the message it sends.
  Future<void> _runHash(String body) async {
    if (_isRunning) return;
    _isRunning = true;
    try {
      final result = await commands.run(body);
      switch (result.kind) {
        case HashKind.info:
          _notes.add((
            id: 'n${_noteSeq++}',
            text: result.text,
            ts: DateTime.now().millisecondsSinceEpoch,
          ));
          _rebuild();
        case HashKind.directQueued:
          if (result.convId != conversationId) {
            _say('Sent to @${result.user}');
          }
        case HashKind.done:
          break;
        default:
          _say(result.text);
      }
      if (result.isFinished) {
        text.clear();
        length.value = 0;
        prompt.close();
        WidgetsBinding.instance.addPostFrameCallback((_) => scrollToLatest());
      }
    } finally {
      _isRunning = false;
    }
  }

  Future<void> send() async {
    final body = text.text.trim();
    if (body.isEmpty) return;
    if (CommandRepository.isHashLine(body)) return _runHash(body);
    if (body.characters.length > maxLength) {
      _say('Messages can be up to $maxLength characters.');
      return;
    }
    final replied = reply.value;
    final replyTo = replied?.msgId;
    text.clear();
    length.value = 0;
    reply.value = null;
    _lastTyping = DateTime.fromMillisecondsSinceEpoch(0);
    if (SeedUi.isActive) {
      SeedMessages.send(
        conversationId,
        body,
        replyTo: replyTo,
        isEncrypted: isLocked.value,
      );
    } else {
      final result = await messages.sendText(
        conversationId,
        body,
        replyTo: replyTo,
      );
      switch (result) {
        case SendResult.blocked:
          text.text = body;
          length.value = body.characters.length;
          reply.value = replied;
          _say(messages.lastBlock);
          await _refreshGate();
        case SendResult.tooLong:
          _say('Messages can be up to $maxLength characters.');
        case SendResult.invalid:
        case SendResult.noSession:
          _say("That message couldn't be sent.");
        case SendResult.queued:
          break;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => scrollToLatest());
  }

  void tapPlaceholder() => _say('Coming soon');

  // ---- attachments ---------------------------------------------------------

  /// Why photos cannot be attached here, or null. An encrypted thread is not
  /// a reason: its files are sealed first. A thread the policy blocks closes
  /// the composer, with its own reason.
  String? get attachBlock {
    if (kind != 'dm' && kind != 'group') {
      return 'Photos and documents can be sent in direct messages and groups.';
    }
    return null;
  }

  /// True when the attach sheet may open; otherwise says why in the notice.
  bool tapAttach() {
    final reason = attachBlock;
    if (reason != null) {
      _say(reason);
      return false;
    }
    if (!SeedUi.isActive && !socket.isOnline) {
      _say('Attachments need a connection');
      return false;
    }
    return true;
  }

  Future<void> attach(AttachSource source) async {
    final PickedAttachment? file;
    try {
      file = source == AttachSource.document
          ? await attachments.pickDocument()
          : await attachments.pick(source);
    } on AttachmentException catch (e) {
      _say(e.message);
      return;
    }
    if (file == null) return;
    final replied = reply.value;
    reply.value = null;
    final upload = PendingUpload(
      id: 'u${_uploadSeq++}',
      file: file,
      replyTo: replied?.msgId,
    );
    uploads.add(upload);
    WidgetsBinding.instance.addPostFrameCallback((_) => scrollToLatest());
    unawaited(_runUpload(upload));
  }

  /// Upload, then the ordinary send of the tag. No tag is built before the
  /// server returned a url; a failure leaves the photo here with a retry.
  /// In an encrypted thread the file is sealed with a fresh key first and only
  /// the blob is uploaded; the key goes into the tag, which is sent sealed.
  /// An upload that already succeeded is reused, with its key, by every retry.
  Future<void> _runUpload(PendingUpload upload) async {
    upload.isFailed.value = false;
    upload.error.value = null;
    upload.progress.value = 0;
    upload.cancel = CancelToken();
    try {
      if (SeedUi.isActive) {
        await _seedUpload(upload);
      } else {
        await _uploadFor(upload);
      }
      upload.progress.value = 1;
      final tag = AttachmentTag(
        kind: upload.file.kind,
        name: upload.file.name,
        size: AttachmentTag.sizeText(upload.file.bytes),
        url: SeedUi.isActive
            ? '/uploads/seed-upload.${upload.file.isImage ? 'jpg' : 'pdf'}'
            : upload.uploaded!.url,
        type: upload.file.mime,
        e2eKey: upload.e2eKey,
        e2eIv: upload.e2eIv,
      );
      if (SeedUi.isActive) {
        SeedMessages.send(
          conversationId,
          tag.build(),
          replyTo: upload.replyTo,
          isEncrypted: isLocked.value,
        );
      } else {
        final result = await messages.sendAttachment(
          conversationId,
          tag,
          replyTo: upload.replyTo,
        );
        switch (result) {
          case SendResult.queued:
            break;
          case SendResult.blocked:
            await _refreshGate();
            throw AttachmentException(messages.lastBlock);
          case SendResult.tooLong:
          case SendResult.invalid:
          case SendResult.noSession:
            throw AttachmentException(
              "That ${upload.file.isImage ? 'photo' : 'file'} couldn't be sent.",
            );
        }
      }
      uploads.remove(upload);
      WidgetsBinding.instance.addPostFrameCallback((_) => scrollToLatest());
    } on AttachmentException catch (e) {
      if (!uploads.contains(upload)) return;
      upload.isFailed.value = true;
      upload.error.value = e.message;
      upload.canRetry.value = e.isRetryable;
    } catch (_) {
      if (!uploads.contains(upload)) return;
      upload.isFailed.value = true;
      upload.error.value =
          "That ${upload.file.isImage ? 'photo' : 'file'} couldn't be sent. Try again.";
      upload.canRetry.value = true;
    }
  }

  /// Makes sure the server holds this file in the form the thread needs. The
  /// thread is asked again every time: a blob made for another answer (plain
  /// for an encrypted thread, or the reverse) is dropped, never sent.
  Future<void> _uploadFor(PendingUpload upload) async {
    final mode = await messages.attachMode(conversationId);
    if (mode == null) throw AttachmentException(messages.lastBlock);
    final isSealed = mode == AttachMode.encrypted;
    if (upload.isEncrypted != isSealed) {
      upload.uploaded = null;
      upload.e2eKey = null;
      upload.e2eIv = null;
      upload.sealed = null;
    }
    if (upload.uploaded != null) return;
    if (!isSealed) {
      upload.uploaded = await attachments.upload(
        upload.file,
        onProgress: (p) => upload.progress.value = p,
        cancel: upload.cancel,
      );
      return;
    }
    attachments.checkBlobSize(upload.file);
    var sealed = upload.sealed;
    if (sealed == null) {
      final bytes = await attachments.readBytes(upload.file);
      try {
        sealed = await e2e.encryptFile(bytes);
      } catch (_) {
        throw const AttachmentException(
          "That file couldn't be encrypted. Try again.",
        );
      }
      upload.sealed = sealed;
      upload.e2eKey = sealed.key;
      upload.e2eIv = sealed.iv;
    }
    upload.uploaded = await attachments.uploadBlob(
      Uint8List.fromList(sealed.ciphertext),
      onProgress: (p) => upload.progress.value = p,
      cancel: upload.cancel,
      isImage: upload.file.isImage,
    );
    upload.sealed = null;
  }

  /// Debug only: walks the progress, and fails once so the retry shows.
  Future<void> _seedUpload(PendingUpload upload) async {
    for (var i = 1; i <= 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (upload.cancel.isCancelled) {
        throw const AttachmentException('Cancelled.');
      }
      upload.progress.value = i / 10;
      if (i == 6 && !_hasSeedFailed) {
        _hasSeedFailed = true;
        throw const AttachmentException('The upload failed. Tap retry.');
      }
    }
  }

  void retryUpload(PendingUpload upload) => unawaited(_runUpload(upload));

  void cancelUpload(PendingUpload upload) {
    upload.cancel.cancel();
    uploads.remove(upload);
  }

  /// The picture of an image attachment: the cached file when there is one, a
  /// network image when the cache could not get it. Null while the cache is
  /// fetching it ([isImageLoading]) or when its address is not a chat upload
  /// on this server (then it is not fetched). Asking starts the fetch once.
  /// An encrypted picture is decrypted in memory and never written to disk;
  /// it is never shown from the network.
  ImageProvider? imageOf(AttachmentTag tag) {
    if (SeedUi.isActive && tag.url.startsWith('/uploads/seed-')) {
      return tag.url == '/uploads/seed-photo.jpg' ||
              tag.url == '/uploads/seed-e2e-photo.e2e'
          ? const AssetImage('assets/images/connectum_logo.png')
          : null;
    }
    if (tag.isEncrypted || tag.isUnreadable) {
      final bytes = secureImages[tag.url];
      if (bytes != null) return MemoryImage(bytes);
      if (!tag.isUnreadable && _imageStarted.add(tag.url)) {
        scheduleMicrotask(() => _openSecureImage(tag));
      }
      return null;
    }
    final url = tag.resolvedUrl;
    if (url == null) return null;
    final file = imageFiles[tag.url];
    if (file != null) return FileImage(file);
    if (imageGaveUp.contains(tag.url)) return NetworkImage(url);
    if (_imageStarted.add(tag.url)) scheduleMicrotask(() => _cacheImage(tag));
    return null;
  }

  /// Reads Rx values: call it inside an Obx.
  bool isImageLoading(AttachmentTag tag) {
    if (SeedUi.isActive && tag.url.startsWith('/uploads/seed-')) return false;
    if (tag.isEncrypted || tag.isUnreadable) {
      return !tag.isUnreadable &&
          !secureImages.containsKey(tag.url) &&
          !secureFailures.containsKey(tag.url);
    }
    return tag.resolvedUrl != null &&
        !imageFiles.containsKey(tag.url) &&
        !imageGaveUp.contains(tag.url);
  }

  /// What the picture shows when it cannot be shown; reads Rx values.
  String imageProblem(AttachmentTag tag) => tag.isEncrypted || tag.isUnreadable
      ? secureFailures[tag.url] ?? undecryptable
      : "Photo can't be shown";

  /// A wrong key, a damaged or a short blob. The same words for each, and no
  /// file name.
  static const undecryptable = "This file can't be decrypted";

  Future<void> _cacheImage(AttachmentTag tag) async {
    try {
      final file =
          await attachmentCache.cached(tag) ??
          await attachmentCache.fetch(
            tag,
            onProgress: (_) {},
            cancel: _imageCancel,
          );
      if (!isClosed) imageFiles[tag.url] = file;
    } on AttachmentException catch (_) {
      if (!isClosed) imageGaveUp.add(tag.url);
    }
  }

  /// The decrypted bytes of an encrypted blob: from the stored blob, or
  /// downloaded into the cache first (the blob only, still encrypted). A blob
  /// that does not open is deleted so the next try fetches it again.
  Future<Uint8List> _decryptedBytes(
    AttachmentTag tag, {
    void Function(double progress)? onProgress,
    CancelToken? cancel,
  }) async {
    if (tag.resolvedUrl == null) {
      throw const AttachmentException(undecryptable, isRetryable: false);
    }
    var blob = await attachmentCache.readBlob(tag);
    if (blob == null) {
      await attachmentCache.forget(tag);
      await attachmentCache.fetch(
        tag,
        onProgress: onProgress ?? (_) {},
        cancel: cancel ?? _imageCancel,
      );
      blob = await attachmentCache.readBlob(tag);
    }
    if (blob == null) {
      await attachmentCache.forget(tag);
      throw const AttachmentException(undecryptable);
    }
    try {
      return await e2e.decryptFile(blob, tag.e2eKey!, tag.e2eIv!);
    } catch (_) {
      await attachmentCache.forget(tag);
      throw const AttachmentException(undecryptable);
    }
  }

  Future<void> _openSecureImage(AttachmentTag tag) async {
    try {
      final bytes = await _decryptedBytes(tag);
      if (isClosed) return;
      _secureOrder.add(tag.url);
      secureImages[tag.url] = bytes;
      if (_secureOrder.length > _secureKeep) {
        final oldest = _secureOrder.removeAt(0);
        secureImages.remove(oldest);
        _imageStarted.remove(oldest);
      }
    } on AttachmentException catch (e) {
      if (!isClosed) secureFailures[tag.url] = e.message;
    }
  }

  /// The viewer is about to open: counts as the file's latest use.
  void viewedImage(AttachmentTag tag) {
    final file = imageFiles[tag.url];
    if (file != null) unawaited(attachmentCache.touch(file));
  }

  void retryImage(AttachmentTag tag) {
    secureFailures.remove(tag.url);
    unawaited(imageOf(tag)?.evict());
    imageFiles.remove(tag.url);
    imageGaveUp.remove(tag.url);
    _imageStarted.remove(tag.url);
    imageRetries[tag.url] = (imageRetries[tag.url] ?? 0) + 1;
  }

  // ---- opening documents ---------------------------------------------------

  static const noAppNotice = 'No app on this phone can open this file type';

  /// A tap on a document row: opens the cached file, or downloads it first
  /// (progress and cancel on the row, the reason and a retry if it fails).
  Future<void> openFile(AttachmentTag tag) async {
    final running = downloads[tag.url];
    if (running != null && !running.isFailed.value) return;
    if (!_openingFiles.add(tag.url)) return;
    final download = FileDownload();
    try {
      if (SeedUi.isActive) {
        await _seedOpen(tag, download);
        return;
      }
      if (tag.isEncrypted || tag.isUnreadable) {
        await _openSecureFile(tag, download);
        return;
      }
      if (tag.resolvedUrl == null) {
        _say("This file can't be opened here.");
        return;
      }
      var file = await attachmentCache.cached(tag);
      if (file == null) {
        downloads[tag.url] = download;
        file = await attachmentCache.fetch(
          tag,
          onProgress: (p) => download.progress.value = p,
          cancel: download.cancel,
        );
        downloads.remove(tag.url);
      }
      _report(await attachmentCache.open(file));
    } on AttachmentException catch (e) {
      if (download.cancel.isCancelled) return;
      download.isFailed.value = true;
      download.error.value = e.message;
      downloads[tag.url] = download;
    } finally {
      _openingFiles.remove(tag.url);
    }
  }

  /// An encrypted document: the stored blob (downloaded first if needed) is
  /// decrypted in memory, written to `open-tmp` just before the viewer opens
  /// it and removed at the next start, on sign out and on `session_replaced`.
  Future<void> _openSecureFile(AttachmentTag tag, FileDownload download) async {
    if (tag.isUnreadable) {
      _say(undecryptable);
      return;
    }
    try {
      downloads[tag.url] = download;
      final bytes = await _decryptedBytes(
        tag,
        onProgress: (p) => download.progress.value = p,
        cancel: download.cancel,
      );
      downloads.remove(tag.url);
      final file = await attachmentCache.writeForOpening(tag.name, bytes);
      if (file == null) {
        _say("This file can't be opened here.");
        return;
      }
      _report(await attachmentCache.open(file));
    } on AttachmentException {
      downloads.remove(tag.url);
      rethrow;
    }
  }

  void _report(OpenOutcome outcome) {
    switch (outcome) {
      case OpenOutcome.opened:
        break;
      case OpenOutcome.noApp:
        _say(noAppNotice);
      case OpenOutcome.failed:
        _say("This file couldn't be opened.");
    }
  }

  void cancelDownload(AttachmentTag tag) {
    downloads.remove(tag.url)?.cancel.cancel();
  }

  /// Debug only. `seed-slow` takes a few seconds, `seed-fail` stops half way
  /// with "no longer on the server", a `.docx` ends with the no-app notice and
  /// anything else with a note that it would have opened.
  Future<void> _seedOpen(AttachmentTag tag, FileDownload download) async {
    if (tag.url.contains('seed-e2e-bad')) {
      throw const AttachmentException(undecryptable);
    }
    if (!_seedCached.contains(tag.url)) {
      downloads[tag.url] = download;
      final steps = tag.url.contains('seed-slow') ? 30 : 8;
      for (var i = 1; i <= steps; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (download.cancel.isCancelled) return;
        download.progress.value = i / steps;
        if (tag.url.contains('seed-fail') && i == steps ~/ 2) {
          throw const AttachmentException(
            'This file is no longer on the server.',
          );
        }
      }
      _seedCached.add(tag.url);
      downloads.remove(tag.url);
    }
    if (tag.url.endsWith('.docx')) {
      _report(OpenOutcome.noApp);
    } else {
      _say('Opened ${tag.name} (sample)');
    }
  }

  void startReply(Message m) {
    reply.value = m;
    focus.requestFocus();
  }

  void clearReply() => reply.value = null;

  Future<void> retry(Message m) async {
    if (SeedUi.isActive) {
      SeedMessages.retry(conversationId, m.msgId);
    } else {
      await messages.retry(m.msgId);
    }
  }

  // ---- reactions -----------------------------------------------------------

  /// Teams have no reaction command; a message that is not on the server yet,
  /// failed or deleted cannot take one. Encrypted messages can: a reaction is
  /// not part of the encrypted text.
  bool canReact(Message m) =>
      kind != 'host' &&
      !m.isLocalTemp &&
      m.status != MessageStatus.failed &&
      !m.isDeleted;

  List<Reaction> reactionsOf(Message m) =>
      m.isDeleted ? const [] : Reaction.parse(m.reactionsJson, me);

  /// Toggles my [emoji] on [m]. Returns a plain-words problem, or null; the
  /// chips change when the server's reaction event arrives.
  Future<String?> react(Message m, String emoji) async {
    if (!canReact(m)) return "That message can't take a reaction yet.";
    if (SeedUi.isActive) {
      SeedMessages.react(conversationId, m.msgId, emoji);
      return null;
    }
    if (!socket.isOnline) return 'Needs a connection';
    final result = await messages.react(m, emoji);
    return switch (result) {
      ReactResult.sent => null,
      ReactResult.needsConnection => 'Needs a connection',
      ReactResult.notSupported => "Reactions aren't available here.",
    };
  }

  /// A tap on a chip: the same toggle, with a problem shown as a notice.
  Future<void> toggleReaction(Message m, String emoji) async {
    final problem = await react(m, emoji);
    if (problem != null) _say(problem);
  }

  Future<void> copy(Message m) =>
      Clipboard.setData(ClipboardData(text: m.text));

  /// Deletes one of my messages. Returns a plain-words problem, or null.
  Future<String?> delete(Message m) async {
    if (SeedUi.isActive) {
      SeedMessages.delete(conversationId, m.msgId);
      return null;
    }
    if (m.kind == 'form' &&
        (m.isLocalTemp || m.status == MessageStatus.failed)) {
      await submissions.discardPending(m.msgId);
      return null;
    }
    final result = await messages.deleteMessage(m);
    return switch (result) {
      DeleteResult.deleted => null,
      DeleteResult.denied => "You can't delete that message.",
      DeleteResult.needsConnection =>
        'Deleting needs a connection. Try again when you are online.',
      DeleteResult.notSupported => "Messages can't be deleted here.",
      DeleteResult.failed => "That didn't work. Try again.",
    };
  }

  @override
  void onClose() {
    HomeReload.overlays.remove(conversationId);
    WidgetsBinding.instance.removeObserver(this);
    _readTimer?.cancel();
    _noticeTimer?.cancel();
    _seedTimer?.cancel();
    _listWorker?.dispose();
    _onlineWorker?.dispose();
    _setupWorker?.dispose();
    _noticeWorker?.dispose();
    for (final upload in uploads) {
      upload.cancel.cancel();
    }
    _imageCancel.cancel();
    for (final download in downloads.values) {
      download.cancel.cancel();
    }
    picker.onClose();
    scroll.removeListener(_onScroll);
    scroll.dispose();
    text.dispose();
    focus.dispose();
    super.onClose();
  }
}
