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

/// A designation an employee may pick (`designationRules[]`): for the whole
/// organisation or tied to some branches.
class JoinDesignation {
  const JoinDesignation({
    required this.name,
    this.isAcrossOrg = false,
    this.branches = const [],
  });

  final String name;
  final bool isAcrossOrg;
  final List<String> branches;
}

/// What a joining person chooses from: the categories, the partner
/// organisations, the details each category asks for and what an employee
/// picks (branch, department, designation).
class JoinPage {
  const JoinPage({
    this.categories = const [],
    this.affiliates = const [],
    this.requiredFields = const {},
    this.branches = const [],
    this.departments = const [],
    this.designations = const [],
    this.isCodeRequired = false,
  });

  final List<String> categories;
  final List<JoinAffiliate> affiliates;
  final Map<String, List<String>> requiredFields;
  final List<String> branches;
  final List<String> departments;
  final List<JoinDesignation> designations;

  /// `employeeSignup.codeRequired`: an employee must have a code.
  final bool isCodeRequired;

  /// The designations a person of [branch] can hold: those for the whole
  /// organisation, those tied to no branch and those tied to [branch].
  List<String> designationsFor(String branch) => [
    for (final d in designations)
      if (d.isAcrossOrg ||
          d.branches.isEmpty ||
          branch.isEmpty ||
          d.branches.contains(branch))
        d.name,
  ];

  /// [name] as the organisation spells it, or null when it has no such branch.
  String? branchNamed(String? name) {
    final wanted = (name ?? '').trim().toLowerCase();
    if (wanted.isEmpty) return null;
    for (final b in branches) {
      if (b.toLowerCase() == wanted) return b;
    }
    return null;
  }

  static List<String> _names(Object? raw) => [
    for (final e in raw is List ? raw : const [])
      if (idText(e is Map ? e['name'] : e).isNotEmpty)
        idText(e is Map ? e['name'] : e),
  ];

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
    final designations = <JoinDesignation>[];
    final rules = data['designationRules'];
    if (rules is List) {
      for (final d in rules) {
        final name = d is Map ? idText(d['name']) : idText(d);
        if (name.isEmpty) continue;
        designations.add(
          JoinDesignation(
            name: name,
            isAcrossOrg: d is Map && d['acrossOrg'] == true,
            branches: d is Map ? _names(d['branches']) : const [],
          ),
        );
      }
    } else {
      for (final name in _names(data['designations'])) {
        designations.add(JoinDesignation(name: name, isAcrossOrg: true));
      }
    }
    final signup = data['employeeSignup'];
    return JoinPage(
      categories: categories,
      affiliates: affiliates,
      requiredFields: required,
      branches: _names(data['branches']),
      departments: _names(data['departments']),
      designations: designations,
      isCodeRequired: signup is Map && signup['codeRequired'] == true,
    );
  }
}
