import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_animation_placeholder.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_state_image.dart';
import '../../core/widgets/app_state_view.dart';
import '../../core/widgets/app_status_pill.dart';
import '../../core/widgets/app_text_field.dart';
import 'gallery_controller.dart';

class GalleryView extends GetView<GalleryController> {
  const GalleryView({super.key});

  static const _colors = <String, Color>{
    'accent': AppColors.accent,
    'accentHover': AppColors.accentHover,
    'accentTint': AppColors.accentTint,
    'accentSoft': AppColors.accentSoft,
    'accentInk': AppColors.accentInk,
    'accentDisabled': AppColors.accentDisabled,
    'ivory': AppColors.ivory,
    'peach': AppColors.peach,
    'apricot': AppColors.apricot,
    'sand': AppColors.sand,
    'olive': AppColors.olive,
    'taupe': AppColors.taupe,
    'background': AppColors.background,
    'surface': AppColors.surface,
    'sage': AppColors.sage,
    'bubbleIn': AppColors.bubbleIn,
    'ink': AppColors.ink,
    'muted': AppColors.muted,
    'line': AppColors.line,
    'inputBorder': AppColors.inputBorder,
    'error': AppColors.error,
    'yesFill': AppColors.yesFill,
    'yesDot': AppColors.yesDot,
    'noFill': AppColors.noFill,
    'noDot': AppColors.noDot,
  };

  static const _routes = <String, String>{
    'splash': AppRoutes.splash,
    'onboarding': AppRoutes.onboarding,
    'authentication': AppRoutes.authentication,
    'verification': AppRoutes.verification,
    'enterprises': AppRoutes.enterprises,
    'enterprise_created': AppRoutes.enterpriseCreated,
    'chats': AppRoutes.chats,
    'ai_agents': AppRoutes.aiAgents,
    'conversation': '/conversation/demo',
    'submissions': AppRoutes.submissions,
    'submission_detail': '/submissions/demo',
    'profile': AppRoutes.profile,
    'notifications': AppRoutes.notifications,
    'debug/socket': AppRoutes.debugSocket,
    'debug/assets': AppRoutes.debugAssets,
    'debug/chat': AppRoutes.debugChat,
    'debug/notifications': AppRoutes.debugNotifications,
    'debug/tasks': AppRoutes.debugTasks,
    'debug/tickets': AppRoutes.debugTickets,
  };

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      bottomBarColor: AppColors.sand,
      bottomBar: const _DemoTabBar(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xl),
          const Text('Gallery', style: AppText.display),
          _section('Auth-style screen'),
          AppButton.primary(
            label: 'Open auth-style screen',
            icon: Icons.arrow_forward,
            onPressed: () => Get.toNamed(AppRoutes.galleryAuth),
          ),
          _section('Colors'),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final e in _colors.entries)
                _Swatch(name: e.key, color: e.value),
            ],
          ),
          _section('Type'),
          const _Sample('display 30', AppText.display),
          const _Sample('heading 26', AppText.heading),
          const _Sample('title 21', AppText.title),
          const _Sample('subtitle 17', AppText.subtitle),
          const _Sample('body 13 - Plus Jakarta Sans', AppText.body),
          const _Sample('bodyStrong 13', AppText.bodyStrong),
          const _Sample('readable 12', AppText.readable),
          const _Sample('readableStrong 12', AppText.readableStrong),
          const _Sample('label 11', AppText.label),
          const _Sample('caption 11', AppText.caption),
          const _Sample('error 11', AppText.error),
          _section('Spacing'),
          Wrap(
            spacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: const [
              _Bar('xxs', AppSpacing.xxs),
              _Bar('xs', AppSpacing.xs),
              _Bar('sm', AppSpacing.sm),
              _Bar('md', AppSpacing.md),
              _Bar('lg', AppSpacing.lg),
              _Bar('xl', AppSpacing.xl),
              _Bar('xxl', AppSpacing.xxl),
            ],
          ),
          _section('Radius'),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: const [
              _Round('8', AppRadius.xs),
              _Round('10', AppRadius.control),
              _Round('12', AppRadius.md),
              _Round('14', AppRadius.card),
              _Round('15', AppRadius.bubble),
              _Round('16', AppRadius.lg),
              _Round('20', AppRadius.sheet),
              _Round('pill', AppRadius.pill),
            ],
          ),
          _section('Shadows'),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: const [
              _Shadow('soft', AppShadows.soft),
              _Shadow('card', AppShadows.card),
              _Shadow('focusRing', AppShadows.focusRing),
              _Shadow('sheet', AppShadows.sheet),
            ],
          ),
          _section('Motion'),
          const Text(
            'fast 190 / base 320 / slow 500 / page 450 ms\n'
            'out cubic(.25,.06,.12,1)\n'
            'sheet spring 300/32, press spring 420/34\n'
            'parallax 25%, tab rise 8, press scale .97',
            style: AppText.readable,
          ),
          _section('AppButton'),
          AppButton.primary(
            label: 'Primary',
            icon: Icons.arrow_forward,
            onPressed: () {},
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton.secondary(label: 'Secondary', onPressed: () {}),
          const SizedBox(height: AppSpacing.sm),
          const AppButton.primary(label: 'Disabled', onPressed: null),
          const SizedBox(height: AppSpacing.sm),
          AppButton.primary(
            label: 'Loading',
            isLoading: true,
            onPressed: () {},
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              AppButton.icon(
                icon: Icons.close,
                semanticLabel: 'Close',
                onPressed: () {},
              ),
              AppButton.icon(
                icon: Icons.add,
                semanticLabel: 'Add',
                onPressed: () {},
              ),
            ],
          ),
          _section('AppTextField'),
          AppTextField(
            controller: controller.singleLine,
            label: 'Single line',
            hint: 'Type here',
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: controller.multiline,
            label: 'Multiline',
            hint: 'Several lines',
            minLines: 3,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: controller.withError,
            label: 'Error',
            errorText: 'Enter a valid email address.',
          ),
          _section('AppAvatar / AppStatusPill'),
          const Row(
            children: [
              AppAvatar(name: 'Priya Sharma'),
              SizedBox(width: AppSpacing.sm),
              AppAvatar(name: 'Arjun'),
              SizedBox(width: AppSpacing.sm),
              AppAvatar(name: ''),
              SizedBox(width: AppSpacing.xl),
              AppStatusPill(isYes: true),
              SizedBox(width: AppSpacing.sm),
              AppStatusPill(isYes: false),
            ],
          ),
          _section('AppBottomSheet'),
          AppButton.secondary(
            label: 'Open sheet',
            onPressed: () => AppBottomSheet.show(
              context,
              title: 'Sample sheet',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Springs up, drag the handle or the body down to close.',
                    style: AppText.readable,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(label: 'Sheet field', hint: 'Keyboard test'),
                  const SizedBox(height: AppSpacing.lg),
                  AppButton.primary(label: 'Got it', onPressed: Get.back),
                ],
              ),
            ),
          ),
          _section('AppStateView'),
          const AppAnimationPlaceholder(name: 'placeholder'),
          for (final state in [
            AppViewState.loading,
            AppViewState.empty,
            AppViewState.error,
            AppViewState.offline,
          ])
            SizedBox(
              height: 320,
              child: AppStateView(
                state: state,
                emptyImage: AppStateImageKind.emptyChats,
                emptyTitle: 'No chats yet',
                emptyMessage: 'Conversations will appear here.',
                onRetry: () {},
                child: const SizedBox.shrink(),
              ),
            ),
          _section('Routes'),
          for (final e in _routes.entries) ...[
            AppButton.secondary(
              label: e.key,
              onPressed: () => Get.toNamed(e.value),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.sm),
    child: Text(title, style: AppText.subtitle),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = color.computeLuminance() < 0.4;
    return Container(
      width: 104,
      height: 56,
      padding: const EdgeInsets.all(AppSpacing.xs),
      alignment: Alignment.bottomLeft,
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadius.controlAll,
        border: Border.all(color: AppColors.line),
      ),
      child: Text(
        name,
        style: AppText.caption.copyWith(
          color: isDark ? AppColors.background : AppColors.ink,
        ),
      ),
    );
  }
}

class _Sample extends StatelessWidget {
  const _Sample(this.text, this.style);

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Text(text, style: style),
  );
}

class _Bar extends StatelessWidget {
  const _Bar(this.label, this.size);

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(width: size, height: size, color: AppColors.accent),
      Text(label, style: AppText.caption),
    ],
  );
}

class _Round extends StatelessWidget {
  const _Round(this.label, this.radius);

  final String label;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: 56,
    height: 56,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.accentTint,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: Text(label, style: AppText.caption),
  );
}

class _Shadow extends StatelessWidget {
  const _Shadow(this.label, this.shadows);

  final String label;
  final List<BoxShadow> shadows;

  @override
  Widget build(BuildContext context) => Container(
    width: 120,
    height: 72,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: AppRadius.cardAll,
      boxShadow: shadows,
      border: Border.all(color: AppColors.line),
    ),
    child: Text(label, style: AppText.caption),
  );
}

class _DemoTabBar extends StatelessWidget {
  const _DemoTabBar();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 56,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        Text('Chats', style: AppText.readableStrong),
        Text('AI', style: AppText.readableStrong),
        Text('Submissions', style: AppText.readableStrong),
        Text('Profile', style: AppText.readableStrong),
      ],
    ),
  );
}
