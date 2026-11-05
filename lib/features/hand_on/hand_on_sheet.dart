import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_highlight_text.dart';
import '../../core/widgets/app_progress_bar.dart';
import '../../core/widgets/app_success_animation.dart';
import '../../data/e2e/e2e_texts.dart';
import '../../data/repositories/hand_on_repository.dart';
import 'hand_on_controller.dart';

/// The work surface of the hand-on: offer, preparing, sending, paused, done,
/// failed, stopped. Closing the sheet never stops a run; Stop does.
class HandOnSheet {
  HandOnSheet._();

  static Future<void> open(BuildContext context, HandOnController c) =>
      AppBottomSheet.show<void>(
        context,
        title: 'Earlier messages',
        child: _Body(controller: c),
      );
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final HandOnController controller;

  static String _count(int n) {
    final s = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final hand = c.hand;
    return Obx(() {
      final offer = hand.offer.value;
      final name = offer?.name ?? 'the new device';
      final p = hand.progress.value;
      final phase = hand.phase.value;
      final children = <Widget>[];
      void gap([double h = AppSpacing.sm]) => children.add(SizedBox(height: h));
      void text(String t, [TextStyle style = AppText.readable]) =>
          children.add(Text(t, style: style));
      void named(String template, [TextStyle style = AppText.readable]) =>
          children.add(
            AppHighlightText(template, values: {'device': name}, style: style),
          );
      void close(String label) => children.add(
        AppButton.text(
          label: label,
          onPressed: () {
            Navigator.of(context).pop();
            hand.close();
          },
        ),
      );

      switch (phase) {
        case HandOnPhase.offered:
          named(
            offer?.isContinue ?? false
                ? E2eTexts.continueTitleTemplate
                : E2eTexts.approveTitleTemplate,
            AppText.subtitle,
          );
          gap();
          text(E2eTexts.approveBody);
          gap(AppSpacing.xs);
          text('ID ${(offer?.id ?? '').substring(0, 8)}', AppText.caption);
          gap(AppSpacing.lg);
          children.add(
            AppButton.primary(
              label: offer?.isContinue ?? false ? 'Continue' : E2eTexts.approve,
              isCentered: true,
              onPressed: hand.approve,
            ),
          );
          gap(AppSpacing.xs);
          children.add(
            AppButton.secondary(
              label: E2eTexts.notMe,
              onPressed: () => c.openSecurity(context),
            ),
          );
          gap(AppSpacing.xs);
          children.add(
            AppButton.text(
              label: E2eTexts.later,
              onPressed: () {
                Navigator.of(context).pop();
                hand.later();
              },
            ),
          );
        case HandOnPhase.checking:
          text('Checking that device…', AppText.subtitle);
          gap();
          text('Making sure it is still yours and still waiting.');
        case HandOnPhase.preparing || HandOnPhase.sending:
          named(E2eTexts.approveRunningTemplate, AppText.subtitle);
          gap();
          if (phase == HandOnPhase.preparing) {
            text('Preparing…');
          } else {
            text(
              p.isTotalKnown
                  ? 'Sending ${_count(p.sent)} of ${_count(p.total)}'
                  : '${_count(p.sent)} sent so far',
              AppText.readableStrong,
            );
            final fraction = p.fraction;
            if (fraction != null) {
              gap(AppSpacing.xs);
              children.add(AppProgressBar(value: fraction));
            }
          }
          if (p.note.isNotEmpty) {
            gap(AppSpacing.xs);
            text('${p.note}…', AppText.caption);
          }
          gap(AppSpacing.xs);
          text(
            'You can leave this screen. It keeps going while Connectum stays open.',
            AppText.caption,
          );
          gap(AppSpacing.lg);
          children.add(
            AppButton.secondary(label: 'Stop', onPressed: hand.cancel),
          );
        case HandOnPhase.paused:
          text('Paused', AppText.subtitle);
          gap();
          text(hand.message.value);
          gap(AppSpacing.lg);
          children.add(
            AppButton.secondary(label: 'Stop', onPressed: hand.cancel),
          );
          gap(AppSpacing.xs);
          close('Close');
        case HandOnPhase.done:
          children.add(const Center(child: AppSuccessAnimation()));
          gap();
          text(E2eTexts.allSet, AppText.subtitle);
          gap(AppSpacing.xs);
          named(E2eTexts.allSetBodyTemplate);
          gap(AppSpacing.lg);
          children.add(
            AppButton.primary(
              label: 'Done',
              isCentered: true,
              onPressed: () {
                Navigator.of(context).pop();
                hand.close();
              },
            ),
          );
        case HandOnPhase.failed:
          text(E2eTexts.couldNotFinish, AppText.subtitle);
          gap();
          text(hand.message.value);
          gap(AppSpacing.lg);
          if (hand.isRetryable.value) {
            children.add(
              AppButton.primary(
                label: E2eTexts.tryAgain,
                isCentered: true,
                onPressed: hand.retry,
              ),
            );
            gap(AppSpacing.xs);
          }
          close('Close');
        case HandOnPhase.cancelled:
          text('Stopped', AppText.subtitle);
          gap();
          text(
            '${_count(p.sent)} messages were already sent and stay there. You can continue from where it stopped.',
          );
          gap(AppSpacing.lg);
          children.add(
            AppButton.primary(
              label: 'Continue',
              isCentered: true,
              onPressed: hand.approve,
            ),
          );
          gap(AppSpacing.xs);
          close('Close');
        case HandOnPhase.gone:
          text('Nothing more to do', AppText.subtitle);
          gap();
          text(hand.message.value);
          gap(AppSpacing.lg);
          close('Close');
        case HandOnPhase.idle:
          text('Nothing is waiting for your earlier messages.');
          gap(AppSpacing.lg);
          close('Close');
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    });
  }
}
