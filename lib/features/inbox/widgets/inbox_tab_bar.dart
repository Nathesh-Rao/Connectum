import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_inbox.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_tones.dart';
import '../inbox_controller.dart';
import '../models/inbox_tab.dart';

/// The Inbox's segmented tab bar: a rounded track with a thumb that slides
/// under the chosen tab and follows the page while it is swiped. The tabs
/// come from [InboxTabs.all].
class InboxTabBar extends StatelessWidget {
  const InboxTabBar({super.key, required this.controller, required this.pager});

  final InboxController controller;

  /// The pages' controller, owned by the widget that builds the PageView.
  final PageController pager;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    const tabs = InboxTabs.all;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.xs,
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppInbox.trackFill,
          borderRadius: AppRadius.pillAll,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppInbox.tabTrackPad),
          child: SizedBox(
            height: AppInbox.tabHeight,
            child: LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth / tabs.length;
                return Obx(() {
                  final selected = c.tabIndex.value;
                  final counts = [for (final t in tabs) c.badgeOf(t.id)];
                  final pills = [for (final t in tabs) c.pillOf(t.id)];
                  return AnimatedBuilder(
                    animation: pager,
                    builder: (context, _) {
                      final pos = _position(pager, selected, tabs.length);
                      return Stack(
                        children: [
                          PositionedDirectional(
                            start: pos * w,
                            top: 0,
                            bottom: 0,
                            width: w,
                            child: const DecoratedBox(
                              key: ValueKey('inbox-tab-thumb'),
                              decoration: BoxDecoration(
                                color: AppInbox.thumbFill,
                                borderRadius: AppRadius.pillAll,
                                boxShadow: AppInbox.thumbShadow,
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              for (var i = 0; i < tabs.length; i++)
                                Expanded(
                                  child: _Tab(
                                    def: tabs[i],
                                    isSelected: selected == i,
                                    nearness: (1 - (pos - i).abs()).clamp(
                                      0.0,
                                      1.0,
                                    ),
                                    count: counts[i],
                                    pill: pills[i],
                                    onTap: () => c.selectTab(i),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      );
                    },
                  );
                });
              },
            ),
          ),
        ),
      ),
    );
  }

  /// The page as a fraction while it moves; the tab shown before it is built.
  static double _position(PageController p, int selected, int n) {
    if (p.hasClients && p.positions.length == 1) {
      final pos = p.position;
      if (pos.hasPixels && pos.hasContentDimensions) {
        final v = p.page;
        if (v != null) return v.clamp(0.0, n - 1.0);
      }
    }
    return selected.toDouble();
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.def,
    required this.isSelected,
    required this.nearness,
    required this.count,
    required this.pill,
    required this.onTap,
  });

  final InboxTabDef def;
  final bool isSelected;
  final double nearness;
  final int count;

  /// The quiet total after the label (Records); empty for none.
  final String pill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = Color.lerp(AppInbox.tabMuted, AppInbox.tabInk, nearness)!;
    final accent = Color.lerp(AppInbox.tabMuted, AppColors.primary, nearness)!;
    final spoken = [
      def.label,
      if (pill.isNotEmpty && count == 0) pill,
      if (count > 0) '$count waiting for you',
    ].join(', ');
    final labelStyle = AppText.bodyStrong.copyWith(color: ink, height: 1.2);
    return Semantics(
      button: true,
      selected: isSelected,
      label: spoken,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, box) {
            final scaler = MediaQuery.textScalerOf(context);
            final dir = Directionality.of(context);
            double textW(String t, TextStyle st, {bool isScaled = true}) {
              final tp = TextPainter(
                text: TextSpan(text: t, style: st),
                textDirection: dir,
                textScaler: isScaled ? scaler : TextScaler.noScaling,
                maxLines: 1,
              )..layout();
              final w = tp.width;
              tp.dispose();
              return w;
            }

            const pad = AppSpacing.xs * 2;
            const gap = AppSpacing.xxs;
            var need = textW(def.label, labelStyle);
            if (pill.isNotEmpty) {
              need += gap + _CountPill.widthOf(pill, textW);
            }
            // The icon goes before the label is cut.
            final hasIcon = need + AppInbox.tabIcon + gap + pad <= box.maxWidth;
            return Center(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: hasIcon ? AppSpacing.xs : AppSpacing.xxs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasIcon) ...[
                      Icon(
                        isSelected ? def.selectedIcon : def.icon,
                        size: AppInbox.tabIcon,
                        color: accent,
                      ),
                      const SizedBox(width: gap),
                    ],
                    Flexible(
                      child: Text(
                        def.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: labelStyle,
                      ),
                    ),
                    if (pill.isNotEmpty) ...[
                      const SizedBox(width: gap),
                      _CountPill(
                        key: ValueKey('inbox-${def.id.name}-count'),
                        label: pill,
                        nearness: nearness,
                        tone: def.id == InboxTab.approvals
                            ? (pill == '0'
                                  ? AppInbox.emptyCountTone
                                  : AppInbox.approvalsCountTone)
                            : AppInbox.recordsCountTone,
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A tab's count, small and quiet: a tint of the tab's own tone.
class _CountPill extends StatelessWidget {
  const _CountPill({
    super.key,
    required this.label,
    required this.nearness,
    required this.tone,
  });

  final String label;
  final double nearness;
  final AppTone tone;

  static const _style = TextStyle(
    fontFamily: AppText.fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  static double widthOf(
    String label,
    double Function(String, TextStyle, {bool isScaled}) w,
  ) => (w(label, _style) + AppSpacing.xs * 1.5).clamp(
    AppSpacing.unreadBadge,
    double.infinity,
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.lerp(
          AppColors.white,
          tone.tintStrong,
          0.4 + 0.6 * nearness,
        ),
        borderRadius: AppRadius.pillAll,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppSpacing.unreadBadge,
          minHeight: AppSpacing.unreadBadge,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs * 0.75),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              label,
              maxLines: 1,
              style: _style.copyWith(color: tone.strong),
            ),
          ),
        ),
      ),
    );
  }
}
