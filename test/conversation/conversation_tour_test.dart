import 'package:connectum/core/selection/message_selection.dart';
import 'package:connectum/core/selection/selection_rules.dart';
import 'package:connectum/core/tour/tour_id.dart';
import 'package:connectum/core/tour/tour_service.dart';
import 'package:connectum/core/tour/tour_texts.dart';
import 'package:connectum/core/widgets/message_selection/selectable_row.dart';
import 'package:connectum/core/widgets/message_selection/selection_app_bar.dart';
import 'package:connectum/core/widgets/message_selection/selection_reaction_bar.dart';
import 'package:connectum/data/models/reaction.dart';
import 'package:connectum/features/conversation/conversation_tour.dart';
import 'package:connectum/features/conversation/conversation_tour_demo.dart';
import 'package:connectum/features/conversation/widgets/conversation_sample_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../core/tour/tour_demo_test.dart' show startPumped;
import '../core/tour/tour_test_support.dart';

const _dm = ConversationTourCaps(
  canAttach: true,
  canReact: true,
  canEdit: true,
  canReply: true,
  canDelete: true,
);

/// The conversation screen's parts that the tour touches, built from the real
/// widgets: the header switcher with the selection bar, the thread with the
/// sample rows (or one real message), the reaction overlay and the composer.
class _Chat extends StatelessWidget {
  const _Chat({
    required this.tour,
    required this.realSelection,
    required this.hasReal,
    this.scale = 1,
  });

  final ConversationTour tour;
  final MessageSelection realSelection;
  final bool hasReal;
  final double scale;
  @override
  Widget build(BuildContext context) {
    final demo = tour.demo;
    final scroll = ScrollController();
    return MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Obx(() {
          final isSample = demo.isOn.value;
          final selection = isSample ? demo.selection : realSelection;
          final target = isSample
              ? ConversationTourDemo.targetOf(demo.caps)
              : ConversationTourDemo.targetOf(_dm);
          return Column(
            children: [
              SelectionHeaderSwitcher(
                isSelecting: demo.selection.isActive || realSelection.isActive,
                selectionBar: KeyedSubtree(
                  key: tour.selectionBarKey,
                  child: SelectionAppBar(
                    count: selection.ids.length,
                    isEditIcon: true,
                    onExit: () {},
                    items: [
                      for (final a in SelectionRules.available([
                        target,
                      ], isEditIcon: true))
                        SelectionBarItem(
                          action: a,
                          icon: Icons.circle,
                          label: a.name,
                          onTap: () {},
                        ),
                    ],
                  ),
                ),
                header: KeyedSubtree(
                  key: tour.headerKey,
                  child: const SizedBox(height: 56, width: double.infinity),
                ),
              ),
              Expanded(
                child: KeyedSubtree(
                  key: tour.areaKey,
                  child: Stack(
                    children: [
                      ListView(
                        reverse: true,
                        controller: scroll,
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (isSample)
                            for (final i in demo.items)
                              ConversationSampleRow(
                                tour: tour,
                                item: i,
                                isDirect: true,
                              ),
                          if (hasReal)
                            SelectableRow(
                              selection: realSelection,
                              id: 'real-1',
                              swipeKey: tour.swipeKey,
                              onSwipeReply: () {},
                              child: KeyedSubtree(
                                key: tour.messageKey,
                                child: const SizedBox(
                                  height: 44,
                                  child: Text('a real message'),
                                ),
                              ),
                            ),
                        ],
                      ),
                      Positioned.fill(
                        child: SelectionBarOverlay(
                          selection: selection,
                          scroll: scroll,
                          isShown: () => target.canReact,
                          barWidth: SelectionReactionBar.idealWidth(
                            Reaction.quick.length,
                          ),
                          bar: (_) => KeyedSubtree(
                            key: tour.reactionKey,
                            child: SelectionReactionBar(
                              emojis: Reaction.quick,
                              mine: const {},
                              onPick: (_) {},
                              onMore: () {},
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              KeyedSubtree(
                key: tour.composerKey,
                child: const SizedBox(height: 56, width: double.infinity),
              ),
            ],
          );
        }),
      ),
    );
  }
}

void main() {
  late ConversationTour tour;
  late TourService service;
  late MessageSelection real;

  setUp(() {
    service = TourService(userId: () => 'u1', store: memoryStore());
    tour = ConversationTour(service: service);
    real = MessageSelection();
  });

  group('the steps follow what the chat allows', () {
    test('a direct chat gets six, header first', () {
      final steps = tour.steps(_dm, hasMessage: false);
      expect(steps.map((s) => s.title), [
        TourTexts.chatInfoTitle,
        TourTexts.chatComposerTitle,
        TourTexts.chatHashTitle,
        TourTexts.chatSwipeTitle,
        TourTexts.chatHoldTitle,
        TourTexts.chatOptionsTitle,
      ]);
      expect(steps[3].actions.single.kind.name, 'swipeRow');
      expect(steps[4].actions.single.kind.name, 'longPressRow');
      expect(steps[5].actions.single.carry, steps[4].actions.single.carry);
    });

    test(
      'an encrypted chat has no # step, no edit, and says what the lock means',
      () {
        final steps = tour.steps(
          const ConversationTourCaps(
            isEncrypted: true,
            canAttach: true,
            canReact: true,
            canEdit: true,
            canReply: true,
            canDelete: true,
          ),
          hasMessage: false,
        );
        expect(
          steps.map((s) => s.title),
          isNot(contains(TourTexts.chatHashTitle)),
        );
        expect(steps.first.body, TourTexts.chatInfoLockedBody);
        final options = steps.last.body;
        expect(options, isNot(contains('Edit')));
        expect(options, isNot(contains('15 minutes')));
        expect(steps.length, 5);
      },
    );

    test('a chat that cannot send has no composer or # step', () {
      final steps = tour.steps(
        const ConversationTourCaps(
          isEncrypted: true,
          isBlocked: true,
          canReact: true,
          canReply: true,
        ),
        hasMessage: false,
      );
      expect(steps.map((s) => s.target), isNot(contains(tour.composerKey)));
    });

    test('a team has no reply step and no reaction line', () {
      final steps = tour.steps(const ConversationTourCaps(), hasMessage: false);
      expect(
        steps.map((s) => s.title),
        isNot(contains(TourTexts.chatSwipeTitle)),
      );
      final hold = steps.firstWhere((s) => s.title == TourTexts.chatHoldTitle);
      expect(hold.body, 'Press and hold a message to select it.');
      expect(hold.target, tour.messageKey);
      final composer = steps.firstWhere(
        (s) => s.title == TourTexts.chatComposerTitle,
      );
      expect(composer.body, isNot(contains('photo')));
    });

    test('the hold step points at the reaction bar where reactions exist', () {
      final hold = tour
          .steps(_dm, hasMessage: false)
          .firstWhere((s) => s.title == TourTexts.chatHoldTitle);
      expect(hold.target, tour.reactionKey);
      expect(hold.body, contains('Quick reactions'));
    });

    test('the options copy names exactly what the selection bar offers', () {
      final options = tour
          .steps(_dm, hasMessage: false)
          .firstWhere((s) => s.title == TourTexts.chatOptionsTitle);
      expect(
        options.body,
        'The bar shows Reply, Edit, Delete and Forward. More has Copy. '
        'You can edit your own message for 15 minutes.',
      );
      // Chats never offer save or pin of a message.
      expect(options.body, isNot(contains('Save')));
      expect(options.body, isNot(contains('Pin')));
    });

    test('never more than six', () {
      for (final e in [true, false]) {
        for (final b in [true, false]) {
          final caps = ConversationTourCaps(
            isEncrypted: e,
            isBlocked: b,
            canAttach: true,
            canReact: true,
            canEdit: true,
            canReply: true,
            canDelete: true,
          );
          for (final has in [true, false]) {
            expect(
              tour.steps(caps, hasMessage: has).length,
              lessThanOrEqualTo(6),
            );
          }
        }
      }
    });
  });

  group('the sample', () {
    test('a sample own message allows what the chat allows', () {
      final t = ConversationTourDemo.targetOf(_dm);
      expect(t.canEdit && t.canDelete && t.canReply && t.canForward, isTrue);
      final encrypted = ConversationTourDemo.targetOf(
        const ConversationTourCaps(isEncrypted: true, canEdit: true),
      );
      expect(encrypted.canEdit, isFalse);
    });

    test('it seeds only when the chat has no message, and restores', () {
      tour.demo.prepare(_dm, hasRealMessage: true);
      expect(tour.demo.seed(), isFalse);
      expect(tour.demo.isOn.value, isFalse);
      tour.demo.prepare(_dm, hasRealMessage: false);
      expect(tour.demo.seed(), isTrue);
      expect(tour.demo.items.length, 2);
      expect(tour.demo.items.first.message!.isMine, isTrue);
      expect(tour.demo.items.last.message!.isMine, isFalse);
      tour.demo.select();
      expect(tour.demo.selection.isActive, isTrue);
      tour.demo.restore();
      tour.demo.restore();
      expect(tour.demo.isOn.value, isFalse);
      expect(tour.demo.items, isEmpty);
      expect(tour.demo.selection.isActive, isFalse);
    });
  });

  group('on screen', () {
    Future<TourStart> go(
      WidgetTester tester, {
      required bool hasMessage,
      ConversationTourCaps caps = _dm,
    }) async {
      await service.markSeen(TourId.chatList);
      return startPumped(
        tester,
        () => tour.start(
          caps,
          hasMessage: hasMessage,
          holdId: hasMessage ? 'real-1' : null,
          select: real.onLongPress,
          clear: real.clear,
        ),
      );
    }

    Future<void> next(WidgetTester tester, [String? label]) async {
      await tester.tap(find.text(label ?? TourTexts.next));
      // An action's target (a bar) can need a few frames after the action.
      await pumpTour(tester);
      await pumpTour(tester);
    }

    testWidgets('an empty chat shows two tagged samples and the whole script', (
      tester,
    ) async {
      useTallScreen(tester);
      await tester.pumpWidget(
        _Chat(tour: tour, realSelection: real, hasReal: false),
      );
      expect(await tour.start(_dm, hasMessage: false), TourStart.notReady);
      expect(find.text(TourTexts.sampleTag), findsNothing);
      expect(await go(tester, hasMessage: false), TourStart.started);
      await pumpTour(tester);

      expect(find.text(TourTexts.sampleTag), findsNWidgets(2));
      expect(find.text(TourTexts.sampleWelcome), findsOneWidget);
      expect(find.text(TourTexts.sampleReply), findsOneWidget);
      // Samples take no touch.
      expect(
        find.descendant(
          of: find.byType(ConversationSampleRow),
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );

      await next(tester); // composer
      await next(tester); // hash
      final restX = tester.getTopLeft(find.text(TourTexts.sampleWelcome)).dx;
      await next(tester); // swipe
      expect(find.text(TourTexts.chatSwipeTitle), findsOneWidget);
      final slidX = tester.getTopLeft(find.text(TourTexts.sampleWelcome)).dx;
      expect(slidX, greaterThan(restX + 20), reason: 'the row slid right');

      await next(tester); // hold
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(TourTexts.chatHoldTitle), findsOneWidget);
      expect(tour.demo.selection.isActive, isTrue);
      expect(find.byType(SelectionReactionBar), findsOneWidget);
      final backX = tester.getTopLeft(find.text(TourTexts.sampleWelcome)).dx;
      expect(backX, closeTo(restX, 1), reason: 'the swipe was undone');
      expect(real.isActive, isFalse, reason: 'the real selection is untouched');

      await next(tester); // options, selection carried
      expect(find.text(TourTexts.chatOptionsTitle), findsOneWidget);
      expect(tour.demo.selection.isActive, isTrue);
      expect(find.byType(SelectionAppBar), findsOneWidget);

      await next(tester, TourTexts.done);
      expect(service.isActive.value, isFalse);
      expect(tour.demo.isOn.value, isFalse);
      expect(tour.demo.selection.isActive, isFalse);
      expect(find.text(TourTexts.sampleTag), findsNothing);
      expect(find.byType(SelectionAppBar), findsNothing);
      expect(await service.isSeen(TourId.chat), isTrue);
    });

    testWidgets('a chat with a message uses it and shows no sample', (
      tester,
    ) async {
      useTallScreen(tester);
      await tester.pumpWidget(
        _Chat(tour: tour, realSelection: real, hasReal: true),
      );
      expect(await go(tester, hasMessage: true), TourStart.started);
      await pumpTour(tester);
      expect(tour.demo.isOn.value, isFalse);
      expect(find.text(TourTexts.sampleTag), findsNothing);
      await next(tester);
      await next(tester);
      await next(tester); // swipe on the real row
      expect(find.text(TourTexts.chatSwipeTitle), findsOneWidget);
      await next(tester); // hold: the real selection opens
      expect(real.isActive, isTrue);
      expect(real.ids.single, 'real-1');
      expect(tour.demo.selection.isActive, isFalse);
      await next(tester); // options
      expect(real.isActive, isTrue);
      await next(tester, TourTexts.done);
      expect(real.isActive, isFalse, reason: 'cleared when the tour ends');
      expect(find.text('a real message'), findsOneWidget);
    });

    testWidgets('skipping with a selection open clears the real selection', (
      tester,
    ) async {
      useTallScreen(tester);
      await tester.pumpWidget(
        _Chat(tour: tour, realSelection: real, hasReal: true),
      );
      expect(await go(tester, hasMessage: true), TourStart.started);
      await pumpTour(tester);
      await next(tester);
      await next(tester);
      await next(tester);
      await next(tester);
      expect(real.isActive, isTrue);
      await tester.tap(find.text(TourTexts.skip));
      await pumpTour(tester);
      expect(real.isActive, isFalse);
    });

    testWidgets('cancelling with the sample selected puts everything back', (
      tester,
    ) async {
      useTallScreen(tester);
      await tester.pumpWidget(
        _Chat(tour: tour, realSelection: real, hasReal: false),
      );
      expect(await go(tester, hasMessage: false), TourStart.started);
      await pumpTour(tester);
      await next(tester);
      await next(tester);
      await next(tester);
      await next(tester);
      expect(tour.demo.selection.isActive, isTrue);
      tour.cancel();
      await tester.pump();
      expect(tour.demo.isOn.value, isFalse);
      expect(tour.demo.selection.isActive, isFalse);
      expect(await service.isSeen(TourId.chat), isFalse);
    });

    for (final scale in [1.0, 1.5]) {
      testWidgets('320 px wide at ${scale}x text, with the sample', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await loadAppFont();
        await tester.pumpWidget(
          _Chat(tour: tour, realSelection: real, hasReal: false, scale: scale),
        );
        expect(await go(tester, hasMessage: false), TourStart.started);
        await pumpTour(tester);
        for (var i = 0; i < 6; i++) {
          final label = i == 5 ? TourTexts.done : TourTexts.next;
          expect(find.text(label), findsOneWidget, reason: 'step $i');
          final rect = tester.getRect(find.text(label));
          expect(rect.left, greaterThanOrEqualTo(0), reason: 'step $i');
          expect(rect.right, lessThanOrEqualTo(320), reason: 'step $i');
          expect(tester.takeException(), isNull, reason: 'step $i');
          await tester.tap(find.text(label));
          await pumpTour(tester);
          await pumpTour(tester);
        }
        expect(service.isActive.value, isFalse);
        expect(tour.demo.isOn.value, isFalse);
      });
    }
  });
}
