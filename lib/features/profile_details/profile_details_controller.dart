import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'package:connectum/core/log/log.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import 'package:connectum/features/profile/profile.dart';
import '../../data/profile/personal_details.dart';

/// The Personal details screen: gender, date of birth, address, education and
/// skills, loaded with `profile.get` and saved with `profile.update`. Only
/// what changed is sent; a field made empty is sent as null.
class ProfileDetailsController extends GetxController {
  ProfileDetailsController({required this.repository});

  final ProfileRepository repository;

  static const genders = <String, String>{
    'male': 'Male',
    'female': 'Female',
    'other': 'Other',
    'prefer_not_to_say': 'Prefer not to say',
  };

  final state = AppViewState.loading.obs;
  final errorMessage = ''.obs;
  final isSaving = false.obs;
  final isDirty = false.obs;

  /// Why the last save was refused (the server's words), shown under the form.
  final error = RxnString();

  final gender = ''.obs;
  final dob = ''.obs;
  final skillList = <String>[].obs;
  final skillsError = RxnString();

  late final address = TextEditingController();
  late final education = TextEditingController();
  late final skills = TextEditingController();

  PersonalDetails _saved = const PersonalDetails();

  @override
  void onInit() {
    super.onInit();
    for (final c in [address, education, skills]) {
      c.addListener(_onEdited);
    }
    ever(gender, (_) => _refresh());
    ever(dob, (_) => _refresh());
    load();
  }

  Future<void> load() async {
    state.value = AppViewState.loading;
    try {
      final record = await repository.loadRecord();
      _apply(record.details);
      state.value = AppViewState.content;
    } on SocketCallError catch (e, st) {
      AppLog.e('profile_details_controller', e, st);
      errorMessage.value = e.isConnectionGap || e.message.isEmpty
          ? ProfileTexts.detailsLoadFailed
          : e.message;
      state.value = AppViewState.error;
    } catch (e, st) {
      AppLog.e('profile_details_controller', e, st);
      errorMessage.value = ProfileTexts.detailsLoadFailed;
      state.value = AppViewState.error;
    }
  }

  void _apply(PersonalDetails d) {
    _saved = d;
    gender.value = d.gender;
    dob.value = d.dob;
    address.text = DetailsRules.typed(d.address, DetailsRules.addressBytes);
    education.text = DetailsRules.typed(
      d.education,
      DetailsRules.educationBytes,
    );
    skills.text = d.skills.join(', ');
    _refresh();
  }

  void _onEdited() {
    skillList.assignAll(DetailsRules.parseSkills(skills.text));
    skillsError.value = DetailsRules.skillsError(skillList);
    error.value = null;
    _refresh();
  }

  /// What the form holds now.
  PersonalDetails get draft => PersonalDetails(
    gender: gender.value,
    dob: dob.value,
    address: address.text,
    education: education.text,
    skills: DetailsRules.parseSkills(skills.text),
  );

  Map<String, dynamic> get changes => draft.changesFrom(_saved);

  void _refresh() => isDirty.value = changes.isNotEmpty;

  void selectGender(String wire) =>
      gender.value = gender.value == wire ? '' : wire;

  void setDob(DateTime? date) =>
      dob.value = date == null ? '' : DetailsRules.dobToWire(date);

  /// Saves what changed. True when it saved, or when nothing had changed.
  /// On a refusal the draft stays and the server's `message` shows.
  Future<bool> save() async {
    if (isSaving.value) return false;
    final body = changes;
    if (body.isEmpty) return true;
    final problem = DetailsRules.skillsError(draft.skills);
    if (problem != null) {
      error.value = problem;
      return false;
    }
    isSaving.value = true;
    error.value = null;
    try {
      await repository.updateDetails(body);
      _saved = draft;
      _refresh();
      AppNotices.success(ProfileTexts.detailsSaved);
      return true;
    } on SocketCallError catch (e, st) {
      AppLog.e('profile_details_controller', e, st);
      error.value = e.isConnectionGap
          ? ProfileTexts.offline
          : (e.message.isEmpty ? ProfileTexts.detailsSaveFailed : e.message);
      return false;
    } catch (e, st) {
      AppLog.e('profile_details_controller', e, st);
      error.value = ProfileTexts.detailsSaveFailed;
      return false;
    } finally {
      if (!isClosed) isSaving.value = false;
    }
  }

  @override
  void onClose() {
    address.dispose();
    education.dispose();
    skills.dispose();
    super.onClose();
  }
}
