import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/theme/app_presence.dart';
import 'package:connectum/core/theme/app_theme.dart';
import 'package:connectum/data/profile/presence.dart';
import 'package:connectum/data/repositories/presence_repository.dart';
import 'package:connectum/features/person_profile/models/person_card.dart';
import 'package:connectum/features/person_profile/person_profile_controller.dart';
import 'package:connectum/features/person_profile/person_profile_view.dart';
import 'package:connectum/features/profile/profile_texts.dart';
import 'package:connectum/features/profile/widgets/presence_pill.dart';
import 'package:connectum/features/profile/widgets/profile_identity_card.dart';
import 'package:connectum/features/profile_details/profile_details_controller.dart';
import 'package:connectum/features/profile_details/profile_details_view.dart';
import 'package:connectum/features/profile_status/profile_status_controller.dart';
import 'package:connectum/features/profile_status/profile_status_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'profile_fakes.dart';

void _phone(WidgetTester tester, {double width = 320, double scale = 1.5}) {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Widget _app(Widget home) => MaterialApp(theme: AppTheme.light, home: home);

class _Presence extends Fake implements PresenceRepository {
  _Presence(this.isUp);
  final bool isUp;
  @override
  PresenceDot dotFor(String username) =>
      isUp ? PresenceDot.online : PresenceDot.offline;
}

void main() {
  setUp(() {
    Get.reset();
    Get.testMode = true;
  });

  group('hero card', () {
    Widget card({
      Presence presence = Presence.busy,
      String? status = 'In the office until 5, back on Monday morning',
    }) => _app(
      Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ProfileIdentityCard(
              name: 'Alexandra Montgomery-Featherstonehaugh',
              username: 'alexandra.montgomery.featherstonehaugh',
              organisation:
                  'Greenfield Community Health and Wellbeing Cooperative',
              designation: 'Senior Regional Operations Coordinator',
              roles: const ['admin', 'approver', 'records'],
              presence: presence,
              status: status,
              onStatusTap: () {},
              onPhotoTap: () {},
            ),
          ),
        ),
      ),
    );

    testWidgets('fits at 320 px and 1.5x text without overflow', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(card());
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Busy'), findsOneWidget);
      expect(find.textContaining('In the office'), findsOneWidget);
      expect(find.text('admin'), findsOneWidget);
    });

    testWidgets('the presence pill and the status line are 44 pt tall', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(card());
      await tester.pump();
      final pill = tester.getSize(find.byType(PresencePill));
      expect(pill.height, greaterThanOrEqualTo(44));
      final line = tester.getSize(find.byType(StatusLine));
      expect(line.height, greaterThanOrEqualTo(44));
    });

    testWidgets('tapping the pill or the status line opens the editor', (
      tester,
    ) async {
      _phone(tester, scale: 1);
      var taps = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SingleChildScrollView(
              child: ProfileIdentityCard(
                name: 'Ana',
                username: 'ana',
                organisation: '',
                presence: Presence.available,
                status: 'Hello',
                onStatusTap: () => taps++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Available'));
      await tester.tap(find.text('Hello'));
      expect(taps, 2);
    });

    testWidgets('no status shows a muted "Add a status"', (tester) async {
      _phone(tester, scale: 1);
      await tester.pumpWidget(card(status: null));
      expect(find.text('Add a status'), findsOneWidget);
      final text = tester.widget<Text>(find.text('Add a status'));
      expect(text.style!.color, AppColors.muted);
    });

    testWidgets('the dot is the colour of the presence', (tester) async {
      _phone(tester, scale: 1);
      for (final p in Presence.values) {
        await tester.pumpWidget(card(presence: p));
        final dot = tester.widget<Container>(
          find.byKey(const ValueKey('profile-presence-dot')),
        );
        final color = (dot.decoration! as BoxDecoration).color;
        expect(color, AppPresenceTones.dot(p), reason: p.wire);
      }
      expect(
        AppPresenceTones.dot(Presence.busy),
        AppPresenceTones.dot(Presence.dnd),
      );
      expect(
        AppPresenceTones.dot(Presence.meeting),
        AppPresenceTones.of(Presence.meeting).solid,
      );
      expect(
        AppPresenceTones.dot(Presence.away),
        AppPresenceTones.of(Presence.away).solid,
      );
    });

    testWidgets('without designation, enterprise or roles the chips are gone', (
      tester,
    ) async {
      _phone(tester, scale: 1);
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: ProfileIdentityCard(
              name: 'Ana',
              username: 'ana',
              organisation: '',
              presence: Presence.available,
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.apartment_outlined), findsNothing);
    });
  });

  group('discard prompt', () {
    Future<void> openFrom(WidgetTester tester, Widget screen) async {
      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Get.to<void>(() => screen),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'status: asks before leaving with changes; Keep editing stays',
      (tester) async {
        _phone(tester, scale: 1);
        final rig = ProfileRig()
          ..ownProfile(status: null, presence: 'available');
        final c = ProfileStatusController(
          repository: rig.repository,
          profiles: rig.profiles,
          avatars: rig.avatars,
          store: rig.session,
        );
        Get.put(c);
        await openFrom(tester, const ProfileStatusView());
        await tester.enterText(find.byType(TextField), 'Working from home');
        await tester.pump();
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        expect(find.text('Discard your changes?'), findsOneWidget);
        expect(find.text(ProfileTexts.discardBody), findsOneWidget);
        await tester.tap(find.text(ProfileTexts.keepEditing));
        await tester.pumpAndSettle();
        expect(find.byType(ProfileStatusView), findsOneWidget);
        expect(c.text.text, 'Working from home');

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(find.byType(ProfileStatusView), findsNothing);
        expect(rig.socket.sent, isEmpty);
      },
    );

    testWidgets('status: no prompt when nothing changed', (tester) async {
      _phone(tester, scale: 1);
      final rig = ProfileRig()..ownProfile(status: 'x', presence: 'busy');
      Get.put(
        ProfileStatusController(
          repository: rig.repository,
          profiles: rig.profiles,
          avatars: rig.avatars,
          store: rig.session,
        ),
      );
      await openFrom(tester, const ProfileStatusView());
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsNothing);
      expect(find.byType(ProfileStatusView), findsNothing);
    });

    testWidgets('status: the counter, the 140 cut and the preview', (
      tester,
    ) async {
      _phone(tester, scale: 1);
      final rig = ProfileRig()..ownProfile();
      Get.put(
        ProfileStatusController(
          repository: rig.repository,
          profiles: rig.profiles,
          avatars: rig.avatars,
          store: rig.session,
        ),
      );
      await openFrom(tester, const ProfileStatusView());
      expect(find.text('0/140'), findsOneWidget);
      expect(find.text('No status message'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        '${'a' * 135}😀😀😀😀😀😀😀',
      );
      await tester.pump();
      expect(find.text('140/140'), findsOneWidget);
      final counter = tester.widget<Text>(
        find.byKey(const ValueKey('status-counter')),
      );
      expect(counter.style!.fontWeight, FontWeight.w700);
      await tester.enterText(find.byType(TextField), 'short\nline');
      await tester.pump();
      expect(find.text('9/140'), findsOneWidget);
      expect(find.text('shortline'), findsWidgets);
      for (final p in Presence.values) {
        expect(find.text(p.label), findsOneWidget);
      }
    });

    testWidgets('status: the chosen presence shows a check', (tester) async {
      _phone(tester, scale: 1);
      final rig = ProfileRig()..ownProfile(status: null, presence: 'away');
      Get.put(
        ProfileStatusController(
          repository: rig.repository,
          profiles: rig.profiles,
          avatars: rig.avatars,
          store: rig.session,
        ),
      );
      await openFrom(tester, const ProfileStatusView());
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await tester.tap(find.text('Busy'));
      await tester.pump();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('details: asks before leaving with changes', (tester) async {
      _phone(tester, scale: 1);
      final rig = ProfileRig();
      rig.socket.onSd = (a, b) async => {
        'profile': {'address': 'Old', 'skills': <String>[]},
      };
      final c = ProfileDetailsController(repository: rig.repository);
      Get.put(c);
      await openFrom(tester, const ProfileDetailsView());
      expect(find.text(ProfileTexts.detailsPrivate), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'New address');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsOneWidget);
      await tester.tap(find.text(ProfileTexts.keepEditing));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileDetailsView), findsOneWidget);
      expect(c.address.text, 'New address');
    });

    testWidgets('details: byte counters and skill chips', (tester) async {
      _phone(tester, scale: 1);
      final rig = ProfileRig();
      rig.socket.onSd = (a, b) async => {'profile': <String, dynamic>{}};
      Get.put(ProfileDetailsController(repository: rig.repository));
      await openFrom(tester, const ProfileDetailsView());
      expect(find.text('0/200 bytes'), findsOneWidget);
      expect(find.text('0/120 bytes'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'é' * 150);
      await tester.pump();
      expect(find.text('200/200 bytes'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Dart, Erlang, dart');
      await tester.pump();
      expect(find.text('Dart'), findsOneWidget);
      expect(find.text('Erlang'), findsOneWidget);
      expect(find.textContaining('2/30 skills'), findsOneWidget);
    });
  });

  group("another person's profile", () {
    Future<PersonProfileController> show(
      WidgetTester tester,
      PersonCard card, {
      bool online = false,
      String? status,
      Object? presence = 'busy',
    }) async {
      _phone(tester, scale: 1.5);
      final rig = ProfileRig();
      if (status != null || presence != null) {
        rig.profiles.onEvent(
          profileEvent(card.username, status: status, presence: presence),
        );
      }
      final c = PersonProfileController(
        card: card,
        profiles: rig.profiles,
        presence: _Presence(online),
        avatars: rig.avatars,
      );
      Get.put(c);
      await tester.pumpWidget(
        GetMaterialApp(theme: AppTheme.light, home: const PersonProfileView()),
      );
      await tester.pump();
      return c;
    }

    testWidgets('shows what is held, with Close and Message', (tester) async {
      await show(
        tester,
        const PersonCard(
          username: 'ravi',
          name: 'Ravi Kumar',
          designation: 'Nurse',
          department: 'Ward',
          branch: 'Pune',
          email: 'ravi@clinic.test',
          mobile: '+91 98765 43210',
        ),
        online: true,
        status: 'On rounds',
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Ravi Kumar'), findsOneWidget);
      expect(find.text('@ravi'), findsOneWidget);
      expect(find.text('Nurse'), findsOneWidget);
      expect(find.text('Ward • Pune'), findsOneWidget);
      expect(find.text('ravi@clinic.test'), findsOneWidget);
      expect(find.text('+91 98765 43210'), findsOneWidget);
      expect(find.byKey(const ValueKey('person-status')), findsOneWidget);
      expect(find.text('Busy'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
    });

    testWidgets('a missing value shows nothing, no web fallbacks', (
      tester,
    ) async {
      await show(tester, const PersonCard(username: 'sam'), presence: null);
      expect(find.text('sam'), findsOneWidget);
      expect(find.text('Bangalore HQ'), findsNothing);
      expect(find.text('Connectum member'), findsNothing);
      expect(find.text('Active on Connectum'), findsNothing);
      expect(find.text('WORK'), findsNothing);
      expect(find.text('CONTACT'), findsNothing);
      expect(find.byKey(const ValueKey('person-status')), findsNothing);
    });

    testWidgets('department alone has no bullet', (tester) async {
      await show(
        tester,
        const PersonCard(username: 'sam', department: 'Billing'),
        presence: null,
      );
      expect(find.text('Billing'), findsOneWidget);
      expect(find.textContaining('•'), findsNothing);
    });

    testWidgets('presence shows only while the person is online', (
      tester,
    ) async {
      await show(
        tester,
        const PersonCard(username: 'sam'),
        online: false,
        presence: 'dnd',
      );
      expect(find.byType(PresencePill), findsNothing);
      expect(find.byType(PresenceDotView), findsNothing);
    });

    testWidgets('online with no choice reads the status text', (tester) async {
      await show(
        tester,
        const PersonCard(username: 'sam'),
        online: true,
        status: 'In a meeting',
        presence: null,
      );
      expect(find.text('In a meeting'), findsWidgets);
      expect(find.byType(PresencePill), findsOneWidget);
    });
  });
}
