import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import '../models/emoji_catalog.dart';

/// The "+" of the reaction bar: every emoji of [EmojiCatalog] with a search.
/// Pops with the chosen emoji.
class EmojiPickerSheet extends StatelessWidget {
  const EmojiPickerSheet({super.key, required this.mine});

  final Set<String> mine;

  static Future<String?> show(BuildContext context, {Set<String>? mine}) =>
      AppBottomSheet.show<String>(
        context,
        title: 'React',
        child: EmojiPickerSheet(mine: mine ?? const {}),
      );

  @override
  Widget build(BuildContext context) {
    final query = ''.obs;
    final maxList = MediaQuery.sizeOf(context).height * 0.4;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          hint: 'Search emoji',
          leading: const Icon(Icons.search, size: 20, color: AppColors.muted),
          onChanged: (v) => query.value = v,
        ),
        const SizedBox(height: AppSpacing.xs),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: math.max(maxList, 160)),
          child: Obx(() {
            final list = EmojiCatalog.search(query.value);
            if (list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Center(
                  child: Text('No emoji found', style: AppText.readable),
                ),
              );
            }
            return GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: AppSpacing.minTapTarget,
                mainAxisExtent: AppSpacing.minTapTarget,
              ),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final e = list[i].emoji;
                return Semantics(
                  button: true,
                  selected: mine.contains(e),
                  label: e,
                  onTap: () => Navigator.of(context).pop(e),
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(e),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: mine.contains(e) ? AppColors.primaryTint : null,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        e,
                        textScaler: MediaQuery.textScalerOf(
                          context,
                        ).clamp(maxScaleFactor: 1.2),
                        style: const TextStyle(fontSize: 24, height: 1.2),
                      ),
                    ),
                  ),
                );
              },
            );
          }),
        ),
      ],
    );
  }
}
