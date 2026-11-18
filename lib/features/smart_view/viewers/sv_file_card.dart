import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_sv.dart';
import '../../../core/theme/app_text.dart';
import '../../../data/smart_view/sv_file.dart';
import '../widgets/sv_file_chips.dart';

/// A file the viewer cannot draw: a big tinted type icon, the name, the type
/// and the size. Download and Open with are in the bar below.
class SvFileCard extends StatelessWidget {
  const SvFileCard({super.key, required this.file, this.note});

  /// The calm card for a PDF that cannot be opened (protected or broken).
  const SvFileCard.pdfProblem({super.key, required this.file})
    : note = "This PDF can't be previewed";

  final SvFile file;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final size = file.sizeText;
    final type = file.typeLabel;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: AppSv.fileCircle,
              height: AppSv.fileCircle,
              decoration: BoxDecoration(
                color: file.kind.palette.background,
                shape: BoxShape.circle,
              ),
              child: Icon(
                svFileIcon(file.kind),
                size: AppSv.fileCircleIcon,
                color: file.kind.palette.foreground,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              SvFile.middleEllipsis(file.name, 40),
              style: AppSv.fileTitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              size.isEmpty ? type : '$type · $size',
              style: AppText.supporting,
            ),
            if (note != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                note!,
                style: AppText.supporting.copyWith(color: AppColors.ink),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
