import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../sv_file_preview_controller.dart';
import 'sv_file_card.dart';

/// A PDF from the cached temp file, pages scrolled vertically with pinch zoom
/// and drawn lazily by pdfrx. A password-protected or broken PDF shows the
/// calm "can't be previewed" card.
class SvPdfViewer extends StatefulWidget {
  const SvPdfViewer({super.key, required this.load});

  final SvFileLoad load;

  @override
  State<SvPdfViewer> createState() => _SvPdfViewerState();
}

class _SvPdfViewerState extends State<SvPdfViewer> {
  final _controller = PdfViewerController();
  int _page = 1;
  int _count = 0;

  void _zoomed() {
    if (!_controller.isReady) return;
    widget.load.isZoomed.value =
        _controller.value.getMaxScaleOnAxis() > _controller.minScale * 1.02;
  }

  @override
  void dispose() {
    widget.load.isZoomed.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PdfViewer.file(
          widget.load.local!.path,
          controller: _controller,
          params: PdfViewerParams(
            backgroundColor: AppColors.surfaceSubtle,
            onViewerReady: (doc, c) =>
                setState(() => _count = doc.pages.length),
            onPageChanged: (n) {
              if (n != null && n != _page) setState(() => _page = n);
            },
            onInteractionEnd: (_) => _zoomed(),
            loadingBannerBuilder: (context, got, total) => const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
            errorBannerBuilder: (context, error, stack, ref) =>
                SvFileCard.pdfProblem(file: widget.load.file),
          ),
        ),
        if (_count > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: AppSpacing.sm,
            child: Center(
              child: SvPdfChrome(
                page: _page,
                count: _count,
                onGoTo: (n) => _controller.goToPage(pageNumber: n),
              ),
            ),
          ),
      ],
    );
  }
}

/// The slim bottom overlay: previous, "3 / 12" (tap: go to a page), next.
class SvPdfChrome extends StatelessWidget {
  const SvPdfChrome({
    super.key,
    required this.page,
    required this.count,
    required this.onGoTo,
  });

  final int page;
  final int count;
  final ValueChanged<int> onGoTo;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Step(
            icon: Icons.chevron_left,
            label: 'Previous page',
            onTap: page > 1 ? () => onGoTo(page - 1) : null,
          ),
          GestureDetector(
            key: const ValueKey('sv-pdf-pill'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _goTo(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                '$page / $count',
                style: AppText.readableStrong.copyWith(color: AppColors.white),
              ),
            ),
          ),
          _Step(
            icon: Icons.chevron_right,
            label: 'Next page',
            onTap: page < count ? () => onGoTo(page + 1) : null,
          ),
        ],
      ),
    );
  }

  void _goTo(BuildContext context) {
    AppBottomSheet.show<void>(
      context,
      title: 'Go to page',
      child: SvGoToPage(count: count, onGoTo: onGoTo),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(
          icon,
          color: onTap == null
              ? AppColors.white.withValues(alpha: 0.4)
              : AppColors.white,
        ),
      ),
    ),
  );
}

/// The "Go to page" sheet body: a number field and Go.
class SvGoToPage extends StatefulWidget {
  const SvGoToPage({super.key, required this.count, required this.onGoTo});

  final int count;
  final ValueChanged<int> onGoTo;

  @override
  State<SvGoToPage> createState() => _SvGoToPageState();
}

class _SvGoToPageState extends State<SvGoToPage> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit([String? _]) {
    final n = int.tryParse(_text.text.trim());
    if (n == null || n < 1 || n > widget.count) {
      setState(() => _error = 'Enter a page from 1 to ${widget.count}');
      return;
    }
    Navigator.of(context).pop();
    widget.onGoTo(n);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AppTextField(
        controller: _text,
        hint: 'Page (1 to ${widget.count})',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textInputAction: TextInputAction.go,
        autofocus: true,
        errorText: _error,
        onSubmitted: _submit,
      ),
      const SizedBox(height: AppSpacing.md),
      AppButton.primary(label: 'Go', isCentered: true, onPressed: _submit),
    ],
  );
}
