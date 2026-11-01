import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../config/app_config.dart';
import '../../features/authentication/authentication_binding.dart';
import '../../features/authentication/authentication_view.dart';
import '../../features/conversation/conversation_binding.dart';
import '../../features/conversation/conversation_view.dart';
import '../../features/debug_assets/debug_assets_binding.dart';
import '../../features/debug_assets/debug_assets_view.dart';
import '../../features/debug_e2e/debug_e2e_binding.dart';
import '../../features/debug_e2e/debug_e2e_view.dart';
import '../../features/debug_socket/debug_socket_binding.dart';
import '../../features/debug_socket/debug_socket_view.dart';
import '../../features/enterprise_created/enterprise_created_binding.dart';
import '../../features/enterprise_created/enterprise_created_view.dart';
import '../../features/enterprises/enterprises_binding.dart';
import '../../features/enterprises/enterprises_view.dart';
import '../../features/forms/form_binding.dart';
import '../../features/forms/form_view.dart';
import '../../features/forms/models/form_launch.dart';
import '../../features/gallery/gallery_auth_binding.dart';
import '../../features/home_shell/home_shell_binding.dart';
import '../../features/home_shell/home_shell_controller.dart';
import '../../features/home_shell/home_shell_view.dart';
import '../../features/gallery/gallery_auth_view.dart';
import '../../features/gallery/gallery_binding.dart';
import '../../features/gallery/gallery_view.dart';
import '../../features/notifications/notifications_binding.dart';
import '../../features/notifications/notifications_view.dart';
import '../../features/onboarding/onboarding_binding.dart';
import '../../features/onboarding/onboarding_view.dart';
import '../../features/security/security_binding.dart';
import '../../features/security/security_view.dart';
import '../../features/splash/splash_binding.dart';
import '../../features/splash/splash_view.dart';
import '../../features/submission_detail/submission_detail_binding.dart';
import '../../features/submission_detail/submission_detail_view.dart';
import '../../features/verification/verification_binding.dart';
import '../../features/workspace/workspace_binding.dart';
import '../../features/workspace/workspace_view.dart';
import '../../features/verification/verification_view.dart';
import 'app_routes.dart';
import 'app_transitions.dart';

class AppPages {
  AppPages._();

  static String get initial => kDebugMode && AppConfig.startRoute.isNotEmpty
      ? AppConfig.startRoute
      : AppRoutes.splash;

  static GetPage<dynamic> _page(
    String name,
    GetPageBuilder page,
    Bindings binding,
    AppTransitionKind kind,
  ) {
    final transition = AppTransition(kind);
    return GetPage(
      name: name,
      page: page,
      binding: binding,
      customTransition: transition,
      transitionDuration: transition.duration,
      opaque: kind != AppTransitionKind.slideUp,
    );
  }

  static final pages = <GetPage<dynamic>>[
    _page(
      AppRoutes.splash,
      () => const SplashView(),
      SplashBinding(),
      AppTransitionKind.fade,
    ),
    _page(
      AppRoutes.onboarding,
      () => const OnboardingView(),
      OnboardingBinding(),
      AppTransitionKind.intro,
    ),
    _page(
      AppRoutes.authentication,
      () => const AuthenticationView(),
      AuthenticationBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.verification,
      () => const VerificationView(),
      VerificationBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.enterprises,
      () => const EnterprisesView(),
      EnterprisesBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.enterpriseCreated,
      () => const EnterpriseCreatedView(),
      EnterpriseCreatedBinding(),
      AppTransitionKind.enter,
    ),
    for (final route in HomeShellController.tabRoutes)
      _page(
        route,
        () => const HomeShellView(),
        HomeShellBinding(),
        AppTransitionKind.enter,
      ),
    _page(
      AppRoutes.conversation,
      () => ConversationView(
        conversationId: Uri.decodeComponent(Get.parameters['id'] ?? ''),
      ),
      ConversationBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.submissionDetail,
      () => SubmissionDetailView(
        submissionId: Uri.decodeComponent(Get.parameters['id'] ?? ''),
      ),
      SubmissionDetailBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.form,
      () => FormView(launch: Get.arguments as FormLaunch),
      FormBinding(),
      AppTransitionKind.slideUp,
    ),
    _page(
      AppRoutes.workspace,
      () => const WorkspaceView(),
      WorkspaceBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.notifications,
      () => const NotificationsView(),
      NotificationsBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.security,
      () => const SecurityView(),
      SecurityBinding(),
      AppTransitionKind.push,
    ),
    if (kDebugMode) ...[
      _page(
        AppRoutes.gallery,
        () => const GalleryView(),
        GalleryBinding(),
        AppTransitionKind.fade,
      ),
      _page(
        AppRoutes.galleryAuth,
        () => const GalleryAuthView(),
        GalleryAuthBinding(),
        AppTransitionKind.push,
      ),
      _page(
        AppRoutes.debugAssets,
        () => const DebugAssetsView(),
        DebugAssetsBinding(),
        AppTransitionKind.push,
      ),
      _page(
        AppRoutes.debugSocket,
        () => const DebugSocketView(),
        DebugSocketBinding(),
        AppTransitionKind.push,
      ),
    ],
    if (kDebugMode)
      _page(
        AppRoutes.debugE2e,
        () => const DebugE2eView(),
        DebugE2eBinding(),
        AppTransitionKind.push,
      ),
  ];
}
