import 'package:connectum/features/inbox/inbox_binding.dart';
import 'package:connectum/features/inbox/inbox_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_socket.dart';

void main() {
  late FakeSocket socket;

  Future<void> boot(WidgetTester tester) async {
    Get.reset();
    socket = FakeSocket()..goOnline();
    InboxBinding().dependencies();
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(Get.reset);
    await tester.pumpWidget(
      const GetMaterialApp(
        debugShowCheckedModeBanner: false,
        home: InboxView(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the sample: pills, search, caption, empty state', (
    tester,
  ) async {
    await boot(tester);
    for (final label in [
      'All',
      'Tasks & tickets',
      'Approvals',
      'Reminders',
      'My submissions',
      'Broadcast',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('6'), findsOneWidget);
    expect(find.text('Search mail'), findsOneWidget);
    expect(find.text('0 messages'), findsOneWidget);
    expect(find.text('Visualize tasks & tickets'), findsOneWidget);
    expect(find.text('You are all clear.'), findsOneWidget);
    expect(find.text('Nothing is waiting for you.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await expectLater(
      find.byType(GetMaterialApp),
      matchesGoldenFile('goldens/inbox_placeholder.png'),
    );
  });

  testWidgets('it makes no network call, whatever is tapped', (tester) async {
    await boot(tester);
    await tester.tap(find.text('Approvals'));
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.tap(find.text('Visualize tasks & tickets'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(socket.calls, isEmpty);
    expect(find.text('You are all clear.'), findsOneWidget);
  });
}
