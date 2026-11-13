import '../data/api/api_client.dart';
import '../data/models/identity_info.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/session_store.dart';
import 'demo_mode.dart';

/// Any email and any code sign in as the demo person. No request leaves the
/// device.
class DemoAuthRepository extends AuthRepository {
  // ignore: use_super_parameters
  DemoAuthRepository(
    ApiClient api,
    SessionStore store,
    SessionRepository session,
  ) : _store = store,
      _session = session,
      super(api, store, session);

  final SessionStore _store;
  final SessionRepository _session;

  static const _delay = Duration(milliseconds: 500);

  @override
  Future<LoginStart> startLogin(String email) async {
    await Future<void>.delayed(_delay);
    return const LoginStart(LoginStartKind.codeSent);
  }

  @override
  Future<LoginStart> startSetup(Map<String, dynamic> body) async {
    await Future<void>.delayed(_delay);
    return const LoginStart(LoginStartKind.codeSent);
  }

  @override
  Future<void> startRegister(Map<String, dynamic> body) =>
      Future<void>.delayed(_delay);

  @override
  Future<IdentityInfo> verifyLogin(String email, String otp) => _accept(email);

  /// `demo1234` signs in with any email; anything else is the same
  /// `invalid_credentials` the server answers.
  @override
  Future<IdentityInfo> loginWithPassword(String email, String password) async {
    await Future<void>.delayed(_delay);
    if (password != 'demo1234') {
      throw const ApiException(
        'invalid_credentials',
        'That email and password do not match. You can sign in with an emailed code instead.',
        status: 401,
      );
    }
    return _accept(email);
  }

  @override
  Future<LoginStart> startPasswordChange() async {
    await Future<void>.delayed(_delay);
    return const LoginStart(LoginStartKind.codeSent);
  }

  @override
  Future<void> setPassword(String otp, String newPassword) async {
    await Future<void>.delayed(_delay);
    await _remember(true);
  }

  @override
  Future<void> removePassword(String otp) async {
    await Future<void>.delayed(_delay);
    await _remember(false);
  }

  Future<void> _remember(bool value) async {
    final current = _store.identity.value;
    if (current != null) {
      await _store.saveIdentity(current.copyWith(hasPassword: value));
    }
  }

  @override
  Future<IdentityInfo> verifyRegister(String email, String otp) =>
      _accept(email);

  @override
  Future<SetupResult> verifySetup(String email, String otp) async {
    await _accept(email);
    final (name, id) = DemoMode.orgs.first;
    await _session.signIn(
      orgId: id,
      userId: DemoMode.username,
      token: 'demo',
      orgName: name,
    );
    return SetupResult(id, name);
  }

  Future<IdentityInfo> _accept(String email) async {
    await Future<void>.delayed(_delay);
    final info = DemoMode.identity(email);
    await _store.saveIdentity(info);
    return info;
  }

  @override
  Future<List<String>> countries() async => const ['India', 'United States'];

  @override
  Future<List<String>> cities(String country) async => const [
    'Chennai',
    'Bengaluru',
    'Mumbai',
  ];

  @override
  Future<IdentityInfo?> refreshMe() async => _store.identity.value;

  @override
  Future<List<EnterpriseHit>> search(String query) async => const [];

  @override
  Future<EnterpriseHit?> byId(String id) async => null;

  @override
  Future<void> enter(String enterprise) async {
    await Future<void>.delayed(_delay);
    final name = DemoMode.orgs
        .where((o) => o.$2 == enterprise)
        .map((o) => o.$1)
        .firstOrNull;
    await _session.signIn(
      orgId: enterprise,
      userId: DemoMode.username,
      token: 'demo',
      orgName: name,
    );
  }

  @override
  Future<void> signOutIdentity() async {
    await _store.clearIdentity();
  }
}
