import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/widgets/app_action_bar.dart';
import '../../../core/widgets/app_form_card.dart';
import '../../../data/models/form_card.dart';
import '../../tickets/models/ticket_action_style.dart';
import '../../tickets/widgets/ticket_action_sheet.dart';
import '../conversation_controller.dart';

/// The actions of a ticket card, under its fields. It shows nothing until the
/// ticket is known and has something this person may do; the ticket is read
/// again (shared, cached) while the card is on screen.
class TicketCardActions extends StatelessWidget {
  const TicketCardActions({
    super.key,
    required this.card,
    required this.controller,
  });

  final FormCardData card;
  final ConversationController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final actions = c.ticketActionsOf(card);
      WidgetsBinding.instance.addPostFrameCallback((_) => c.ensureTicket(card));
      if (actions.isEmpty) {
        return AppFormCardScope.maybeOf(context)?.footer ??
            const SizedBox.shrink();
      }
      return AppFormCardActionArea(
        child: AppActionBar(
          inset: AppFormCardActionArea.inset,
          items: actionItemsOf(actions),
          onTap: (item) {
            final detail = c.ticketDetailOf(card);
            if (detail == null) return;
            final action = actions.firstWhere((a) => a.name == item.id);
            TicketActionSheet.show(context, detail, action);
          },
        ),
      );
    });
  }
}
