import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/app_text_field.dart';
import '../connect_controller.dart';

class ManualPane extends StatelessWidget {
  const ManualPane({super.key, required this.controller});

  final ConnectController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Search by enterprise name or Connectum ID.',
          style: AppText.readable,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          controller: c.query,
          focusNode: c.queryFocus,
          hint: 'Enterprise name or ID',
          minHeight: AppSpacing.sheetFieldHeight,
          borderColor: AppColors.line,
          textInputAction: TextInputAction.search,
          onChanged: c.onQueryChanged,
          onSubmitted: (_) => c.submitManual(),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: SingleChildScrollView(
            child: Obx(() {
              if (c.isSearching.value) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Center(
                    child: Text('Searching…', style: AppText.readable),
                  ),
                );
              }
              final error = c.searchMessage.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (error != null) Text(error, style: AppText.readable),
                  for (final r in c.results)
                    AppListRow(
                      title: r.name,
                      subtitle: r.city.isEmpty ? r.id : '${r.city} · ${r.id}',
                      trailing: const Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: AppColors.rowChevron,
                      ),
                      onTap: () => c.selectHit(r),
                    ),
                ],
              );
            }),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton.secondary(
          label: 'Scan QR code instead',
          icon: Icons.qr_code_scanner,
          onPressed: c.showScanner,
        ),
      ],
    );
  }
}
