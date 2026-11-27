import 'dart:async';

import '../../demo/demo_mode.dart';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../../core/routes/app_routes.dart';
import '../../core/routes/home_reload.dart';
import 'package:connectum/core/log/log.dart';
import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/tour/tour.dart';
import 'package:connectum/core/utils/utils.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import 'package:connectum/features/chats/chats.dart';
import 'package:connectum/features/password/password.dart';
import 'package:connectum/features/qr/qr.dart';
import 'package:connectum/features/settings/settings.dart';
import '../../data/profile_photo/profile_photo_picker.dart';
import '../../data/session_store.dart';
import 'profile_tour.dart';
import '../../data/profile/personal_details.dart';
import '../../data/profile/presence.dart';

class ProfileController extends GetxController {
  ProfileController({
    required this.store,
    required this.session,
    required this.connectivity,
    required this.switcher,
    required this.qr,
    required this.avatars,
    required this.photos,
    required this.picker,
    this.logs,
    this.tour,
    this.profileTour,
    this.profiles,
    this.repository,
  });

  final SessionStore store;
  final SessionRepository session;
  final ConnectivityService connectivity;
  final EnterpriseSwitcherController switcher;
  final QrRepository qr;
  final PeopleAvatars avatars;
  final ProfilePhotoRepository photos;
  final ProfilePhotoPicker picker;

  /// People's status and chosen presence; null where it is not set up.
  final PeopleProfiles? profiles;

  /// The own profile record (roles, designation); null where it is not set up.
  final ProfileRepository? repository;

  /// `profile.get`, once it has answered: the header's roles and designation.
  final record = Rxn<ProfileRecord>();

  /// The first-run tours; null where they are not set up.
  final TourService? tour;

  /// The first-run tour of this screen; null where tours are not set up.
  final ProfileTour? profileTour;
  late final TourTrigger _tourTrigger = TourTrigger(
    canTry: () => profileTour != null && !isClosed && !isPhotoBusy.value,
    start: _startTour,
  );

  /// The Logs section's controller; null when logging could not be set up.
  final LogsController? logs;

  /// True while a new picture is being sent or the old one removed.
  final isPhotoBusy = false.obs;

  /// 0 to 1 while a picture is uploading, null otherwise.
  final photoProgress = Rxn<double>();
  final isCopied = false.obs;
  final isLoggingOut = false.obs;
  final version = RxnString();
  Timer? _copiedTimer;

  @override
  void onInit() {
    super.onInit();
    AppSettings.version().then((v) => version.value = v);
    fireAndLog('profile_controller', _loadRecord);
  }

  Future<void> _loadRecord() async {
    final repo = repository;
    if (repo == null || SeedUi.isActive || !repo.isOnline) return;
    try {
      final loaded = await repo.loadRecord();
      if (!isClosed) record.value = loaded;
    } on SocketCallError catch (e, st) {
      AppLog.e('profile_controller', e, st, 'profile.get');
    }
  }

  /// What the own profile shows. Reads an Rx value: call it in Obx.
  Presence get presence => profiles?.presenceOf(username) ?? Presence.available;

  /// The own status message, or null. Reads an Rx value.
  String? get status => profiles?.statusOf(username);

  String get designation => record.value?.designation ?? '';

  List<String> get roles => record.value?.roles ?? const [];

  void openStatus() => Get.toNamed(AppRoutes.profileStatus);

  void openDetails() => Get.toNamed(AppRoutes.profileDetails);

  String get name {
    if (SeedUi.isActive) return SeedUi.profile().name;
    final identity = store.identity.value;
    if (identity != null && identity.name.isNotEmpty) return identity.name;
    return store.userId ?? identity?.username ?? '';
  }

  String get username => SeedUi.isActive
      ? SeedUi.profile().username
      : (store.identity.value?.username ?? '');

  String get email => SeedUi.isActive
      ? SeedUi.profile().email
      : (store.identity.value?.email ?? '');

  String get connectumId => SeedUi.isActive
      ? SeedUi.profile().connectumId
      : (store.identity.value?.connectumId ?? '');

  String get organisation => switcher.currentName;

  String get category {
    if (SeedUi.isActive) return SeedUi.profile().category;
    for (final m in switcher.enterprises) {
      if (m.enterprise == switcher.currentOrgId) return m.category;
    }
    return '';
  }

  bool get isOnline =>
      connectivity.state.value == AppConnectivity.online || SeedUi.isActive;

  Future<void> copyConnectumId() async {
    if (connectumId.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: connectumId));
    isCopied.value = true;
    _copiedTimer?.cancel();
    _copiedTimer = Timer(AppDurations.copiedHold, () => isCopied.value = false);
  }

  /// The own picture's address, or null. Reads an Rx value: call it in Obx.
  String? get picture => avatars.urlOf(username);

  bool get hasPhoto => picture != null;

  /// Picks a picture, lets the person crop it, then uploads it. The new
  /// picture shows at once; a failure puts the old one back.
  Future<void> changePhoto(PhotoSource source) async {
    if (isPhotoBusy.value) return;
    try {
      final picked = await picker.pick(source);
      if (picked == null || isClosed) return;
      // Untyped: GetX builds a GetPageRoute<dynamic>, which a typed
      // pushNamed<Uint8List> cannot accept.
      final result = await Get.toNamed(
        AppRoutes.photoCrop,
        arguments: {'bytes': picked},
      );
      if (isClosed || result is! Uint8List) return;
      await _replace(
        () => photos.upload(
          result,
          onProgress: (p) => photoProgress.value = p,
          cancel: CancelToken(),
        ),
        shown: AvatarImages.registerMemory(result),
      );
    } on PhotoPickException catch (e) {
      if (!isClosed) _pickFailed(e);
    } catch (e, st) {
      AppLog.e('profile_controller', e, st);
      debugPrint('changePhoto failed: ${e.runtimeType}');
      if (!isClosed) {
        AppNotices.show(
          "Couldn't open the photo editor. Try again.",
          variant: AppNoticeVariant.error,
        );
      }
    }
  }

  Future<void> removePhoto() => _replace(photos.remove, shown: null);

  /// Shows [shown] as the own picture, runs [work] and keeps the answer; any
  /// failure restores what was there and says why.
  Future<void> _replace(
    Future<Object?> Function() work, {
    String? shown,
  }) async {
    final name = username;
    final previous = avatars.urlOf(name);
    isPhotoBusy.value = true;
    photoProgress.value = shown == null ? null : 0;
    try {
      await avatars.set(name, shown);
      final result = await work();
      if (result is String) await avatars.set(name, result);
    } on ProfilePhotoException catch (e) {
      await avatars.set(name, previous);
      AppNotices.show(
        e.message,
        variant: e.error == ProfilePhotoError.network
            ? AppNoticeVariant.warning
            : AppNoticeVariant.error,
      );
    } catch (e, st) {
      AppLog.e('profile_controller', e, st);
      debugPrint('photo update failed: ${e.runtimeType}');
      await avatars.set(name, previous);
      AppNotices.show(
        "Couldn't update your photo. Try again.",
        variant: AppNoticeVariant.error,
      );
    } finally {
      if (!isClosed) {
        isPhotoBusy.value = false;
        photoProgress.value = null;
      }
    }
  }

  void _pickFailed(PhotoPickException e) {
    final isDenied =
        e.error == PhotoPickError.cameraDenied ||
        e.error == PhotoPickError.libraryDenied;
    AppNotices.show(
      isDenied ? '${e.message} Turn it on in Settings to continue.' : e.message,
      variant: isDenied ? AppNoticeVariant.warning : AppNoticeVariant.error,
      actionLabel: isDenied ? 'Open Settings' : null,
      onAction: isDenied ? AppSettings.open : null,
    );
  }

  void prepareSwitcher() => switcher.prepare();

  Future<void> openQr(BuildContext context) =>
      QrSheet.show(context, repository: qr);

  bool get hasPassword => store.identity.value?.hasPassword ?? false;

  Future<void> openPassword(BuildContext context) =>
      PasswordSheet.show(context, hasPassword: hasPassword);

  void openSecurity() => Get.toNamed(AppRoutes.security);

  void replayIntroduction() =>
      Get.toNamed(AppRoutes.onboarding, arguments: {'replay': true});

  /// "Replay all tours": every tour plays again as the person visits its
  /// screen.
  Future<void> replayTours() async {
    final tour = this.tour;
    if (tour == null) return;
    try {
      await tour.resetAll();
      AppNotices.info(TourTexts.replayDone);
    } catch (e, st) {
      AppLog.e('profile_controller', e, st);
    }
  }

  Future<int> unsentCount() async =>
      SeedUi.isActive ? SeedUi.profileUnsent.value : session.unsentCount();

  /// Takes the home down first (as an enterprise switch does), then signs out
  /// everywhere and opens the sign-in screen. A failed server call never
  /// blocks the local sign-out.
  Future<void> logOut() async {
    if (isLoggingOut.value) return;
    isLoggingOut.value = true;
    try {
      if (SeedUi.isActive && !DemoMode.isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        Get.back<void>();
        return;
      }
      final retire = HomeReload.retireHome;
      HomeReload.retireHome = null;
      retire?.call();
      await WidgetsBinding.instance.endOfFrame;
      await session.logOut(notice: "You're logged out.");
    } finally {
      isLoggingOut.value = false;
    }
  }

  @override
  void onReady() {
    super.onReady();
    if (profileTour != null) _tourTrigger.schedule();
  }

  Future<TourStart> _startTour() async {
    final tour = profileTour;
    if (tour == null || isClosed) return TourStart.failed;
    await WidgetsBinding.instance.endOfFrame;
    if (isClosed) return TourStart.failed;
    return tour.start();
  }

  @override
  void onClose() {
    _tourTrigger.dispose();
    profileTour?.cancel();
    _copiedTimer?.cancel();
    logs?.dispose();
    super.onClose();
  }
}
