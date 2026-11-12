import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/widgets/app_bottom_sheet.dart';
import 'ai_summary_controller.dart';
import 'ai_texts.dart';
import 'widgets/ai_notice_dialog.dart';
import 'widgets/ai_sheet.dart';

/// What the AI icon does: a dialog (not set up, cannot reach
/// the server) or the sheet.
Future<void> openAi(BuildContext context, AiSummaryController c) async {
  final entry = await c.resolveEntry();
  if (!context.mounted) return;
  switch (entry) {
    case AiEntry.notSetUp:
      return AiNoticeDialog.show(
        context,
        title: AiTexts.setupTitle,
        text: c.setupText,
      );
    case AiEntry.problem:
      return AiNoticeDialog.show(
        context,
        title: AiTexts.errorTitle(c.lastProblem),
        text: c.errorText(c.lastProblem),
      );
    case AiEntry.sheet:
      break;
  }
  var isOpen = true;
  final worker = ever(c.blocked, (setup) {
    if (setup == null || !isOpen || !context.mounted) return;
    isOpen = false;
    Navigator.of(context).pop();
    unawaited(
      AiNoticeDialog.show(
        context,
        title: AiTexts.setupTitle,
        text: c.setupText,
      ),
    );
  });
  final sheet = AppBottomSheet.show<void>(
    context,
    title: AiTexts.title,
    titleWidget: const AiSheetTitle(),
    child: AiSheet(
      controller: c,
      onClose: () {
        if (!isOpen) return;
        isOpen = false;
        Navigator.of(context).pop();
      },
    ),
  );
  unawaited(c.onSheetOpened());
  await sheet;
  isOpen = false;
  worker.dispose();
  c.cancel();
}
