import 'package:connectum/features/inbox/inbox_live.dart';
import 'package:connectum/features/inbox/models/inbox_live_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InboxLiveRule', () {
    test('the work events read the Inbox again', () {
      for (final n in [
        'submissions_changed',
        'submission_approved',
        'submission_rejected',
        'submission_notice',
        'ticket_assigned',
        'task_assigned',
        'task_updated',
        'task_completed',
        'resync',
      ]) {
        expect(InboxLiveRule.isWork(n), isTrue, reason: n);
      }
    });

    test('chat, typing, approval and other events do not', () {
      for (final n in [
        'message',
        'typing',
        'presence',
        'read_receipt',
        'request_created',
        'request_resolved',
        'broadcast',
        'feed_item',
        'feed_changed',
        'status_change',
        'welcome',
        'my_submissions_changed',
        'subtask',
        '',
      ]) {
        expect(InboxLiveRule.isWork(n), isFalse, reason: n);
      }
    });

    test('the name is the sd_event name, else the type', () {
      expect(
        InboxLiveRule.nameOf({'type': 'sd_event', 'event': 'task_updated'}),
        'task_updated',
      );
      expect(InboxLiveRule.nameOf({'type': 'resync'}), 'resync');
      expect(InboxLiveRule.nameOf({'type': 'sd_event'}), '');
      expect(InboxLiveRule.nameOf({'type': 5}), '');
    });

    test('the timings are 300 ms and 2 s', () {
      final live = InboxLive(
        state: () => InboxLiveState.active,
        isBusy: () => false,
        read: () async {},
      );
      expect(live.debounce, const Duration(milliseconds: 300));
      expect(live.minGap, const Duration(seconds: 2));
    });
  });
}
