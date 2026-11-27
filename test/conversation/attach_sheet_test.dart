import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/widgets/tonal_accent.dart';
import 'package:connectum/data/repositories/attachment_repository.dart';
import 'package:connectum/features/conversation/conversation_controller.dart';
import 'package:connectum/features/conversation/widgets/attach_circle_button.dart';
import 'package:connectum/features/conversation/widgets/attach_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeController implements ConversationController {
  final picked = <AttachSource>[];
  @override
  Future<void> attach(AttachSource source) async => picked.add(source);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<_FakeController> _open(
  WidgetTester tester, {
  double scale = 1.0,
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  final c = _FakeController();
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale), padding: padding),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => AttachSheet.show(context, c),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('one header, one close, three circles in a row, no labels', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text('Attach'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byType(AttachCircleButton), findsNWidgets(3));
    for (final l in ['Photo library', 'Camera', 'Document']) {
      expect(find.text(l), findsNothing);
      expect(find.bySemanticsLabel(l), findsOneWidget);
      expect(find.byTooltip(l), findsOneWidget);
    }
    final ys = [
      for (final e in find.byType(AttachCircleButton).evaluate())
        tester.getCenter(find.byWidget(e.widget)).dy,
    ];
    expect(ys.toSet().length, 1);
    expect(
      tester.getSize(find.byType(AttachCircleButton).first),
      const Size(56, 56),
    );
  });

  testWidgets('each circle starts its own flow and closes the sheet', (
    tester,
  ) async {
    final c = await _open(tester);
    await tester.tap(find.byIcon(Icons.photo_library_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(AttachSheet), findsNothing);
    expect(c.picked, [AttachSource.library]);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.photo_camera_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.description_outlined));
    await tester.pumpAndSettle();
    expect(c.picked, [
      AttachSource.library,
      AttachSource.camera,
      AttachSource.document,
    ]);
  });

  testWidgets('X closes the sheet', (tester) async {
    await _open(tester);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(AttachSheet), findsNothing);
  });

  testWidgets('accents differ and are stable', (tester) async {
    await _open(tester);
    final colors = <Color>[];
    for (final icon in [
      Icons.photo_library_outlined,
      Icons.photo_camera_outlined,
      Icons.description_outlined,
    ]) {
      colors.add(tester.widget<Icon>(find.byIcon(icon)).color!);
    }
    expect(colors.toSet().length, 3);
    expect(colors, [
      AppColors.primaryBright,
      AppColors.violet,
      AppColors.yesDot,
    ]);
    final box = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(AttachCircleButton).first,
            matching: find.byType(Container),
          )
          .first,
    );
    expect(box.decoration, TonalAccent.circle(AppColors.primaryBright));
  });

  testWidgets('height wraps content and respects the bottom inset', (
    tester,
  ) async {
    await _open(tester);
    final plain = tester.getSize(find.byType(AttachSheet)).height;
    expect(plain, lessThan(200));
    await tester.pumpWidget(const SizedBox());
    await _open(tester, padding: const EdgeInsets.only(bottom: 30));
    expect(tester.getSize(find.byType(AttachSheet)).height, plain + 30);
  });

  testWidgets('text scale 1.3 does not overflow', (tester) async {
    await _open(tester, scale: 1.3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a circle with no handler is faded and inert', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AttachCircleButton(
            icon: Icons.camera,
            label: 'Camera',
            accent: AppColors.violet,
          ),
        ),
      ),
    );
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.4);
  });
}
