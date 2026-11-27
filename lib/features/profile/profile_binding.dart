import 'package:get/get.dart';

import 'package:connectum/core/log/log.dart';
import 'package:connectum/core/tour/tour.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import 'package:connectum/features/chats/chats.dart';
import 'package:connectum/features/settings/settings.dart';
import '../../data/profile_photo/profile_photo_picker.dart';
import '../../data/session_store.dart';
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
        profiles: Get.find<PeopleProfiles>(),
        repository: Get.find<ProfileRepository>(),
        tour: Get.isRegistered<TourService>() ? Get.find<TourService>() : null,
        profileTour: Get.isRegistered<TourService>()
            ? ProfileTour(service: Get.find<TourService>())
            : null,
      ),
    );
  }
}
