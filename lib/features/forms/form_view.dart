import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_skeleton.dart';
import '../../core/widgets/app_state_image.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/models/form_definition.dart';
import 'form_controller.dart';
import 'models/form_launch.dart';
import 'widgets/form_field_row.dart';
import 'widgets/form_grid_editor.dart';

/// A form, full height, rising over the chat: title and close at the top,
/// the fields in the middle, Done (or Save) pinned under them and above the
/// keyboard. The chat stays mounted underneath.
class FormView extends GetView<FormController> {
  const FormView({super.key, required this.launch});

  final FormLaunch launch;

  @override
  String? get tag => launch.tag;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    AppStateImage.precache(context, const [
      AppStateImageKind.error,
      AppStateImageKind.offline,
    ], size: AppSpacing.stateImageSmall);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close(context, c);
      },
      child: AppScaffold(
        isScrollable: false,
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        hasOuterBottomBar: true,
        body: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.background,
              borderRadius: AppRadius.sheetTop,
            ),
            child: ClipRRect(
              borderRadius: AppRadius.sheetTop,
              child: Column(
                children: [
                  _Header(launch: launch, onClose: () => _close(context, c)),
                  if (c.isEncryptedChat) const _EncryptionNote(),
                  Obx(() {
                    final text = c.banner.value;
                    return AnimatedSize(
                      duration: AppDurations.fast,
                      curve: AppCurves.out,
                      alignment: Alignment.topCenter,
                      child: text == null
                          ? const SizedBox(width: double.infinity)
                          : _Banner(text: text),
                    );
                  }),
                  Expanded(child: _Body(controller: c)),
                  _Footer(launch: launch, controller: c),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Closing with edits asks first; while a save is being written it waits.
  Future<void> _close(BuildContext context, FormController c) async {
    if (c.isSubmitting.value) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!c.isDirty) {
      Get.back<bool>(result: false);
      return;
    }
    await AppBottomSheet.show<void>(
      context,
      title: 'Discard changes?',
      child: _ConfirmDiscard(
        onDiscard: () {
          Navigator.of(context).pop();
          Get.back<bool>(result: false);
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.launch, required this.onClose});

  final FormLaunch launch;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.xs,
      AppSpacing.sm,
      AppSpacing.md,
      AppSpacing.xs,
    ),
    child: Row(
      children: [
        AppButton.icon(
          icon: Icons.close,
          semanticLabel: 'Cancel',
          onPressed: onClose,
        ),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            launch.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.title,
          ),
        ),
      ],
    ),
  );
}

class _EncryptionNote extends StatelessWidget {
  const _EncryptionNote();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(
      AppSpacing.sheetPaddingX,
      0,
      AppSpacing.sheetPaddingX,
      AppSpacing.xs,
    ),
    child: Row(
      children: [
        Icon(Icons.lock_open_outlined, size: 14, color: AppColors.muted),
        SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            "Forms in this chat aren't end-to-end encrypted",
            style: AppText.caption,
          ),
        ),
      ],
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(
      AppSpacing.sheetPaddingX,
      0,
      AppSpacing.sheetPaddingX,
      AppSpacing.xs,
    ),
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: AppColors.accentSoft,
      borderRadius: AppRadius.controlAll,
      border: Border.all(color: AppColors.peach),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, size: 16, color: AppColors.error),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(text, style: AppText.readable)),
      ],
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final FormController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(
      () => AppStateView(
        state: c.viewState.value,
        errorMessage: "We couldn't open this form.",
        onRetry: c.retry,
        loadingChild: const _Skeleton(),
        child: _Fields(controller: c),
      ),
    );
  }
}

class _Fields extends StatelessWidget {
  const _Fields({required this.controller});

  final FormController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final def = c.definition!;
    // Sections only watch values when one of them has a condition.
    if (!c.hasSectionConditions) return _list(c, def, c.visibleSections());
    return Obx(() => _list(c, def, c.visibleSections()));
  }

  Widget _list(FormController c, FormDefinition def, List<String> sections) {
    {
      return ListView(
        controller: c.scroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sheetPaddingX,
          AppSpacing.xxs,
          AppSpacing.sheetPaddingX,
          AppSpacing.lg,
        ),
        children: [
          for (final name in sections) ...[
            if (name.isNotEmpty &&
                (def.sectionOf(name)?.caption ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.xs,
                  bottom: AppSpacing.sm,
                ),
                child: Text(
                  def.sectionOf(name)!.caption.toUpperCase(),
                  style: AppText.eyebrow.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            if (c.grids[name] != null)
              FormGridEditor(controller: c, grid: c.grids[name]!)
            else
              for (final f in def.fieldsOf(name))
                if (c.fields[f.name] != null)
                  FormFieldRow(controller: c, input: c.fields[f.name]!),
          ],
        ],
      );
    }
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.launch, required this.controller});

  final FormLaunch launch;
  final FormController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sheetPaddingX,
        AppSpacing.sm,
        AppSpacing.sheetPaddingX,
        AppSpacing.sheetPaddingBottom -
            AppSpacing.xs +
            MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Obx(() {
        final isReady = c.viewState.value == AppViewState.content;
        return AppButton.primary(
          label: launch.buttonLabel,
          isCentered: true,
          isLoading: c.isSubmitting.value,
          onPressed: isReady && !c.hasBlockingField.value ? c.done : null,
        );
      }),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => AppSkeletonScope(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.sheetPaddingX),
      child: Column(
        children: [
          for (var i = 0; i < 5; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSkeleton(width: 90, height: AppSpacing.sm),
                  SizedBox(height: AppSpacing.xs),
                  AppSkeleton(height: AppSpacing.controlHeight),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class _ConfirmDiscard extends StatelessWidget {
  const _ConfirmDiscard({required this.onDiscard});

  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('What you filled in will be lost.', style: AppText.readable),
      const SizedBox(height: AppSpacing.lg),
      AppButton.primary(
        label: 'Discard',
        isCentered: true,
        onPressed: onDiscard,
      ),
      const SizedBox(height: AppSpacing.xs),
      AppButton.secondary(
        label: 'Keep editing',
        onPressed: () => Navigator.of(context).pop(),
      ),
    ],
  );
}
