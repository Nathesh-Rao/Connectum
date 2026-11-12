import '../../data/ai/ai_repository.dart';
import '../../data/ai/ai_setup_cache.dart';
import '../../data/ai/ai_repository_impl.dart';
import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:get/get.dart';

import '../../data/api/api_client.dart';
import '../../data/attachment_cache.dart';
import '../debug/seed_ui.dart';
import '../../data/db/app_database.dart';
import '../../data/e2e/e2e_key_store.dart';
import '../../data/form_logic/form_logic_service.dart';
import '../../data/repositories/attachment_repository.dart';
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
import '../../data/repositories/message_repository.dart';
import '../../data/repositories/presence_repository.dart';
import '../../data/repositories/qr_repository.dart';
import '../../data/repositories/typing_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/repositories/submission_repository.dart';
import '../../data/repositories/task_repository.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';
import '../../features/connect_target/connect_target_controller.dart';
import '../utils/install_referrer.dart';
import 'deep_link_service.dart';
import 'invite_service.dart';
import '../../demo/demo_ai_repository.dart';
import '../../demo/demo_auth_repository.dart';
import '../../demo/demo_feed_repository.dart';
import '../../demo/demo_mode.dart';
import '../../demo/demo_services.dart';
import '../debug/seed_qr.dart';
import '../debug/seed_tasks.dart';
import '../debug/seed_tickets.dart';

class InitialBinding extends Bindings {
  InitialBinding(this.connectivity);

  final ConnectivityService connectivity;

  @override
  void dependencies() {
    final isDemo = DemoMode.isActive;
    final store = Get.put(
      isDemo ? DemoSessionStore() : SessionStore(),
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
    Get.put(
      CommandRepository(socket, store, connectivity, messages, conversations),
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
      TicketRepository(socket, store, conversations),
      permanent: true,
    );
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
    Get.put(ApprovalRepository(socket, store, feed), permanent: true);
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
    if (!isDemo) unawaited(localNotifications.start());
    final attachments = Get.put(AttachmentRepository(store), permanent: true);
    Get.put(FormFileRepository(attachments, store), permanent: true);
    final attachmentCache = Get.put(
      AttachmentCache(attachments.dio),
      permanent: true,
    );
    // Decrypted documents made for the viewer last run do not outlive it.
    unawaited(attachmentCache.clearOpenTmp());
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
      unawaited(SeedTickets.start());
    }
  }
}
