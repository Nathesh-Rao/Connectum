enum QrKind { person, organisation }

/// One branch of the organisation, as `connect.my` lists it (administrators
/// only). Choosing one only changes which payload is drawn.
class QrBranch {
  const QrBranch({
    required this.name,
    required this.payload,
    this.city,
    this.url,
  });

  factory QrBranch.fromJson(Map<String, dynamic> json) => QrBranch(
    name: _text(json['name']),
    city: _optional(json['city']),
    payload: _text(json['payload']),
    url: _optional(json['url']),
  );

  final String name;
  final String? city;
  final String payload;
  final String? url;

  /// `name · city`, or just the name when there is no city.
  String get label => city == null ? name : '$name · $city';
}

/// Everything one QR card shows. [payload] is the server's text, drawn as it
/// is; [url] is null when the server has no public address.
class QrCardData {
  const QrCardData({
    required this.kind,
    required this.name,
    required this.display,
    required this.payload,
    this.organisation,
    this.url,
    this.branch,
  });

  static const fallbackOrganisation = 'Connectum Enterprise';

  final QrKind kind;

  /// The heading: the person's name or the organisation's name.
  final String name;

  /// The organisation's name under a person's name; null when there is none.
  final String? organisation;

  /// The code as XXXX-XXXX.
  final String display;
  final String payload;
  final String? url;

  /// The chosen branch on an organisation card; null is the whole organisation.
  final QrBranch? branch;

  bool get isPerson => kind == QrKind.person;

  /// The line above the code, with `{name}` the highlighted name.
  String get sentence => isPerson
      ? 'Scan to connect with {name} on Connectum'
      : 'Scan to join {name} on Connectum';

  /// What the share sheet gets as a link: the url, else the payload text.
  String get link => url ?? payload;

  String get shareSubject => isPerson ? 'Connect with $name' : 'Join $name';

  String get shareText => isPerson
      ? 'Connect with me on Connectum using code $display: $link'
      : 'Join $name on Connectum using code $display: $link';

  String get fileName {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final short = slug.length > 40 ? slug.substring(0, 40) : slug;
    return 'connectum-qr-${short.isEmpty ? 'code' : short}.png';
  }

  /// The organisation card for one [branch] (null: the whole organisation).
  /// The code and heading stay the organisation's.
  QrCardData withBranch(QrBranch? branch) => branch == null
      ? QrCardData(
          kind: kind,
          name: name,
          organisation: organisation,
          display: display,
          payload: payload,
          url: url,
        )
      : QrCardData(
          kind: kind,
          name: name,
          organisation: organisation,
          display: display,
          payload: branch.payload,
          url: branch.url,
          branch: branch,
        );
}

/// The parsed `connect.my` answer. Either card can be missing; the screen
/// shows only what exists.
class QrCodes {
  const QrCodes({this.person, this.organisation, this.branches = const []});

  factory QrCodes.fromJson(Map<String, dynamic> data) {
    final person = _map(data['person']);
    final enterprise = _map(data['enterprise']);
    final branches = data['branches'];
    return QrCodes(
      person: person == null
          ? null
          : _personCard(person, _optional(enterprise?['name'])),
      organisation: enterprise == null ? null : _organisationCard(enterprise),
      branches: [
        if (branches is List)
          for (final b in branches)
            if (_map(b) case final branch?) QrBranch.fromJson(branch),
      ],
    );
  }

  final QrCardData? person;
  final QrCardData? organisation;

  /// Empty unless the server sent a list.
  final List<QrBranch> branches;

  List<QrKind> get kinds => [
    if (person != null) QrKind.person,
    if (organisation != null) QrKind.organisation,
  ];

  static QrCardData _personCard(
    Map<String, dynamic> json,
    String? organisation,
  ) {
    final name = _text(json['name']);
    return QrCardData(
      kind: QrKind.person,
      name: name.isEmpty ? _text(json['username']) : name,
      organisation: organisation,
      display: _text(json['display']),
      payload: _text(json['payload']),
      url: _optional(json['url']),
    );
  }

  static QrCardData _organisationCard(Map<String, dynamic> json) {
    final name = _text(json['name']);
    return QrCardData(
      kind: QrKind.organisation,
      name: name.isEmpty ? QrCardData.fallbackOrganisation : name,
      display: _text(json['display']),
      payload: _text(json['payload']),
      url: _optional(json['url']),
    );
  }
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : null;

String _text(Object? value) => value is String ? value : '';

String? _optional(Object? value) {
  final text = _text(value);
  return text.isEmpty ? null : text;
}
