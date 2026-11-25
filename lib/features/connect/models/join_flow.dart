import '../../../data/models/join_page.dart';

enum JoinStep { type, category, affiliate, review }

/// The associate join steps of the web's JoinWizard: Associate card, then
/// category, then an optional affiliate, then a review. Pure rules: which
/// steps show, what each one checks and what is sent.
class JoinFlow {
  const JoinFlow({
    required this.page,
    this.step = JoinStep.type,
    this.category = '',
    this.affiliate = '',
    this.affiliateBranch = '',
  });

  static const chooseCategory = 'Choose what describes you.';
  static const chooseAffiliate = 'Choose your affiliate.';
  static const chooseBranch = 'Choose your branch.';
  static const individual = "No, I'm an individual";

  final JoinPage page;
  final JoinStep step;
  final String category;
  final String affiliate;
  final String affiliateBranch;

  bool get hasCategories => page.categories.isNotEmpty;
  bool get hasAffiliates => page.affiliates.isNotEmpty;

  /// The Associate card shows only when the organisation offers a choice.
  bool get isOpen => hasCategories || hasAffiliates;

  List<JoinStep> get steps => [
    JoinStep.type,
    if (hasCategories) JoinStep.category,
    if (hasAffiliates) JoinStep.affiliate,
    JoinStep.review,
  ];

  int get index => steps.indexOf(step).clamp(0, steps.length - 1);
  int get total => steps.length;
  bool get isFirst => index == 0;

  JoinAffiliate? get chosenAffiliate {
    for (final a in page.affiliates) {
      if (a.name == affiliate) return a;
    }
    return null;
  }

  List<String> get branches => chosenAffiliate?.branches ?? const [];
  bool get needsBranch => branches.length > 1;

  /// The category the person joins under: their own, else the affiliate's.
  String get effectiveCategory =>
      category.isNotEmpty ? category : (chosenAffiliate?.category ?? '');

  /// Details this category asks for that the app cannot collect yet.
  List<String> get unsupportedFields =>
      page.requiredFields[effectiveCategory] ?? const [];

  String get title => switch (step) {
    JoinStep.type => 'Who are you here?',
    JoinStep.category => 'What describes you?',
    JoinStep.affiliate => 'Your partner organisation',
    JoinStep.review => 'Check and send',
  };

  JoinFlow copyWith({
    JoinStep? step,
    String? category,
    String? affiliate,
    String? affiliateBranch,
  }) => JoinFlow(
    page: page,
    step: step ?? this.step,
    category: category ?? this.category,
    affiliate: affiliate ?? this.affiliate,
    affiliateBranch: affiliateBranch ?? this.affiliateBranch,
  );

  JoinFlow chooseAssociate() => copyWith(
    category: '',
    affiliate: '',
    affiliateBranch: '',
    step: hasCategories ? JoinStep.category : JoinStep.affiliate,
  );

  JoinFlow pickCategory(String value) => copyWith(category: value);

  JoinFlow pickAffiliate(String value) =>
      copyWith(affiliate: value, affiliateBranch: '');

  JoinFlow pickNoAffiliate() => copyWith(affiliate: '', affiliateBranch: '');

  JoinFlow pickBranch(String value) => copyWith(affiliateBranch: value);

  JoinFlow advance() => copyWith(step: steps[(index + 1).clamp(0, total - 1)]);

  JoinFlow back() => copyWith(step: steps[(index - 1).clamp(0, total - 1)]);

  /// What is wrong on the current step, by field name; empty when it may go on.
  Map<String, String> problems() {
    final e = <String, String>{};
    switch (step) {
      case JoinStep.category:
        if (category.isEmpty) e['category'] = chooseCategory;
      case JoinStep.affiliate:
        if (affiliate.isEmpty) {
          if (!hasCategories) e['affiliate'] = chooseAffiliate;
        } else if (needsBranch && affiliateBranch.isEmpty) {
          e['affiliateBranch'] = chooseBranch;
        }
      case JoinStep.type:
      case JoinStep.review:
        break;
    }
    return e;
  }

  /// What the current step hands to `POST /join/check`; null when it has
  /// nothing to check.
  Map<String, dynamic>? checkBody() => switch (step) {
    JoinStep.category => {'isEmployee': false, 'category': category},
    JoinStep.affiliate => {
      'isEmployee': false,
      if (category.isNotEmpty) 'category': category,
      if (affiliate.isNotEmpty) 'affiliate': affiliate,
      if (affiliate.isNotEmpty && needsBranch) 'affiliateBranch': affiliateBranch,
    },
    _ => null,
  };

  /// The choices sent with `POST /join`. Without an own category the
  /// affiliate's is used by the server, as before.
  Map<String, dynamic> joinBody() => {
    'isEmployee': false,
    if (category.isNotEmpty) 'category': category,
    if (affiliate.isNotEmpty) 'affiliate': affiliate,
    if (affiliate.isNotEmpty && needsBranch) 'affiliateBranch': affiliateBranch,
  };
}
