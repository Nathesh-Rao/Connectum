import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../inbox_controller.dart';
import '../inbox_views_controller.dart';
import '../models/inbox_saved_view.dart';

/// The shape of every dialog of the saved views: a title, the words, then
/// the buttons one under the other (they never overflow, whatever the width
/// or the text size).
class _InboxDialog extends StatelessWidget {
  const _InboxDialog({
    required this.title,
    required this.children,
    this.message,
  });

  final String title;
  final String? message;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: AppColors.white,
    surfaceTintColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(AppSpacing.lg),
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppText.title),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(message!, style: AppText.body),
          ],
          const SizedBox(height: AppSpacing.lg),
          ...children,
        ],
      ),
    ),
  );
}

/// "Save your changes?": Save, Discard, Cancel.
class InboxUnsavedDialog extends StatelessWidget {
  const InboxUnsavedDialog({super.key});

  static const title = 'Save your changes?';
  static const message = 'This view has changes that are not saved.';

  static Future<UnsavedChoice?> ask(BuildContext context) =>
      showDialog<UnsavedChoice>(
        context: context,
        barrierColor: AppColors.sheetBackdrop,
        builder: (_) => const InboxUnsavedDialog(),
      );

  @override
  Widget build(BuildContext context) => _InboxDialog(
    title: title,
    message: message,
    children: [
      AppButton.primary(
        label: 'Save',
        isCentered: true,
        onPressed: () => Navigator.of(context).pop(UnsavedChoice.save),
      ),
      const SizedBox(height: AppSpacing.xs),
      AppButton.secondary(
        label: 'Discard',
        isDanger: true,
        onPressed: () => Navigator.of(context).pop(UnsavedChoice.discard),
      ),
      const SizedBox(height: AppSpacing.xs),
      AppButton.text(
        label: 'Cancel',
        tone: AppTextButtonTone.ink,
        onPressed: () => Navigator.of(context).pop(UnsavedChoice.cancel),
      ),
    ],
  );
}

/// "Remove the view ...?": true to remove it.
class InboxRemoveDialog extends StatelessWidget {
  const InboxRemoveDialog({super.key, required this.name});

  final String name;

  static Future<bool> ask(BuildContext context, String name) async =>
      await showDialog<bool>(
        context: context,
        barrierColor: AppColors.sheetBackdrop,
        builder: (_) => InboxRemoveDialog(name: name),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => _InboxDialog(
    title: 'Remove the view "$name"?',
    message: 'Its filters are forgotten. The records are not touched.',
    children: [
      AppButton.secondary(
        label: 'Remove view',
        isDanger: true,
        onPressed: () => Navigator.of(context).pop(true),
      ),
      const SizedBox(height: AppSpacing.xs),
      AppButton.text(
        label: 'Cancel',
        tone: AppTextButtonTone.ink,
        onPressed: () => Navigator.of(context).pop(false),
      ),
    ],
  );
}

/// A name for a view. [onSubmit] gets the name and answers '' when it
/// worked, else the words to show under the field (the dialog stays open).
/// True when it worked.
class InboxNameDialog extends StatefulWidget {
  const InboxNameDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    required this.onSubmit,
  });

  final String title;
  final String confirmLabel;
  final Future<String> Function(String name) onSubmit;

  static Future<bool> ask(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    required Future<String> Function(String name) onSubmit,
  }) async =>
      await showDialog<bool>(
        context: context,
        barrierColor: AppColors.sheetBackdrop,
        builder: (_) => InboxNameDialog(
          title: title,
          confirmLabel: confirmLabel,
          onSubmit: onSubmit,
        ),
      ) ??
      false;

  @override
  State<InboxNameDialog> createState() => _InboxNameDialogState();
}

class _InboxNameDialogState extends State<InboxNameDialog> {
  final _name = TextEditingController();
  final _error = ''.obs;
  final _isBusy = false.obs;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isBusy.value) return;
    _isBusy.value = true;
    final problem = await widget.onSubmit(_name.text);
    _isBusy.value = false;
    if (!mounted) return;
    if (problem.isEmpty) {
      Navigator.of(context).pop(true);
    } else {
      _error.value = problem;
    }
  }

  @override
  Widget build(BuildContext context) => _InboxDialog(
    title: widget.title,
    children: [
      Obx(
        () => AppTextField(
          controller: _name,
          label: 'Name',
          hint: 'View name',
          errorText: _error.value.isEmpty ? null : _error.value,
          maxLength: InboxViewLimits.maxName,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          enabled: !_isBusy.value,
          onChanged: (_) => _error.value = '',
          onSubmitted: (_) => _submit(),
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      Obx(
        () => AppButton.primary(
          label: widget.confirmLabel,
          isCentered: true,
          isLoading: _isBusy.value,
          onPressed: _isBusy.value ? null : _submit,
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      AppButton.text(
        label: 'Cancel',
        tone: AppTextButtonTone.ink,
        onPressed: () => Navigator.of(context).pop(false),
      ),
    ],
  );
}

/// Shows "Save your changes?" whenever the controller asks for it, and hands
/// the answer back. Wraps the Inbox screen.
class InboxPromptHost extends StatefulWidget {
  const InboxPromptHost({
    super.key,
    required this.controller,
    required this.child,
  });

  final InboxController controller;
  final Widget child;

  @override
  State<InboxPromptHost> createState() => _InboxPromptHostState();
}

class _InboxPromptHostState extends State<InboxPromptHost> {
  Worker? _worker;

  @override
  void initState() {
    super.initState();
    _worker = ever(widget.controller.unsavedPrompt, (prompt) {
      if (prompt != null) _ask(prompt);
    });
  }

  Future<void> _ask(UnsavedPrompt prompt) async {
    if (!mounted) return;
    final choice = await InboxUnsavedDialog.ask(context);
    prompt.reply(choice ?? UnsavedChoice.cancel);
  }

  @override
  void dispose() {
    _worker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
