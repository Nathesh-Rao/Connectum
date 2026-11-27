import 'dart:io';

import 'package:connectum/core/log/log_file_sink.dart';
import 'package:connectum/core/widgets/app_notices.dart';
import 'package:connectum/core/widgets/app_switch.dart';
import 'package:connectum/features/profile/widgets/profile_row.dart';
import 'package:connectum/features/settings/logs_controller.dart';
import 'package:connectum/features/settings/widgets/logs_options_sheet.dart';
import 'package:connectum/features/settings/widgets/logs_settings_tile.dart';
import 'package:connectum/features/settings/widgets/old_log_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: AppNoticeHost(child: Center(child: child)),
  ),
);

void main() {
  test('subtitle states', () {
    expect(LogsController.subtitle(const LogState()), 'Off');
    expect(
      LogsController.subtitle(const LogState(fileName: 'f.txt')),
      'Off · last file f.txt',
    );
    expect(
      LogsController.subtitle(
        const LogState(isEnabled: true, fileName: 'f.txt', sizeBytes: 2048),
      ),
      'On · f.txt · 2 KB',
    );
  });

  testWidgets('tile shows the state; the switch drives the controller', (
    tester,
  ) async {
    late Directory dir;
    late LogFileSink sink;
    late LogsController c;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('logui');
      sink = LogFileSink(
        directory: () async => dir,
        flushInterval: const Duration(hours: 1),
      );
      await sink.init();
      c = LogsController(sink: sink);
    });
    await tester.pumpWidget(_host(LogsSettingsTile(controller: c)));
    expect(find.text('Record app activity for support'), findsOneWidget);
    expect(find.byType(ProfileIconTile), findsOneWidget);
    expect(find.textContaining('Share them only with support'), findsOneWidget);
    Switch sw() => tester.widget<Switch>(find.byType(Switch));
    void expectColors(bool isOn) {
      final thumb = sw().thumbColor!.resolve({});
      final track = sw().trackColor!.resolve({});
      expect(thumb, AppSwitch.thumbColor(isOn: isOn));
      expect(track, AppSwitch.trackColor(isOn: isOn));
      expect(thumb, isNot(track));
    }

    expect(sw().value, isFalse);
    expectColors(false);

    final context = tester.element(find.byType(LogsSettingsTile));
    await tester.runAsync(() => c.setEnabled(context, true));
    await tester.pump();
    expect(find.textContaining('ConnectumMobileLog_'), findsNothing);
    expect(find.text('Record app activity for support'), findsOneWidget);
    expect(sw().value, isTrue);
    expectColors(true);
    expect(sink.isEnabled, isTrue);

    await tester.runAsync(() => c.setEnabled(context, false));
    await tester.pump();
    expect(find.textContaining('last file'), findsNothing);
    expect(sink.isEnabled, isFalse);

    await tester.runAsync(() async {
      await tester.tap(find.text('Logs'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('Save to device'), findsOneWidget);

    await tester.runAsync(() async {
      c.dispose();
      await dir.delete(recursive: true);
    });
  });

  testWidgets('options sheet: Share to Connectum first, no Upload log', (
    tester,
  ) async {
    var saved = 0;
    var viewed = 0;
    var shared = 0;
    await tester.pumpWidget(
      _host(
        LogsOptionsSheet(
          hasFile: false,
          onView: () async => viewed++,
          onSave: () async => saved++,
          onShare: () async {},
          onShareToConnectum: () async => shared++,
        ),
      ),
    );
    expect(find.text('View log file'), findsOneWidget);
    expect(find.text('Read the log inside the app'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('View log file')).dy,
      lessThan(tester.getTopLeft(find.text('Save to device')).dy),
    );
    expect(find.text('Save to device'), findsOneWidget);
    expect(find.text('Share file'), findsOneWidget);
    expect(find.text('Upload log'), findsNothing);
    expect(find.text('Soon'), findsNothing);
    expect(find.text('Share to Connectum'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Share to Connectum')).dy,
      lessThan(tester.getTopLeft(find.text('View log file')).dy),
    );
    expect(
      find.text('No log file yet. Turn on Logs to create one.'),
      findsOneWidget,
    );
    await tester.tap(find.text('View log file'));
    await tester.tap(find.text('Save to device'));
    expect(saved, 0);
    expect(viewed, 0);
    await tester.tap(find.text('Share to Connectum'));
    expect(shared, 0);
  });

  testWidgets('options sheet with a file enables save', (tester) async {
    var saved = 0;
    var viewed = 0;
    await tester.pumpWidget(
      _host(
        Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => LogsOptionsSheet(
              hasFile: true,
              onView: () async => viewed++,
              onSave: () async => saved++,
              onShare: () async {},
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('No log file yet'), findsNothing);
    await tester.tap(find.text('Save to device'));
    await tester.pump();
    expect(saved, 1);
  });

  testWidgets('options sheet: View log file opens the viewer', (tester) async {
    var viewed = 0;
    await tester.pumpWidget(
      _host(
        Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => LogsOptionsSheet(
              hasFile: true,
              onView: () async => viewed++,
              onSave: () async {},
              onShare: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('View log file'));
    await tester.pump();
    expect(viewed, 1);
  });

  testWidgets('old log dialog: Yes, No and dismiss', (tester) async {
    bool? result = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await OldLogDialog.ask(context, 'f.txt'),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Old log file found'), findsOneWidget);
    expect(
      find.text(
        'Delete the old log file (f.txt) and start a new one? Choose No to keep adding to it.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Yes, delete'));
    await tester.pumpAndSettle();
    expect(result, isTrue);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No, keep it'));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
