import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'models/qr_models.dart';
import 'qr_controller.dart';
import 'widgets/qr_kind_switch.dart';

class QrView extends GetView<QrController> {
  const QrView({super.key});

  static const _wholeOrganisation = 'Whole organisation';
  static const _pickHint = 'Pick a branch for its own QR.';

  static String branchHint(String name) =>
      'Scans are noted as coming through $name.';

  static String _tabLabel(QrKind kind) =>
      kind == QrKind.person ? 'My QR' : 'Organisation QR';

  static Rect? _origin(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(
      () => AppStateView(
        state: c.state.value,
        onRetry: c.load,
        errorMessage: c.errorMessage.value,
        emptyTitle: 'No QR code available',
        emptyMessage: 'There is no QR code you can show right now.',
        loadingChild: const Center(child: AppQrLoading()),
        child: _Content(controller: c),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.controller});

  final QrController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final data = c.current;
      final isOrganisation = c.selected.value == QrKind.organisation;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.kinds.length > 1) ...[
            QrKindSwitch(
              labels: [for (final kind in c.kinds) QrView._tabLabel(kind)],
              selected: c.kinds.indexOf(c.selected.value),
              onSelected: (i) => c.selectKind(c.kinds[i]),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (isOrganisation && c.branches.isNotEmpty) ...[
            AppFilterChips(
              chips: [
                const AppFilterChip(label: QrView._wholeOrganisation),
                for (final b in c.branches) AppFilterChip(label: b.label),
              ],
              selected: c.branch.value == null
                  ? 0
                  : c.branches.indexOf(c.branch.value!) + 1,
              onSelected: (i) =>
                  c.selectBranch(i == 0 ? null : c.branches[i - 1]),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              c.branch.value == null
                  ? QrView._pickHint
                  : QrView.branchHint(c.branch.value!.name),
              style: AppText.caption.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (data != null) ...[
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AppQrShareCard(
                      data: data,
                      onCopy: c.copyCode,
                      width: math.min(
                        constraints.maxWidth,
                        AppSpacing.qrCardWidth,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Builder(
              builder: (context) => AppButton.primary(
                label: 'Share',
                leadingIcon: Icons.ios_share,
                isCentered: true,
                isLoading: c.isSharing.value,
                onPressed: () => c.shareImage(QrView._origin(context)),
              ),
            ),
            if (c.canRegenerate) ...[
              const SizedBox(height: AppSpacing.xs),
              Builder(
                builder: (context) => AppButton.text(
                  label: 'Regenerate QR code',
                  leadingIcon: Icons.refresh_rounded,
                  tone: AppTextButtonTone.ink,
                  onPressed: c.isRegenerating.value
                      ? null
                      : () async {
                          final isConfirmed = await AppConfirmDialog.ask(
                            context,
                            title: 'Regenerate your QR code?',
                            message:
                                'Your current QR code and Connectum code will '
                                'stop working. Anyone who saved or printed it '
                                'will need the new one.',
                            confirmLabel: 'Regenerate',
                            isDanger: true,
                          );
                          if (isConfirmed) await c.regenerate();
                        },
                ),
              ),
            ],
          ],
        ],
      );
    });
  }
}
