import 'package:connectum/core/debug/seed_tickets.dart';
import 'package:connectum/core/widgets/app_state_view.dart';
import 'package:connectum/data/models/record_state.dart';
import 'package:connectum/data/models/ticket.dart';
import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/features/tickets/tickets_texts.dart';
import 'package:connectum/features/tickets/widgets/ticket_history_panel.dart';
import 'package:connectum/features/tickets/widgets/ticket_history_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.now().millisecondsSinceEpoch;

/// An event [minutes] ago.
Map<String, dynamic> _ev(
  int id,
  String op, {
  String by = 'ben',
  int minutes = 0,
  Map<String, dynamic> extra = const {},
}) => {'id': id, 'op': op, 'by': by, 'ts': _now - minutes * 60000, ...extra};

Map<String, dynamic> _history(
  List<Map<String, dynamic>> events, {
  Map<String, dynamic> files = const {},
}) => {
  'caption': 'Ticket',
  'events': events,
  'names': {
    'ana': 'Ana Rao',
    'ben': 'Ben Iyer',
    'sam': 'Sam Joseph',
    'rhea': 'Rhea Das',
  },
  'fields': {'title': 'Title', 'stage': 'Stage'},
  'files': files,
};

const _ticket = Ticket(id: 24, by: 'ana', ts: 1, tstruct: 'help_ticket');

HistoryFeed _feed(Map<String, dynamic> data) => HistoryFeed(
  history: RecordHistory.parse(data),
  nameOf: (u) => u,
  ticket: _ticket,
  first: 'Open',
);

/// The timeline alone, in a scroll view.
Widget _timeline(Map<String, dynamic> data) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: TicketHistoryTimeline(feed: _feed(data)),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the timeline', () {
    testWidgets('lists the newest event first', (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _timeline(
          _history([
            _ev(1, 'created', by: 'ana', minutes: 30),
            _ev(
              2,
              'sent',
              by: 'ana',
              minutes: 20,
              extra: {
                'to': ['ben'],
                'fromHolder': 'ana',
              },
            ),
            _ev(
              3,
              'status',
              minutes: 10,
              extra: {'fromStatus': 'Open', 'toStatus': 'Done', 'final': true},
            ),
          ]),
        ),
      );
      final created = tester.getTopLeft(find.text('Created')).dy;
      final sent = tester.getTopLeft(find.text('Sent to Ben Iyer')).dy;
      final status = tester.getTopLeft(find.text('Status updated')).dy;
      expect(status, lessThan(sent));
      expect(sent, lessThan(created));
    });

    testWidgets('every kind of event has its icon, title and meta', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _timeline(
          _history([
            for (var i = 0; i < RecordEvent.ops.length; i++)
              _ev(i + 1, RecordEvent.ops[i], by: 'sam', minutes: 90 - i),
          ]),
        ),
      );
      for (final op in RecordEvent.ops) {
        expect(find.text(TicketsTexts.opTitle(op)), findsOneWidget, reason: op);
        final icon = HistoryKind.of(op).icon!;
        expect(find.byIcon(icon), findsWidgets, reason: op);
      }
      expect(
        find.textContaining('Sam Joseph'),
        findsNWidgets(RecordEvent.ops.length),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unknown op is a neutral dot with the BE words', (
      tester,
    ) async {
      await tester.pumpWidget(
        _timeline(_history([_ev(1, 'archived_elsewhere', minutes: 5)])),
      );
      expect(find.text('archived elsewhere'), findsOneWidget);
      expect(HistoryKind.of('archived_elsewhere').icon, isNull);
    });

    testWidgets('a status change is two pills, the final one with a check', (
      tester,
    ) async {
      await tester.pumpWidget(
        _timeline(
          _history([
            _ev(
              1,
              'status',
              extra: {'fromStatus': 'Open', 'toStatus': 'In progress'},
            ),
            _ev(
              2,
              'status',
              minutes: -1,
              extra: {
                'fromStatus': 'In progress',
                'toStatus': 'Done',
                'final': true,
              },
            ),
          ]),
        ),
      );
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('In progress'), findsNWidgets(2));
      expect(find.text('Done'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward), findsNWidgets(2));
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('several recipients collapse to a name and +N, a tap opens', (
      tester,
    ) async {
      await tester.pumpWidget(
        _timeline(
          _history([
            _ev(
              1,
              'sent',
              by: 'ana',
              extra: {
                'to': ['ben', 'sam', 'rhea'],
                'fromHolder': 'ana',
                'via': 'user',
              },
            ),
          ]),
        ),
      );
      expect(find.text('Ana Rao'), findsWidgets);
      expect(find.text('+2'), findsOneWidget);
      expect(find.text('Sam Joseph'), findsNothing);
      await tester.tap(find.text('+2'));
      await tester.pump();
      expect(find.text('+2'), findsNothing);
      expect(find.text('Sam Joseph'), findsOneWidget);
      expect(find.text('Rhea Das'), findsOneWidget);
    });

    testWidgets('completion shows "from -> to" and the hours as a pill', (
      tester,
    ) async {
      await tester.pumpWidget(
        _timeline(
          _history([
            _ev(1, 'status', minutes: 20, extra: {'completion': '40'}),
            _ev(2, 'status', extra: {'completion': '81', 'hours': '2.5'}),
          ]),
        ),
      );
      expect(find.text('81%'), findsOneWidget);
      expect(find.text('40%'), findsNWidgets(2));
      expect(find.text('2.5 h'), findsOneWidget);
    });

    testWidgets('a long remark shows four lines and See more', (tester) async {
      final long = List.filled(40, 'remark').join(' ');
      await tester.pumpWidget(
        _timeline(
          _history([
            _ev(1, 'status', extra: {'remarks': long}),
            _ev(2, 'status', minutes: -1, extra: {'remarks': 'Short one'}),
          ]),
        ),
      );
      expect(find.text('See more'), findsOneWidget);
      expect(find.text('Short one'), findsOneWidget);
      final collapsed = tester
          .getSize(find.text(long, findRichText: true))
          .height;
      await tester.tap(find.text('See more'));
      await tester.pump();
      expect(find.text('See less'), findsOneWidget);
      expect(
        tester.getSize(find.text(long, findRichText: true)).height,
        greaterThan(collapsed),
      );
    });

    testWidgets('files are chips, more than three collapse', (tester) async {
      await tester.pumpWidget(
        _timeline(
          _history(
            [
              _ev(
                1,
                'status',
                extra: {
                  'files': ['f1', 'f2', 'f3', 'f4', 'f5'],
                },
              ),
            ],
            files: {
              for (var i = 1; i <= 5; i++)
                'f$i': {'id': 'f$i', 'name': 'photo$i.png'},
            },
          ),
        ),
      );
      expect(find.text('photo1.png'), findsOneWidget);
      expect(find.text('photo3.png'), findsOneWidget);
      expect(find.text('photo4.png'), findsNothing);
      expect(find.text('+2'), findsOneWidget);
      expect(find.byIcon(Icons.attach_file), findsNWidgets(4));
    });

    testWidgets('edits show three rows, the rest on +N more', (tester) async {
      await tester.pumpWidget(
        _timeline(
          _history([
            _ev(
              1,
              'edited',
              extra: {
                'changes': [
                  for (var i = 1; i <= 4; i++)
                    {'field': 'title', 'from': 'old$i', 'to': 'new$i'},
                ],
              },
            ),
          ]),
        ),
      );
      expect(find.textContaining('old3', findRichText: true), findsOneWidget);
      expect(find.textContaining('old4', findRichText: true), findsNothing);
      await tester.tap(find.text('+1 more'));
      await tester.pump();
      expect(find.textContaining('old4', findRichText: true), findsOneWidget);
    });

    testWidgets('a tap on the time shows the exact date and time', (
      tester,
    ) async {
      await tester.pumpWidget(
        _timeline(_history([_ev(1, 'created', by: 'ana', minutes: 5)])),
      );
      expect(find.text('5 min ago'), findsOneWidget);
      await tester.tap(find.text('5 min ago'));
      await tester.pump(const Duration(milliseconds: 200));
      final at = DateTime.fromMillisecondsSinceEpoch(_now - 5 * 60000);
      expect(find.textContaining('${at.year}'), findsOneWidget);
    });

    testWidgets('one semantics node reads the whole event', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _timeline(
          _history([
            _ev(
              1,
              'status',
              by: 'ben',
              minutes: 120,
              extra: {
                'fromStatus': 'Open',
                'toStatus': 'In progress',
                'completion': '81',
                'remarks': 'Technician called',
              },
            ),
          ]),
        ),
      );
      expect(
        find.bySemanticsLabel(
          'Status updated by Ben Iyer, 2 hours ago, Open to In progress, '
          'completion 81 percent, remark Technician called',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('the panel', () {
    Widget panel({
      RecordHistory? history,
      AppViewState state = AppViewState.content,
      Future<void> Function()? onRefresh,
    }) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TicketHistoryPanel(
            history: history,
            state: state,
            ticket: _ticket,
            nameOf: (u) => u,
            onRefresh: onRefresh ?? () async {},
          ),
        ),
      ),
    );

    testWidgets('empty and error and loading', (tester) async {
      await tester.pumpWidget(panel(state: AppViewState.empty));
      expect(find.text('No history yet'), findsOneWidget);
      var retries = 0;
      await tester.pumpWidget(
        panel(state: AppViewState.error, onRefresh: () async => retries++),
      );
      expect(find.text(TicketsTexts.historyError), findsOneWidget);
      await tester.tap(find.text(TicketsTexts.historyRetry));
      expect(retries, 1);
      await tester.pumpWidget(panel(state: AppViewState.loading));
      expect(find.text('No history yet'), findsNothing);
    });

    testWidgets('the header says the count', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        panel(
          history: RecordHistory.parse(
            _history([_ev(1, 'created'), _ev(2, 'sent')]),
          ),
        ),
      );
      expect(find.bySemanticsLabel('History, 2 events'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a live event fades in', (tester) async {
      tester.view.physicalSize = const Size(420, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final events = [
        for (var i = 1; i <= 30; i++)
          _ev(i, 'status', minutes: 60 - i, extra: {'remarks': 'event $i'}),
      ];
      final data = ValueNotifier(RecordHistory.parse(_history(events)));
      Widget host() => MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: data,
            builder: (_, h, _) => SingleChildScrollView(
              child: TicketHistoryPanel(
                history: h,
                state: AppViewState.content,
                ticket: _ticket,
                nameOf: (u) => u,
                onRefresh: () async {},
              ),
            ),
          ),
        ),
      );
      RecordHistory withNew(int id) => RecordHistory.parse(
        _history([
          ...events,
          _ev(id, 'status', extra: {'remarks': 'event $id'}),
        ]),
      );

      await tester.pumpWidget(host());
      expect(find.text('event 30'), findsOneWidget);

      // At the top: the new event appears with a short fade.
      data.value = withNew(31);
      await tester.pump();
      expect(find.text('event 31'), findsOneWidget);
      final fade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.text('event 31'),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, lessThan(1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(fade.opacity.value, 1);
    });
  });

  group('the demo history', () {
    test('has every kind of event, a long history and a short one', () async {
      await SeedTickets.start();
      addTearDown(SeedTickets.stop);
      RecordHistory read(int id) => RecordHistory.parse(
        SeedTickets.answer(RecordCmd.history, {'id': id}),
      );
      final all = read(SeedTickets.demoHistoryAll);
      final ops = {for (final e in all.events) e.op};
      expect(ops.containsAll(RecordEvent.ops), isTrue);
      expect(all.events.any((e) => e.to.length > 2), isTrue);
      expect(all.events.any((e) => e.remarks.length > 200), isTrue);
      expect(read(SeedTickets.demoHistoryLong).events, hasLength(40));
      expect(read(SeedTickets.demoHistoryShort).events, hasLength(2));
    });
  });
}
