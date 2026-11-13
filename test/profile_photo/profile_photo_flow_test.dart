import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:connectum/core/routes/app_pages.dart';
import 'package:connectum/core/routes/app_routes.dart';
import 'package:connectum/core/theme/app_theme.dart';
import 'package:connectum/core/widgets/avatar_image.dart';
import 'package:connectum/core/widgets/app_notices.dart';
import 'package:connectum/data/models/identity_info.dart';
import 'package:connectum/data/profile_photo/profile_photo_picker.dart';
import 'package:connectum/data/repositories/people_avatars.dart';
import 'package:connectum/data/repositories/profile_photo_repository.dart';
import "package:connectum/data/repositories/qr_repository.dart";
import "package:connectum/data/repositories/session_repository.dart";
import 'package:connectum/data/session_store.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/features/chats/enterprise_switcher_controller.dart';
import 'package:connectum/features/profile/profile_controller.dart';
import 'package:connectum/features/profile/profile_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _Store extends Fake implements SessionStore {
  @override
  final identity = Rxn<IdentityInfo>(
    const IdentityInfo(
      token: 't',
      email: 'me@test.co',
      enterprises: [],
      username: 'me',
      name: 'Me',
    ),
  );
  @override
  String? get orgId => null;
  @override
  String? get userId => 'me';
}

class _Switcher extends Fake implements EnterpriseSwitcherController {
  @override
  String get currentName => 'Org';
  @override
  String? get currentOrgId => null;
  @override
  List<EnterpriseMembership> get enterprises => const [];
}

class _Avatars extends Fake implements PeopleAvatars {
  @override
  final urls = <String, String>{}.obs;
  @override
  String? urlOf(String? username) => urls[(username ?? '').toLowerCase()];
  @override
  Future<void> set(String username, String? url) async {
    if (url == null) {
      urls.remove(username);
    } else {
      urls[username] = url;
    }
  }
}

class _Picker implements ProfilePhotoPicker {
  _Picker(this.result);

  Object? result;
  final sources = <PhotoSource>[];

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    sources.add(source);
    final r = result;
    if (r is Exception || r is Error) throw r!;
    return r as Uint8List?;
  }
}

class _Failing extends Fake implements ProfilePhotoRepository {
  @override
  Future<String> upload(
    Uint8List bytes, {
    required void Function(double progress) onProgress,
    dynamic cancel,
  }) async => throw StateError('boom');
}

Future<Uint8List> _png() async {
  final r = ui.PictureRecorder();
  ui.Canvas(r).drawRect(
    const ui.Rect.fromLTWH(0, 0, 400, 300),
    ui.Paint()..color = const ui.Color(0xFF3366CC),
  );
  final image = await r.endRecording().toImage(400, 300);
  return (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
}

class _Rig {
  _Rig(this.picker, this.photos, this.avatars);
  final _Picker picker;
  final ProfilePhotoRepository photos;
  final _Avatars avatars;
  late ProfileController controller;
}

Future<_Rig> _pumpApp(
  WidgetTester tester, {
  required Object? pick,
  ProfilePhotoRepository? photos,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  Get.reset();
  Get.testMode = true;
  final rig = _Rig(
    _Picker(pick),
    photos ??
        FakeProfilePhotoRepository(
          delay: const Duration(milliseconds: 30),
          register: AvatarImages.registerMemory,
        ),
    _Avatars(),
  );
  final crop = AppPages.pages.firstWhere((p) => p.name == AppRoutes.photoCrop);
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.light,
      initialRoute: '/profile',
      builder: (context, child) =>
          AppNoticeHost(child: child ?? const SizedBox.shrink()),
      getPages: [
        GetPage(
          name: '/profile',
          page: () => const ProfileView(),
          binding: BindingsBuilder(() {
            rig.controller = ProfileController(
              store: _Store(),
              session: _NoSession(),
              connectivity: ConnectivityService(),
              switcher: _Switcher(),
              qr: _NoQr(),
              avatars: rig.avatars,
              photos: rig.photos,
              picker: rig.picker,
            );
            Get.put(rig.controller);
          }),
        ),
        crop,
      ],
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
  addTearDown(Get.reset);
  return rig;
}

class _NoSession extends Fake implements SessionRepository {}

class _NoQr extends Fake implements QrRepository {}

Future<void> _settle(WidgetTester tester, [int ms = 400]) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pump(Duration(milliseconds: ms));
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(
    find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Change profile photo',
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('camera: crop opens, Done uploads, avatar updates', (
    tester,
  ) async {
    final bytes = (await tester.runAsync(_png))!;
    final rig = await _pumpApp(tester, pick: bytes);
    await _choose(tester, 'Take photo');
    await _settle(tester);
    expect(rig.picker.sources, [PhotoSource.camera]);
    expect(find.text('Adjust your photo'), findsOneWidget);

    await tester.tap(find.text('Done'));
    for (var i = 0; i < 20 && rig.controller.avatars.urlOf('me') == null; i++) {
      await _settle(tester, 100);
    }
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    final fake = rig.photos as FakeProfilePhotoRepository;
    expect(fake.uploads, hasLength(1));
    expect(find.text('Adjust your photo'), findsNothing);
    expect(rig.avatars.urlOf('me'), startsWith('memory:'));
    expect(rig.controller.isPhotoBusy.value, isFalse);
  });

  testWidgets('gallery reaches the crop screen too', (tester) async {
    final bytes = (await tester.runAsync(_png))!;
    final rig = await _pumpApp(tester, pick: bytes);
    await _choose(tester, 'Choose from gallery');
    await _settle(tester);
    expect(rig.picker.sources, [PhotoSource.gallery]);
    expect(find.text('Adjust your photo'), findsOneWidget);
  });

  testWidgets('cancelling the crop uploads nothing and shows no error', (
    tester,
  ) async {
    final bytes = (await tester.runAsync(_png))!;
    final rig = await _pumpApp(tester, pick: bytes);
    await _choose(tester, 'Take photo');
    await _settle(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect((rig.photos as FakeProfilePhotoRepository).uploads, isEmpty);
    expect(find.text('Adjust your photo'), findsNothing);
    expect(find.textContaining("Couldn't"), findsNothing);
    expect(rig.avatars.urlOf('me'), isNull);
    expect(rig.controller.isPhotoBusy.value, isFalse);
  });

  testWidgets('a picker that throws shows the notice', (tester) async {
    final rig = await _pumpApp(tester, pick: StateError('camera exploded'));
    await _choose(tester, 'Take photo');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("Couldn't open the photo editor. Try again."), findsOne);
    expect(rig.controller.isPhotoBusy.value, isFalse);
    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('an unexpected upload error restores state and shows a notice', (
    tester,
  ) async {
    final bytes = (await tester.runAsync(_png))!;
    final rig = await _pumpApp(tester, pick: bytes, photos: _Failing());
    await _choose(tester, 'Take photo');
    await _settle(tester);
    await tester.tap(find.text('Done'));
    await _settle(tester, 100);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("Couldn't update your photo. Try again."), findsOne);
    expect(rig.avatars.urlOf('me'), isNull);
    expect(rig.controller.isPhotoBusy.value, isFalse);
    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(milliseconds: 400));
  });
}
