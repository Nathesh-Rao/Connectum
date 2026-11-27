import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/log/log.dart';
import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import '../inbox_controller.dart';
import '../inbox_views_controller.dart';
import '../models/inbox_saved_view.dart';
import 'inbox_view_dialogs.dart';

/// The Views panel (`HashInboxModal.jsx` saved views), a bottom panel: the
/// Default View first, then the named ones in one card with the open one
/// ticked and the default starred, and the actions on the open view as tiles. Works offline on the last known list; saving needs a connection.
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
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppInbox.cardFill,
              borderRadius: BorderRadius.circular(AppInbox.cardRadius),
              border: Border.all(color: AppInbox.cardBorder),
            ),
            child: Column(
              children: [
                for (var i = 0; i < names.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: AppColors.line),
                  _ViewRow(
                    name: names[i],
                    isOpen: names[i] == open,
                    isDefault:
                        names[i] != InboxViewLimits.defaultName &&
                        names[i] == defaultName,
                    onTap: () => _open(context, names[i]),
                  ),
                ],
              ],
            ),
          ),
          if (v.problem.value.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            _Note(text: v.problem.value, isError: true),
          ],
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, box) {
              final w = (box.maxWidth - AppSpacing.xs) / 2;
              return Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  _Action(
                    width: w,
                    icon: Icons.save_outlined,
                    label: 'Save view',
                    onTap: canWrite ? () => _save(context) : null,
                  ),
                  _Action(
                    width: w,
                    icon: Icons.save_as_outlined,
                    label: 'Save as new view',
                    onTap: canWrite ? () => _saveAsNew(context) : null,
                  ),
                  _Action(
                    width: w,
                    icon: Icons.add_rounded,
                    label: 'Create view',
                    onTap: canWrite ? () => _create(context) : null,
                  ),
                  if (isNamed)
                    _Action(
                      width: w,
                      icon: v.isOpenDefault
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      label: v.isOpenDefault
                          ? 'Clear default'
                          : 'Set as default',
                      onTap: canWrite && v.saved(open) != null
                          ? _toggleDefault
                          : null,
                    ),
                  if (isNamed)
                    _Action(
                      width: w,
                      icon: Icons.delete_outline_rounded,
                      label: 'Remove view',
                      isDanger: true,
                      onTap: canWrite ? () => _remove(context) : null,
                    ),
                ],
              );
            },
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
      borderRadius: BorderRadius.circular(AppInbox.cardRadius),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              AnimatedContainer(
                duration: AppDurations.fast,
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOpen ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                    color: isOpen ? AppColors.primary : AppColors.inputBorder,
                    width: 1.5,
                  ),
                ),
                child: isOpen
                    ? const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: AppColors.white,
                      )
                    : null,
              ),
              const SizedBox(width: AppSpacing.sm),
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
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpacing.xs,
                  ),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: AppColors.violetTint,
                      borderRadius: AppRadius.pillAll,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.xxs / 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 12,
                            color: AppColors.violetStrong,
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          Text(
                            'Default',
                            style: AppText.caption.copyWith(
                              color: AppColors.violetStrong,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// An action of the open view: a tonal tile with its icon in a disc, two to
/// a row.
class _Action extends StatelessWidget {
  const _Action({
    required this.width,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDanger = false,
  });

  final double width;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final isOn = onTap != null;
    final ink = !isOn
        ? AppColors.disabledInk
        : isDanger
        ? AppColors.error
        : AppColors.ink;
    final disc = !isOn
        ? AppColors.fill
        : isDanger
        ? AppColors.noFill
        : AppInbox.discFill;
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        enabled: isOn,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: AppInbox.cardFill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: const BorderSide(color: AppInbox.cardBorder),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: disc,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: Icon(
                          icon,
                          size: 18,
                          color: isOn && !isDanger ? AppInbox.discInk : ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        label,
                        style: AppText.readableStrong.copyWith(color: ink),
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
