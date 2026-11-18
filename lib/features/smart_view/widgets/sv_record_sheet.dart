import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_sv.dart';
import '../../../core/theme/app_text.dart';
import '../../../data/smart_view/sv_columns.dart';
import 'smart_view_card.dart';
import 'sv_file_chips.dart';
import 'smart_view_status_pill.dart';

/// "Record details": one record read from the rows already in memory, never
/// from the device's storage. Title and status, then every visible field in
/// the card's key/value layout with nothing folded. Read only.
class SvRecordSheet {
  SvRecordSheet._();

  static Future<void> show(
    BuildContext context,
    SvCardData data, {
    SvFileOpener? onOpenFiles,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.sheetBackdrop,
      elevation: 0,
      sheetAnimationStyle: AnimationStyle(
        duration: AppDurations.slow,
        reverseDuration: AppDurations.base,
        curve: AppCurves.sheet,
        reverseCurve: AppCurves.out,
      ),
      builder: (sheet) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(sheet).pop(),
            ),
          ),
          Positioned.fill(
            child: SvRecordSheetBody(data: data, onOpenFiles: onOpenFiles),
          ),
        ],
      ),
    );
  }
}

class SvRecordSheetBody extends StatelessWidget {
  const SvRecordSheetBody({super.key, required this.data, this.onOpenFiles});

  final SvCardData data;
  final SvFileOpener? onOpenFiles;

  @override
  Widget build(BuildContext context) {
    final pairs = SvPair.listOf(data);
    return DraggableScrollableSheet(
      initialChildSize: 0.95,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      snap: true,
      builder: (context, scroll) => DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.sheetTop,
        ),
        child: CustomScrollView(
          controller: scroll,
          slivers: [
            SliverToBoxAdapter(child: _Header(data: data)),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.sheetPaddingX,
                0,
                AppSpacing.sheetPaddingX,
                AppSpacing.md + MediaQuery.paddingOf(context).bottom,
              ),
              sliver: SliverList.separated(
                itemCount: pairs.length,
                separatorBuilder: (context, i) => const Divider(
                  height: 1,
                  thickness: 1,
                  color: AppSv.hairline,
                ),
                itemBuilder: (context, i) =>
                    SvPairRow(pair: pairs[i], onOpenFiles: onOpenFiles),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.data});

  final SvCardData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sheetPaddingX,
        AppSpacing.sheetPaddingTop,
        AppSpacing.sheetPaddingX,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: AppSpacing.handleWidth,
              height: AppSpacing.handleHeight,
              decoration: const BoxDecoration(
                color: AppColors.sheetHandle,
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Record details', style: AppText.subtitle),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  data.title,
                  style: AppSv.cardTitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              SmartViewStatusPill(label: data.status, isCompact: true),
            ],
          ),
        ],
      ),
    );
  }
}
