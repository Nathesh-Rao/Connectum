import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import '../sv_file_preview_controller.dart';

/// Text, code, JSON, logs: monospace, selectable, first 200 KB, with a
/// copy-all button; lines wrap or scroll sideways by [SvFilePreviewController.isWrap].
class SvTextViewer extends StatelessWidget {
  const SvTextViewer({super.key, required this.load, required this.isWrap});

  final SvFileLoad load;
  final bool isWrap;

  @override
  Widget build(BuildContext context) {
    final text = load.text.value ?? '';
    final body = SelectableText(text, style: AppSv.fileMono);
    return Stack(
      children: [
        Column(
          children: [
            if (load.isCut.value)
              Container(
                width: double.infinity,
                color: AppColors.violetTint,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: const Text(
                  'Showing first 200 KB — Download for the full file',
                  style: AppText.supporting,
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSv.fileTextPad),
                child: isWrap
                    ? SizedBox(width: double.infinity, child: body)
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: body,
                      ),
              ),
            ),
          ],
        ),
        Positioned(
          right: AppSpacing.xs,
          bottom: AppSpacing.xs,
          child: Material(
            color: AppColors.white,
            shape: const CircleBorder(
              side: BorderSide(color: AppSv.cardBorder),
            ),
            child: IconButton(
              key: const ValueKey('sv-copy-all'),
              tooltip: 'Copy all',
              icon: const Icon(Icons.copy_all_outlined, color: AppColors.ink),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                AppNotices.show('Copied', variant: AppNoticeVariant.success);
              },
            ),
          ),
        ),
      ],
    );
  }
}
