import 'package:connectum/data/models/models.dart';

/// What a record is, for the title and the actions of its detail screen. A
/// request (`req.*`) and a task are not records: they never open here.
enum RecordKind {
  ticket('Ticket'),
  submission('Submission'),
  approval('Approval');

  const RecordKind(this.title);

  final String title;

  /// A form with a status table (the structure, or `record.actions` listing
  /// statuses) is a ticket; a record that waits for, or was
  /// refused by, an approval step is an approval; any other is a plain
  /// submission.
  static RecordKind of(
    Ticket t, {
    bool hasRequest = false,
    bool hasStatus = false,
  }) {
    if (hasRequest || t.isAwaitingApproval) return approval;
    if (t.recordStatus.toLowerCase() == 'rejected' && !hasStatus) {
      return approval;
    }
    return hasStatus || t.hasStatus ? ticket : submission;
  }
}
