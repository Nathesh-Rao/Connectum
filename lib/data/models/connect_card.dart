import 'ids.dart';

/// An organisation's public card (`GET /api/sd/connect/{code}`).
class ConnectCard {
  const ConnectCard({
    required this.code,
    required this.display,
    required this.name,
    required this.location,
    required this.categories,
    this.branch,
    this.isBranchUnavailable = false,
    this.isFromPersonLink = false,
  });

  static const branchUnavailableText =
      'That branch is no longer active. You will join the organisation without a branch label.';

  final String code;
  final String display;
  final String name;
  final String location;
  final List<String> categories;
  final String? branch;

  /// The server dropped the branch from the link (no longer active).
  final bool isBranchUnavailable;
  final bool isFromPersonLink;

  factory ConnectCard.fromJson(Map<String, dynamic> data) {
    final e = ((data['enterprise'] as Map?) ?? {}).cast<String, dynamic>();
    final place = e['location'] is Map
        ? (e['location'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final cityCountry = [
      idText(place['city']),
      idText(place['country']),
    ].where((s) => s.isNotEmpty).join(', ');
    final isUnavailable =
        data['branchUnavailable'] == true || e['branchUnavailable'] == true;
    final branch = isUnavailable ? '' : idText(e['branch']);
    final code = idText(e['code']).replaceAll('-', '').toUpperCase();
    return ConnectCard(
      code: code,
      display: idText(e['display']).isEmpty ? code : idText(e['display']),
      name: idText(e['name']),
      location: cityCountry.isEmpty ? idText(place['address']) : cityCountry,
      categories: ((e['categories'] as List?) ?? []).map(idText).toList(),
      branch: branch.isEmpty ? null : branch,
      isBranchUnavailable: isUnavailable,
      isFromPersonLink: data['fromPersonLink'] == true,
    );
  }
}
