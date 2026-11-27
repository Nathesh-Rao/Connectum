import 'dart:async';

import 'package:connectum/data/models/identity_info.dart';
import 'package:connectum/data/repositories/people_avatars.dart';
import 'package:connectum/data/repositories/people_profiles.dart';
import 'package:connectum/data/repositories/profile_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// A socket that records plain command lines and `sd` calls and answers them
/// from [onCommand] / [onSd].
class FakeProfileSocket extends Fake implements SocketService {
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  bool online = true;
  final sent = <String>[];
  final sdCalls = <({String action, Map<String, dynamic> args})>[];

  /// The event a command line gets back; null sends no answer.
  Map<String, dynamic>? Function(String line) onCommand = (line) => {
    'type': 'ack',
    'cmd': line.substring(1).split(' ').first,
    'ok': true,
  };

  Future<Map<String, dynamic>> Function(
    String action,
    Map<String, dynamic> args,
  )
  onSd = (action, args) async => {};

  void emit(Map<String, dynamic> event) => _events.add(event);

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  @override
  bool get isOnline => online;

  @override
  Future<bool> sendCommand(String line) async {
    if (!online) return false;
    sent.add(line);
    final reply = onCommand(line);
    if (reply != null) scheduleMicrotask(() => _events.add(reply));
    return true;
  }

  @override
  Future<Map<String, dynamic>> sdCall(
    String action,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(seconds: 12),
  }) {
    sdCalls.add((action: action, args: args));
    return onSd(action, args);
  }
}

class FakeSession extends Fake implements SessionStore {
  @override
  final identity = Rxn<IdentityInfo>(
    const IdentityInfo(
      token: 't',
      email: 'me@test.co',
      enterprises: [],
      username: 'me',
      name: 'Me Myself',
    ),
  );
  @override
  String? get orgId => 'org';
  @override
  String? get userId => 'me';
}

class FakeAvatars extends Fake implements PeopleAvatars {
  @override
  final urls = <String, String>{}.obs;
  @override
  String? urlOf(String? username) => urls[(username ?? '').toLowerCase()];
}

/// A `profile` event as the server sends it.
Map<String, dynamic> profileEvent(
  String user, {
  String? status,
  Object? presence = _absent,
  String? avatar,
}) => {
  'type': 'profile',
  'user': user,
  'avatar': avatar,
  'status': status,
  if (presence != _absent) 'presence': presence,
};

const _absent = Object();

class ProfileRig {
  ProfileRig() {
    profiles = PeopleProfiles(socket, session);
    repository = ProfileRepository(
      socket,
      ackTimeout: const Duration(milliseconds: 200),
    );
  }

  final socket = FakeProfileSocket();
  final session = FakeSession();
  final avatars = FakeAvatars();
  late final PeopleProfiles profiles;
  late final ProfileRepository repository;

  void ownProfile({String? status, Object? presence}) =>
      profiles.onEvent(profileEvent('me', status: status, presence: presence));
}
