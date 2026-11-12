import 'package:connectum/core/theme/app_tones.dart';
import 'package:connectum/features/tickets/models/ticket_detail_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('labels choose icons, anything unknown is notes', () {
    expect(TicketDetailRow.of('Also tell', 'x').icon, Icons.groups_outlined);
    expect(TicketDetailRow.of('Category', 'x').icon, Icons.category_outlined);
    expect(
      TicketDetailRow.of('Expected completion', 'x').icon,
      Icons.event_available_outlined,
    );
    expect(TicketDetailRow.of('Need by', 'x').icon, Icons.event_outlined);
    expect(TicketDetailRow.of('Priority', 'High').icon, Icons.flag_outlined);
    expect(
      TicketDetailRow.of('Subtype', 'x').icon,
      Icons.account_tree_outlined,
    );
    expect(TicketDetailRow.of('Ticket no', '1').icon, Icons.tag);
    expect(TicketDetailRow.of('Mood', 'x').icon, Icons.notes);
  });

  test('priority becomes a tone: high red, medium orange, low slate', () {
    expect(TicketDetailRow.of('Priority', 'High').priority, AppTones.red);
    expect(TicketDetailRow.of('Priority', 'Medium').priority, AppTones.violet);
    expect(TicketDetailRow.of('Priority', 'Low').priority, AppTones.slate);
    expect(TicketDetailRow.of('Category', 'High').priority, isNull);
  });

  test('dates read like the card, other text is untouched', () {
    expect(TicketDetailRow.of('Need by', '2026-11-05').value, '5 Nov 2026');
    expect(
      TicketDetailRow.of('Remarks', 'see 2026-11-05').value,
      'see 2026-11-05',
    );
    expect(TicketDetailRow.of('Remarks', 'Lift stuck').value, 'Lift stuck');
  });
}
