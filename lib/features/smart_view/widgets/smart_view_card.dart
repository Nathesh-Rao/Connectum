import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import '../../../data/smart_view/sv_columns.dart';
import '../../../data/smart_view/sv_file.dart';
import 'sv_col_icon.dart';
import 'sv_file_chips.dart';
import 'smart_view_status_pill.dart';

/// One record as a read-only card: a header (its position in the list, the
/// title, the record status) on a soft wash, then every field as a row split
/// 50/50, icon and name left, value right (No., By, Submitted, the status
/// field, then the structure's own fields). Up to [maxFields] show; more are
/// behind a "Show all (N)" row that grows the card. No buttons, no progress,
/// no menu.
class SmartViewCard extends StatelessWidget {
  const SmartViewCard({
    super.key,
    required this.data,
    required this.isExpanded,
    required this.onToggle,
    this.position = 1,
    this.onTap,
    this.version = 0,
    this.onOpenFiles,
    this.isFilesExpanded = false,
    this.onToggleFiles,
  });

  static const maxFields = 6;

  final SvCardData data;
  final bool isExpanded;
  final VoidCallback onToggle;

  /// 1-based place of the record in the list as shown (filtered and sorted).
  final int position;
  final VoidCallback? onTap;
  final int version;
  final SvFileOpener? onOpenFiles;
  final bool isFilesExpanded;
  final VoidCallback? onToggleFiles;

  @override
  Widget build(BuildContext context) {
    final pairs = SvPair.listOf(data);
    final hasMore = pairs.length > maxFields;
    final shown = hasMore && !isExpanded
        ? pairs.take(maxFields).toList()
        : pairs;
    final radius = BorderRadius.circular(AppSv.cardRadius);
    final card = RepaintBoundary(
      child: Semantics(
        container: true,
        label: 'Record ${data.number}, ${data.title}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: radius,
              border: Border.all(color: AppSv.cardBorder),
              boxShadow: AppSv.cardShadow,
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                children: [
                  const Positioned.fill(child: CardTopRightDecoration()),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(data: data, position: position),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSv.cardPad,
                        ),
                        child: AppAnimatedSize(
                          duration: AppDurations.sheetResize,
                          curve: AppCurves.out,
                          alignment: Alignment.topCenter,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = 0; i < shown.length; i++) ...[
                                if (i > 0)
                                  const Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: AppSv.hairline,
                                  ),
                                SvPairRow(
                                  pair: shown[i],
                                  onOpenFiles: onOpenFiles,
                                  isFilesExpanded: isFilesExpanded,
                                  onToggleFiles: onToggleFiles,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (hasMore)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSv.cardPad,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: onToggle,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.xs,
                                ),
                                child: Text(
                                  isExpanded
                                      ? 'Show less'
                                      : 'Show all (${pairs.length})',
                                  style: AppSv.showAll,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        const SizedBox(height: AppSpacing.xs),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (version == 0) return card;
    return TweenAnimationBuilder<double>(
      key: ValueKey('fade-${data.number}-$version'),
      tween: Tween(begin: 0, end: 1),
      duration: AppDurations.reduced,
      curve: AppCurves.out,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: card,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.data, required this.position});

  final SvCardData data;
  final int position;

  @override
  Widget build(BuildContext context) {
    final text = '$position';
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSv.headerHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSv.cardPad,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            Container(
              key: const ValueKey('sv-card-position'),
              width: AppSv.numberCircle,
              height: AppSv.numberCircle,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppSv.numberFill,
                shape: BoxShape.circle,
              ),
              child: Text(
                text,
                style: text.length >= 3
                    ? AppSv.numberTextSmall
                    : AppSv.numberText,
                maxLines: 1,
                softWrap: false,
              ),
            ),
            const SizedBox(width: AppSv.numberGap),
            Expanded(
              child: Text(
                data.title,
                style: AppSv.cardTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppSv.headerPillMax),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SmartViewStatusPill(label: data.status, isCompact: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SvPair {
  const SvPair(
    this.label,
    this.value, {
    required this.icon,
    this.isStatus = false,
    this.type,
    this.typed,
    this.files = const [],
  });

  final String label;
  final String value;
  final IconData icon;
  final bool isStatus;
  final SvColType? type;
  final Object? typed;
  final List<SvFile> files;

  /// Every line a record shows: No., By, Submitted, the status field, then
  /// the structure's own visible fields.
  static List<SvPair> listOf(SvCardData data) => [
    SvPair('No.', data.number, icon: Icons.tag),
    SvPair('By', data.by, icon: Icons.person_outline),
    SvPair('Submitted', data.submitted, icon: Icons.calendar_today_outlined),
    if (data.ticketStatus.isNotEmpty)
      SvPair(
        data.ticketLabel,
        data.ticketStatus,
        icon: Icons.layers_outlined,
        isStatus: true,
      ),
    for (final f in data.fields)
      SvPair(
        f.column.label,
        f.cell.text,
        icon: SvColIcon.of(f.column.type),
        type: f.column.type,
        typed: f.cell.typed,
        files: f.cell.files,
      ),
  ];

  bool get isEmpty => value == SmartViewColumns.empty || value.isEmpty;
}

class SvPairRow extends StatelessWidget {
  const SvPairRow({
    super.key,
    required this.pair,
    this.onOpenFiles,
    this.isFilesExpanded = false,
    this.onToggleFiles,
  });

  final SvPair pair;
  final SvFileOpener? onOpenFiles;
  final bool isFilesExpanded;

  /// Null shows every file (the record details).
  final VoidCallback? onToggleFiles;

  @override
  Widget build(BuildContext context) {
    final keyLine = MediaQuery.textScalerOf(
      context,
    ).scale(AppSv.fieldKey.fontSize! * AppSv.fieldKey.height!);
    return Container(
      constraints: const BoxConstraints(minHeight: AppSv.rowMin),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(vertical: AppSv.rowPadY),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: keyLine,
                  child: Center(
                    child: Icon(
                      pair.icon,
                      size: AppSv.rowIcon,
                      color: AppColors.cardMuted,
                    ),
                  ),
                ),
                const SizedBox(width: AppSv.rowIconGap),
                Expanded(child: Text(pair.label, style: AppSv.fieldKey)),
              ],
            ),
          ),
          Expanded(
            child: _Value(
              pair: pair,
              onOpenFiles: onOpenFiles,
              isFilesExpanded: isFilesExpanded,
              onToggleFiles: onToggleFiles,
            ),
          ),
        ],
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value({
    required this.pair,
    this.onOpenFiles,
    required this.isFilesExpanded,
    this.onToggleFiles,
  });

  final SvPair pair;
  final SvFileOpener? onOpenFiles;
  final bool isFilesExpanded;
  final VoidCallback? onToggleFiles;

  @override
  Widget build(BuildContext context) {
    if (pair.isEmpty) {
      return Semantics(
        label: 'empty',
        child: const Text(SmartViewColumns.empty, style: AppSv.fieldValueEmpty),
      );
    }
    final type = pair.type;
    if (type == SvColType.file && pair.files.isNotEmpty) {
      return SvFileChips(
        files: pair.files,
        onOpen: onOpenFiles,
        isExpanded: isFilesExpanded,
        onToggle: onToggleFiles,
      );
    }
    final isPill =
        pair.isStatus || type == SvColType.status || type == SvColType.select;
    if (isPill) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SmartViewStatusPill(label: pair.value, isCompact: true),
        ),
      );
    }
    if (type == SvColType.checkbox) {
      return Align(
        alignment: Alignment.centerLeft,
        child: _YesNo(isYes: pair.value.toLowerCase() == 'yes'),
      );
    }
    return Text(pair.value, style: AppSv.fieldValue);
  }
}

class _YesNo extends StatelessWidget {
  const _YesNo({required this.isYes});

  final bool isYes;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSpacing.statusPillHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isYes ? AppColors.yesFill : AppColors.noFill,
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        isYes ? 'Yes' : 'No',
        style: AppText.readableStrong.copyWith(
          color: isYes ? AppColors.yesText : AppColors.noText,
        ),
      ),
    );
  }
}
