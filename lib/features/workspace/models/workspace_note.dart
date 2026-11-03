import 'package:get/get.dart';

/// A small row of the workspace feed that is not stored: the answer of a `#`
/// command, or "Sent to @name" for an `@name` message (which opens that chat
/// and turns into the reason when the send fails).
class WorkspaceNote {
  WorkspaceNote({
    required this.id,
    required String text,
    required this.ts,
    this.convId,
    this.user = '',
  }) : text = text.obs;

  final String id;
  final int ts;
  final String? convId;
  final String user;
  final RxString text;
  final isProblem = false.obs;
}
