import '../repositories/conversation_repository.dart';

/// A port of the web's `careSummary.js` (`toPlainText`): the `care.summary`
/// answer as the plain text the web copies, and the thread's person.
class CareSummaryText {
  CareSummaryText._();

  static final _care = RegExp(r'^care-([A-Za-z0-9._-]+)$');

  /// The username of the person of a care thread (`group:care-<username>`),
  /// or null when [convId] is not one or the name has no usable username.
  static String? personOf(String convId) {
    if (ConversationRepository.kindOf(convId) != 'group') return null;
    final m = _care.firstMatch(ConversationRepository.targetOf(convId).trim());
    return m?.group(1);
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _dayKey(DateTime d) =>
      '${d.year}-${_two(d.month)}-${_two(d.day)}';

  static DateTime _at(num ts) =>
      DateTime.fromMillisecondsSinceEpoch(ts.toInt());

  static String timeOf(num ts) {
    final d = _at(ts);
    return '${_two(d.hour)}:${_two(d.minute)}';
  }

  /// "Today", "Yesterday", or "13 Oct" (with the year when it is not this
  /// year).
  static String dayLabel(num ts, DateTime now) {
    final d = _at(ts);
    final key = _dayKey(d);
    if (key == _dayKey(now)) return 'Today';
    if (key == _dayKey(now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    final label = '${d.day} ${_months[d.month - 1]}';
    return d.year == now.year ? label : '$label ${d.year}';
  }

  static List<Map> _list(Object? v) => v is List
      ? [
          for (final x in v)
            if (x is Map) x,
        ]
      : const [];

  static String _s(Object? v) => v == null ? '' : '$v';

  static num _n(Object? v) => v is num ? v : 0;

  static List<String> _roles(Map m) {
    final roles = m['roles'];
    final list = roles is List && roles.isNotEmpty
        ? roles
        : (m['role'] != null && '${m['role']}'.isNotEmpty ? [m['role']] : []);
    return [
      for (final r in list)
        if (r != null && '$r'.isNotEmpty) '$r',
    ];
  }

  static String _plural(num n, String one, [String? many]) =>
      '$n ${n == 1 ? one : (many ?? '${one}s')}';

  /// "9 forms and 2 messages by 6 people, 13 Oct to 14 Oct."
  static String headline(Map summary, DateTime now) {
    final s = summary['stats'];
    if (s is! Map || (_n(s['forms']) == 0 && _n(s['messages']) == 0)) {
      return 'Nothing has been recorded in this thread yet.';
    }
    final parts = [
      if (_n(s['forms']) != 0) _plural(_n(s['forms']), 'form'),
      if (_n(s['messages']) != 0) _plural(_n(s['messages']), 'message'),
    ];
    final who = _plural(_n(s['people']), 'person', 'people');
    final head = '${parts.join(' and ')} by $who';
    if (s['first'] is! num || s['last'] is! num) return '$head.';
    final a = dayLabel(s['first'] as num, now);
    final b = dayLabel(s['last'] as num, now);
    return '$head, ${a == b ? a : '$a to $b'}.';
  }

  /// "41 · Male · Tiruchirappalli": age, gender and city when present.
  static String factsLine(Map summary) {
    final person = summary['person'];
    final rows = person is Map ? _list(person['rows']) : const <Map>[];
    String? pick(String label) {
      for (final r in rows) {
        if (r['label'] == label) return _s(r['value']);
      }
      return null;
    }

    return [
      pick('Age'),
      pick('Gender'),
      pick('City'),
    ].where((v) => v != null && v.isNotEmpty).join(' · ');
  }

  static String _fields(List<Map> fields, Object? more) {
    final text = fields
        .map((f) => '${_s(f['caption'])}: ${_s(f['value'])}')
        .join('; ');
    return _n(more) != 0 ? '$text (+${_n(more)} more)' : text;
  }

  /// The whole summary as plain text, as the web builds it for copying.
  static String toPlainText(Map summary, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final person = summary['person'] is Map
        ? summary['person'] as Map
        : const {};
    final team = _list(summary['team']);
    final names = <String, ({String name, String role})>{
      for (final m in team)
        _s(m['username']): (
          name: _s(m['name']).isEmpty ? _s(m['username']) : _s(m['name']),
          role: _roles(m).join(', '),
        ),
      if (_s(person['username']).isNotEmpty)
        _s(person['username']): (
          name: _s(person['name']).isEmpty
              ? _s(person['username'])
              : _s(person['name']),
          role: '',
        ),
    };
    String who(Object? u) {
      final e = names[_s(u)];
      final name = e?.name.isNotEmpty == true ? e!.name : _s(u);
      return e != null && e.role.isNotEmpty ? '$name (${e.role})' : name;
    }

    final lines = <String>[];
    final facts = factsLine(summary);
    lines.add(
      '${_s(person['name']).isEmpty ? 'Summary' : _s(person['name'])}'
      '${facts.isEmpty ? '' : ', $facts'}',
    );
    lines.add(headline(summary, at));
    if (team.isNotEmpty) {
      lines.add(
        'Team: ${team.map((m) {
          final roles = _roles(m);
          return '${_s(m['name'])}${roles.isEmpty ? '' : ' (${roles.join(', ')})'}';
        }).join(', ')}',
      );
    }
    final latest = _list(summary['latest']);
    if (latest.isNotEmpty) {
      lines
        ..add('')
        ..add('Where things stand');
      for (final r in latest) {
        final fields = _list(r['fields']);
        final count = _n(r['count']);
        lines.add(
          '- ${_s(r['caption'])}${count > 1 ? ' x$count' : ''} - '
          '${dayLabel(_n(r['ts']), at)} ${timeOf(_n(r['ts']))}, ${who(r['by'])}'
          '${fields.isEmpty ? '' : ': ${_fields(fields, r['more'])}'}',
        );
      }
    }
    // Newest first with ties kept in their order, then read back to front,
    // as the web does.
    final indexed =
        [for (final e in _list(summary['timeline']).indexed) (e.$1, e.$2)]
          ..sort((a, b) {
            final c = _n(b.$2['ts']).compareTo(_n(a.$2['ts']));
            return c != 0 ? c : a.$1.compareTo(b.$1);
          });
    final days = <({String key, String label, List<Map> items})>[];
    for (final (_, it) in indexed) {
      final ts = _n(it['ts']);
      final key = _dayKey(_at(ts));
      var day = days.where((d) => d.key == key).firstOrNull;
      if (day == null) {
        day = (key: key, label: dayLabel(ts, at), items: <Map>[]);
        days.add(day);
      }
      day.items.add(it);
    }
    if (days.isNotEmpty) {
      lines
        ..add('')
        ..add('Timeline');
      for (final d in days.reversed) {
        lines.add(d.label);
        for (final it in d.items.reversed) {
          final time = timeOf(_n(it['ts']));
          if (it['kind'] == 'form') {
            final fields = _list(it['fields']);
            lines.add(
              '  $time ${_s(it['caption'])}'
              '${it['edited'] == true ? ' (edited)' : ''} - ${who(it['by'])}'
              '${fields.isEmpty ? '' : ': ${_fields(fields, it['more'])}'}',
            );
          } else {
            lines.add('  $time ${who(it['by'])}: ${_s(it['text'])}');
          }
        }
      }
    }
    final stats = summary['stats'];
    if (stats is Map && stats['truncated'] == true) {
      lines
        ..add('')
        ..add('Only the most recent entries are included.');
    }
    return lines.join('\n');
  }
}
