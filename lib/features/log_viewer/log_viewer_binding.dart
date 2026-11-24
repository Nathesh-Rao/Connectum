import 'package:get/get.dart';

import '../../core/log/log_file_sink.dart';
import '../settings/logs_controller.dart';
import 'log_viewer_controller.dart';

class LogViewerBinding extends Bindings {
  @override
  void dependencies() {
    final sink = Get.find<LogFileSink>();
    Get.lazyPut(
      () => LogViewerController(
        sink: sink,
        logs: LogsController(sink: sink),
      ),
    );
  }
}
