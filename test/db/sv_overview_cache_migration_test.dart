import 'package:connectum/data/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

/// Keeps the tables the statements create and drop, and returns no rows (the
/// version 2 backfill then has nothing to do). No real SQLite is needed.
class _Db extends Fake implements Database {
  _Db({Set<String>? tables}) : tables = tables ?? <String>{};

  final Set<String> tables;
  final statements = <String>[];

  static final _create = RegExp(
    r'CREATE TABLE (?:IF NOT EXISTS )?(\w+)',
    caseSensitive: false,
  );
  static final _drop = RegExp(
    r'DROP TABLE (?:IF EXISTS )?(\w+)',
    caseSensitive: false,
  );

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    statements.add(sql);
    final created = _create.firstMatch(sql)?.group(1);
    if (created != null) tables.add(created);
    final dropped = _drop.firstMatch(sql)?.group(1);
    if (dropped != null) tables.remove(dropped);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async => const [];

  @override
  Batch batch() => _Batch();
}

class _Batch extends Fake implements Batch {
  @override
  Future<List<Object?>> commit({
    bool? exclusive,
    bool? noResult,
    bool? continueOnError,
  }) async => const [];
}

void main() {
  test(
    'a database at version 15 with sv_overview_cache loses it at 16',
    () async {
      final db = _Db(tables: {'messages', 'sv_overview_cache'});
      await AppDatabase.migrate(db, 15, 16);
      expect(db.tables, isNot(contains('sv_overview_cache')));
      expect(db.tables, contains('messages'));
      expect(db.statements, ['DROP TABLE IF EXISTS sv_overview_cache']);
    },
  );

  test('a fresh install works and never creates sv_overview_cache', () async {
    final db = _Db();
    await AppDatabase.migrate(db, 0, 16);
    expect(db.tables, isNot(contains('sv_overview_cache')));
    expect(db.tables, contains('messages'));
    expect(db.tables, contains('people_avatars'));
    expect(
      db.statements.where(
        (q) => q.toUpperCase().contains('CREATE TABLE SV_OVERVIEW_CACHE'),
      ),
      isEmpty,
    );
  });

  test('the sign-out wipe no longer lists the table', () {
    expect(AppDatabase.scopedTables, isNot(contains('sv_overview_cache')));
  });
}
