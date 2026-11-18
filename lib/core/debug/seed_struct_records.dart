import '../../data/repositories/struct_records_repository.dart';
import '../../data/repositories/submission_repository.dart';
import '../../demo/demo_mode.dart';
import 'seed_ui.dart';

/// Sample records for the `#tstruct <name>` screen (DEMO_MODE / SEED_UI): the
/// Leave request structure with my own records and other people's, so the
/// Edit and Delete rules show. No server; debug builds only.
class SeedStructRecords {
  SeedStructRecords._();

  static bool get isActive => SeedUi.isActive;

  static const me = DemoMode.username;

  static List<Map<String, dynamic>>? _rows;

  static List<Map<String, dynamic>> _seed() {
    final now = DateTime.now().millisecondsSinceEpoch;
    Map<String, dynamic> row(
      int i,
      String by,
      String byName,
      String kind,
      int days, {
      String status = '',
    }) => {
      'id': 5000 + i,
      'tstruct': 'leave',
      'by': by,
      'byName': byName,
      'ts': now - 3600000 * (i + 1),
      if (status.isNotEmpty) 'status': status,
      'values': {
        'kind': kind,
        'from': '2026-11-${(10 + i).toString().padLeft(2, '0')}',
        'days': days,
        'doctor': kind == 'Sick leave' ? 'Dr. Rao' : '',
      },
    };
    return [
      row(1, me, 'Alex Morgan', 'Casual leave', 2),
      row(2, 'maya', 'Maya Iyer', 'Sick leave', 3),
      row(3, me, 'Alex Morgan', 'Earned leave', 5, status: 'pending'),
      row(4, 'sam', 'Sam Verma', 'Casual leave', 1),
      row(5, me, 'Alex Morgan', 'Sick leave', 4, status: 'rejected'),
      row(6, 'maya', 'Maya Iyer', 'Earned leave', 7),
    ];
  }

  static StructRecordsRepository repository(SubmissionRepository submissions) {
    final rows = _rows ??= _seed();
    return StructRecordsRepository(
      call: (command, args) async {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        final onlyRecords = args['recordsOnly'] == true;
        final list = [
          for (final r in rows)
            if (!onlyRecords ||
                (r['status'] != 'pending' && r['status'] != 'rejected'))
              r,
        ];
        final offset = (args['offset'] as int?) ?? 0;
        final limit = (args['limit'] as int?) ?? 50;
        final page = list.skip(offset).take(limit).toList();
        return {
          'submissions': page,
          'total': list.length,
          'offset': offset,
          'limit': limit,
          'hasMore': offset + page.length < list.length,
        };
      },
      isOnline: () => true,
      me: () => me,
      isAdmin: () => false,
      definition: (name, scope) async => submissions.definitions[name],
      deleteRecord: (id) async {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        rows.removeWhere((r) => '${r['id']}' == id);
        return null;
      },
    );
  }
}
