import 'package:dio/dio.dart';
import 'package:get/get.dart';

/// A document being downloaded to open. Lives with the conversation screen; a
/// finished download leaves the file in the attachment cache instead.
class FileDownload {
  final cancel = CancelToken();

  /// 0 to 1; stays 0 while the server has not said how long the file is.
  final progress = 0.0.obs;
  final isFailed = false.obs;
  final error = RxnString();
}
