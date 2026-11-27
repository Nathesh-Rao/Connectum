import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import '../../../data/smart_view/preview/sv_preview_parsers.dart';

/// The text of a Word file or a slide deck, with the banner that says it is
/// only the text. Plain text only: nothing in the file is opened or loaded.
class SvDocViewer extends StatefulWidget {
  const SvDocViewer({super.key, required this.doc, required this.onOpenWith});

  final SvDocText doc;
  final VoidCallback onOpenWith;

  @override
  State<SvDocViewer> createState() => _SvDocViewerState();
}

class _SvDocViewerState extends State<SvDocViewer> {
  int _slide = 0;

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    final pages = doc.pages;
    final blocks = pages.isEmpty ? <SvDocBlock>[] : pages[_slide];
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: AppColors.violetTint,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xxs,
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Text preview — open the file for full formatting',
                  style: AppText.supporting,
                ),
              ),
              AppButton.text(
                label: 'Open with…',
                tone: AppTextButtonTone.accent,
                onPressed: widget.onOpenWith,
              ),
            ],
          ),
        ),
        Expanded(
          child: blocks.isEmpty
              ? const Center(
                  child: Text('No text found', style: AppText.supporting),
                )
              : ListView.builder(
                  key: const ValueKey('sv-doc-blocks'),
                  padding: const EdgeInsets.all(AppSv.fileTextPad),
                  itemCount: blocks.length,
                  itemBuilder: (context, i) => _Block(block: blocks[i]),
                ),
        ),
        if (doc.isSlides && pages.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppButton.icon(
                  icon: Icons.chevron_left,
                  semanticLabel: 'Previous slide',
                  onPressed: _slide > 0 ? () => setState(() => _slide--) : null,
                ),
                Text(
                  'Slide ${_slide + 1} / ${pages.length}',
                  key: const ValueKey('sv-slide-counter'),
                  style: AppText.readableStrong,
                ),
                AppButton.icon(
                  icon: Icons.chevron_right,
                  semanticLabel: 'Next slide',
                  onPressed: _slide < pages.length - 1
                      ? () => setState(() => _slide++)
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.block});

  final SvDocBlock block;

  @override
  Widget build(BuildContext context) {
    final isHeading = block.style == SvBlockStyle.heading;
    final style = AppText.readable.copyWith(
      fontWeight: isHeading || block.isBold ? FontWeight.w700 : null,
      fontSize: isHeading ? 16 : null,
      color: AppColors.ink,
    );
    final text = block.style == SvBlockStyle.list
        ? '•  ${block.text}'
        : block.text;
    return Padding(
      padding: EdgeInsets.only(
        bottom: AppSpacing.sm,
        top: isHeading ? AppSpacing.xs : 0,
      ),
      child: SelectableText(text, style: style),
    );
  }
}
