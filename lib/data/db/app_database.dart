import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/ids.dart';

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
  static const _version = 7;
  static const couldNotConfirm = "couldn't confirm delivery";

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
    2: [
      'ALTER TABLE messages ADD COLUMN cid TEXT',
      'ALTER TABLE outbox ADD COLUMN cid TEXT',
      'ALTER TABLE outbox ADD COLUMN first_attempt_ts INTEGER',
      'ALTER TABLE sync_cursor ADD COLUMN has_more INTEGER',
      'ALTER TABLE sync_cursor ADD COLUMN next_id TEXT',
      'ALTER TABLE sync_cursor ADD COLUMN gap_to TEXT',
      'CREATE INDEX idx_outbox_cid ON outbox(org_id, user_id, cid)',
    ],
    3: [
      'ALTER TABLE conversations ADD COLUMN read_ts INTEGER',
      'ALTER TABLE conversations ADD COLUMN read_id TEXT',
    ],
    4: [
      'ALTER TABLE conversations ADD COLUMN last_id TEXT',
      'ALTER TABLE conversations ADD COLUMN unread_more INTEGER DEFAULT 0',
      'ALTER TABLE conversations ADD COLUMN is_pinned INTEGER DEFAULT 0',
      'ALTER TABLE conversations ADD COLUMN pinned_ts INTEGER',
      'ALTER TABLE conversations ADD COLUMN is_muted INTEGER DEFAULT 0',
      'ALTER TABLE conversations ADD COLUMN delivered_id TEXT',
      'ALTER TABLE conversations ADD COLUMN peer_read_id TEXT',
      'ALTER TABLE conversations ADD COLUMN peer_delivered_id TEXT',
      'ALTER TABLE conversations ADD COLUMN avatar TEXT',
      'ALTER TABLE conversations ADD COLUMN pending_read_id TEXT',
      'ALTER TABLE conversations ADD COLUMN pending_delivered_id TEXT',
      // The version 3 columns held a local "last opened" marker; the server's
      // read position replaces it, so the old values must not be read as one.
      'UPDATE conversations SET read_id = NULL, read_ts = NULL',
    ],
    5: [
      '''CREATE TABLE form_options(
        org_id TEXT NOT NULL, user_id TEXT NOT NULL, options_json TEXT,
        categories_json TEXT, fetched_ts INTEGER,
        PRIMARY KEY(org_id, user_id))''',
      '''CREATE TABLE form_recents(
        org_id TEXT NOT NULL, user_id TEXT NOT NULL, name TEXT NOT NULL,
        scope TEXT, caption TEXT, used_ts INTEGER,
        PRIMARY KEY(org_id, user_id, name))''',
      'ALTER TABLE form_submissions ADD COLUMN rejection_json TEXT',
    ],
    6: [
      'ALTER TABLE messages ADD COLUMN plaintext TEXT',
      'ALTER TABLE messages ADD COLUMN decrypt_state TEXT',
      "UPDATE messages SET decrypt_state = 'pending' WHERE is_encrypted_unsupported = 1",
    ],
    // Pins hold public keys only and are kept on sign-out (not in
    // _scopedTables) so a key that changed while signed out is still noticed.
    7: [
      '''CREATE TABLE e2e_pins(
        org_id TEXT NOT NULL, user_id TEXT NOT NULL, device_user TEXT NOT NULL,
        device_id TEXT NOT NULL, ecdh TEXT NOT NULL, sign TEXT NOT NULL,
        first_ts INTEGER, trusted_ts INTEGER,
        PRIMARY KEY(org_id, user_id, device_user, device_id))''',
    ],
  };

  static const _scopedTables = [
    'organisations',
    'conversations',
    'messages',
    'form_submissions',
    'form_definitions',
    'form_options',
    'form_recents',
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
      if (v == 2) await _backfillCids(db);
    }
  }

  /// Rows from before client ids. A send that was never confirmed (`sending`)
  /// may already be on the server, so it is failed for tap-to-retry instead
  /// of being re-sent. Unsent rows get a cid and stay pending. Other own
  /// messages get one for consistency only.
  static Future<void> _backfillCids(Database db) async {
    final batch = db.batch();
    final sends = await db.rawQuery(
      "SELECT id, org_id, user_id, ref_id, status, attempt_ts FROM outbox WHERE kind IN ('message','reply')",
    );
    for (final r in sends) {
      final cid = newCid();
      final key = [r['org_id'], r['user_id'], r['ref_id']];
      if (r['status'] == 'sending') {
        batch.rawUpdate(
          "UPDATE outbox SET cid = ?, status = 'failed', last_error = ?, first_attempt_ts = attempt_ts WHERE id = ?",
          [cid, couldNotConfirm, r['id']],
        );
        batch.rawUpdate(
          "UPDATE messages SET cid = ?, status = 'failed', fail_reason = ? WHERE org_id = ? AND user_id = ? AND msg_id = ?",
          [cid, couldNotConfirm, ...key],
        );
      } else {
        batch.rawUpdate('UPDATE outbox SET cid = ? WHERE id = ?', [
          cid,
          r['id'],
        ]);
        batch.rawUpdate(
          'UPDATE messages SET cid = ? WHERE org_id = ? AND user_id = ? AND msg_id = ?',
          [cid, ...key],
        );
      }
    }
    final own = await db.rawQuery(
      'SELECT rowid AS r FROM messages WHERE is_mine = 1 AND cid IS NULL',
    );
    for (final r in own) {
      batch.rawUpdate('UPDATE messages SET cid = ? WHERE rowid = ?', [
        newCid(),
        r['r'],
      ]);
    }
    await batch.commit(noResult: true);
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
