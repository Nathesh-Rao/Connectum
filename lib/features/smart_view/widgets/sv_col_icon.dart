import 'package:flutter/material.dart';

import '../../../data/smart_view/sv_columns.dart';

/// The line icon of a field type in a Smart View card.
class SvColIcon {
  SvColIcon._();

  static IconData of(SvColType type) => switch (type) {
    SvColType.date => Icons.calendar_today_outlined,
    SvColType.time => Icons.schedule,
    SvColType.datetime => Icons.edit_calendar_outlined,
    SvColType.number => Icons.tag,
    SvColType.status || SvColType.select => Icons.layers_outlined,
    SvColType.email => Icons.mail_outline,
    SvColType.phone => Icons.phone_outlined,
    SvColType.url => Icons.link,
    SvColType.file => Icons.attach_file,
    SvColType.checkbox => Icons.check_box_outlined,
    SvColType.text || SvColType.unknown => Icons.notes,
  };

  /// The type as a plain word, for [AppSv.toneOfType] and [byKind].
  static String kindOf(SvColType type) => switch (type) {
    SvColType.date => 'date',
    SvColType.time => 'time',
    SvColType.datetime => 'datetime',
    SvColType.number => 'number',
    SvColType.status => 'status',
    SvColType.select => 'select',
    SvColType.email => 'email',
    SvColType.phone => 'phone',
    SvColType.url => 'url',
    SvColType.file => 'file',
    SvColType.checkbox => 'checkbox',
    SvColType.text || SvColType.unknown => 'text',
  };

  static IconData byKind(String kind) => switch (kind) {
    'date' => Icons.calendar_today_outlined,
    'time' => Icons.schedule,
    'datetime' => Icons.edit_calendar_outlined,
    'number' => Icons.tag,
    'status' || 'select' => Icons.layers_outlined,
    'email' => Icons.mail_outline,
    'phone' => Icons.phone_outlined,
    'url' => Icons.link,
    'file' => Icons.attach_file,
    'checkbox' => Icons.check_box_outlined,
    'person' => Icons.person_outline,
    _ => Icons.notes,
  };
}
