import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_loading.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../data/models/connect_card.dart';
import '../connect_controller.dart';
import '../models/join_flow.dart';

/// The join steps of the web's JoinWizard: Associate card, category, optional
/// affiliate, review.
class JoinSteps extends StatelessWidget {
  const JoinSteps({super.key, required this.card, required this.controller});

  final ConnectCard card;
  final ConnectController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final flow = c.joinFlow.value;
      if (flow == null) {
        if (c.isLoadingPage.value) return const _Loading();
        return _PageError(controller: c);
      }
      if (!flow.isOpen) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "This enterprise isn't open for joining from the app yet.",
              style: AppText.body,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton.text(label: 'Cancel', onPressed: c.backToEntry),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Step ${flow.index + 1} of ${flow.total}: ${flow.title}',
            style: AppText.readableStrong,
          ),
          const SizedBox(height: AppSpacing.sm),
          KeyedSubtree(
            key: ValueKey(flow.step),
            child: switch (flow.step) {
              JoinStep.type => _TypeStep(card: card, controller: c),
              JoinStep.category => _CategoryStep(controller: c, flow: flow),
              JoinStep.affiliate => _AffiliateStep(controller: c, flow: flow),
              JoinStep.review => _ReviewStep(card: card, flow: flow),
            },
          ),
          Obx(() {
            final error = c.joinMessage.value;
            return error == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(error, style: AppText.error),
                  );
          }),
          const SizedBox(height: AppSpacing.lg),
          if (flow.step == JoinStep.review)
            Obx(
              () => AppButton.primary(
                label: 'Join ${card.name}',
                isCentered: true,
                isLoading: c.isJoining.value,
                onPressed: c.join,
              ),
            )
          else if (flow.step != JoinStep.type)
            Obx(
              () => AppButton.primary(
                label: 'Next',
                isCentered: true,
                isLoading: c.isJoining.value,
                onPressed: c.nextStep,
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.text(
            label: flow.isFirst ? 'Cancel' : 'Back',
            onPressed: c.backStep,
          ),
        ],
      );
    });
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
    child: Column(
      children: [
        AppLoading(),
        SizedBox(height: AppSpacing.sm),
        Text('Loading…', style: AppText.readable),
      ],
    ),
  );
}

class _PageError extends StatelessWidget {
  const _PageError({required this.controller});

  final ConnectController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Obx(
          () => Text(
            c.pageMessage.value ?? 'Something went wrong. Please try again.',
            style: AppText.error,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton.primary(
          label: 'Try again',
          isCentered: true,
          onPressed: c.loadJoinPage,
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton.text(label: 'Cancel', onPressed: c.backToEntry),
      ],
    );
  }
}

class _TypeStep extends StatelessWidget {
  const _TypeStep({required this.card, required this.controller});

  final ConnectCard card;
  final ConnectController controller;

  @override
  Widget build(BuildContext context) {
    final categories = controller.joinFlow.value?.page.categories ?? const [];
    final shown = categories.take(4).join(', ');
    final more = categories.length > 4 ? ' …' : '';
    final text =
        'A customer, vendor, partner or other outside person'
        '${categories.isEmpty ? '' : ': $shown$more'}.';
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: controller.chooseAssociate,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: AppColors.inputBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.person_outline,
                size: 22,
                color: AppColors.primaryStrong,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("I'm an associate", style: AppText.bodyStrong),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(text, style: AppText.readable),
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

class _CategoryStep extends StatelessWidget {
  const _CategoryStep({required this.controller, required this.flow});

  final ConnectController controller;
  final JoinFlow flow;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChoiceList(
          label: 'Category',
          options: flow.page.categories,
          selected: flow.category,
          onPick: c.pickCategory,
          searchHint: 'Search ${flow.page.categories.length} options',
        ),
        _FieldError(controller: c, field: 'category'),
      ],
    );
  }
}

class _AffiliateStep extends StatelessWidget {
  const _AffiliateStep({required this.controller, required this.flow});

  final ConnectController controller;
  final JoinFlow flow;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChoiceList(
          label: 'Are you from one of our partner organisations?',
          options: [for (final a in flow.page.affiliates) a.name],
          selected: flow.affiliate,
          onPick: c.pickAffiliate,
          searchHint: 'Search partner organisations',
          alwaysSearch: true,
          noneLabel: flow.hasCategories ? JoinFlow.individual : null,
          onNone: c.pickNoAffiliate,
        ),
        _FieldError(controller: c, field: 'affiliate'),
        if (flow.affiliate.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          if (flow.needsBranch) ...[
            _ChoiceList(
              label: 'Branch',
              options: flow.branches,
              selected: flow.affiliateBranch,
              onPick: c.pickBranch,
              searchHint: 'Search branches',
            ),
            _FieldError(controller: c, field: 'affiliateBranch'),
          ] else
            Text(
              'Branch: NA (this affiliate has '
              '${flow.branches.isEmpty ? 'no branches' : 'one branch'}).',
              style: AppText.readable,
            ),
        ],
      ],
    );
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({required this.card, required this.flow});

  final ConnectCard card;
  final JoinFlow flow;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Enterprise', card.name),
      ('You are', 'Associate'),
      if (flow.category.isNotEmpty) ('Category', flow.category),
      (
        'Affiliate',
        flow.affiliate.isEmpty ? 'None (an individual)' : flow.affiliate,
      ),
      if (flow.affiliate.isNotEmpty)
        ('Branch', flow.needsBranch ? flow.affiliateBranch : 'NA'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              border: i == 0
                  ? null
                  : const Border(top: BorderSide(color: AppColors.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rows[i].$1, style: AppText.readable),
                Text(rows[i].$2, style: AppText.bodyStrong),
              ],
            ),
          ),
      ],
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError({required this.controller, required this.field});

  final ConnectController controller;
  final String field;

  @override
  Widget build(BuildContext context) => Obx(() {
    final text = controller.fieldErrors[field];
    return text == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(text, style: AppText.error),
          );
  });
}

/// A list of rows to pick from, with a search box when it is long (or always
/// for [alwaysSearch]) and an optional first "none" row that is not filtered.
class _ChoiceList extends StatefulWidget {
  const _ChoiceList({
    required this.label,
    required this.options,
    required this.selected,
    required this.onPick,
    required this.searchHint,
    this.alwaysSearch = false,
    this.noneLabel,
    this.onNone,
  });

  final String label;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onPick;
  final String searchHint;
  final bool alwaysSearch;
  final String? noneLabel;
  final VoidCallback? onNone;

  @override
  State<_ChoiceList> createState() => _ChoiceListState();
}

class _ChoiceListState extends State<_ChoiceList> {
  static const _searchFrom = 6;
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final hasSearch = w.alwaysSearch || w.options.length > _searchFrom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(w.label, style: AppText.readableStrong),
        const SizedBox(height: AppSpacing.xs),
        if (hasSearch) ...[
          AppSearchField(
            hint: w.searchHint,
            controller: _query,
            onChanged: (_) {},
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: AppSpacing.joinListMaxHeight),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _query,
            builder: (context, value, _) {
              final q = value.text.trim().toLowerCase();
              final rows = [
                for (final o in w.options)
                  if (o.toLowerCase().contains(q)) o,
              ];
              return ListView(
                shrinkWrap: true,
                children: [
                  if (w.noneLabel != null)
                    _ChoiceRow(
                      label: w.noneLabel!,
                      isSelected: w.selected.isEmpty,
                      onTap: w.onNone ?? () {},
                    ),
                  for (final o in rows)
                    _ChoiceRow(
                      label: o,
                      isSelected: w.selected == o,
                      onTap: () => w.onPick(o),
                    ),
                  if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Text(
                        'Nothing matches “${value.text.trim()}”.',
                        style: AppText.readable,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: isSelected,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        curve: AppCurves.out,
        margin: const EdgeInsets.only(bottom: AppSpacing.xxs),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryTint : AppColors.white,
          borderRadius: AppRadius.controlAll,
          border: Border.all(
            color: isSelected ? AppColors.primaryBright : AppColors.inputBorder,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppText.readableStrong.copyWith(
                  color: isSelected ? AppColors.primaryStrong : AppColors.ink,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check, size: 16, color: AppColors.primaryStrong),
          ],
        ),
      ),
    ),
  );
}
