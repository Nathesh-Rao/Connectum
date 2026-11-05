import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';

/// Keeps one broken field from taking the form down. After a field is built,
/// a subtree that ended in an error widget is swapped for a quiet row; the
/// error itself is still reported by the framework, and the id and type of the
/// field (never its value) are logged here.
class FormFieldBoundary extends StatefulWidget {
  const FormFieldBoundary({
    super.key,
    required this.id,
    required this.type,
    required this.child,
  });

  final String id;
  final String type;
  final Widget child;

  @override
  State<FormFieldBoundary> createState() => _FormFieldBoundaryState();
}

class _FormFieldBoundaryState extends State<FormFieldBoundary> {
  bool _isBroken = false;

  @override
  Widget build(BuildContext context) {
    if (_isBroken) return const _BrokenField();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    return widget.child;
  }

  void _check() {
    if (!mounted || _isBroken) return;
    var hasError = false;
    void visit(Element e) {
      if (hasError) return;
      if (e.widget is ErrorWidget) {
        hasError = true;
        return;
      }
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    if (!hasError) return;
    debugPrint('Form field "${widget.id}" (${widget.type}) could not be built');
    setState(() => _isBroken = true);
  }
}

class _BrokenField extends StatelessWidget {
  const _BrokenField();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Row(
      children: [
        const Icon(Icons.info_outline, size: 16, color: AppColors.muted),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            "This field can't be shown",
            style: AppText.caption.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    ),
  );
}
