import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/log/safe.dart';
import '../inbox_controller.dart';
import '../inbox_views_controller.dart';
import '../models/inbox_saved_view.dart';
import 'inbox_view_dialogs.dart';

/// The Views sheet (`HashInboxModal.jsx` saved views): the Default View first,
/// then the named ones with the open one marked, and the actions on the open
/// view. Works offline on the last known list; saving needs a connection.
class InboxViewsSheet {
  InboxViewsSheet._();

  static Future<void> show(BuildContext context, InboxController inbox) {
    fireAndLog('inbox_views_sheet', inbox.refreshViews);
    return AppBottomSheet.show<void>(
      context,
      title: 'Views',
      child: InboxViewsPanel(controller: inbox),
    );
  }
}

/// The sheet's content. Public so a test can draw it without a sheet.
class InboxViewsPanel extends StatelessWidget {
  const InboxViewsPanel({super.key, required this.controller});

  final InboxController controller;

  InboxViews get _v => controller.views;

  void _close(BuildContext context) => Navigator.of(context).pop();

  Future<void> _open(BuildContext context, String name) async {
    final isOpen = await controller.openView(name);
    if (isOpen && context.mounted) _close(context);
  }

  Future<void> _save(BuildContext context) async {
    final problem = await controller.saveView();
    if (problem.isEmpty) {
      if (context.mounted) _close(context);
    } else {
      _v.problem.value = problem;
    }
  }

  Future<void> _saveAsNew(BuildContext context) async {
    final isDone = await InboxNameDialog.ask(
      context,
      title: 'Save as new view',
      confirmLabel: 'Save',
      onSubmit: controller.saveAsNew,
    );
    if (isDone && context.mounted) _close(context);
  }

  Future<void> _create(BuildContext context) async {
    if (!await controller.confirmLeave() || !context.mounted) return;
    final isDone = await InboxNameDialog.ask(
      context,
      title: 'Create view',
      confirmLabel: 'Create',
      onSubmit: controller.createView,
    );
    if (isDone && context.mounted) _close(context);
  }

  Future<void> _remove(BuildContext context) async {
    final name = _v.current.value;
    if (!await InboxRemoveDialog.ask(context, name) || !context.mounted) {
      return;
    }
    final problem = await controller.removeView();
    if (problem.isEmpty) {
      if (context.mounted) _close(context);
    } else {
      _v.problem.value = problem;
    }
  }

  Future<void> _toggleDefault() async {
    final problem = await controller.toggleDefault();
    if (problem.isNotEmpty) _v.problem.value = problem;
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    return Obx(() {
      final isOffline = v.isOffline;
      final canWrite = !isOffline && v.isReady && !v.isBusy.value;
      final isNamed = v.current.value.isNotEmpty;
      final open = v.openName;
      final names = v.names;
      final defaultName = v.defaultName;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isOffline)
            const _Note(text: InboxViews.offlineNote, isError: false),
          if (v.hasLoadError)
            _LoadError(
              onRetry: () =>
                  fireAndLog('inbox_views_sheet', controller.refreshViews),
            ),
          for (final name in names)
            _ViewRow(
              name: name,
              isOpen: name == open,
              isDefault:
                  name != InboxViewLimits.defaultName && name == defaultName,
              onTap: () => _open(context, name),
            ),
          if (v.problem.value.isNotEmpty)
            _Note(text: v.problem.value, isError: true),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1, color: AppColors.line),
          _Action(
            icon: Icons.save_outlined,
            label: 'Save view',
            onTap: canWrite ? () => _save(context) : null,
          ),
          _Action(
            icon: Icons.save_as_outlined,
            label: 'Save as new view',
            onTap: canWrite ? () => _saveAsNew(context) : null,
          ),
          _Action(
            icon: Icons.add,
            label: 'Create view',
            onTap: canWrite ? () => _create(context) : null,
          ),
          if (isNamed)
            _Action(
              icon: v.isOpenDefault ? Icons.star : Icons.star_border,
              label: v.isOpenDefault ? 'Clear default' : 'Set as default',
              onTap: canWrite && v.saved(open) != null ? _toggleDefault : null,
            ),
          if (isNamed)
            _Action(
              icon: Icons.delete_outline,
              label: 'Remove view',
              isDanger: true,
              onTap: canWrite ? () => _remove(context) : null,
            ),
        ],
      );
    });
  }
}

class _ViewRow extends StatelessWidget {
  const _ViewRow({
    required this.name,
    required this.isOpen,
    required this.isDefault,
    required this.onTap,
  });

  final String name;
  final bool isOpen;
  final bool isDefault;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: isOpen,
    label: isOpen ? '$name, open' : name,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: isOpen
                  ? const Icon(Icons.check, size: 18, color: AppColors.primary)
                  : null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Text(
                  name,
                  style: isOpen ? AppText.bodyStrong : AppText.body,
                ),
              ),
            ),
            if (isDefault)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: AppSpacing.xs),
                child: Text('Default', style: AppText.caption),
              ),
          ],
        ),
      ),
    ),
  );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDanger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null
        ? AppColors.muted
        : isDanger
        ? AppColors.error
        : AppColors.ink;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          child: Row(
            children: [
              SizedBox(width: 28, child: Icon(icon, size: 20, color: color)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Text(
                    label,
                    style: AppText.body.copyWith(color: color),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Text(
      text,
      style: AppText.readable.copyWith(
        color: isError ? AppColors.error : AppColors.muted,
      ),
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      children: [
        Text(
          InboxViews.loadError,
          style: AppText.readable.copyWith(color: AppColors.error),
        ),
        AppButton.text(label: 'Retry', onPressed: onRetry),
      ],
    ),
  );
}
