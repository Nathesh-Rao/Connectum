import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_sv.dart';
import '../../../core/theme/app_text.dart';
import '../../../data/smart_view/preview/sv_preview_parsers.dart';
import '../../../data/smart_view/sv_file.dart';

/// The entries of a zip with their sizes and the totals. Nothing is
/// extracted or opened.
class SvZipViewer extends StatelessWidget {
  const SvZipViewer({super.key, required this.listing});

  final SvZipListing listing;

  @override
  Widget build(BuildContext context) {
    final cut = listing.totalFiles - listing.entries.length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${listing.totalFiles} files · '
              '${SvFile.formatSize(listing.totalSize).isEmpty ? '0 B' : SvFile.formatSize(listing.totalSize)}',
              key: const ValueKey('sv-zip-total'),
              style: AppText.supporting,
            ),
          ),
        ),
        const Divider(height: 1, thickness: 1, color: AppSv.hairline),
        Expanded(
          child: ListView.separated(
            key: const ValueKey('sv-zip-entries'),
            itemCount: listing.entries.length + (cut > 0 ? 1 : 0),
            separatorBuilder: (context, i) =>
                const Divider(height: 1, thickness: 1, color: AppSv.hairline),
            itemBuilder: (context, i) {
              if (i == listing.entries.length) {
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Text(
                    '+ $cut more files — Download for the full list',
                    style: AppText.supporting,
                  ),
                );
              }
              final e = listing.entries[i];
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.name,
                        style: AppSv.fileChipName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      SvFile.formatSize(e.size).isEmpty
                          ? '0 B'
                          : SvFile.formatSize(e.size),
                      style: AppSv.fileChipSize,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
