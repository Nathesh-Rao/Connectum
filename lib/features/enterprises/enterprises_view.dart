import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_flex_gap.dart';
import '../../core/widgets/app_id_copy_strip.dart';
import '../../core/widgets/app_list_row.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/app_notice_banner.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_state_image.dart';
import '../../core/widgets/app_state_view.dart';
import '../../core/widgets/app_tag.dart';
import '../../data/models/identity_info.dart';
import '../connect/connect_view.dart';
import 'enterprises_controller.dart';
import 'widgets/enterprise_tile.dart';

class EnterprisesView extends GetView<EnterprisesController> {
  const EnterprisesView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    AppStateImage.precache(context, const [
      AppStateImageKind.emptyEnterprises,
      AppStateImageKind.error,
      AppStateImageKind.offline,
    ]);
    return AppScaffold(
      showOfflineBar: true,
      body: Obx(() {
        if (c.blockedReasons.isNotEmpty) {
          return _Blocked(
            reasons: c.blockedReasons,
            onBack: c.blockedReasons.clear,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      const AppLogo(width: AppSpacing.headerLogoWidth + 3),
                      const SizedBox(width: AppSpacing.xs),
                      const Text('Connectum', style: AppText.wordmarkLarge),
                      const Spacer(),
                      Transform.translate(
                        offset: const Offset(AppSpacing.sm, 0),
                        child: AppButton.icon(
                          icon: Icons.more_horiz,
                          semanticLabel: 'Account options',
                          onPressed: () => AppBottomSheet.show<void>(
                            context,
                            title: 'Account options',
                            child: AppListRow(
                              title: 'Sign out',
                              titleStyle: AppText.rowLabel,
                              minHeight: AppSpacing.settingRowHeight,
                              trailing: const _Chevron(),
                              onTap: () {
                                Navigator.of(context).pop();
                                c.signOut();
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const AppFlexGap(flex: 28, min: 8, max: 40),
                  const Text('YOUR CONNECTED WORLD', style: AppText.kicker),
                  const SizedBox(height: AppSpacing.xs),
                  const Text('Choose an\nenterprise.', style: AppText.display),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    "Pick where you'd like to work today.",
                    style: AppText.readable,
                  ),
                  const AppFlexGap(flex: 23, min: 8, max: 32),
                  _Message(controller: c),
                  _IdentityStrip(controller: c),
                  const SizedBox(height: AppSpacing.sm),
                  _List(controller: c),
                  const AppFlexGap(flex: 17, min: 8, max: 28),
                  AppButton.primary(
                    label: 'Join another enterprise',
                    leadingIcon: Icons.add,
                    icon: Icons.chevron_right,
                    isCompact: true,
                    onPressed: () {
                      c.connect.open();
                      AppBottomSheet.show<void>(
                        context,
                        title: 'Join another enterprise',
                        child: ConnectView(onEnter: c.enter),
                      ).whenComplete(c.connect.close);
                    },
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Transform.translate(
                  offset: const Offset(-AppSpacing.sm, 0),
                  child: Obx(
                    () => AppButton.text(
                      label: 'Refresh',
                      leadingIcon: Icons.refresh,
                      tone: AppTextButtonTone.accent,
                      isLoading: c.isRefreshing.value,
                      onPressed: c.refresh,
                    ),
                  ),
                ),
                const Spacer(),
                const Text(
                  'One account. Every enterprise.',
                  style: AppText.caption,
                ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) =>
      const Icon(Icons.chevron_right, size: 20, color: AppColors.rowChevron);
}

class _Message extends StatelessWidget {
  const _Message({required this.controller});

  final EnterprisesController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final text = controller.message.value;
      if (text == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: AppNoticeBanner(
          message: text,
          onDismiss: () => controller.message.value = null,
        ),
      );
    });
  }
}

class _IdentityStrip extends StatelessWidget {
  const _IdentityStrip({required this.controller});

  final EnterprisesController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final id = controller.store.identity.value?.connectumId ?? '';
      if (id.isEmpty) return const SizedBox.shrink();
      return AppIdCopyStrip(
        id: id,
        isCopied: controller.isCopied.value,
        onTap: controller.copyConnectumId,
      );
    });
  }
}

class _List extends StatelessWidget {
  const _List({required this.controller});

  final EnterprisesController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final list =
          c.store.identity.value?.enterprises ?? const <EnterpriseMembership>[];
      if (list.isEmpty) {
        final state = c.isRefreshing.value
            ? AppViewState.loading
            : c.loadError.value != null
            ? AppViewState.error
            : c.isOffline
            ? AppViewState.offline
            : AppViewState.empty;
        return SizedBox(
          height: 360,
          child: AppStateView(
            state: state,
            emptyImage: AppStateImageKind.emptyEnterprises,
            emptyTitle: "You're not in an enterprise yet",
            emptyMessage: 'Join one below to get started.',
            errorMessage: c.loadError.value ?? 'Something went wrong.',
            onRetry: c.refresh,
            child: const SizedBox.shrink(),
          ),
        );
      }
      return Column(
        children: [
          for (var i = 0; i < list.length; i++)
            AppListRow(
              leading: EnterpriseTile(
                index: i,
                isCurrent: list[i].enterprise == c.currentOrgId,
              ),
              title: list[i].name,
              subtitle: list[i].isActive
                  ? 'Member · ${list[i].enterprise}'
                  : list[i].enterprise,
              trailing: c.enteringId.value == list[i].enterprise
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accent,
                      ),
                    )
                  : list[i].enterprise == c.currentOrgId
                  ? const EnterpriseCurrentCheck()
                  : list[i].isActive
                  ? const _Chevron()
                  : list[i].status == 'pending'
                  ? const AppTag(
                      label: 'Waiting for approval',
                      tone: AppTagTone.accent,
                      icon: Icons.hourglass_top,
                    )
                  : const AppTag(label: 'Not approved'),
              onTap: () => c.enter(list[i]),
            ),
        ],
      );
    });
  }
}

class _Blocked extends StatelessWidget {
  const _Blocked({required this.reasons, required this.onBack});

  final List<String> reasons;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        const Text(
          "This account needs a step the mobile app doesn't support yet",
          style: AppText.title,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text('Required: ${reasons.join(', ')}.', style: AppText.readable),
        const SizedBox(height: AppSpacing.xl),
        AppButton.secondary(label: 'Back', onPressed: onBack),
        const Spacer(),
      ],
    );
  }
}
