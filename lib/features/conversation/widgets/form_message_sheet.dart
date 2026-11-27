import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../data/models/form_card.dart';
import '../../../data/models/message.dart';
import '../../submission_detail/submission_detail_view.dart'
    show confirmDeleteSubmission;
import '../../tickets/models/card_menu.dart';
import '../../tickets/widgets/record_menu_rows.dart';
import '../../tickets/widgets/ticket_action_sheet.dart';
import '../conversation_controller.dart';

/// The menu of a form message, opened from "Form actions" in the selection
/// bar: retry or edit for one that failed, and the web's card menu (see
/// [CardMenu]) for one that reached the server. It is the record flow, not
/// the message menu the selection bar replaced.
class FormMessageSheet extends StatelessWidget {
  const FormMessageSheet({
    super.key,
    required this.controller,
    required this.message,
  });

  final ConversationController controller;
  final Message message;

  static Future<void> show(
    BuildContext context,
    ConversationController controller,
    Message message,
  ) {
    controller.openRecordMenu(message);
    return AppBottomSheet.show<void>(
      context,
      title: 'Form',
      child: FormMessageSheet(controller: controller, message: message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final m = message;
    final isSettled = !m.isLocalTemp && m.status != MessageStatus.failed;
    final isFailedForm = m.status == MessageStatus.failed;
    final settledCard = isSettled ? c.formCardOf(m) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isFailedForm) ...[
          if (c.isNotPostedFailure(m))
            AppListRow(
              title: 'Save without posting',
              minHeight: AppSpacing.settingRowHeight,
              leading: const Icon(
                Icons.save_outlined,
                size: 20,
                color: AppColors.muted,
              ),
              onTap: () {
                Navigator.of(context).pop();
                c.saveWithoutPosting(m);
              },
            )
          else if (c.isInvalidFailure(m))
            AppListRow(
              title: 'Edit and resend',
              minHeight: AppSpacing.settingRowHeight,
              leading: const Icon(
                Icons.edit_outlined,
                size: 20,
                color: AppColors.muted,
              ),
              onTap: () {
                Navigator.of(context).pop();
                c.editAndResend(m);
              },
            )
          else
            AppListRow(
              title: 'Retry',
              minHeight: AppSpacing.settingRowHeight,
              leading: const Icon(
                Icons.refresh,
                size: 20,
                color: AppColors.muted,
              ),
              onTap: () {
                Navigator.of(context).pop();
                c.retryForm(m);
              },
            ),
        ],
        if (settledCard != null) _cardMenu(context, settledCard),
      ],
    );
  }

  /// A settled form or record card: the web's menu (see [CardMenu]), the
  /// same list the Work Space opens.
  Widget _cardMenu(BuildContext context, FormCardData card) {
    final c = controller;
    final m = message;
    final recordId = c.recordIdOf(card);
    return RecordMenuRows(
      tickets: c.tickets,
      recordId: recordId,
      itemsFor: (state) => c.cardMenuOf(m, card, state),
      onPick: (item) {
        final root = Navigator.of(context, rootNavigator: true).context;
        Navigator.of(context).pop();
        switch (item.id) {
          case CardMenuItem.reply:
            c.startReply(m);
          case CardMenuItem.copy:
            c.copy(m);
          case CardMenuItem.save:
          case CardMenuItem.pin:
          case CardMenuItem.unread:
            c.tapPlaceholder();
          case CardMenuItem.edit:
            c.editForm(m, card);
          case CardMenuItem.history:
            c.openHistory(card);
          case CardMenuItem.delete:
            c.deleteRecordCard(card, () => confirmDeleteSubmission(root, card));
          default:
            if (item.isRecordAction) {
              final detail = c.ticketDetailOf(card);
              if (detail != null) {
                TicketActionSheet.show(root, detail, item.recordActionId);
              }
            }
        }
      },
    );
  }
}
