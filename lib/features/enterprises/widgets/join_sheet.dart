import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/app_text_field.dart';
import '../enterprises_controller.dart';

class JoinSheet extends StatelessWidget {
  const JoinSheet({super.key, required this.controller});

  final EnterprisesController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final outcome = c.joinOutcome.value;
      if (outcome != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(outcome, style: AppText.body),
            const SizedBox(height: AppSpacing.lg),
            AppButton.primary(
              label: 'Done',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      }
      final hit = c.selected.value;
      if (hit != null) return _Categories(controller: c, name: hit.name);
      return _Search(controller: c);
    });
  }
}

class _Search extends StatelessWidget {
  const _Search({required this.controller});

  final EnterprisesController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Search by enterprise name or Connectum ID.',
          style: AppText.readable,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          controller: c.joinQuery,
          hint: 'Enterprise name or ID',
          onChanged: c.onJoinQueryChanged,
        ),
        const SizedBox(height: AppSpacing.sm),
        Obx(() {
          if (c.isJoinBusy.value) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(child: Text('Searching…', style: AppText.readable)),
            );
          }
          final error = c.joinMessage.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null) Text(error, style: AppText.readable),
              for (final r in c.results) ...[
                const SizedBox(height: AppSpacing.xs),
                AppListRow(
                  title: r.name,
                  subtitle: r.city.isEmpty ? r.id : '${r.city} · ${r.id}',
                  trailing: const Icon(Icons.arrow_forward, size: 18),
                  onTap: () => c.selectEnterprise(r),
                ),
              ],
            ],
          );
        }),
      ],
    );
  }
}

class _Categories extends StatelessWidget {
  const _Categories({required this.controller, required this.name});

  final EnterprisesController controller;
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(name, style: AppText.subtitle),
        const SizedBox(height: AppSpacing.xs),
        const Text('Join as', style: AppText.readable),
        const SizedBox(height: AppSpacing.sm),
        for (final category in c.categories) ...[
          AppListRow(
            title: category,
            trailing: c.isJoinBusy.value
                ? null
                : const Icon(Icons.arrow_forward, size: 18),
            onTap: () => c.join(category),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        Obx(() {
          final error = c.joinMessage.value;
          return error == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(error, style: AppText.readable),
                );
        }),
      ],
    );
  }
}
