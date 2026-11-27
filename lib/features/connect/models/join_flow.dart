import '../../../core/data/country_lookup.dart';
import 'package:connectum/data/models/models.dart';
import 'package:connectum/features/authentication/authentication.dart';

enum JoinStep { type, employee, category, affiliate, details, review }

enum JoinKind { employee, associate }

/// The steps of the web's JoinWizard: who you are (Employee or Associate),
/// then per kind an employee code, or a category and an optional affiliate,
/// then the details, then a review. Pure rules: which steps show, what each
/// one checks and what is sent.
class JoinFlow {
  const JoinFlow({
    required this.page,
    this.step = JoinStep.type,
    this.kind,
    this.category = '',
    this.affiliate = '',
    this.affiliateBranch = '',
    this.values = const {},
    this.seed = const {},
  });

  static const chooseCategory = 'Choose what describes you.';
  static const chooseAffiliate = 'Choose your affiliate.';
  static const chooseBranch = 'Choose your branch.';
  static const individual = "No, I'm an individual";
  static const enterName = 'Enter your full name.';
  static const isNeeded = 'This is needed.';
  static const enterCode = 'Enter your employee code.';
  static const enterCodeOrPlace =
      'Enter your employee code, or choose your branch, department and designation.';

  static const genders = ['Female', 'Male', 'Other'];

  /// The details a category can require that the app collects.
  static const requiredKinds = {
    'address',
    'gender',
    'dob',
    'education',
    'skills',
    'branch',
    'department',
  };

  final JoinPage page;
  final JoinStep step;
  final JoinKind? kind;
  final String category;
  final String affiliate;
  final String affiliateBranch;

  /// What was typed or picked on the employee and details steps, by key:
  /// employeeCode, branch, department, designation, name, username, mobile,
  /// mobileIso, country, city, pin, address, gender, dob, education, skills.
  final Map<String, String> values;

  /// The values a fresh choice of kind starts from (the account's name and
  /// username, the scanned branch).
  final Map<String, String> seed;

  String value(String key) => (values[key] ?? '').trim();

  bool get hasCategories => page.categories.isNotEmpty;
  bool get hasAffiliates => page.affiliates.isNotEmpty;

  /// The Associate card shows only when the organisation offers a choice.
  /// The Employee card is always there, as on the web.
  bool get isAssociateOffered => hasCategories || hasAffiliates;

  bool get isEmployee => kind == JoinKind.employee;
  bool get isAssociate => kind == JoinKind.associate;

  /// An employee who typed a code claims the account made for them.
  bool get isClaiming => isEmployee && value('employeeCode').isNotEmpty;

  List<JoinStep> get steps => switch (kind) {
    JoinKind.employee => [
      JoinStep.type,
      JoinStep.employee,
      JoinStep.details,
      JoinStep.review,
    ],
    JoinKind.associate => [
      JoinStep.type,
      if (hasCategories) JoinStep.category,
      if (hasAffiliates) JoinStep.affiliate,
      JoinStep.details,
      JoinStep.review,
    ],
    null => [JoinStep.type],
  };

  int get index => steps.indexOf(step).clamp(0, steps.length - 1);

  /// Before a kind is chosen the web counts four steps.
  int get total => kind == null ? 4 : steps.length;
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

  /// The details the person's own category requires (the web reads the own
  /// category only).
  List<String> get wanted => isAssociate
      ? [
          for (final k in page.requiredFields[category] ?? const <String>[])
            if (requiredKinds.contains(k)) k,
        ]
      : const [];

  List<String> get designations => page.designationsFor(value('branch'));

  String get title => switch (step) {
    JoinStep.type => 'Who are you here?',
    JoinStep.employee => 'Your employee code',
    JoinStep.category => 'What describes you?',
    JoinStep.affiliate => 'Your partner organisation',
    JoinStep.details => 'Your details',
    JoinStep.review => 'Check and send',
  };

  JoinFlow copyWith({
    JoinStep? step,
    JoinKind? kind,
    String? category,
    String? affiliate,
    String? affiliateBranch,
    Map<String, String>? values,
  }) => JoinFlow(
    page: page,
    step: step ?? this.step,
    kind: kind ?? this.kind,
    category: category ?? this.category,
    affiliate: affiliate ?? this.affiliate,
    affiliateBranch: affiliateBranch ?? this.affiliateBranch,
    values: values ?? this.values,
    seed: seed,
  );

  JoinFlow _choose(JoinKind next) {
    final fresh = copyWith(
      kind: next,
      category: '',
      affiliate: '',
      affiliateBranch: '',
      values: Map.of(seed),
    );
    return fresh.copyWith(step: fresh.steps[1]);
  }

  JoinFlow chooseAssociate() => _choose(JoinKind.associate);

  JoinFlow chooseEmployee() => _choose(JoinKind.employee);

  JoinFlow withValue(String key, String text) => copyWith(
    values: {
      ...values,
      key: text,
      if (key == 'branch') 'designation': '',
      if (key == 'country') 'city': '',
    },
  );

  JoinFlow pickCategory(String value) => copyWith(category: value);

  JoinFlow pickAffiliate(String value) =>
      copyWith(affiliate: value, affiliateBranch: '');

  JoinFlow pickNoAffiliate() => copyWith(affiliate: '', affiliateBranch: '');

  JoinFlow pickBranch(String value) => copyWith(affiliateBranch: value);

  JoinFlow advance() =>
      copyWith(step: steps[(index + 1).clamp(0, steps.length - 1)]);

  JoinFlow back() =>
      copyWith(step: steps[(index - 1).clamp(0, steps.length - 1)]);

  String get _dial =>
      (CountryLookup.byIso(values['mobileIso']) ??
              CountryLookup.deviceDefault())
          .dial;

  /// The typed mobile number as `+<dial><digits>`; empty when not valid.
  ({String value, String? error}) get mobile =>
      AuthValidators.mobile(values['mobile'] ?? '', _dial, isRequired: false);

  static List<String> skillList(String text) => [
    for (final s in text.split(','))
      if (s.trim().isNotEmpty) s.trim(),
  ];

  /// The fields whose inputs are on [s]; an error for any other key is shown
  /// as a message instead.
  Set<String> fieldKeys(JoinStep s) => switch (s) {
    JoinStep.employee => {
      'employeeCode',
      'branch',
      'department',
      'designation',
    },
    JoinStep.category => {'category'},
    JoinStep.affiliate => {'affiliate', 'affiliateBranch'},
    JoinStep.details => {
      'name',
      'username',
      'mobile',
      if (isAssociate) ...{'country', 'city', 'pin'},
      ...wanted,
    },
    _ => const {},
  };

  /// The step that owns the first of [keys], or null when none does.
  JoinStep? stepOwning(Iterable<String> keys) {
    for (final s in steps) {
      if (s == JoinStep.review || s == JoinStep.type) continue;
      if (keys.any(fieldKeys(s).contains)) return s;
    }
    return null;
  }

  /// What is wrong on the current step, by field name; empty when it may go on.
  Map<String, String> problems() {
    final e = <String, String>{};
    switch (step) {
      case JoinStep.employee:
        final hasCode = value('employeeCode').isNotEmpty;
        if (page.isCodeRequired && !hasCode) e['employeeCode'] = enterCode;
        if (!hasCode &&
            !page.isCodeRequired &&
            !(value('branch').isNotEmpty &&
                value('department').isNotEmpty &&
                value('designation').isNotEmpty)) {
          e['employeeCode'] = enterCodeOrPlace;
        }
      case JoinStep.category:
        if (category.isEmpty) e['category'] = chooseCategory;
      case JoinStep.affiliate:
        if (affiliate.isEmpty) {
          if (!hasCategories) e['affiliate'] = chooseAffiliate;
        } else if (needsBranch && affiliateBranch.isEmpty) {
          e['affiliateBranch'] = chooseBranch;
        }
      case JoinStep.details:
        if (!isClaiming && value('name').isEmpty) e['name'] = enterName;
        final badMobile = mobile.error;
        if (badMobile != null) e['mobile'] = badMobile;
        for (final k in wanted) {
          final empty = k == 'skills'
              ? skillList(value(k)).isEmpty
              : value(k).isEmpty;
          if (empty) e[k] = isNeeded;
        }
      case JoinStep.type:
      case JoinStep.review:
        break;
    }
    return e;
  }

  Map<String, dynamic> _affiliatePart() => {
    if (category.isNotEmpty) 'category': category,
    if (affiliate.isNotEmpty) 'affiliate': affiliate,
    if (affiliate.isNotEmpty && needsBranch) 'affiliateBranch': affiliateBranch,
  };

  Object _wantedValue(String k) =>
      k == 'skills' ? skillList(value(k)) : value(k);

  /// What the current step hands to `POST /join/check`; null when it has
  /// nothing to check. The details step is the final one (`final:true`). The
  /// category's required values go with it: the server's final check reads
  /// them from this body.
  Map<String, dynamic>? checkBody() => switch (step) {
    JoinStep.employee => {
      'isEmployee': true,
      if (value('employeeCode').isNotEmpty)
        'employeeCode': value('employeeCode'),
    },
    JoinStep.category => {'isEmployee': false, 'category': category},
    JoinStep.affiliate => {'isEmployee': false, ..._affiliatePart()},
    JoinStep.details => {
      if (isClaiming) ...{
        'isEmployee': true,
        'employeeCode': value('employeeCode'),
      },
      if (mobile.value.isNotEmpty) 'mobile': mobile.value,
      if (value('username').isNotEmpty) 'username': value('username'),
      'final': true,
      if (isAssociate && category.isNotEmpty) 'category': category,
      for (final k in wanted) k: _wantedValue(k),
    },
    _ => null,
  };

  /// The choices sent with `POST /join`. Without an own category the
  /// affiliate's is used by the server.
  Map<String, dynamic> joinBody() {
    final body = <String, dynamic>{
      if (value('name').isNotEmpty) 'name': value('name'),
      if (mobile.value.isNotEmpty) 'mobile': mobile.value,
      if (value('username').isNotEmpty) 'username': value('username'),
    };
    if (isEmployee) {
      body['isEmployee'] = true;
      if (isClaiming) {
        body['employeeCode'] = value('employeeCode');
      } else {
        body['branch'] = value('branch');
        body['department'] = value('department');
        body['designation'] = value('designation');
      }
      return body;
    }
    body['isEmployee'] = false;
    for (final k in const ['country', 'city', 'pin']) {
      if (value(k).isNotEmpty) body[k] = value(k);
    }
    body.addAll(_affiliatePart());
    for (final k in wanted) {
      if (k == 'skills') {
        body[k] = skillList(value(k));
      } else if (value(k).isNotEmpty) {
        body[k] = value(k);
      }
    }
    return body;
  }
}
