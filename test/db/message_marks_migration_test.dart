import 'package:connectum/data/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  Future<Database> open() => databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );

  test(
    'a phone at version 16 gets message_marks at 17, keeping its rows',
    () async {
      final raw = await open();
      await AppDatabase.migrate(raw, 0, 16);
      await raw.execute(
        "INSERT INTO messages(org_id, user_id, msg_id, conv_id, status) VALUES('o','u','1','self','sent')",
      );
      final tables = await raw.rawQuery(
        "SELECT name FROM sqlite_master WHERE name = 'message_marks'",
      );
      expect(tables, isEmpty);
      await AppDatabase.migrate(raw, 16, 17);
      final columns = {
        for (final r in await raw.rawQuery('PRAGMA table_info(message_marks)'))
          r['name'],
      };
      expect(
        columns,
        containsAll([
          'org_id',
          'user_id',
          'conv_id',
          'msg_id',
          'is_saved',
          'is_pinned',
          'want_saved',
          'want_pinned',
          'pinned_by',
          'pinned_ts',
          'preview',
        ]),
      );
      expect(await raw.rawQuery('SELECT * FROM messages'), hasLength(1));
      await raw.close();
    },
  );

  test('a fresh install has the table and it is wiped with the scope', () async {
    final raw = await open();
    await AppDatabase.migrate(raw, 0, AppDatabase.schemaVersion);
    await raw.execute(
      "INSERT INTO message_marks(org_id, user_id, conv_id, msg_id, is_saved) VALUES('o','u','self','1',1)",
    );
    await raw.execute(
      "INSERT INTO message_marks(org_id, user_id, conv_id, msg_id, is_saved) VALUES('o','v','self','1',1)",
    );
    await AppDatabase.withDatabase(raw).wipeScope('o', 'u');
    final left = await raw.rawQuery('SELECT user_id FROM message_marks');
    expect(left.map((r) => r['user_id']), ['v']);
    await AppDatabase.withDatabase(raw).wipeAll();
    expect(await raw.rawQuery('SELECT * FROM message_marks'), isEmpty);
    await raw.close();
  });
}
