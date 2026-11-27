import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import '../../../data/smart_view/sv_file.dart';

/// What a card row is about, which picks its icon and tint.
enum InboxFieldKind {
  person(Icons.person_outline_rounded, AppTones.blue),
  date(Icons.calendar_today_outlined, AppTones.teal),
  file(Icons.insert_drive_file_outlined, AppTones.violet),
  number(Icons.tag, AppTones.indigo),
  text(Icons.notes_rounded, AppTones.slate),
  status(Icons.layers_outlined, AppTones.purple),
  tag(Icons.label_outline_rounded, AppTones.indigo),
  link(Icons.link_rounded, AppTones.blue),
  location(Icons.place_outlined, AppTones.teal),
  other(Icons.short_text_rounded, AppTones.slate);

  const InboxFieldKind(this.icon, this.tone);

  final IconData icon;
  final AppTone tone;

  static final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final _isoDateTime = RegExp(r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}');
  static final _number = RegExp(r'^-?\d+([.,]\d+)?$');
  static final _link = RegExp(r'^(https?://|www\.)\S+$', caseSensitive: false);
  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final _user = RegExp(r'^@\w[\w.-]*$');

  /// From the field's type when the structure gives it (`date`, `number`,
  /// `file`...); null when the type says nothing useful.
  static InboxFieldKind? ofType(String? type) {
    final t = (type ?? '').trim().toLowerCase();
    if (t.isEmpty) return null;
    if (t.contains('date') || t == 'slot' || t == 'time') {
      return date;
    }
    if (t.contains('number') || t == 'currency' || t == 'decimal') {
      return number;
    }
    if (t.contains('file') || t == 'attachment' || t == 'upload') return file;
    if (t == 'user' || t == 'person' || t == 'people' || t == 'employee') {
      return person;
    }
    if (t == 'url' || t == 'link' || t == 'email' || t == 'phone') return link;
    if (t == 'location' || t == 'address' || t == 'map') return location;
    if (t == 'status') return status;
    if (t == 'select' || t == 'multiselect' || t == 'radio' || t == 'tag') {
      return tag;
    }
    if (t == 'text' || t == 'textarea' || t == 'longtext') return text;
    return null;
  }

  static final _byName = <(RegExp, InboxFieldKind)>[
    (RegExp(r'file|attach|document|upload|photo|image|receipt|invoice'), file),
    (RegExp(r'date|due|deadline|expir|birth|dob|\bon\b|\bday\b'), date),
    (
      RegExp(
        r'owner|assignee|assigned|requester|requested|raised|manager|approver|'
        r'employee|user|reviewer|contact|person|reporter|\bby\b|\bwho\b',
      ),
      person,
    ),
    (RegExp(r'status|stage|state|step|phase'), status),
    (RegExp(r'url|link|website|email|e-mail|phone|mobile'), link),
    (
      RegExp(r'location|address|city|place|room|site|venue|branch|country'),
      location,
    ),
    (
      RegExp(
        r'amount|cost|price|qty|quantity|count|total|hours|number|\bno\b|'
        r'\bid\b|age|salary|budget|balance|rate',
      ),
      number,
    ),
    (RegExp(r'type|category|kind|tag|label|priority|department|group'), tag),
    (
      RegExp(
        r'description|note|comment|remark|reason|detail|message|summary|title',
      ),
      text,
    ),
  ];

  /// The kind of a row: the field's [type] first, then the value's shape when
  /// it is certain (file ids, an ISO date, a link), then the field name, then
  /// a weaker shape (a number, `@user`, an e-mail); [other] when nothing fits.
  static InboxFieldKind of({
    required String name,
    required String key,
    required Object? raw,
    String? type,
  }) {
    final byType = ofType(type);
    if (byType != null) return byType;
    if (isFileIdList(raw)) return file;
    final v = raw is String ? raw.trim() : '';
    if (_isoDate.hasMatch(v) || _isoDateTime.hasMatch(v)) return date;
    if (_link.hasMatch(v)) return link;
    final words = '${name.toLowerCase()} ${key.toLowerCase()}'.replaceAll(
      RegExp(r'[_-]+'),
      ' ',
    );
    for (final (re, kind) in _byName) {
      if (re.hasMatch(words)) return kind;
    }
    if (raw is num || _number.hasMatch(v)) return number;
    if (_user.hasMatch(v)) return person;
    if (_email.hasMatch(v)) return link;
    if (v.length > 60) return text;
    return other;
  }

  /// A list of 24-hex file ids, nothing else in it.
  static bool isFileIdList(Object? raw) =>
      raw is List &&
      raw.isNotEmpty &&
      raw.every((e) => e is String && SvFile.isFileId(e.trim()));

  /// "2026-11-16" (or with a time) as the app writes dates; null when [v] is
  /// not an ISO date.
  static DateTime? isoDate(String v) {
    final s = v.trim();
    if (!_isoDate.hasMatch(s) && !_isoDateTime.hasMatch(s)) return null;
    return DateTime.tryParse(s);
  }
}
