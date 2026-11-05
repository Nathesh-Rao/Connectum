import 'dart:async';

import 'package:get/get.dart';

import '../../data/api/api_client.dart';
import '../../data/models/connect_card.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/session_store.dart';
import '../debug/seed_connect.dart';
import '../debug/seed_ui.dart';
import '../utils/connect_code.dart';
import 'deep_link_service.dart';

enum InviteStatus { none, hint, loading, ready, invalid, rateLimited, failed }

/// What the welcome and sign-in screens say about the pending link while
/// nobody is signed in: "Join {organisation}" from the public card
/// (`GET /api/sd/connect/{code}`). The card is asked for once per target and
/// kept in memory; a failure is only asked again by a manual retry.
class InviteService extends GetxService {
  InviteService(this._auth, this._store, this._links);

  final AuthRepository _auth;
  final SessionStore _store;
  final DeepLinkService _links;

  final status = InviteStatus.none.obs;
  final card = Rxn<ConnectCard>();

  // A null card is a code the server does not know.
  final _cache = <String, ConnectCard?>{};
  int _viewers = 0;
  String? _loading;

  bool get hasInvite => _links.pending.value != null;
  String? get organisationName => card.value?.name;

  bool get _isVisible =>
      _viewers > 0 && (SeedUi.isActive || !_store.isSignedIn);

  @override
  void onInit() {
    super.onInit();
    ever(_links.pending, (_) => refresh());
    ever(_links.showScanHint, (_) => refresh());
    ever(_links.isClaimInvalid, (_) => refresh());
  }

  /// A screen that shows the card is open.
  void attach() {
    _viewers++;
    refresh();
  }

  void detach() {
    if (_viewers > 0) _viewers--;
  }

  void refresh() {
    if (!_isVisible) {
      status.value = InviteStatus.none;
      return;
    }
    final target = _links.pending.value;
    if (target == null) {
      card.value = null;
      status.value = _links.isClaimInvalid.value
          ? InviteStatus.invalid
          : _links.showScanHint.value
          ? InviteStatus.hint
          : InviteStatus.none;
      return;
    }
    final key = target.linkText;
    if (_cache.containsKey(key)) {
      _apply(_cache[key]);
    } else if (_loading != key) {
      unawaited(_load(target));
    }
  }

  void retry() {
    final target = _links.pending.value;
    if (target != null && _isVisible) unawaited(_load(target));
  }

  /// Forgets the invite (or, for the hint, only the hint).
  void dismiss() {
    if (_links.pending.value != null) {
      unawaited(_links.clear());
    } else {
      _links.showScanHint.value = false;
      _links.isClaimInvalid.value = false;
    }
  }

  void _apply(ConnectCard? found) {
    card.value = found;
    status.value = found == null ? InviteStatus.invalid : InviteStatus.ready;
  }

  Future<void> _load(ConnectCode target) async {
    final key = target.linkText;
    _loading = key;
    card.value = null;
    status.value = InviteStatus.loading;
    try {
      final found = SeedUi.isActive
          ? await SeedConnect.resolve(target)
          : await _auth.connectCard(target);
      _cache[key] = found;
      if (_links.pending.value?.linkText == key) _apply(found);
    } on ApiException catch (e) {
      final isGone =
          e.status == 404 || e.code == 'not_found' || e.code == 'invalid';
      if (isGone) _cache[key] = null;
      if (_links.pending.value?.linkText != key) return;
      if (isGone) {
        _apply(null);
      } else {
        status.value = e.code == 'rate_limited' || e.status == 429
            ? InviteStatus.rateLimited
            : InviteStatus.failed;
      }
    } finally {
      if (_loading == key) _loading = null;
    }
  }

  String get title => switch (status.value) {
    InviteStatus.ready => 'Join ${card.value?.name ?? 'this enterprise'}',
    InviteStatus.loading => 'Checking your invite…',
    InviteStatus.invalid => "This invite isn't valid any more",
    InviteStatus.rateLimited => 'Try again in a moment',
    InviteStatus.failed => "Couldn't check this invite",
    _ => 'Came here from a QR code?',
  };

  String? get message => switch (status.value) {
    InviteStatus.ready =>
      card.value?.branch != null
          ? 'Branch: ${card.value!.branch}'
          : 'Sign in or create an account to continue.',
    InviteStatus.hint => 'Scan it again with your camera.',
    InviteStatus.failed => 'Check your connection, then try again.',
    _ => null,
  };

  String? get actionLabel => switch (status.value) {
    InviteStatus.invalid => 'Dismiss',
    InviteStatus.rateLimited || InviteStatus.failed => 'Try again',
    _ => null,
  };
}
