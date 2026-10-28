import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_list_row.dart';
import '../../core/widgets/app_notice_banner.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/models/identity_info.dart';
import 'enterprises_controller.dart';
import 'widgets/join_sheet.dart';

class EnterprisesView extends GetView<EnterprisesController> {
  const EnterprisesView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
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
            Row(
              children: [
                Image.asset('assets/images/connectum_logo.png', width: 26),
                const SizedBox(width: AppSpacing.xs),
                const Text('Connectum', style: AppText.subtitle),
                const Spacer(),
                AppButton.icon(
                  icon: Icons.more_horiz,
                  semanticLabel: 'Account options',
                  onPressed: () => AppBottomSheet.show<void>(
                    context,
                    title: 'Account options',
                    child: AppButton.secondary(
                      label: 'Sign out',
                      onPressed: () {
                        Navigator.of(context).pop();
                        c.signOut();
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text('YOUR CONNECTED WORLD', style: AppText.label),
            const SizedBox(height: AppSpacing.xs),
            const Text('Choose an\nenterprise.', style: AppText.display),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              "Pick where you'd like to work today.",
              style: AppText.readable,
            ),
            const SizedBox(height: AppSpacing.lg),
            _Message(controller: c),
            _IdentityStrip(controller: c),
            _List(controller: c),
            const SizedBox(height: AppSpacing.md),
            AppButton.primary(
              label: 'Join another enterprise',
              icon: Icons.arrow_forward,
              onPressed: () {
                c.resetJoin();
                AppBottomSheet.show<void>(
                  context,
                  title: 'Join an enterprise',
                  child: JoinSheet(controller: c),
                );
              },
            ),
            const Spacer(),
            Row(
              children: [
                Obx(
                  () => AppButton.text(
                    label: c.isRefreshing.value ? 'Refreshing…' : 'Refresh',
                    onPressed: c.refresh,
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
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: controller.copyConnectumId,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: AppRadius.controlAll,
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                const Text('Connectum ID', style: AppText.label),
                const SizedBox(width: AppSpacing.sm),
                Text(id, style: AppText.bodyStrong),
                const Spacer(),
                const Icon(
                  Icons.copy_rounded,
                  size: 16,
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
        ),
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
          height: 300,
          child: AppStateView(
            state: state,
            emptyAnimation: 'empty-enterprises',
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
          for (final m in list)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: AppListRow(
                leading: AppAvatar(name: m.name),
                title: m.name,
                subtitle: m.isActive
                    ? 'Member · ${m.enterprise}'
                    : m.status == 'pending'
                    ? 'Waiting for approval · ${m.enterprise}'
                    : 'Not approved · ${m.enterprise}',
                trailing: c.enteringId.value == m.enterprise
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accent,
                        ),
                      )
                    : m.isActive
                    ? const Icon(Icons.arrow_forward, size: 18)
                    : null,
                onTap: () => c.enter(m),
              ),
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
