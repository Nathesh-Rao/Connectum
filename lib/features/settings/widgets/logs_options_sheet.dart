import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/app_tag.dart';

/// The four things to do with the log file. The sheet's own header comes
/// from [AppBottomSheet.show].
class LogsOptionsSheet extends StatelessWidget {
  const LogsOptionsSheet({
    super.key,
    required this.hasFile,
    required this.onView,
    required this.onSave,
    required this.onShare,
    required this.onUpload,
  });

  final bool hasFile;
  final Future<void> Function() onView;
  final Future<void> Function() onSave;
  final Future<void> Function() onShare;
  final VoidCallback onUpload;

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
      Semantics(
        button: true,
        child: AppListRow(
          title: 'Upload log',
          subtitle: 'Send the log file to support',
          leading: _icon(Icons.cloud_upload_outlined),
          minHeight: AppSpacing.minTapTarget + AppSpacing.md,
          trailing: const AppTag(label: 'Soon'),
          onTap: onUpload,
        ),
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
