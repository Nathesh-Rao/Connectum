import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../core/theme/app_motion.dart';
import '../../data/e2e/e2e_models.dart';

enum DeviceLimitStep { list, confirm, registering, done, failed }

/// Decides when the device-limit sheet may open: one at a time, and once per
/// organisation until the state changes (the phone gets set up, or the setup
/// ends some other way). A person who asked for it opens it any time nothing
/// else is open.
class LimitSheetGate {
  final _shown = <String>{};
  String? _open;

  bool get isOpen => _open != null;

  bool tryOpen(String org, {bool isRequested = false}) {
    if (_open != null) return false;
    if (!isRequested && _shown.contains(org)) return false;
    _open = org;
    _shown.add(org);
    return true;
  }

  void closed() => _open = null;

  /// The limit state is over for [org]: the next time it comes back, the
  /// sheet may show again.
  void settled(String org) => _shown.remove(org);
}

/// State of the device-limit sheet: the device list, the confirmation, the
/// registration that follows a removal. Everything that touches the server
/// comes in as a function, so the sheet works with sample data too.
class DeviceLimitController extends GetxController {
  DeviceLimitController({
    required this.thisDeviceId,
    required this.load,
    required this.removeDevice,
    required this.retry,
    required this.isOffline,
    required this.maxDevices,
    this.hold = AppDurations.copiedHold,
    List<E2eDevicePublic> devices = const [],
  }) {
    this.devices.assignAll(devices);
  }

  final String thisDeviceId;
  final int maxDevices;

  /// How long the success state shows before the sheet closes.
  final Duration hold;

  /// Reads the device list again; false when it could not be read.
  final Future<List<E2eDevicePublic>?> Function() load;

  /// `e2e.remove` for one device; true when it is gone.
  final Future<bool> Function(E2eDevicePublic) removeDevice;

  /// Tries to register this phone; null when it worked, else the reason.
  final Future<String?> Function() retry;
  final bool Function() isOffline;

  final devices = <E2eDevicePublic>[].obs;
  final step = DeviceLimitStep.list.obs;
  final picked = Rxn<E2eDevicePublic>();
  final busyId = RxnString();
  final problem = RxnString();
  final failure = RxnString();
  final isLoading = false.obs;
  final isLoadFailed = false.obs;

  /// The name of the device just removed, for "Removed ...".
  final removedNote = RxnString();

  /// Set by whoever opens the sheet: closes it.
  VoidCallback? onFinished;

  bool _isRetrying = false;

  bool isThisPhone(E2eDevicePublic d) => d.id == thisDeviceId;

  /// This phone's own entry is never removed from here.
  bool canRemove(E2eDevicePublic d) =>
      !isThisPhone(d) && step.value == DeviceLimitStep.list && !_isBusy;

  bool get _isBusy => busyId.value != null;

  Future<void> loadDevices() async {
    isLoading.value = true;
    isLoadFailed.value = false;
    final read = await load();
    if (read == null) {
      isLoadFailed.value = true;
    } else {
      devices.assignAll(read);
    }
    isLoading.value = false;
  }

  void ask(E2eDevicePublic d) {
    if (!canRemove(d)) return;
    problem.value = null;
    picked.value = d;
    step.value = DeviceLimitStep.confirm;
  }

  void cancel() {
    if (step.value == DeviceLimitStep.confirm) {
      step.value = DeviceLimitStep.list;
    }
    picked.value = null;
  }

  /// Removes the picked device, then tries to register this phone once when
  /// there is room.
  Future<void> confirmRemove() async {
    final d = picked.value;
    if (d == null || _isBusy || step.value != DeviceLimitStep.confirm) return;
    if (isOffline()) {
      problem.value = 'Removing a device needs a connection.';
      return;
    }
    busyId.value = d.id;
    problem.value = null;
    final isOk = await removeDevice(d);
    busyId.value = null;
    if (!isOk) {
      problem.value = "Couldn't remove that device. Try again.";
      return;
    }
    devices.removeWhere((x) => x.id == d.id);
    removedNote.value = d.label.isEmpty ? 'Unnamed device' : d.label;
    picked.value = null;
    step.value = DeviceLimitStep.list;
    if (maxDevices <= 0 || devices.length < maxDevices) {
      await registerAgain();
    }
  }

  /// One registration attempt; success closes the sheet after a short hold.
  Future<void> registerAgain() async {
    if (_isRetrying || step.value == DeviceLimitStep.done) return;
    _isRetrying = true;
    step.value = DeviceLimitStep.registering;
    failure.value = null;
    final reason = await retry();
    _isRetrying = false;
    if (reason == null) {
      await _finish();
    } else {
      failure.value = reason;
      step.value = DeviceLimitStep.failed;
    }
  }

  /// The setup finished some other way (another device was removed, the
  /// server pushed a change).
  Future<void> onRegistered() async {
    if (_isRetrying || step.value == DeviceLimitStep.done) return;
    await _finish();
  }

  void onRefused(String reason) {
    if (_isRetrying || step.value != DeviceLimitStep.registering) return;
    failure.value = reason;
    step.value = DeviceLimitStep.failed;
  }

  void backToList() {
    failure.value = null;
    step.value = DeviceLimitStep.list;
  }

  Future<void> _finish() async {
    if (step.value == DeviceLimitStep.done) return;
    step.value = DeviceLimitStep.done;
    await Future<void>.delayed(hold);
    onFinished?.call();
  }
}
