import 'package:connectum/core/widgets/app_bottom_sheet.dart';
import 'package:connectum/core/widgets/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _Form {
  final field = TextEditingController();
  final error = RxnString();
  var isDisposed = false;

  void dispose() {
    isDisposed = true;
    field.dispose();
  }
}

Widget _host(_Form form) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => AppBottomSheet.show<void>(
            context,
            title: 'Reason',
            onDispose: form.dispose,
            child: Obx(
              () => AppTextField(
                controller: form.field,
                autofocus: true,
                errorText: form.error.value,
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester, _Form form) async {
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(form));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  await tester.pumpAndSettle();
  expect(FocusManager.instance.primaryFocus, isNotNull);
}

// What the keyboard and the form do while the sheet is still animating out.
Future<void> _closeWhileBusy(
  WidgetTester tester,
  _Form form, {
  bool isStillClosing = true,
}) async {
  await tester.pump(const Duration(milliseconds: 50));
  tester.view.viewInsets = FakeViewPadding.zero;
  form.error.value = 'still reacting';
  await tester.pump(const Duration(milliseconds: 50));
  if (isStillClosing) expect(form.isDisposed, isFalse);
  await tester.pumpAndSettle();
  expect(form.isDisposed, isTrue);
  expect(find.byType(AppTextField), findsNothing);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('closing by back keeps the controller until the sheet is gone', (
    tester,
  ) async {
    final form = _Form();
    await _open(tester, form);

    await tester.binding.handlePopRoute();
    await _closeWhileBusy(tester, form);
  });

  testWidgets('closing by drag down keeps the controller until the sheet is '
      'gone', (tester) async {
    final form = _Form();
    await _open(tester, form);

    await tester.timedDragFrom(
      tester.getCenter(find.text('Reason')),
      const Offset(0, 400),
      const Duration(milliseconds: 100),
    );
    // The drag has already carried the sheet off screen by now.
    await _closeWhileBusy(tester, form, isStillClosing: false);
  });
}
