import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/log/log.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/features/share/share.dart';
import '../../core/routes/app_routes.dart';
import 'logs_exporter.dart';
import 'widgets/logs_options_sheet.dart';
import 'widgets/old_log_dialog.dart';

/// State and actions of the Logs section. Owned by the Profile controller,
/// which calls [dispose].
class LogsController {
  LogsController({
    required this.sink,
    LogExporter? exporter,
    this.connectumShare,
  }) : exporter = exporter ?? LogExporter() {
    state.value = sink.state.value;
    sink.state.addListener(_sync);
  }

  final LogFileSink sink;
  final LogExporter exporter;

  /// "Share to Connectum"; null hides it from the Logs menu.
  final ShareRepository? connectumShare;

  final state = const LogState().obs;
  final isBusy = false.obs;

  void dispose() => sink.state.removeListener(_sync);

  void _sync() => state.value = sink.state.value;

  bool get hasFile => state.value.fileName != null;

  /// ON: asks what to do with an old file; dismissing the dialog leaves the
  /// switch OFF. OFF: closes the file and keeps it.
  Future<void> setEnabled(BuildContext context, bool isOn) async {
    if (isBusy.value) return;
    isBusy.value = true;
    try {
      if (!isOn) {
        await sink.disable();
        return;
      }
      if (!await sink.hasOldFile()) {
        await sink.startNew();
        return;
      }
      final name = state.value.fileName ?? '';
      if (!context.mounted) return;
      final isDelete = await OldLogDialog.ask(context, name);
      if (isDelete == null) return;
      if (isDelete) {
        await sink.startNew();
      } else {
        await sink.startAppend();
      }
    } catch (e, st) {
      AppLog.e('logs_controller', e, st);
    } finally {
      isBusy.value = false;
    }
  }

  Future<void> openOptions(BuildContext context) async {
    await sink.flush();
    if (!context.mounted) return;
    await AppBottomSheet.show<void>(
      context,
      title: 'Logs',
      child: LogsOptionsSheet(
        hasFile: hasFile,
        onView: openViewer,
        onSave: saveToDevice,
        onShare: share,
        onShareToConnectum: connectumShare == null
            ? null
            : () => shareToConnectum(context),
      ),
    );
  }

  /// Opens the picker with the log file. It is the file the sink wrote,
  /// already redacted as it was written, the same one Share file hands out.
  Future<void> shareToConnectum(BuildContext context) async {
    final repo = connectumShare;
    if (repo == null) return;
    try {
      final file = await sink.fileForExport();
      if (file == null) {
        return AppNotices.error("Couldn't share the log file");
      }
      if (!context.mounted) return;
      await showShareToConnectum(
        context,
        repository: repo,
        files: [ShareFile(name: file.uri.pathSegments.last, path: file.path)],
      );
    } catch (e, st) {
      AppLog.e('logs_controller', e, st, 'share to connectum');
      AppNotices.error("Couldn't share the log file");
    }
  }

  /// Flushes the buffer, then opens the in-app viewer. Never creates a file.
  Future<void> openViewer() async {
    try {
      AppLog.i('logs_controller', 'open viewer');
      await sink.flush();
      await Get.toNamed(AppRoutes.logViewer);
    } catch (e, st) {
      AppLog.e('logs_controller', e, st, 'view $e');
      AppNotices.error("Couldn't open the log file");
    }
  }

  Future<void> saveToDevice() async {
    try {
      final file = await sink.fileForExport();
      if (file == null) return AppNotices.error("Couldn't save the log file");
      final where = await exporter.saveToDevice(file);
      if (where != null) AppNotices.success('Saved to $where');
    } catch (e, st) {
      AppLog.e('logs_controller', e, st, 'save');
      AppNotices.error("Couldn't save the log file");
    }
  }

  Future<void> share() async {
    try {
      final file = await sink.fileForExport();
      if (file == null) return AppNotices.error("Couldn't share the log file");
      await exporter.share(file);
    } catch (e, st) {
      AppLog.e('logs_controller', e, st, 'share');
      AppNotices.error("Couldn't share the log file");
    }
  }

  /// "Off", "On · name · 12 KB" or "Off · last file name".
  static String subtitle(LogState s) {
    final name = s.fileName;
    if (s.isEnabled) return 'On · ${name ?? ''} · ${size(s.sizeBytes)}';
    return name == null ? 'Off' : 'Off · last file $name';
  }

  static String size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
