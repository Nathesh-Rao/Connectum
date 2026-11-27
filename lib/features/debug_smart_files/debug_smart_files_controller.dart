import 'package:get/get.dart';

import '../../core/debug/seed_smart_view.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/features/smart_view/smart_view.dart';
import '../../data/smart_view/models/sv_row.dart';
import '../../data/smart_view/models/sv_source.dart';
import '../../data/smart_view/sv_file.dart';

/// The Smart View file chips and viewer on the Leave request demo rows and a
/// fake downloader, no server. Debug builds only (see "Before release" in
/// CLAUDE.md).
class DebugSmartFilesController extends GetxController {
  DebugSmartFilesController({required this.files});

  final SvFileRepository files;
  late final SvSource source = SeedSmartView.leaveSource();

  /// One row per demo pattern: one picture, two files, five files, the
  /// damaged scan, four files.
  late final List<SvRow> rows = [
    for (final i in const [1, 2, 3, 4, 5]) SeedSmartView.leaveRows(6)[i],
  ];

  SvFilePreviewController newPreview(List<SvFile> list, int index) =>
      SvFilePreviewController(files: list, repo: files, index: index);
}
