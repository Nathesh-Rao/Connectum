import 'package:get/get.dart';

import '../../core/utils/qr_share_service.dart';
import '../../data/repositories/qr_repository.dart';
import 'models/qr_models.dart';
import 'qr_controller.dart';

class QrBinding extends Bindings {
  QrBinding({required this.repository, this.initialKind = QrKind.person});

  final QrRepository repository;
  final QrKind initialKind;

  @override
  void dependencies() {
    Get.lazyPut(
      () => QrController(
        repository: repository,
        share: QrShareService(),
        initialKind: initialKind,
      ),
    );
  }
}
