import 'package:connectum/core/theme/app_tones.dart';
import 'package:connectum/features/tickets/models/ticket_action_style.dart';
import 'package:connectum/features/tickets/widgets/ticket_action_sheet.dart';
import 'package:connectum/data/models/ticket.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keywords choose icon and tone, ignoring case', () {
    expect(actionStyleFor('SEND').icon, Icons.send_outlined);
    expect(actionStyleFor('Status update').icon, Icons.published_with_changes);
    expect(actionStyleFor('Complete').tone, AppTones.green);
    expect(actionStyleFor('Return').tone, AppTones.orange);
    expect(actionStyleFor('Drop').tone, AppTones.red);
    expect(actionStyleFor('Withdraw').icon, Icons.remove_circle_outline);
    expect(actionStyleFor('Approve').icon, Icons.thumb_up_alt_outlined);
    expect(actionStyleFor('Put on hold').icon, Icons.pause_circle_outline);
    expect(actionStyleFor('Escalate').icon, Icons.trending_up);
  });

  test('the first match wins: a specific word beats the general one', () {
    expect(actionStyleFor('Reassign').icon, Icons.swap_horiz);
    expect(actionStyleFor('Reopen').icon, Icons.restart_alt);
    expect(
      actionStyleFor('Approve and send').icon,
      Icons.thumb_up_alt_outlined,
    );
  });

  test('anything else is an arrow in slate', () {
    final s = actionStyleFor('Banana');
    expect(s.icon, Icons.arrow_forward);
    expect(s.tone, AppTones.slate);
  });

  test('bar items keep the order and names of the actions', () {
    final items = actionItemsOf(const [
      TicketAction(name: 'Send'),
      TicketAction(name: 'Drop'),
    ]);
    expect([for (final i in items) i.id], ['Send', 'Drop']);
    expect(items[1].tone, AppTones.red);
  });

  testWidgets('the sheet header shows the action and where it goes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TicketSheetTitle(
            action: TicketAction(name: 'Return', assign: 'raiser'),
          ),
        ),
      ),
    );
    expect(find.text('Return'), findsOneWidget);
    expect(find.byIcon(Icons.undo), findsOneWidget);
    expect(
      find.text('It goes back to the person who raised it.'),
      findsOneWidget,
    );
  });
}
