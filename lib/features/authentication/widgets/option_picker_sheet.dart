import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_text_field.dart';

class OptionPickerSheet extends StatefulWidget {
  const OptionPickerSheet({super.key, required this.options});

  final List<String> options;

  @override
  State<OptionPickerSheet> createState() => _OptionPickerSheetState();
}

class _OptionPickerSheetState extends State<OptionPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final shown = widget.options
        .where((o) => o.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          hint: 'Search',
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 320,
          child: shown.isEmpty
              ? const Center(child: Text('No matches', style: AppText.readable))
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (context, i) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(shown[i]),
                    child: Container(
                      height: 48,
                      alignment: Alignment.centerLeft,
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: AppColors.line),
                        ),
                      ),
                      child: Text(shown[i], style: AppText.body),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
