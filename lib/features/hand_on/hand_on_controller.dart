import 'package:flutter/material.dart' show BuildContext, Icons, Navigator;
import 'package:get/get.dart';

import '../../data/e2e/e2e_texts.dart';
import '../../core/routes/app_routes.dart';
import '../../core/widgets/app_notice_card.dart';
import '../../core/widgets/app_notices.dart';
import '../../data/repositories/hand_on_repository.dart';
import 'hand_on_sheet.dart';

/// Shows the hand-on to the person: a light notice card while a device waits
/// or a run is going, and the sheet where they approve, watch, stop and retry.
/// The state itself lives in [HandOnRepository].
class HandOnController extends GetxController {
  HandOnController(this.hand);

  final HandOnRepository hand;

  static const _key = 'notice-handon';
  static const _doneKey = 'notice-handon-done';
  bool _isSheetOpen = false;

  @override
  void onInit() {
    super.onInit();
    ever(hand.phase, (_) => _sync());
    ever(hand.offer, (_) => _sync());
    _sync();
  }

  @override
  void onClose() {
    AppNotices.hide(_key);
    AppNotices.hide(_doneKey);
    super.onClose();
  }

  void _sync() {
    final offer = hand.offer.value;
    final name = offer?.name ?? 'a new device';
    switch (hand.phase.value) {
      case HandOnPhase.offered:
        AppNotices.show(
          offer!.isContinue
              ? 'An earlier run stopped part way. Continue where it stopped.'
              : 'This device was just added to your account. If it is yours, approve it.',
          key: _key,
          values: {'device': name},
          title: offer.isContinue
              ? E2eTexts.continueTitleTemplate
              : E2eTexts.approveTitleTemplate,
          icon: Icons.phonelink_lock,
          actionLabel: 'Review',
          onAction: openSheet,
          isPersistent: true,
          onDismiss: hand.later,
        );
      case HandOnPhase.checking ||
          HandOnPhase.preparing ||
          HandOnPhase.sending ||
          HandOnPhase.paused ||
          HandOnPhase.failed ||
          HandOnPhase.cancelled:
        AppNotices.show(
          'Tap to see how far it is.',
          key: _key,
          values: {'device': name},
          title: E2eTexts.approveRunningTemplate,
          icon: Icons.sync,
          actionLabel: 'Open',
          onAction: openSheet,
          isPersistent: true,
        );
      case HandOnPhase.done:
        AppNotices.hide(_key);
        if (!_isSheetOpen) {
          AppNotices.show(
            E2eTexts.allSetBodyTemplate,
            values: {'device': name},
            key: _doneKey,
            title: 'All set',
            variant: AppNoticeVariant.success,
          );
          hand.close();
        }
      case HandOnPhase.gone:
        AppNotices.hide(_key);
        if (!_isSheetOpen) hand.close();
      case HandOnPhase.idle:
        AppNotices.hide(_key);
    }
  }

  Future<void> openSheet() async {
    final context = Get.context;
    if (context == null || _isSheetOpen) return;
    _isSheetOpen = true;
    await HandOnSheet.open(context, this);
    _isSheetOpen = false;
    _sync();
  }

  /// "Not you?": Security lists the devices and removes the one that is not
  /// the person's. Nothing is removed from here.
  void openSecurity(BuildContext sheetContext) {
    Navigator.of(sheetContext).pop();
    Get.toNamed(AppRoutes.security);
  }
}
