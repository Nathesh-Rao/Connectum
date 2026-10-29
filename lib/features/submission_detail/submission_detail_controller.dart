import 'package:get/get.dart';

import '../../core/debug/seed_messages.dart';
import '../../core/routes/app_routes.dart';
import '../../core/widgets/app_state_view.dart';
import '../forms/models/form_launch.dart';
import '../../data/models/form_card.dart';
import '../../data/repositories/submission_repository.dart';
import '../../data/session_store.dart';

/// One submission, in full. It is read from the cache first (a submission of
/// mine) or from the form message it was opened from, then the form's
/// definition is fetched when online so grid sections get their column
/// captions. Everything shows without a connection too.
class SubmissionDetailController extends GetxController {
  SubmissionDetailController({
    required this.submissionId,
    required this.submissions,
    required this.store,
    this.convId,
    this.msgId,
  });

  final String submissionId;
  final String? convId;
  final String? msgId;
  final SubmissionRepository submissions;
  final SessionStore store;

  final card = Rxn<FormCardData>();
  final viewState = AppViewState.loading.obs;

  String get me => store.userId ?? SeedMessages.me;

  bool get canEdit {
    final c = card.value;
    return c != null && (c.canEdit(me) || c.canFix(me));
  }

  /// The form again, filled in with what was saved (or resubmitted when the
  /// submission was declined and may be fixed).
  Future<void> edit() async {
    final c = card.value;
    final saved = submissions.submissionById(submissionId);
    if (c == null || saved == null) return;
    await Get.toNamed(
      AppRoutes.form,
      arguments: FormLaunch.forSubmission(
        c,
        saved,
        me: me,
        scope: submissions.definitions[c.structure]?.scope ?? '',
      ),
    );
  }

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    viewState.value = AppViewState.loading;
    if (!submissions.isLoaded.value) await submissions.reload();
    await _read();
    final c = card.value;
    if (c == null) {
      viewState.value = AppViewState.error;
      return;
    }
    viewState.value = AppViewState.content;
    if (c.structure.isEmpty || submissions.hasFullDefinition(c.structure)) {
      return;
    }
    final definition = await submissions.definition(
      c.structure,
      scope: c.scope == 'user' ? 'user' : (c.scope.isEmpty ? '' : 'admin'),
    );
    if (definition != null) await _read();
  }

  Future<void> _read() async {
    card.value = await submissions.cardFor(
      submissionId,
      convId: convId,
      msgId: msgId,
    );
  }
}
