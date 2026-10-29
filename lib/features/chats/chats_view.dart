import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_filter_tabs.dart';
import '../../core/widgets/app_offline_bar.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_state_image.dart';
import '../../core/widgets/app_state_view.dart';
import '../../core/widgets/app_text_field.dart';
import 'chats_controller.dart';
import 'widgets/conversation_actions_sheet.dart';
import 'widgets/conversation_tile.dart';
import 'widgets/enterprise_switcher_sheet.dart';
import 'widgets/new_chat_sheet.dart';
import 'widgets/search_results.dart';
import 'widgets/skeleton_rows.dart';

class ChatsView extends GetView<ChatsController> {
  const ChatsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    AppStateImage.precache(context, const [
      AppStateImageKind.emptyChats,
      AppStateImageKind.error,
      AppStateImageKind.offline,
      AppStateImageKind.noResults,
    ]);
    return AppScaffold(
      hasOuterBottomBar: true,
      isScrollable: false,
      padding: EdgeInsets.zero,
      body: Column(
        children: [
          _Header(controller: c),
          const AppOfflineBar(),
          _SearchRow(controller: c),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: Obx(
              () => AppFilterTabs(
                controller: c.filterTabs,
                tabs: [
                  AppFilterTab(label: 'All', count: c.unreadChats.value),
                  const AppFilterTab(label: 'Direct & Teams'),
                ],
              ),
            ),
          ),
          if (SeedUi.isActive) const _DebugStates(),
          Expanded(child: _Body(controller: c)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final ChatsController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Container(
      height: AppSpacing.headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                label: 'Switch enterprise',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    c.switcher.prepare();
                    AppBottomSheet.show<void>(
                      context,
                      title: 'Enterprises',
                      child: EnterpriseSwitcherSheet(controller: c.switcher),
                    );
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppSpacing.minTapTarget,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('YOUR ENTERPRISE', style: AppText.eyebrow),
                        Obx(() {
                          c.store.current.value;
                          c.store.identity.value;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  c.enterpriseName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.subtitle,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              const Icon(
                                Icons.keyboard_arrow_down,
                                size: 18,
                                color: AppColors.ink,
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              AppButton.icon(
                icon: Icons.notifications_none,
                semanticLabel: 'Notifications',
                onPressed: c.openNotifications,
              ),
              Positioned(
                top: AppSpacing.sm,
                right: AppSpacing.sm,
                child: Obx(
                  () => c.feed.unread.value > 0
                      ? Container(
                          width: AppSpacing.navDot,
                          height: AppSpacing.navDot,
                          decoration: const BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
          Semantics(
            button: true,
            label: 'Profile',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: c.openProfile,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: AppSpacing.minTapTarget,
                  minHeight: AppSpacing.minTapTarget,
                ),
                child: Center(
                  child: Obx(() {
                    c.store.identity.value;
                    return AppAvatar(name: c.myName, size: 32);
                  }),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
        AppSpacing.xs,
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
          const SizedBox(width: AppSpacing.xs),
          Semantics(
            button: true,
            label: 'New chat',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () {
                c.newChat.prepare();
                AppBottomSheet.show<void>(
                  context,
                  title: 'New Group / Chat',
                  child: NewChatSheet(controller: c.newChat),
                );
              },
              child: Container(
                width: AppSpacing.iconButton,
                height: AppSpacing.searchHeight,
                decoration: const BoxDecoration(
                  color: AppColors.accentTint,
                  borderRadius: BorderRadius.all(Radius.circular(AppRadius.xs)),
                ),
                child: const Icon(
                  Icons.edit_square,
                  size: 20,
                  color: AppColors.accent,
                ),
              ),
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
      final Widget child = isSearching
          ? SearchResults(key: const ValueKey('search'), controller: c)
          : AppStateView(
              key: ValueKey(state),
              state: state,
              emptyImage: AppStateImageKind.emptyChats,
              emptyTitle: 'No conversations yet',
              emptyMessage: 'Start a chat to see it here.',
              emptyActionLabel: 'Start a chat',
              onEmptyAction: () {
                c.newChat.prepare();
                AppBottomSheet.show<void>(
                  context,
                  title: 'New Group / Chat',
                  child: NewChatSheet(controller: c.newChat),
                );
              },
              errorMessage: 'We could not read your chats.',
              onRetry: c.retry,
              loadingChild: const SkeletonRows(),
              child: _List(controller: c),
            );
      return AnimatedSwitcher(
        duration: AppDurations.fast,
        switchInCurve: AppCurves.out,
        child: child,
      );
    });
  }
}

class _List extends StatelessWidget {
  const _List({required this.controller});

  final ChatsController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.background,
      onRefresh: c.refreshList,
      child: Obx(() {
        final ids = c.visibleIds.toList();
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          itemCount: ids.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Obx(
                () => AnimatedSize(
                  duration: AppDurations.fast,
                  curve: AppCurves.out,
                  alignment: Alignment.topLeft,
                  child: c.isOfflineNote.value
                      ? const Padding(
                          padding: EdgeInsets.only(top: AppSpacing.sm),
                          child: Text(
                            "You're offline",
                            style: AppText.readableStrong,
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              );
            }
            if (index == 1) {
              return const Padding(
                padding: EdgeInsets.only(
                  top: AppSpacing.lg,
                  bottom: AppSpacing.xs,
                ),
                child: Text('Direct & Teams', style: AppText.eyebrow),
              );
            }
            final id = ids[index - 2];
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
        );
      }),
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
