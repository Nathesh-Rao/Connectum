import 'package:connectum/core/debug/seed_smart_view.dart';
import 'package:connectum/core/debug/seed_tickets.dart';
import 'package:connectum/data/repositories/smart_view_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';
import 'sv_support.dart';

/// The DEMO_MODE server for Smart View, read by the real repository.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SmartViewRepository repo;
  late TicketRepository tickets;
  final clock = VClock();

  setUp(() async {
    await SeedTickets.start();
    await SeedSmartView.start(isLive: false);
    final socket = FakeSocket();
    final store = FakeStore(user: SeedSmartView.me);
    tickets = TicketRepository(socket, store, FakeConversations());
    repo = SmartViewRepository(
      socket,
      store,
      tickets,
      now: clock.read,
      delay: clock.delay,
    )..onInit();
  });

  tearDown(() {
    repo.onClose();
    SeedSmartView.stop();
    SeedTickets.stop();
  });

  Future<SvTable> open(String name) async {
    final all = await repo.sources();
    return repo.open(all.firstWhere((s) => s.name == name));
  }

  test('four structures; the hidden field is in no field list', () async {
    final all = await repo.sources();
    expect(all.map((s) => s.name).toSet(), {
      'leave',
      'expense',
      'help_ticket',
      'help_task',
    });
    expect(
      all.firstWhere((s) => s.name == 'leave').fieldOf('internal_note'),
      isNull,
    );
  });

  test(
    'Leave request: 120 records through three lists, one copy each',
    () async {
      final t = await open('leave');
      await repo.load(t);
      expect(t.rows.length, 120);
      expect(t.rows.map((r) => r.id).toSet().length, 120);
      expect(t.rows.where((r) => r.isReceived).length, 50);
      expect(t.rows.where((r) => r.canEdit).length, 70);
      expect(
        t.rows.every((r) => !r.values.containsKey('internal_note')),
        isTrue,
      );
      expect(t.phase.value, SvPhase.ready);
    },
  );

  test(
    'Expense claim is empty, Ticket is not_found, Work order fails once',
    () async {
      final empty = await open('expense');
      await repo.load(empty);
      expect(empty.phase.value, SvPhase.empty);

      final gone = await open('help_ticket');
      await repo.load(gone);
      expect(gone.phase.value, SvPhase.noAccess);

      final flaky = await open('help_task');
      await repo.load(flaky);
      expect(flaky.phase.value, SvPhase.error);
      await repo.refresh(flaky);
      expect(flaky.phase.value, SvPhase.ready);
    },
  );

  test(
    'live: a status changes, then a record appears (data.record mode)',
    () async {
      SeedSmartView.isRecordMode = true;
      addTearDown(() => SeedSmartView.isRecordMode = false);
      final t = await open('leave');
      await repo.load(t);
      final before = t.rows.length;
      SeedSmartView.changeStatus();
      await Future<void>.delayed(Duration.zero);
      expect(repo.liveMode, 'record');
      expect(t.versions.length, 1);
      final id = t.versions.keys.single;
      expect(t.rowOf(id)!.values['stage'], 'In progress');
      final newId = SeedSmartView.addRecord();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(t.rows.length, before + 1);
      expect(t.rowOf(newId), isNotNull);
    },
  );

  test('live without data.record: the record is read once', () async {
    SeedSmartView.isRecordMode = false;
    final t = await open('leave');
    await repo.load(t);
    final sentBefore = repo.sent;
    SeedSmartView.changeStatus();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(repo.liveMode, 'refetch');
    expect(repo.sent - sentBefore, 1);
    expect(t.versions.length, 1);
    expect(t.rowOf(t.versions.keys.single)!.values['stage'], 'In progress');
  });
}
