import 'package:connectum/data/models/ticket.dart';
import 'package:connectum/data/smart_view/models/sv_row.dart';
import 'package:connectum/data/smart_view/models/sv_source.dart';
import 'package:connectum/data/smart_view/overview/sv_overview.dart';
import 'package:connectum/features/smart_view/models/sv_overview_model.dart';
import 'package:flutter_test/flutter_test.dart';

// Wednesday 18 Nov 2026, 12:00 local.
final _now = DateTime(2026, 11, 18, 12);

SvRow _row(
  int id,
  DateTime at, {
  String status = '',
  Map<String, dynamic>? v,
}) => SvRow(
  id: id,
  tstruct: 'leave',
  by: 'me',
  ts: at.millisecondsSinceEpoch,
  recordStatus: status,
  values: v ?? const {},
);

const _plain = SvSource(
  name: 'leave',
  caption: 'Leave',
  fields: [SvField(name: 'stage', caption: 'Stage')],
);

void main() {
  test('this week is Monday 00:00 to now, in the device zone', () {
    expect(SvOverview.weekStart(_now), DateTime(2026, 11, 16));
    final rows = [
      _row(1, DateTime(2026, 11, 16)),
      _row(2, DateTime(2026, 11, 15, 23, 59)),
      _row(3, DateTime(2026, 11, 18, 11)),
      _row(4, _now.add(const Duration(hours: 1))),
    ];
    expect(SvOverview.weekCount(rows, _now), 2);
    expect(
      SvOverview.weekStart(DateTime(2026, 11, 22, 23)),
      DateTime(2026, 11, 16),
    );
  });

  test('seven buckets, today last; older and future records are in none', () {
    final rows = [
      _row(1, DateTime(2026, 11, 18, 1)),
      _row(2, DateTime(2026, 11, 18, 9)),
      _row(3, DateTime(2026, 11, 17, 23)),
      _row(4, DateTime(2026, 11, 12)),
      _row(5, DateTime(2026, 11, 11, 23)),
      _row(6, DateTime(2026, 11, 19)),
    ];
    expect(SvOverview.buckets(rows, _now), [1, 0, 0, 0, 0, 1, 2]);
    expect(SvOverview.buckets(const [], _now), List<int>.filled(7, 0));
  });

  test('status mix: the status field, biggest first, ties by label', () {
    final rows = [
      for (var i = 0; i < 3; i++) _row(i, _now, v: {'stage': 'Open'}),
      _row(10, _now, v: {'stage': 'Done'}),
      _row(11, _now, v: {'stage': 'Blocked'}),
    ];
    const source = SvSource(
      name: 'leave',
      caption: 'Leave',
      fields: [SvField(name: 'stage', caption: 'Stage')],
      table: TicketTable(field: 'stage'),
    );
    final mix = SvOverview.statusMix(source, rows);
    expect(
      [for (final m in mix) '${m.label}:${m.count}'],
      ['Open:3', 'Blocked:1', 'Done:1'],
    );
  });

  test('without a status field the approval words are the mix', () {
    final rows = [
      _row(1, _now, status: 'pending'),
      _row(2, _now, status: 'pending'),
      _row(3, _now),
    ];
    final mix = SvOverview.statusMix(_plain, rows);
    expect(mix.first.label, 'Waiting for approval');
    expect(mix.first.count, 2);
    expect(SvOverview.pendingCount(rows), 2);
  });

  test('a hidden field never reaches a label or a count', () {
    const source = SvSource(
      name: 'leave',
      caption: 'Leave',
      fields: [SvField(name: 'stage', caption: 'Stage')],
      table: TicketTable(field: 'secret'),
    );
    final rows = [
      _row(1, _now, v: {'secret': 'HIDDEN-VALUE'}),
    ];
    final mix = SvOverview.statusMix(source, rows);
    expect(mix.single.label, 'Recorded');
    final stats = SvOverview.stats(source, rows, total: 1, now: _now);
    expect('${stats.mix.map((m) => m.label)}', isNot(contains('HIDDEN')));
  });

  test('last entry wording', () {
    int at(Duration d) => _now.subtract(d).millisecondsSinceEpoch;
    expect(SvOverview.lastEntry(null, _now), 'No records yet');
    expect(
      SvOverview.lastEntry(at(const Duration(seconds: 20)), _now),
      'Last entry just now',
    );
    expect(
      SvOverview.lastEntry(at(const Duration(minutes: 5)), _now),
      'Last entry 5 min ago',
    );
    expect(
      SvOverview.lastEntry(at(const Duration(hours: 31)), _now),
      'Last entry 31 h ago',
    );
    expect(
      SvOverview.lastEntry(at(const Duration(days: 5)), _now),
      'Last entry 5 d ago',
    );
    expect(
      SvOverview.lastEntry(at(const Duration(days: 90)), _now),
      'Last entry 3 mo ago',
    );
  });

  test('thousands separators', () {
    expect(SvOverview.thousands(0), '0');
    expect(SvOverview.thousands(999), '999');
    expect(SvOverview.thousands(1000), '1,000');
    expect(SvOverview.thousands(1234567), '1,234,567');
  });

  test('count is the server total, never less than what was read', () {
    final rows = [_row(1, _now), _row(2, _now)];
    final a = SvOverview.stats(_plain, rows, total: 40, now: _now);
    expect(a.count, 40);
    expect(a.isPartial, isTrue);
    final b = SvOverview.stats(_plain, rows, total: 0, now: _now);
    expect(b.count, 2);
    expect(b.isPartial, isFalse);
  });

  group('the model', () {
    test('reads one structure after another and fills the cards', () async {
      final order = <String>[];
      var bTries = 0;
      var running = 0;
      var maxRunning = 0;
      final model = SvOverviewModel(
        clock: () => _now,
        read: (s) async {
          running++;
          if (running > maxRunning) maxRunning = running;
          order.add(s.name);
          await Future<void>.delayed(const Duration(milliseconds: 5));
          running--;
          if (s.name == 'b' && ++bTries == 1) {
            return const SvOverviewRead(isOk: false);
          }
          return SvOverviewRead(isOk: true, rows: [_row(1, _now)], total: 1);
        },
      );
      const names = ['a', 'b', 'c'];
      await model.start([for (final n in names) SvSource(name: n, caption: n)]);
      expect(order, names);
      expect(maxRunning, 1);
      expect(model.isSettled, isTrue);
      expect(model.hasFailed, isTrue);
      expect(model.isPartial, isTrue);
      expect(model.records, 2);
      expect(model.week, 2);
      expect(model.cards[1].phase.value, SvCardPhase.error);
      await model.retry(model.cards[1]);
      expect(model.cards[1].phase.value, SvCardPhase.ready);
      expect(model.records, 3);
      expect(model.updatedAt.value, _now);
    });

    test('a reset drops a read that is still running', () async {
      final model = SvOverviewModel(
        clock: () => _now,
        read: (s) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return SvOverviewRead(isOk: true, rows: [_row(1, _now)], total: 1);
        },
      );
      final run = model.start([const SvSource(name: 'a', caption: 'A')]);
      model.reset();
      await run;
      expect(model.cards, isEmpty);
      expect(model.updatedAt.value, isNull);
    });

    test('the pending tile needs a structure with an approval flow', () async {
      final model = SvOverviewModel(
        read: (s) async => const SvOverviewRead(isOk: true),
      );
      await model.start([const SvSource(name: 'a', caption: 'A')]);
      expect(model.hasPendingSource, isFalse);
      await model.start([
        const SvSource(
          name: 'b',
          caption: 'B',
          table: TicketTable(field: 'stage'),
        ),
      ]);
      expect(model.hasPendingSource, isTrue);
    });
  });
}
