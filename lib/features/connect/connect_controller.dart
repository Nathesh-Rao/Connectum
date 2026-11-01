import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/debug/seed_connect.dart';
import '../../core/debug/seed_ui.dart';
import '../../core/routes/app_routes.dart';
import '../../core/utils/app_settings.dart';
import '../../core/utils/connect_code.dart';
import '../../data/api/api_client.dart';
import '../../data/api/api_messages.dart';
import '../../data/models/connect_card.dart';
import '../../data/models/identity_info.dart';
import '../../data/models/ids.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';

enum ConnectMode { scan, manual }

enum ConnectPhase { entry, resolving, confirm, failed, done }

enum ConnectCameraState { off, starting, ready, denied, unavailable }

enum ConnectFailure { notFound, rateLimited, offline, other }

enum ConnectOutcome { requestSent, joined }

class ConnectController extends GetxController with WidgetsBindingObserver {
  ConnectController({
    required this.auth,
    required this.store,
    required this.session,
    required this.connectivity,
  });

  static const noticeHold = Duration(seconds: 2);
  static const _searchDebounce = Duration(milliseconds: 400);

  final AuthRepository auth;
  final SessionStore store;
  final SessionRepository session;
  final ConnectivityService connectivity;

  final mode = ConnectMode.scan.obs;
  final phase = ConnectPhase.entry.obs;

  // scanner
  final camera = Rxn<MobileScannerController>();
  final cameraState = ConnectCameraState.off.obs;
  final hasTorch = false.obs;
  final isTorchOn = false.obs;
  final scanNotice = RxnString();
  MobileScannerController? _scanner;
  StreamSubscription<BarcodeCapture>? _detections;
  Timer? _noticeTimer;
  DateTime? _cooldownUntil;

  // manual
  final query = TextEditingController();
  final queryFocus = FocusNode();
  final results = <EnterpriseHit>[].obs;
  final isSearching = false.obs;
  final searchMessage = RxnString();
  Timer? _debounce;

  // resolved organisation
  final card = Rxn<ConnectCard>();
  final membership = Rxn<EnterpriseMembership>();
  final selectedCategory = RxnString();
  final isJoining = false.obs;
  final joinMessage = RxnString();
  final failure = ConnectFailure.other.obs;
  final failureDetail = RxnString();
  final retryAfter = 0.obs;
  final outcome = ConnectOutcome.requestSent.obs;
  final welcome = RxnString();

  /// A person's code from a person's QR, kept in memory only until the
  /// "connect with the person" step exists.
  ConnectCode? keptPersonLink;
  ConnectCode? _link;
  bool _isOpen = false;

  bool get isOffline =>
      !SeedUi.isActive && connectivity.state.value == AppConnectivity.offline;

  // ---- sheet ----------------------------------------------------------------------

  void open() {
    _isOpen = true;
    _cooldownUntil = null;
    scanNotice.value = null;
    query.clear();
    results.clear();
    searchMessage.value = null;
    card.value = null;
    membership.value = null;
    keptPersonLink = null;
    _link = null;
    mode.value = ConnectMode.scan;
    phase.value = ConnectPhase.entry;
    WidgetsBinding.instance.addObserver(this);
    unawaited(startCamera());
  }

  void close() {
    _isOpen = false;
    WidgetsBinding.instance.removeObserver(this);
    _noticeTimer?.cancel();
    _debounce?.cancel();
    queryFocus.unfocus();
    unawaited(stopCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isOpen) return;
    if (state == AppLifecycleState.paused) {
      unawaited(stopCamera(keepState: true));
    } else if (state == AppLifecycleState.resumed && _isScanning) {
      unawaited(startCamera());
    }
  }

  bool get _isScanning =>
      phase.value == ConnectPhase.entry && mode.value == ConnectMode.scan;

  void showManual() {
    mode.value = ConnectMode.manual;
    unawaited(stopCamera());
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (_isOpen && mode.value == ConnectMode.manual) {
        queryFocus.requestFocus();
      }
    });
  }

  void showScanner() {
    queryFocus.unfocus();
    mode.value = ConnectMode.scan;
    if (phase.value == ConnectPhase.entry) unawaited(startCamera());
  }

  /// Back to the entry step (scanner or manual) from a failure or the card.
  void backToEntry() {
    phase.value = ConnectPhase.entry;
    card.value = null;
    if (mode.value == ConnectMode.scan) unawaited(startCamera());
  }

  // ---- camera ---------------------------------------------------------------------

  Future<void> startCamera() async {
    if (!_isOpen || _scanner != null) return;
    if (cameraState.value != ConnectCameraState.denied) {
      cameraState.value = ConnectCameraState.starting;
    }
    final scanner = MobileScannerController(
      autoStart: false,
      formats: const [BarcodeFormat.qrCode],
    );
    _scanner = scanner;
    scanner.addListener(_onCameraValue);
    _detections = scanner.barcodes.listen(_onDetect);
    camera.value = scanner;
    try {
      await scanner.start();
    } on MobileScannerException catch (e) {
      if (_scanner != scanner) return;
      cameraState.value = e.errorCode == MobileScannerErrorCode.permissionDenied
          ? ConnectCameraState.denied
          : ConnectCameraState.unavailable;
      await stopCamera(keepState: true);
    } catch (_) {
      if (_scanner != scanner) return;
      cameraState.value = ConnectCameraState.unavailable;
      await stopCamera(keepState: true);
    }
  }

  Future<void> stopCamera({bool keepState = false}) async {
    final scanner = _scanner;
    if (scanner == null) return;
    _scanner = null;
    camera.value = null;
    hasTorch.value = false;
    isTorchOn.value = false;
    if (!keepState || cameraState.value == ConnectCameraState.ready) {
      cameraState.value = ConnectCameraState.off;
    }
    scanner.removeListener(_onCameraValue);
    await _detections?.cancel();
    _detections = null;
    try {
      await scanner.stop();
    } catch (_) {}
    await scanner.dispose();
  }

  void _onCameraValue() {
    final scanner = _scanner;
    if (scanner == null) return;
    final value = scanner.value;
    hasTorch.value = value.torchState != TorchState.unavailable;
    isTorchOn.value = value.torchState == TorchState.on;
    final error = value.error;
    if (error != null) {
      cameraState.value =
          error.errorCode == MobileScannerErrorCode.permissionDenied
          ? ConnectCameraState.denied
          : ConnectCameraState.unavailable;
    } else if (value.isRunning) {
      cameraState.value = ConnectCameraState.ready;
    }
  }

  Future<void> toggleTorch() async {
    try {
      await _scanner?.toggleTorch();
    } catch (_) {}
  }

  Future<void> openSettings() => AppSettings.open();

  void _onDetect(BarcodeCapture capture) {
    if (!_isScanning) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        handleScan(raw);
        return;
      }
    }
  }

  /// One entry point for a scanned (or simulated) text.
  void handleScan(String raw) {
    if (!_isScanning) return;
    final link = ConnectLinkParser.parse(raw).value;
    if (link == null) {
      _rejectScan();
      return;
    }
    HapticFeedback.lightImpact();
    resolve(link);
  }

  void _rejectScan() {
    final now = DateTime.now();
    final until = _cooldownUntil;
    if (until != null && now.isBefore(until)) return;
    _cooldownUntil = now.add(noticeHold);
    scanNotice.value = "That isn't a Connectum code";
    _noticeTimer?.cancel();
    _noticeTimer = Timer(noticeHold, () => scanNotice.value = null);
  }

  // ---- manual entry -----------------------------------------------------------------

  void onQueryChanged(String text) {
    _debounce?.cancel();
    searchMessage.value = null;
    _debounce = Timer(_searchDebounce, () => _search(text.trim()));
  }

  Future<void> _search(String text) async {
    if (!_isOpen) return;
    if (text.length < 2) {
      results.clear();
      return;
    }
    isSearching.value = true;
    try {
      List<EnterpriseHit> hits;
      if (SeedUi.isActive) {
        hits = SeedConnect.search(text);
      } else {
        final link = ConnectLinkParser.parse(text).value;
        final hit = link == null ? null : await auth.byId(link.display);
        hits = hit != null ? [hit] : await auth.search(text);
      }
      if (text != query.text.trim()) return;
      results.assignAll(hits);
      if (hits.isEmpty) searchMessage.value = 'No enterprise found.';
    } on ApiException catch (e) {
      searchMessage.value = e.code == 'rate_limited'
          ? _waitText(e.retryAfterSeconds)
          : ApiMessages.of(e);
    } finally {
      isSearching.value = false;
    }
  }

  /// The keyboard's action key: a typed code or pasted link goes straight on.
  void submitManual() {
    final link = ConnectLinkParser.parse(query.text).value;
    if (link != null) {
      queryFocus.unfocus();
      resolve(link);
    } else if (results.length == 1) {
      selectHit(results.first);
    }
  }

  void selectHit(EnterpriseHit hit) {
    final link = ConnectLinkParser.parse(hit.id).value;
    if (link == null) {
      searchMessage.value = 'No enterprise found.';
      return;
    }
    queryFocus.unfocus();
    resolve(link);
  }

  // ---- resolve ----------------------------------------------------------------------

  Future<void> resolve(ConnectCode link) async {
    _link = link;
    phase.value = ConnectPhase.resolving;
    scanNotice.value = null;
    unawaited(stopCamera());
    if (isOffline) {
      _fail(ConnectFailure.offline);
      return;
    }
    try {
      final found = SeedUi.isActive
          ? await SeedConnect.resolve(link)
          : await auth.connectCard(link);
      if (!_isOpen) return;
      card.value = found;
      membership.value = _membershipOf(found);
      keptPersonLink = link.isPersonLink ? link : null;
      selectedCategory.value = found.categories.length == 1
          ? found.categories.first
          : null;
      joinMessage.value = null;
      phase.value = ConnectPhase.confirm;
    } on ApiException catch (e) {
      if (!_isOpen) return;
      if (e.code == 'unauthenticated') {
        _toLogin();
      } else if (e.code == 'rate_limited' || e.status == 429) {
        retryAfter.value = e.retryAfterSeconds ?? 60;
        _fail(ConnectFailure.rateLimited);
      } else if (e.code == 'network' || e.code == 'bad_response') {
        _fail(ConnectFailure.offline);
      } else if (e.code == 'not_found' || e.code == 'invalid') {
        _fail(ConnectFailure.notFound);
      } else {
        _fail(ConnectFailure.other, detail: ApiMessages.of(e));
      }
    }
  }

  void _fail(ConnectFailure kind, {String? detail}) {
    failure.value = kind;
    failureDetail.value = detail;
    phase.value = ConnectPhase.failed;
  }

  void retry() {
    final link = _link;
    if (link != null) resolve(link);
  }

  EnterpriseMembership? _membershipOf(ConnectCard found) {
    final list = store.identity.value?.enterprises ?? const [];
    for (final m in list) {
      if (_plain(m.enterprise) == found.code) return m;
    }
    return null;
  }

  static String _plain(String id) => id.replaceAll('-', '').toUpperCase();

  String get failureTitle => switch (failure.value) {
    ConnectFailure.notFound => "We couldn't find that enterprise",
    ConnectFailure.rateLimited => 'Too many lookups',
    ConnectFailure.offline => "You're offline",
    ConnectFailure.other => 'Something went wrong',
  };

  String get failureBody => switch (failure.value) {
    ConnectFailure.notFound =>
      'The code may be wrong or may have been renewed. Ask for a new QR code, or enter the code by hand.',
    ConnectFailure.rateLimited =>
      '${_waitText(retryAfter.value)} Nothing was lost: scan again after that.',
    ConnectFailure.offline =>
      "Looking up an enterprise needs a connection. The code is kept; try again when you're back online.",
    ConnectFailure.other =>
      failureDetail.value ?? 'Please try again in a moment.',
  };

  static String _waitText(int? seconds) {
    final s = seconds ?? 60;
    if (s < 60) return 'Try again in $s seconds.';
    final minutes = (s / 60).ceil();
    return 'Try again in $minutes ${minutes == 1 ? 'minute' : 'minutes'}.';
  }

  // ---- join -------------------------------------------------------------------------

  void selectCategory(String category) {
    selectedCategory.value = category;
    joinMessage.value = null;
  }

  Future<void> join() async {
    final found = card.value;
    final category = selectedCategory.value;
    if (found == null || category == null || isJoining.value) return;
    if (isOffline) {
      joinMessage.value = 'Connect to the internet to join.';
      return;
    }
    isJoining.value = true;
    joinMessage.value = null;
    try {
      final Map<String, dynamic> data;
      if (SeedUi.isActive) {
        data = await SeedConnect.join(found);
      } else {
        final page = await auth.publicPage(found.display);
        final extra =
            (((page['onboarding'] as Map?)?[category]
                    as Map?)?['requiredFields']
                as List?) ??
            [];
        if (extra.isNotEmpty) {
          joinMessage.value =
              'Joining as $category needs more details than the mobile app supports yet.';
          return;
        }
        final check = await auth.joinCheck(found.display, category);
        final fields = (check['fields'] as Map?) ?? {};
        if (fields.isNotEmpty) {
          joinMessage.value = '${fields.values.first}';
          return;
        }
        data = await auth.join(found.display, category, branch: found.branch);
      }
      await _afterJoin(found, category, data);
    } on ApiException catch (e) {
      if (!_isOpen) return;
      if (e.code == 'unauthenticated') {
        _toLogin();
      } else if (e.code == 'already') {
        await _refreshMe();
        membership.value = _membershipOf(found);
        if (membership.value == null) joinMessage.value = ApiMessages.of(e);
      } else if (e.code == 'rate_limited' || e.status == 429) {
        joinMessage.value =
            'Too many join requests. ${_waitText(e.retryAfterSeconds ?? 3600)}';
      } else {
        joinMessage.value = ApiMessages.of(e);
      }
    } finally {
      isJoining.value = false;
    }
  }

  Future<void> _afterJoin(
    ConnectCard found,
    String category,
    Map<String, dynamic> data,
  ) async {
    final isPending =
        data['status'] == 'pending' || data['nextStep'] == 'approval';
    if (SeedUi.isActive) {
      _seedAdd(found, category, isPending ? 'pending' : 'active');
    } else {
      await _refreshMe();
    }
    if (!_isOpen) return;
    final text = idText(data['welcome']);
    welcome.value = text.isEmpty ? null : text;
    membership.value = _membershipOf(found);
    outcome.value = isPending
        ? ConnectOutcome.requestSent
        : ConnectOutcome.joined;
    phase.value = ConnectPhase.done;
  }

  Future<void> _refreshMe() async {
    try {
      await auth.refreshMe();
    } on ApiException catch (_) {}
  }

  void _seedAdd(ConnectCard found, String category, String status) {
    final current = store.identity.value;
    if (current == null) return;
    store.identity.value = current.copyWith(
      enterprises: [
        ...current.enterprises,
        EnterpriseMembership(
          enterprise: found.display,
          name: found.name,
          city: '',
          category: category,
          username: 'alex',
          status: status,
        ),
      ],
    );
  }

  void _toLogin() {
    session.loginNotice.value = SessionRepository.endedNotice;
    Get.offAllNamed(AppRoutes.authentication);
  }

  @override
  void onClose() {
    close();
    query.dispose();
    queryFocus.dispose();
    super.onClose();
  }
}
