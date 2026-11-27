import 'package:dio/dio.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_smart_files.dart';
import '../../data/attachment_cache.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'debug_smart_files_controller.dart';

class DebugSmartFilesBinding extends Bindings {
  @override
  void dependencies() {
    final dio = Dio();
    Get.lazyPut(
      () => DebugSmartFilesController(
        files: SvFileRepository(
          dio: dio,
          token: () => null,
          origin: '',
          cache: AttachmentCache(dio),
          onUnauthorized: () {},
          fetcher: SeedSmartFiles.fetcher,
        ),
      ),
    );
  }
}
