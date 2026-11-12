import 'package:flutter/material.dart';
import './app_spinner.dart';
import 'package:get/get.dart';

import '../routes/invite_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'app_button.dart';
import 'app_highlight_text.dart';

/// A calm card for an invite or a step of joining. [onDismiss] null hides the
/// close button.
class AppInviteCard extends StatelessWidget {
  const AppInviteCard({
    super.key,
    required this.title,
    this.message,
    this.values = const {},
    this.icon = Icons.groups_outlined,
    this.isLoading = false,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
  });

  final String title;
  final String? message;

  /// Names in [title] and [message] (`{key}` placeholders) that stand out.
  final Map<String, String> values;
  final IconData icon;
  final bool isLoading;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(
        left: AppSpacing.sm,
        top: AppSpacing.xxs,
        bottom: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: AppSpacing.avatarSmall,
            height: AppSpacing.avatarSmall,
            decoration: const BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: AppRadius.mdAll,
            ),
            child: isLoading
                ? const Center(child: AppSpinner(size: AppSpinnerSize.sm))
                : Icon(icon, size: 18, color: AppColors.primaryBright),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppHighlightText(
                    title,
                    values: values,
                    style: AppText.bodyStrong,
                  ),
                  if (message != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    AppHighlightText(
                      message!,
                      values: values,
                      style: AppText.readable.copyWith(color: AppColors.muted),
                    ),
                  ],
                  if (actionLabel != null && onAction != null)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onAction,
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          actionLabel!,
                          style: AppText.readableStrong.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (onDismiss != null)
            AppButton.icon(
              icon: Icons.close,
              semanticLabel: 'Dismiss',
              onPressed: onDismiss,
            )
          else
            const SizedBox(width: AppSpacing.sm),
        ],
      ),
    );
  }
}

/// The invite card of the welcome and sign-in screens: empty unless there is
/// an invite (or the one-time hint) to show.
class AppInviteSlot extends StatelessWidget {
  const AppInviteSlot({super.key, required this.invite});

  final InviteService invite;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final status = invite.status.value;
      final isShown = status != InviteStatus.none;
      return AnimatedSize(
        duration: AppDurations.base,
        curve: AppCurves.out,
        alignment: Alignment.topCenter,
        child: !isShown
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: AppInviteCard(
                  title: invite.title,
                  message: invite.message,
                  icon: status == InviteStatus.hint
                      ? Icons.qr_code_scanner
                      : Icons.groups_outlined,
                  isLoading: status == InviteStatus.loading,
                  actionLabel: invite.actionLabel,
                  onAction: status == InviteStatus.invalid
                      ? invite.dismiss
                      : invite.retry,
                  onDismiss: status == InviteStatus.invalid
                      ? null
                      : invite.dismiss,
                ),
              ),
      );
    });
  }
}
