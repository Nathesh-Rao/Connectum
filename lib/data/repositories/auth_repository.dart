import 'package:get/get.dart';

import '../../core/utils/connect_code.dart';
import '../api/api_client.dart';
import '../models/connect_card.dart';
import '../models/identity_info.dart';
import '../models/ids.dart';
import '../session_store.dart';
import 'session_repository.dart';

enum LoginStartKind { codeSent, trusted, throttled }

class LoginStart {
  const LoginStart(this.kind, {this.retryAfter = 0, this.expiresInSec = 300});

  final LoginStartKind kind;
  final int retryAfter;
  final int expiresInSec;
}

/// The account needs a step the mobile app does not support (2FA or a
/// forced password change).
class UnsupportedStep implements Exception {
  const UnsupportedStep(this.reasons);

  final List<String> reasons;
}

class SetupResult {
  const SetupResult(this.enterpriseId, this.name);

  final String enterpriseId;
  final String name;
}

class EnterpriseHit {
  const EnterpriseHit(this.id, this.name, this.city);

  final String id;
  final String name;
  final String city;
}

class AuthRepository extends GetxService {
  AuthRepository(this._api, this._store, this._session);

  final ApiClient _api;
  final SessionStore _store;
  final SessionRepository _session;

  String _identityToken() {
    final token = _store.identity.value?.token;
    if (token == null) throw const ApiException('unauthenticated', '');
    return token;
  }

  // ---- sign in ----------------------------------------------------------------

  Future<LoginStart> startLogin(String email) async {
    final trust = await _store.trustFor(email);
    try {
      return await _startLogin(email, trust);
    } on ApiException catch (e) {
      const keep = {
        'no_account',
        'rate_limited',
        'invalid',
        'network',
        'bad_response',
      };
      if (trust == null || keep.contains(e.code)) rethrow;
      // A trusted start that fails drops the stored token and asks for a code.
      await _store.clearTrust(email);
      return _startLogin(email, null);
    }
  }

  Future<LoginStart> _startLogin(String email, String? trust) async {
    final data = await _api.post(
      '/login/start',
      body: {'email': email, 'trust': ?trust},
    );
    if (data['trusted'] == true && data['token'] != null) {
      await _acceptIdentity(data, email);
      return const LoginStart(LoginStartKind.trusted);
    }
    if (data['sent'] == false) {
      return LoginStart(
        LoginStartKind.throttled,
        retryAfter: intOf(data['retryAfter']),
      );
    }
    return LoginStart(
      LoginStartKind.codeSent,
      expiresInSec: data['expiresInSec'] == null
          ? 300
          : intOf(data['expiresInSec']),
    );
  }

  Future<IdentityInfo> verifyLogin(String email, String otp) async {
    final data = await _api.post(
      '/login/verify',
      body: {'email': email, 'otp': otp, 'deviceId': await _store.deviceId()},
    );
    final trust = data['trust'];
    if (trust is String && trust.isNotEmpty) {
      await _store.saveTrust(email, trust);
    }
    return _acceptIdentity(data, email);
  }

  // ---- set up an enterprise -----------------------------------------------------

  Future<LoginStart> startSetup(Map<String, dynamic> body) async {
    final data = await _api.post('/setup/start', body: body);
    if (data['sent'] == false) {
      return LoginStart(
        LoginStartKind.throttled,
        retryAfter: intOf(data['retryAfter']),
      );
    }
    return LoginStart(
      LoginStartKind.codeSent,
      expiresInSec: data['expiresInSec'] == null
          ? 300
          : intOf(data['expiresInSec']),
    );
  }

  /// Creates the enterprise. The answer holds the account (identity) session
  /// and a session inside the new enterprise: both are stored like the sign-in
  /// and enter flows do, and the socket starts.
  Future<SetupResult> verifySetup(String email, String otp) async {
    final data = await _api.post(
      '/setup/verify',
      body: {'email': email, 'otp': otp, 'deviceId': await _store.deviceId()},
    );
    final session = ((data['session'] as Map?) ?? {}).cast<String, dynamic>();
    _checkBlockers(data);
    _checkBlockers(session);
    await _store.saveIdentity(
      IdentityInfo.fromResponse(
        idText(data['token']),
        data,
        fallbackEmail: email,
      ),
    );
    final user = ((session['user'] as Map?) ?? {}).cast<String, dynamic>();
    final enterpriseId = idText(session['enterprise'] ?? data['enterprise']);
    await _session.signIn(
      orgId: enterpriseId,
      userId: idText(user['username']),
      token: idText(session['token']),
      expiresTs: session['expiresTs'] == null
          ? null
          : intOf(session['expiresTs']),
      orgName: idText(data['name']),
    );
    return SetupResult(
      idText(data['enterprise'] ?? enterpriseId),
      idText(data['name']),
    );
  }

  // ---- create account -----------------------------------------------------------

  Future<void> startRegister(Map<String, dynamic> body) async {
    await _api.post('/register/start', body: body);
  }

  Future<IdentityInfo> verifyRegister(String email, String otp) async {
    final data = await _api.post(
      '/register/verify',
      body: {'email': email, 'otp': otp, 'deviceId': await _store.deviceId()},
    );
    return _acceptIdentity(data, email);
  }

  Future<IdentityInfo> _acceptIdentity(
    Map<String, dynamic> data,
    String email,
  ) async {
    _checkBlockers(data);
    final info = IdentityInfo.fromResponse(
      idText(data['token']),
      data,
      fallbackEmail: email,
    );
    await _store.saveIdentity(info);
    return info;
  }

  void _checkBlockers(Map<String, dynamic> data) {
    final reasons = [
      if (data['totpDue'] == true) 'two-step verification (totpDue)',
      if (data['mustChangePassword'] == true)
        'a required password change (mustChangePassword)',
    ];
    if (reasons.isNotEmpty) throw UnsupportedStep(reasons);
  }

  Future<List<String>> countries() async {
    final data = await _api.get('/geo/countries');
    return ((data['countries'] as List?) ?? []).map(idText).toList();
  }

  Future<List<String>> cities(String country) async {
    final data = await _api.get('/geo/cities', query: {'country': country});
    return ((data['cities'] as List?) ?? []).map(idText).toList();
  }

  // ---- enterprises ---------------------------------------------------------------

  Future<IdentityInfo?> refreshMe() async {
    final current = _store.identity.value;
    if (current == null) return null;
    final data = await _api.get('/me', bearer: current.token);
    final identity = ((data['identity'] as Map?) ?? {}).cast<String, dynamic>();
    final next = current.copyWith(
      enterprises: IdentityInfo.parseEnterprises(data['enterprises']),
      expiresTs: data['sessionExpiresTs'] == null
          ? null
          : intOf(data['sessionExpiresTs']),
      connectumId: idText(identity['connectumId']).isEmpty
          ? null
          : idText(identity['connectumId']),
    );
    await _store.saveIdentity(next);
    return next;
  }

  /// The person's status in the organisation a person's link names, after a
  /// best-effort refresh of the account's memberships. Null when not a member.
  Future<String?> membershipStatus(ConnectCode target) async {
    try {
      await refreshMe();
    } on ApiException catch (_) {}
    String plain(String id) => id.replaceAll('-', '').toUpperCase();
    final org = plain(target.org ?? target.code);
    for (final m in _store.identity.value?.enterprises ?? const []) {
      if (plain(m.enterprise) == org) return m.status;
    }
    return null;
  }

  Future<List<EnterpriseHit>> search(String query) async {
    final data = await _api.get('/enterprises', query: {'q': query});
    return ((data['enterprises'] as List?) ?? []).whereType<Map>().map((e) {
      return EnterpriseHit(
        idText(e['enterprise']),
        idText(e['name']),
        idText(e['city']),
      );
    }).toList();
  }

  /// A Connectum ID typed in the search box (the public page by ID).
  Future<EnterpriseHit?> byId(String id) async {
    try {
      final data = await _api.get('/enterprise/$id');
      return EnterpriseHit(
        idText(data['enterprise']),
        idText(data['name']),
        '',
      );
    } on ApiException catch (e) {
      if (e.code == 'not_found') return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> publicPage(String id) =>
      _api.get('/enterprise/$id');

  /// The organisation's public card for a scanned or typed code (no session).
  Future<ConnectCard> connectCard(ConnectCode link) async {
    final data = await _api.get(
      '/connect/${link.code}',
      query: {'org': ?link.org, 'branch': ?link.branch},
    );
    return ConnectCard.fromJson(data);
  }

  /// Exchanges a referrer claim token for its invite (no session; used once,
  /// good for 24 hours). Null when the token is used or expired.
  Future<ConnectCode?> claimInvite(String token) async {
    try {
      final data = await _api.get(
        '/connect/claim/${Uri.encodeComponent(token)}',
      );
      final org = idText(data['org']);
      final branch = idText(data['branch']);
      return ConnectLinkParser.parse(
        Uri(
          scheme: 'https',
          host: ConnectLinkParser.publicHost,
          pathSegments: ['connect', idText(data['code'])],
          queryParameters: {
            if (org.isNotEmpty) 'org': org,
            if (branch.isNotEmpty) 'branch': branch,
          },
        ).toString(),
      ).value;
    } on ApiException catch (e) {
      if (e.status == 404 || e.code == 'not_found') return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> joinCheck(String enterprise, String category) =>
      _api.post(
        '/join/check',
        body: {
          'enterprise': enterprise,
          'isEmployee': false,
          'category': category,
        },
        bearer: _identityToken(),
      );

  Future<Map<String, dynamic>> join(
    String enterprise,
    String category, {
    String? branch,
  }) async {
    final data = await _api.post(
      '/join',
      body: {
        'enterprise': enterprise,
        'isEmployee': false,
        'category': category,
        'connectBranch': ?branch,
      },
      bearer: _identityToken(),
    );
    return data;
  }

  /// Enters one enterprise: stores its session and starts the socket.
  Future<void> enter(String enterprise) async {
    final identity = _store.identity.value;
    if (identity == null) throw const ApiException('unauthenticated', '');
    try {
      final data = await _api.enter(
        identity.token,
        enterprise,
        await _store.deviceId(),
      );
      _checkBlockers(data);
      final user = ((data['user'] as Map?) ?? {}).cast<String, dynamic>();
      final current = _store.orgId;
      if (current != null) {
        // The server already ended the old token when it is the same enterprise.
        await _session.leaveCurrent(endOnServer: current != enterprise);
      }
      await _session.signIn(
        orgId: idText(data['enterprise'] ?? enterprise),
        userId: idText(user['username']),
        token: idText(data['token']),
        expiresTs: data['expiresTs'] == null ? null : intOf(data['expiresTs']),
        orgName: identity.enterprises
            .where((e) => e.enterprise == enterprise)
            .map((e) => e.name)
            .firstOrNull,
      );
    } on ApiException catch (e) {
      if (e.code == 'unauthenticated') await _store.clearIdentity();
      rethrow;
    }
  }

  /// Leaves the account (identity) session. Cached enterprise data stays.
  Future<void> signOutIdentity() async {
    final token = _store.identity.value?.token;
    if (token != null) {
      try {
        await _api.post('/logout', bearer: token);
      } catch (_) {}
    }
    await _session.clearConnectTarget();
    await _store.clearIdentity();
  }
}
