import 'package:get/get.dart';

import 'package:connectum/core/utils/utils.dart';
import 'package:connectum/data/repositories/repositories.dart';
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
