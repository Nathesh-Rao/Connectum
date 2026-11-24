import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Hands the log file to the person: a copy in a place the file manager shows,
/// or the system share sheet. Failures are thrown for the controller to turn
/// into a friendly notice; the file's text is never read into the log.
class LogExporter {
  static const _channel = MethodChannel('connectum/device');

  /// Where the copy went (`Downloads/<name>` or the name on iOS), or null when
  /// the person closed the system dialog.
  ///
  /// Android 10+ writes straight into the public Downloads folder through
  /// MediaStore (no permission). Older Android and iOS open the system
  /// "save as" screen (Android document picker, iOS Files export).
  Future<String?> saveToDevice(File file) async {
    final name = file.uri.pathSegments.last;
    if (Platform.isAndroid) {
      final answer = await _channel.invokeMethod<String>('saveToDownloads', {
        'path': file.path,
        'name': name,
      });
      if (answer == 'saved') return 'Downloads/$name';
      if (answer != 'unsupported') throw StateError('save failed');
    }
    final saved = await FilePicker.saveFile(
      fileName: name,
      bytes: await file.readAsBytes(),
      mimeType: 'text/plain',
    );
    return saved == null ? null : name;
  }

  Future<void> share(File file) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')],
        subject: 'Connectum mobile log',
      ),
    );
  }
}
