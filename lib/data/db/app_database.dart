import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

typedef Row = Map<String, Object?>;

class Sql {
  const Sql(this._executor);

  final DatabaseExecutor _executor;

  Future<List<Row>> query(String sql, [List<Object?> args = const []]) =>
      _executor.rawQuery(sql, args);

  Future<int> insert(String sql, [List<Object?> args = const []]) =>
      _executor.rawInsert(sql, args);

  Future<int> update(String sql, [List<Object?> args = const []]) =>
      _executor.rawUpdate(sql, args);
}

class AppDatabase {
  static const _version = 1;

  static const _migrations = <int, List<String>>{
    1: [
      '''CREATE TABLE organisations(
        org_id TEXT NOT NULL, user_id TEXT NOT NULL, name TEXT, last_active_ts INTEGER,
        PRIMARY KEY(org_id, user_id))''',
      '''CREATE TABLE conversations(
        org_id TEXT NOT NULL, user_id TEXT NOT NULL, conv_id TEXT NOT NULL,
        kind TEXT NOT NULL, title TEXT, last_text TEXT, last_ts INTEGER DEFAULT 0,
        last_from TEXT, unread INTEGER DEFAULT 0, is_archived INTEGER DEFAULT 0,
        is_encrypted INTEGER DEFAULT 0, members_json TEXT,
        PRIMARY KEY(org_id, user_id, conv_id))''',
      '''CREATE TABLE messages(
        org_id TEXT NOT NULL, user_id TEXT NOT NULL, msg_id TEXT NOT NULL,
        conv_id TEXT NOT NULL, sender TEXT, is_mine INTEGER DEFAULT 0,
        kind TEXT DEFAULT 'chat', text TEXT, ts INTEGER DEFAULT 0, reply_to TEXT,
        status TEXT NOT NULL, is_encrypted_unsupported INTEGER DEFAULT 0,
        edited_ts INTEGER, is_deleted INTEGER DEFAULT 0, reactions_json TEXT,
        form_json TEXT, preview_json TEXT, fail_reason TEXT, local_seq INTEGER DEFAULT 0,
        PRIMARY KEY(org_id, user_id, msg_id))''',
      'CREATE INDEX idx_messages_conv ON messages(org_id, user_id, conv_id, ts)',
      '''CREATE TABLE form_submissions(
        org_id TEXT NOT NULL, user_id TEXT NOT NULL, submission_id TEXT NOT NULL,
        tstruct TEXT, by_user TEXT, ts INTEGER DEFAULT 0, values_json TEXT,
        labels_json TEXT, status TEXT, approval_json TEXT, edited_ts INTEGER,
        sync_state TEXT NOT NULL DEFAULT 'synced',
        PRIMARY KEY(org_id, user_id, submission_id))''',
      '''CREATE TABLE form_definitions(
        org_id TEXT NOT NULL, user_id TEXT NOT NULL, name TEXT NOT NULL,
        scope TEXT, caption TEXT, definition_json TEXT, fetched_ts INTEGER,
        PRIMARY KEY(org_id, user_id, name))''',
      '''CREATE TABLE outbox(
        id INTEGER PRIMARY KEY AUTOINCREMENT, org_id TEXT NOT NULL, user_id TEXT NOT NULL,
        conv_id TEXT, kind TEXT NOT NULL, payload_json TEXT NOT NULL, ref_id TEXT,
        status TEXT NOT NULL, retry_count INTEGER DEFAULT 0, next_attempt_ts INTEGER DEFAULT 0,
        last_error TEXT, cursor_at_send TEXT, attempt_ts INTEGER, created_ts INTEGER)''',
      'CREATE INDEX idx_outbox_scope ON outbox(org_id, user_id, status, id)',
      '''CREATE TABLE sync_cursor(
        org_id TEXT NOT NULL, user_id TEXT NOT NULL, conv_id TEXT NOT NULL,
        last_server_id TEXT, last_history_now INTEGER, synced_ts INTEGER,
        PRIMARY KEY(org_id, user_id, conv_id))''',
    ],
  };

  static const _scopedTables = [
    'organisations',
    'conversations',
    'messages',
    'form_submissions',
    'form_definitions',
    'outbox',
    'sync_cursor',
  ];

  Database? _db;

  Future<Database> get _database async => _db ??= await openDatabase(
    p.join(await getDatabasesPath(), 'connectum.db'),
    version: _version,
    onCreate: (db, _) => _migrate(db, 0, _version),
    onUpgrade: _migrate,
  );

  static Future<void> _migrate(Database db, int from, int to) async {
    for (var v = from + 1; v <= to; v++) {
      for (final statement in _migrations[v]!) {
        await db.execute(statement);
      }
    }
  }

  Future<List<Row>> query(String sql, [List<Object?> args = const []]) async =>
      Sql(await _database).query(sql, args);

  Future<int> insert(String sql, [List<Object?> args = const []]) async =>
      Sql(await _database).insert(sql, args);

  Future<int> update(String sql, [List<Object?> args = const []]) async =>
      Sql(await _database).update(sql, args);

  Future<T> transaction<T>(Future<T> Function(Sql sql) action) async {
    final db = await _database;
    return db.transaction((txn) => action(Sql(txn)));
  }

  Future<void> wipeScope(String orgId, String userId) =>
      transaction((sql) async {
        for (final table in _scopedTables) {
          await sql.update(
            'DELETE FROM $table WHERE org_id = ? AND user_id = ?',
            [orgId, userId],
          );
        }
      });
}
