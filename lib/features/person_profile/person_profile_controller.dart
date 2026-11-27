import 'package:get/get.dart';

import '../../core/routes/conversation_route.dart';
import '../../data/profile/presence.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'models/person_card.dart';

/// Someone else's profile, read only, from what is already held: no server
/// call. Presence shows only while the person is online.
class PersonProfileController extends GetxController {
  PersonProfileController({
    required this.card,
    required this.profiles,
    required this.presence,
    required this.avatars,
  });

  final PersonCard card;
  final PeopleProfiles profiles;
  final PresenceRepository presence;
  final PeopleAvatars avatars;

  /// Reads Rx values: call it inside an Obx.
  String? get picture => avatars.urlOf(card.username);

  /// The status message, or null.
  String? get status {
    final s = profiles.statusOf(card.username);
    return s == null || s.trim().isEmpty ? null : s.trim();
  }

  /// True while the person is online and presence is live.
  bool get isOnline => presence.dotFor(card.username) == PresenceDot.online;

  /// What the person shows, or null unless they are online.
  Presence? get mood => isOnline ? profiles.presenceOf(card.username) : null;

  void message() => ConversationRoute.open('dm:${card.username.toLowerCase()}');
}
