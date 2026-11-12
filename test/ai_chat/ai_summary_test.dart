import 'package:connectum/core/utils/mention_text.dart';
import 'package:connectum/data/ai/ai_models.dart';
import 'package:connectum/data/ai/ai_setup_cache.dart';
import 'package:connectum/data/ai/fake_ai_repository.dart';
import 'package:connectum/data/repositories/message_repository.dart'
    show MessageRepository, SendResult;
import 'package:connectum/features/ai_chat/ai_summary_message_format.dart';
import 'package:connectum/features/ai_chat/ai_texts.dart';
import 'package:connectum/features/ai_chat/ai_summary_controller.dart';
import 'package:connectum/features/ai_chat/widgets/ai_rich_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _fast = Duration(milliseconds: 10);

class Rig {
  Rig({
    AiSetup? setup,
    FakeAiScenario scenario = FakeAiScenario.short,
    this.isOnline = true,
    Future<SendResult> Function(String)? post,
    this.isAdmin = false,
  }) : fake = setup == null
           ? FakeAiRepository(scenario: scenario, delay: _fast)
           : FakeAiRepository(setup: setup, scenario: scenario, delay: _fast) {
    c = AiSummaryController(
      ai: fake,
      setup: AiSetupCache(fake),
      chatId: 'dm:ana',
      title: () => 'Ana',
      isOnline: () => isOnline,
      post: post ?? (_) async => SendResult.queued,
      isAdmin: () => isAdmin,
    );
  }

  final FakeAiRepository fake;
  late final AiSummaryController c;
  bool isOnline;
  bool isAdmin;
}

class _ChartRepository extends FakeAiRepository {
  _ChartRepository([
    this.answer =
        'Sales rose.\n\n```chart\n{"title":"Sales by city","unit":"lakh","data":[{"label":"Pune","value":9},{"label":"Goa","value":1250}]}\n```\n\n- Done',
  ]);

  final String answer;

  @override
  Stream<AiSummaryChunk> summarize(AiSummaryRequest request) =>
      Stream.value(AiSummaryChunk(answer, isFinal: true));
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the icon shows in direct, group, team and global chats only', () {
    for (final id in ['dm:ana', 'group:sales', 'host:support', 'global']) {
      expect(aiAvailableIn(id), isTrue, reason: id);
    }
    expect(aiAvailableIn('workspace:me'), isFalse);
    expect(aiAvailableIn('group:care-ravi'), isTrue);
    expect(aiAvailableIn('group:care-ravi.k_2'), isTrue);
    expect(aiAvailableIn('group:care-'), isFalse);
    expect(aiAvailableIn('group:care-a b'), isFalse);
  });

  test('summarize loads, then shows the result with range and count', () async {
    final r = Rig();
    await r.c.onSheetOpened();
    r.c.pick(AiRange.week);
    final run = r.c.summarize();
    expect(r.c.phase.value, AiPhase.loading);
    await run;
    await settle();
    expect(r.c.phase.value, AiPhase.result);
    expect(r.c.text.value, contains('Friday'));
    expect(r.c.usedLabel.value, 'Last 7 days');
    expect(r.fake.lastRequest!.range, AiRange.week);
    expect(r.fake.lastRequest!.title, 'Ana');
    expect(r.fake.lastRequest!.agent!.id, 'claude');
    expect(r.c.messageCount.value, 42);
  });

  test('a streamed answer ends on the full text', () async {
    final r = Rig()..fake.isStreaming = true;
    await r.c.summarize();
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(r.c.phase.value, AiPhase.loading);
    expect(r.c.text.value, isNotEmpty);
    await settle();
    expect(r.c.phase.value, AiPhase.result);
    expect(r.c.text.value.length, greaterThan(30));
  });

  for (final kind in AiErrorKind.values) {
    test('$kind ends in the error state', () async {
      final r = Rig(scenario: FakeAiScenario.failure);
      r.fake.failure = kind;
      await r.c.onSheetOpened();
      await r.c.summarize();
      await settle();
      expect(r.c.phase.value, AiPhase.error);
      expect(r.c.error.value, kind);
    });
  }

  test('a refused answer clears the cached setup', () async {
    final r = Rig(scenario: FakeAiScenario.failure);
    r.fake.failure = AiErrorKind.agentGone;
    await r.c.onSheetOpened();
    await r.c.summarize();
    await settle();
    await r.c.onSheetOpened();
    expect(r.fake.setupCalls, 2);
  });

  test('a double tap on Summarize asks once', () async {
    final r = Rig();
    await r.c.onSheetOpened();
    final a = r.c.summarize();
    final b = r.c.summarize();
    await Future.wait([a, b]);
    await settle();
    expect(r.fake.summarizeCalls, 1);
  });

  test('a date range waits for a date and sends it', () async {
    final r = Rig();
    await r.c.onSheetOpened();
    r.c.pick(AiRange.date);
    expect(r.c.canSummarize, isFalse);
    r.c.pickDate(DateTime(2026, 10, 1, 15));
    expect(r.c.canSummarize, isTrue);
    await r.c.summarize();
    await settle();
    expect(r.fake.lastRequest!.range, AiRange.date);
    expect(r.fake.lastRequest!.date, DateTime(2026, 10, 1, 15));
    expect(r.c.usedLabel.value, 'From 2026-10-01');
  });

  test('range starts follow the web: midnight, device time', () {
    final now = DateTime(2026, 11, 10, 14, 30);
    expect(AiRange.everything.since(now), isNull);
    expect(AiRange.today.since(now), DateTime(2026, 11, 10));
    expect(AiRange.week.since(now), DateTime(2026, 11, 3));
    expect(AiRange.month.since(now), DateTime(2026, 10, 11));
    expect(AiRange.date.since(now), isNull);
    expect(
      AiRange.date.since(now, date: DateTime(2026, 9, 1, 8)),
      DateTime(2026, 9, 1),
    );
  });

  test('two agents: the first is chosen and the choice is sent', () async {
    final r = Rig(
      setup: const AiSetup(
        AiSetupState.ready,
        agents: [
          AiAgent(id: 'a', name: 'A'),
          AiAgent(id: 'b', name: 'B'),
        ],
      ),
    );
    await r.c.onSheetOpened();
    expect(r.c.agent.value!.id, 'a');
    r.c.pickAgent(r.c.agents[1]);
    await r.c.summarize();
    await settle();
    expect(r.fake.lastRequest!.agent!.id, 'b');
  });

  test('a setup call that fails shows the error, not "not set up"', () async {
    final r = Rig();
    r.fake.setupFailure = AiErrorKind.offline;
    expect(await r.c.resolveEntry(), AiEntry.problem);
    expect(r.c.lastProblem, AiErrorKind.offline);
    await r.c.onSheetOpened();
    expect(r.c.phase.value, AiPhase.error);
  });

  test('a change of agents drops the cached setup', () async {
    final r = Rig();
    final cache = AiSetupCache(r.fake);
    await cache.get();
    r.fake.changeAgents();
    await settle();
    await cache.get();
    expect(r.fake.setupCalls, 2);
  });

  test('offline: no call is made', () async {
    final r = Rig(isOnline: false);
    await r.c.summarize();
    expect(r.c.error.value, AiErrorKind.offline);
    expect(r.fake.summarizeCalls, 0);
  });

  test('cancel stops the summary and ignores a late answer', () async {
    final r = Rig();
    await r.c.onSheetOpened();
    await r.c.summarize();
    r.c.cancel();
    expect(r.c.phase.value, AiPhase.cancelled);
    expect(r.fake.cancelCalls, 1);
    await settle();
    expect(r.c.phase.value, AiPhase.cancelled);
    expect(r.c.text.value, isEmpty);
  });

  group('an end-to-end chat is summarised like any other', () {
    test('summarize starts: nothing is refused', () async {
      final r = Rig();
      expect(await r.c.summarize(), AiSummarizeResult.started);
      await settle();
      expect(r.fake.summarizeCalls, 1);
      expect(r.c.phase.value, AiPhase.result);
    });

    test('the icon opens the sheet, with the one caption', () async {
      final r = Rig();
      expect(await r.c.resolveEntry(), AiEntry.sheet);
      expect(r.c.privacyText, AiTexts.privacy);
    });

    test('summarising and sharing log no message text', () async {
      final logged = <String>[];
      final old = debugPrint;
      debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
      final r = Rig();
      await r.c.summarize();
      await settle();
      await r.c.share();
      debugPrint = old;
      expect(logged, isEmpty);
    });
  });

  test('copy puts the summary on the clipboard', () async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    final r = Rig();
    await r.c.summarize();
    await settle();
    await r.c.copy();
    expect(copied, r.c.text.value);
  });

  test('regenerate asks again', () async {
    final r = Rig();
    await r.c.summarize();
    await settle();
    await r.c.summarize();
    await settle();
    expect(r.fake.summarizeCalls, 2);
    expect(r.c.phase.value, AiPhase.result);
  });

  group('entry', () {
    test('no agents shows the dialog, not the sheet', () async {
      final r = Rig(setup: const AiSetup(AiSetupState.notSetUp));
      expect(await r.c.resolveEntry(), AiEntry.notSetUp);
    });

    test('ready opens the sheet', () async {
      expect(await Rig().c.resolveEntry(), AiEntry.sheet);
    });

    test('not set up: admin and others get different words', () async {
      final r = Rig(setup: const AiSetup(AiSetupState.notSetUp));
      await r.c.resolveEntry();
      expect(
        r.c.setupText,
        'No AI agent is set up for you yet. Ask your administrator.',
      );
      r.isAdmin = true;
      expect(r.c.setupText, contains('Set it up in the web app'));
      expect(r.c.setupText, isNot(contains('Ask your administrator')));
      expect(r.c.errorText(AiErrorKind.notSetUp), r.c.setupText);
    });

    test('the two rate limits have their own words', () {
      expect(
        AiTexts.errorText(AiErrorKind.rateLimited),
        'Too many questions in a minute. Try again shortly.',
      );
      expect(
        AiTexts.errorText(AiErrorKind.agentBusy),
        'The AI is busy right now. Try again in a moment.',
      );
    });

    test(
      'tickets and records are group chats and get the icon; care threads do not',
      () {
        expect(aiAvailableIn('group:Ticket-12-Leave'), isTrue);
        expect(aiAvailableIn('group:care-ravi'), isTrue);
        expect(aiAvailableIn('group:care-ravi.k_2'), isTrue);
        expect(aiAvailableIn('group:care-'), isFalse);
        expect(aiAvailableIn('group:care-a b'), isFalse);
      },
    );
  });

  group('setup cache', () {
    test('one call within 60 s, a new one after, refresh forces one', () async {
      var now = DateTime(2026, 1, 1);
      final fake = FakeAiRepository();
      final cache = AiSetupCache(fake, clock: () => now);
      await cache.get();
      await cache.get();
      expect(fake.setupCalls, 1);
      now = now.add(const Duration(seconds: 59));
      await cache.get();
      expect(fake.setupCalls, 1);
      await cache.get(isRefresh: true);
      expect(fake.setupCalls, 2);
      now = now.add(const Duration(seconds: 61));
      await cache.get();
      expect(fake.setupCalls, 3);
    });

    test('calls at the same moment share one request', () async {
      final fake = FakeAiRepository();
      final cache = AiSetupCache(fake);
      await Future.wait([cache.get(), cache.get()]);
      expect(fake.setupCalls, 1);
    });
  });

  test('plain rendering handles headings, bullets and bold', () {
    final text = TextSpan(
      children: aiSpans('## Title\n- one **two**\n3. three'),
    ).toPlainText();
    expect(text, 'Title\n•  one two\n3. three');
  });

  group('AiSummaryMessageFormat', () {
    test('first line is exactly the title, blank line, the text as it is', () {
      expect(AiSummaryMessageFormat.build('**A**\n- b'), [
        '✨ AI summary\n\n**A**\n- b',
      ]);
    });

    test('the preview is exactly what is posted', () async {
      final r = Rig();
      await r.c.summarize();
      await settle();
      expect(r.c.sharePreview, startsWith('✨ AI summary\n\n'));
      final posted = <String>[];
      final s = Rig(
        post: (t) async {
          posted.add(t);
          return SendResult.queued;
        },
      );
      await s.c.summarize();
      await settle();
      final preview = s.c.sharePreview;
      await s.c.share();
      expect(posted.join('\n\n'), preview);
    });

    test('a summary with @names and # lines is plain text on the wire', () {
      const summary =
          '# Decisions\n@ana will send it; cc @ravi.\n#tasks\n## Open\n'
          '- ping (@ana) a@b.com';
      final parts = AiSummaryMessageFormat.build(summary);
      for (final part in parts) {
        // Nothing the app or the server would read as a mention.
        expect(MentionText.split(part).where((r) => r.user != null), isEmpty);
        // The message never starts with #, so it is no command and needs no
        // `##` escape; inside `/c <cid> /msg ...` a # line is just text.
        expect(part, startsWith('✨ AI summary\n'));
        final wire = MessageRepository.cidCommand('dm:ana', part, 'm-1')!;
        expect(wire, startsWith('/c m-1 /msg ana ✨ AI summary'));
        final group = MessageRepository.cidCommand('group:sales', part, 'm-1')!;
        expect(group, startsWith('/c m-1 /groupmsg sales ✨ AI summary'));
      }
      expect(parts.single, contains('@\u200Bana'));
      expect(parts.single, contains('#tasks'));
      expect(parts.single, contains('a@b.com'));
    });

    test('a chart becomes text lines in the preview, copy and post', () async {
      final posted = <String>[];
      final fake = _ChartRepository();
      final c = AiSummaryController(
        ai: fake,
        setup: AiSetupCache(fake),
        chatId: 'dm:ana',
        title: () => 'Ana',
        isOnline: () => true,
        post: (t) async {
          posted.add(t);
          return SendResult.queued;
        },
        isAdmin: () => false,
      );
      await c.onSheetOpened();
      await c.summarize();
      await settle();
      const lines =
          'Sales rose.\n\nSales by city (lakh)\n- Pune: 9\n- Goa: 1,250\n\n- Done';
      expect(c.sharePreview, '✨ AI summary\n\n$lines');
      await c.share();
      expect(posted.single, '✨ AI summary\n\n$lines');
      expect(posted.join(), isNot(contains('chart')));
      expect(posted.join(), isNot(contains('"type"')));
      final copied = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied.add((call.arguments as Map)['text'] as String);
            }
            return null;
          });
      await c.copy();
      expect(copied.single, lines);
    });

    test('a malformed or open chart is left out of the text', () async {
      final fake = _ChartRepository(
        'Before.\n\n```chart\n{"type":"bar","data":[\n```\n\nAfter.\n```chart\n{"type"',
      );
      final c = AiSummaryController(
        ai: fake,
        setup: AiSetupCache(fake),
        chatId: 'dm:ana',
        title: () => 'Ana',
        isOnline: () => true,
        post: (t) async => SendResult.queued,
        isAdmin: () => false,
      );
      await c.onSheetOpened();
      await c.summarize();
      await settle();
      expect(c.sharePreview, '✨ AI summary\n\nBefore.\n\nAfter.');
    });

    test('mentions are broken, emails and plain text are not', () {
      final out = AiSummaryMessageFormat.build(
        '@ana ping (@ravi) a@b.com',
      ).single;
      expect(out, contains('@\u200Bana'));
      expect(out, contains('(@\u200Bravi)'));
      expect(out, contains('a@b.com'));
    });

    test('a long text becomes numbered parts that fit, then is shortened', () {
      final long = List.generate(300, (i) => 'Sentence number $i.').join(' ');
      final parts = AiSummaryMessageFormat.build(long);
      expect(parts.length, greaterThan(1));
      expect(parts.length, lessThanOrEqualTo(AiSummaryMessageFormat.maxParts));
      for (var i = 0; i < parts.length; i++) {
        expect(parts[i].length, lessThanOrEqualTo(2000));
        expect(parts[i], startsWith('✨ AI summary (${i + 1}/'));
      }
      final huge = List.generate(2000, (i) => 'Sentence number $i.').join(' ');
      final cut = AiSummaryMessageFormat.build(huge);
      expect(cut, hasLength(AiSummaryMessageFormat.maxParts));
      expect(cut.last, endsWith(AiSummaryMessageFormat.shortened));
    });
  });
}
