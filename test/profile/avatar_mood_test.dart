import 'package:connectum/core/theme/app_presence.dart';
import 'package:connectum/core/theme/app_theme.dart';
import 'package:connectum/core/widgets/app_avatar.dart';
import 'package:connectum/data/profile/presence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets(
    'an online person shows a ring and a dot in the presence colour',
    (tester) async {
      for (final p in Presence.values) {
        await tester.pumpWidget(
          _wrap(
            AppAvatar(
              name: 'Ana',
              kind: AppAvatarKind.person,
              presence: AppPresenceDot.online,
              mood: p,
            ),
          ),
        );
        final ring = tester.widget<DecoratedBox>(
          find.byKey(const ValueKey('avatar-mood-ring')),
        );
        final border = (ring.decoration as BoxDecoration).border! as Border;
        expect(border.top.color, AppPresenceTones.dot(p), reason: p.wire);
      }
    },
  );

  testWidgets('without a mood the online dot is plain and has no ring', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const AppAvatar(
          name: 'Ana',
          kind: AppAvatarKind.person,
          presence: AppPresenceDot.online,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('avatar-mood-ring')), findsNothing);
  });

  testWidgets('no dot, no ring when the person is not online', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AppAvatar(
          name: 'Ana',
          kind: AppAvatarKind.person,
          mood: Presence.busy,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('avatar-mood-ring')), findsNothing);
  });
}
