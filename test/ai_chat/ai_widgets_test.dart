import 'dart:async';

import 'package:connectum/data/ai/ai_models.dart';
import 'package:connectum/data/ai/ai_setup_cache.dart';
import 'package:connectum/data/ai/fake_ai_repository.dart';
import 'package:connectum/data/repositories/message_repository.dart'
    show SendResult;
import 'package:connectum/features/ai_chat/ai_entry.dart';
import 'package:connectum/features/ai_chat/ai_summary_controller.dart';
import 'package:connectum/features/ai_chat/ai_texts.dart';
import 'package:connectum/features/ai_chat/widgets/ai_header_button.dart';
import 'package:connectum/features/ai_chat/widgets/ai_notice_dialog.dart';
import 'package:connectum/features/ai_chat/widgets/ai_rich_text.dart';
import 'package:connectum/features/ai_chat/widgets/ai_sheet.dart';
import 'package:connectum/features/conversation/widgets/conversation_header.dart';
import 'package:connectum/core/widgets/app_button.dart';
import 'package:connectum/core/widgets/app_chart/app_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {double width = 320, double scale = 1}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 700),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

AiSummaryController make(
  FakeAiRepository fake, {
  bool isOnline = true,
  bool isEncrypted = false,
  bool isAdmin = false,
  Future<SendResult> Function(String)? post,
}) => AiSummaryController(
  ai: fake,
  setup: AiSetupCache(fake),
  chatId: 'dm:ana',
  title: () => 'Ana',
  isEncrypted: () => isEncrypted,
  isOnline: () => isOnline,
  post: post ?? (_) async => SendResult.queued,
  isAdmin: () => isAdmin,
);

void main() {
  testWidgets('the header shows the AI button only when given one', (
    tester,
  ) async {
    Widget header(List<Widget> trailing) => host(
      ConversationHeader(
        title: 'Ana',
        status: null,
        avatar: const SizedBox(width: 44, height: 44),
        onBack: () {},
        trailing: trailing,
      ),
    );
    await tester.pumpWidget(header(const []));
    expect(find.byType(AiHeaderButton), findsNothing);
    var taps = 0;
    await tester.pumpWidget(header([AiHeaderButton(onPressed: () => taps++)]));
    expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
    expect(find.byTooltip('AI'), findsOneWidget);
    expect(tester.getSize(find.byType(AiHeaderButton)), const Size(48, 48));
    await tester.tap(find.byType(AiHeaderButton));
    expect(taps, 1);
  });

  testWidgets(
    'the sheet walks menu, range, loading and result, with share and privacy',
    (tester) async {
      final fake = FakeAiRepository(
        scenario: FakeAiScenario.markdown,
        delay: const Duration(milliseconds: 800),
      );
      final c = make(fake);
      var closed = 0;
      await tester.pumpWidget(
        host(
          AiSheet(controller: c, onClose: () => closed++),
          width: 320,
          scale: 2,
        ),
      );
      unawaited(c.onSheetOpened());
      await tester.pumpAndSettle();
      expect(find.text(AiTexts.summarize), findsOneWidget);
      await tester.tap(find.text(AiTexts.summarize));
      await tester.pumpAndSettle();
      expect(find.text('Last 7 days'), findsOneWidget);
      expect(find.text(AiTexts.privacy), findsOneWidget);
      await tester.tap(find.text('Last 7 days'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Summarize'));
      await tester.tap(find.text('Summarize'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text(AiTexts.summarizing), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      expect(find.text('Last 7 days · 42 messages'), findsOneWidget);
      expect(find.text(AiTexts.caption), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Regenerate'), findsOneWidget);
      expect(find.text('Share in chat'), findsOneWidget);
      await tester.ensureVisible(find.text('Close'));
      await tester.tap(find.text('Close'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(closed, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancel shows the cancelled state', (tester) async {
    final fake = FakeAiRepository(delay: const Duration(seconds: 3));
    final c = make(fake);
    await tester.pumpWidget(host(AiSheet(controller: c, onClose: () {})));
    await tester.pumpAndSettle();
    await c.summarize();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text(AiTexts.cancelledTitle), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  for (final kind in AiErrorKind.values) {
    testWidgets('error $kind shows its text and an action', (tester) async {
      final c = make(FakeAiRepository());
      c.phase.value = AiPhase.error;
      c.error.value = kind;
      await tester.pumpWidget(
        host(AiSheet(controller: c, onClose: () {}), scale: 2),
      );
      expect(find.text(AiTexts.errorTitle(kind)), findsOneWidget);
      expect(find.text(c.errorText(kind)), findsOneWidget);
      expect(find.text('Share in chat'), findsNothing);
      expect(find.byType(AppButton), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the not-set-up dialog fits a narrow phone', (tester) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => AiNoticeDialog.show(
              context,
              title: AiTexts.setupTitle,
              text: AiTexts.setupText(),
            ),
            child: const Text('open'),
          ),
        ),
        scale: 2,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(AiTexts.setupTitle), findsOneWidget);
    expect(find.text(AiTexts.setupText()), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('OK'), findsNothing);
  });

  testWidgets('two agents show the AI chips; one does not', (tester) async {
    final two = FakeAiRepository(
      setup: const AiSetup(
        AiSetupState.ready,
        agents: [
          AiAgent(id: 'a', name: 'Alpha'),
          AiAgent(id: 'b', name: 'Beta'),
        ],
      ),
    );
    final c = make(two);
    await c.onSheetOpened();
    c.openSetup();
    await tester.pumpWidget(host(AiSheet(controller: c, onClose: () {})));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('A date'), findsOneWidget);
    final one = make(FakeAiRepository());
    await one.onSheetOpened();
    one.openSetup();
    await tester.pumpWidget(host(AiSheet(controller: one, onClose: () {})));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsNothing);
  });

  testWidgets('an encrypted chat: the dialog explains, nothing is sent', (
    tester,
  ) async {
    final fake = FakeAiRepository(delay: const Duration(milliseconds: 10));
    final c = make(fake, isEncrypted: true);
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => openAi(context, c),
            child: const Text('ai'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ai'));
    await tester.pumpAndSettle();
    expect(find.text(AiTexts.encryptedTitle), findsOneWidget);
    expect(find.text(AiTexts.encryptedText), findsOneWidget);
    expect(find.text(AiTexts.summarize), findsNothing);
    expect(fake.setupCalls, 0);
    expect(fake.summarizeCalls, 0);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final isAdmin in [false, true]) {
    testWidgets('not set up as ${isAdmin ? 'an admin' : 'a member'}', (
      tester,
    ) async {
      final fake = FakeAiRepository(
        setup: const AiSetup(AiSetupState.notSetUp),
      );
      final c = make(fake, isAdmin: isAdmin);
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => openAi(context, c),
              child: const Text('ai'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ai'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          isAdmin ? 'Set it up in the web app' : 'Ask your administrator',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          isAdmin ? 'Ask your administrator' : 'Set it up in the web app',
        ),
        findsNothing,
      );
    });
  }

  group('share in chat', () {
    Future<(AiSummaryController, List<String>)> result(
      WidgetTester tester, {
      bool isEncrypted = false,
      List<SendResult>? results,
      double width = 320,
      double scale = 1,
    }) async {
      final sent = <String>[];
      final c = make(
        FakeAiRepository(delay: const Duration(milliseconds: 10)),
        isEncrypted: isEncrypted,
        post: (t) async {
          sent.add(t);
          return results == null || results.isEmpty
              ? SendResult.queued
              : results.removeAt(0);
        },
      );
      c.usedLabel.value = 'Last 7 days';
      c.text.value = '**Decisions**\n- Ship on Friday, ping @ana';
      c.phase.value = AiPhase.result;
      await tester.pumpWidget(
        host(
          AiSheet(controller: c, onClose: () {}),
          width: width,
          scale: scale,
        ),
      );
      await tester.pumpAndSettle();
      return (c, sent);
    }

    testWidgets('Cancel sends nothing, Post sends one exact message', (
      tester,
    ) async {
      final (c, sent) = await result(tester);
      await tester.tap(find.text('Share in chat'));
      await tester.pumpAndSettle();
      expect(find.text(AiTexts.shareTitle), findsOneWidget);
      expect(find.text(AiTexts.shareText), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      await tester.tap(find.text('Share in chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Post'));
      await tester.pumpAndSettle();
      expect(sent, [
        '✨ AI summary\n\n**Decisions**\n- Ship on Friday, ping @\u200Bana',
      ]);
    });

    testWidgets('a double tap sends once', (tester) async {
      final (c, sent) = await result(tester);
      final first = c.share();
      final second = c.share();
      expect(await second, isFalse);
      expect(await first, isTrue);
      expect(await c.share(), isFalse);
      expect(sent, hasLength(1));
    });

    testWidgets('a failed send keeps the result, retry sends it once', (
      tester,
    ) async {
      final (c, sent) = await result(
        tester,
        results: [SendResult.invalid, SendResult.queued],
      );
      expect(await c.share(), isFalse);
      expect(c.phase.value, AiPhase.result);
      expect(c.isSharing.value, isFalse);
      expect(await c.share(), isTrue);
      expect(sent, hasLength(2));
      expect(sent[0], sent[1]);
      await tester.pump(const Duration(seconds: 5));
    });

    test(
      'a long summary is split in order and a retry never repeats a part',
      () async {
        final sent = <String>[];
        var fails = 1;
        final c = make(
          FakeAiRepository(delay: const Duration(milliseconds: 5)),
          post: (t) async {
            if (sent.length == 1 && fails-- > 0) return SendResult.invalid;
            sent.add(t);
            return SendResult.queued;
          },
        );
        c.phase.value = AiPhase.result;
        c.usedLabel.value = 'Last 7 days';
        c.text.value = List.generate(
          120,
          (i) => 'Point $i is done.',
        ).join('\n');
        expect(await c.share(), isFalse);
        expect(sent, hasLength(1));
        expect(await c.share(), isTrue);
        expect(sent.length, greaterThan(1));
        for (var i = 0; i < sent.length; i++) {
          expect(sent[i].length, lessThanOrEqualTo(2000));
          expect(sent[i], contains('(${i + 1}/${sent.length})'));
        }
      },
    );

    testWidgets('sharing shows a preview of exactly what is posted', (
      tester,
    ) async {
      final (c, sent) = await result(tester);
      await tester.tap(find.text('Share in chat'));
      await tester.pumpAndSettle();
      expect(find.text(AiTexts.shareTitle), findsOneWidget);
      expect(find.text(c.sharePreview), findsOneWidget);
      expect(sent, isEmpty);
      await tester.tap(find.text('Post'));
      await tester.pumpAndSettle();
      expect(sent.join('\n\n'), c.sharePreview);
      expect(sent.first, startsWith('✨ AI summary\n\n'));
      expect(c.canShare, isFalse);
    });

    testWidgets('Copy still works and the result fits large text', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      final (c, _) = await result(tester, scale: 2);
      await tester.ensureVisible(find.text('Copy'));
      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(copied, c.text.value);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('the privacy caption shows at large text and narrow width', (
      tester,
    ) async {
      final c = make(FakeAiRepository());
      c.openSetup();
      await tester.pumpWidget(
        host(AiSheet(controller: c, onClose: () {}), width: 280, scale: 2),
      );
      await tester.pumpAndSettle();
      expect(find.text(AiTexts.privacy), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the action offered per error', () {
    const close = [
      AiErrorKind.noKey,
      AiErrorKind.badKey,
      AiErrorKind.keyUnreadable,
      AiErrorKind.noCredit,
      AiErrorKind.modelUnavailable,
      AiErrorKind.forbiddenAddress,
      AiErrorKind.noPermission,
      AiErrorKind.notSetUp,
      AiErrorKind.agentGone,
      AiErrorKind.careNotFound,
    ];
    const retry = [
      AiErrorKind.offline,
      AiErrorKind.serverTimeout,
      AiErrorKind.timeout,
      AiErrorKind.providerUnreachable,
      AiErrorKind.failed,
      AiErrorKind.badRequest,
      AiErrorKind.emptyAnswer,
    ];
    const tryAgain = [
      AiErrorKind.rateLimited,
      AiErrorKind.agentBusy,
      AiErrorKind.providerRateLimited,
      AiErrorKind.providerBusy,
    ];
    Future<void> show(
      WidgetTester tester,
      AiErrorKind kind, {
      bool isAdmin = false,
    }) async {
      final c = make(FakeAiRepository(), isAdmin: isAdmin);
      c.phase.value = AiPhase.error;
      c.error.value = kind;
      await tester.pumpWidget(host(AiSheet(controller: c, onClose: () {})));
    }

    for (final kind in close) {
      testWidgets('$kind offers Close only', (tester) async {
        await show(tester, kind);
        expect(find.widgetWithText(AppButton, 'Close'), findsOneWidget);
        expect(find.text('Retry'), findsNothing);
        expect(find.text('Try again'), findsNothing);
      });
    }
    for (final kind in retry) {
      testWidgets('$kind offers Retry', (tester) async {
        await show(tester, kind);
        expect(find.widgetWithText(AppButton, 'Retry'), findsOneWidget);
      });
    }
    for (final kind in tryAgain) {
      testWidgets('$kind offers Try again', (tester) async {
        await show(tester, kind);
        expect(find.widgetWithText(AppButton, 'Try again'), findsOneWidget);
      });
    }
    testWidgets(
      'a key problem tells a member to ask, an admin to use the web',
      (tester) async {
        await show(tester, AiErrorKind.badKey);
        expect(find.textContaining('Ask your administrator.'), findsOneWidget);
        await show(tester, AiErrorKind.badKey, isAdmin: true);
        expect(find.textContaining('Set it up in the web app'), findsOneWidget);
        expect(find.textContaining('Ask your administrator.'), findsNothing);
      },
    );
    testWidgets('the care too-large error cannot change a range', (
      tester,
    ) async {
      final c = AiSummaryController(
        ai: FakeAiRepository(),
        setup: AiSetupCache(FakeAiRepository()),
        chatId: 'group:care-ravi',
        title: () => 'Ravi',
        isEncrypted: () => false,
        isOnline: () => true,
        post: (_) async => SendResult.queued,
        isAdmin: () => false,
        carePerson: 'ravi',
      );
      c.phase.value = AiPhase.error;
      c.error.value = AiErrorKind.tooLarge;
      await tester.pumpWidget(host(AiSheet(controller: c, onClose: () {})));
      expect(find.widgetWithText(AppButton, 'Close'), findsOneWidget);
      expect(find.text('Change range'), findsNothing);
    });
  });

  group('a care thread sheet', () {
    AiSummaryController care(FakeAiRepository fake) => AiSummaryController(
      ai: fake,
      setup: AiSetupCache(fake),
      chatId: 'group:care-ravi',
      title: () => 'Ravi',
      isEncrypted: () => false,
      isOnline: () => true,
      post: (_) async => SendResult.queued,
      isAdmin: () => false,
      carePerson: 'ravi',
    );

    testWidgets('has no range, shows the note, then the truncated note', (
      tester,
    ) async {
      final fake = FakeAiRepository(delay: const Duration(milliseconds: 10));
      final c = care(fake);
      await c.onSheetOpened();
      await tester.pumpWidget(host(AiSheet(controller: c, onClose: () {})));
      expect(find.text('Summarize this thread'), findsOneWidget);
      expect(find.text('Summarize this chat'), findsNothing);
      await tester.tap(find.text('Summarize this thread'));
      await tester.pumpAndSettle();
      expect(find.text(AiTexts.careNote), findsOneWidget);
      expect(find.text('Last 7 days'), findsNothing);
      expect(find.text('From'), findsNothing);
      expect(find.text(AiTexts.privacy), findsOneWidget);
      await tester.tap(find.text('Summarize'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text(AiTexts.careTruncated), findsOneWidget);
      expect(fake.lastRequest!.carePerson, 'ravi');
      expect(find.text('Share in chat'), findsOneWidget);
    });

    testWidgets('a chat sheet is unchanged: range and no thread note', (
      tester,
    ) async {
      final c = make(FakeAiRepository());
      await c.onSheetOpened();
      await tester.pumpWidget(host(AiSheet(controller: c, onClose: () {})));
      expect(find.text('Summarize this chat'), findsOneWidget);
      await tester.tap(find.text('Summarize this chat'));
      await tester.pumpAndSettle();
      expect(find.text('From'), findsOneWidget);
      expect(find.text(AiTexts.careNote), findsNothing);
    });
  });

  testWidgets('an answer with a chart draws it and hides a broken one', (
    tester,
  ) async {
    final fake = FakeAiRepository(
      scenario: FakeAiScenario.chartMalformed,
      delay: const Duration(milliseconds: 10),
    );
    final c = make(fake);
    await c.onSheetOpened();
    c.phase.value = AiPhase.result;
    c.text.value = fakeChartSamples[FakeAiScenario.chartBar]!;
    await tester.pumpWidget(
      host(AiSheet(controller: c, onClose: () {}), width: 360),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppChart), findsOneWidget);
    expect(find.textContaining('"type"'), findsNothing);
    expect(find.textContaining('Bangalore leads.'), findsOneWidget);
    await tester.pumpWidget(
      host(AiRichText(fakeChartSamples[FakeAiScenario.chartMalformed]!)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppChart), findsNothing);
    expect(find.textContaining('"type"'), findsNothing);
    expect(find.textContaining('print(1)'), findsOneWidget);
    await tester.pumpWidget(
      host(const AiRichText('Before\n```chart\n{"type":"bar"')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppChart), findsNothing);
    expect(find.textContaining('Before'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
