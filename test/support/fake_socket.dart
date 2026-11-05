import 'package:connectum/data/e2e/e2e_models.dart';
import 'package:connectum/data/models/session_info.dart';
import 'package:connectum/data/models/conversation.dart';
import 'package:connectum/data/repositories/conversation_repository.dart';
import 'package:connectum/data/repositories/e2e_repository.dart';
import 'package:connectum/data/repositories/form_file_repository.dart';
import 'package:connectum/data/repositories/group_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/data/api/api_client.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class FakeStore extends Fake implements SessionStore {
  FakeStore({this.user = 'me'}) {
    current.value = SessionInfo(orgId: 'org', userId: user, expiresTs: 1 << 50);
  }

  final String user;

  @override
  final current = Rxn<SessionInfo>();

  @override
  String? get userId => current.value?.userId;

  @override
  String? get orgId => current.value?.orgId;

  @override
  bool get hasEnterpriseSession => current.value != null;

  /// Another person or organisation signs in, or nobody ([user] null).
  void switchTo(String? user, {String org = 'org'}) {
    current.value = user == null
        ? null
        : SessionInfo(orgId: org, userId: user, expiresTs: 1 << 50);
  }
}

class FakeE2e extends Fake implements E2eRepository {
  E2eReading reading = const E2eReading.pending();
  int opened = 0;

  @override
  Future<E2eReading> open({
    required String text,
    required String convId,
    String? expectConv,
    E2eDeviceKeys? keys,
    Future<String?> Function(String user, String deviceId)? signKeyFor,
    Future<E2eDevicePublic?> Function(String user, String deviceId)? deviceFor,
    Map<String, ({String ecdh, String sign})>? testPins,
  }) async {
    opened++;
    return reading;
  }
}

/// A [SocketService] that answers `sdCall` from a script and records the
/// calls. Never opens a socket.
class FakeSocket extends SocketService {
  FakeSocket() : super(_Store(), _Connectivity(), _Api());

  /// action -> answer (a map, or a function of the params, or an error).
  final answers = <String, Object>{};
  final calls = <({String action, Map<String, dynamic> args})>[];

  /// Held answers: when set, an action waits for [release].
  final held = <String, Future<void>>{};

  void goOnline() => connection.value = SocketState.online;
  void goOffline() => connection.value = SocketState.offline;

  int count(String action) => calls.where((c) => c.action == action).length;

  @override
  Future<Map<String, dynamic>> sdCall(
    String action,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (!isOnline) throw const SocketCallError('not_connected');
    calls.add((action: action, args: args));
    final wait = held[action];
    if (wait != null) await wait;
    final a = answers[action];
    if (a is SocketCallError) throw a;
    if (a is Map<String, dynamic> Function(Map<String, dynamic>)) {
      return a(args);
    }
    if (a is Map<String, dynamic>) return a;
    return <String, dynamic>{};
  }
}

class _Store extends Fake implements SessionStore {}

class _Connectivity extends Fake implements ConnectivityService {}

class _Api extends Fake implements ApiClient {}

class FakeConnectivity extends Fake implements ConnectivityService {
  @override
  final state = AppConnectivity.online.obs;
}

class FakeConversations extends Fake implements ConversationRepository {
  @override
  final conversations = <Conversation>[].obs;
}

class FakeGroups extends Fake implements GroupRepository {}

class FakeFiles extends Fake implements FormFileRepository {}
