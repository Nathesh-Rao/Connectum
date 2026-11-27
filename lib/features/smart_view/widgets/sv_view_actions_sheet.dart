import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/widgets/widgets.dart';
import '../smart_view_controller.dart';
import 'sv_columns_sheet.dart';
import 'sv_confirm_sheet.dart';
import 'sv_group_by_sheet.dart';
import 'sv_manage_view_sheet.dart';
import 'sv_save_view_sheet.dart';

/// The ⋮ menu of the open view, the web's options menu on a phone: Save,
/// Save as new view, Create view, Remove view, Columns, Group.
class SvViewActionsSheet {
  SvViewActionsSheet._();

  static Future<void> show(BuildContext context, SmartViewController c) {
    return AppBottomSheet.show<void>(
      context,
      title: 'View',
      child: Builder(
        builder: (sheet) {
          void close() => Navigator.of(sheet).pop();
          return Obx(() {
            final selected = c.selectedViewId.value;
            final view = c.viewById(selected);
            final canWrite = c.canManage;
            final isOwn = view != null && !c.isSharedSelected;
            final groups = c.groupBy.length;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvActionRow(
                  icon: Icons.save_outlined,
                  label: 'Save',
                  hint: selected == null
                      ? 'The Default View is not saved'
                      : !c.isDirty
                      ? 'Nothing changed'
                      : null,
                  isEnabled: c.canSave,
                  onTap: () {
                    close();
                    c.saveCurrent();
                  },
                ),
                SvActionRow(
                  icon: Icons.library_add_outlined,
                  label: 'Save as new view',
                  isEnabled: canWrite,
                  onTap: () {
                    close();
                    SvSaveViewSheet.show(context, c);
                  },
                ),
                SvActionRow(
                  icon: Icons.add_box_outlined,
                  label: 'Create view',
                  hint: 'Starts from what is on screen',
                  isEnabled: canWrite,
                  onTap: () {
                    close();
                    SvSaveViewSheet.show(context, c);
                  },
                ),
                SvActionRow(
                  icon: Icons.delete_outline,
                  label: 'Remove view',
                  isDanger: true,
                  isEnabled: canWrite && isOwn,
                  onTap: () async {
                    close();
                    final v = view;
                    if (v == null) return;
                    final yes = await SvConfirmSheet.ask(
                      context,
                      title: 'Remove the view "${v.name}"?',
                      message:
                          'Its filters, grouping and columns are forgotten. '
                          'The data is not touched.',
                      confirm: 'Remove view',
                      cancel: 'Keep it',
                      isDanger: true,
                    );
                    if (yes) await c.deleteView(v.id);
                  },
                ),
                SvActionRow(
                  icon: Icons.view_column_outlined,
                  label: 'Columns',
                  onTap: () {
                    close();
                    SvColumnsSheet.show(context, c);
                  },
                ),
                SvActionRow(
                  icon: Icons.account_tree_outlined,
                  label: groups == 0 ? 'Group' : 'Group ($groups)',
                  onTap: () {
                    close();
                    SvGroupBySheet.show(context, c);
                  },
                ),
              ],
            );
          });
        },
      ),
    );
  }
}
