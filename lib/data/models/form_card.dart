import 'dart:convert';

import 'form_definition.dart';
import 'form_entry.dart';
import 'form_submission.dart';
import 'ids.dart';
import 'message.dart';

/// A submission as one card or one detail page: where it came from (a form
/// message or a cached submission) does not matter to the widgets.
class FormCardData {
  const FormCardData({
    required this.id,
    required this.caption,
    required this.structure,
    required this.scope,
    required this.by,
    required this.ts,
    required this.entries,
    this.grids = const [],
    this.forwardedBy,
    this.hasResult = false,
    this.status,
    this.canResubmit = false,
  });

  final String id;
  final String caption;
  final String structure;

  /// The form's scope as the data gave it (`user`, `global`, ...); empty when
  /// unknown.
  final String scope;
  final String by;
  final int ts;
  final List<FormEntry> entries;
  final List<FormGrid> grids;
  final String? forwardedBy;
  final bool hasResult;
  final String? status;

  /// A declined submission the approver allowed to be fixed and sent again.
  final bool canResubmit;

  bool get isPending => id.startsWith('temp-');

  /// Saved, but not a record yet: it waits for someone to approve it.
  bool get isAwaitingApproval => (status ?? '').toLowerCase() == 'pending';
  bool get isForwarded => forwardedBy != null;

  /// "Submission #25", or a plain note while it is still waiting to be sent.
  String get label => isPending ? 'Waiting to send' : 'Submission #$id';

  /// The fields a card shows: the grid sections come last as one value each.
  List<FormEntry> get cardEntries => [
    ...entries,
    for (final g in grids)
      if (g.asEntry != null) g.asEntry!,
  ];

  /// Cards that are mine, not forwarded and without a result can be edited,
  /// unless they wait for approval (the server locks them) or were declined
  /// (those are resubmitted instead).
  bool canEdit(String me) =>
      by.toLowerCase() == me.toLowerCase() &&
      !isForwarded &&
      !hasResult &&
      !isPending &&
      !isAwaitingApproval &&
      !canResubmit &&
      (status ?? '').toLowerCase() != 'rejected' &&
      (status ?? '').toLowerCase() != 'approved';

  /// The pencil of a declined card: fix it and send it again.
  bool canFix(String me) =>
      canResubmit && by.toLowerCase() == me.toLowerCase() && !isForwarded;

  /// From a form message: the fields it carries, with a fallback to the stored
  /// submission and the form's captions when it carries none. Null when the
  /// message holds no readable form at all. Grid sections are not in form
  /// messages, so this has none.
  static FormCardData? fromMessage(
    Message m, {
    FormSubmission? submission,
    FormDefinition? definition,
    String? status,
    bool canResubmit = false,
  }) {
    final json = m.formJson;
    if (json == null) return null;
    final Object? form;
    try {
      form = jsonDecode(json);
    } on FormatException {
      return null;
    }
    if (form is! Map) return null;
    final structure = idText(form['structure']);
    final id = idText(form['submissionId']);
    final caption = idText(form['caption']).isNotEmpty
        ? idText(form['caption'])
        : (definition?.caption.isNotEmpty ?? false)
        ? definition!.caption
        : structure.isNotEmpty
        ? structure
        : 'Form';
    final entries = <FormEntry>[];
    final fields = form['fields'];
    if (fields is List) {
      for (final f in fields) {
        if (f is! Map) continue;
        final name = idText(f['name']);
        final label = f['label'];
        final fieldCaption = idText(f['caption']).isNotEmpty
            ? idText(f['caption'])
            : definition?.captionOf(name) ?? FormEntry.humanize(name);
        final entry = FormEntry.parse(
          name,
          fieldCaption,
          label is String && label.trim().isNotEmpty ? label : f['value'],
          type: definition?.fieldOf(name)?.type ?? '',
        );
        if (entry != null) entries.add(entry);
      }
    }
    if (entries.isEmpty && submission != null) {
      entries.addAll(_fromValues(submission.valuesJson, definition).$1);
    }
    return FormCardData(
      id: id,
      caption: caption,
      structure: structure,
      scope: idText(form['scope']),
      by: idText(form['by']).isNotEmpty ? idText(form['by']) : m.sender,
      ts: m.ts,
      entries: entries,
      forwardedBy: idText(form['forwardedBy']).isEmpty
          ? null
          : idText(form['forwardedBy']),
      hasResult: form['result'] != null,
      status: status,
      canResubmit: canResubmit,
    );
  }

  /// From a stored submission, with its grid sections.
  static FormCardData fromSubmission(
    FormSubmission s, {
    FormDefinition? definition,
  }) {
    final (entries, grids) = _fromValues(s.valuesJson, definition);
    final caption = (definition?.caption.isNotEmpty ?? false)
        ? definition!.caption
        : FormEntry.humanize(s.tstruct);
    return FormCardData(
      id: s.submissionId,
      caption: caption,
      structure: s.tstruct,
      scope: definition?.scope ?? '',
      by: s.byUser,
      ts: s.ts,
      entries: entries,
      grids: grids,
      status: (s.status ?? '').isEmpty ? null : s.status,
      canResubmit: s.canResubmit,
    );
  }

  /// Fields in the order the form defines them, then any value the definition
  /// does not know, in the order they came. A list of row objects is a grid.
  static (List<FormEntry>, List<FormGrid>) _fromValues(
    String valuesJson,
    FormDefinition? definition,
  ) {
    Map values = const {};
    try {
      final decoded = jsonDecode(valuesJson);
      if (decoded is Map) values = decoded;
    } on FormatException {
      // No values to show.
    }
    final keys = <String>[
      if (definition != null)
        for (final f in definition.fields)
          if (!definition.isGridSection(f.section) &&
              values.containsKey(f.name))
            f.name,
    ];
    for (final k in values.keys) {
      final key = idText(k);
      if (!keys.contains(key)) keys.add(key);
    }
    final entries = <FormEntry>[];
    final grids = <FormGrid>[];
    for (final key in keys) {
      final raw = values[key];
      if (_isGridValue(raw)) {
        final grid = _grid(key, raw as List, definition);
        if (grid != null) grids.add(grid);
        continue;
      }
      if (definition?.fieldOf(key)?.section case final section?
          when definition!.isGridSection(section)) {
        continue;
      }
      final entry = FormEntry.parse(
        key,
        definition?.captionOf(key) ?? FormEntry.humanize(key),
        raw,
        type: definition?.fieldOf(key)?.type ?? '',
      );
      if (entry != null) entries.add(entry);
    }
    return (entries, grids);
  }

  static bool _isGridValue(Object? v) =>
      v is List && v.isNotEmpty && v.every((e) => e is Map);

  static FormGrid? _grid(String name, List rows, FormDefinition? definition) {
    final defined = definition?.columnsOf(name) ?? const [];
    final names = <String>[
      for (final c in defined) c.name,
      for (final row in rows)
        for (final k in (row as Map).keys)
          if (!defined.any((c) => c.name == idText(k))) idText(k),
    ];
    final columns = names.toSet().toList();
    if (columns.isEmpty) return null;
    final types = {for (final c in defined) c.name: c.type};
    return FormGrid(
      name: name,
      caption: definition?.sectionOf(name)?.caption ?? FormEntry.humanize(name),
      columns: [
        for (final c in columns)
          definition?.captionOf(c) ?? FormEntry.humanize(c),
      ],
      rows: [
        for (final row in rows)
          [
            for (final c in columns)
              FormEntry.parse(
                    c,
                    c,
                    (row as Map)[c],
                    type: types[c] ?? '',
                  )?.text ??
                  '',
          ],
      ],
    );
  }
}
