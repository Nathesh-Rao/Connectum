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
  test('a database at version 12 with ai_consent loses it at 13', () async {
    final db = _Db(tables: {'messages', 'ai_consent'});
    await AppDatabase.migrate(db, 12, 13);
    expect(db.tables, isNot(contains('ai_consent')));
    expect(db.tables, contains('messages'));
    expect(db.statements, ['DROP TABLE IF EXISTS ai_consent']);
  });

  test(
    'a fresh database never has ai_consent, not even for a moment',
    () async {
      final db = _Db();
      await AppDatabase.migrate(db, 0, 13);
      expect(db.tables, isNot(contains('ai_consent')));
      expect(db.tables, contains('messages'));
      expect(
        db.statements.where(
          (s) => s.toUpperCase().contains('CREATE TABLE AI_CONSENT'),
        ),
        isEmpty,
      );
    },
  );
}
