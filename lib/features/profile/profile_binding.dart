import 'package:get/get.dart';

import '../../core/tour/tour_service.dart';
import '../../data/profile_photo/profile_photo_picker.dart';
import '../../core/log/log_bootstrap.dart';
import '../../core/log/log_file_sink.dart';
import '../../data/repositories/people_avatars.dart';
import '../../data/repositories/profile_photo_repository.dart';
import '../../data/repositories/qr_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/repositories/share_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../chats/enterprise_switcher_controller.dart';
import '../settings/logs_controller.dart';
import 'profile_controller.dart';
import 'profile_tour.dart';

class ProfileBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => ProfileController(
        logs: LogsController(
          sink: Get.isRegistered<LogFileSink>()
              ? Get.find<LogFileSink>()
              : Get.put(LogBootstrap.current(), permanent: true),
          connectumShare: Get.isRegistered<ShareRepository>()
              ? Get.find<ShareRepository>()
              : null,
        ),
        store: Get.find<SessionStore>(),
        session: Get.find<SessionRepository>(),
        connectivity: Get.find<ConnectivityService>(),
        switcher: Get.find<EnterpriseSwitcherController>(),
        qr: Get.find<QrRepository>(),
        avatars: Get.find<PeopleAvatars>(),
        photos: Get.find<ProfilePhotoRepository>(),
        picker: Get.find<ProfilePhotoPicker>(),
        tour: Get.isRegistered<TourService>() ? Get.find<TourService>() : null,
        profileTour: Get.isRegistered<TourService>()
            ? ProfileTour(service: Get.find<TourService>())
            : null,
      ),
    );
  }
}
