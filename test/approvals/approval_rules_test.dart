import 'package:connectum/data/models/approval.dart';
import 'package:connectum/features/approvals/approval_reason_controller.dart';
import 'package:connectum/features/approvals/models/approval_rules.dart';
import 'package:flutter_test/flutter_test.dart';

Approval request({
  String type = 'submission',
  String status = Approval.pending,
  bool canRespond = true,
  String direction = Approval.incoming,
}) => Approval(
  id: 1,
  type: type,
  status: status,
  canRespond: canRespond,
  direction: direction,
);

void main() {
  test('a submission offers accept, reject, return and ignore', () {
    expect(ApprovalRules.actionsFor(request()), [
      ApprovalAction.accept,
      ApprovalAction.reject,
      ApprovalAction.returnIt,
      ApprovalAction.ignore,
    ]);
  });

  test('only a submission can be returned', () {
    final actions = ApprovalRules.actionsFor(request(type: 'group_invite'));
    expect(actions, isNot(contains(ApprovalAction.returnIt)));
    expect(actions, contains(ApprovalAction.reject));
  });

  test('read-only when canRespond is false or it is not pending', () {
    expect(ApprovalRules.actionsFor(request(canRespond: false)), isEmpty);
    expect(
      ApprovalRules.actionsFor(request(status: Approval.accepted)),
      isEmpty,
    );
  });

  test('reject and return need a reason, accept and ignore do not', () {
    expect(ApprovalRules.needsReason(ApprovalAction.reject), isTrue);
    expect(ApprovalRules.needsReason(ApprovalAction.returnIt), isTrue);
    expect(ApprovalRules.needsReason(ApprovalAction.accept), isFalse);
    expect(ApprovalRules.needsReason(ApprovalAction.ignore), isFalse);
  });

  test('send is allowed only with a non-empty reason when one is needed', () {
    expect(ApprovalRules.canSend(ApprovalAction.reject, ''), isFalse);
    expect(ApprovalRules.canSend(ApprovalAction.reject, '   '), isFalse);
    expect(
      ApprovalRules.canSend(ApprovalAction.reject, 'Wrong amount'),
      isTrue,
    );
    expect(ApprovalRules.canSend(ApprovalAction.returnIt, ''), isFalse);
    expect(ApprovalRules.canSend(ApprovalAction.accept, ''), isTrue);
    expect(ApprovalRules.canSend(ApprovalAction.ignore, ''), isTrue);
  });

  test('the resubmit switch is only for rejecting a submission', () {
    final s = request();
    expect(ApprovalRules.offersResubmit(s, ApprovalAction.reject), isTrue);
    expect(ApprovalRules.offersResubmit(s, ApprovalAction.returnIt), isFalse);
    expect(ApprovalRules.offersResubmit(s, ApprovalAction.accept), isFalse);
    expect(
      ApprovalRules.offersResubmit(
        request(type: 'group_invite'),
        ApprovalAction.reject,
      ),
      isFalse,
    );
  });

  test('the reason sheet will not send an empty reason', () async {
    var sent = 0;
    String? sentReason;
    bool? sentResubmit;
    final form = ApprovalReasonController(
      request: request(),
      action: ApprovalAction.reject,
      onSend: (reason, comment, allow) async {
        sent++;
        sentReason = reason;
        sentResubmit = allow;
        return true;
      },
    );
    expect(form.canSend, isFalse);
    expect(await form.send(), isFalse);
    form.reason.text = '  Wrong amount ';
    form.onReasonChanged(form.reason.text);
    expect(form.canSend, isTrue);
    expect(await form.send(), isTrue);
    expect(sent, 1);
    expect(sentReason, 'Wrong amount');
    expect(sentResubmit, isTrue);
  });

  test('a return sends no resubmit flag', () async {
    bool? sentResubmit = true;
    final form = ApprovalReasonController(
      request: request(),
      action: ApprovalAction.returnIt,
      onSend: (reason, comment, allow) async {
        sentResubmit = allow;
        return true;
      },
    )..onReasonChanged('Missing receipt');
    form.reason.text = 'Missing receipt';
    await form.send();
    expect(sentResubmit, isNull);
  });
}
