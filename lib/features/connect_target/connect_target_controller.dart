import 'dart:async';

import 'package:get/get.dart';

import '../../core/debug/connect_flow_log.dart';
import '../../core/debug/seed_connect.dart';
import '../../core/debug/seed_ui.dart';
import '../../core/routes/app_routes.dart';
import '../../core/routes/conversation_route.dart';
import '../../core/routes/deep_link_service.dart';
import '../../core/routes/home_reload.dart';
import '../../core/theme/app_motion.dart';
import '../../core/utils/connect_code.dart';
import '../../core/widgets/app_notice_card.dart';
import '../../core/widgets/app_notices.dart';
import '../../data/api/api_client.dart';
import '../../data/api/api_messages.dart';
import '../../data/models/connect_card.dart';
import '../../data/models/connect_lookup.dart';
import '../../data/models/identity_info.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/connect_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';

enum ConnectTargetStep {
  resolving,
  person,
  organisation,
  otherOrganisation,
  connected,
  alreadyAssociates,
  failed,
}

enum ConnectTargetFailure {
  notFound,
  invalid,
  rateLimited,
  offline,
  refused,
  other,
}

/// What one tap does for a code that names another organisation, from the
/// person's standing there.
enum OtherOrganisationPlan {
  connectAfterSwitch,
  switchOnly,
  join,
  wait,
  rejected,
}

/// The answer to a `connect.scan`, kept by [DeepLinkService] until the person
/// has seen it, so a sheet that was taken down does not lose it.
class ConnectOutcome {
  const ConnectOutcome({
    required this.link,
    this.person,
    this.isNew = false,
    this.failure,
    this.message,
    this.retryAfter,
  });

  final String link;
  final ConnectPerson? person;
  final bool isNew;
  final ConnectTargetFailure? failure;
  final String? message;
  final int? retryAfter;

  /// Connected, already associated, not found, invalid or refused: the target
  /// is done. Offline, rate limited and other failures keep it.
  bool get isFinal =>
      failure == null ||
      failure == ConnectTargetFailure.notFound ||
      failure == ConnectTargetFailure.invalid ||
      failure == ConnectTargetFailure.refused;

  /// A template: `{you}` and `{name}` are filled from [noticeValues].
  String get noticeText {
    if (failure == null) {
      return isNew
          ? '{you} are now connected with {name}.'
          : '{you} are already connected with {name}.';
    }
    return isFinal
        ? "The person couldn't be connected. Ask for a new QR code."
        : "Couldn't finish connecting yet. We'll try again when you're back.";
  }

  Map<String, String> get noticeValues => {
    'you': 'You',
    'name': person?.name ?? 'them',
  };
}

/// Confirms a scanned or opened Connectum code inside the signed-in
/// organisation: looks it up (connects nothing), asks, and only then connects.
class ConnectTargetController extends GetxController {
  ConnectTargetController({
    required this.target,
    required this.repository,
    required this.auth,
    required this.store,
    required this.session,
    required this.connectivity,
    required this.links,
  });

  final ConnectRepository repository;
  final AuthRepository auth;
  final SessionStore store;
  final SessionRepository session;
  final ConnectivityService connectivity;
  final DeepLinkService links;

  ConnectCode target;

  final step = ConnectTargetStep.resolving.obs;
  final failure = ConnectTargetFailure.other.obs;
  final message = RxnString();
  final retryAfter = RxnInt();
  final person = Rxn<ConnectPerson>();
  final card = Rxn<ConnectCard>();
  final membership = Rxn<EnterpriseMembership>();
  final isBusy = false.obs;

  /// True while the target must outlive a close by the person: offline, or
  /// handed on to a switch or a join.
  bool _isKept = false;

  bool get isOffline =>
      !SeedUi.isActive && connectivity.state.value == AppConnectivity.offline;

  @override
  void onInit() {
    super.onInit();
    ever(links.pending, (next) {
      if (next == null || next.linkText == target.linkText) return;
      target = next;
      load();
    });
    ever(connectivity.state, (state) {
      if (state == AppConnectivity.online &&
          step.value == ConnectTargetStep.failed &&
          failure.value == ConnectTargetFailure.offline) {
        load();
      }
    });
  }

  @override
  void onReady() {
    super.onReady();
    load();
  }

  /// The person closed the sheet (Cancel, Done, back, swipe or backdrop). A
  /// close by the home reload is not one: the service reopens the sheet.
  void onUserClosed() {
    if (HomeReload.isRunning) return;
    links.sheetClosedByUser(isKept: _isKept);
  }

  // ---- look up ----------------------------------------------------------------

  Future<void> load() async {
    final asked = target;
    _isKept = false;
    message.value = null;
    step.value = ConnectTargetStep.resolving;
    if (isOffline) {
      _fail(ConnectTargetFailure.offline);
      return;
    }
    final done = links.outcome.value;
    if (done != null && done.link == target.linkText && done.isFinal) {
      _apply(done);
      return;
    }
    if (shouldScanAfterSwitch(
      confirmedLink: links.confirmedLink,
      link: target.linkText,
      currentOrg: store.orgId,
      linkOrg: target.org,
    )) {
      final asked = target;
      final result = await links.scanIfConfirmed(asked);
      if (result != null && identical(asked, target)) _apply(result);
      return;
    }
    try {
      final found = await repository.lookup(asked);
      if (!identical(asked, target)) return;
      _show(found);
    } on SocketCallError catch (e) {
      if (!identical(asked, target)) return;
      await _onLookupError(e);
    }
  }

  void _show(ConnectLookup found) {
    final who = found.person;
    if (who != null) {
      person.value = who;
      step.value = found.isConnected
          ? ConnectTargetStep.alreadyAssociates
          : ConnectTargetStep.person;
      if (found.isConnected) unawaited(links.clear(only: target));
      return;
    }
    card.value = found.card;
    step.value = ConnectTargetStep.organisation;
  }

  Future<void> _onLookupError(SocketCallError e) async {
    switch (e.code) {
      case 'wrong_org':
        await _loadOtherOrganisation();
      case 'not_found':
        if (target.isPersonLink) {
          _fail(ConnectTargetFailure.notFound);
        } else {
          await _loadOtherOrganisation();
        }
      case 'invalid_code':
        _fail(ConnectTargetFailure.invalid);
      case 'rate_limited':
        _failRateLimited(e.details);
      case 'invalid' || 'forbidden':
        _fail(ConnectTargetFailure.refused, detail: e.message);
      default:
        _fail(
          e.isConnectionGap
              ? ConnectTargetFailure.offline
              : ConnectTargetFailure.other,
        );
    }
  }

  /// The code belongs to another organisation: its public card (no sign-in)
  /// says whose it is, and whether the person can switch to it or join it.
  Future<void> _loadOtherOrganisation() async {
    final asked = target;
    try {
      final found = SeedUi.isActive
          ? await SeedConnect.resolve(asked)
          : await auth.connectCard(asked);
      if (!identical(asked, target)) return;
      final current = store.orgId ?? SeedUi.currentOrgId;
      if (_plain(found.code) == _plain(current)) {
        _fail(ConnectTargetFailure.notFound);
        return;
      }
      card.value = found;
      membership.value = _membershipOf(found);
      step.value = ConnectTargetStep.otherOrganisation;
    } on ApiException catch (e) {
      if (!identical(asked, target)) return;
      if (e.code == 'unauthenticated') {
        _toLogin();
      } else if (e.code == 'not_found' || e.code == 'invalid') {
        _fail(ConnectTargetFailure.notFound);
      } else if (e.code == 'rate_limited' || e.status == 429) {
        _failRateLimited(e.details);
      } else if (e.code == 'network' || e.code == 'bad_response') {
        _fail(ConnectTargetFailure.offline);
      } else {
        _fail(ConnectTargetFailure.other);
      }
    }
  }

  EnterpriseMembership? _membershipOf(ConnectCard found) {
    final list = store.identity.value?.enterprises ?? const [];
    for (final m in list) {
      if (_plain(m.enterprise) == found.code) return m;
    }
    return null;
  }

  static String _plain(String id) => id.replaceAll('-', '').toUpperCase();

  // ---- connect ----------------------------------------------------------------

  /// The one tap that connects.
  Future<void> connect() async {
    if (isBusy.value || step.value != ConnectTargetStep.person) return;
    await _connectNow();
  }

  /// Runs `connect.scan`. Reached only from the confirm tap; after a switch
  /// the service runs it from the confirmed link (see [load]).
  Future<void> _connectNow() async {
    if (isBusy.value) return;
    if (isOffline) {
      _fail(ConnectTargetFailure.offline);
      return;
    }
    final asked = target;
    isBusy.value = true;
    try {
      final result = await links.scan(asked);
      if (result != null && identical(asked, target)) _apply(result);
    } finally {
      isBusy.value = false;
    }
  }

  void _apply(ConnectOutcome result) {
    final who = result.person;
    if (who != null) person.value = who;
    final kind = result.failure;
    if (kind != null) {
      retryAfter.value = result.retryAfter;
      _fail(kind, detail: result.message);
      return;
    }
    step.value = result.isNew
        ? ConnectTargetStep.connected
        : ConnectTargetStep.alreadyAssociates;
  }

  /// `connect.scan` as an outcome: errors become a failure kind, never thrown.
  static Future<ConnectOutcome> scanOutcome(
    ConnectRepository repository,
    ConnectCode target,
  ) async {
    final link = target.linkText;
    try {
      final result = await repository.scan(target);
      return ConnectOutcome(
        link: link,
        person: result.person,
        isNew: !result.isConnected,
      );
    } on SocketCallError catch (e) {
      final seconds = e.details is Map
          ? (e.details as Map)['retryAfter']
          : null;
      final kind = switch (e.code) {
        'not_found' || 'wrong_org' => ConnectTargetFailure.notFound,
        'invalid_code' => ConnectTargetFailure.invalid,
        'rate_limited' => ConnectTargetFailure.rateLimited,
        'invalid' || 'forbidden' => ConnectTargetFailure.refused,
        _ =>
          e.isConnectionGap
              ? ConnectTargetFailure.offline
              : ConnectTargetFailure.other,
      };
      return ConnectOutcome(
        link: link,
        failure: kind,
        message: e.message.isEmpty ? null : e.message,
        retryAfter: seconds is int ? seconds : null,
      );
    }
  }

  void openChat() {
    final username = person.value?.username ?? '';
    if (username.isEmpty) return;
    ConversationRoute.open('dm:${username.toLowerCase()}');
  }

  // ---- another organisation ------------------------------------------------------

  /// What the one tap on an other-organisation sheet does.
  static OtherOrganisationPlan planFor({
    required bool isPerson,
    required String? status,
  }) => switch (status) {
    null => OtherOrganisationPlan.join,
    'active' =>
      isPerson
          ? OtherOrganisationPlan.connectAfterSwitch
          : OtherOrganisationPlan.switchOnly,
    'pending' => OtherOrganisationPlan.wait,
    _ => OtherOrganisationPlan.rejected,
  };

  /// The only way `connect.scan` runs without a fresh tap on the sheet: the
  /// person's tap marked this link confirmed, and the switch landed in the
  /// organisation the link names.
  static bool shouldScanAfterSwitch({
    required String? confirmedLink,
    required String link,
    required String? currentOrg,
    required String? linkOrg,
  }) =>
      confirmedLink == link &&
      currentOrg != null &&
      linkOrg != null &&
      _plain(currentOrg) == _plain(linkOrg);

  bool get isConnectAfterSwitch =>
      planFor(
        isPerson: target.isPersonLink,
        status: membership.value?.status,
      ) ==
      OtherOrganisationPlan.connectAfterSwitch;

  /// Switches to the organisation the link names. A person's link is marked
  /// confirmed first: the new home reopens the sheet, which scans at once.
  /// An organisation's link is finished by the switch. A failed switch keeps
  /// the target and scans nothing.
  Future<void> switchOrganisation() async {
    final m = membership.value;
    if (m == null || !m.isActive || isBusy.value) return;
    if (SeedUi.isActive) {
      message.value = 'Sample data: nothing to switch to.';
      return;
    }
    if (isOffline) {
      _switchFailed('Connect to the internet to switch.');
      return;
    }
    isBusy.value = true;
    message.value = null;
    final asked = target;
    if (isConnectAfterSwitch) links.confirmedLink = asked.linkText;
    ConnectFlowLog.log('confirm tap', {
      'person': asked.isPersonLink,
      'confirmed': links.confirmedLink != null,
    });
    try {
      await auth.enter(m.enterprise);
      _isKept = true;
      if (!isConnectAfterSwitch) {
        _isKept = false;
        await links.clear(only: asked);
      }
      await HomeReload.run();
    } on UnsupportedStep {
      _switchFailed('This enterprise needs a step the app cannot do yet.');
    } on ApiException catch (e) {
      if (e.code == 'unauthenticated') {
        _toLogin();
      } else {
        _switchFailed(ApiMessages.of(e));
      }
    } finally {
      isBusy.value = false;
    }
  }

  void _switchFailed(String text) {
    links.confirmedLink = null;
    _isKept = true;
    AppNotices.show(text, variant: AppNoticeVariant.warning);
  }

  /// Hands the link to the existing "Join another enterprise" sheet. The
  /// caller closes this sheet.
  void joinOrganisation() {
    _isKept = true;
    unawaited(_requestJoinAfterClose());
  }

  Future<void> _requestJoinAfterClose() async {
    await Future<void>.delayed(AppDurations.slow);
    links.requestJoin(target);
  }

  // ---- failures ---------------------------------------------------------------

  void _fail(ConnectTargetFailure kind, {String? detail}) {
    failure.value = kind;
    message.value = detail != null && detail.isNotEmpty ? detail : null;
    _isKept = kind == ConnectTargetFailure.offline;
    if (kind == ConnectTargetFailure.notFound ||
        kind == ConnectTargetFailure.invalid ||
        kind == ConnectTargetFailure.refused) {
      unawaited(links.clear(only: target));
    }
    step.value = ConnectTargetStep.failed;
  }

  void _failRateLimited(Object? details) {
    final seconds = details is Map ? details['retryAfter'] : null;
    retryAfter.value = seconds is int ? seconds : null;
    _fail(ConnectTargetFailure.rateLimited);
  }

  void _toLogin() {
    _isKept = true;
    session.loginNotice.value = SessionRepository.endedNotice;
    Get.offAllNamed(AppRoutes.authentication);
  }

  String get failureTitle => switch (failure.value) {
    ConnectTargetFailure.notFound => "We couldn't find that code",
    ConnectTargetFailure.invalid => "That isn't a Connectum code",
    ConnectTargetFailure.rateLimited => 'Too many tries',
    ConnectTargetFailure.offline => "You're offline",
    ConnectTargetFailure.refused => "This can't be connected",
    ConnectTargetFailure.other => 'Something went wrong',
  };

  String get failureBody => switch (failure.value) {
    ConnectTargetFailure.notFound =>
      'The code may have been renewed, or it belongs to someone outside this organisation. Ask for a new QR code.',
    ConnectTargetFailure.invalid =>
      'Check the QR code or the link and try again.',
    ConnectTargetFailure.rateLimited => _waitText(retryAfter.value),
    ConnectTargetFailure.offline =>
      "Checking a code needs a connection. It is kept; try again when you're back online.",
    ConnectTargetFailure.refused =>
      message.value ?? "You can't connect with this code.",
    ConnectTargetFailure.other => 'Please try again in a moment.',
  };

  static String _waitText(int? seconds) {
    if (seconds == null) return 'Wait a few minutes, then try again.';
    if (seconds < 60) return 'Wait $seconds seconds, then try again.';
    final minutes = (seconds / 60).ceil();
    return 'Wait $minutes ${minutes == 1 ? 'minute' : 'minutes'}, then try again.';
  }

  /// What to tell the person about a membership that is not active yet: a
  /// template with `{name}` (the enterprise).
  String? get otherOrganisationNote {
    final m = membership.value;
    if (m == null || m.isActive) return null;
    return m.status == 'pending'
        ? 'Your request to join {name} is waiting for approval. {you} can switch to it once an administrator approves.'
        : "Your earlier request to join {name} wasn't approved. Contact the enterprise if you think that's a mistake.";
  }
}
