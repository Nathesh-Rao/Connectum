import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../../features/connect_target/connect_target_controller.dart';
import '../../features/connect_target/connect_target_sheet.dart';
import '../debug/connect_flow_log.dart';
import '../debug/seed_ui.dart';
import '../utils/connect_code.dart';
import '../utils/install_referrer.dart';
import '../widgets/app_notice_card.dart';
import '../widgets/app_notices.dart';
import 'app_routes.dart';
import 'home_reload.dart';

/// The one receiver of Connectum links: the cold-start link, links while the
/// app runs, and codes handed over by the in-app scanner. Raw text only ever
/// becomes a code through [ConnectLinkParser]. The pending target (code, org,
/// branch) is kept in memory and in secure storage until it is used,
/// cancelled, expired (24 hours), or the person signs out or the session is
/// replaced. It survives a join, the wait for approval and an app restart.
/// What a pending person's target needs next, from the person's standing in
/// the organisation it names.
enum PendingPersonStep { confirm, join, wait, enter, rejected }

/// What the service does after the connect sheet is gone.
enum SheetClose { none, reopen, notice }

class DeepLinkService extends GetxService with WidgetsBindingObserver {
  DeepLinkService(
    this._appLinks,
    this._store,
    this._connectivity,
    this._referrer,
  );

  static const _storageKey = 'connect.pending';
  static const _savedAtKey = 'connect.pending.at';
  static const expiry = Duration(hours: 24);
  // Once per install: sign out never clears it.
  static const _firstStartKey = 'install.first_start';
  static const _repeatWindow = Duration(seconds: 10);
  static const _blockedRoutes = {
    AppRoutes.splash,
    AppRoutes.onboarding,
    AppRoutes.authentication,
    AppRoutes.verification,
    AppRoutes.enterpriseCreated,
    AppRoutes.form,
  };

  final AppLinks _appLinks;
  final SessionStore _store;
  final ConnectivityService _connectivity;
  final InstallReferrerSource _referrer;
  StreamSubscription<Uri>? _subscription;
  final _ready = Completer<void>();

  final pending = Rxn<ConnectCode>();

  /// True on an install's first start that found no invite: the welcome and
  /// sign-in screens suggest scanning the QR code again.
  final showScanHint = false.obs;

  /// Set once by the app's bindings: exchanges a referrer claim token for its
  /// target (null when the server does not know it).
  Future<ConnectCode?> Function(String token)? claimResolver;

  /// The referrer carried a claim that turned out used, expired or limited.
  final isClaimInvalid = false.obs;

  /// An organisation the person chose to join from a link; the enterprises
  /// screen opens its join sheet on it.
  final joinRequest = Rxn<ConnectCode>();

  /// The link whose connect the person confirmed on the sheet and that is
  /// waiting for the organisation switch to finish. In memory only, set by
  /// the confirm tap, so [connect.scan] never runs without one.
  String? confirmedLink;

  /// The answer to the last `connect.scan`, kept until the person has seen it
  /// (the sheet is only a view of it).
  final outcome = Rxn<ConnectOutcome>();

  /// Set once by the app's bindings: runs `connect.scan` for a target.
  Future<ConnectOutcome> Function(ConnectCode target)? scanner;

  /// Set once by the app's bindings: refreshes the account's memberships and
  /// returns the person's status in the organisation [target] names (null when
  /// not a member or unknown).
  Future<String?> Function(ConnectCode target)? membershipStatus;

  bool _isSheetOpen = false;
  bool _isStarting = false;
  bool _isChecking = false;
  DateTime? _savedAt;
  // Null: the sheet was not closed by the person; else whether the target is
  // kept (offline, handed to a join).
  bool? _userClosed;
  int _reopens = 0;
  static const _maxReopens = 3;
  Future<ConnectOutcome>? _scanning;
  String? _lastLink;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _canShow =>
      (_store.hasEnterpriseSession || SeedUi.isActive) &&
      !_blockedRoutes.contains(Get.currentRoute);

  @override
  Future<void> onInit() async {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    ever(_connectivity.state, (state) {
      if (state == AppConnectivity.online) resume();
    });
    await _load();
    _subscription = _appLinks.uriLinkStream.listen(
      (uri) => receive(uri.toString()),
    );
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) receive(initial.toString());
    } finally {
      _ready.complete();
    }
  }

  /// The first start of an install: reads the install referrer once. The
  /// flag is set only after a conclusive answer, so an unavailable Play
  /// service is asked again next start and a read invite is never applied
  /// twice. A link that is already pending wins over the referrer.
  Future<void> runFirstStart() async {
    await _ready.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    if (await _store.readValue(_firstStartKey) != null) return;
    var read = const ReferrerRead.inconclusive();
    try {
      read = await _referrer.read().timeout(const Duration(seconds: 4));
    } catch (_) {}
    if (!read.isConclusive) return;
    await _store.writeValue(_firstStartKey, 'done');
    await startWith(read.referrer);
  }

  /// What the first start does with a referrer string: a valid code becomes
  /// the pending target, a claim token is exchanged once ([shouldClaim]), and
  /// without any target the scan hint shows.
  Future<void> startWith(String? referrer, {bool shouldClaim = true}) async {
    isClaimInvalid.value = false;
    if (pending.value == null) {
      final invite = InstallReferrerParser.read(referrer);
      if (invite.target != null) {
        keep(invite.target!);
      } else if (invite.claim != null && shouldClaim) {
        await _claim(invite.claim!);
      }
    }
    showScanHint.value = pending.value == null && !isClaimInvalid.value;
  }

  /// One call, never repeated: a used, expired or rate-limited token shows the
  /// "isn't valid any more" card.
  Future<void> _claim(String token) async {
    final resolve = claimResolver;
    if (resolve == null) return;
    try {
      final target = await resolve(token);
      if (target == null) {
        isClaimInvalid.value = true;
      } else if (pending.value == null) {
        keep(target);
      }
    } catch (_) {
      isClaimInvalid.value = true;
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) resume();
  }

  Future<void> _load() async {
    final saved = await _store.readValue(_storageKey);
    if (saved == null || pending.value != null) return;
    final target = ConnectLinkParser.parse(saved).value;
    final at = int.tryParse(await _store.readValue(_savedAtKey) ?? '');
    final savedAt = at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
    if (target == null || isExpired(savedAt, DateTime.now())) {
      await clear();
      return;
    }
    _savedAt = savedAt;
    pending.value = target;
    ConnectFlowLog.log('pending loaded', {'person': target.isPersonLink});
  }

  /// A target saved without a time (an older install) counts as expired.
  static bool isExpired(DateTime? savedAt, DateTime now) =>
      savedAt == null || now.difference(savedAt) >= expiry;

  /// The one rule for where a pending person's target goes next.
  static PendingPersonStep stepFor({
    required bool isInOrg,
    required String? status,
  }) {
    if (isInOrg) return PendingPersonStep.confirm;
    return switch (status) {
      null => PendingPersonStep.join,
      'pending' => PendingPersonStep.wait,
      'active' => PendingPersonStep.enter,
      _ => PendingPersonStep.rejected,
    };
  }

  static String _plain(String id) => id.replaceAll('-', '').toUpperCase();

  bool _isCurrentOrg(ConnectCode target) =>
      _store.orgId != null &&
      _plain(_store.orgId!) == _plain(target.org ?? target.code);

  void _save(ConnectCode target) {
    ConnectFlowLog.log('pending stored', {
      'person': target.isPersonLink,
      'by': ConnectFlowLog.caller(),
    });
    _savedAt = DateTime.now();
    unawaited(_store.writeValue(_storageKey, target.linkText));
    unawaited(
      _store.writeValue(
        _savedAtKey,
        _savedAt!.millisecondsSinceEpoch.toString(),
      ),
    );
  }

  /// A raw link or scanned text. Unreadable text is ignored.
  void receive(String raw) {
    final target = ConnectLinkParser.parse(raw).value;
    if (target != null) receiveCode(target);
  }

  /// A code that already went through the parser (the in-app scanner).
  void receiveCode(ConnectCode target) {
    ConnectFlowLog.log('receive', {'person': target.isPersonLink});
    final link = target.linkText;
    final now = DateTime.now();
    if (link == _lastLink && now.difference(_lastAt) < _repeatWindow) return;
    _lastLink = link;
    _lastAt = now;
    pending.value = target;
    showScanHint.value = false;
    _reopens = 0;
    _save(target);
    resume();
  }

  /// Remembers a target without opening anything (the join sheet found a
  /// person's code while the person is not in an organisation yet).
  void keep(ConnectCode target) {
    pending.value = target;
    showScanHint.value = false;
    _save(target);
  }

  /// Forgets the pending target. With [only], a newer target stays.
  Future<void> clear({ConnectCode? only}) async {
    final current = pending.value;
    if (only != null && current != null && current.linkText != only.linkText) {
      return;
    }
    ConnectFlowLog.log('pending cleared', {
      'had': current != null,
      'confirmed': confirmedLink != null,
      'by': ConnectFlowLog.caller(),
    });
    if (only == null) outcome.value = null;
    pending.value = null;
    confirmedLink = null;
    _lastLink = null;
    _savedAt = null;
    await _store.deleteValue(_storageKey);
    await _store.deleteValue(_savedAtKey);
  }

  /// Asks the enterprises screen to open its join sheet on [target].
  void requestJoin(ConnectCode target) {
    joinRequest.value = target;
    if (Get.currentRoute != AppRoutes.enterprises) {
      Get.toNamed(AppRoutes.enterprises);
    }
  }

  /// Shows the confirm sheet for the pending target when the person is in an
  /// organisation, on a screen that can take it, and the home is ready (no
  /// reload running or just done). Safe to call any number of times: while
  /// the sheet is open or a start is waiting, a call does nothing.
  Future<void> resume() async {
    final target = pending.value;
    ConnectFlowLog.log('resume', {
      'pending': target != null,
      'person': target?.isPersonLink,
      'inOrg': target != null && _isCurrentOrg(target),
      'confirmed': confirmedLink != null,
      'sheetOpen': _isSheetOpen,
      'starting': _isStarting,
      'reloading': HomeReload.isRunning,
    });
    if (target == null || !tryClaimSheet()) return;
    try {
      await HomeReload.settled();
      final next = pending.value;
      final context = Get.context;
      if (next == null || context == null || !_canShow || _isSheetOpen) return;
      if (isExpired(_savedAt, DateTime.now())) {
        await clear(only: next);
        return;
      }
      if (!await _isReadyToShow(next)) return;
      final ready = Get.context;
      if (pending.value?.linkText != next.linkText ||
          ready == null ||
          !ready.mounted ||
          _isSheetOpen) {
        return;
      }
      // After a switch the confirmed link scans at once, from here: a sheet
      // that is lost does not lose the answer.
      unawaited(
        scanIfConfirmed(next).then((result) {
          if (result != null) _noticeIfNoSheet();
        }),
      );
      _isSheetOpen = true;
      _userClosed = null;
      ConnectFlowLog.log('sheet opened', {'person': next.isPersonLink});
      unawaited(
        ConnectTargetSheet.show(ready, next).then((_) => _afterSheet()),
      );
    } finally {
      releaseSheetClaim();
    }
  }

  /// One start at a time: false while the sheet is open or a start waits.
  bool tryClaimSheet() {
    if (_isSheetOpen || _isStarting) return false;
    _isStarting = true;
    return true;
  }

  void releaseSheetClaim() => _isStarting = false;

  /// `connect.scan`, the one place it runs. The sheet's confirm tap and the
  /// confirmed link after a switch both come here; a second call for a scan in
  /// flight shares it.
  Future<ConnectOutcome?> scan(ConnectCode target) async {
    final run = scanner;
    if (run == null) return null;
    final inFlight = _scanning;
    if (inFlight != null) return inFlight;
    ConnectFlowLog.log('scan start', {'person': target.isPersonLink});
    outcome.value = null;
    final future = _scanning = run(target);
    try {
      final result = await future;
      ConnectFlowLog.log('scan result', {
        'failure': result.failure?.name,
        'final': result.isFinal,
      });
      outcome.value = result;
      if (result.isFinal) await clear(only: target);
      return result;
    } finally {
      _scanning = null;
    }
  }

  /// The scan after a switch: only for a link the person confirmed with the
  /// tap, now inside the organisation it names. A finished answer is reused.
  Future<ConnectOutcome?> scanIfConfirmed(
    ConnectCode target, {
    String? currentOrg,
  }) async {
    final done = outcome.value;
    if (done != null && done.link == target.linkText && done.isFinal) {
      return done;
    }
    final isConfirmed = ConnectTargetController.shouldScanAfterSwitch(
      confirmedLink: confirmedLink,
      link: target.linkText,
      currentOrg: currentOrg ?? _store.orgId,
      linkOrg: target.org,
    );
    if (!isConfirmed) return null;
    return scan(target);
  }

  /// Called by the sheet when the person closed it (not the home reload).
  void sheetClosedByUser({required bool isKept}) => _userClosed = isKept;

  void _afterSheet() {
    final isUser = _userClosed != null;
    final next = closeSheet(isUser: isUser, isKept: _userClosed ?? false);
    _userClosed = null;
    _isSheetOpen = false;
    switch (next) {
      case SheetClose.reopen:
        unawaited(resume());
      case SheetClose.notice:
        _noticeIfNoSheet();
      case SheetClose.none:
    }
  }

  /// The rules for a closed sheet. The person closing it ends the matter
  /// (the target is dropped unless [isKept]); anything else (the home reload,
  /// a route removal) leaves the target pending and the sheet comes back.
  SheetClose closeSheet({required bool isUser, bool isKept = false}) {
    ConnectFlowLog.log('sheet closed', {
      'reason': isUser ? 'user' : 'removed',
      'pending': pending.value != null,
      'outcome': outcome.value != null,
      'kept': isKept,
    });
    if (isUser) {
      _reopens = 0;
      outcome.value = null;
      if (!isKept) unawaited(clear());
      return SheetClose.none;
    }
    if (pending.value != null && _reopens < _maxReopens) {
      _reopens++;
      return SheetClose.reopen;
    }
    return outcome.value != null ? SheetClose.notice : SheetClose.none;
  }

  /// The answer arrived and no sheet shows it: a light notice card instead.
  void _noticeIfNoSheet() {
    final result = outcome.value;
    if (result == null || _isSheetOpen) return;
    outcome.value = null;
    AppNotices.show(
      result.noticeText,
      values: result.noticeValues,
      variant: result.failure == null
          ? AppNoticeVariant.success
          : AppNoticeVariant.warning,
    );
  }

  /// A person's target for another organisation waits, without a sheet, until
  /// the person is approved there; a rejection drops it with a notice.
  Future<bool> _isReadyToShow(ConnectCode target) async {
    final check = membershipStatus;
    if (!target.isPersonLink || check == null || _isCurrentOrg(target)) {
      return true;
    }
    if (_isChecking) return false;
    _isChecking = true;
    try {
      final status = await check(target);
      switch (stepFor(isInOrg: false, status: status)) {
        case PendingPersonStep.wait:
          return false;
        case PendingPersonStep.rejected:
          await clear(only: target);
          AppNotices.show(
            "Your request to join that enterprise wasn't approved, so the person could not be connected.",
            variant: AppNoticeVariant.warning,
          );
          return false;
        default:
          return pending.value?.linkText == target.linkText;
      }
    } finally {
      _isChecking = false;
    }
  }
}
