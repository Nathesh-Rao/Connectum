import 'package:flutter/material.dart';

import '../data/app_countries.dart';
import '../data/country_lookup.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'app_text_field.dart';

/// Body of the country-code bottom sheet: search by name, ISO code or dial
/// code. Pops the chosen [AppCountry].
class CountryPickerSheet extends StatefulWidget {
  const CountryPickerSheet({super.key});

  @override
  State<CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<CountryPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final shown = CountryLookup.search(_query);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          hint: 'Search country or code',
          minHeight: AppSpacing.sheetFieldHeight,
          borderColor: AppColors.line,
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 320,
          child: shown.isEmpty
              ? const Center(child: Text('No matches', style: AppText.readable))
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final c = shown[i];
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(c),
                      child: Container(
                        height: 48,
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: AppColors.line),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(c.flag, style: AppText.subtitle),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(child: Text(c.name, style: AppText.body)),
                            Text('+${c.dial}', style: AppText.readable),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
