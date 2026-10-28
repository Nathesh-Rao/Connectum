import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../data/models/conversation.dart';
import '../../data/models/identity_info.dart';
import '../../data/models/message.dart';

/// Debug-only fixture for UI checks: run with --dart-define=SEED_UI=1 and the
/// enterprises screen shows five sample enterprises. Ignored in release. The
/// data lives in memory only: nothing goes to SQLite, SessionStore or secure
/// storage. Remove before release (see CLAUDE.md).
class SeedUi {
  SeedUi._();

  static const _requested = String.fromEnvironment('SEED_UI') == '1';

  /// Debug and profile builds only (profile is needed for the scrolling check).
  static bool get isActive => !kReleaseMode && _requested;

  static const currentOrgId = 'CMYD-Z063';
  static const sampleEnterpriseName = 'Agile Labs';

  static IdentityInfo? identity() {
    if (!isActive) return null;
    const names = [
      ('Agile Labs', 'CMYD-Z063'),
      ('Agile Space', 'WR4Q-BHSK'),
      ('Demo HR', 'QC2V-N0ET'),
      ('Demo University', 'EHYS-EAYP'),
      ('Kauvery hospital', '2Z73-TQ5C'),
    ];
    return IdentityInfo(
      token: 'seed',
      email: 'alex@example.com',
      connectumId: 'MN68-2CQ9',
      enterprises: [
        for (final (name, id) in names)
          EnterpriseMembership(
            enterprise: id,
            name: name,
            city: '',
            category: '',
            username: 'alex',
            status: 'active',
          ),
      ],
    );
  }

  /// Which state the Chats screen shows: content, loading, empty, error or
  /// offline. Switched by the debug chips on the screen.
  static final chatsState = 'content'.obs;

  /// SEED_ROWS=300 adds that many generated direct messages after the samples,
  /// for the scrolling check.
  static const _extraRows = int.fromEnvironment('SEED_ROWS');

  static const online = {'priya', 'meera'};
  static const offline = {'arjun', 'ravi'};

  static List<Conversation>? _conversations;

  static List<Conversation> conversations() {
    if (!isActive) return const [];
    return _conversations ??= _buildConversations();
  }

  static List<Conversation> _buildConversations() {
    final now = DateTime.now().millisecondsSinceEpoch;
    int ago(Duration d) => now - d.inMilliseconds;
    final rows = <Conversation>[
      Conversation(
        convId: 'dm:priya',
        kind: 'dm',
        title: 'Priya Sharma',
        lastText: "The new flow looks great. Let's ship it!",
        lastTs: ago(const Duration(minutes: 2)),
        lastFrom: 'priya',
        unread: 2,
      ),
      Conversation(
        convId: 'group:Design Collective',
        kind: 'group',
        title: 'Design Collective',
        lastText: 'Shared the updated components',
        lastTs: ago(const Duration(minutes: 12)),
        lastFrom: 'alex',
        unread: 3,
        lastIsMine: true,
        lastStatus: MessageStatus.sent,
      ),
      Conversation(
        convId: 'dm:arjun',
        kind: 'dm',
        title: 'Arjun Mehta',
        lastText: 'Can you take a look at the proposal?',
        lastTs: ago(const Duration(minutes: 28)),
        lastFrom: 'arjun',
      ),
      Conversation(
        convId: 'group:Product & Engineering',
        kind: 'group',
        title: 'Product & Engineering',
        lastText: 'Friday release is looking good',
        lastTs: ago(const Duration(hours: 1)),
        lastFrom: 'Nina',
      ),
      Conversation(
        convId: 'dm:meera',
        kind: 'dm',
        title: 'Meera Iyer',
        lastText: 'Clinical examination - Ortho',
        lastTs: ago(const Duration(hours: 3)),
        lastFrom: 'meera',
        unread: 1,
        lastKind: 'form',
        lastFormName: 'Clinical examination - Ortho',
      ),
      Conversation(
        convId: 'dm:ravi',
        kind: 'dm',
        title: 'Ravi Kumar',
        lastText: 'e2e',
        lastTs: ago(const Duration(hours: 5)),
        lastFrom: 'ravi',
        isEncrypted: true,
        lastIsEncrypted: true,
      ),
      Conversation(
        convId: 'dm:sana',
        kind: 'dm',
        title: 'Sana Khan',
        lastText: 'Sending the report now',
        lastTs: ago(const Duration(hours: 6)),
        lastFrom: 'alex',
        lastIsMine: true,
        lastStatus: MessageStatus.pending,
      ),
      Conversation(
        convId: 'dm:dev',
        kind: 'dm',
        title: 'Dev Patel',
        lastText: 'Could you resend the invoice, it did not go through',
        lastTs: ago(const Duration(days: 1, hours: 2)),
        lastFrom: 'alex',
        lastIsMine: true,
        lastStatus: MessageStatus.failed,
      ),
      Conversation(
        convId:
            'group:Regional Operations and Quality Assurance Leadership Team',
        kind: 'group',
        title: 'Regional Operations and Quality Assurance Leadership Team',
        lastText:
            'Please review the attached quarterly summary before the leadership meeting on Thursday morning',
        lastTs: ago(const Duration(days: 3)),
        lastFrom: 'Kavitha',
        unread: 7,
      ),
      Conversation(
        convId: 'host:hr',
        kind: 'host',
        title: 'HR Department',
        lastText: 'Your leave request was approved',
        lastTs: ago(const Duration(days: 9)),
        lastFrom: 'hr',
      ),
      Conversation(
        convId: 'host:support',
        kind: 'host',
        title: 'Support Desk',
        lastText: 'New ticket assigned',
        lastTs: ago(const Duration(days: 40)),
        lastFrom: 'support',
        unread: 128,
      ),
      Conversation(
        convId: 'global',
        kind: 'global',
        title: 'Everyone',
        lastText: 'Welcome to Agile Labs',
        lastTs: ago(const Duration(days: 400)),
        lastFrom: 'admin',
      ),
      Conversation(
        convId: 'group:Old project',
        kind: 'group',
        title: 'Old project',
        lastText: 'Archived chat',
        lastTs: ago(const Duration(days: 60)),
        lastFrom: 'alex',
        isArchived: true,
      ),
    ];
    for (var i = 0; i < _extraRows; i++) {
      rows.add(
        Conversation(
          convId: 'dm:person$i',
          kind: 'dm',
          title: 'Person ${i + 1}',
          lastText: 'Sample message number ${i + 1}',
          lastTs: ago(Duration(minutes: 90 + i * 7)),
          lastFrom: 'person$i',
          unread: i % 9 == 0 ? (i % 4) + 1 : 0,
        ),
      );
    }
    return rows;
  }
}
