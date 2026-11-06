import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

/// One row of an [AppPopupMenu]: an action row, or a switch row when
/// [switchValue] is set. A switch row toggles in place and keeps the menu
/// open; an action row closes it first.
class AppMenuItem {
  const AppMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.switchValue,
    this.isDanger = false,
    this.isEnabled = true,
    this.hasDividerBefore = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final RxBool? switchValue;
  final bool isDanger;
  final bool isEnabled;
  final bool hasDividerBefore;
}

/// A three-dot button that opens a floating card under it, aligned to the
/// right edge of the screen.
class AppPopupMenu extends StatelessWidget {
  const AppPopupMenu({
    super.key,
    required this.items,
    required this.tooltip,
    this.icon = Icons.more_horiz,
  });

  final List<AppMenuItem> items;
  final String tooltip;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(
        width: AppSpacing.badgedIconHit,
        height: AppSpacing.badgedIconHit,
      ),
      icon: Icon(icon, color: AppColors.ink),
      onPressed: () => AppPopupMenuCard.show(context, items),
    );
  }
}

/// The card itself, opened under the widget of [anchor].
class AppPopupMenuCard extends StatelessWidget {
  const AppPopupMenuCard({super.key, required this.items});

  final List<AppMenuItem> items;

  static Future<void> show(BuildContext anchor, List<AppMenuItem> items) {
    final box = anchor.findRenderObject()! as RenderBox;
    final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
    final isStill = MediaQuery.disableAnimationsOf(anchor);
    return showGeneralDialog<void>(
      context: anchor,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(anchor).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: isStill ? Duration.zero : AppDurations.reduced,
      pageBuilder: (context, _, _) {
        final media = MediaQuery.of(context);
        final width = math.min(
          AppSpacing.popupMenuMaxWidth,
          media.size.width - 2 * AppSpacing.popupMenuMargin,
        );
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 1,
              maxScaleFactor: 1.3,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: bottom,
                right: AppSpacing.popupMenuMargin,
                width: width,
                child: AppPopupMenuCard(items: items),
              ),
            ],
          ),
        );
      },
      transitionBuilder: (context, animation, _, child) {
        final t = CurvedAnimation(parent: animation, curve: AppCurves.out);
        return FadeTransition(
          opacity: t,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1).animate(t),
            alignment: Alignment.topRight,
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight =
        MediaQuery.sizeOf(context).height * AppSpacing.fixedSheetFraction;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg)),
        boxShadow: AppShadows.soft,
      ),
      child: Material(
        color: AppColors.background,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg)),
          side: BorderSide(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in items) ...[
                if (item.hasDividerBefore)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    indent: AppSpacing.md,
                    endIndent: AppSpacing.md,
                    color: AppColors.line,
                  ),
                _MenuRow(item: item),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item});

  final AppMenuItem item;

  void _onTap(BuildContext context) {
    if (item.switchValue == null) Navigator.of(context).pop();
    item.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final ink = !item.isEnabled
        ? AppColors.disabledInk
        : item.isDanger
        ? AppColors.error
        : AppColors.ink;
    final iconInk = !item.isEnabled
        ? AppColors.disabledInk
        : item.isDanger
        ? AppColors.error
        : AppColors.muted;
    final value = item.switchValue;
    return Semantics(
      container: true,
      button: value == null,
      toggled: value?.value,
      enabled: item.isEnabled,
      label: item.label,
      excludeSemantics: true,
      onTap: item.isEnabled ? () => _onTap(context) : null,
      child: InkWell(
        onTap: item.isEnabled ? () => _onTap(context) : null,
        highlightColor: AppColors.sage,
        splashColor: AppColors.sage,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.popupMenuRow),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                Icon(item.icon, size: AppSpacing.popupMenuIcon, color: iconInk),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    item.label,
                    style: AppText.body.copyWith(color: ink),
                  ),
                ),
                if (value != null)
                  Obx(
                    () => Switch(
                      value: value.value,
                      onChanged: item.isEnabled ? (_) => _onTap(context) : null,
                      activeThumbColor: AppColors.background,
                      activeTrackColor: AppColors.accent,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
