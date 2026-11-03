import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/e2e/e2e_models.dart';
import '../../data/models/conversation.dart';
import '../../data/models/form_definition.dart';
import '../../data/models/form_option.dart';
import '../../data/models/form_submission.dart';
import '../../data/models/hash_command.dart';
import '../../data/models/identity_info.dart';
import '../../data/models/message.dart';
import '../../data/repositories/e2e_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'seed_sample_forms.dart';

/// Debug-only fixture for UI checks: run with --dart-define=SEED_UI=1 and the
/// enterprises screen shows five sample enterprises. Ignored in release. The
/// data lives in memory only: nothing goes to SQLite, SessionStore or secure
/// storage. Remove before release (see CLAUDE.md).
class SeedUi {
  SeedUi._();

  static const _requested = String.fromEnvironment('SEED_UI') == '1';

  /// Debug builds only.
  static bool get isActive => kDebugMode && _requested;

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
        for (final (name, id, status) in [
          ('Northwind Traders', 'NW7D-3QPX', 'pending'),
          ('Orchard Co-op', '8RCH-4RD1', 'rejected'),
        ])
          EnterpriseMembership(
            enterprise: id,
            name: name,
            city: '',
            category: 'Vendor',
            username: 'alex',
            status: status,
          ),
      ],
    );
  }

  /// Profile tab fixtures: typical, long (long name and email) or sparse
  /// (optional fields missing); and how many unsent messages the log out
  /// sheet reports.
  static final profileVariant = 'typical'.obs;
  static final profileUnsent = 0.obs;

  static ({
    String name,
    String username,
    String email,
    String connectumId,
    String category,
  })
  profile() => switch (profileVariant.value) {
    'long' => (
      name: 'Alexandria Montgomery-Featherstonehaugh',
      username: 'alexandria.montgomery.featherstonehaugh',
      email:
          'alexandria.montgomery-featherstonehaugh@very-long-company-domain.example.com',
      connectumId: 'MN68-2CQ9',
      category: 'Regional distribution partner',
    ),
    'sparse' => (
      name: 'Alex Morgan',
      username: '',
      email: '',
      connectumId: 'MN68-2CQ9',
      category: '',
    ),
    _ => (
      name: 'Alex Morgan',
      username: 'alex',
      email: 'alex@example.com',
      connectumId: 'MN68-2CQ9',
      category: 'Employee',
    ),
  };

  /// Which state the Chats screen shows: content, loading, empty, error or
  /// offline. Switched by the debug chips on the screen.
  static final chatsState = _chatsDelay > 0 ? 'loading'.obs : 'content'.obs;

  /// SEED_CHATS_DELAY_MS=3000 holds the Chats skeleton for that long at start.
  static const _chatsDelay = int.fromEnvironment('SEED_CHATS_DELAY_MS');

  static void releaseChatsDelay() {
    if (!isActive || _chatsDelay <= 0) return;
    Future.delayed(
      const Duration(milliseconds: _chatsDelay),
      () => chatsState.value = 'content',
    );
  }

  /// SEED_ROWS=300 adds that many generated direct messages after the samples,
  /// for the scrolling check.
  static const _extraRows = int.fromEnvironment('SEED_ROWS');

  static const online = {'priya', 'meera'};

  static final _trusted = <String>{};

  /// The composer state of the encrypted sample threads. dm:ravi: this phone is
  /// registered, so it unlocks (null). dm:isha: the peer has no device. dm:arjun:
  /// a security key changed until it is trusted.
  static ({String reason, bool isKeyChange})? e2eGate(String convId) {
    if (e2eState.value == 'required' && convId.startsWith('dm:')) {
      return (reason: 'Setting up secure messaging', isKeyChange: false);
    }
    if (convId == 'dm:isha') {
      return (reason: "isha hasn't set up encryption yet", isKeyChange: false);
    }
    if (convId == 'group:Night Shift') {
      return (
        reason: "meera and isha haven't set up encryption yet",
        isKeyChange: false,
      );
    }
    if (convId == 'group:Finance' && !_trusted.contains(convId)) {
      return (reason: "kavitha's security key changed", isKeyChange: true);
    }
    if (convId == 'dm:zoya' && !_trusted.contains(convId)) {
      return (reason: "zoya's security key changed", isKeyChange: true);
    }
    return null;
  }

  static void trust(String convId) => _trusted.add(convId);

  static const e2eStates = [
    'devices',
    'pending',
    'notice',
    'limit',
    'removed',
    'earlier',
    'required',
    'late',
    'late-none',
    'readable',
  ];

  /// The secure-messaging setup state shown by the sample screens ('required':
  /// required mode before setup finished).
  static final e2eState = 'devices'.obs;

  static E2eDevicePublic _device(
    String id,
    String label,
    int daysAgo, {
    bool isLate = false,
  }) => E2eDevicePublic(
    id: id,
    ecdh: '',
    sign: '',
    isLate: isLate,
    label: label,
    ts: DateTime.now().subtract(Duration(days: daysAgo)).millisecondsSinceEpoch,
  );

  /// Puts a setup state into the E2E repository's in-memory fields. Nothing
  /// is registered, stored or sent.
  static void applyE2e(E2eRepository e2e, String state) {
    e2eState.value = state;
    const mine = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
    final phone = _device(mine, 'Connectum mobile (moto g32)', 0);
    final older = [
      _device('9f8e7d6c5b4a39281706f5e4d3c2b1a0', 'Chrome on Mac', 41),
      _device('0a1b2c3d4e5f60718293a4b5c6d7e8f1', 'Firefox on Windows', 12),
    ];
    e2e.mode.value = state == 'required' ? 'required' : 'optional';
    e2e.maxDevices.value = state == 'limit' ? 3 : 10;
    e2e.isStatusKnown.value = true;
    e2e.isRecoveryOn.value = state == 'devices' || state == 'earlier';
    e2e.issueReason.value = '';
    e2e.notice.value = '';
    e2e.isLate.value = false;
    e2e.helpers.clear();
    e2e.isHelpersKnown.value = false;
    e2e.lateHint.value = '';
    e2e.hasKeys.value = true;
    e2e.deviceId.value = mine;
    e2e.myDevices.assignAll([phone, ...older]);
    switch (state) {
      case 'pending':
      case 'required':
        e2e.hasKeys.value = false;
        e2e.deviceId.value = '';
        e2e.myDevices.assignAll(older);
        e2e.phase.value = E2eSetupPhase.working;
      case 'notice':
        e2e.notice.value = E2eRepository.noticeText;
        e2e.phase.value = E2eSetupPhase.ready;
      case 'earlier':
        e2e.notice.value =
            '${E2eRepository.noticeText}${E2eRepository.earlierText}';
        e2e.myDevices.assignAll([
          phone,
          _device('1111c3d4e5f60718293a4b5c6d7e8f90', phone.label, 30),
          ...older,
        ]);
        e2e.phase.value = E2eSetupPhase.ready;
      case 'late':
      case 'late-none':
        // This phone is late: with a helper (an older device active lately),
        // or with none, which points to the recovery code.
        final isHelped = state == 'late';
        e2e.myDevices.assignAll([
          _device(mine, phone.label, 0, isLate: true),
          ...older,
        ]);
        e2e.isLate.value = true;
        e2e.isHelpersKnown.value = true;
        if (isHelped) e2e.helpers.assignAll([older.first]);
        e2e.lateHint.value = E2eRepository.lateHintText;
        e2e.phase.value = E2eSetupPhase.ready;
      case 'readable':
        e2e.notice.value = E2eRepository.readableText;
        e2e.phase.value = E2eSetupPhase.ready;
      case 'limit':
        e2e.hasKeys.value = false;
        e2e.deviceId.value = '';
        e2e.myDevices.assignAll([
          ...older,
          _device('2222c3d4e5f60718293a4b5c6d7e8f90', 'iPhone', 90),
        ]);
        e2e.phase.value = E2eSetupPhase.limit;
      case 'removed':
        e2e.myDevices.assignAll(older);
        e2e.phase.value = E2eSetupPhase.removed;
      default:
        e2e.phase.value = E2eSetupPhase.ready;
    }
  }

  static bool isEncrypted(String convId) =>
      conversations().any((c) => c.convId == convId && c.isEncrypted);

  /// A fake `/cmds` catalog: the real names, sample summaries.
  static List<HashCommand> commands() {
    HashCommand c(
      String name,
      String summary,
      String usage,
      String reply, {
      List<String> aliases = const [],
      String category = 'lookup',
      bool isAvailable = true,
    }) => HashCommand(
      name: name,
      aliases: aliases,
      category: category,
      summary: summary,
      usage: usage,
      replies: [reply],
      isAvailable: isAvailable,
    );
    return [
      c(
        'dm',
        'Send a direct message to someone',
        '#dm <user> <text...>',
        'dm_ack',
        aliases: ['msg', 'pm'],
        category: 'messaging',
      ),
      c(
        'reply',
        'Reply to a message in the global room',
        '#reply <messageId> <text...>',
        'own_message_id',
        category: 'messaging',
      ),
      c(
        'replydm',
        'Reply to a message in a direct conversation',
        '#replydm <user> <messageId> <text...>',
        'dm_ack',
        category: 'messaging',
      ),
      c(
        'groupmsg',
        'Send a message to a group',
        '#groupmsg <group> <text...>',
        'group_msg_ack',
        aliases: ['gm'],
        category: 'messaging',
      ),
      c(
        'replygroup',
        'Reply to a message in a group',
        '#replygroup <group> <messageId> <text...>',
        'group_msg_ack',
        category: 'messaging',
      ),
      c(
        'users',
        'Who is online right now',
        '#users',
        'users',
        aliases: ['online', 'who'],
      ),
      c('groups', 'The groups you are in', '#groups', 'groups'),
      c(
        'inbox',
        'Your direct-message threads, newest first',
        '#inbox',
        'conversations',
        aliases: ['conversations'],
      ),
      c(
        'profile',
        "See someone's avatar and status",
        '#profile <user>',
        'profile',
      ),
      c(
        'creategroup',
        'Create a group',
        '#creategroup <name>',
        'group_created',
        aliases: ['newgroup'],
        category: 'groups',
      ),
      c(
        'leavegroup',
        'Leave a group',
        '#leavegroup <group>',
        'left_group',
        aliases: ['leave'],
        category: 'groups',
      ),
      c(
        'me',
        'Your account, permissions and counters',
        '#me',
        'sd',
        aliases: ['whoami'],
        category: 'people',
      ),
      c(
        'associates',
        'People you are connected with',
        '#associates',
        'sd',
        aliases: ['contacts'],
        category: 'people',
      ),
      c(
        'find',
        'Find a person by username, email or mobile',
        '#find <query...>',
        'sd',
        aliases: ['search'],
        category: 'people',
      ),
      c(
        'requests',
        'Your pending approvals and invitations',
        '#requests [status]',
        'sd',
        aliases: ['approvals'],
        category: 'people',
      ),
      c(
        'accept',
        'Accept a request or invitation',
        '#accept <requestId>',
        'sd',
        category: 'people',
      ),
      c(
        'reject',
        'Reject a request or invitation',
        '#reject <requestId>',
        'sd',
        category: 'people',
      ),
      c(
        'transfer',
        'Ask another host to take over one of your users',
        '#transfer <user> <toHost>',
        'sd',
        category: 'people',
        isAvailable: false,
      ),
      c(
        'notifications',
        'Your notifications (unread first)',
        '#notifications [category]',
        'sd',
        aliases: ['notifs'],
        category: 'inbox',
      ),
      c(
        'remind',
        'Add a reminder card for yourself',
        '#remind <text...>',
        'sd',
        aliases: ['reminder'],
        category: 'inbox',
      ),
      c(
        'forms',
        'The forms and options available to you',
        '#forms',
        'sd',
        category: 'forms',
      ),
      c(
        'tstruct',
        'Open a form in the viewer',
        '#tstruct <name>',
        'sd',
        aliases: ['ts', 'structure'],
        category: 'forms',
      ),
      c(
        'submissions',
        'Forms you have submitted',
        '#submissions',
        'sd',
        category: 'forms',
      ),
      c(
        'help',
        'List all # commands, or explain one',
        '#help [command]',
        'cmd_catalog',
        aliases: ['commands'],
        category: 'help',
      ),
      const HashCommand(
        name: 'leaverequest',
        category: 'custom',
        summary: 'Request time off',
        usage: '#leaverequest [input]',
        isCustom: true,
      ),
    ];
  }

  /// The fake answer of a command that is not a message send.
  static String hashInfo(HashCommand cmd) => switch (cmd.name) {
    'users' => 'Online: priya, meera',
    'groups' => 'Groups: Design Collective, Product & Engineering',
    'me' => 'Signed in as alex',
    'forms' => '4 options: Clinical examination, Leave request, Expense, Visit',
    'associates' => '3 users: priya, meera, arjun',
    _ => 'Done (sample result)',
  };

  static E2eKeyReview keyReview(String user) => E2eKeyReview(
    user: user,
    safetyNumber:
        '48210 93751 07264 55819 30427 71586 12093 64875 20318 97640 53172 80469',
    devices: const {},
    changed: [
      E2ePinChange(
        user: user,
        device: const E2eDevicePublic(
          id: '3f9a1c7e5b2d4086a1f0c9d8e7b6a5f4',
          ecdh: '',
          sign: '',
          label: 'Chrome on Windows',
        ),
      ),
    ],
  );
  static const offline = {'arjun', 'ravi'};

  static const _careMembers = [
    'alex',
    'isha',
    'kavitha',
    'meera',
    'nina',
    'raj',
  ];

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
    const FormRecent(
      name: 'test_mobile',
      scope: 'user',
      caption: 'Test Mobile',
    ),
  ];

  static List<FormOption>? _options;

  /// The picker's list: the forms that exist here, 26 more to scroll, and
  /// two kinds that are not forms (shown as unavailable).
  static List<FormOption> formOptions() {
    if (!isActive) return const [];
    return _options ??= [
      const FormOption(
        id: 'test-mobile',
        caption: 'Test Mobile',
        type: 'data_input',
        target: 'test_mobile',
        targetScope: 'user',
        category: 'data_input',
        order: 0,
      ),
      const FormOption(
        id: 'leave',
        caption: 'Leave request',
        type: 'data_input',
        target: 'leave',
        targetScope: 'user',
        category: 'data_input',
        order: 1,
      ),
      const FormOption(
        id: 'expense',
        caption: 'Expense claim',
        type: 'data_input',
        target: 'expense',
        targetScope: 'admin',
        category: 'data_input',
        order: 2,
      ),
      const FormOption(
        id: 'all',
        caption: 'Everything form',
        type: 'data_input',
        target: 'all_types',
        targetScope: 'user',
        category: 'data_input',
        order: 3,
      ),
      const FormOption(
        id: 'report',
        caption: 'Monthly report',
        type: 'download',
        target: 'monthly',
        targetScope: '',
        category: 'download',
        order: 4,
      ),
      const FormOption(
        id: 'stock',
        caption: 'Stock levels',
        type: 'get_data',
        target: 'stock',
        targetScope: '',
        category: 'get_data',
        order: 5,
      ),
      ...SeedSampleForms.options(),
      for (var i = 1; i <= 26; i++)
        FormOption(
          id: 'sample-$i',
          caption: 'Sample form $i',
          type: 'data_input',
          target: 'leave',
          targetScope: 'user',
          category: 'data_input',
          order: 5 + i,
        ),
    ];
  }

  static Map<String, FormCategory> formCategories() => isActive
      ? const {
          'data_input': FormCategory(
            id: 'data_input',
            label: 'Forms',
            icon: 'edit_note',
            isExecutable: true,
          ),
          'download': FormCategory(
            id: 'download',
            label: 'Downloads',
            icon: 'download',
            isExecutable: true,
          ),
          'get_data': FormCategory(
            id: 'get_data',
            label: 'Data',
            icon: 'query_stats',
            isExecutable: true,
          ),
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
          {
            'name': 'title',
            'caption': 'Title',
            'type': 'text',
            'required': true,
          },
          {
            'name': 'amount',
            'caption': 'Amount',
            'type': 'number',
            'required': true,
            'min': 0,
          },
          {'name': 'spentOn', 'caption': 'Spent on', 'type': 'date'},
          {'name': 'where', 'caption': 'Where', 'type': 'location'},
        ],
      }),
      'all_types': FormDefinition.fromMap('all_types', 'user', _allTypes),
      ...SeedSampleForms.definitions(),
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
      {
        'name': 'title',
        'caption': 'Title',
        'type': 'text',
        'required': true,
        'section': 'basics',
      },
      {
        'name': 'notes',
        'caption': 'Notes',
        'type': 'text',
        'multiline': true,
        'section': 'basics',
      },
      {
        'name': 'email',
        'caption': 'Email',
        'type': 'email',
        'section': 'basics',
      },
      {
        'name': 'site',
        'caption': 'Website',
        'type': 'url',
        'section': 'basics',
      },
      {
        'name': 'phone',
        'caption': 'Mobile',
        'type': 'mobile',
        'section': 'basics',
      },
      {
        'name': 'age',
        'caption': 'Age',
        'type': 'wholenumber',
        'min': 18,
        'max': 99,
        'section': 'basics',
      },
      {
        'name': 'fee',
        'caption': 'Fee',
        'type': 'number',
        'min': 0,
        'section': 'basics',
      },
      {
        'name': 'born',
        'caption': 'Date of birth',
        'type': 'date',
        'max': '2010-12-31',
        'section': 'basics',
      },
      {'name': 'at', 'caption': 'Time', 'type': 'time', 'section': 'basics'},
      {
        'name': 'level',
        'caption': 'Level',
        'type': 'list',
        'required': true,
        'options': ['Staff', 'Manager', 'Director'],
        'section': 'choices',
      },
      {
        'name': 'city',
        'caption': 'City',
        'type': 'list',
        'options': [for (var i = 1; i <= 40; i++) 'City $i'],
        'section': 'choices',
      },
      {
        'name': 'tags',
        'caption': 'Tags',
        'type': 'list',
        'multi': true,
        'options': ['Urgent', 'Follow-up', 'Billing', 'Travel', 'Training'],
        'section': 'choices',
      },
      {
        'name': 'branch',
        'caption': 'Branch',
        'type': 'list',
        'source': 'branches',
        'section': 'choices',
      },
      {
        'name': 'place',
        'caption': 'Location',
        'type': 'location',
        'section': 'choices',
      },
      {
        'name': 'code',
        'caption': 'Reference',
        'type': 'autogenerate',
        'section': 'choices',
      },
      {
        'name': 'budget',
        'caption': 'Budget',
        'type': 'number',
        'required': true,
        'section': 'more',
      },
      {
        'name': 'reason',
        'caption': 'Reason',
        'type': 'text',
        'multiline': true,
        'section': 'more',
      },
      {
        'name': 'item',
        'caption': 'Item',
        'type': 'text',
        'required': true,
        'section': 'items',
      },
      {
        'name': 'qty',
        'caption': 'Quantity',
        'type': 'wholenumber',
        'min': 1,
        'default': 1,
        'section': 'items',
      },
      {
        'name': 'unit',
        'caption': 'Unit',
        'type': 'list',
        'options': ['Piece', 'Box', 'Kg'],
        'section': 'items',
      },
      {
        'name': 'file',
        'caption': 'Attachment',
        'type': 'file',
        'section': 'items',
      },
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
      _local(refusedId, 'sample_selection', const Duration(minutes: 6), {
        'pick': 'Purple',
      }),
      _local(draftId, 'sample_fetch', const Duration(minutes: 2), {
        'colour': 'Green',
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

  static const refusedId = 'temp-seed-refused';
  static const draftId = 'temp-seed-draft';

  static FormSubmission _local(
    String id,
    String form,
    Duration ago,
    Map<String, Object?> values,
  ) => FormSubmission(
    submissionId: id,
    tstruct: form,
    byUser: 'alex',
    ts: DateTime.now().millisecondsSinceEpoch - ago.inMilliseconds,
    valuesJson: jsonEncode(values),
    syncState: 'pending_create',
  );

  /// A sample form the server refused (a stale choice) and a draft that waits
  /// for a fetch, in the Work Space, to see both states.
  static final formFailures = <String, String>{
    refusedId: 'Some answers need fixing.',
  };
  static final formDrafts = <String, List<String>>{
    draftId: ['Code of the colour (fetched)'],
  };
  static final formPending =
      <
        String,
        ({
          Map<String, dynamic> values,
          Object? errors,
          String name,
          String scope,
          String caption,
          bool isDraft,
        })
      >{
        refusedId: (
          values: {'pick': 'Purple'},
          errors: {
            'fields': {'pick': 'That is not one of the choices on offer.'},
          },
          name: 'sample_selection',
          scope: 'user',
          caption: 'Sample: choices from another form, and a fill',
          isDraft: false,
        ),
        draftId: (
          values: {'colour': 'Green'},
          errors: null,
          name: 'sample_fetch',
          scope: 'user',
          caption: 'Sample: fetch (a field filled from another form)',
          isDraft: true,
        ),
      };

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
        lastText:
            '[ATTACHMENT:{"kind":"image","name":"components.jpg","size":"1.2 MB","url":"/uploads/seed-photo.jpg","type":"image/jpeg"}]',
        lastTs: ago(const Duration(minutes: 12)),
        lastFrom: 'alex',
        unread: 3,
        memberCount: 5,
        isMuted: true,
        lastIsMine: true,
        lastStatus: MessageStatus.sent,
      ),
      Conversation(
        convId: 'group:Care Team',
        kind: 'group',
        title: 'Care Team',
        lastText: 'Thanks all.',
        lastTs: ago(const Duration(minutes: 3)),
        lastFrom: 'kavitha',
        isEncrypted: true,
        memberCount: 6,
        members: _careMembers,
      ),
      Conversation(
        convId: 'group:Night Shift',
        kind: 'group',
        title: 'Night Shift',
        lastText: 'Thanks all.',
        lastTs: ago(const Duration(minutes: 20)),
        lastFrom: 'kavitha',
        isEncrypted: true,
        memberCount: 6,
        members: _careMembers,
      ),
      Conversation(
        convId: 'group:Finance',
        kind: 'group',
        title: 'Finance',
        lastText: 'Thanks all.',
        lastTs: ago(const Duration(minutes: 40)),
        lastFrom: 'kavitha',
        isEncrypted: true,
        memberCount: 6,
        members: _careMembers,
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
        lastText: 'See you at 5. Bring the signed copy.',
        lastTs: ago(const Duration(hours: 5)),
        lastFrom: 'ravi',
        isEncrypted: true,
      ),
      Conversation(
        convId: 'dm:isha',
        kind: 'dm',
        title: 'Isha Rao',
        lastText: 'e2e1:EEEE',
        lastTs: ago(const Duration(hours: 5, minutes: 30)),
        lastFrom: 'isha',
        isEncrypted: true,
        lastIsEncrypted: true,
      ),
      Conversation(
        convId: 'dm:zoya',
        kind: 'dm',
        title: 'Zoya Ali',
        lastText: 'Thanks, noted.',
        lastTs: ago(const Duration(hours: 5, minutes: 40)),
        lastFrom: 'zoya',
        isEncrypted: true,
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
