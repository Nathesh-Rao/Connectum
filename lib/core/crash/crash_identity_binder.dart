import 'package:get/get.dart';

import '../../data/session_store.dart';
import 'crash_breadcrumbs.dart';
import 'crash_config.dart';
import 'crash_reporter.dart';

/// Follows the session store: sets the identity on sign-in, on restore and on
/// an organisation switch, clears it when the session ends for any reason
/// (sign out, expired, password changed).
class CrashIdentityBinder {
  CrashIdentityBinder(
    this._store,
    this._reporter, {
    this.config = const CrashConfig(),
  }) {
    _workers = [ever(_store.current, _sync), ever(_store.identity, _sync)];
    _sync(null);
  }

  final SessionStore _store;
  final CrashReporter _reporter;
  final CrashConfig config;
  late final List<Worker> _workers;
  CrashIdentity? _last;

  void dispose() {
    for (final w in _workers) {
      w.dispose();
    }
  }

  void _sync(Object? _) {
    final info = _store.current.value;
    if (info == null) {
      if (_last == null) return;
      _last = null;
      _reporter.clearIdentity();
      CrashBreadcrumbs.add(Crumb.signOut);
      return;
    }
    final identity = _store.identity.value;
    var orgName = '';
    if (config.includeOrgName && identity != null) {
      for (final e in identity.enterprises) {
        if (e.enterprise == info.orgId) orgName = e.name;
      }
    }
    final next = CrashIdentity(
      userId: info.userId,
      email: config.includeEmail ? (identity?.email ?? '') : '',
      orgName: orgName,
      orgId: info.orgId,
    );
    if (next == _last) return;
    final previous = _last;
    _last = next;
    _reporter.setIdentity(next);
    if (previous == null) {
      CrashBreadcrumbs.add(Crumb.signIn);
    } else if (previous.orgId != next.orgId) {
      CrashBreadcrumbs.add(Crumb.orgSwitched);
    }
  }
}
