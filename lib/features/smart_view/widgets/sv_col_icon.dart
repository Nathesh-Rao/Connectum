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
    SvColType.status || SvColType.select => Icons.sell_outlined,
    SvColType.email => Icons.mail_outline,
    SvColType.phone => Icons.phone_outlined,
    SvColType.url => Icons.link,
    SvColType.file => Icons.attach_file,
    SvColType.checkbox => Icons.check_box_outlined,
    SvColType.text || SvColType.unknown => Icons.notes,
  };
}
