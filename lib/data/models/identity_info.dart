import 'ids.dart';

class EnterpriseMembership {
  const EnterpriseMembership({
    required this.enterprise,
    required this.name,
    required this.city,
    required this.category,
    required this.username,
    required this.status,
  });

  final String enterprise;
  final String name;
  final String city;
  final String category;
  final String username;
  final String status;

  bool get isActive => status == 'active';

  factory EnterpriseMembership.fromJson(Map<String, dynamic> j) =>
      EnterpriseMembership(
        enterprise: idText(j['enterprise']),
        name: idText(j['name']),
        city: idText(j['city']),
        category: idText(j['category']),
        username: idText(j['username']),
        status: j['status'] == null ? 'active' : idText(j['status']),
      );

  Map<String, dynamic> toJson() => {
    'enterprise': enterprise,
    'name': name,
    'city': city,
    'category': category,
    'username': username,
    'status': status,
  };
}

/// The account (identity) session: who the person is and which
/// enterprises they belong to. The token is kept apart in secure storage.
class IdentityInfo {
  const IdentityInfo({
    required this.token,
    required this.email,
    required this.enterprises,
    this.expiresTs,
    this.connectumId = '',
    this.name = '',
    this.username = '',
  });

  final String token;
  final int? expiresTs;
  final String email;
  final String connectumId;
  final String name;
  final String username;
  final List<EnterpriseMembership> enterprises;

  bool get isExpired =>
      expiresTs != null && expiresTs! < DateTime.now().millisecondsSinceEpoch;

  IdentityInfo copyWith({
    List<EnterpriseMembership>? enterprises,
    int? expiresTs,
    String? connectumId,
  }) => IdentityInfo(
    token: token,
    email: email,
    enterprises: enterprises ?? this.enterprises,
    expiresTs: expiresTs ?? this.expiresTs,
    connectumId: connectumId ?? this.connectumId,
    name: name,
    username: username,
  );

  static List<EnterpriseMembership> parseEnterprises(Object? raw) =>
      ((raw as List?) ?? [])
          .whereType<Map>()
          .map((e) => EnterpriseMembership.fromJson(e.cast<String, dynamic>()))
          .toList();

  factory IdentityInfo.fromResponse(
    String token,
    Map<String, dynamic> data, {
    String? fallbackEmail,
  }) {
    final identity = ((data['identity'] as Map?) ?? {}).cast<String, dynamic>();
    return IdentityInfo(
      token: token,
      expiresTs: data['expiresTs'] == null ? null : intOf(data['expiresTs']),
      email: idText(identity['email']).isEmpty
          ? (fallbackEmail ?? '')
          : idText(identity['email']),
      connectumId: idText(identity['connectumId']),
      name: idText(identity['name']),
      username: idText(identity['username']),
      enterprises: parseEnterprises(data['enterprises']),
    );
  }

  Map<String, dynamic> toJson() => {
    'expiresTs': expiresTs,
    'email': email,
    'connectumId': connectumId,
    'name': name,
    'username': username,
    'enterprises': enterprises.map((e) => e.toJson()).toList(),
  };

  factory IdentityInfo.fromJson(String token, Map<String, dynamic> j) =>
      IdentityInfo(
        token: token,
        expiresTs: j['expiresTs'] == null ? null : intOf(j['expiresTs']),
        email: idText(j['email']),
        connectumId: idText(j['connectumId']),
        name: idText(j['name']),
        username: idText(j['username']),
        enterprises: parseEnterprises(j['enterprises']),
      );
}
