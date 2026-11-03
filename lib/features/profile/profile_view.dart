import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import '../chats/widgets/enterprise_switcher_sheet.dart';
import 'profile_controller.dart';
import 'widgets/logout_sheet.dart';
import 'widgets/profile_identity_card.dart';
import 'widgets/profile_row.dart';

class ProfileView extends GetView<ProfileController> {
  const ProfileView({super.key});

  Future<void> _openSwitcher(BuildContext context) {
    controller.prepareSwitcher();
    return AppBottomSheet.show<void>(
      context,
      title: 'Enterprises',
      child: EnterpriseSwitcherSheet(controller: controller.switcher),
    );
  }

  Future<void> _confirmLogOut(BuildContext context) async {
    final unsent = await controller.unsentCount();
    if (!context.mounted) return;
    await _showLogOut(context, unsent);
  }

  Future<void> _showLogOut(BuildContext context, int unsent) =>
      AppBottomSheet.show<void>(
        context,
        title: 'Log out of Connectum?',
        child: LogoutSheet(controller: controller, unsent: unsent),
      );

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      hasOuterBottomBar: true,
      isScrollable: false,
      padding: EdgeInsets.zero,
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Profile', style: AppText.heading),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.xl,
              ),
              child: Obx(() {
                // Read here so the view rebuilds on a sign-in change, a
                // connection change or a seed variant switch.
                SeedUi.profileVariant.value;
                c.store.identity.value;
                c.connectivity.state.value;
                final email = c.email;
                final category = c.category;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ProfileIdentityCard(
                      name: c.name,
                      username: c.username,
                      organisation: c.organisation,
                      isOnline: c.isOnline,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    ProfileGroup(
                      title: 'ACCOUNT',
                      children: [
                        if (c.connectumId.isNotEmpty)
                          ProfileInfoRow(
                            label: 'Connectum ID',
                            value: c.connectumId,
                            valueStyle: AppText.body.copyWith(
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                            onTap: c.copyConnectumId,
                            trailing: _CopyIcon(isCopied: c.isCopied),
                          ),
                        if (email.isNotEmpty)
                          ProfileInfoRow(label: 'Email', value: email),
                        if (category.isNotEmpty)
                          ProfileInfoRow(label: 'Category', value: category),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    ProfileGroup(
                      title: 'WORKSPACE',
                      children: [
                        ProfileActionRow(
                          icon: Icons.swap_horiz_rounded,
                          title: 'Switch enterprise',
                          subtitle: c.organisation,
                          onTap: () => _openSwitcher(context),
                        ),
                        ProfileActionRow(
                          icon: Icons.shield_outlined,
                          title: 'Security',
                          subtitle: 'Devices and encryption',
                          onTap: c.openSecurity,
                        ),
                        ProfileActionRow(
                          icon: Icons.play_circle_outline,
                          title: 'Experience the introduction',
                          subtitle: 'Replay the welcome tour',
                          onTap: c.replayIntroduction,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AppButton.secondary(
                      label: 'Log out',
                      leadingIcon: Icons.logout,
                      isDanger: true,
                      onPressed: () => _confirmLogOut(context),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Obx(() {
                      final version = c.version.value;
                      if (version == null) return const SizedBox.shrink();
                      return Text(
                        'Connectum $version',
                        textAlign: TextAlign.center,
                        style: AppText.caption.copyWith(color: AppColors.muted),
                      );
                    }),
                    if (SeedUi.isActive) _SeedChips(show: _showLogOut),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyIcon extends StatelessWidget {
  const _CopyIcon({required this.isCopied});

  final RxBool isCopied;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => AnimatedSwitcher(
        duration: AppDurations.base,
        child: isCopied.value
            ? const Row(
                key: ValueKey('copied'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Copied', style: AppText.copiedLabel),
                  SizedBox(width: AppSpacing.xs),
                  Icon(Icons.check, size: 18, color: AppColors.yesDot),
                ],
              )
            : const Icon(
                Icons.copy_rounded,
                key: ValueKey('copy'),
                size: 18,
                color: AppColors.muted,
              ),
      ),
    );
  }
}

/// Debug only (SEED_UI=1): switches the Profile fixtures and opens the log
/// out sheet without signing anyone out.
class _SeedChips extends StatelessWidget {
  const _SeedChips({required this.show});

  final Future<void> Function(BuildContext context, int unsent) show;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.xs,
        children: [
          for (final v in ['typical', 'long', 'sparse'])
            ActionChip(
              label: Text(v),
              onPressed: () => SeedUi.profileVariant.value = v,
            ),
          ActionChip(label: const Text('sheet'), onPressed: () => show(context, 0)),
          ActionChip(
            label: const Text('sheet · 3 unsent'),
            onPressed: () => show(context, 3),
          ),
        ],
      ),
    );
  }
}
