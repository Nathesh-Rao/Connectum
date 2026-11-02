import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../../data/e2e/e2e_models.dart';
import '../../data/repositories/e2e_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';

/// The Security screen and the setup sheets share this controller: it lives
/// with the home shell (see HomeShellBinding) and is reused by `/security`.
class SecurityController extends GetxController {
  SecurityController({
    required this.e2e,
    required this.store,
    required this.connectivity,
  });

  final E2eRepository e2e;
  final SessionStore store;
  final ConnectivityService connectivity;

  /// Devices from the last read: live when known, else the saved copy.
  final saved = <E2eDevicePublic>[].obs;
  final savedMode = ''.obs;
  final isSavedRecovery = false.obs;
  final isBusy = false.obs;
  final busyId = RxnString();
  final problem = RxnString();

  bool get isOffline =>
      !SeedUi.isActive && connectivity.state.value != AppConnectivity.online;

  String get organisation {
    final org = store.orgId ?? (SeedUi.isActive ? SeedUi.currentOrgId : null);
    for (final m in store.identity.value?.enterprises ?? const []) {
      if (m.enterprise == org) return m.name;
    }
    return org ?? '';
  }

  String get mode =>
      e2e.mode.value.isNotEmpty ? e2e.mode.value : savedMode.value;

  List<E2eDevicePublic> get devices =>
      e2e.isStatusKnown.value ? e2e.myDevices : saved;

  /// Whether a recovery key exists. Read-only here: the recovery key is not
  /// listed as a device and cannot be removed from this screen.
  bool get isRecoveryOn =>
      e2e.isStatusKnown.value ? e2e.isRecoveryOn.value : isSavedRecovery.value;

  /// The waiting line for a phone added after other devices, else null.
  String? get lateTitle => e2e.isLate.value
      ? 'Waiting for your other device to show your earlier messages'
      : null;

  /// Who can show the past (from `e2e.sync.pending`), or the way out when no
  /// device was active recently. Null until that read has answered.
  String? get lateDetail {
    if (!e2e.isLate.value || !e2e.isHelpersKnown.value) return null;
    final names = [
      for (final d in e2e.helpers)
        if (d.label.trim().isNotEmpty) d.label.trim(),
    ];
    if (e2e.helpers.isEmpty) {
      return 'None of your other devices was active recently. If you set up a recovery code, you can use it to bring them back.';
    }
    return names.isEmpty
        ? 'One of your other devices can show them.'
        : 'Can show them: ${names.join(', ')}.';
  }

  bool isThisPhone(E2eDevicePublic d) => d.id == e2e.deviceId.value;

  @override
  void onReady() {
    super.onReady();
    load();
  }

  Future<void> load() async {
    if (SeedUi.isActive) {
      if (e2e.phase.value == E2eSetupPhase.idle) {
        SeedUi.applyE2e(e2e, 'devices');
      }
      return;
    }
    final last = await e2e.readSavedStatus();
    if (last != null) {
      saved.assignAll(last.devices);
      savedMode.value = last.mode;
      isSavedRecovery.value = last.isRecovery;
    }
    if (!isOffline) await e2e.refreshStatus();
  }

  /// Removes one device after the person confirmed. Returns false and sets
  /// [problem] when it did not work. When the sheet for a full device list is
  /// open, the registration is tried again afterwards.
  Future<bool> remove(E2eDevicePublic d) async {
    if (isBusy.value) return false;
    if (isOffline) {
      problem.value = 'Removing a device needs a connection.';
      return false;
    }
    isBusy.value = true;
    busyId.value = d.id;
    problem.value = null;
    try {
      if (SeedUi.isActive) {
        e2e.myDevices.removeWhere((x) => x.id == d.id);
        if (e2e.phase.value == E2eSetupPhase.limit) {
          e2e.phase.value = E2eSetupPhase.ready;
        }
        return true;
      }
      final wasFull = e2e.phase.value == E2eSetupPhase.limit;
      if (!await e2e.removeDevice(d.id)) {
        problem.value = "Couldn't remove that device. Try again.";
        return false;
      }
      if (wasFull) await e2e.setUpAgain();
      return true;
    } finally {
      isBusy.value = false;
      busyId.value = null;
    }
  }

  /// "Set up again" / "Retry" / "Set up this phone".
  Future<void> setUp() async {
    if (isBusy.value) return;
    if (isOffline) {
      problem.value = 'Setting up needs a connection.';
      return;
    }
    isBusy.value = true;
    problem.value = null;
    try {
      if (SeedUi.isActive) {
        e2e.phase.value = E2eSetupPhase.ready;
        return;
      }
      await e2e.setUpAgain();
    } finally {
      isBusy.value = false;
    }
  }

  void dismissLateHint() {
    if (SeedUi.isActive) {
      e2e.lateHint.value = '';
      return;
    }
    e2e.dismissLateHint();
  }

  void dismissNotice() {
    if (SeedUi.isActive) {
      e2e.notice.value = '';
      return;
    }
    e2e.dismissNotice();
  }
}
