import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/features/chats/chats.dart';
import 'chat_info_controller.dart';
import 'widgets/chat_info_body.dart';

/// The info of a conversation: reached by tapping the conversation header.
/// Read only; it works from what is stored.
class ChatInfoView extends GetView<ChatInfoController> {
  const ChatInfoView({super.key, required this.conversationId});

  final String conversationId;

  @override
  String? get tag => conversationId;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    AppStateImage.precache(context, const [AppStateImageKind.emptyGeneric]);
    return AppScaffold(
      isScrollable: false,
      padding: EdgeInsets.zero,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.xxs,
            ),
            child: Row(
              children: [
                AppButton.icon(
                  icon: Icons.arrow_back,
                  semanticLabel: 'Back',
                  onPressed: Get.back,
                ),
                const Expanded(child: Text('Chat info', style: AppText.title)),
              ],
            ),
          ),
          const AppOfflineBar(),
          Expanded(
            child: Obx(() {
              final data = c.data;
              if (data == null) {
                return const AppStateView(
                  state: AppViewState.empty,
                  emptyTitle: 'Conversation not available',
                  emptyMessage: "This conversation isn't saved on this phone.",
                  child: SizedBox.shrink(),
                );
              }
              return ChatInfoBody(
                data: data,
                onOpenTicket: c.openTicket,
                onAddPeople: c.addPeople,
                onOpenMember: c.openMember,
                onOpenMemberProfile: c.openMemberProfile,
                pictureOf: c.pictureOf,
                onRename: () {
                  final renamer = c.renamer;
                  if (renamer == null) return;
                  RecordRenameSheet.showFor(
                    context,
                    renamer,
                    data.conversation.title,
                  );
                },
                onRefresh: c.ticketId == null ? null : c.refreshTicket,
              );
            }),
          ),
        ],
      ),
    );
  }
}
