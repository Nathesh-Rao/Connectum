import 'package:connectum/core/crash/crash_service.dart';
import 'package:connectum/features/debug_crashtest/debug_crashtest_controller.dart';
import 'package:connectum/features/debug_crashtest/debug_crashtest_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'fake_crash_reporter.dart';

void main() {
  tearDown(Get.reset);

  testWidgets('renders and sends a breadcrumb through the fake reporter', (
    tester,
  ) async {
    final r = FakeCrashReporter();
    final service = CrashService(r);
    CrashService.current = service;
    Get.put(
      DebugCrashTestController(service, emailOf: () => 'ann@example.com'),
    );
    await tester.pumpWidget(const GetMaterialApp(home: DebugCrashTestView()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Identity set: yes (an***)'), findsOneWidget);
    expect(find.text('Collection enabled: yes'), findsOneWidget);
    await tester.tap(find.text('Send breadcrumb'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(r.logs, ['screen:crashtest']);
    expect(find.text('screen:crashtest'), findsOneWidget);
  });
}
