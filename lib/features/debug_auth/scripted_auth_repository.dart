import '../../data/api/api_client.dart';
import '../../data/models/identity_info.dart';
import '../../data/repositories/auth_repository.dart';

enum PasswordOutcome { wrong, locked, lockedWithTime, network }

/// Debug only: answers the password sign-in with the chosen refusal and
/// sends nothing to a server.
class ScriptedAuthRepository extends AuthRepository {
  // ignore: use_super_parameters
  ScriptedAuthRepository(super.api, super.store, super.session);

  PasswordOutcome outcome = PasswordOutcome.wrong;

  @override
  Future<IdentityInfo> loginWithPassword(String email, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    throw switch (outcome) {
      PasswordOutcome.wrong => const ApiException(
        'invalid_credentials',
        '',
        status: 401,
      ),
      PasswordOutcome.locked => const ApiException(
        'rate_limited',
        '',
        status: 429,
      ),
      PasswordOutcome.lockedWithTime => const ApiException(
        'rate_limited',
        '',
        status: 429,
        details: {'retryAfter': 20},
      ),
      PasswordOutcome.network => const ApiException('network', ''),
    };
  }
}
