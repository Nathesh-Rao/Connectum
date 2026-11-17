import 'dart:convert';
import 'dart:io';

/// The real captured replies of the record flow, in
/// `test/fixtures/records/` (from the BE's `tools/postman/examples.json`).
Map<String, dynamic> fixture(String name) {
  final file = File('test/fixtures/records/$name.json');
  final reply = jsonDecode(file.readAsStringSync()) as Map;
  return reply.cast<String, dynamic>();
}

/// The `data` of an ok reply.
Map<String, dynamic> fixtureData(String name) =>
    (fixture(name)['data'] as Map).cast<String, dynamic>();
