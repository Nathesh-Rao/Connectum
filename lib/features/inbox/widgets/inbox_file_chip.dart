import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_sv.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_tones.dart';
import '../../../data/smart_view/sv_file.dart';
import '../models/inbox_card_rows.dart';

/// The files of one field as a single chip: the file icon and "3 files" (or
/// "1 file"). It is built from [SvFile]s, so when the server sends names,
/// types and sizes (`fileMeta`) a lone file shows its name and type. Tapping
/// opens the Smart View file preview on these files (it fetches on tap).
class InboxFileChip extends StatelessWidget {
  const InboxFileChip({super.key, required this.files, this.onOpen});

  final List<SvFile> files;
  final void Function(List<SvFile> files)? onOpen;

  String get _label {
    if (files.length == 1 && files.first.name != 'File') {
      return '${files.first.name} · ${files.first.metaText}';
    }
    return InboxCardRow.filesText(files.length);
  }

  @override
  Widget build(BuildContext context) {
    final open = onOpen;
    final tone = AppTones.violet;
    return Semantics(
      button: open != null,
      label: _label,
      excludeSemantics: true,
      onTap: open == null ? null : () => open(files),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open == null ? null : () => open(files),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSv.fileMinHit),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(AppSv.fileChipRadius),
                border: Border.all(color: AppSv.cardBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xxs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.attach_file_rounded,
                      size: AppSpacing.popupMenuIcon,
                      color: tone.strong,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Flexible(
                      child: Text(
                        _label,
                        style: AppText.inboxValue.copyWith(color: tone.strong),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
