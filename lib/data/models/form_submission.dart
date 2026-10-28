import 'ids.dart';

class FormSubmission {
  const FormSubmission({
    required this.submissionId,
    required this.tstruct,
    required this.byUser,
    required this.ts,
    required this.valuesJson,
    required this.syncState,
    this.status,
    this.editedTs,
  });

  final String submissionId;
  final String tstruct;
  final String byUser;
  final int ts;
  final String valuesJson;
  final String syncState;
  final String? status;
  final int? editedTs;

  bool get isPending => syncState != 'synced';

  factory FormSubmission.fromRow(Map<String, Object?> r) => FormSubmission(
    submissionId: idText(r['submission_id']),
    tstruct: idText(r['tstruct']),
    byUser: idText(r['by_user']),
    ts: intOf(r['ts']),
    valuesJson: idText(r['values_json']),
    syncState: idText(r['sync_state']),
    status: r['status'] as String?,
    editedTs: r['edited_ts'] == null ? null : intOf(r['edited_ts']),
  );
}
