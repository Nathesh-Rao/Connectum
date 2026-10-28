import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'core/config/app_config.dart';
import 'core/routes/app_pages.dart';
import 'core/routes/initial_binding.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_connectivity_scope.dart';
import 'data/socket/connectivity_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validate();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(ConnectumApp(connectivity: ConnectivityService()));
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
      initialBinding: InitialBinding(connectivity),
      initialRoute: AppPages.initial,
      getPages: AppPages.pages,
      builder: (context, child) => AppConnectivityScope(
        state: connectivity.state,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
