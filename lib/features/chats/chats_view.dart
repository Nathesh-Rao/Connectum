import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_offline_bar.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_state_image.dart';
import '../../core/widgets/app_state_view.dart';
import '../../core/widgets/app_notices.dart';
import '../../core/widgets/app_text_field.dart';
import 'chats_controller.dart';
import 'models/chat_filter.dart';
import 'widgets/chat_filter_bar.dart';
import 'widgets/chats_header.dart';
import 'widgets/workspace_row.dart';
import 'widgets/conversation_actions_sheet.dart';
import 'widgets/conversation_tile.dart';
import 'widgets/enterprise_switcher_sheet.dart';
import 'widgets/new_chat_fab.dart';
import 'widgets/new_chat_sheet.dart';
import 'widgets/search_results.dart';
import 'widgets/skeleton_rows.dart';
import '../../core/widgets/app_refresh.dart';

class ChatsView extends GetView<ChatsController> {
  const ChatsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    AppStateImage.precache(context, const [
      AppStateImageKind.emptyChats,
      AppStateImageKind.error,
      AppStateImageKind.noResults,
    ]);
    return AppScaffold(
      hasOuterBottomBar: true,
      isScrollable: false,
      padding: EdgeInsets.zero,
      body: Column(
        children: [
          ChatsHeader(
            enterpriseName: () {
              c.store.current.value;
              c.store.identity.value;
              return c.enterpriseName;
            },
            unread: () => c.feed.unread.value,
            onSwitchEnterprise: () {
              c.switcher.prepare();
              AppBottomSheet.show<void>(
                context,
                title: 'Enterprises',
                child: EnterpriseSwitcherSheet(controller: c.switcher),
              );
            },
            onOpenNotifications: c.openNotifications,
          ),
          const AppOfflineBar(),
          _SearchRow(controller: c),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              0,
              AppSpacing.page,
              AppSpacing.sm,
            ),
            child: ChatFilterBar(
              filter: c.filter,
              hasThreads: c.hasThreads,
              threadUnread: c.threadUnread,
              onSelected: c.select,
            ),
          ),
          if (SeedUi.isActive) const _DebugStates(),
          Expanded(
            child: Stack(
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: c.newChatButton.onScroll,
                  child: _Body(controller: c),
                ),
                Positioned(
                  right: AppSpacing.fabMargin,
                  bottom: AppSpacing.fabMargin,
                  child: Obx(
                    () => NewChatFab(
                      isShown: c.newChatButton.isShown.value,
                      isKeyboardOpen: isKeyboardOpen,
                      onPressed: () => _openNewChat(context, c),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _openNewChat(BuildContext context, ChatsController c) {
  c.newChat.prepare();
  AppBottomSheet.show<void>(
    context,
    title: 'New Group / Chat',
    child: NewChatSheet(controller: c.newChat),
  );
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.controller});

  final ChatsController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.xl,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AppTextField(
              controller: c.searchField,
              focusNode: c.searchFocus,
              hint: 'Search people, teams, messages',
              minHeight: AppSpacing.searchHeight,
              fillColor: AppColors.searchFill,
              borderColor: Colors.transparent,
              borderRadius: const BorderRadius.all(
                Radius.circular(AppRadius.xs),
              ),
              leading: const Icon(
                Icons.search,
                size: 18,
                color: AppColors.muted,
              ),
              suffix: Obx(
                () => c.query.value.isEmpty
                    ? const SizedBox.shrink()
                    : AppButton.icon(
                        icon: Icons.close,
                        semanticLabel: 'Clear search',
                        onPressed: c.clearSearch,
                      ),
              ),
              textInputAction: TextInputAction.search,
              onChanged: c.onQueryChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final ChatsController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final isSearching = c.isSearching;
      final state = c.viewState.value;
      final isFiltered = c.filter.value != ChatFilterKind.all;
      final Widget child = isSearching
          ? SearchResults(key: const ValueKey('search'), controller: c)
          : _Refreshable(
              isEnabled: state == AppViewState.empty,
              onRefresh: () => _refresh(c),
              child: AppStateView(
                key: ValueKey(state),
                state: state,
                emptyImage: AppStateImageKind.emptyChats,
                emptyTitle: _emptyTitle(c.filter.value),
                emptyMessage: _emptyMessage(c.filter.value),
                emptyActionLabel: isFiltered
                    ? 'View all conversations'
                    : 'Start a chat',
                onEmptyAction: isFiltered
                    ? () => c.select(ChatFilterKind.all)
                    : () => _openNewChat(context, c),
                errorMessage: 'We could not read your chats.',
                onRetry: c.retry,
                loadingChild: const SkeletonRows(),
                child: _List(controller: c),
              ),
            );
      return Column(
        children: [
          if (!isSearching && c.filter.value != ChatFilterKind.threads)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: WorkspaceRow(onTap: c.openWorkspace),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: AppDurations.fast,
              switchInCurve: AppCurves.out,
              child: child,
            ),
          ),
        ],
      );
    });
  }
}

String _emptyTitle(ChatFilterKind filter) => switch (filter) {
  ChatFilterKind.all => 'No conversations yet',
  ChatFilterKind.direct => 'No direct conversations',
  ChatFilterKind.threads => 'No threads',
};

String _emptyMessage(ChatFilterKind filter) => switch (filter) {
  ChatFilterKind.all => 'Start a chat to see it here.',
  ChatFilterKind.direct =>
    "You don't have any direct messages or team conversations open.",
  ChatFilterKind.threads => "You don't have any thread conversations open.",
};

Future<void> _refresh(ChatsController c) async {
  if (c.isOffline) AppNotices.info("You're offline");
  await c.refreshList();
}

/// Lets the empty state be pulled to refresh, like the list.
class _Refreshable extends StatelessWidget {
  const _Refreshable({
    required this.isEnabled,
    required this.onRefresh,
    required this.child,
  });

  final bool isEnabled;
  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isEnabled) return child;
    return AppRefresh(
      onRefresh: onRefresh,
      slivers: [SliverFillRemaining(hasScrollBody: false, child: child)],
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.controller});

  final ChatsController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppRefresh(
      onRefresh: () => _refresh(c),
      slivers: [
        Obx(() {
          final ids = c.visibleIds.toList();
          return SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.sm,
              AppSpacing.page,
              AppSpacing.fab +
                  AppSpacing.fabMargin * 2 +
                  MediaQuery.paddingOf(context).bottom,
            ),
            sliver: SliverList.builder(
              itemCount: ids.length,
              itemBuilder: (context, index) {
                final id = ids[index];
                final row = c.rowOf(id);
                return Obx(
                  () => ConversationTile(
                    key: ValueKey(id),
                    conversation: row.value,
                    controller: c,
                    onTap: () => c.open(id),
                    onLongPress: () =>
                        ConversationActionsSheet.show(context, c, row.value),
                  ),
                );
              },
            ),
          );
        }),
      ],
    );
  }
}

/// Debug only (SEED_UI=1): switches the Chats screen between its states.
class _DebugStates extends StatelessWidget {
  const _DebugStates();

  @override
  Widget build(BuildContext context) {
    const states = ['content', 'loading', 'empty', 'error', 'offline'];
    return SizedBox(
      height: AppSpacing.minTapTarget,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
        children: [
          for (final s in states)
            AppButton.text(
              label: s,
              onPressed: () => SeedUi.chatsState.value = s,
            ),
        ],
      ),
    );
  }
}
