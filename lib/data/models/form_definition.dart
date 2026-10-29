import 'dart:convert';

import 'ids.dart';

class FormFieldDef {
  const FormFieldDef({
    required this.name,
    required this.caption,
    required this.type,
    required this.section,
    this.raw = const {},
  });

  final String name;
  final String caption;
  final String type;
  final String section;

  /// The field exactly as the server sent it: the form screen reads its
  /// rules (required, options, min, max, condition...) from here.
  final Map<String, dynamic> raw;

  bool get isRequired => raw['required'] == true;
  bool get isReadOnly => raw['readOnly'] == true;
  bool get isMulti => raw['multi'] == true;
  bool get isMultiline => raw['multiline'] == true;
  Object? get condition => raw['condition'];
  Object? get defaultValue => raw['default'];
  bool get hasCalc => raw['calc'] is Map;

  /// The fixed choices of a list; empty when it takes them from a source.
  List<String> get options => [
    for (final o in (raw['options'] as List? ?? const []))
      if (idText(o).isNotEmpty) idText(o),
  ];

  /// `branches`, `users`, `isource:<name>`...; empty for a list of fixed
  /// choices.
  String get source => raw['source'] is String ? raw['source'] as String : '';

  num? get min => raw['min'] is num ? raw['min'] as num : null;
  num? get max => raw['max'] is num ? raw['max'] as num : null;
  String get minText => idText(raw['min']);
  String get maxText => idText(raw['max']);
}

class FormSectionDef {
  const FormSectionDef({
    required this.name,
    required this.caption,
    required this.isGrid,
    this.condition,
  });

  final String name;
  final String caption;
  final bool isGrid;
  final Object? condition;
}

/// What a form looks like, from `tstruct.get` / `tstruct.user.get` (full) or
/// from the `structures` map of `submissions.list` (captions only, no types
/// and no sections). Parsing never throws: anything unexpected is left out.
class FormDefinition {
  const FormDefinition({
    required this.name,
    required this.caption,
    required this.scope,
    required this.fields,
    required this.sections,
    required this.captions,
    required this.isFull,
    this.raw = const {},
  });

  static const captionsOnlyMarker = 'captionsOnly';

  final String name;
  final String caption;

  /// `user` for a form a person made, `admin` for an admin-managed one.
  final String scope;
  final List<FormFieldDef> fields;
  final List<FormSectionDef> sections;
  final Map<String, String> captions;
  final bool isFull;
  final Map<String, dynamic> raw;

  factory FormDefinition.parse(String name, String scope, String json) {
    try {
      final data = jsonDecode(json);
      if (data is Map) return FormDefinition.fromMap(name, scope, data);
    } on FormatException {
      // Falls through to an empty definition.
    }
    return FormDefinition(
      name: name,
      caption: '',
      scope: scope,
      fields: const [],
      sections: const [],
      captions: const {},
      isFull: false,
    );
  }

  factory FormDefinition.fromMap(String name, String scope, Map data) {
    final rawFields = data['fields'];
    final fields = <FormFieldDef>[];
    final captions = <String, String>{};
    if (rawFields is List) {
      for (final f in rawFields) {
        if (f is! Map) continue;
        final n = idText(f['name']);
        if (n.isEmpty) continue;
        final c = idText(f['caption']);
        fields.add(
          FormFieldDef(
            name: n,
            caption: c.isEmpty ? n : c,
            type: idText(f['type']),
            section: idText(f['section']),
            raw: f.cast<String, dynamic>(),
          ),
        );
        captions[n] = c.isEmpty ? n : c;
      }
    } else if (rawFields is Map) {
      rawFields.forEach((k, v) {
        final c = idText(v);
        if (c.isNotEmpty) captions[idText(k)] = c;
      });
    }
    final sections = <FormSectionDef>[];
    final rawSections = data['sections'];
    if (rawSections is List) {
      for (final s in rawSections) {
        if (s is! Map) continue;
        final n = idText(s['name']);
        if (n.isEmpty) continue;
        final c = idText(s['caption']);
        sections.add(
          FormSectionDef(
            name: n,
            caption: c.isEmpty ? n : c,
            isGrid: s['grid'] == true,
            condition: s['condition'],
          ),
        );
      }
    }
    return FormDefinition(
      name: name,
      caption: idText(data['caption']),
      scope: scope,
      fields: fields,
      sections: sections,
      captions: captions,
      isFull: data[captionsOnlyMarker] != true && fields.isNotEmpty,
      raw: data.cast<String, dynamic>(),
    );
  }

  /// A captions-only definition from a `structures` entry, in the shape that
  /// is stored.
  static String captionsJson(Map structure) => jsonEncode({
    'caption': structure['caption'],
    'fields': structure['fields'],
    captionsOnlyMarker: true,
  });

  /// The sections in the order they are shown, with the fields that belong to
  /// none first (an empty section name).
  List<String> get sectionOrder => [
    if (fields.any((f) => f.section.isEmpty || sectionOf(f.section) == null))
      '',
    for (final s in sections) s.name,
  ];

  /// The fields shown in [section] ('' for the ones that belong to none).
  List<FormFieldDef> fieldsOf(String section) => [
    for (final f in fields)
      if (section.isEmpty
          ? (f.section.isEmpty || sectionOf(f.section) == null)
          : f.section == section)
        f,
  ];

  bool get allowsForward => raw['allowForward'] != false;

  bool isGridSection(String section) =>
      sections.any((s) => s.name == section && s.isGrid);

  FormSectionDef? sectionOf(String name) {
    for (final s in sections) {
      if (s.name == name) return s;
    }
    return null;
  }

  FormFieldDef? fieldOf(String name) {
    for (final f in fields) {
      if (f.name == name) return f;
    }
    return null;
  }

  /// The columns of a grid section: the fields whose section is that name.
  List<FormFieldDef> columnsOf(String section) => [
    for (final f in fields)
      if (f.section == section) f,
  ];

  String? captionOf(String field) => captions[field];
}
