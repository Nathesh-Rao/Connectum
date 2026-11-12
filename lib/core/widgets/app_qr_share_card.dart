import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../features/qr/models/qr_models.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'app_card_circles.dart';
import 'app_highlight_text.dart';
import 'app_logo.dart';
import 'app_tag.dart';

/// The QR card: who the code is, the QR and the code as XXXX-XXXX.
/// Light colours and no text scaling, so the screen and the shared image
/// match whatever the phone's text size or theme is. No LayoutBuilder (it
/// sits under AppScaffold's IntrinsicHeight): the width comes from [width],
/// or from the screen width clamped to a sensible range. The shared image
/// always passes [AppSpacing.qrCardWidth].
class AppQrShareCard extends StatelessWidget {
  const AppQrShareCard({
    super.key,
    required this.data,
    this.width,
    this.onCopy,
    this.isExporting = false,
  });

  final QrCardData data;
  final double? width;

  /// Copies the code. On screen only: the code becomes tappable and a quiet
  /// copy icon sits beside it.
  final VoidCallback? onCopy;

  /// True when the card is drawn for the shared image: no copy icon and no
  /// tap area, so the image is the plain card.
  final bool isExporting;

  @override
  Widget build(BuildContext context) {
    final cardWidth =
        width ??
        (MediaQuery.sizeOf(context).width - 2 * AppSpacing.page).clamp(
          AppSpacing.qrCardMinWidth,
          AppSpacing.qrCardWidth,
        );
    final qrSize = cardWidth - 2 * AppSpacing.xl;
    final isCopyable = onCopy != null && !isExporting;
    const codeGap = AppSpacing.md - _CopyableCode.tapPadding;
    final codeText = Text(
      data.display,
      style: AppText.title.copyWith(letterSpacing: 2),
      textAlign: TextAlign.center,
      maxLines: 1,
    );
    final card = MediaQuery.withNoTextScaling(
      child: Container(
        width: cardWidth,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: AppColors.cardLine),
          boxShadow: AppShadows.soft,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card - 1),
          child: AppCardCircles(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AppHighlightText(
                    data.sentence,
                    values: {'name': data.name},
                    style: AppText.title,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                  ),
                  if (data.organisation != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      data.organisation!,
                      style: AppText.readable.copyWith(color: AppColors.muted),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (data.branch != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: qrSize),
                      child: AppTag(
                        label: data.branch!.name,
                        tone: AppTagTone.accent,
                        icon: Icons.place_outlined,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  _QrCode(payload: data.payload, size: qrSize),
                  SizedBox(height: isCopyable ? codeGap : AppSpacing.md),
                  isCopyable
                      ? _CopyableCode(code: data.display, onCopy: onCopy!)
                      : codeText,
                  SizedBox(height: isCopyable ? codeGap : AppSpacing.md),
                  const Divider(height: 1, thickness: 1, color: AppColors.line),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const AppLogo(width: AppSpacing.qrFooterLogo),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        'Connectum',
                        style: AppText.readableStrong.copyWith(
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (width != null) return card;
    // RenderConstrainedBox does not clamp the width it passes on when asked
    // for an intrinsic height, so under AppScaffold's IntrinsicHeight the
    // card is centred with padding, which does.
    final gutter =
        (MediaQuery.sizeOf(context).width - 2 * AppSpacing.page - cardWidth) /
        2;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter < 0 ? 0 : gutter),
      child: card,
    );
  }
}

/// The code as a tap target: padded for a long hit area (the gaps around it
/// are shortened by the same amount, so the card keeps its size) with a quiet
/// copy icon. An empty slot on the left keeps the code centred.
class _CopyableCode extends StatelessWidget {
  const _CopyableCode({required this.code, required this.onCopy});

  static const double tapPadding = AppSpacing.xs;
  static const double _iconSlot = 24;

  final String code;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final style = AppText.title.copyWith(letterSpacing: 2);
    return Semantics(
      button: true,
      label: 'Copy code',
      excludeSemantics: true,
      onTap: onCopy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onCopy,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: tapPadding),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: _iconSlot),
              Text(code, style: style, maxLines: 1),
              SizedBox(
                width: _iconSlot,
                child: Icon(
                  Icons.copy_rounded,
                  size: 16,
                  color: style.color!.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The QR drawn from the server's [payload] exactly as it is: error
/// correction M, a quiet zone of [_quietModules] modules, dark modules on a
/// white tile. Modules are a whole number of third-pixels, so they are sharp
/// on the screen and at the 3x share image; the rest of the tile stays white.
class _QrCode extends StatelessWidget {
  const _QrCode({required this.payload, required this.size});

  static const _quietModules = 4;

  final String payload;
  final double size;

  @override
  Widget build(BuildContext context) {
    final result = QrValidator.validate(
      data: payload,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
    );
    final qr = result.qrCode;
    Widget? code;
    if (qr != null) {
      final modules = qr.moduleCount;
      final module =
          (size / (modules + 2 * _quietModules) * AppSpacing.qrShareScale)
              .floorToDouble() /
          AppSpacing.qrShareScale;
      code = CustomPaint(
        size: Size.square(module * modules),
        painter: QrPainter.withQr(
          qr: qr,
          gapless: true,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: AppColors.ink,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: AppColors.ink,
          ),
        ),
      );
    }
    return Semantics(
      image: true,
      label: 'QR code',
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: AppColors.cardLine),
          boxShadow: AppShadows.soft,
        ),
        child: code,
      ),
    );
  }
}

/// The card on a soft background with a margin all round: what is shared as
/// an image, drawn [AppSpacing.qrShareWidth] logical pixels wide.
class AppQrShareFrame extends StatelessWidget {
  const AppQrShareFrame({super.key, required this.data});

  final QrCardData data;

  /// Loads the logo into the image cache, so an offscreen draw has it at once.
  static Future<void> preload() {
    final done = Completer<void>();
    final stream = const AssetImage(
      'assets/images/connectum_logo_blue.png',
    ).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    void finish() {
      stream.removeListener(listener);
      if (!done.isCompleted) done.complete();
    }

    listener = ImageStreamListener(
      (_, _) => finish(),
      onError: (_, _) => finish(),
    );
    stream.addListener(listener);
    return done.future.timeout(const Duration(seconds: 2), onTimeout: finish);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.qrShareWidth,
      color: AppColors.fill,
      padding: const EdgeInsets.all(
        (AppSpacing.qrShareWidth - AppSpacing.qrCardWidth) / 2,
      ),
      child: AppQrShareCard(
        data: data,
        width: AppSpacing.qrCardWidth,
        isExporting: true,
      ),
    );
  }
}
