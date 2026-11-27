import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'package:connectum/core/log/log.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/features/profile/profile.dart';
import '../../data/profile/presence.dart';
import '../../data/profile/status_text.dart';
import '../../data/session_store.dart';

/// The status editor: the presence chips and the status message, saved with
/// `/setstatus` first and then `/setpresence`, each only if it changed.
class ProfileStatusController extends GetxController {
  ProfileStatusController({
    required this.repository,
    required this.profiles,
    required this.avatars,
    required this.store,
  });

  final ProfileRepository repository;
  final PeopleProfiles profiles;
  final PeopleAvatars avatars;
  final SessionStore store;

  late final TextEditingController text;
  late final presence = _basePresence.obs;

  /// What is saved, as of the last open or the last acked command. Presence is
  /// the value shown (chosen, else read from the status text): picking it
  /// again sends nothing.
  late Presence _basePresence;
  late String _baseStatus;

  /// True while the draft differs from what is saved.
  final isDirty = false.obs;
  final isSaving = false.obs;
  final error = RxnString();

  @override
  void onInit() {
    final me = store.userId;
    _basePresence = profiles.presenceOf(me);
    _baseStatus = (profiles.statusOf(me) ?? '').trim();
    text = TextEditingController(text: StatusText.typed(_baseStatus));
    text.addListener(_refresh);
    ever(presence, (_) => _refresh());
    super.onInit();
  }

  void _refresh() => isDirty.value = isStatusChanged || isPresenceChanged;

  String get username => store.userId ?? '';
  String get name => store.identity.value?.name.isNotEmpty == true
      ? store.identity.value!.name
      : username;
  String? get picture => avatars.urlOf(username);

  bool get isStatusChanged => StatusText.toSend(text.text) != _baseStatus;
  bool get isPresenceChanged => presence.value != _basePresence;

  bool get hasChanges => isStatusChanged || isPresenceChanged;

  void choose(Presence value) {
    presence.value = value;
    error.value = null;
  }

  void clear() {
    text.clear();
    error.value = null;
  }

  /// Sends what changed and closes; on any failure the draft stays and the
  /// reason shows. Returns true when it saved (or had nothing to save).
  Future<bool> save() async {
    if (isSaving.value) return false;
    if (!hasChanges) return true;
    if (!repository.isOnline) {
      error.value = ProfileTexts.offline;
      return false;
    }
    isSaving.value = true;
    error.value = null;
    try {
      if (isStatusChanged) {
        final sent = StatusText.toSend(text.text);
        await repository.setStatus(sent);
        _baseStatus = sent;
      }
      if (isPresenceChanged) {
        await repository.setPresence(presence.value);
        _basePresence = presence.value;
      }
      _refresh();
      AppNotices.success(ProfileTexts.statusSaved);
      return true;
    } on ProfileCommandException catch (e) {
      _refresh();
      error.value = ProfileTexts.commandError(e.code);
      return false;
    } catch (e, st) {
      AppLog.e('profile_status_controller', e, st);
      error.value = ProfileTexts.saveFailed;
      return false;
    } finally {
      if (!isClosed) isSaving.value = false;
    }
  }

  @override
  void onClose() {
    text.dispose();
    super.onClose();
  }
}
