import '../../data/ai/ai_repository.dart';
import '../../data/ai/ai_setup_cache.dart';
import '../../data/ai/ai_repository_impl.dart';
import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../data/api/api_client.dart';
import '../../data/attachment_cache.dart';
import '../config/app_config.dart';
import '../crash/crash_identity_binder.dart';
import '../crash/crash_service.dart';
import '../debug/seed_ui.dart';
import '../../data/db/app_database.dart';
import '../../data/e2e/e2e_key_store.dart';
import '../../data/form_logic/form_logic_service.dart';
import '../../data/repositories/attachment_repository.dart';
import '../../data/repositories/attachment_sender.dart';
import '../../data/repositories/share_repository.dart';
import '../../data/repositories/approval_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/command_repository.dart';
import '../../data/repositories/connect_repository.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/e2e_repository.dart';
import '../../data/repositories/group_repository.dart';
import '../../data/repositories/hand_on_repository.dart';
import '../../data/repositories/encryption_policy.dart';
import '../../data/notifications/local_notification_service.dart';
import '../../data/notifications/push/noop_push_service.dart';
import '../../data/notifications/push/push_token_registry.dart';
import '../../data/repositories/feed_repository.dart';
import '../../features/notifications/notification_router.dart';
import '../../data/repositories/form_file_repository.dart';
import '../../data/repositories/form_options_repository.dart';
import '../../data/repositories/marks_repository.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/profile_photo/profile_photo_picker.dart';
import '../../data/repositories/people_avatars.dart';
import '../../data/repositories/people_repository.dart';
import '../../data/repositories/presence_repository.dart';
import '../../data/repositories/profile_photo_repository.dart';
import '../widgets/avatar_image.dart';
import '../../demo/demo_profile_photo_picker.dart';
import '../../data/repositories/qr_repository.dart';
import '../../data/repositories/typing_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/repositories/submission_repository.dart';
import '../../data/repositories/task_repository.dart';
import '../../data/repositories/inbox_repository.dart';
import '../../data/repositories/inbox_views_repository.dart';
import '../../data/repositories/smart_view_repository.dart';
import '../../data/repositories/sv_saved_views_repository.dart';
import '../debug/seed_saved_views.dart';
import '../../data/repositories/sv_file_repository.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../data/repositories/workspace_repository.dart';
import '../../features/tickets/saved_record_notice.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/read_gate.dart';
import '../../data/socket/socket_service.dart';
import '../../features/connect_target/connect_target_controller.dart';
import '../utils/install_referrer.dart';
import '../tour/tour_service.dart';
import 'deep_link_service.dart';
import 'invite_service.dart';
import '../../demo/demo_ai_repository.dart';
import '../../demo/demo_auth_repository.dart';
import '../../demo/demo_feed_repository.dart';
import '../../demo/demo_mode.dart';
import '../../demo/demo_services.dart';
import '../../data/smart_view/sv_prefs.dart';
import '../debug/seed_qr.dart';
import '../debug/seed_tasks.dart';
import '../debug/seed_smart_files.dart';
import '../debug/seed_smart_view.dart';
import '../debug/seed_tickets.dart';
import '../log/safe.dart';
import '../log/app_log.dart';
import '../log/log_bootstrap.dart';
import '../log/log_formatter.dart';

class InitialBinding extends Bindings {
  InitialBinding(this.connectivity, {SmartViewPrefs? smartViewPrefs})
    : smartViewPrefs = smartViewPrefs ?? SmartViewPrefs();

  final ConnectivityService connectivity;
  final SmartViewPrefs smartViewPrefs;

  /// Keeps the log header's user and organisation current: one `CONTEXT`
  /// line on sign-in, sign-out and an organisation switch.
  static void _bindLogContext(SessionStore store) {
    void sync() {
      final identity = store.identity.value;
      final orgId = store.orgId;
      String? org;
      if (orgId != null) {
        org = orgId;
        for (final m in identity?.enterprises ?? const []) {
          if (m.enterprise == orgId) org = m.name;
        }
      }
      final name = identity?.name ?? '';
      LogContextHolder.set(
        LogContext(
          user: identity == null
              ? null
              : '${name.isEmpty ? identity.username : name} <${identity.email}>',
          org: org,
          isKnown: true,
        ),
      );
    }

    ever(store.identity, (_) => sync());
    ever(store.current, (_) => sync());
    sync();
  }

  @override
  void dependencies() {
    final isDemo = DemoMode.isActive;
    final store = Get.put(
      isDemo ? DemoSessionStore() : SessionStore(),
      permanent: true,
    );
    _bindLogContext(store);
    Get.put(LogBootstrap.current(), permanent: true);
    Get.put(smartViewPrefs, permanent: true);
    Get.put(CrashService.current, permanent: true);
    Get.put(
      CrashIdentityBinder(store, CrashService.current.reporter),
      permanent: true,
    );
    store.identity.value = SeedUi.identity();
    final links = Get.put(
      DeepLinkService(
        AppLinks(),
        store,
        connectivity,
        Platform.isAndroid && !isDemo
            ? const PlayInstallReferrerSource()
            : const NoInstallReferrerSource(),
      ),
      permanent: true,
    );
    final db = Get.put(AppDatabase(), permanent: true);
    final api = Get.put(ApiClient(store), permanent: true);
    if (!kReleaseMode && !isDemo && AppConfig.isConfigured) {
      fireAndLog('initial_binding', () => _logEnvironment(api));
    }
    Get.put(connectivity, permanent: true);
    final socket = Get.put(
      isDemo
          ? DemoSocketService(store, connectivity, api)
          : SocketService(store, connectivity, api),
      permanent: true,
    );
    connectivity.attachSocket(socket.connection);
    final e2e = Get.put(
      E2eRepository(E2eKeyStore(), socket, store, db),
      permanent: true,
    );
    Get.put(HandOnRepository(e2e, socket, store), permanent: true);
    final policy = Get.put(
      EncryptionPolicy(socket, store, e2e),
      permanent: true,
    );
    final conversations = Get.put(
      ConversationRepository(db, store, socket, e2e),
      permanent: true,
    );
    Get.put(GroupRepository(socket, store, conversations), permanent: true);
    final connect = Get.put(ConnectRepository(socket), permanent: true);
    Get.put(
      isDemo ? const SeedQrScenario('Demo').repository() : QrRepository(socket),
      permanent: true,
    );
    final messages = Get.put(
      MessageRepository(db, store, socket, conversations, policy, e2e),
      permanent: true,
    );
    final readGate = Get.put(ReadGate(), permanent: true);
    Get.put(MarksRepository(db, store, socket, readGate), permanent: true);
    Get.put(PeopleRepository(socket, readGate), permanent: true);
    final commands = Get.put(
      CommandRepository(
        socket,
        store,
        connectivity,
        messages,
        conversations,
        readGate: readGate,
      ),
      permanent: true,
    );
    final formOptions = Get.put(
      FormOptionsRepository(db, store, socket),
      permanent: true,
    );
    final submissions = Get.put(
      SubmissionRepository(db, store, socket, messages, formOptions),
      permanent: true,
    );
    final tickets = Get.put(
      TicketRepository(socket, store, conversations, gate: readGate),
      permanent: true,
    );
    final smartView = Get.put(
      SmartViewRepository(socket, store, tickets, gate: readGate),
      permanent: true,
    );
    Get.put(InboxRepository(socket, store, readGate), permanent: true);
    Get.put(InboxViewsRepository(socket, store, readGate), permanent: true);
    commands.sourceSuggester = smartView.suggestions;
    Get.put(
      SvSavedViewsRepository(
        call: isDemo
            ? (SeedSavedViews()..armConflict()).callWithConflict
            : smartView.gated,
      ),
      permanent: true,
    );
    Get.put(
      WorkspaceRepository(
        socket,
        store,
        tickets,
        syncOwn: submissions.syncFromServer,
      ),
      permanent: true,
    );
    Get.put(SavedRecordNotice(submissions, tickets), permanent: true);
    final ai = Get.put<AiRepository>(
      isDemo
          ? DemoAiRepository()
          : AiRepositoryImpl(
              socket,
              store,
              messages,
              statusOf: (id) => submissions.submissionById(id)?.status,
              displayNameOf: tickets.nameOf,
            ),
      permanent: true,
    );
    Get.put(AiSetupCache(ai), permanent: true);
    Get.put(FormLogicService(store, socket), permanent: true);
    Get.put(PresenceRepository(socket), permanent: true);
    Get.put(TypingRepository(socket), permanent: true);
    final feed = Get.put(
      isDemo
          ? DemoFeedRepository(socket, store, e2e)
          : FeedRepository(socket, store, e2e),
      permanent: true,
    );
    final tasks = Get.put(TaskRepository(socket, store), permanent: true);
    Get.put(
      ApprovalRepository(socket, store, feed, gate: readGate),
      permanent: true,
    );
    final notificationRouter = Get.put(
      NotificationRouter(store, feed, tasks, tickets),
      permanent: true,
    );
    final pushRegistry = Get.put(
      PushTokenRegistry(store, NoopPushService()),
      permanent: true,
    );
    final localNotifications = Get.put(
      LocalNotificationService(
        feed,
        conversations,
        store,
        notificationRouter,
        pushRegistry,
      ),
      permanent: true,
    );
    if (!isDemo)
      fireAndLog('initial_binding', () => localNotifications.start());
    Get.put(
      TourService(
        userId: () => store.userId,
        blockerNames: ['e2eSetup', 'notificationExplainer'],
        blockers: [
          // Secure-messaging setup needs the person.
          () => switch (Get.find<E2eRepository>().phase.value) {
            E2eSetupPhase.working ||
            E2eSetupPhase.limit ||
            E2eSetupPhase.removed ||
            E2eSetupPhase.refused => true,
            _ => false,
          },
          // The notification explainer comes first.
          () => localNotifications.shouldExplain,
        ],
      ),
      permanent: true,
    );
    final attachments = Get.put(AttachmentRepository(store), permanent: true);
    final shareToConnectum = Get.put(
      ShareRepository(
        conversations: conversations,
        sender: AttachmentSender(
          messages: messages,
          attachments: attachments,
          e2e: e2e,
        ),
        attachments: attachments,
        socket: socket,
      ),
      permanent: true,
    );
    Get.put(FormFileRepository(attachments, store), permanent: true);
    final attachmentCache = Get.put(
      AttachmentCache(attachments.dio),
      permanent: true,
    );
    AvatarImages.cache = attachmentCache;
    Get.put(
      SvFileRepository(
        dio: attachments.dio,
        token: () => store.token,
        origin: AppConfig.baseUrl,
        cache: attachmentCache,
        onUnauthorized: api.reportUnauthorized,
        store: store,
        fetcher: isDemo ? SeedSmartFiles.fetcher : null,
        connectumShare: shareToConnectum,
      ),
      permanent: true,
    );
    Get.put(PeopleAvatars(db, store, socket, conversations), permanent: true);
    Get.put<ProfilePhotoRepository>(
      isDemo
          ? FakeProfilePhotoRepository(register: AvatarImages.registerMemory)
          : ProfilePhotoRepositoryImpl(attachments.dio, store, socket),
      permanent: true,
    );
    Get.put<ProfilePhotoPicker>(
      isDemo ? DemoProfilePhotoPicker() : ImageProfilePhotoPicker(),
      permanent: true,
    );
    // Decrypted documents made for the viewer last run do not outlive it.
    fireAndLog('initial_binding', () => attachmentCache.clearOpenTmp());
    final session = Get.put(
      isDemo
          ? DemoSessionRepository(
              store,
              db,
              api,
              socket,
              attachmentCache,
              links,
            )
          : SessionRepository(store, db, api, socket, attachmentCache, links),
      permanent: true,
    );
    final auth = Get.put(
      isDemo
          ? DemoAuthRepository(api, store, session)
          : AuthRepository(api, store, session),
      permanent: true,
    );
    links.claimResolver = auth.claimInvite;
    links.membershipStatus = auth.membershipStatus;
    links.scanner = (target) =>
        ConnectTargetController.scanOutcome(connect, target);
    Get.put(InviteService(auth, store, links), permanent: true);
    if (isDemo) {
      SeedTasks.start();
      fireAndLog(
        'initial_binding',
        () => SeedTickets.start().then((_) {
          SeedTickets.startOtherPerson();
          return SeedSmartView.start();
        }),
      );
    }
  }
}

Future<void> _logEnvironment(ApiClient api) async {
  try {
    final data = await api.version(const Duration(seconds: 4));
    debugPrint('server: ${data['environment']} ${data['release']}');
  } catch (e, st) {
    AppLog.e('initial_binding', e, st);
  }
}
