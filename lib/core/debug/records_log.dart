import 'package:flutter/foundation.dart';

/// `[records]` console lines for finding why records or tickets are missing.
/// Debug builds only; ids, counts and codes, never tokens, text or values.
class RecordsLog {
  RecordsLog._();

  static void line(String text) {
    if (kDebugMode) debugPrint('[records] $text');
  }

  /// One line per command: what was asked, what came back.
  static void call(
    String cmd,
    Map<String, dynamic> args, {
    required String org,
    required String user,
    Map<String, dynamic>? reply,
    Object? error,
  }) {
    if (!kDebugMode) return;
    final asked = [
      'cmd=$cmd',
      'org=$org',
      'user=$user',
      if (args['as'] != null) 'as=${args['as']}',
      if (args['id'] != null) 'id=${args['id']}',
      if (args['limit'] != null) 'limit=${args['limit']}',
      if (args['offset'] != null) 'offset=${args['offset']}',
      if (args['priority'] != null) 'priority=${args['priority']}',
    ].join(' ');
    if (error != null) {
      line('$asked -> ERROR $error');
      return;
    }
    final r = reply ?? const {};
    final subs = r['submissions'];
    final notes = r['notifications'];
    final items = r['items'];
    final counts = [
      if (subs is List) 'submissions=${subs.length}',
      if (notes is List) 'notifications=${notes.length}',
      if (items is List) 'items=${items.length}',
      if (r['submission'] is Map) 'submission=1',
      if (r.containsKey('hasMore')) 'hasMore=${r['hasMore']}',
      if (r.containsKey('total')) 'total=${r['total']}',
      if (r.containsKey('holder')) 'holderSet=${'${r['holder']}'.isNotEmpty}',
      if (r['structures'] is Map) 'forms=${(r['structures'] as Map).length}',
    ].join(' ');
    line('$asked -> ok $counts');
  }

  static final _cards = <String>{};

  /// Why a form card became a record card or stayed a plain form card; once
  /// per card and reason.
  static void card({
    required String conversation,
    required int? messageId,
    required String structure,
    required bool isRecord,
    required String rule,
  }) {
    if (!kDebugMode) return;
    final key = '$conversation/$messageId/$isRecord/$rule';
    if (!_cards.add(key)) return;
    line(
      'card conv=$conversation form=$structure id=$messageId '
      '-> ${isRecord ? 'RECORD' : 'plain'} (rule: $rule)',
    );
  }
}
