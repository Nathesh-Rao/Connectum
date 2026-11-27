import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_list_row.dart';
import '../../core/widgets/app_search_field.dart';
import '../../core/widgets/app_sheet_header.dart';
import '../../core/widgets/app_skeleton.dart';
import '../../core/widgets/app_state_view.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/conversation_avatar.dart';
import '../../data/repositories/share_repository.dart';
import 'share_to_connectum_controller.dart';

/// Opens the "Share to Connectum" picker for [files]. Sending closes the sheet
/// and leaves the person where they were; the result is a notice.
Future<void> showShareToConnectum(
  BuildContext context, {
  required ShareRepository repository,
  required List<ShareFile> files,
}) {
  final controller = ShareToConnectumController(repo: repository, files: files)
    ..load();
  return AppBottomSheet.showPinned<void>(
    context,
    child: ShareToConnectumSheet(controller: controller),
  );
}

/// Owns [controller]: it is closed when the sheet's animation is done.
class ShareToConnectumSheet extends StatefulWidget {
  const ShareToConnectumSheet({super.key, required this.controller});

  final ShareToConnectumController controller;

  @override
  State<ShareToConnectumSheet> createState() => _ShareToConnectumSheetState();
}

class _ShareToConnectumSheetState extends State<ShareToConnectumSheet> {
  @override
  void dispose() {
    widget.controller.onClose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final listHeight = math.max(
      MediaQuery.sizeOf(context).height * 0.45,
      400.0,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSheetHeader(title: 'Share to Connectum', subtitle: c.fileLine),
        Flexible(
          child: CustomScrollView(
            key: const ValueKey('share-list'),
            shrinkWrap: true,
            slivers: [
              SliverToBoxAdapter(child: _Chips(controller: c)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                    AppSpacing.xs,
                  ),
                  child: AppSearchField(
                    hint: 'Search chats',
                    controller: c.search,
                    onChanged: c.onSearch,
                  ),
                ),
              ),
              Obx(() {
                final state = c.viewState.value;
                if (state != AppViewState.content) {
                  return SliverToBoxAdapter(
                    child: SizedBox(
                      height: listHeight,
                      child: AppStateView(
                        state: state,
                        emptyTitle: 'No chats yet',
                        emptyMessage: 'Start a chat, then share a file to it.',
                        errorMessage: "Your chats couldn't be loaded.",
                        loadingChild: const _Skeleton(),
                        onRetry: c.load,
                        child: const SizedBox.shrink(),
                      ),
                    ),
                  );
                }
                final rows = c.visible;
                if (rows.isEmpty) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                      child: Center(
                        child: Text('No chats found', style: AppText.readable),
                      ),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  sliver: SliverList.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, i) =>
                        _TargetRow(target: rows[i], controller: c),
                  ),
                );
              }),
            ],
          ),
        ),
        Obx(
          () => c.viewState.value != AppViewState.content
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Obx(
                        () => c.isNoteOpen.value
                            ? AppTextField(
                                key: const ValueKey('share-caption'),
                                controller: c.caption,
                                autofocus: true,
                                hint: 'Add a note (optional)',
                                textInputAction: TextInputAction.done,
                              )
                            : Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: AppButton.text(
                                  key: const ValueKey('share-add-note'),
                                  label: 'Add a note',
                                  leadingIcon: Icons.edit_outlined,
                                  onPressed: c.isNoteOpen.toggle,
                                ),
                              ),
                      ),
                      Obx(
                        () => c.problem.value == null
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(
                                  top: AppSpacing.xs,
                                ),
                                child: Text(
                                  c.problem.value!,
                                  key: const ValueKey('share-problem'),
                                  style: AppText.error,
                                ),
                              ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Obx(
                        () => AppButton.primary(
                          key: const ValueKey('share-send'),
                          label: c.sendLabel,
                          leadingIcon: Icons.send_rounded,
                          isCentered: true,
                          isLoading: c.isChecking.value,
                          onPressed: c.selected.isEmpty
                              ? null
                              : () async {
                                  final navigator = Navigator.of(context);
                                  if (await c.submit()) navigator.pop();
                                },
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips({required this.controller});

  final ShareToConnectumController controller;

  @override
  Widget build(BuildContext context) => Obx(() {
    final chats = controller.chosen;
    return AnimatedSize(
      duration: AppDurations.fast,
      curve: AppCurves.out,
      alignment: Alignment.topCenter,
      child: chats.isEmpty
          ? const SizedBox(width: double.infinity)
          : SizedBox(
              height: 40,
              child: ListView.separated(
                key: const ValueKey('share-chips'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xxs,
                ),
                itemCount: chats.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.xs),
                itemBuilder: (context, i) {
                  final chat = chats[i];
                  return Semantics(
                    button: true,
                    label: 'Remove ${chat.title}',
                    child: GestureDetector(
                      onTap: () => controller.remove(chat.convId),
                      child: Container(
                        padding: const EdgeInsetsDirectional.only(
                          start: AppSpacing.xxs,
                          end: AppSpacing.xs,
                        ),
                        decoration: const BoxDecoration(
                          color: AppColors.primaryTint,
                          borderRadius: AppRadius.pillAll,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            conversationAvatarFor(
                              chat,
                              size: AppSpacing.chipAvatar,
                            ),
                            const SizedBox(width: AppSpacing.xxs),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 120),
                              child: Text(
                                chat.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.readable,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xxs),
                            const Icon(
                              Icons.close,
                              size: 14,
                              color: AppColors.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  });
}

class _TargetRow extends StatelessWidget {
  const _TargetRow({required this.target, required this.controller});

  final ShareTarget target;
  final ShareToConnectumController controller;

  static String _type(ShareTarget t) => switch (t.chat.kind) {
    'dm' =>
      t.chat.isEncrypted ? 'Direct message · encrypted' : 'Direct message',
    'group' => t.chat.isEncrypted ? 'Group · encrypted' : 'Group',
    'host' => 'Team',
    _ => 'Everyone',
  };

  @override
  Widget build(BuildContext context) {
    final t = target;
    return Obx(() {
      final isOn = controller.selected.contains(t.chat.convId);
      return Semantics(
        button: true,
        selected: isOn,
        enabled: t.isEnabled,
        child: Opacity(
          opacity: t.isEnabled ? 1 : 0.5,
          child: AppListRow(
            title: t.chat.title,
            subtitle: t.disabledReason ?? _type(t),
            isSelected: isOn,
            leading: _CheckAvatar(chat: t, isOn: isOn),
            onTap: t.isEnabled ? () => controller.toggle(t) : null,
          ),
        ),
      );
    });
  }
}

class _CheckAvatar extends StatelessWidget {
  const _CheckAvatar({required this.chat, required this.isOn});

  final ShareTarget chat;
  final bool isOn;

  @override
  Widget build(BuildContext context) {
    const size = AppSpacing.avatarSmall;
    final AppAvatar avatar = conversationAvatarFor(chat.chat, size: size);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -2,
            bottom: -2,
            child: AnimatedScale(
              duration: AppDurations.fast,
              curve: AppCurves.out,
              scale: isOn ? 1 : 0,
              child: Container(
                key: isOn ? const ValueKey('share-check') : null,
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryBright,
                  border: Border.all(color: AppColors.white, width: 1.5),
                ),
                child: const Icon(Icons.check, size: 12, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => AppSkeletonScope(
    child: Column(
      key: const ValueKey('share-skeleton'),
      children: [
        for (var i = 0; i < 4; i++)
          const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                AppSkeleton(
                  width: AppSpacing.avatarSmall,
                  height: AppSpacing.avatarSmall,
                  isCircle: true,
                ),
                SizedBox(width: AppSpacing.md),
                Expanded(child: AppSkeleton(height: AppSpacing.sm)),
              ],
            ),
          ),
      ],
    ),
  );
}
