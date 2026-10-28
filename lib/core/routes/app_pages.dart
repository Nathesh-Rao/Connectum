import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../features/ai_agents/ai_agents_binding.dart';
import '../../features/ai_agents/ai_agents_view.dart';
import '../../features/authentication/authentication_binding.dart';
import '../../features/authentication/authentication_view.dart';
import '../../features/chats/chats_binding.dart';
import '../../features/chats/chats_view.dart';
import '../../features/conversation/conversation_binding.dart';
import '../../features/conversation/conversation_view.dart';
import '../../features/debug_socket/debug_socket_binding.dart';
import '../../features/debug_socket/debug_socket_view.dart';
import '../../features/enterprises/enterprises_binding.dart';
import '../../features/enterprises/enterprises_view.dart';
import '../../features/gallery/gallery_auth_binding.dart';
import '../../features/gallery/gallery_auth_view.dart';
import '../../features/gallery/gallery_binding.dart';
import '../../features/gallery/gallery_view.dart';
import '../../features/notifications/notifications_binding.dart';
import '../../features/notifications/notifications_view.dart';
import '../../features/onboarding/onboarding_binding.dart';
import '../../features/onboarding/onboarding_view.dart';
import '../../features/profile/profile_binding.dart';
import '../../features/profile/profile_view.dart';
import '../../features/splash/splash_binding.dart';
import '../../features/splash/splash_view.dart';
import '../../features/submission_detail/submission_detail_binding.dart';
import '../../features/submission_detail/submission_detail_view.dart';
import '../../features/submissions/submissions_binding.dart';
import '../../features/submissions/submissions_view.dart';
import '../../features/verification/verification_binding.dart';
import '../../features/verification/verification_view.dart';
import 'app_routes.dart';
import 'app_transitions.dart';

class AppPages {
  AppPages._();

  static String get initial =>
      !kReleaseMode ? AppRoutes.gallery : AppRoutes.splash;

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
      AppRoutes.chats,
      () => const ChatsView(),
      ChatsBinding(),
      AppTransitionKind.enter,
    ),
    _page(
      AppRoutes.aiAgents,
      () => const AiAgentsView(),
      AiAgentsBinding(),
      AppTransitionKind.tab,
    ),
    _page(
      AppRoutes.conversation,
      () => const ConversationView(),
      ConversationBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.submissions,
      () => const SubmissionsView(),
      SubmissionsBinding(),
      AppTransitionKind.tab,
    ),
    _page(
      AppRoutes.submissionDetail,
      () => const SubmissionDetailView(),
      SubmissionDetailBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.profile,
      () => const ProfileView(),
      ProfileBinding(),
      AppTransitionKind.tab,
    ),
    _page(
      AppRoutes.notifications,
      () => const NotificationsView(),
      NotificationsBinding(),
      AppTransitionKind.push,
    ),
    if (!kReleaseMode) ...[
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
        AppRoutes.debugSocket,
        () => const DebugSocketView(),
        DebugSocketBinding(),
        AppTransitionKind.push,
      ),
    ],
  ];
}
