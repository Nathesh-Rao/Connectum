import '../../../data/models/ticket.dart';
import 'ticket_detail_row.dart';
import 'ticket_text.dart';

/// The record's own values as detail rows, in the form's order: what the
/// header already says (status, assignee, progress, subject) and empty values
/// are left out. The details screen and the chat info page read the same rows.
List<TicketDetailRow> ticketValueRows(Ticket t, {String status = ''}) {
  final table = t.table;
  final hidden = table?.headerFields ?? const <String>{};
  bool isHidden(String key) {
    if (hidden.contains(key)) return true;
    final m = _hiddenSuffix.firstMatch(key);
    return m != null && t.values.containsKey(key.substring(0, m.start));
  }

  return [
    for (final e in t.values.entries)
      if (!isHidden(e.key) &&
          !(table == null &&
              status.isNotEmpty &&
              TicketText.value(e.value) == status) &&
          TicketText.value(e.value).isNotEmpty)
        TicketDetailRow.of(
          t.form?.labelOf(e.key) ?? e.key,
          TicketText.value(e.value),
        ),
  ];
}

final _hiddenSuffix = RegExp(r'_(completion|comments|files|hours)$');

const _summaryOrder = [
  ['ticket no', 'ticket number'],
  ['priority'],
  null,
  ['category'],
  ['subtype', 'sub type', 'sub-type'],
  ['need by', 'due', 'deadline'],
  ['expected', 'completion date'],
];

/// The few rows a ticket is summed up by: ticket no, priority, assigned to,
/// category, subtype, need by and expected completion. The one `null` in
/// [_summaryOrder] is where "Assigned to" goes. A row the form has no value
/// for is left out, except the ticket no, which falls back to the id.
List<TicketDetailRow> ticketSummaryRows(
  Ticket t, {
  required String assignedTo,
}) {
  final values = ticketValueRows(t);
  final rows = <TicketDetailRow>[];
  for (final words in _summaryOrder) {
    if (words == null) {
      if (assignedTo.isNotEmpty) {
        rows.add(TicketDetailRow.of('Assigned to', assignedTo));
      }
      continue;
    }
    final found = values.where(
      (r) => words.any(r.label.toLowerCase().contains),
    );
    if (found.isNotEmpty) {
      rows.add(found.first);
    } else if (words.first == 'ticket no') {
      rows.add(TicketDetailRow.of('Ticket no', '${t.id}'));
    }
  }
  return rows;
}
