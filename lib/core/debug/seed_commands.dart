import '../../data/commands/command_reply.dart';

/// Fixture for `/debug/commands`: the catalogue frame of the "#" commands doc
/// (section 1.2) and the table of section 3.2, and canned server answers. No
/// server call is made.
class SeedCommands {
  SeedCommands._();

  static Map<String, dynamic> _arg(
    String name,
    String type, {
    bool required = true,
    List<String>? values,
    int? max,
  }) => {
    'name': name,
    'type': type,
    'required': required,
    'values': ?values,
    if (max != null) ...{'rest': true, 'max': max},
  };

  static Map<String, dynamic> _cmd(
    String name,
    String category,
    String summary,
    String usage,
    List<Map<String, dynamic>> args, {
    List<String> aliases = const [],
    List<String> reply = const ['sd'],
    bool available = true,
    String requires = 'none',
  }) => {
    'name': name,
    'aliases': aliases,
    'category': category,
    'summary': summary,
    'usage': usage,
    'args': args,
    'reply': reply,
    'available': available,
    'requires': requires,
  };

  static Map<String, dynamic> catalogFrame() => {
    'type': 'cmd_catalog',
    'prefix': '#',
    'escape': '##',
    'filter': '',
    'categories': [
      for (final c in const [
        ['messaging', 'Messaging'],
        ['lookup', 'Look things up'],
        ['groups', 'Groups'],
        ['profile', 'Your profile'],
        ['people', 'People and approvals'],
        ['inbox', 'Notifications and cards'],
        ['forms', 'Forms'],
        ['admin', 'Administration'],
        ['custom', 'Custom'],
        ['help', 'Help'],
      ])
        {'id': c[0], 'label': c[1]},
    ],
    'commands': [
      _cmd(
        'dm',
        'messaging',
        'Send a direct message to someone',
        '#dm <user> <text...>',
        [_arg('user', 'user'), _arg('text', 'text', max: 2000)],
        aliases: ['msg', 'pm'],
        reply: ['dm_ack'],
      ),
      _cmd(
        'groupmsg',
        'messaging',
        'Message a group',
        '#groupmsg <group> <text...>',
        [_arg('group', 'group'), _arg('text', 'text', max: 2000)],
        aliases: ['gm'],
        reply: ['group_msg_ack'],
      ),
      _cmd(
        'users',
        'lookup',
        'Who is online',
        '#users',
        [],
        aliases: ['online', 'who'],
        reply: ['users'],
      ),
      _cmd(
        'groups',
        'lookup',
        'Groups you are in',
        '#groups',
        [],
        reply: ['groups'],
      ),
      _cmd(
        'inbox',
        'lookup',
        'Direct threads, newest first',
        '#inbox',
        [],
        aliases: ['conversations'],
        reply: ['conversations'],
      ),
      _cmd(
        'historyhost',
        'lookup',
        'Load a host conversation',
        '#historyhost <host>',
        [_arg('host', 'host')],
        reply: ['history'],
      ),
      _cmd(
        'profile',
        'profile',
        "Someone's avatar and status",
        '#profile <user>',
        [_arg('user', 'user')],
        reply: ['profile'],
      ),
      _cmd(
        'creategroup',
        'groups',
        'Create a group',
        '#creategroup <name>',
        [_arg('name', 'group')],
        aliases: ['newgroup'],
        reply: ['group_created'],
      ),
      _cmd(
        'addmember',
        'groups',
        'Add an online user to a group',
        '#addmember <group> <user>',
        [_arg('group', 'group'), _arg('user', 'user')],
        aliases: ['invitegroup'],
        reply: ['group_created', 'group_invite_pending'],
      ),
      _cmd(
        'leavegroup',
        'groups',
        'Leave a group',
        '#leavegroup <group>',
        [_arg('group', 'group')],
        aliases: ['leave'],
        reply: ['left_group'],
      ),
      _cmd(
        'me',
        'profile',
        'Your account and permissions',
        '#me',
        [],
        aliases: ['whoami'],
      ),
      _cmd(
        'associates',
        'people',
        'People you are connected with',
        '#associates',
        [],
        aliases: ['contacts'],
      ),
      _cmd(
        'find',
        'people',
        'Find a person by username, email or mobile',
        '#find <query...>',
        [_arg('query', 'text', max: 100)],
        aliases: ['search'],
      ),
      _cmd(
        'transfer',
        'people',
        'Ask another host to take over a user',
        '#transfer <user> <toHost>',
        [_arg('user', 'user'), _arg('toHost', 'user')],
        available: false,
        requires: 'host',
      ),
      _cmd(
        'scan',
        'people',
        'Connect with someone by their code',
        '#scan <code...>',
        [_arg('code', 'text', max: 100)],
      ),
      _cmd(
        'forms',
        'forms',
        'Forms and options available to you',
        '#forms',
        [],
      ),
      _cmd(
        'options',
        'forms',
        'Options of lite structures',
        '#options [category]',
        [_arg('category', 'word', required: false)],
        aliases: ['opts'],
      ),
      _cmd(
        'lookups',
        'admin',
        'Organisation lists',
        '#lookups',
        [],
        aliases: ['cfg-lookups'],
      ),
      _cmd('form', 'forms', 'Open a form definition', '#form <name>', [
        _arg('name', 'word'),
      ]),
      _cmd(
        'tstruct',
        'forms',
        'Open a form with your records',
        '#tstruct <name>',
        [_arg('name', 'text')],
        aliases: ['ts', 'struct'],
      ),
      _cmd(
        'tstruct-add',
        'forms',
        'Open a form to fill in',
        '#tstruct-add <name>',
        [_arg('name', 'text')],
        aliases: ['create', 'ts-add'],
      ),
      _cmd(
        'help',
        'help',
        'List commands or explain one',
        '#help [command]',
        [_arg('command', 'word', required: false)],
        aliases: ['commands'],
        reply: ['cmd_catalog'],
      ),
      _cmd(
        'rate',
        'admin',
        'Set a rating (enum sample)',
        '#rate <level>',
        [
          _arg('level', 'enum', values: ['low', 'medium', 'high']),
        ],
        available: false,
        requires: 'admin',
      ),
      _cmd(
        'react',
        'messaging',
        'React to a message (msgid, emoji sample)',
        '#react <id> <emoji>',
        [_arg('id', 'msgid'), _arg('emoji', 'emoji')],
      ),
      _cmd('open', 'lookup', 'Open a link (url sample)', '#open <link>', [
        _arg('link', 'url'),
      ]),
    ],
  };

  static const people = [
    'ana',
    'ravi',
    'meera',
    'sunil',
    'priya',
    'kiran',
    'dev',
    'asha',
    'omar',
    'lena',
    'tom',
    'zoe',
  ];

  /// Answers a `/cmdcomplete` input like the server would for a `user`
  /// argument, after [latency].
  static Future<CommandSuggestions> suggest(
    String input,
    int page,
    int reqId, {
    required Duration latency,
  }) async {
    await Future<void>.delayed(latency);
    final token = input.contains(' ') ? input.split(' ').last : '';
    final all = [
      for (final p in people)
        if (p.startsWith(token.toLowerCase())) p,
    ];
    final from = (page - 1) * CommandSuggester.pageSize;
    final slice = all.skip(from).take(CommandSuggester.pageSize).toList();
    return CommandSuggestions(
      input: input,
      reqId: reqId,
      kind: 'arg',
      token: token,
      argName: 'user',
      items: [
        for (final p in slice)
          CommandSuggestion(value: p, label: p, hint: 'online'),
      ],
      page: page,
      hasMore: from + slice.length < all.length,
      total: all.length,
    );
  }

  static Map<String, dynamic> unknownFrame(String name) => {
    'type': 'error',
    'code': 'unknown_command',
    'text':
        '#$name is not a command. Type #help to see them all, or ## to send a message that starts with #.',
    'suggestions': ['dm', 'users', 'groups'],
  };

  static Map<String, dynamic> usageFrame() => {
    'type': 'error',
    'code': 'usage',
    'text': 'Missing text. Usage: #dm <user> <text...>',
    'command': 'dm',
    'usage': '#dm <user> <text...>',
  };
}
