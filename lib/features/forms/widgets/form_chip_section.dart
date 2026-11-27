import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';

/// A heading over a wrapping flow of chips. With [collapseAfter] set and more
/// chips than that, the rest hide behind a "Show all" link.
class FormChipSection extends StatefulWidget {
  const FormChipSection({
    super.key,
    required this.label,
    required this.chips,
    this.collapseAfter,
  });

  final String label;
  final List<Widget> chips;
  final int? collapseAfter;

  @override
  State<FormChipSection> createState() => _FormChipSectionState();
}

class _FormChipSectionState extends State<FormChipSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final limit = widget.collapseAfter;
    final isCollapsed =
        limit != null && widget.chips.length > limit && !_isExpanded;
    final chips = isCollapsed
        ? widget.chips.take(limit).toList()
        : widget.chips;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            widget.label,
            style: const TextStyle(
              fontFamily: AppText.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.3,
              color: AppColors.ink,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.chipGap,
          runSpacing: AppSpacing.chipRunGap,
          children: chips,
        ),
        if (isCollapsed)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: InkWell(
              onTap: () => setState(() => _isExpanded = true),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppSpacing.minTapTarget,
                ),
                child: const Center(
                  widthFactor: 1,
                  child: Text(
                    'Show all',
                    style: TextStyle(
                      fontFamily: AppText.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: AppColors.muted,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
