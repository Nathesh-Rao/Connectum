import '../models/form_definition.dart';
import '../models/ids.dart';
import '../models/struct_records.dart';
import '../records/record_commands.dart';
import '../smart_view/models/sv_row.dart';
import '../socket/socket_service.dart';
import '../../core/log/app_log.dart';

/// The records screen of `#tstruct <name>`: every record of one structure the
/// server lets this person see, read page by page (`submissions.list`, the
/// web's `listRecords`). Rows stay in memory (never SQLite, never a log).
/// The commands go through [call] (the Smart View gate in the app: one at a
/// time, paced, under the rate limit); [deleteRecord] is the app's existing
/// delete (`submissions.delete`).
class StructRecordsRepository {
  StructRecordsRepository({
    required this.call,
    required this.isOnline,
    required this.me,
    required this.isAdmin,
    required this.definition,
    required this.deleteRecord,
  });

  static const pageSize = 50;

  /// The web asks for the person's own waiting/declined ones in one more
  /// list; the newest of those is enough here.
  static const _mineWindow = 100;

  final Future<Map<String, dynamic>> Function(
    String command,
    Map<String, dynamic> args,
  )
  call;
  final bool Function() isOnline;
  final String Function() me;
  final bool Function() isAdmin;
  final Future<FormDefinition?> Function(String name, String scope) definition;

  /// Null when it is gone; otherwise the words to show.
  final Future<String?> Function(String id) deleteRecord;

  bool isMine(String owner) =>
      owner.isNotEmpty && owner.toLowerCase() == me().toLowerCase();

  /// The structure and what this person may see of it. Null when its
  /// definition can't be had.
  Future<StructRecordsSchema?> open(String name, String scope) async {
    final def = await definition(name, scope);
    if (def == null || !def.isFull) return null;
    return StructRecordsSchema.of(
      def,
      isCreator: isMine(idText(def.raw['owner'])),
      isAdmin: isAdmin(),
    );
  }

  /// One page. The first page also carries my own waiting or declined
  /// submissions of this structure (not records, the web shows them too).
  /// Throws [SocketCallError].
  Future<StructRecordsPage> page(
    StructRecordsSchema view, {
    int offset = 0,
  }) async {
    if (!isOnline()) throw const SocketCallError('not_connected');
    final data = await call(RecordCmd.list, {
      'tstruct': view.name,
      'recordsOnly': true,
      'limit': pageSize,
      if (offset > 0) 'offset': offset,
    });
    final rows = _rows(data);
    if (offset == 0) {
      try {
        final all = await call(RecordCmd.list, {
          'tstruct': view.name,
          'limit': _mineWindow,
        });
        final have = {for (final r in rows) r.id};
        for (final r in _rows(all)) {
          final s = r.recordStatus.toLowerCase();
          if ((s == 'pending' || s == 'rejected') &&
              isMine(r.by) &&
              have.add(r.id)) {
            rows.add(r);
          }
        }
        rows.sort((a, b) => b.ts.compareTo(a.ts));
      } on SocketCallError catch (e) {
        AppLog.w('struct_records_repository', 'socket ${e.code}');
        // The records are what this screen is for; the extras are best effort.
      } catch (e, st) {
        AppLog.e('struct_records_repository', e, st);
        // The records are what this screen is for; the extras are best effort.
      }
    }
    final received = (data['submissions'] as List? ?? const []).length;
    final total = data['total'];
    return StructRecordsPage(
      rows: rows,
      total: total is num ? total.toInt() : rows.length,
      hasMore: data['hasMore'] == true,
      received: received,
    );
  }

  static List<SvRow> _rows(Map<String, dynamic> data) => [
    for (final raw in data['submissions'] as List? ?? const [])
      ?SvRow.tryParse(raw, isReceived: false),
  ];

  /// The web's rule for the buttons (`RecordPages.jsx` `canEdit`): the
  /// person's own record that is not waiting for approval. The server decides
  /// again when the action runs.
  bool canChange(StructRecordsSchema view, SvRow row) =>
      !view.isReadOnly &&
      isMine(row.by) &&
      row.recordStatus.toLowerCase() != 'pending';
}
