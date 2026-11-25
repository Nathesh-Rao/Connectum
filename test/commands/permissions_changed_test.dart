import 'dart:async';

import 'package:connectum/data/repositories/command_repository.dart';
import 'package:connectum/data/repositories/conversation_repository.dart';
import 'package:connectum/data/repositories/message_repository.dart';
import 'package:connectum/data/socket/read_gate.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

class _Socket extends FakeSocket {
  final bus = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get events => bus.stream;

  @override
  bool isCurrent(Map<String, dynamic> event) => true;
}

class _Messages extends Fake implements MessageRepository {}

Map<String, dynamic> _perm(List<String> p, {bool isAdmin = false}) => {
  'permissions': p,
  'isAdmin': isAdmin,
};

const _changed = {'type': 'sd_event', 'event': 'permissions_changed'};

void main() {
  late _Socket socket;
  late CommandRepository repo;

  setUp(() {
    socket = _Socket()..goOnline();
    repo = CommandRepository(
      socket,
      FakeStore(),
      FakeConnectivity(),
      _Messages(),
      FakeConversations() as ConversationRepository,
      readGate: ReadGate(delay: (_) async {}),
      permissionsDebounce: const Duration(milliseconds: 20),
    )..onInit();
  });

  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'permissions_changed re-reads perm.mine once and updates state',
    () async {
      socket.answers['perm.mine'] = _perm(['broadcast']);
      socket.bus.add(_changed);
      await settle();
      expect(socket.count('perm.mine'), 1);
      expect(repo.permissions.value, {'broadcast'});

      socket.answers['perm.mine'] = _perm([
        'broadcast',
        'invite',
      ], isAdmin: true);
      socket.bus.add(_changed);
      await settle();
      expect(socket.count('perm.mine'), 2);
      expect(repo.permissions.value, {'broadcast', 'invite'});
      expect(repo.isAdmin.value, isTrue);
    },
  );

  test('a stale read never overwrites the newest one', () async {
    final slow = Completer<void>();
    var n = 0;
    socket.answers['perm.mine'] = (Map<String, dynamic> _) {
      n++;
      return _perm([n == 1 ? 'old' : 'new']);
    };
    socket.held['perm.mine'] = slow.future;
    socket.bus.add(_changed);
    await settle();
    socket.bus.add(_changed);
    await settle();
    expect(repo.permissions.value, isNull);
    slow.complete();
    await settle();
    expect(repo.permissions.value, {'new'});
    expect(socket.count('perm.mine'), 2);
  });

  test('a burst of three events causes exactly one perm.mine read', () async {
    socket.answers['perm.mine'] = _perm(['a']);
    socket.bus.add(_changed);
    socket.bus.add({'type': 'sd_event', 'event': 'roles_changed'});
    socket.bus.add({'type': 'sd_event', 'event': 'org_config_changed'});
    await settle();
    expect(socket.count('perm.mine'), 1);
    expect(repo.permissions.value, {'a'});
  });
}
