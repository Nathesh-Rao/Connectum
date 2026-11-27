import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/theme/app_spacing.dart';
import 'package:connectum/core/widgets/app_png_icon.dart';
import 'package:connectum/data/models/form_option.dart';
import 'package:connectum/data/repositories/form_options_repository.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/features/forms/forms_picker_controller.dart';
import 'package:connectum/core/widgets/app_search_field.dart';
import 'package:connectum/features/forms/widgets/form_chip.dart';
import 'package:connectum/features/forms/widgets/forms_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _FakeOptions implements FormOptionsRepository {
  @override
  final options = <FormOption>[].obs;
  @override
  final categories = <String, FormCategory>{}.obs;
  @override
  final recents = <FormRecent>[].obs;
  @override
  final isLoaded = true.obs;
  @override
  final hasError = false.obs;
  @override
  Future<void> refresh() async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeConnectivity implements ConnectivityService {
  @override
  final state = AppConnectivity.online.obs;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

FormOption _opt(String caption, {String type = 'data_input'}) => FormOption(
  id: caption,
  caption: caption,
  type: type,
  target: caption.toLowerCase(),
  targetScope: 'user',
  category: '',
  order: 0,
);

Future<FormsPickerController> _open(
  WidgetTester tester,
  List<FormOption> list, {
  double scale = 1.0,
  EdgeInsets padding = EdgeInsets.zero,
  List<FormRecent> recents = const [],
}) async {
  final repo = _FakeOptions()
    ..options.assignAll(list)
    ..recents.assignAll(recents);
  final c = FormsPickerController(
    options: repo,
    connectivity: _FakeConnectivity(),
    shell: null,
  );
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
            onPressed: () => FormsPickerSheet.show(context, c),
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
  testWidgets('one header, one close button, shared search field', (
    tester,
  ) async {
    await _open(tester, [_opt('Leave')]);
    expect(find.text('Forms'), findsNWidgets(2));
    expect(find.text('Choose a form to fill in'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byType(AppSearchField), findsOneWidget);
  });

  testWidgets('chips wrap and launch; My Submissions lives in the bar', (
    tester,
  ) async {
    await _open(tester, [_opt('Leave'), _opt('Expense')]);
    expect(find.byType(FormChip), findsNWidgets(2));
    final a = tester.getTopLeft(find.widgetWithText(FormChip, 'Leave'));
    final b = tester.getTopLeft(find.widgetWithText(FormChip, 'Expense'));
    expect(a.dy, b.dy);
    expect(find.text('My Submissions'), findsOneWidget);
    expect(find.text('2 forms'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('My Submissions')).dy,
      greaterThan(a.dy),
    );
    final chip = tester.widget<FormChip>(
      find.widgetWithText(FormChip, 'Leave'),
    );
    expect(chip.onTap, isNotNull);
  });

  testWidgets('Show all only above 12 and expands', (tester) async {
    await _open(tester, [for (var i = 0; i < 12; i++) _opt('Form $i')]);
    expect(find.text('Show all'), findsNothing);
    Navigator.of(tester.element(find.text('Form 0'))).pop();
    await tester.pumpAndSettle();

    await _open(tester, [for (var i = 0; i < 15; i++) _opt('Form $i')]);
    expect(find.byType(FormChip, skipOffstage: false), findsNWidgets(12));
    await tester.ensureVisible(find.text('Show all'));
    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();
    expect(find.text('Show all'), findsNothing);
    expect(find.byType(FormChip, skipOffstage: false), findsNWidgets(15));
  });

  testWidgets('search shows every match without the link', (tester) async {
    await _open(tester, [for (var i = 0; i < 15; i++) _opt('Form $i')]);
    await tester.enterText(find.byType(TextField), 'form');
    await tester.pumpAndSettle();
    expect(find.text('Show all'), findsNothing);
    expect(find.byType(FormChip, skipOffstage: false), findsNWidgets(15));
  });

  testWidgets('unavailable chips are inert and the section hides if empty', (
    tester,
  ) async {
    await _open(tester, [_opt('Leave')]);
    expect(find.text('Not available on mobile yet'), findsNothing);
    Navigator.of(tester.element(find.text('Leave'))).pop();
    await tester.pumpAndSettle();

    await _open(tester, [
      _opt('Leave'),
      _opt('Test link', type: 'axpert_iview'),
    ]);
    expect(find.text('Not available on mobile yet'), findsOneWidget);
    expect(find.text("Isn't available on mobile yet"), findsNothing);
    final chip = tester.widget<FormChip>(
      find.widgetWithText(FormChip, 'Test link'),
    );
    expect(chip.onTap, isNull);
    expect(find.text('1 form'), findsOneWidget);
  });

  testWidgets('search filters chips and shows the empty state', (tester) async {
    await _open(tester, [_opt('Leave'), _opt('Expense')]);
    await tester.enterText(find.byType(TextField), 'exp');
    await tester.pumpAndSettle();
    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Leave'), findsNothing);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('No forms found'), findsOneWidget);
    expect(find.text('Try a different name'), findsOneWidget);
  });

  testWidgets('fits at text scale 1.3 with long names', (tester) async {
    await _open(tester, [
      _opt('A very long form name that keeps going and going for two lines'),
      _opt('Test link', type: 'link'),
    ], scale: 1.3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom bar respects the safe-area inset', (tester) async {
    await _open(tester, [
      _opt('Leave'),
    ], padding: const EdgeInsets.only(bottom: 48));
    final sheetBottom = tester.getBottomLeft(find.byType(BottomSheet)).dy;
    final barBottom = tester
        .getBottomLeft(find.widgetWithText(TextButton, 'My Submissions'))
        .dy;
    expect(sheetBottom - barBottom, greaterThanOrEqualTo(48));
  });

  testWidgets('chip icon comes from the dictionary, default otherwise', (
    tester,
  ) async {
    await _open(tester, [_opt('Leave request'), _opt('Zzz')]);
    IconData iconOf(String l) => tester
        .widget<Icon>(
          find.descendant(
            of: find.widgetWithText(FormChip, l),
            matching: find.byType(Icon),
          ),
        )
        .icon!;
    expect(iconOf('Leave request'), Icons.beach_access_outlined);
    expect(iconOf('Zzz'), Icons.description_outlined);
  });

  testWidgets('bottom bar count styles and text My Submissions', (
    tester,
  ) async {
    await _open(tester, [_opt('Leave'), _opt('Expense')]);
    final rich = tester.widget<RichText>(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == '2 forms',
      ),
    );
    final root = rich.text as TextSpan;
    final inner = root.children!.first as TextSpan;
    expect(root.style!.fontSize, 14);
    expect(root.style!.fontWeight, FontWeight.w500);
    expect(root.style!.color, AppColors.muted);
    final num = inner.children!.first as TextSpan;
    expect(num.style!.fontWeight, FontWeight.w600);
    expect(num.style!.color, AppColors.ink);
    expect(find.widgetWithText(TextButton, 'My Submissions'), findsOneWidget);
    expect(find.byIcon(Icons.history), findsNothing);
    expect(find.byType(AppPngIcon), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
  });

  testWidgets('a recent reads as its Forms chip; an unknown one is hidden', (
    tester,
  ) async {
    await _open(
      tester,
      [_opt('Punch In'), _opt('Leave')],
      recents: const [
        FormRecent(name: 'PUNCH IN', scope: 'user', caption: 'PUNCH IN'),
        FormRecent(name: 'gone', scope: 'user', caption: 'GONE'),
      ],
    );
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('PUNCH IN'), findsNothing);
    expect(find.text('GONE'), findsNothing);
    expect(find.text('Punch In'), findsNWidgets(2));
    expect(find.byIcon(Icons.history), findsOneWidget);
  });

  testWidgets('a form keeps one accent in Recent, Forms and search', (
    tester,
  ) async {
    final list = [_opt('Task'), _opt('Punch In'), _opt('Leave')];
    await _open(
      tester,
      list,
      recents: const [
        FormRecent(name: 'task', scope: 'user', caption: 'Task'),
        FormRecent(name: 'punch in', scope: 'user', caption: 'Punch In'),
        FormRecent(name: 'gone', scope: 'user', caption: 'Gone'),
      ],
    );
    Color borderOf(Finder f) =>
        ((tester
                            .widget<Container>(
                              find
                                  .descendant(
                                    of: f,
                                    matching: find.byType(Container),
                                  )
                                  .first,
                            )
                            .decoration!
                        as BoxDecoration)
                    .border!
                as Border)
            .top
            .color;
    for (final name in ['Task', 'Punch In']) {
      final chips = find.widgetWithText(FormChip, name);
      expect(chips, findsNWidgets(2));
      final expected = FormChip.decoration(
        FormChip.accentOf(name),
      ).border!.top.color;
      expect(borderOf(chips.at(0)), expected);
      expect(borderOf(chips.at(1)), expected);
    }
    expect(
      borderOf(find.widgetWithText(FormChip, 'Task').first),
      isNot(borderOf(find.widgetWithText(FormChip, 'Punch In').first)),
    );
    expect(find.text('Gone'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'task');
    await tester.pump(const Duration(seconds: 1));
    final searched = find.widgetWithText(FormChip, 'Task');
    expect(searched, findsOneWidget);
    expect(
      borderOf(searched),
      FormChip.decoration(FormChip.accentOf('Task')).border!.top.color,
    );
  });

  testWidgets('no matching recent hides the Recent section', (tester) async {
    await _open(
      tester,
      [_opt('Leave')],
      recents: const [FormRecent(name: 'gone', scope: 'u', caption: 'GONE')],
    );
    expect(find.text('Recent'), findsNothing);
  });

  testWidgets('chip flow uses the spacing tokens', (tester) async {
    await _open(tester, [_opt('Leave')]);
    final wrap = tester.widget<Wrap>(find.byType(Wrap).first);
    expect(wrap.spacing, AppSpacing.chipGap);
    expect(wrap.runSpacing, AppSpacing.chipRunGap);
    expect(AppSpacing.chipGap, 10);
    expect(AppSpacing.chipRunGap, 14);
  });

  testWidgets('chips carry a light accent tint; disabled stay white', (
    tester,
  ) async {
    await _open(tester, [
      _opt('Leave'),
      _opt('Test link', type: 'axpert_iview'),
    ]);
    BoxDecoration decorationOf(String l) =>
        tester
                .widget<Container>(
                  find
                      .descendant(
                        of: find.widgetWithText(FormChip, l),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(decorationOf('Leave').color, AppColors.white);
    expect(decorationOf('Test link').color, AppColors.white);
    final accent = FormChip.accentOf('Leave');
    expect(
      (decorationOf('Leave').border! as Border).top.color,
      accent.withValues(alpha: FormChip.borderAlpha),
    );
    expect(decorationOf('Leave').border!.top.width, 1);
    expect(
      (decorationOf('Test link').border! as Border).top.color,
      AppColors.line,
    );
    expect(find.byIcon(Icons.history), findsNothing);
    expect(find.byType(AppPngIcon), findsOneWidget);
  });

  group('150 forms', () {
    final list = [
      for (var i = 0; i < 150; i++)
        _opt(
          i % 10 == 0
              ? 'Very long form name number $i that keeps going and going '
                    'well past one line of the sheet width'
              : 'Form $i${'x' * (i % 7)}',
          type: i % 25 == 0 ? 'axpert_iview' : 'data_input',
        ),
    ];

    for (final scale in [1.0, 1.3]) {
      testWidgets('scrolls only the middle at scale $scale', (tester) async {
        await _open(tester, list, scale: scale);
        expect(tester.takeException(), isNull);
        final sheet = tester.getRect(find.byType(BottomSheet));
        expect(sheet.height, lessThanOrEqualTo(600 * 0.85 + 1));
        final scroll = find.byType(SingleChildScrollView);
        expect(scroll, findsOneWidget);
        final header = tester.getTopLeft(find.text('Choose a form to fill in'));
        final search = tester.getTopLeft(find.byType(AppSearchField));
        final bar = tester.getTopLeft(find.text('My Submissions'));
        await tester.drag(scroll, const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.text('Choose a form to fill in')),
          header,
        );
        expect(tester.getTopLeft(find.byType(AppSearchField)), search);
        expect(tester.getTopLeft(find.text('My Submissions')), bar);
        expect(
          tester
              .state<ScrollableState>(find.byType(Scrollable).last)
              .position
              .pixels,
          greaterThan(0),
        );
      });
    }

    testWidgets('Show all expands to every form; count matches', (
      tester,
    ) async {
      await _open(tester, list);
      const available = 144;
      expect(find.byType(FormChip, skipOffstage: false), findsNWidgets(12 + 6));
      expect(find.text('$available forms'), findsOneWidget);
      await tester.ensureVisible(find.text('Show all'));
      await tester.tap(find.text('Show all'));
      await tester.pumpAndSettle();
      expect(find.text('Show all'), findsNothing);
      expect(find.byType(FormChip, skipOffstage: false), findsNWidgets(150));
    });

    testWidgets('search filters chips, hides the link, updates the count', (
      tester,
    ) async {
      await _open(tester, list);
      await tester.enterText(find.byType(TextField), 'Form 1');
      await tester.pumpAndSettle();
      final expected = list
          .where((o) => o.caption.toLowerCase().contains('form 1'))
          .toList();
      final avail = expected.where((o) => o.type == 'data_input').length;
      expect(find.text('Show all'), findsNothing);
      expect(
        find.byType(FormChip, skipOffstage: false),
        findsNWidgets(expected.length),
      );
      expect(find.text(avail == 1 ? '1 form' : '$avail forms'), findsOneWidget);
    });

    for (final n in [150, 500]) {
      testWidgets('first build of $n chips (timing)', (tester) async {
        final big = [for (var i = 0; i < n; i++) _opt('Form number $i')];
        final sw = Stopwatch()..start();
        await _open(tester, big);
        await tester.tap(find.text('Show all'));
        await tester.pumpAndSettle();
        sw.stop();
        // ignore: avoid_print
        print('TIMING $n chips: ${sw.elapsedMilliseconds} ms');
      });
    }
  });
}
