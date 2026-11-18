import 'package:connectum/data/models/record_live.dart';
import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';
import 'ticket_fixtures.dart';

Map<String, dynamic> _record({
  String status = 'In progress',
  String holder = 'ben',
  int completion = 40,
  bool isFinal = false,
  int ts = 1000,
  String by = 'ben',
}) => {
  'status': status,
  'holder': holder,
  'claimants': <String>[],
  'completion': completion,
  'final': isFinal,
  'ts': ts,
  'by': by,
};

Map<String, dynamic> _event(String name, Map<String, dynamic> data) => {
  'type': 'sd_event',
  'event': name,
  'data': data,
};

Map<String, dynamic> _changed(int id, [Map<String, dynamic>? record]) =>
    _event('submissions_changed', {
      'id': id,
      'tstruct': 'help_ticket',
      'action': 'Status update',
      'record': ?record,
    });

void main() {
  late FakeSocket socket;
  late TicketRepository repo;

  setUp(() {
    socket = FakeSocket()..goOnline();
    repo = TicketRepository(socket, FakeStore(user: 'ana'), FakeConversations())
      ..onInit();
    addTearDown(repo.onClose);
    socket.answers[RecordCmd.actions] = fixtureData('record_actions');
  });

  test('an event with a record updates the card at once, no command', () {
    repo.onEvent(_changed(24, _record(completion: 70, ts: 5000)));
    final live = repo.liveOf(24).value;
    expect(live.isKnown, isTrue);
    expect(live.status, 'In progress');
    expect(live.holder, 'ben');
    expect(live.completion, 70);
    expect(live.isFinal, isFalse);
    expect(live.lastBy, 'ben');
    expect(live.lastTs, 5000);
    expect(socket.calls, isEmpty);
  });

  test('a card that came with a record shows it', () {
    expect(
      repo.applySummary(
        30,
        RecordSummary.tryParse(_record(status: 'Done', isFinal: true))!,
      ),
      isTrue,
    );
    expect(repo.liveOf(30).value.isFinal, isTrue);
    expect(repo.liveOf(30).value.status, 'Done');
  });

  test('an older or equal ts is ignored, a newer one applies', () {
    repo.onEvent(_changed(24, _record(completion: 70, ts: 5000)));
    repo.onEvent(_changed(24, _record(completion: 10, ts: 4000)));
    expect(repo.liveOf(24).value.completion, 70);
    repo.onEvent(_changed(24, _record(completion: 20, ts: 5000)));
    expect(repo.liveOf(24).value.completion, 70);
    repo.onEvent(_changed(24, _record(completion: 90, ts: 6000)));
    expect(repo.liveOf(24).value.completion, 90);
  });

  test('events out of order end on the newest state', () {
    repo.onEvent(_changed(24, _record(status: 'Done', isFinal: true, ts: 9)));
    repo.onEvent(_changed(24, _record(status: 'Open', ts: 3)));
    repo.onEvent(_changed(24, _record(status: 'In progress', ts: 6)));
    final live = repo.liveOf(24).value;
    expect(live.status, 'Done');
    expect(live.isFinal, isTrue);
  });

  test('a read does not let an older summary undo it', () async {
    repo.onEvent(_changed(24, _record(completion: 70, ts: 5000)));
    await repo.actions(24);
    repo.onEvent(_changed(24, _record(completion: 5, ts: 4000)));
    expect(repo.liveOf(24).value.summaryTs, 5000);
    expect(repo.liveOf(24).value.completion, isNot(5));
  });

  test(
    'a missing record is unknown, not "No status", and is asked for',
    () async {
      repo.showSummary(41, null);
      expect(repo.liveOf(41).value.isKnown, isFalse);
      expect(repo.liveOf(41).value.status, isEmpty);
      socket.answers[RecordCmd.summary] = {
        'summaries': [
          {'id': 41, 'tstruct': 'help_ticket', 'record': _record(ts: 7)},
        ],
        'omitted': 0,
      };
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(socket.count(RecordCmd.summary), 1);
      expect(repo.liveOf(41).value.isKnown, isTrue);
      expect(repo.liveOf(41).value.status, 'In progress');
    },
  );

  test('an event without a record asks records.summary, one batch', () async {
    socket.answers[RecordCmd.summary] = {'summaries': [], 'omitted': 0};
    repo.onEvent(_changed(24));
    repo.onEvent(_changed(25));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(socket.count(RecordCmd.summary), 1);
    final ids = socket.calls.single.args['ids'] as List;
    expect(ids.toSet(), {24, 25});
  });

  test(
    '120 ids go out in 3 calls of at most 50, spaced under the limit',
    () async {
      final stamps = <DateTime>[];
      final sizes = <int>[];
      socket.answers[RecordCmd.summary] = (args) {
        stamps.add(DateTime.now());
        sizes.add((args['ids'] as List).length);
        return {'summaries': <Object>[], 'omitted': 0};
      };
      repo.requestSummaries([for (var i = 1; i <= 120; i++) i]);
      repo.requestSummaries([for (var i = 1; i <= 120; i++) i]);
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      expect(socket.count(RecordCmd.summary), 3);
      expect(sizes, [50, 50, 20]);
      for (var i = 1; i < stamps.length; i++) {
        expect(
          stamps[i].difference(stamps[i - 1]),
          greaterThanOrEqualTo(const Duration(milliseconds: 450)),
        );
      }
    },
  );

  test('an id already in flight is not asked again', () async {
    socket.answers[RecordCmd.summary] = {'summaries': [], 'omitted': 0};
    socket.held[RecordCmd.summary] = Future<void>.delayed(
      const Duration(milliseconds: 600),
    );
    repo.requestSummaries([7, 8]);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    repo.requestSummaries([7, 8]);
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    expect(socket.count(RecordCmd.summary), 1);
  });

  test(
    'a final record hides the actions at once; they come back on a read',
    () async {
      await repo.actions(24);
      expect(repo.itemsOf(24), isNotEmpty);
      repo.onEvent(
        _changed(
          24,
          _record(status: 'Done', isFinal: true, holder: 'ana', ts: 9),
        ),
      );
      expect(repo.itemsOf(24), isEmpty);
      expect(repo.liveOf(24).value.isFinal, isTrue);
      await repo.ensureMenu(24);
      expect(repo.itemsOf(24), isNotEmpty);
    },
  );

  test('a record that is no longer with me hides the actions', () async {
    await repo.actions(24);
    expect(repo.itemsOf(24), isNotEmpty);
    repo.onEvent(_changed(24, _record(holder: 'ben', ts: 10)));
    expect(repo.itemsOf(24), isEmpty);
    expect(repo.liveOf(24).value.holder, 'ben');
  });
}
