import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import '../../../data/smart_view/sv_saved_view.dart';
import '../smart_view_controller.dart';
import 'sv_confirm_sheet.dart';
import 'sv_save_view_sheet.dart';

/// A tab's own menu (long press): Rename, Duplicate, Delete. The Default
/// View has none.
class SvManageViewSheet {
  SvManageViewSheet._();

  static Future<void> show(
    BuildContext context,
    SmartViewController c,
    SvSavedView view,
  ) {
    return AppBottomSheet.show<void>(
      context,
      title: view.name,
      child: Builder(
        builder: (sheet) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvActionRow(
              icon: Icons.edit_outlined,
              label: 'Rename',
              onTap: () {
                Navigator.of(sheet).pop();
                SvSaveViewSheet.show(
                  context,
                  c,
                  renameId: view.id,
                  initial: view.name,
                );
              },
            ),
            SvActionRow(
              icon: Icons.copy_outlined,
              label: 'Duplicate',
              onTap: () {
                Navigator.of(sheet).pop();
                c.duplicateView(view.id);
              },
            ),
            SvActionRow(
              icon: Icons.delete_outline,
              label: 'Delete',
              isDanger: true,
              onTap: () async {
                Navigator.of(sheet).pop();
                final yes = await SvConfirmSheet.ask(
                  context,
                  title: 'Remove the view "${view.name}"?',
                  message:
                      'Its filters, grouping and columns are forgotten. '
                      'The data is not touched.',
                  confirm: 'Remove view',
                  cancel: 'Keep it',
                  isDanger: true,
                );
                if (yes) await c.deleteView(view.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of a view sheet: an icon circle and a label.
class SvActionRow extends StatelessWidget {
  const SvActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isEnabled = true,
    this.isDanger = false,
    this.hint,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isEnabled;
  final bool isDanger;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final color = !isEnabled
        ? AppColors.tertiary
        : isDanger
        ? AppColors.error
        : AppColors.ink;
    return Semantics(
      button: true,
      enabled: isEnabled,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isEnabled ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSv.sheetRowHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              Container(
                width: AppSv.sheetIconCircle,
                height: AppSv.sheetIconCircle,
                decoration: const BoxDecoration(
                  color: AppSv.sortIconFill,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: AppSpacing.popupMenuIcon,
                  color: isEnabled ? AppColors.muted : AppColors.tertiary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppText.body.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    if (hint != null)
                      Text(
                        hint!,
                        style: AppText.caption.copyWith(
                          color: AppColors.tertiary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
