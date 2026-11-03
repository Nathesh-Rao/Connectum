import 'package:get/get.dart';

import '../../data/form_logic/form_logic_assets.dart';
import '../../data/form_logic/form_logic_runner.dart';
import '../../data/form_logic/sample_forms.dart';
import '../../data/session_store.dart';
import '../../data/socket/socket_service.dart';

class DebugFormLogicController extends GetxController {
  DebugFormLogicController({
    required this.session,
    required this.socket,
    required this.samples,
  });

  final SessionStore session;
  final SocketService socket;
  final SampleForms samples;

  final sampleResults = <SampleFormResult>[].obs;
  final sampleError = RxnString();
  final isCheckingSamples = false.obs;

  bool get canCheckSamples => session.hasEnterpriseSession && socket.isOnline;

  /// Reads the `sample_*` forms (read only) and runs their cases.
  Future<void> checkSamples() async {
    isCheckingSamples.value = true;
    sampleError.value = null;
    sampleResults.clear();
    try {
      for (final o in await samples.list()) {
        sampleResults.add(await samples.check(o));
      }
      if (sampleResults.isEmpty) {
        sampleError.value = 'No sample_* forms are offered to this person.';
      }
    } on Object catch (e) {
      sampleError.value = e.toString();
    }
    isCheckingSamples.value = false;
  }

  final isRunning = true.obs;
  final error = RxnString();
  final report = Rxn<FormLogicReport>();
  final checks = <String>[].obs;
  final version = RxnString();

  @override
  void onReady() {
    super.onReady();
    run();
  }

  Future<void> run() async {
    isRunning.value = true;
    error.value = null;
    report.value = null;
    try {
      final assets = await FormLogicAssets.loadVerified();
      version.value = assets.version;
      checks.assignAll(assets.checks);
      final result = await FormLogicRunner.run(assets);
      if (result.error != null) {
        error.value = result.error;
      } else {
        report.value = result;
      }
    } on Object catch (e) {
      error.value = e.toString();
    }
    isRunning.value = false;
  }
}
