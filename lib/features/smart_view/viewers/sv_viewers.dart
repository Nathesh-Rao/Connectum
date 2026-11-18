import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../data/smart_view/sv_file.dart';
import '../sv_file_preview_controller.dart';
import 'sv_doc_viewer.dart';
import 'sv_file_card.dart';
import 'sv_image_viewer.dart';
import 'sv_media_player.dart';
import 'sv_media_viewer.dart';
import 'sv_pdf_viewer.dart';
import 'sv_sheet_viewer.dart';
import 'sv_text_viewer.dart';
import 'sv_zip_viewer.dart';

/// Draws one ready file. [isActive] is false for a page that is not the one
/// shown. A test passes its own to stand in for a viewer that needs a
/// platform view or plugin.
typedef SvViewerBuilder =
    Widget Function(BuildContext context, SvFileLoad load, bool isActive);

/// The viewer of each file type. The defaults draw the real thing; tests
/// replace the ones that need a plugin (PDF, video, audio).
class SvViewers {
  const SvViewers({this.pdf, this.media, this.mediaPlayer = _player});

  final SvViewerBuilder? pdf;
  final SvViewerBuilder? media;
  final SvMediaPlayerFactory mediaPlayer;

  static SvMediaPlayer _player(File file) => SvMediaPlayer.file(file);

  /// The body of a loaded file by its viewer.
  Widget build(
    BuildContext context,
    SvFilePreviewController controller,
    SvFileLoad load,
    bool isActive,
  ) {
    switch (load.file.viewer) {
      case SvViewer.image:
        return SvImageViewer(file: load.local!, load: load);
      case SvViewer.pdf:
        return pdf?.call(context, load, isActive) ??
            SvPdfViewer(key: ValueKey('pdf-${load.file.id}'), load: load);
      case SvViewer.video:
      case SvViewer.audio:
        return media?.call(context, load, isActive) ??
            SvMediaViewer(
              key: ValueKey('media-${load.file.id}'),
              load: load,
              isActive: isActive,
              factory: mediaPlayer,
            );
      case SvViewer.sheet:
        return SvSheetViewer(book: load.sheet!);
      case SvViewer.docx:
      case SvViewer.pptx:
        return SvDocViewer(doc: load.doc!, onOpenWith: controller.openWith);
      case SvViewer.zip:
        return SvZipViewer(listing: load.zip!);
      case SvViewer.text:
        return Obx(
          () => SvTextViewer(load: load, isWrap: controller.isWrap.value),
        );
      case SvViewer.none:
        return SvFileCard(file: load.file);
    }
  }
}
