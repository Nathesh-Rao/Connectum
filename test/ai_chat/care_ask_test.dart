import 'dart:async';

import 'package:connectum/core/widgets/app_text_field.dart';
import 'package:connectum/data/ai/ai_models.dart';
import 'package:connectum/data/ai/ai_setup_cache.dart';
import 'package:connectum/data/ai/fake_ai_repository.dart';
import 'package:connectum/data/repositories/message_repository.dart'
    show SendResult;
import 'package:connectum/features/ai_chat/ai_summary_controller.dart';
import 'package:connectum/features/ai_chat/ai_texts.dart';
import 'package:connectum/features/ai_chat/widgets/ai_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: MediaQuery(
    data: const MediaQueryData(size: Size(360, 800)),
    child: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

AiSummaryController _make(FakeAiRepository fake, {String? person = 'ravi'}) =>
    AiSummaryController(
      ai: fake,
      setup: AiSetupCache(fake),
      chatId: person == null ? 'dm:ana' : 'group:care-$person',
      title: () => 'Ravi Kumar',
      isEncrypted: () => false,
      isOnline: () => true,
      post: (_) async => SendResult.queued,
      isAdmin: () => false,
      carePerson: person,
    );

Future<void> _settle(AiSummaryController c) async {
  for (var i = 0; i < 20 && c.phase.value == AiPhase.loading; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test(
    'a typed question reads the thread and shows the patient note',
    () async {
      final fake = FakeAiRepository(delay: Duration.zero)
        ..care = FakeCareThread.patient;
      final c = _make(fake);
      await c.onSheetOpened();
      await c.ask('  What dose?  ');
      await _settle(c);
      expect(c.phase.value, AiPhase.result);
      expect(fake.lastRequest!.question, 'What dose?');
      expect(fake.careThreadCalls, 1);
      expect(c.isPatientView.value, isTrue);
      expect(c.isAnswer, isTrue);
      expect(c.canShare, isFalse);
    },
  );

  test(
    'the team version has no patient note; the summary can be shared',
    () async {
      final fake = FakeAiRepository(delay: Duration.zero);
      final c = _make(fake);
      await c.onSheetOpened();
      await c.ask('Who said that?');
      await _settle(c);
      expect(c.isPatientView.value, isFalse);
      await c.summarize();
      await _settle(c);
      expect(fake.lastRequest!.question, isNull);
      expect(
        fake.careThreadCalls,
        1,
        reason: 'the one-tap summary has no thread',
      );
      expect(c.isAnswer, isFalse);
      expect(c.canShare, isTrue);
    },
  );

  test('retry asks the same question again', () async {
    final fake = FakeAiRepository(delay: Duration.zero);
    final c = _make(fake);
    await c.onSheetOpened();
    await c.ask('Which medicines?');
    await _settle(c);
    await c.retry();
    await _settle(c);
    expect(fake.lastRequest!.question, 'Which medicines?');
    expect(fake.summarizeCalls, 2);
  });

  test(
    'an empty question and a chat without a care person do nothing',
    () async {
      final fake = FakeAiRepository(delay: Duration.zero);
      final c = _make(fake);
      await c.ask('   ');
      expect(fake.summarizeCalls, 0);
      final chat = _make(fake, person: null);
      await chat.ask('hello?');
      expect(fake.summarizeCalls, 0);
    },
  );

  test('not_found shows our words, and the patient gets their own', () async {
    final fake = FakeAiRepository(delay: Duration.zero)
      ..care = FakeCareThread.notFound;
    final c = _make(fake);
    await c.onSheetOpened();
    await c.ask('q');
    await _settle(c);
    expect(c.phase.value, AiPhase.error);
    expect(c.error.value, AiErrorKind.careNotFound);
    expect(
      c.errorText(c.error.value!),
      'There is no shared care conversation with this person yet.',
    );
    fake.care = FakeCareThread.patientNotFound;
    await c.ask('q');
    await _settle(c);
    expect(c.error.value, AiErrorKind.careNotStarted);
    expect(c.errorText(c.error.value!), contains('care team is connected'));
  });

  testWidgets('the care menu has the question field, a chat menu does not', (
    tester,
  ) async {
    final fake = FakeAiRepository(delay: Duration.zero);
    final care = _make(fake);
    await tester.pumpWidget(_host(AiSheet(controller: care, onClose: () {})));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(AiTexts.careSummarize), findsOneWidget);
    expect(find.byType(AppTextField), findsOneWidget);
    final chat = _make(fake, person: null);
    await tester.pumpWidget(_host(AiSheet(controller: chat, onClose: () {})));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(AppTextField), findsNothing);
  });

  testWidgets(
    'sending a question shows the answer, the patient note, no share',
    (tester) async {
      final fake = FakeAiRepository(delay: const Duration(milliseconds: 400))
        ..care = FakeCareThread.patient;
      final c = _make(fake);
      await tester.pumpWidget(_host(AiSheet(controller: c, onClose: () {})));
      unawaited(c.onSheetOpened());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(EditableText), 'What dose?');
      await tester.tap(find.byTooltip(AiTexts.askSend));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text(AiTexts.summarizing), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(AiTexts.patientScope), findsOneWidget);
      expect(find.text('Share in chat'), findsNothing);
      expect(find.text('Regenerate'), findsOneWidget);
      expect(find.textContaining(AiTexts.questionLabel), findsOneWidget);
      expect(fake.lastRequest!.question, 'What dose?');
    },
  );

  testWidgets('the not-found state uses the error block with its words', (
    tester,
  ) async {
    final fake = FakeAiRepository(delay: Duration.zero)
      ..care = FakeCareThread.patientNotFound;
    final c = _make(fake);
    await tester.pumpWidget(_host(AiSheet(controller: c, onClose: () {})));
    unawaited(c.onSheetOpened());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(EditableText), 'q');
    await tester.tap(find.byTooltip(AiTexts.askSend));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text(AiTexts.errorTitle(AiErrorKind.careNotStarted)),
      findsOneWidget,
    );
    expect(find.textContaining('care team is connected'), findsOneWidget);
  });
}
