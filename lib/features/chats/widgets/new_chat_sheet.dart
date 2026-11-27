import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_highlight_text.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/app_state_image.dart';
import '../../../core/widgets/app_state_view.dart';
import '../../../core/widgets/app_text_field.dart';
import '../models/chat_person.dart';
import '../new_chat_controller.dart';
import 'new_chat_person_row.dart';
import 'skeleton_rows.dart';

/// The New chat sheet: a fixed header (title, search, New group) over one
/// scrolling list. Connected people come first; the rest follow under "Not
/// connected" and load a page at a time as the list scrolls.
class NewChatSheet extends StatelessWidget {
  const NewChatSheet({super.key, required this.controller});

  final NewChatController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sheetPaddingX),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('New Group / Chat', style: AppText.title),
              ),
              AppButton.icon(
                icon: Icons.close,
                semanticLabel: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: c.queryField,
            hint: 'Search by name or username',
            minHeight: AppSpacing.searchHeight,
            fillColor: AppColors.searchFill,
            borderColor: Colors.transparent,
            borderRadius: const BorderRadius.all(Radius.circular(AppRadius.xs)),
            textStyle: AppText.input,
            leading: const Icon(Icons.search, size: 18, color: AppColors.muted),
            onChanged: c.onQueryChanged,
            textInputAction: TextInputAction.search,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppListRow(
            title: 'New group',
            subtitle: 'Create a group and add people',
            leading: const Icon(
              Icons.group_add_outlined,
              size: 22,
              color: AppColors.primaryBright,
            ),
            trailing: const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.rowChevron,
            ),
            minHeight: AppSpacing.settingRowHeight,
            onTap: c.openNewGroup,
          ),
          Expanded(
            child: Obx(() {
              final state = c.listState;
              return AppStateView(
                state: state,
                loadingChild: const SkeletonRows(),
                onRetry: c.retry,
                emptyImage: AppStateImageKind.emptyChats,
                emptyTitle: c.isOffline
                    ? 'You are offline'
                    : 'No one to show yet',
                emptyMessage: c.isOffline
                    ? 'Finding someone new needs a connection.'
                    : 'People you chat with will show up here.',
                errorMessage: 'We could not load the list of people.',
                child: _PeopleList(controller: c),
              );
            }),
          ),
        ],
      ),
    );
  }
}

enum _Kind { note, header, person, footer }

class _Item {
  const _Item(this.kind, {this.title, this.person});

  final _Kind kind;
  final String? title;
  final ChatPerson? person;
}

class _PeopleList extends StatelessWidget {
  const _PeopleList({required this.controller});

  final NewChatController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() => _build(controller));
  }

  Widget _build(NewChatController c) {
    final note = c.explanation.value;
    final sendingNow = c.sending.toSet();
    final connected = c.connectedPeople;
    final others = c.otherPeople;
    final isMoreFailed = c.hasLoadMoreFailed.value;
    final isLoadingMore = c.isLoadingMore.value;
    final isReading = c.isLoading.value;
    final hasFailed = c.hasFailed.value;
    final showOthers =
        others.isNotEmpty || isReading || hasFailed || c.hasMore.value;
    final items = <_Item>[
      if (note != null) const _Item(_Kind.note),
      if (connected.isNotEmpty && showOthers)
        const _Item(_Kind.header, title: 'Connected'),
      for (final p in connected) _Item(_Kind.person, person: p),
      if (showOthers) const _Item(_Kind.header, title: 'Not connected'),
      for (final p in others) _Item(_Kind.person, person: p),
      if (isLoadingMore || isMoreFailed || (hasFailed && others.isEmpty))
        const _Item(_Kind.footer),
    ];
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 200) c.loadMore();
        return false;
      },
      child: ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          switch (item.kind) {
            case _Kind.note:
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: AppHighlightText(
                  note ?? '',
                  values: c.explanationValues,
                ),
              );
            case _Kind.header:
              return Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.sm,
                  bottom: AppSpacing.xxs,
                ),
                child: Text(
                  item.title ?? '',
                  style: AppText.fieldLabel,
                  semanticsLabel: item.title,
                ),
              );
            case _Kind.person:
              final p = item.person!;
              return NewChatPersonRow(
                key: ValueKey(p.username.toLowerCase()),
                person: p,
                link: c.linkOf(p),
                onOpen: () => c.start(p),
                onConnect: () => c.connect(p),
                isSending: sendingNow.contains(p.username.toLowerCase()),
              );
            case _Kind.footer:
              return _Footer(
                isFailed: isMoreFailed || hasFailed,
                reason: c.failureReason.value,
                onRetry: hasFailed ? c.retry : c.retryMore,
              );
          }
        },
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.isFailed, required this.onRetry, this.reason});

  final bool isFailed;
  final String? reason;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(
        child: isFailed
            ? Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.xs,
                children: [
                  Text(
                    reason ?? "Couldn't load more people.",
                    style: AppText.readable,
                    textAlign: TextAlign.center,
                  ),
                  AppButton.text(label: 'Retry', onPressed: onRetry),
                ],
              )
            : const Text('Loading…', style: AppText.readable),
      ),
    );
  }
}
