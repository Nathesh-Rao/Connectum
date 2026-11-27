import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/features/share/share.dart';
import '../../../data/smart_view/sv_file.dart';
import '../sv_file_preview_controller.dart';
import '../viewers/sv_file_card.dart';
import '../viewers/sv_sheet_skeleton.dart';
import '../viewers/sv_viewers.dart';
import 'sv_file_chips.dart';

/// The file viewer of a record: a centred dialog (78% of the height) that
/// grows to full screen and back. Opens with a short fade and scale; back
/// closes it, or first leaves full screen.
class SvFilePreviewDialog {
  SvFilePreviewDialog._();

  static Future<void> show(
    BuildContext context,
    SvFilePreviewController controller, {
    SvViewers viewers = const SvViewers(),
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierLabel: 'File preview',
      barrierDismissible: true,
      barrierColor: AppColors.ink.withValues(alpha: AppSv.fileScrim),
      transitionDuration: AppDurations.smartControls,
      pageBuilder: (context, _, _) =>
          SvFilePreviewHost(controller: controller, viewers: viewers),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: AppCurves.out);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(
              begin: AppSv.fileOpenScale,
              end: 1,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

/// Starts the controller when the dialog opens and closes it when it goes.
class SvFilePreviewHost extends StatefulWidget {
  const SvFilePreviewHost({
    super.key,
    required this.controller,
    this.viewers = const SvViewers(),
  });

  final SvFilePreviewController controller;
  final SvViewers viewers;

  @override
  State<SvFilePreviewHost> createState() => _SvFilePreviewHostState();
}

class _SvFilePreviewHostState extends State<SvFilePreviewHost> {
  @override
  void initState() {
    super.initState();
    widget.controller.onReady();
  }

  @override
  void dispose() {
    widget.controller.onClose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SvFilePreviewBody(controller: widget.controller, viewers: widget.viewers);
}

class SvFilePreviewBody extends StatelessWidget {
  const SvFilePreviewBody({
    super.key,
    required this.controller,
    this.viewers = const SvViewers(),
  });

  final SvFilePreviewController controller;
  final SvViewers viewers;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    return Obx(() {
      final isFull = c.isFull.value;
      final inset = isFull ? 0.0 : AppSv.fileDialogInset;
      final vertical = isFull
          ? 0.0
          : size.height * (1 - AppSv.fileDialogHeight) / 2;
      return PopScope(
        canPop: !isFull,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) c.toggleFull();
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (!c.isFull.value) Navigator.of(context).maybePop();
                },
              ),
            ),
            AnimatedContainer(
              duration: AppDurations.fileFull,
              curve: AppCurves.out,
              margin: EdgeInsets.symmetric(
                horizontal: inset,
                vertical: vertical,
              ),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(
                  isFull ? 0 : AppSv.fileDialogRadius,
                ),
                boxShadow: isFull ? const [] : AppSv.fileDialogShadow,
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                key: const ValueKey('sv-file-dialog'),
                color: AppColors.white,
                child: AnimatedPadding(
                  duration: AppDurations.fileFull,
                  curve: AppCurves.out,
                  padding: isFull ? pad : EdgeInsets.zero,
                  child: Column(
                    children: [
                      _Header(controller: c),
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: AppSv.hairline,
                      ),
                      Expanded(
                        child: Obx(
                          () => PageView.builder(
                            key: const ValueKey('sv-file-pages'),
                            controller: c.pages,
                            physics: c.current.isZoomed.value
                                ? const NeverScrollableScrollPhysics()
                                : const PageScrollPhysics(),
                            itemCount: c.files.length,
                            onPageChanged: c.onPage,
                            itemBuilder: (context, i) => _FilePage(
                              load: c.loads[i],
                              controller: c,
                              viewers: viewers,
                              index: i,
                            ),
                          ),
                        ),
                      ),
                      if (c.files.length > 1 && c.files.length <= 8)
                        _Dots(controller: c),
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: AppSv.hairline,
                      ),
                      _BottomBar(controller: c),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final SvFilePreviewController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SizedBox(
      height: AppSv.fileBarHeight,
      child: Row(
        children: [
          const SizedBox(width: AppSpacing.sm),
          Obx(() {
            final file = c.current.file;
            return Container(
              width: AppSv.fileHeaderCircle,
              height: AppSv.fileHeaderCircle,
              decoration: BoxDecoration(
                color: file.kind.palette.background,
                shape: BoxShape.circle,
              ),
              child: Icon(
                svFileIcon(file.kind),
                size: AppSv.fileHeaderIcon,
                color: file.kind.palette.foreground,
              ),
            );
          }),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Obx(() {
              final file = c.current.file;
              final line = file.headerText(
                position: c.index.value + 1,
                total: c.files.length,
              );
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    SvFile.middleEllipsis(file.name, 30),
                    key: const ValueKey('sv-file-title'),
                    style: AppSv.fileTitle,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                  ),
                  Text(
                    line,
                    key: const ValueKey('sv-file-subtitle'),
                    style: AppSv.fileChipSize,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              );
            }),
          ),
          Obx(
            () => AppButton.icon(
              key: const ValueKey('sv-file-full'),
              icon: c.isFull.value
                  ? Icons.close_fullscreen_rounded
                  : Icons.open_in_full_rounded,
              semanticLabel: c.isFull.value
                  ? 'Exit full screen'
                  : 'Full screen',
              onPressed: c.toggleFull,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'File actions',
            icon: const Icon(Icons.more_vert, color: AppColors.ink),
            color: AppColors.white,
            onSelected: (v) {
              switch (v) {
                case 'download':
                  c.download();
                case 'open':
                  c.openWith();
                case 'share':
                  c.share();
                case 'wrap':
                  c.isWrap.toggle();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'download', child: Text('Download')),
              const PopupMenuItem(value: 'open', child: Text('Open with…')),
              const PopupMenuItem(value: 'share', child: Text('Share')),
              if (c.current.file.viewer == SvViewer.text)
                CheckedPopupMenuItem(
                  value: 'wrap',
                  checked: c.isWrap.value,
                  child: const Text('Wrap lines'),
                ),
            ],
          ),
          AppButton.icon(
            icon: Icons.close,
            semanticLabel: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: AppSpacing.xxs),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.controller});

  final SvFilePreviewController controller;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Obx(
      () => Row(
        key: const ValueKey('sv-file-dots'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < controller.files.length; i++)
            Container(
              width: AppSv.fileDot,
              height: AppSv.fileDot,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == controller.index.value
                    ? AppColors.primary
                    : AppColors.primaryTint,
              ),
            ),
        ],
      ),
    ),
  );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.controller});

  final SvFilePreviewController controller;

  /// The file is made local first (progress shows on its page), then the
  /// picker opens over the dialog; sending leaves the dialog where it is.
  Future<void> _shareToConnectum(BuildContext context) async {
    final share = controller.repo.connectumShare;
    if (share == null) return;
    final file = await controller.fileForConnectum();
    if (file == null || !context.mounted) return;
    await showShareToConnectum(context, repository: share, files: [file]);
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Obx(() {
        final isBusy = c.current.phase.value == SvFilePhase.loading;
        // Without sharing set up, the two buttons keep their own look.
        if (!c.canShareToConnectum) {
          return Row(
            children: [
              Expanded(
                child: AppButton.primary(
                  key: const ValueKey('sv-file-download'),
                  label: 'Download',
                  leadingIcon: Icons.download_outlined,
                  isCentered: true,
                  onPressed: isBusy ? null : c.download,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton.secondary(
                  key: const ValueKey('sv-file-open'),
                  label: 'Open with…',
                  leadingIcon: Icons.open_in_new,
                  onPressed: isBusy ? null : c.openWith,
                ),
              ),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppButton.primary(
              key: const ValueKey('sv-file-share-connectum'),
              label: 'Share to Connectum',
              leadingIcon: Icons.send_rounded,
              isCentered: true,
              onPressed: isBusy ? null : () => _shareToConnectum(context),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: AppButton.secondary(
                    key: const ValueKey('sv-file-download'),
                    label: 'Download',
                    leadingIcon: Icons.download_outlined,
                    onPressed: isBusy ? null : c.download,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppButton.secondary(
                    key: const ValueKey('sv-file-open'),
                    label: 'Open with…',
                    leadingIcon: Icons.open_in_new,
                    onPressed: isBusy ? null : c.openWith,
                  ),
                ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

class _FilePage extends StatelessWidget {
  const _FilePage({
    required this.load,
    required this.controller,
    required this.viewers,
    required this.index,
  });

  final SvFileLoad load;
  final SvFilePreviewController controller;
  final SvViewers viewers;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      switch (load.phase.value) {
        case SvFilePhase.loading:
          return _Progress(load: load, onCancel: controller.cancel);
        case SvFilePhase.error:
          return _Problem(load: load, onRetry: controller.retry);
        case SvFilePhase.ready:
          final Widget body = load.isShowable.value
              ? viewers.build(
                  context,
                  controller,
                  load,
                  controller.index.value == index,
                )
              : SvFileCard(file: load.file);
          if (!load.isMaybeStale.value) return body;
          return Column(
            children: [
              const _StaleNote(),
              Expanded(child: body),
            ],
          );
        case SvFilePhase.idle:
          return SvFileCard(file: load.file);
      }
    });
  }
}

class _StaleNote extends StatelessWidget {
  const _StaleNote();

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('sv-file-stale'),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xs,
    ),
    child: Text(
      "Couldn't check for a newer version. This copy may be out of date.",
      style: AppSv.fileChipSize,
      textAlign: TextAlign.center,
    ),
  );
}

class _Progress extends StatelessWidget {
  const _Progress({required this.load, required this.onCancel});

  final SvFileLoad load;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Obx(() => _body());

  Widget _body() {
    if (load.isParsing.value) {
      return const SvSheetSkeleton(key: ValueKey('sv-sheet-skeleton'));
    }
    final value = load.progress.value;
    final known = value > 0;
    final bytes = load.transfer.value;
    final detail = bytes.isStarted ? bytes.text : '';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: known
                ? 'Downloading ${(value * 100).round()} percent'
                : 'Downloading',
            child: SizedBox(
              width: AppSv.fileRing,
              height: AppSv.fileRing,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: AppSv.fileRing,
                    height: AppSv.fileRing,
                    child: CircularProgressIndicator(
                      value: known ? value : null,
                      strokeWidth: AppSv.fileRingStroke,
                      color: AppColors.primary,
                      backgroundColor: AppColors.primaryTint,
                    ),
                  ),
                  if (known)
                    Text(
                      '${(value * 100).floor()}%',
                      style: AppText.readableStrong,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            SvFile.middleEllipsis(load.file.name, 30),
            style: AppText.readable,
            maxLines: 1,
          ),
          if (detail.isNotEmpty)
            Padding(
              key: const ValueKey('sv-file-bytes'),
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                detail,
                style: AppSv.fileChipSize,
                maxLines: 2,
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.text(label: 'Cancel', onPressed: onCancel),
        ],
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.load, required this.onRetry});

  final SvFileLoad load;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isRetryable =
        load.problem.value != SvFileProblem.forbidden &&
        load.problem.value != SvFileProblem.notFound;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: AppSv.fileCircleIcon,
              color: AppColors.tertiary,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              SvFile.middleEllipsis(load.file.name, 30),
              style: AppText.bodyStrong,
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              load.message.value ?? "The file couldn't be loaded.",
              style: AppText.supporting,
              textAlign: TextAlign.center,
            ),
            if (isRetryable) ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton.text(
                label: 'Retry',
                tone: AppTextButtonTone.accent,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
