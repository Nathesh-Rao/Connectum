import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:get/get.dart';

import '../../data/api/api_client.dart';
import '../../data/attachment_cache.dart';
import '../debug/seed_ui.dart';
import '../../data/db/app_database.dart';
import '../../data/e2e/e2e_key_store.dart';
import '../../data/form_logic/form_logic_service.dart';
import '../../data/repositories/attachment_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/command_repository.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/e2e_repository.dart';
import '../../data/repositories/encryption_policy.dart';
import '../../data/repositories/feed_repository.dart';
import '../../data/repositories/form_file_repository.dart';
import '../../data/repositories/form_options_repository.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/repositories/presence_repository.dart';
import '../../data/repositories/typing_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/repositories/submission_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';
import 'deep_link_service.dart';

class InitialBinding extends Bindings {
  InitialBinding(this.connectivity);

  final ConnectivityService connectivity;

  @override
  void dependencies() {
    final store = Get.put(SessionStore(), permanent: true);
    store.identity.value = SeedUi.identity();
    Get.put(DeepLinkService(AppLinks(), store), permanent: true);
    final db = Get.put(AppDatabase(), permanent: true);
    final api = Get.put(ApiClient(store), permanent: true);
    Get.put(connectivity, permanent: true);
    final socket = Get.put(
      SocketService(store, connectivity, api),
      permanent: true,
    );
    connectivity.attachSocket(socket.connection);
    final e2e = Get.put(
      E2eRepository(E2eKeyStore(), socket, store, db),
      permanent: true,
    );
    final policy = Get.put(
      EncryptionPolicy(socket, store, e2e),
      permanent: true,
    );
    final conversations = Get.put(
      ConversationRepository(db, store, socket, e2e),
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
    Get.put(
      SubmissionRepository(db, store, socket, messages, formOptions),
      permanent: true,
    );
    Get.put(FormLogicService(), permanent: true);
    Get.put(PresenceRepository(socket), permanent: true);
    Get.put(TypingRepository(socket), permanent: true);
    Get.put(FeedRepository(socket), permanent: true);
    final attachments = Get.put(AttachmentRepository(store), permanent: true);
    Get.put(FormFileRepository(attachments, store), permanent: true);
    final attachmentCache = Get.put(
      AttachmentCache(attachments.dio),
      permanent: true,
    );
    // Decrypted documents made for the viewer last run do not outlive it.
    unawaited(attachmentCache.clearOpenTmp());
    final session = Get.put(
      SessionRepository(store, db, api, socket, attachmentCache),
      permanent: true,
    );
    Get.put(AuthRepository(api, store, session), permanent: true);
  }
}
