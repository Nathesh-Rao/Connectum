import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/models/conversation.dart';
import '../../data/models/form_definition.dart';
import '../../data/models/form_option.dart';
import '../../data/models/form_submission.dart';
import '../../data/models/identity_info.dart';
import '../../data/models/message.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// Debug-only fixture for UI checks: run with --dart-define=SEED_UI=1 and the
/// enterprises screen shows five sample enterprises. Ignored in release. The
/// data lives in memory only: nothing goes to SQLite, SessionStore or secure
/// storage. Remove before release (see CLAUDE.md).
class SeedUi {
  SeedUi._();

  static const _requested = String.fromEnvironment('SEED_UI') == '1';

  /// Debug and profile builds only (profile is needed for the scrolling check).
  static bool get isActive => !kReleaseMode && _requested;

  /// A corner ribbon on every screen while sample data is on.
  static Widget withRibbon(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: Stack(
      fit: StackFit.expand,
      children: [
        child,
        Builder(
          builder: (context) => Positioned(
            right: -50,
            top: MediaQuery.paddingOf(context).top + 6,
            child: IgnorePointer(
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: 170,
                  height: 22,
                  alignment: Alignment.center,
                  color: AppColors.error,
                  child: Text(
                    'SAMPLE DATA',
                    style: AppText.label.copyWith(
                      color: AppColors.background,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

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

  /// Pin or mute in the sample list, so the long-press menu works in this mode.
  static void setFlags(String convId, {bool? isPinned, bool? isMuted}) {
    _conversations = [
      for (final c in conversations())
        c.convId == convId
            ? c.withFlags(isPinned: isPinned, isMuted: isMuted)
            : c,
    ];
    chatsState.refresh();
  }

  // ---- forms -----------------------------------------------------------------

  static final recents = <FormRecent>[
    const FormRecent(name: 'leave', scope: 'user', caption: 'Leave request'),
    const FormRecent(name: 'test_mobile', scope: 'user', caption: 'Test Mobile'),
  ];

  static List<FormOption>? _options;

  /// The picker's list: the forms that exist here, 26 more to scroll, and
  /// two kinds that are not forms (shown as unavailable).
  static List<FormOption> formOptions() {
    if (!isActive) return const [];
    return _options ??= [
      const FormOption(id: 'test-mobile', caption: 'Test Mobile', type: 'data_input', target: 'test_mobile', targetScope: 'user', category: 'data_input', order: 0),
      const FormOption(id: 'leave', caption: 'Leave request', type: 'data_input', target: 'leave', targetScope: 'user', category: 'data_input', order: 1),
      const FormOption(id: 'expense', caption: 'Expense claim', type: 'data_input', target: 'expense', targetScope: 'admin', category: 'data_input', order: 2),
      const FormOption(id: 'all', caption: 'Everything form', type: 'data_input', target: 'all_types', targetScope: 'user', category: 'data_input', order: 3),
      const FormOption(id: 'report', caption: 'Monthly report', type: 'download', target: 'monthly', targetScope: '', category: 'download', order: 4),
      const FormOption(id: 'stock', caption: 'Stock levels', type: 'get_data', target: 'stock', targetScope: '', category: 'get_data', order: 5),
      for (var i = 1; i <= 26; i++)
        FormOption(id: 'sample-$i', caption: 'Sample form $i', type: 'data_input', target: 'leave', targetScope: 'user', category: 'data_input', order: 5 + i),
    ];
  }

  static Map<String, FormCategory> formCategories() => isActive
      ? const {
          'data_input': FormCategory(id: 'data_input', label: 'Forms', icon: 'edit_note', isExecutable: true),
          'download': FormCategory(id: 'download', label: 'Downloads', icon: 'download', isExecutable: true),
          'get_data': FormCategory(id: 'get_data', label: 'Data', icon: 'query_stats', isExecutable: true),
        }
      : const {};

  /// The choices of a list that takes them from the organisation.
  static List<FormChoice>? choices(String source) => switch (source) {
    'branches' => const [
      FormChoice('HQ', 'HQ'),
      FormChoice('Bengaluru', 'Bengaluru'),
      FormChoice('Chennai', 'Chennai'),
    ],
    _ => const [],
  };

  static Map<String, FormDefinition>? _definitions;
  static List<FormSubmission>? _submissions;

  /// A form with a grid section (like the test server's), and captions-only
  /// entries for the others (what a list answer carries).
  static Map<String, FormDefinition> definitions() {
    if (!isActive) return const {};
    return _definitions ??= {
      'test_mobile': FormDefinition.fromMap('test_mobile', 'user', {
        'caption': 'Test Mobile',
        'sections': [
          {'name': 'section1Sec', 'caption': 'Section 1'},
          {'name': 'section2Sec', 'caption': 'Section 2', 'grid': true},
        ],
        'fields': [
          {
            'name': 'testField',
            'caption': 'test field',
            'type': 'text',
            'section': 'section2Sec',
          },
          {
            'name': 'numericText',
            'caption': 'numeric Text',
            'type': 'wholenumber',
            'section': 'section2Sec',
          },
          {
            'name': 'description',
            'caption': 'Description',
            'type': 'text',
            'section': 'section1Sec',
          },
          {
            'name': 'locationField',
            'caption': 'Location Field',
            'type': 'location',
            'section': 'section1Sec',
          },
        ],
      }),
      'ortho': FormDefinition.fromMap('ortho', 'user', {
        'caption': 'Clinical examination - Ortho',
        'fields': {
          'patient': 'Patient',
          'diet': 'Diet advice',
          'physio': 'Physiotherapy required',
          'surgery': 'Surgery required',
          'ip': 'IP required',
          'notes': 'Clinical notes',
          'seenOn': 'Seen on',
          'place': 'Clinic location',
          'fee': 'Consultation fee',
          'tags': 'Tags',
        },
        FormDefinition.captionsOnlyMarker: true,
      }),
      'leave': FormDefinition.fromMap('leave', 'user', {
        'caption': 'Leave request',
        'sections': [
          {'name': 'main', 'caption': 'Leave'},
          {
            'name': 'proof',
            'caption': 'Medical proof',
            'condition': {'field': 'kind', 'op': 'eq', 'value': 'Sick leave'},
          },
        ],
        'fields': [
          {
            'name': 'kind',
            'caption': 'Leave type',
            'type': 'list',
            'required': true,
            'section': 'main',
            'options': ['Casual leave', 'Sick leave', 'Earned leave'],
          },
          {
            'name': 'from',
            'caption': 'From',
            'type': 'date',
            'required': true,
            'section': 'main',
          },
          {
            'name': 'days',
            'caption': 'Days',
            'type': 'wholenumber',
            'required': true,
            'min': 1,
            'max': 30,
            'section': 'main',
          },
          {
            'name': 'doctor',
            'caption': 'Doctor name',
            'type': 'text',
            'required': true,
            'section': 'proof',
          },
        ],
      }),
      'expense': FormDefinition.fromMap('expense', 'admin', {
        'caption': 'Expense claim',
        'fields': [
          {'name': 'title', 'caption': 'Title', 'type': 'text', 'required': true},
          {'name': 'amount', 'caption': 'Amount', 'type': 'number', 'required': true, 'min': 0},
          {'name': 'spentOn', 'caption': 'Spent on', 'type': 'date'},
          {'name': 'where', 'caption': 'Where', 'type': 'location'},
        ],
      }),
      'all_types': FormDefinition.fromMap('all_types', 'user', _allTypes),
    };
  }

  static final _allTypes = <String, Object?>{
    'caption': 'Everything form',
    'sections': [
      {'name': 'basics', 'caption': 'Basics'},
      {'name': 'choices', 'caption': 'Choices'},
      {
        'name': 'more',
        'caption': 'Only for managers',
        'condition': {
          'any': [
            {'field': 'level', 'op': 'eq', 'value': 'Manager'},
            {'field': 'age', 'op': 'gte', 'value': 60},
          ],
        },
      },
      {'name': 'items', 'caption': 'Items', 'grid': true},
    ],
    'fields': [
      {'name': 'title', 'caption': 'Title', 'type': 'text', 'required': true, 'section': 'basics'},
      {'name': 'notes', 'caption': 'Notes', 'type': 'text', 'multiline': true, 'section': 'basics'},
      {'name': 'email', 'caption': 'Email', 'type': 'email', 'section': 'basics'},
      {'name': 'site', 'caption': 'Website', 'type': 'url', 'section': 'basics'},
      {'name': 'phone', 'caption': 'Mobile', 'type': 'mobile', 'section': 'basics'},
      {'name': 'age', 'caption': 'Age', 'type': 'wholenumber', 'min': 18, 'max': 99, 'section': 'basics'},
      {'name': 'fee', 'caption': 'Fee', 'type': 'number', 'min': 0, 'section': 'basics'},
      {'name': 'born', 'caption': 'Date of birth', 'type': 'date', 'max': '2010-12-31', 'section': 'basics'},
      {'name': 'at', 'caption': 'Time', 'type': 'time', 'section': 'basics'},
      {'name': 'level', 'caption': 'Level', 'type': 'list', 'required': true, 'options': ['Staff', 'Manager', 'Director'], 'section': 'choices'},
      {'name': 'city', 'caption': 'City', 'type': 'list', 'options': [for (var i = 1; i <= 40; i++) 'City $i'], 'section': 'choices'},
      {'name': 'tags', 'caption': 'Tags', 'type': 'list', 'multi': true, 'options': ['Urgent', 'Follow-up', 'Billing', 'Travel', 'Training'], 'section': 'choices'},
      {'name': 'branch', 'caption': 'Branch', 'type': 'list', 'source': 'branches', 'section': 'choices'},
      {'name': 'place', 'caption': 'Location', 'type': 'location', 'section': 'choices'},
      {'name': 'code', 'caption': 'Reference', 'type': 'autogenerate', 'section': 'choices'},
      {'name': 'budget', 'caption': 'Budget', 'type': 'number', 'required': true, 'section': 'more'},
      {'name': 'reason', 'caption': 'Reason', 'type': 'text', 'multiline': true, 'section': 'more'},
      {'name': 'item', 'caption': 'Item', 'type': 'text', 'required': true, 'section': 'items'},
      {'name': 'qty', 'caption': 'Quantity', 'type': 'wholenumber', 'min': 1, 'default': 1, 'section': 'items'},
      {'name': 'unit', 'caption': 'Unit', 'type': 'list', 'options': ['Piece', 'Box', 'Kg'], 'section': 'items'},
      {'name': 'file', 'caption': 'Attachment', 'type': 'file', 'section': 'items'},
    ],
  };

  static List<FormSubmission> submissions() {
    if (!isActive) return const [];
    return _submissions ??= _buildSubmissions();
  }

  static List<FormSubmission> _buildSubmissions() {
    final now = DateTime.now().millisecondsSinceEpoch;
    FormSubmission s(
      int id,
      String form,
      Duration ago,
      Map<String, Object?> values, {
      String? status,
    }) => FormSubmission(
      submissionId: '$id',
      tstruct: form,
      byUser: 'alex',
      ts: now - ago.inMilliseconds,
      valuesJson: jsonEncode(values),
      syncState: 'synced',
      status: status,
    );
    return [
      s(1060, 'test_mobile', const Duration(minutes: 20), {
        'description': 'This is a test',
        'locationField': {'lat': 12.918562, 'lng': 77.57447},
        'section2Sec': [
          {'numericText': 12, 'testField': 'test'},
          {'numericText': 340000, 'testField': 'second row with a longer text'},
        ],
      }),
      s(1059, 'ortho', const Duration(hours: 3), {
        'patient': 'Sabarish',
        'diet': 'test',
        'physio': 'Yes',
        'surgery': 'No',
        'ip': true,
        'notes':
            'Patient reports intermittent pain in the left knee after long walks. Advised rest, ice and a follow-up in two weeks if it does not settle.',
        'seenOn': '2026-10-28',
        'place': 'MG Road clinic, Bengaluru 560001',
        'fee': 1250.5,
        'tags': ['knee', 'follow-up', 'physio'],
      }),
      s(1058, 'leave', const Duration(days: 1, hours: 2), {
        'kind': 'Casual leave',
        'from': '2026-11-03',
        'days': 2,
      }),
      s(1057, 'expense', const Duration(days: 2), {
        'title': 'Client dinner',
        'amount': 18400,
        'spentOn': '2026-10-26',
        'where': {
          'lat': 12.9716,
          'lng': 77.5946,
          'address': '12 Church Street, Bengaluru',
        },
      }, status: 'Pending'),
      s(1056, 'expense', const Duration(days: 5), {
        'title': 'Taxi to airport',
        'amount': 950,
        'spentOn': '2026-10-23',
      }, status: 'Approved'),
      s(1055, 'leave', const Duration(days: 9), {
        'kind': 'Sick leave',
        'from': '2026-10-20',
        'days': 1,
      }),
      for (var i = 0; i < _extraRows ~/ 10; i++)
        s(
          900 - i,
          'expense',
          Duration(days: 12 + i),
          {
            'title': 'Sample expense ${i + 1}',
            'amount': 100 * (i + 1),
            'spentOn': '2026-09-${(i % 27 + 1).toString().padLeft(2, '0')}',
          },
          status: i.isEven ? 'Approved' : 'Pending',
        ),
    ];
  }

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
        memberCount: 5,
        isMuted: true,
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
        isPinned: true,
      ),
      Conversation(
        convId: 'group:Product & Engineering',
        kind: 'group',
        title: 'Product & Engineering',
        lastText: 'Friday release is looking good',
        lastTs: ago(const Duration(hours: 1)),
        lastFrom: 'Nina',
        memberCount: 8,
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
        convId: 'dm:forms',
        kind: 'dm',
        title: 'Form cards (sample)',
        lastText: 'Clinical examination - Ortho',
        lastTs: ago(const Duration(seconds: 30)),
        lastFrom: 'forms',
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
