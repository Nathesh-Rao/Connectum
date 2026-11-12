import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'core/config/app_config.dart';
import 'core/debug/seed_ui.dart';
import 'core/routes/app_pages.dart';
import 'core/routes/conversation_route.dart';
import 'core/routes/home_reload.dart';
import 'core/routes/initial_binding.dart';
import 'core/theme/app_scroll_behavior.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_config_error.dart';
import 'core/widgets/app_connectivity_scope.dart';
import 'core/widgets/app_notices.dart';
import 'data/socket/connectivity_service.dart';
import 'demo/demo_mode.dart';
import 'demo/demo_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final configError = AppConfig.validate();
  if (configError != null) {
    runApp(AppConfigError(message: configError));
    return;
  }
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(
    ConnectumApp(
      connectivity: DemoMode.isActive
          ? DemoConnectivityService()
          : ConnectivityService(),
    ),
  );
}

class ConnectumApp extends StatelessWidget {
  const ConnectumApp({super.key, required this.connectivity});

  final ConnectivityService connectivity;

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Connectum',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      scrollBehavior: const AppScrollBehavior(),
      initialBinding: InitialBinding(connectivity),
      initialRoute: AppPages.initial,
      getPages: AppPages.pages,
      navigatorObservers: [ConversationRoute.observer, HomeReload.observer],
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
