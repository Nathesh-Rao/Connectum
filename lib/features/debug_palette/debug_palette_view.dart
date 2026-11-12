import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_chart_colors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_tones.dart';
import '../../core/utils/avatar_palette.dart';
import '../../core/widgets/app_action_bar.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_pill_bar.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_status_pill.dart';
import '../../core/widgets/app_unread_badge.dart';
import '../tickets/models/ticket_action_style.dart';
import 'button_samples.dart';
import 'debug_palette_controller.dart';

/// Debug only: every colour token with its contrast, and the widgets that use
/// them in each state.
class DebugPaletteView extends GetView<DebugPaletteController> {
  const DebugPaletteView({super.key});

  static const _tokens = <(String, Color, String)>[
    ('primary', AppColors.primary, 'filled buttons, links, active labels'),
    ('primaryBright', AppColors.primaryBright, 'icons, FAB, switches, dots'),
    ('primaryLight', AppColors.primaryLight, 'decorative highlights'),
    ('cyanBlue', AppColors.cyanBlue, 'decorative gradients, glows'),
    ('primaryStrong', AppColors.primaryStrong, 'pressed, text on tints'),
    ('violet', AppColors.violet, 'AI, series 2, Medium, Return'),
    ('purple', AppColors.purple, 'tickets, filled violet pill'),
    ('violetStrong', AppColors.violetStrong, 'text on violetTint'),
    ('primarySoft', AppColors.primarySoft, 'selected rows (6 %)'),
    ('primaryTint', AppColors.primaryTint, 'chips, tinted buttons (10 %)'),
    ('primaryTintStrong', AppColors.primaryTintStrong, 'highlight (16 %)'),
    ('primaryBorder', AppColors.primaryBorder, 'soft borders (26 %)'),
    ('primaryDisabled', AppColors.primaryDisabled, 'disabled filled button'),
    ('violetTint', AppColors.violetTint, 'violet chips (13 %)'),
    (
      'white',
      AppColors.white,
      'every page, sheet, card; content on filled colours',
    ),
    (
      'surfaceSubtle',
      AppColors.surfaceSubtle,
      'cool panel fill (profile identity card)',
    ),
    ('fill', AppColors.fill, 'neutral fills'),
    ('bubbleIn', AppColors.bubbleIn, 'incoming bubble'),
    ('bubbleOut', AppColors.bubbleOut, 'outgoing bubble'),
    ('ink', AppColors.ink, 'headings, primary text'),
    ('muted', AppColors.muted, 'secondary text'),
    ('cardMuted', AppColors.cardMuted, 'secondary text on cards'),
    ('tertiary', AppColors.tertiary, 'non-essential info only'),
    ('line', AppColors.line, 'dividers'),
    ('inputBorder', AppColors.inputBorder, 'input borders'),
    ('error', AppColors.error, 'danger'),
    ('yesDot', AppColors.yesDot, 'success'),
    ('mention', AppColors.mention, 'mention in text'),
    ('mentionMe', AppColors.mentionMe, 'mention of me'),
  ];

  static const _categories = <(String, AppTone)>[
    ('Messages, Broadcasts', AppTones.indigo),
    ('Approvals', AppTones.blue),
    ('Tickets, Submissions', AppTones.purple),
    ('Tasks', AppTones.teal),
    ('Medium, Return', AppTones.violet),
    ('High, Urgent, Drop', AppTones.red),
    ('Complete', AppTones.green),
    ('General', AppTones.slate),
  ];

  static const _actions = [
    'Reassign',
    'Reopen',
    'Escalate',
    'Approve',
    'Hold',
    'Complete',
    'Return',
    'Drop',
    'Send',
    'Update',
  ];

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xl),
          const Text('Palette', style: AppText.display),
          _section('Tokens (contrast on white / on surfaceSubtle)'),
          for (final t in _tokens) _TokenRow(t.$1, t.$2, t.$3),
          _section('Buttons'),
          const ButtonSamples(),
          const SizedBox(height: AppSpacing.sm),
          AppButton.primary(label: 'Primary', onPressed: () {}),
          const SizedBox(height: AppSpacing.xs),
          const AppButton.primary(label: 'Primary disabled', onPressed: null),
          const SizedBox(height: AppSpacing.xs),
          AppButton.primary(
            label: 'Primary loading',
            onPressed: () {},
            isLoading: true,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(label: 'Secondary', onPressed: () {}),
          const SizedBox(height: AppSpacing.xs),
          AppButton.text(
            label: 'Text accent',
            onPressed: () {},
            tone: AppTextButtonTone.accent,
          ),
          AppButton.text(label: 'Text muted', onPressed: () {}),
          AppButton.icon(
            icon: Icons.add,
            onPressed: () {},
            semanticLabel: 'Add',
          ),
          _section('Pills'),
          Obx(
            () => AppPillBar(
              pills: [
                for (final k in AppPillKind.values)
                  AppPill(label: k.name, kind: k, count: 3),
              ],
              selected: controller.selectedPill.value,
              onSelected: controller.selectPill,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Row(
            children: [
              AppStatusPill(isYes: true),
              SizedBox(width: AppSpacing.xs),
              AppStatusPill(isYes: false),
              SizedBox(width: AppSpacing.xs),
              AppUnreadBadge(label: '5'),
              SizedBox(width: AppSpacing.xs),
              AppUnreadBadge(label: '5', isMuted: true),
            ],
          ),
          _section('Avatars'),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [for (final h in AvatarPalette.hues) _AvatarSwatch(h)],
          ),
          _section('Chart series'),
          Row(
            children: [
              for (final c in AppChartColors.series)
                Expanded(
                  child: Container(
                    height: 32,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: AppRadius.mdAll,
                    ),
                  ),
                ),
            ],
          ),
          _section('Notification tiles'),
          for (final c in _categories) _ToneTile(c.$1, c.$2),
          _section('Action buttons'),
          AppActionBar(
            layout: AppActionLayout.full,
            items: [
              for (final name in _actions)
                ActionItem(
                  id: name,
                  label: name,
                  icon: actionStyleFor(name).icon,
                  tone: actionStyleFor(name).tone,
                ),
            ],
            onTap: (_) {},
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  static Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xs),
    child: Text(title, style: AppText.subtitle),
  );
}

String _hex(Color c) =>
    '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

class _TokenRow extends StatelessWidget {
  const _TokenRow(this.name, this.color, this.role);

  final String name;
  final Color color;
  final String role;

  @override
  Widget build(BuildContext context) {
    final onWhite = AvatarPalette.contrast(color, AppColors.white);
    final onPage = AvatarPalette.contrast(color, AppColors.surfaceSubtle);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: AppColors.line),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$name  ${_hex(color)}', style: AppText.readableStrong),
                Text(
                  '$role · ${onWhite.toStringAsFixed(1)} / '
                  '${onPage.toStringAsFixed(1)}',
                  style: AppText.caption.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarSwatch extends StatelessWidget {
  const _AvatarSwatch(this.hue);

  final AvatarHue hue;

  @override
  Widget build(BuildContext context) {
    final c = AvatarPalette.colorsOf(hue);
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.background,
            shape: BoxShape.circle,
          ),
          child: Text(
            hue.name.substring(0, 1).toUpperCase(),
            style: AppText.subtitle.copyWith(color: c.foreground),
          ),
        ),
        Text(hue.name, style: AppText.caption),
      ],
    );
  }
}

class _ToneTile extends StatelessWidget {
  const _ToneTile(this.label, this.tone);

  final String label;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: tone.tint, shape: BoxShape.circle),
            child: Icon(Icons.notifications_rounded, color: tone.solid),
          ),
          const SizedBox(width: AppSpacing.xs),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: tone.solid,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              label,
              style: AppText.readableStrong.copyWith(color: tone.strong),
            ),
          ),
        ],
      ),
    );
  }
}
