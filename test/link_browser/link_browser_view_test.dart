import 'package:connectum/core/utils/link_launcher.dart';
import 'package:connectum/features/link_browser/link_browser_controller.dart';
import 'package:connectum/features/link_browser/link_browser_view.dart';
import 'package:connectum/features/link_browser/models/link_browser_args.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';

Future<(LinkBrowserController, List<String>)> _pump(WidgetTester tester) async {
  Get.reset();
  final launched = <String>[];
  final c = Get.put(
    LinkBrowserController(
      args: const LinkBrowserArgs(
        url: 'https://connectum.app/page',
        title: 'Timesheet',
      ),
      trustedHosts: const {'connectum.app'},
      launcher: LinkLauncher(
        launch: (uri) async {
          launched.add(uri.toString());
          return true;
        },
      ),
    ),
  );
  await tester.pumpWidget(
    GetMaterialApp(
      home: LinkBrowserView(pageBuilder: (_) => const SizedBox.expand()),
    ),
  );
  return (c, launched);
}

void main() {
  testWidgets('shows title, host, lock and a loading cover', (tester) async {
    await _pump(tester);
    expect(find.text('Timesheet'), findsOneWidget);
    expect(find.text('connectum.app'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('menu has Reload, Open in browser, Copy link, Share', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump(const Duration(milliseconds: 400));
    for (final t in ['Reload', 'Open in browser', 'Copy link', 'Share']) {
      expect(find.text(t), findsOneWidget);
    }
  });

  testWidgets('progress finishes and an error shows retry and browser', (
    tester,
  ) async {
    final (c, _) = await _pump(tester);
    c.handleProgress(60);
    await tester.pump();
    c.handleError(
      WebResourceError(
        errorCode: -2,
        description: '',
        errorType: WebResourceErrorType.hostLookup,
        isForMainFrame: true,
      ),
    );
    await tester.pump();
    expect(c.error.value, LinkBrowserError.offline);
    expect(find.text('Open in browser'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('http and ssl errors are told apart', (tester) async {
    final (c, _) = await _pump(tester);
    c.handleHttpError(200);
    expect(c.error.value, isNull);
    c.handleHttpError(503);
    expect(c.error.value, LinkBrowserError.http);
    c.handleError(
      WebResourceError(
        errorCode: -1,
        description: '',
        errorType: WebResourceErrorType.failedSslHandshake,
        isForMainFrame: true,
      ),
    );
    expect(c.error.value, LinkBrowserError.ssl);
  });

  testWidgets('leaving the trusted hosts opens the phone browser', (
    tester,
  ) async {
    final (c, launched) = await _pump(tester);
    var d = await c.handleNavigation(
      const NavigationRequest(
        url: 'https://connectum.app/x',
        isMainFrame: true,
      ),
    );
    expect(d, NavigationDecision.navigate);
    d = await c.handleNavigation(
      const NavigationRequest(url: 'https://evil.com/x', isMainFrame: true),
    );
    expect(d, NavigationDecision.prevent);
    expect(launched, ['https://evil.com/x']);
    d = await c.handleNavigation(
      const NavigationRequest(url: 'intent://x#Intent;end', isMainFrame: true),
    );
    expect(d, NavigationDecision.prevent);
    expect(launched.length, 1);
    await tester.pump(const Duration(seconds: 4));
  });
}
