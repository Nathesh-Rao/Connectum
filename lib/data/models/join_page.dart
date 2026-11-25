import 'ids.dart';

/// A partner organisation a joining person may name (`affiliates[]` of
/// `GET /api/sd/enterprise/<id>`).
class JoinAffiliate {
  const JoinAffiliate({
    required this.name,
    this.category = '',
    this.branches = const [],
  });

  final String name;
  final String category;
  final List<String> branches;
}

/// What a joining person chooses from: the categories, the partner
/// organisations and the details each category asks for.
class JoinPage {
  const JoinPage({
    this.categories = const [],
    this.affiliates = const [],
    this.requiredFields = const {},
  });

  final List<String> categories;
  final List<JoinAffiliate> affiliates;
  final Map<String, List<String>> requiredFields;

  factory JoinPage.fromJson(Map<String, dynamic> data) {
    final rawCategories = data['categories'];
    final categories = [
      for (final c in rawCategories is List ? rawCategories : const [])
        if (idText(c).isNotEmpty) idText(c),
    ];
    final affiliates = <JoinAffiliate>[];
    final rawAffiliates = data['affiliates'];
    for (final a in rawAffiliates is List ? rawAffiliates : const []) {
      final name = a is Map ? idText(a['name']) : idText(a);
      if (name.isEmpty) continue;
      final rawBranches = a is Map ? a['branches'] : null;
      final branches = [
        for (final b in rawBranches is List ? rawBranches : const [])
          if (idText(b).isNotEmpty) idText(b),
      ];
      affiliates.add(
        JoinAffiliate(
          name: name,
          category: a is Map ? idText(a['category']) : '',
          branches: branches,
        ),
      );
    }
    final required = <String, List<String>>{};
    final onboarding = data['onboarding'];
    if (onboarding is Map) {
      for (final e in onboarding.entries) {
        final v = e.value;
        final list = v is Map ? v['requiredFields'] : null;
        if (list is List && list.isNotEmpty) {
          required['${e.key}'] = [for (final f in list) idText(f)];
        }
      }
    }
    return JoinPage(
      categories: categories,
      affiliates: affiliates,
      requiredFields: required,
    );
  }
}
