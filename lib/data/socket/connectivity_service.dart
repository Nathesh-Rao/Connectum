import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get/get.dart';

import 'socket_service.dart';

enum AppConnectivity { online, offline, connecting }

class ConnectivityService extends GetxService {
  final hasNetwork = true.obs;
  final simulateOffline = false.obs;
  final state = AppConnectivity.connecting.obs;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Rx<SocketState>? _socket;

  @override
  Future<void> onInit() async {
    super.onInit();
    final connectivity = Connectivity();
    _apply(await connectivity.checkConnectivity());
    _subscription = connectivity.onConnectivityChanged.listen(_apply);
    ever(hasNetwork, (_) => _recompute());
    ever(simulateOffline, (_) => _recompute());
  }

  void attachSocket(Rx<SocketState> socketState) {
    _socket = socketState;
    ever(socketState, (_) => _recompute());
    _recompute();
  }

  void _apply(List<ConnectivityResult> results) {
    hasNetwork.value = results.any((r) => r != ConnectivityResult.none);
  }

  void _recompute() {
    if (simulateOffline.value || !hasNetwork.value) {
      state.value = AppConnectivity.offline;
    } else if (_socket?.value == SocketState.online) {
      state.value = AppConnectivity.online;
    } else {
      state.value = AppConnectivity.connecting;
    }
  }

  @override
  void onClose() {
    _subscription?.cancel();
    super.onClose();
  }
}
