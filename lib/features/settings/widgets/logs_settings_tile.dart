import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_row_highlight.dart';
import '../../../core/widgets/app_switch.dart';
import '../../profile/widgets/profile_row.dart';
import '../logs_controller.dart';

/// The "Logs" section: one tile, tap the left part for the options sheet, the
/// switch on the right turns logging on or off.
class LogsSettingsTile extends StatelessWidget {
  const LogsSettingsTile({super.key, required this.controller});

  final LogsController controller;

  static const _minHeight = 64.0;
  static const subtitle = 'Record app activity for support';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.xxs,
            0,
            AppSpacing.xxs,
            AppSpacing.sm,
          ),
          child: Text('LOGS', style: AppText.eyebrow),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: AppRadius.cardAll,
            border: Border.all(color: AppColors.line),
          ),
          child: Obx(() {
            final s = controller.state.value;
            return ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _minHeight),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: 'Log options, $subtitle',
                        excludeSemantics: true,
                        onTap: () => controller.openOptions(context),
                        child: AppRowHighlight(
                          bleed: 0,
                          onTap: () => controller.openOptions(context),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.sm,
                            ),
                            child: Row(
                              children: [
                                const ProfileIconTile(
                                  icon: Icons.bug_report_outlined,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: const [
                                      Text(
                                        'Logs',
                                        maxLines: 1,
                                        style: AppText.rowTitle,
                                      ),
                                      Text(
                                        subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppText.rowCaption,
                                      ),
                                      // Room for a future progress bar.
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const VerticalDivider(
                      width: 1,
                      thickness: 1,
                      indent: AppSpacing.sm,
                      endIndent: AppSpacing.sm,
                      color: AppColors.line,
                    ),
                    Semantics(
                      toggled: s.isEnabled,
                      label: 'Logs, switch, ${s.isEnabled ? 'on' : 'off'}',
                      excludeSemantics: true,
                      onTap: () =>
                          controller.setEnabled(context, !s.isEnabled),
                      child: SizedBox(
                        width: 72,
                        child: Center(
                          child: AppSwitch(
                            value: s.isEnabled,
                            onChanged: (v) => controller.setEnabled(context, v),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.xxs,
            AppSpacing.xs,
            AppSpacing.xxs,
            0,
          ),
          child: Text(
            'Logs include technical details, API requests and responses '
            '(passwords, tokens and keys are hidden) and your email. '
            'Share them only with support.',
            style: AppText.caption,
          ),
        ),
      ],
    );
  }
}
