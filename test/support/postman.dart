import 'dart:convert';
import 'dart:io';

/// The real sample replies of the Postman collection, by item name.
class Postman {
  Postman._(this._items);

  static final Postman instance = Postman._(_load());

  final Map<String, Map<String, dynamic>> _items;

  static Map<String, Map<String, dynamic>> _load() {
    final file = File(
      'reference/tickets/postman/Connectum_Mobile_QR.postman_collection.json',
    );
    final root = jsonDecode(file.readAsStringSync()) as Map;
    final out = <String, Map<String, dynamic>>{};
    void walk(Object? items, String prefix) {
      for (final raw in items as List) {
        final item = raw as Map;
        final name = '$prefix${item['name']}';
        if (item['item'] != null) {
          walk(item['item'], '$name/');
          continue;
        }
        final responses = item['response'];
        if (responses is List && responses.isNotEmpty) {
          final body = (responses.first as Map)['body'];
          if (body is String && body.trim().startsWith('{')) {
            out[name] = (jsonDecode(body) as Map).cast<String, dynamic>();
          }
        }
      }
    }

    walk(root['item'], '');
    return out;
  }

  /// The whole reply of the item whose full name ends with [suffix].
  Map<String, dynamic> reply(String suffix) {
    final hits = _items.entries.where((e) => e.key.endsWith(suffix)).toList();
    if (hits.length != 1) {
      throw StateError('"$suffix" matches ${hits.length} items');
    }
    return hits.single.value;
  }

  /// The `data` of an ok reply.
  Map<String, dynamic> data(String suffix) =>
      (reply(suffix)['data'] as Map).cast<String, dynamic>();

  /// The `error` of a refusal.
  Map<String, dynamic> error(String suffix) =>
      (reply(suffix)['error'] as Map).cast<String, dynamic>();
}
