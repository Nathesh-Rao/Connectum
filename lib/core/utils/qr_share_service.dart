import 'dart:io';
import 'dart:ui';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../features/qr/models/qr_models.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_qr_share_card.dart';
import 'widget_image.dart';

/// Shares a QR card as an image. Never logs the link.
class QrShareService {
  /// The card as a PNG, [AppSpacing.qrShareWidth] x [AppSpacing.qrShareScale]
  /// pixels wide.
  Future<List<int>> render(QrCardData data) async {
    await AppQrShareFrame.preload();
    return WidgetImage.png(
      AppQrShareFrame(data: data),
      width: AppSpacing.qrShareWidth,
      pixelRatio: AppSpacing.qrShareScale,
    );
  }

  Future<void> shareImage(QrCardData data, {Rect? origin}) async {
    final bytes = await render(data);
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, data.fileName));
    try {
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          subject: data.shareSubject,
          text: data.shareText,
          sharePositionOrigin: origin,
        ),
      );
    } finally {
      if (file.existsSync()) await file.delete();
    }
  }
}
