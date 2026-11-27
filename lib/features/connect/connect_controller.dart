import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/debug/seed_connect.dart';
import '../../core/data/app_countries.dart';
import '../../core/data/country_lookup.dart';
import '../../core/debug/seed_ui.dart';
import '../../core/routes/app_routes.dart';
import '../../core/routes/deep_link_service.dart';
import '../../core/theme/app_motion.dart';
import '../../core/utils/app_settings.dart';
import '../../core/utils/connect_code.dart';
import '../../core/widgets/app_notices.dart';
import '../../data/api/api_client.dart';
import '../../data/api/api_messages.dart';
import '../../data/models/connect_card.dart';
import '../../data/models/identity_info.dart';
import '../../data/models/ids.dart';
import '../../data/models/join_page.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/session_store.dart';
import 'models/join_flow.dart';
import '../../data/socket/connectivity_service.dart';
import '../../core/log/safe.dart';
import '../../core/log/app_log.dart';

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
    required this.links,
  });

  static const noticeHold = Duration(seconds: 2);
  static const _searchDebounce = Duration(milliseconds: 400);

  final AuthRepository auth;
  final SessionStore store;
  final SessionRepository session;
  final ConnectivityService connectivity;
  final DeepLinkService links;

  final mode = ConnectMode.scan.obs;
  final phase = ConnectPhase.entry.obs;

  // scanner
  final camera = Rxn<MobileScannerController>();
  final cameraState = ConnectCameraState.off.obs;
  final hasTorch = false.obs;
  final isTorchOn = false.obs;
  final scanNotice = RxnString();
  final isScanSuccess = false.obs;
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
  final joinFlow = Rxn<JoinFlow>();
  final isLoadingPage = false.obs;
  final pageMessage = RxnString();
  final fieldErrors = <String, String>{}.obs;
  final isJoining = false.obs;
  final joinMessage = RxnString();
  final _texts = <String, TextEditingController>{};
  List<String> _countries = const [];
  final failure = ConnectFailure.other.obs;
  final failureDetail = RxnString();
  final retryAfter = 0.obs;
  final outcome = ConnectOutcome.requestSent.obs;
  final welcome = RxnString();
  final awaitingFrom = RxnString();

  /// A person's code from a person's QR, kept in memory only until the
  /// "connect with the person" step exists.
  ConnectCode? keptPersonLink;
  ConnectCode? _link;
  bool _isOpen = false;

  /// Opened on a link that is already chosen: it is joined, not confirmed.
  bool _isJoinOnly = false;

  bool get isOffline =>
      !SeedUi.isActive && connectivity.state.value == AppConnectivity.offline;

  // ---- sheet ----------------------------------------------------------------------

  void open({ConnectCode? link}) {
    _isOpen = true;
    _isJoinOnly = link != null;
    _cooldownUntil = null;
    scanNotice.value = null;
    isScanSuccess.value = false;
    query.clear();
    results.clear();
    searchMessage.value = null;
    card.value = null;
    joinFlow.value = null;
    fieldErrors.clear();
    membership.value = null;
    awaitingFrom.value = null;
    keptPersonLink = null;
    _link = null;
    mode.value = ConnectMode.scan;
    phase.value = ConnectPhase.entry;
    WidgetsBinding.instance.addObserver(this);
    if (link != null) {
      fireAndLog('connect_controller', () => resolve(link));
    } else {
      fireAndLog('connect_controller', () => startCamera());
    }
  }

  void close() {
    _isOpen = false;
    final pending = links.pending.value;
    final status = membership.value?.status;
    // A request that waits for approval keeps the link so the flow can carry
    // on once it is approved; an organisation's own link is only kept when
    // the person has no organisation session yet.
    final isKept =
        status == 'active' ||
        (status == 'pending' &&
            (!store.hasEnterpriseSession || (_link?.isPersonLink ?? false)));
    if (_link != null &&
        pending != null &&
        _link!.linkText == pending.linkText &&
        !isKept) {
      fireAndLog('connect_controller', () => links.clear());
    }
    WidgetsBinding.instance.removeObserver(this);
    _noticeTimer?.cancel();
    _debounce?.cancel();
    queryFocus.unfocus();
    fireAndLog('connect_controller', () => stopCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isOpen) return;
    if (state == AppLifecycleState.paused) {
      fireAndLog('connect_controller', () => stopCamera(keepState: true));
    } else if (state == AppLifecycleState.resumed && _isScanning) {
      fireAndLog('connect_controller', () => startCamera());
    }
  }

  bool get _isScanning =>
      phase.value == ConnectPhase.entry && mode.value == ConnectMode.scan;

  void showManual() {
    mode.value = ConnectMode.manual;
    fireAndLog('connect_controller', () => stopCamera());
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (_isOpen && mode.value == ConnectMode.manual) {
        queryFocus.requestFocus();
      }
    });
  }

  void showScanner() {
    queryFocus.unfocus();
    mode.value = ConnectMode.scan;
    if (phase.value == ConnectPhase.entry)
      fireAndLog('connect_controller', () => startCamera());
  }

  /// Back to the entry step (scanner or manual) from a failure or the card.
  void backToEntry() {
    if (keptPersonLink != null) {
      keptPersonLink = null;
      fireAndLog('connect_controller', () => links.clear());
    }
    _isJoinOnly = false;
    phase.value = ConnectPhase.entry;
    card.value = null;
    joinFlow.value = null;
    fieldErrors.clear();
    isScanSuccess.value = false;
    if (mode.value == ConnectMode.scan)
      fireAndLog('connect_controller', () => startCamera());
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
    _detections = scanner.barcodes.listen(
      _onDetect,
      onError: streamOnError('connect_controller'),
    );
    camera.value = scanner;
    try {
      await scanner.start();
    } on MobileScannerException catch (e) {
      if (_scanner != scanner) return;
      cameraState.value = e.errorCode == MobileScannerErrorCode.permissionDenied
          ? ConnectCameraState.denied
          : ConnectCameraState.unavailable;
      await stopCamera(keepState: true);
    } catch (e, st) {
      AppLog.e('connect_controller', e, st);
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
    } catch (e, st) {
      AppLog.e('connect_controller', e, st);
    }
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
    } catch (e, st) {
      AppLog.e('connect_controller', e, st);
    }
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
    isScanSuccess.value = true;
    if (_shouldHandOff) {
      _handOff(link);
      return;
    }
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
      if (_shouldHandOff) {
        _handOff(link);
        return;
      }
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

  // ---- scanner hand-off ----------------------------------------------------------

  /// Inside an organisation a scanned or typed code goes through the same
  /// confirm sheet as a link from the phone's camera.
  bool get _shouldHandOff => store.hasEnterpriseSession && !_isJoinOnly;

  void _handOff(ConnectCode link) {
    Get.back<void>();
    Future<void>.delayed(AppDurations.slow, () => links.receiveCode(link));
  }

  // ---- resolve ----------------------------------------------------------------------

  Future<void> resolve(ConnectCode link) async {
    _link = link;
    phase.value = ConnectPhase.resolving;
    scanNotice.value = null;
    fireAndLog('connect_controller', () => stopCamera());
    if (isOffline) {
      _fail(ConnectFailure.offline);
      return;
    }
    try {
      final found = SeedUi.isActive
          ? await SeedConnect.resolve(link)
          : await auth.connectCard(link);
      if (!_isOpen) return;
      if (found.isBranchUnavailable) {
        link = link.withoutBranch();
        _link = link;
        AppNotices.show(ConnectCard.branchUnavailableText);
      }
      card.value = found;
      membership.value = _membershipOf(found);
      keptPersonLink = link.isPersonLink ? link : null;
      if (link.isPersonLink) links.keep(link);
      joinFlow.value = null;
      fieldErrors.clear();
      joinMessage.value = null;
      phase.value = ConnectPhase.confirm;
      if (membership.value == null) {
        fireAndLog('connect_controller', () => loadJoinPage());
      }
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

  /// What the person chooses from (`GET /enterprise/<id>`): the web's card.
  Future<void> loadJoinPage() async {
    final found = card.value;
    if (found == null || isLoadingPage.value) return;
    pageMessage.value = null;
    if (SeedUi.isActive) {
      _startFlow(JoinPage(categories: found.categories), found);
      return;
    }
    if (isOffline) {
      pageMessage.value = 'Connect to the internet to join.';
      return;
    }
    isLoadingPage.value = true;
    try {
      final data = await auth.publicPage(found.display);
      if (!_isOpen || card.value != found) return;
      _startFlow(JoinPage.fromJson(data), found);
    } on ApiException catch (e) {
      if (!_isOpen) return;
      pageMessage.value = ApiMessages.of(e);
    } catch (e, st) {
      AppLog.e('connect_controller', e, st);
      pageMessage.value = ApiMessages.of(e);
    } finally {
      isLoadingPage.value = false;
    }
  }

  void _setFlow(JoinFlow next) {
    joinFlow.value = next;
    joinMessage.value = null;
  }

  /// The flow's starting values: the account's name and username (as the web
  /// prefills them), the scanned branch when the organisation has it.
  void _startFlow(JoinPage page, ConnectCard found) {
    final identity = store.identity.value;
    final branch = page.branchNamed(found.branch);
    final seed = {
      'name': identity?.name ?? '',
      'username': identity?.username ?? '',
      'mobileIso': CountryLookup.deviceDefault().iso,
      'branch': ?branch,
    };
    joinFlow.value = JoinFlow(page: page, values: seed, seed: seed);
    _syncTexts();
  }

  String get identityEmail => store.identity.value?.email ?? '';

  /// The text controller of a typed field. It lives with the controller, so
  /// going back and forward keeps what was typed.
  TextEditingController textFor(String key) => _texts.putIfAbsent(
    key,
    () => TextEditingController(text: joinFlow.value?.values[key] ?? ''),
  );

  void _syncTexts() {
    final values = joinFlow.value?.values ?? const <String, String>{};
    for (final e in _texts.entries) {
      final text = values[e.key] ?? '';
      if (e.value.text != text) e.value.text = text;
    }
  }

  /// A typed or picked value of the employee or details step.
  void setValue(String key, String text) {
    final f = joinFlow.value;
    if (f == null) return;
    fieldErrors.remove(key);
    joinFlow.value = f.withValue(key, text);
    _syncTexts();
  }

  void chooseAssociate() {
    final f = joinFlow.value;
    if (f == null) return;
    fieldErrors.clear();
    _setFlow(f.chooseAssociate());
    _syncTexts();
  }

  void chooseEmployee() {
    final f = joinFlow.value;
    if (f == null) return;
    fieldErrors.clear();
    _setFlow(f.chooseEmployee());
    _syncTexts();
  }

  Future<List<String>> loadCountries() async {
    if (_countries.isNotEmpty) return _countries;
    try {
      _countries = await auth.countries();
    } on ApiException catch (e) {
      AppLog.w('connect_controller', 'countries ${e.code}');
    } catch (e, st) {
      AppLog.e('connect_controller', e, st);
    }
    return _countries;
  }

  Future<List<String>> loadCities() async {
    final country = joinFlow.value?.value('country') ?? '';
    if (country.isEmpty) return const [];
    try {
      return await auth.cities(country);
    } on ApiException catch (e) {
      AppLog.w('connect_controller', 'cities ${e.code}');
    } catch (e, st) {
      AppLog.e('connect_controller', e, st);
    }
    return const [];
  }

  /// A country's name picked for the profile: it also sets the mobile
  /// number's country code while no number is typed.
  void pickCountry(String name) {
    final f = joinFlow.value;
    if (f == null) return;
    setValue('country', name);
    final match = CountryLookup.matchName(name);
    if (match != null && (f.values['mobile'] ?? '').trim().isEmpty) {
      setValue('mobileIso', match.iso);
    }
  }

  void pickMobileCountry(AppCountry picked) =>
      setValue('mobileIso', picked.iso);

  void pickCategory(String value) {
    final f = joinFlow.value;
    if (f == null) return;
    fieldErrors.remove('category');
    _setFlow(f.pickCategory(value));
  }

  void pickAffiliate(String value) {
    final f = joinFlow.value;
    if (f == null) return;
    fieldErrors.remove('affiliate');
    fieldErrors.remove('affiliateBranch');
    _setFlow(f.pickAffiliate(value));
  }

  void pickNoAffiliate() {
    final f = joinFlow.value;
    if (f == null) return;
    fieldErrors.clear();
    _setFlow(f.pickNoAffiliate());
  }

  void pickBranch(String value) {
    final f = joinFlow.value;
    if (f == null) return;
    fieldErrors.remove('affiliateBranch');
    _setFlow(f.pickBranch(value));
  }

  /// The previous step, or back to the entry from the first one.
  void backStep() {
    final f = joinFlow.value;
    if (f == null || f.isFirst) {
      backToEntry();
      return;
    }
    fieldErrors.clear();
    _setFlow(f.back());
  }

  /// Checks the current step the way the web does, then moves on. An answer
  /// that says what is wrong stays; a check that cannot be reached does not
  /// block (the join decides at the end).
  Future<void> nextStep() async {
    final f = joinFlow.value;
    final found = card.value;
    if (f == null || found == null || isJoining.value) return;
    final local = f.problems();
    if (local.isNotEmpty) {
      fieldErrors.assignAll(local);
      return;
    }
    fieldErrors.clear();
    final body = f.checkBody();
    if (body != null && !SeedUi.isActive) {
      isJoining.value = true;
      try {
        final check = await auth.joinCheck(found.display, body);
        if (!_isOpen) return;
        final fields = check['fields'];
        if (check['ok'] == false || (fields is Map && fields.isNotEmpty)) {
          _showFields(fields is Map ? fields : const {}, f);
          return;
        }
      } on ApiException catch (e) {
        if (!_isOpen) return;
        if (e.code == 'unauthenticated') {
          _toLogin();
          return;
        }
        if (e.code != 'rate_limited' && e.status != 429) {
          joinMessage.value = ApiMessages.of(e);
        }
      } catch (e, st) {
        AppLog.e('connect_controller', e, st);
      } finally {
        isJoining.value = false;
      }
    }
    final current = joinFlow.value;
    if (current == null || !_isOpen) return;
    joinFlow.value = current.advance();
  }

  /// Puts the server's messages under their fields. A message for a field
  /// that has no input on the step the person is on is shown as the message.
  void _showFields(Map fields, JoinFlow f) {
    final errors = {for (final e in fields.entries) '${e.key}': '${e.value}'};
    fieldErrors.assignAll(errors);
    final shown = f.fieldKeys(f.step);
    final other = errors.entries.where((e) => !shown.contains(e.key));
    if (other.isNotEmpty) joinMessage.value = other.first.value;
  }

  Future<void> join() async {
    final found = card.value;
    final f = joinFlow.value;
    if (found == null || f == null || isJoining.value) return;
    if (isOffline) {
      joinMessage.value = 'Connect to the internet to join.';
      return;
    }
    isJoining.value = true;
    joinMessage.value = null;
    try {
      final Map<String, dynamic> data = SeedUi.isActive
          ? await SeedConnect.join(found)
          : await auth.join(found.display, f.joinBody(), branch: found.branch);
      await _afterJoin(found, f.category, data);
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
        final fields = e.fieldErrors;
        if (fields.isNotEmpty) _showFields(fields, f);
        joinMessage.value ??= ApiMessages.of(e);
        _showJoinErrorStep(f, fields.isNotEmpty ? fields.keys : _codeKeys(e));
      }
    } finally {
      isJoining.value = false;
    }
  }

  static Iterable<String> _codeKeys(ApiException e) =>
      e.code == 'code_required' ? const ['employeeCode'] : const [];

  /// Goes back to the details step for a refused detail (as the web does) and
  /// to the code step for the code; any other refusal stays on the review.
  void _showJoinErrorStep(JoinFlow f, Iterable<String> keys) {
    if (keys.isEmpty) return;
    if (keys.contains('employeeCode') && fieldErrors['employeeCode'] == null) {
      fieldErrors['employeeCode'] = joinMessage.value ?? JoinFlow.enterCode;
    }
    final target = f.stepOwning(keys);
    if (target != JoinStep.details && target != JoinStep.employee) return;
    final current = joinFlow.value;
    if (current != null) joinFlow.value = current.copyWith(step: target);
  }

  Future<void> _afterJoin(
    ConnectCard found,
    String category,
    Map<String, dynamic> data,
  ) async {
    final isPending =
        data['status'] == 'pending' || data['nextStep'] == 'approval';
    awaitingFrom.value = isPending
        ? _approvers(data['awaitingApprovalFrom'])
        : null;
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

  /// `awaitingApprovalFrom` is a count of approvers.
  static String? _approvers(Object? value) {
    if (value is int && value > 0) {
      return value == 1 ? '1 approver' : '$value approvers';
    }
    final text = idText(value);
    return text.isEmpty || text == '0' ? null : text;
  }

  Future<void> _refreshMe() async {
    try {
      await auth.refreshMe();
    } on ApiException catch (e) {
      AppLog.w('connect_controller', '${e.runtimeType}');
    } catch (e, st) {
      AppLog.e('connect_controller', e, st);
    }
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
    for (final t in _texts.values) {
      t.dispose();
    }
    query.dispose();
    queryFocus.dispose();
    super.onClose();
  }
}
