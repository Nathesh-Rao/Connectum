import '../../data/db/app_database.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/message_repository.dart';
import 'cache_vectors.dart';

/// One conversation and one message are written under a dummy organisation A
/// and none under B. Read through the repositories as B nothing may come back;
/// as A the rows do. Only the dummy rows are written and removed.
class ScopeVectors {
  ScopeVectors._();

  static const _a = '__scope_vectors_a__';
  static const _b = '__scope_vectors_b__';
  static const _user = 'u1';
  static const _conv = 'dm:scope_check';

  static Future<List<CacheVector>> run(
    AppDatabase db,
    ConversationRepository conversations,
    MessageRepository messages,
  ) async {
    final out = <CacheVector>[];
    try {
      await _clean(db);
      await db.transaction((sql) async {
        await ConversationRepository.ensure(sql, _a, _user, _conv);
        await sql.insert(
          "INSERT INTO messages(org_id, user_id, msg_id, conv_id, status, text, ts) VALUES(?,?,'scope-1',?,'sent','x',1)",
          [_a, _user, _conv],
        );
      });
      final convB = await conversations.readFor(_b, _user);
      final convA = await conversations.readFor(_a, _user);
      final msgB = await messages.readFor(_b, _user, _conv);
      final msgA = await messages.readFor(_a, _user, _conv);
      final convUser = await conversations.readFor(_a, 'u2');
      final msgUser = await messages.readFor(_a, 'u2', _conv);
      out.add(
        CacheVector(
          'conversations: org B sees nothing, org A sees its row',
          convB.isEmpty && convA.length == 1,
          'B ${convB.length}, A ${convA.length}',
        ),
      );
      out.add(
        CacheVector(
          'messages: org B sees nothing, org A sees its row',
          msgB.isEmpty && msgA.length == 1,
          'B ${msgB.length}, A ${msgA.length}',
        ),
      );
      out.add(
        CacheVector(
          'conversations and messages: another user of org A sees nothing',
          convUser.isEmpty && msgUser.isEmpty,
          'conversations ${convUser.length}, messages ${msgUser.length}',
        ),
      );
    } on Object catch (e) {
      out.add(CacheVector('scope checks ran', false, '$e'));
    } finally {
      try {
        await _clean(db);
      } on Object catch (_) {}
    }
    return out;
  }

  static Future<void> _clean(AppDatabase db) => db.transaction((sql) async {
    for (final table in ['messages', 'conversations']) {
      await sql.update('DELETE FROM $table WHERE org_id IN (?, ?)', [_a, _b]);
    }
  });
}
