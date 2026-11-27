import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';

/// The things to do with the log file: Share to Connectum first, then view,
/// save and the system share. The sheet's own header comes
/// from [AppBottomSheet.show].
class LogsOptionsSheet extends StatelessWidget {
  const LogsOptionsSheet({
    super.key,
    required this.hasFile,
    required this.onView,
    required this.onSave,
    required this.onShare,
    this.onShareToConnectum,
  });

  final bool hasFile;
  final Future<void> Function() onView;
  final Future<void> Function() onSave;
  final Future<void> Function() onShare;

  /// Opens the Share to Connectum picker; null hides the card.
  final Future<void> Function()? onShareToConnectum;

  Widget _icon(IconData icon) => Icon(icon, color: AppColors.primary);

  Widget _fileRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Future<void> Function() action,
  }) => Semantics(
    button: true,
    enabled: hasFile,
    child: Opacity(
      opacity: hasFile ? 1 : 0.5,
      child: AppListRow(
        title: title,
        subtitle: subtitle,
        leading: _icon(icon),
        minHeight: AppSpacing.minTapTarget + AppSpacing.md,
        onTap: hasFile
            ? () {
                Navigator.of(context).pop();
                action();
              }
            : null,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (onShareToConnectum != null)
        _ConnectumCard(
          isEnabled: hasFile,
          onTap: () {
            Navigator.of(context).pop();
            onShareToConnectum!();
          },
        ),
      _fileRow(
        context,
        icon: Icons.article_outlined,
        title: 'View log file',
        subtitle: 'Read the log inside the app',
        action: onView,
      ),
      _fileRow(
        context,
        icon: Icons.download_outlined,
        title: 'Save to device',
        subtitle: 'Copy the log file to your Downloads',
        action: onSave,
      ),
      _fileRow(
        context,
        icon: Icons.ios_share_outlined,
        title: 'Share file',
        subtitle: 'Send the log file with another app',
        action: onShare,
      ),
      if (!hasFile)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text(
            'No log file yet. Turn on Logs to create one.',
            style: AppText.caption.copyWith(color: AppColors.muted),
          ),
        ),
    ],
  );
}

/// The primary choice: a tonal card in the app's accent, above the rows.
class _ConnectumCard extends StatelessWidget {
  const _ConnectumCard({required this.isEnabled, required this.onTap});

  final bool isEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: isEnabled,
    label: 'Share to Connectum. Send the log file to a chat',
    excludeSemantics: true,
    child: Opacity(
      opacity: isEnabled ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Material(
          color: AppColors.primarySoft,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.cardAll,
            side: const BorderSide(color: AppColors.primaryBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('logs-share-connectum'),
            onTap: isEnabled ? onTap : null,
            child: Container(
              constraints: const BoxConstraints(
                minHeight: AppSpacing.minTapTarget + AppSpacing.lg,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Container(
                    width: AppSpacing.avatarSmall,
                    height: AppSpacing.avatarSmall,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      size: 18,
                      color: AppColors.white,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Share to Connectum',
                          style: AppText.rowTitle.copyWith(
                            color: AppColors.primaryStrong,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Send the log file to a chat',
                          style: AppText.rowCaption,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.primary),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
