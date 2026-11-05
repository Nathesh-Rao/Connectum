import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/relative_time.dart';
import '../../../core/widgets/app_tag.dart';
import '../../../data/models/approval.dart';
import '../approvals_texts.dart';

/// One request in a list: its type, what it is about, who it is from (or who
/// it waits for), the time and the status.
class ApprovalTile extends StatelessWidget {
  const ApprovalTile({super.key, required this.request, required this.onTap});

  final Approval request;
  final VoidCallback onTap;

  /// What the request says: the form's name, the server's message, or the
  /// requester.
  static String headline(Approval r) {
    if (r.caption.isNotEmpty) return r.caption;
    if (r.message.isNotEmpty) return r.message;
    return ApprovalsTexts.typeLabel(r.type);
  }

  /// "Waiting for meg, raj" for a request I sent that is still open; the
  /// requester otherwise.
  static String whoLine(Approval r) {
    if (r.isOutgoing && r.isPending && r.approvers.isNotEmpty) {
      return '${ApprovalsTexts.waitingFor} ${r.approvers.join(', ')}';
    }
    return '${ApprovalsTexts.from} ${r.fromLabel}';
  }

  @override
  Widget build(BuildContext context) {
    final r = request;
    final summary = r.lines.take(2).map((l) => '${l.caption}: ${l.value}');
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.page,
            vertical: AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ApprovalsTexts.typeLabel(r.type).toUpperCase(),
                      style: AppText.eyebrow,
                    ),
                  ),
                  Text(
                    RelativeTime.label(r.createdTs, DateTime.now()),
                    style: AppText.rowCaption,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                headline(r),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.rowTitle,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(whoLine(r), style: AppText.rowCaption),
              if (summary.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  summary.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.readable.copyWith(color: AppColors.muted),
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              AppTag(
                label: ApprovalsTexts.statusLabel(r.status),
                tone: r.isPending ? AppTagTone.accent : AppTagTone.neutral,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
