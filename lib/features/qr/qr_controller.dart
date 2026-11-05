import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../core/utils/qr_share_service.dart';
import '../../core/widgets/app_notices.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/repositories/qr_repository.dart';
import '../../data/socket/socket_service.dart';
import 'models/qr_models.dart';

class QrController extends GetxController {
  QrController({
    required this.repository,
    required this.share,
    this.initialKind = QrKind.person,
  });

  final QrRepository repository;
  final QrShareService share;
  final QrKind initialKind;

  final state = AppViewState.loading.obs;
  final errorMessage = ''.obs;
  final kinds = <QrKind>[].obs;
  final selected = QrKind.person.obs;
  final branches = <QrBranch>[].obs;

  /// The branch put in the organisation QR; null is the whole organisation.
  final branch = Rxn<QrBranch>();
  final isSharing = false.obs;

  final person = Rxn<QrCardData>();
  final organisation = Rxn<QrCardData>();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  QrCardData? get current => selected.value == QrKind.person
      ? person.value
      : organisation.value?.withBranch(branch.value);

  /// One call per open, and one per Try again.
  Future<void> load() async {
    state.value = AppViewState.loading;
    try {
      final codes = await repository.load();
      person.value = codes.person;
      organisation.value = codes.organisation;
      branches.assignAll(codes.organisation == null ? [] : codes.branches);
      branch.value = null;
      kinds.assignAll(codes.kinds);
      if (kinds.isNotEmpty) {
        selected.value = kinds.contains(initialKind)
            ? initialKind
            : kinds.first;
      }
      state.value = kinds.isEmpty ? AppViewState.empty : AppViewState.content;
    } catch (e) {
      person.value = null;
      organisation.value = null;
      errorMessage.value = _message(e);
      state.value = AppViewState.error;
      AppNotices.error(errorMessage.value);
    }
  }

  static String _message(Object error) {
    if (error is SocketCallError) {
      if (error.isConnectionGap) {
        return "Can't reach the server. Check your connection and try again.";
      }
      if (error.message.isNotEmpty) return error.message;
    }
    return 'Could not load your QR codes.';
  }

  void selectKind(QrKind kind) => selected.value = kind;

  void selectBranch(QrBranch? value) => branch.value = value;

  Future<void> shareImage(Rect? origin) async {
    final data = current;
    if (data == null || isSharing.value) return;
    isSharing.value = true;
    try {
      await share.shareImage(data, origin: origin);
    } catch (_) {
      AppNotices.error('Could not create the image.');
    } finally {
      isSharing.value = false;
    }
  }

  /// Copies the code as shown (XXXX-XXXX); with a branch chosen it is still
  /// the organisation code.
  Future<void> copyCode() async {
    final data = current;
    if (data == null) return;
    await Clipboard.setData(ClipboardData(text: data.display));
    HapticFeedback.lightImpact();
    AppNotices.success('Code copied');
  }
}
