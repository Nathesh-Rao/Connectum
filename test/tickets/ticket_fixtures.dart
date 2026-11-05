import 'dart:convert';
import 'dart:io';

/// The real captured replies, in `assets/debug/tickets/`.
Map<String, dynamic> fixture(String name) {
  final file = File('assets/debug/tickets/$name.json');
  final reply = jsonDecode(file.readAsStringSync()) as Map;
  return reply.cast<String, dynamic>();
}

/// The `data` of an ok reply.
Map<String, dynamic> fixtureData(String name) =>
    (fixture(name)['data'] as Map).cast<String, dynamic>();
