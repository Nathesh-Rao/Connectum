import 'package:get/get.dart';

import 'package:connectum/core/log/log.dart';
import 'package:connectum/features/settings/settings.dart';
import 'log_viewer_controller.dart';

class LogViewerBinding extends Bindings {
  @override
  void dependencies() {
    final sink = Get.isRegistered<LogFileSink>()
        ? Get.find<LogFileSink>()
        : Get.put(LogBootstrap.current(), permanent: true);
    Get.lazyPut(
      () => LogViewerController(
        sink: sink,
        logs: LogsController(sink: sink),
      ),
    );
  }
}
