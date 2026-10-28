class AppRoutes {
  AppRoutes._();

  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const authentication = '/authentication';
  static const verification = '/verification';
  static const enterprises = '/enterprises';
  static const chats = '/chats';
  static const aiAgents = '/ai-agents';
  static const conversation = '/conversation/:id';
  static const submissions = '/submissions';
  static const submissionDetail = '/submissions/:id';
  static const profile = '/profile';
  static const notifications = '/notifications';

  static const gallery = '/gallery';
  static const galleryAuth = '/gallery/auth';
  static const debugSocket = '/debug/socket';

  static String conversationOf(String id) => '/conversation/$id';
  static String submissionDetailOf(String id) => '/submissions/$id';
}
