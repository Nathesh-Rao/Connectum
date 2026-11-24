import 'package:connectum/features/inbox/models/inbox_record_tone.dart';
import 'package:flutter_test/flutter_test.dart';

// Ported from the web's tests/frontend/recordTone.test.mjs.
void main() {
  group('recordStateOf', () {
    test('a record at a final status is completed, whatever else it says', () {
      expect(recordStateOf(isFinal: true), InboxState.completed);
      expect(
        recordStateOf(isFinal: true, isWaiting: true, holder: 'me', me: 'me'),
        InboxState.completed,
      );
      expect(
        recordStateOf(isFinal: true, statusText: 'Rejected'),
        InboxState.completed,
      );
    });

    test('open: pending when it waits for the person or their team', () {
      expect(
        recordStateOf(holder: 'olivia', me: 'olivia'),
        InboxState.pending,
        reason: 'with the person',
      );
      expect(
        recordStateOf(holder: 'Olivia', me: 'olivia'),
        InboxState.pending,
        reason: 'case does not matter',
      );
      expect(
        recordStateOf(holder: 'maya, @olivia', me: 'olivia'),
        InboxState.pending,
        reason: 'shared with the person',
      );
      expect(
        recordStateOf(holder: 'maya', via: ['holder'], me: 'olivia'),
        InboxState.pending,
        reason: 'with someone of their team',
      );
      expect(
        recordStateOf(holder: 'maya', via: ['sent'], me: 'olivia'),
        InboxState.assigned,
      );
      expect(recordStateOf(holder: 'maya', me: 'olivia'), InboxState.assigned);
      expect(recordStateOf(holder: '', me: 'olivia'), InboxState.assigned);
      expect(recordStateOf(), InboxState.assigned);
    });

    test('declined, bad statuses and waiting have their own states', () {
      expect(
        recordStateOf(isDeclined: true, holder: 'olivia', me: 'olivia'),
        InboxState.rejected,
      );
      for (final w in [
        'Rejected',
        'declined',
        'BLOCKED',
        'Failed',
        'Overdue',
        'Cancelled',
        'canceled',
      ]) {
        expect(recordStateOf(statusText: w), InboxState.rejected, reason: w);
      }
      expect(recordStateOf(statusText: 'Open'), InboxState.assigned);
      expect(
        recordStateOf(isWaiting: true, holder: 'olivia', me: 'olivia'),
        InboxState.waiting,
      );
      expect(
        recordStateOf(isWaiting: true, isDeclined: true),
        InboxState.rejected,
        reason: 'declined wins over waiting',
      );
    });

    test(
      'the chosen list decides pending vs assigned, never over the rest',
      () {
        expect(
          recordStateOf(
            holder: 'maya',
            via: ['holder'],
            me: 'olivia',
            view: 'assigned',
          ),
          InboxState.assigned,
        );
        expect(
          recordStateOf(holder: 'olivia', me: 'olivia', view: 'assigned'),
          InboxState.assigned,
        );
        expect(
          recordStateOf(holder: 'maya', me: 'olivia', view: 'pending'),
          InboxState.pending,
        );
        expect(
          recordStateOf(isFinal: true, view: 'assigned'),
          InboxState.completed,
        );
        expect(
          recordStateOf(isDeclined: true, view: 'pending'),
          InboxState.rejected,
        );
        expect(
          recordStateOf(isWaiting: true, view: 'assigned'),
          InboxState.waiting,
        );
        expect(
          recordStateOf(
            holder: 'maya',
            via: ['holder'],
            me: 'olivia',
            view: 'completed',
          ),
          InboxState.pending,
          reason: 'a view that is not pending or assigned changes nothing',
        );
      },
    );

    test('every state says what it means', () {
      for (final s in InboxState.values) {
        expect(inboxStateWords[s], isNotEmpty, reason: s.name);
      }
    });
  });

  group('priorityOf', () {
    InboxPriority? p(Object? v) => priorityOf(values: {'priority': v});

    test('high, medium, low', () {
      expect(p('High'), InboxPriority.high);
      expect(p('Medium'), InboxPriority.medium);
      expect(p('Low'), InboxPriority.low);
    });

    test('every word of every level', () {
      for (final w in [
        'Highest',
        'very high',
        'Urgent',
        'CRITICAL',
        'high priority',
        'P0',
        'P1',
        'Blocker',
        'severe',
        'major',
        'sev 1',
        'sev1',
      ]) {
        expect(p(w), InboxPriority.high, reason: w);
      }
      for (final w in [
        'Normal',
        'moderate',
        'average',
        'med',
        'P2',
        'sev 2',
        'sev2',
      ]) {
        expect(p(w), InboxPriority.medium, reason: w);
      }
      for (final w in [
        'Minor',
        'trivial',
        'Low priority',
        'lowest',
        'very low',
        'P3',
        'P4',
        'sev 3',
        'sev4',
      ]) {
        expect(p(w), InboxPriority.low, reason: w);
      }
    });

    test('found by name or caption, label first, first of a list', () {
      expect(
        priorityOf(values: {'sev': '1'}, fields: {'sev': 'Severity'}),
        isNull,
        reason: 'a number alone says nothing',
      );
      expect(
        priorityOf(
          values: {'sev': 'x7'},
          labels: {'sev': 'High'},
          fields: {'sev': 'Severity'},
        ),
        InboxPriority.high,
      );
      expect(priorityOf(values: {'ticket_urgency': 'low'}), InboxPriority.low);
      expect(
        priorityOf(
          values: {
            'importance': ['Medium', 'x'],
          },
        ),
        InboxPriority.medium,
      );
      expect(
        priorityOf(values: {'title': 'High', 'notes': 'Low'}),
        isNull,
        reason: 'a field that is not about importance is not read',
      );
      expect(priorityOf(), isNull);
      for (final v in ['', 'Whenever', null, <String, dynamic>{}]) {
        expect(p(v), isNull, reason: '$v');
      }
    });

    test('the first field that matches a level wins', () {
      expect(
        priorityOf(
          values: {'risk': 'unknown', 'priority': 'Low', 'urgency': 'High'},
        ),
        InboxPriority.low,
      );
    });
  });

  test('the words of an answer are plain', () {
    expect(answerWord('  High   Priority '), 'high');
    expect(answerWord(3), '3');
    expect(answerWord(null), '');
    expect(answerWord(true), '');
    expect(answerWord([]), '');
    expect(
      signalField.hasMatch('Priority Level') &&
          signalField.hasMatch('risk_score') &&
          !signalField.hasMatch('Title'),
      isTrue,
    );
  });
}
