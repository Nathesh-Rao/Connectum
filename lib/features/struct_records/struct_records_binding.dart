import 'package:get/get.dart';

import '../../core/debug/seed_struct_records.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import '../../data/session_store.dart';
import 'models/struct_records_launch.dart';
import 'struct_records_controller.dart';

class StructRecordsBinding extends Bindings {
  @override
  void dependencies() {
    final launch = Get.arguments as StructRecordsLaunch;
    Get.lazyPut(() {
      final submissions = Get.find<SubmissionRepository>();
      final StructRecordsRepository repository;
      if (SeedStructRecords.isActive) {
        repository = SeedStructRecords.repository(submissions);
      } else {
        final gate = Get.find<SmartViewRepository>();
        final socket = Get.find<SocketService>();
        final store = Get.find<SessionStore>();
        final commands = Get.find<CommandRepository>();
        repository = StructRecordsRepository(
          call: gate.gated,
          isOnline: () => socket.isOnline,
          me: () => store.userId ?? '',
          isAdmin: () => commands.isAdmin.value,
          definition: (name, scope) =>
              submissions.definition(name, scope: scope),
          deleteRecord: submissions.deleteSubmission,
        );
      }
      return StructRecordsController(repository: repository, launch: launch);
    });
  }
}
