import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../config/app_config.dart';
import '../../features/approvals/approvals_binding.dart';
import '../../features/approvals/approvals_view.dart';
import '../../features/authentication/authentication_binding.dart';
import '../../features/authentication/authentication_view.dart';
import '../../features/chat_info/chat_info_binding.dart';
import '../../features/chat_info/chat_info_view.dart';
import '../../features/conversation/conversation_binding.dart';
import '../../features/conversation/conversation_view.dart';
import '../../features/debug_ai/debug_ai_binding.dart';
import '../../features/debug_ai/debug_ai_view.dart';
import '../../features/debug_assets/debug_assets_binding.dart';
import '../../features/debug_chat/debug_chat_binding.dart';
import '../../features/debug_commands/debug_commands_binding.dart';
import '../../features/debug_commands/debug_commands_view.dart';
import '../../features/debug_notifications/debug_notifications_binding.dart';
import '../../features/debug_notifications/debug_notifications_view.dart';
import '../../features/debug_chat/debug_chat_view.dart';
import '../../features/debug_assets/debug_assets_view.dart';
import '../../features/debug_connect/debug_connect_binding.dart';
import '../../features/debug_connect/debug_connect_view.dart';
import '../../features/debug_e2e/debug_e2e_binding.dart';
import '../../features/debug_e2e/debug_e2e_view.dart';
import '../../features/debug_forms/debug_forms_binding.dart';
import '../../features/debug_forms/debug_forms_view.dart';
import '../../features/debug_formlogic/debug_formlogic_binding.dart';
import '../../features/debug_formlogic/debug_formlogic_view.dart';
import '../../features/debug_qr/debug_qr_binding.dart';
import '../../features/debug_qr/debug_qr_view.dart';
import '../../features/debug_socket/debug_socket_binding.dart';
import '../../features/debug_tasks/debug_tasks_binding.dart';
import '../../features/debug_tasks/debug_tasks_view.dart';
import '../../features/debug_tickets/debug_tickets_binding.dart';
import '../../features/debug_tickets/debug_tickets_view.dart';
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
import '../../features/new_group/new_group_binding.dart';
import '../../features/new_group/new_group_view.dart';
import '../../features/notifications/notifications_binding.dart';
import '../../features/notifications/notifications_view.dart';
import '../../features/onboarding/onboarding_binding.dart';
import '../../features/onboarding/onboarding_view.dart';
import '../../features/security/security_binding.dart';
import '../../features/security/security_view.dart';
import '../../features/splash/splash_binding.dart';
import '../../features/splash/splash_view.dart';
import '../../features/submission_detail/submission_detail_binding.dart';
import '../../features/tasks/tasks_binding.dart';
import '../../features/tasks/tasks_view.dart';
import '../../features/tickets/ticket_detail_binding.dart';
import '../../features/tickets/ticket_detail_view.dart';
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
      AppRoutes.chatInfo,
      () => ChatInfoView(
        conversationId: Uri.decodeComponent(Get.parameters['id'] ?? ''),
      ),
      ChatInfoBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.newGroup,
      () => const NewGroupView(),
      NewGroupBinding(),
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
      AppRoutes.tasks,
      () => const TasksView(),
      TasksBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.ticket,
      () => const TicketDetailView(),
      TicketDetailBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.approvals,
      () => const ApprovalsView(),
      ApprovalsBinding(),
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
        AppRoutes.debugNotifications,
        () => const DebugNotificationsView(),
        DebugNotificationsBinding(),
        AppTransitionKind.push,
      ),
      _page(
        AppRoutes.debugCommands,
        () => const DebugCommandsView(),
        DebugCommandsBinding(),
        AppTransitionKind.push,
      ),
      _page(
        AppRoutes.debugAi,
        () => const DebugAiView(),
        DebugAiBinding(),
        AppTransitionKind.push,
      ),
      _page(
        AppRoutes.debugTickets,
        () => const DebugTicketsView(),
        DebugTicketsBinding(),
        AppTransitionKind.push,
      ),
      _page(
        AppRoutes.debugTasks,
        () => const DebugTasksView(),
        DebugTasksBinding(),
        AppTransitionKind.push,
      ),
      _page(
        AppRoutes.debugChat,
        () => const DebugChatView(),
        DebugChatBinding(),
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
    if (kDebugMode)
      _page(
        AppRoutes.debugFormLogic,
        () => const DebugFormLogicView(),
        DebugFormLogicBinding(),
        AppTransitionKind.push,
      ),
    if (kDebugMode)
      _page(
        AppRoutes.debugConnect,
        () => const DebugConnectView(),
        DebugConnectBinding(),
        AppTransitionKind.push,
      ),
    if (kDebugMode)
      _page(
        AppRoutes.debugQr,
        () => const DebugQrView(),
        DebugQrBinding(),
        AppTransitionKind.push,
      ),
    if (kDebugMode)
      _page(
        AppRoutes.debugForms,
        () => const DebugFormsView(),
        DebugFormsBinding(),
        AppTransitionKind.push,
      ),
  ];
}
