import 'package:connectum/core/theme/app_text.dart';
import 'package:connectum/core/widgets/app_form_card.dart';
import 'package:connectum/data/models/form_card.dart';
import 'package:connectum/data/models/form_entry.dart';
import 'package:connectum/features/chats/widgets/workspace_row.dart';
import 'package:connectum/features/conversation/widgets/chat_rows.dart';
import 'package:connectum/features/workspace/widgets/workspace_welcome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void _is(TextStyle s, double size, FontWeight w) {
  expect(s.fontSize, size);
  expect(s.fontWeight, w);
}

void main() {
  test('Work Space role styles keep their size and weight', () {
    _is(AppText.wsTitle, 16, FontWeight.w600);
    _is(AppText.wsSubtitle, 14, FontWeight.w400);
    _is(AppText.wsMeta, 13, FontWeight.w400);
    _is(AppText.wsTime, 12, FontWeight.w400);
    _is(AppText.wsChip, 12, FontWeight.w600);
    _is(AppText.wsSection, 14, FontWeight.w600);
    final t = AppFormCardText.workspace;
    _is(t.title, 16, FontWeight.w600);
    _is(t.strip, 12, FontWeight.w600);
    _is(t.label, 13, FontWeight.w400);
    _is(t.value, 14, FontWeight.w400);
    _is(t.time, 12, FontWeight.w400);
    _is(t.sender, 13, FontWeight.w400);
  });

  test('the chat card keeps its own sizes', () {
    expect(AppFormCardText.chat.title.fontSize, 13);
    expect(AppFormCardText.chat.value.fontSize, 13);
    expect(AppFormCardText.chat.time.fontSize, 11);
  });

  testWidgets('the pinned row preview is the chat preview style', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorkspaceRow(onTap: () {})),
      ),
    );
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.text('My Work Space'));
    _is(title.style!, 16, FontWeight.w600);
    final preview = tester.widget<Text>(find.textContaining("Type '#'"));
    _is(preview.style!, 14, FontWeight.w400);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('Work Space card, divider and welcome fit at $scale', (
      tester,
    ) async {
      final card = FormCardData(
        id: '7',
        caption: 'A rather long help ticket form name that wraps',
        structure: 'help_ticket',
        scope: 'user',
        by: 'bruno',
        ts: DateTime(2026, 11, 5, 9, 30).millisecondsSinceEpoch,
        entries: [
          for (var i = 0; i < 10; i++)
            FormEntry(
              name: 'f$i',
              caption: 'Field number $i caption',
              text: 'A fairly long value to wrap over a few lines $i',
            ),
        ],
      );
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const WorkspaceWelcome(text: 'Welcome to your Work Space'),
                    const DayDivider(label: 'Today', style: AppText.wsSection),
                    SystemRow(
                      text: 'Sent to @someone with a longer line',
                      onTap: () {},
                      style: AppText.wsMeta,
                    ),
                    AppFormCard(
                      data: card,
                      isSent: true,
                      text: AppFormCardText.workspace,
                      note: 'A note under the card',
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
