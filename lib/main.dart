import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'core/config/app_config.dart';
import 'core/crash/crash_bootstrap.dart';
import 'core/crash/crash_hooks.dart';
import 'core/crash/crash_reporter.dart';
import 'core/crash/crash_route_observer.dart';
import 'core/crash/crash_service.dart';
import 'core/debug/seed_ui.dart';
import 'core/errors/error_widget.dart';
import 'core/errors/run_guarded.dart';
import 'core/log/log_bootstrap.dart';
import 'core/routes/app_pages.dart';
import 'core/routes/conversation_route.dart';
import 'core/routes/home_reload.dart';
import 'core/routes/initial_binding.dart';
import 'core/theme/app_scroll_behavior.dart';
import 'core/utils/app_settings.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_config_error.dart';
import 'core/widgets/app_connectivity_scope.dart';
import 'core/widgets/app_notices.dart';
import 'core/widgets/app_startup_error.dart';
import 'data/smart_view/sv_prefs.dart';
import 'data/socket/connectivity_service.dart';
import 'demo/demo_mode.dart';
import 'demo/demo_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LogBootstrap.install();
  final reporter = await guarded(
    () => createCrashReporter(isDemo: DemoMode.isActive),
    reason: 'startup crash reporter',
  );
  final active = reporter ?? const NoopCrashReporter();
  CrashService.current = CrashService(active);
  installCrashHooks(active);
  installErrorWidget();
  if (active.isEnabled) {
    runGuarded(() async {
      active.setKey('app_version', await AppSettings.version() ?? '');
    }, reason: 'startup version key');
  }
  await _start();
}

Future<void> _start() async {
  try {
    final configError = AppConfig.validate();
    if (configError != null) {
      runApp(AppConfigError(message: configError));
      return;
    }
    await guarded(
      () => SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
      reason: 'startup system ui',
    );
    await guarded(
      () =>
          SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
      reason: 'startup orientation',
    );
    final smartViewPrefs = await guarded(
      SmartViewPrefs.load,
      reason: 'startup smart view prefs',
    );
    runApp(
      ConnectumApp(
        smartViewPrefs: smartViewPrefs,
        connectivity: DemoMode.isActive
            ? DemoConnectivityService()
            : ConnectivityService(),
      ),
    );
  } catch (e, s) {
    CrashService.nonFatal(e, s, 'startup blocked');
    runApp(AppStartupError(onRetry: () => unawaited(_start())));
  }
}

class ConnectumApp extends StatelessWidget {
  const ConnectumApp({
    super.key,
    required this.connectivity,
    this.smartViewPrefs,
  });

  final ConnectivityService connectivity;
  final SmartViewPrefs? smartViewPrefs;

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Connectum',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      scrollBehavior: const AppScrollBehavior(),
      initialBinding: InitialBinding(
        connectivity,
        smartViewPrefs: smartViewPrefs,
      ),
      initialRoute: AppPages.initial,
      getPages: AppPages.pages,
      navigatorObservers: [
        ConversationRoute.observer,
        HomeReload.observer,
        CrashRouteObserver(),
      ],
      builder: (context, child) {
        final app = AppConnectivityScope(
          state: connectivity.state,
          child: AppNoticeHost(child: child ?? const SizedBox.shrink()),
        );
        // Sample data (SEED_UI, never in release) is marked on every screen.
        return SeedUi.isActive && !DemoMode.isActive
            ? SeedUi.withRibbon(app)
            : app;
      },
    );
  }
}
