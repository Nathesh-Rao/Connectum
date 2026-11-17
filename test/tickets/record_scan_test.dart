import 'dart:io';

import 'package:connectum/data/models/ticket.dart';
import 'package:connectum/data/records/record_commands.dart';
import 'package:flutter_test/flutter_test.dart';

/// Source scans: the old flow is gone from the app, and the record screens
/// follow the house rules.
void main() {
  final files = [
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart')) f,
  ];

  test('no code sends or reads a removed command', () {
    final hits = <String>[];
    for (final f in files) {
      if (f.path.endsWith('data/records/record_commands.dart')) continue;
      final text = f.readAsStringSync();
      for (final old in RecordCmd.removed) {
        if (text.contains(old)) hits.add('${f.path}: $old');
      }
    }
    expect(hits, isEmpty);
  });

  test('the old status table is not read: no structures[].status.actions', () {
    final model = File('lib/data/models/ticket.dart').readAsStringSync();
    expect(model.contains("['actions']"), isFalse);
    expect(model.contains('class TicketAction'), isFalse);
    expect(model.contains('editableIn'), isFalse);
    final table = TicketTable.tryParse({
      'field': 'stage',
      'statuses': ['A', 'B'],
      'final': ['B'],
      'actions': [
        {'name': 'Send'},
      ],
    })!;
    expect(table.statuses.map((s) => s.name), ['A', 'B']);
  });

  test('command names live in one place', () {
    final scattered = <String>[];
    final names = [
      RecordCmd.mine,
      RecordCmd.actions,
      RecordCmd.status,
      RecordCmd.send,
      RecordCmd.history,
      RecordCmd.people,
      RecordCmd.targets,
      RecordCmd.thread,
      TaskCmd.list,
      TaskCmd.create,
      TaskCmd.update,
    ];
    for (final f in files) {
      if (f.path.endsWith('data/records/record_commands.dart')) continue;
      final text = f.readAsStringSync();
      for (final n in names) {
        if (text.contains("'$n'")) scattered.add('${f.path}: $n');
      }
    }
    expect(scattered, isEmpty);
  });

  test('no typed Get.toNamed<T>', () {
    final hits = [
      for (final f in files)
        if (RegExp(r'toNamed<(?!dynamic)').hasMatch(f.readAsStringSync()))
          f.path,
    ];
    expect(hits, isEmpty);
  });

  test('no pumpAndSettle in the ticket tests', () {
    final hits = [
      for (final f in Directory('test/tickets').listSync())
        if (f is File &&
            !f.path.endsWith('record_scan_test.dart') &&
            f.path.endsWith('.dart') &&
            f.readAsStringSync().contains('pumpAndSettle'))
          f.path,
    ];
    expect(hits, isEmpty);
  });
}
