import 'package:connectum/data/models/approval.dart';
import 'package:connectum/features/inbox/approval_reason_controller.dart';
import 'package:connectum/features/inbox/models/approval_rules.dart';
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

  test('declining a form and returning one need a reason; the rest do not', () {
    final form = request();
    expect(ApprovalRules.needsReason(form, ApprovalAction.reject), isTrue);
    expect(ApprovalRules.needsReason(form, ApprovalAction.returnIt), isTrue);
    expect(ApprovalRules.needsReason(form, ApprovalAction.accept), isFalse);
    expect(ApprovalRules.needsReason(form, ApprovalAction.ignore), isFalse);
  });

  test('a sign-up or a connection may be declined without a reason', () {
    for (final type in ['onboarding', 'associate', 'membership']) {
      final r = request(type: type);
      expect(ApprovalRules.needsReason(r, ApprovalAction.reject), isFalse);
      expect(ApprovalRules.opensSheet(r, ApprovalAction.reject), isFalse);
      expect(ApprovalRules.canSend(r, ApprovalAction.reject, ''), isTrue);
    }
    expect(ApprovalRules.opensSheet(request(), ApprovalAction.reject), isTrue);
  });

  test('send is allowed only with a non-empty reason when one is needed', () {
    final s = request();
    expect(ApprovalRules.canSend(s, ApprovalAction.reject, ''), isFalse);
    expect(ApprovalRules.canSend(s, ApprovalAction.reject, '   '), isFalse);
    expect(ApprovalRules.canSend(s, ApprovalAction.reject, 'Wrong'), isTrue);
    expect(ApprovalRules.canSend(s, ApprovalAction.returnIt, ''), isFalse);
    expect(ApprovalRules.canSend(s, ApprovalAction.accept, ''), isTrue);
    expect(ApprovalRules.canSend(s, ApprovalAction.ignore, ''), isTrue);
  });

  test('the resubmit switch is only for declining a form', () {
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

  group('answerFor', () {
    test('accept sends no reason and no resubmit flag', () {
      final a = ApprovalRules.answerFor(
        request(),
        ApprovalAction.accept,
        reason: 'ignored text',
        allowResubmit: true,
      )!;
      expect(a.reason, isNull);
      expect(a.allowResubmit, isNull);
      expect(a.comment, isNull);
    });

    test('a form decline carries reason, comment and allowResubmit', () {
      final a = ApprovalRules.answerFor(
        request(),
        ApprovalAction.reject,
        reason: '  No receipt ',
        comment: ' Attach it ',
        allowResubmit: true,
      )!;
      expect(a.reason, 'No receipt');
      expect(a.comment, 'Attach it');
      expect(a.allowResubmit, isTrue);
    });

    test('allowResubmit defaults to false on a form decline', () {
      final a = ApprovalRules.answerFor(
        request(),
        ApprovalAction.reject,
        reason: 'x',
      )!;
      expect(a.allowResubmit, isFalse);
    });

    test('a return carries a reason and never allowResubmit', () {
      final a = ApprovalRules.answerFor(
        request(),
        ApprovalAction.returnIt,
        reason: 'Missing',
        allowResubmit: true,
      )!;
      expect(a.reason, 'Missing');
      expect(a.allowResubmit, isNull);
    });

    test('a missing reason on a form decline or return gives no answer', () {
      expect(
        ApprovalRules.answerFor(request(), ApprovalAction.reject, reason: ' '),
        isNull,
      );
      expect(
        ApprovalRules.answerFor(request(), ApprovalAction.returnIt),
        isNull,
      );
    });

    test('a sign-up decline is sent with no reason and no resubmit flag', () {
      final a = ApprovalRules.answerFor(
        request(type: 'onboarding'),
        ApprovalAction.reject,
      )!;
      expect(a.reason, isNull);
      expect(a.allowResubmit, isNull);
    });

    test('a comment alone is sent when filled; text is cut to 500', () {
      final a = ApprovalRules.answerFor(
        request(type: 'associate'),
        ApprovalAction.accept,
        comment: 'x' * 600,
      )!;
      expect(a.comment, hasLength(ApprovalRules.maxText));
      final b = ApprovalRules.answerFor(
        request(),
        ApprovalAction.reject,
        reason: 'y' * 700,
      )!;
      expect(b.reason, hasLength(ApprovalRules.maxText));
    });
  });

  test('the reason sheet will not send an empty reason for a form', () async {
    var sent = 0;
    String? sentReason;
    bool? sentResubmit;
    final form = ApprovalReasonController(
      request: request(),
      action: ApprovalAction.reject,
      onSend: (reason, note, allow) async {
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
    expect(form.allowResubmit.value, isFalse);
    expect(await form.send(), isTrue);
    expect(sent, 1);
    expect(sentReason, 'Wrong amount');
    expect(sentResubmit, isFalse);
  });

  test('a return sends no resubmit flag', () async {
    bool? sentResubmit;
    final form = ApprovalReasonController(
      request: request(),
      action: ApprovalAction.returnIt,
      onSend: (reason, note, allow) async {
        sentResubmit = allow;
        return true;
      },
    );
    form.reason.text = 'Missing receipt';
    form.onReasonChanged(form.reason.text);
    form.allowResubmit.value = true;
    await form.send();
    expect(sentResubmit, isFalse);
  });
}
