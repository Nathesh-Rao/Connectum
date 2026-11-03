import '../forms/temporary_condition_evaluator.dart';

/// One condition against some values, with the answer of the web's
/// `evalCondition` (`chat-app/features/connectumChat/utils/formEngine.js:27`,
/// origin/main) worked out by reading it. [isDocumented] marks an answer taken
/// from `FORM_LOGIC_FOR_MOBILE.md` section 6 rather than from that function.
class ConditionVector {
  const ConditionVector(
    this.name,
    this.condition,
    this.values,
    this.web, {
    this.isDocumented = false,
  });

  final String name;
  final Map<String, dynamic> condition;
  final Map<String, Object?> values;
  final bool web;
  final bool isDocumented;

  bool get temporary =>
      TemporaryConditionEvaluator.matches(condition, (n) => values[n]);

  bool get isSame => temporary == web;
}

/// Where `TemporaryConditionEvaluator` agrees with the web and where it does
/// not. The differences are NOT fixed in Dart: the JS bundle will replace it.
const conditionVectors = <ConditionVector>[
  ConditionVector(
    'eq: same text',
    {'field': 'a', 'op': 'eq', 'value': 'Yes'},
    {'a': 'Yes'},
    true,
  ),
  ConditionVector(
    'eq: numbers as text',
    {'field': 'a', 'op': 'eq', 'value': 5},
    {'a': '5.0'},
    true,
  ),
  ConditionVector(
    'eq: CASE (web is case-sensitive)',
    {'field': 'a', 'op': 'eq', 'value': 'Yes'},
    {'a': 'yes'},
    false,
  ),
  ConditionVector(
    'eq: spaces round the text (web does not trim)',
    {'field': 'a', 'op': 'eq', 'value': 'Yes'},
    {'a': ' Yes '},
    false,
  ),
  ConditionVector(
    'eq: empty value equals empty (web: never)',
    {'field': 'a', 'op': 'eq', 'value': ''},
    {'a': ''},
    false,
  ),
  ConditionVector(
    'ne: CASE',
    {'field': 'a', 'op': 'ne', 'value': 'Yes'},
    {'a': 'yes'},
    true,
  ),
  ConditionVector(
    'ne: empty against a value',
    {'field': 'a', 'op': 'ne', 'value': 'x'},
    {'a': ''},
    true,
  ),
  ConditionVector(
    'toggle: saved text Yes, condition true (doc: counts as Yes)',
    {'field': 'a', 'op': 'eq', 'value': 'Yes'},
    {'a': 'true'},
    true,
    isDocumented: true,
  ),
  ConditionVector(
    'toggle: " ON " counts as Yes (doc)',
    {'field': 'a', 'op': 'eq', 'value': 'Yes'},
    {'a': ' ON '},
    true,
    isDocumented: true,
  ),
  ConditionVector(
    'toggle: condition value "on", saved Yes (doc)',
    {'field': 'a', 'op': 'eq', 'value': 'on'},
    {'a': 'Yes'},
    true,
    isDocumented: true,
  ),
  ConditionVector(
    'gt: numbers as text (10 > 9)',
    {'field': 'a', 'op': 'gt', 'value': 9},
    {'a': '10'},
    true,
  ),
  ConditionVector(
    'gt: empty',
    {'field': 'a', 'op': 'gt', 'value': 1},
    {'a': ''},
    false,
  ),
  ConditionVector(
    'lte: text compare "B" <= "a" (code units)',
    {'field': 'a', 'op': 'lte', 'value': 'a'},
    {'a': 'B'},
    true,
  ),
  ConditionVector(
    'in: number against "5" (web is strict)',
    {
      'field': 'a',
      'op': 'in',
      'value': [5, 6],
    },
    {'a': '5'},
    false,
  ),
  ConditionVector(
    'in: CASE',
    {
      'field': 'a',
      'op': 'in',
      'value': ['Sick', 'Other'],
    },
    {'a': 'sick'},
    false,
  ),
  ConditionVector(
    'in: exact text',
    {
      'field': 'a',
      'op': 'in',
      'value': ['Sick', 'Other'],
    },
    {'a': 'Sick'},
    true,
  ),
  ConditionVector(
    'between: numbers, ends included',
    {
      'field': 'a',
      'op': 'between',
      'value': [1, 5],
    },
    {'a': '5'},
    true,
  ),
  ConditionVector(
    'between: empty',
    {
      'field': 'a',
      'op': 'between',
      'value': [1, 5],
    },
    {'a': ''},
    false,
  ),
  ConditionVector(
    'notempty: spaces only (web: has a value)',
    {'field': 'a', 'op': 'notempty'},
    {'a': '  '},
    true,
  ),
  ConditionVector(
    'notempty: empty list',
    {'field': 'a', 'op': 'notempty'},
    {'a': <String>[]},
    false,
  ),
  ConditionVector(
    'eq on a list: includes',
    {'field': 'a', 'op': 'eq', 'value': 'x'},
    {
      'a': ['x', 'y'],
    },
    true,
  ),
  ConditionVector(
    'eq on a list: CASE',
    {'field': 'a', 'op': 'eq', 'value': 'X'},
    {
      'a': ['x', 'y'],
    },
    false,
  ),
  ConditionVector(
    'all: both hold',
    {
      'all': [
        {'field': 'a', 'op': 'eq', 'value': 'x'},
        {'field': 'b', 'op': 'eq', 'value': 'y'},
      ],
    },
    {'a': 'x', 'b': 'y'},
    true,
  ),
  ConditionVector(
    'all: one fails',
    {
      'all': [
        {'field': 'a', 'op': 'eq', 'value': 'x'},
        {'field': 'b', 'op': 'eq', 'value': 'y'},
      ],
    },
    {'a': 'x', 'b': 'z'},
    false,
  ),
  ConditionVector(
    'any: one holds (sample_condition)',
    {
      'any': [
        {'field': 'kind', 'op': 'eq', 'value': 'Other'},
        {'field': 'kind', 'op': 'eq', 'value': 'Sick'},
      ],
    },
    {'kind': 'Sick'},
    true,
  ),
  ConditionVector(
    'any: none holds',
    {
      'any': [
        {'field': 'kind', 'op': 'eq', 'value': 'Other'},
        {'field': 'kind', 'op': 'eq', 'value': 'Sick'},
      ],
    },
    {'kind': 'Casual'},
    false,
  ),
  ConditionVector(
    'any: empty list (web: some() of nothing is false)',
    {'any': <Object?>[]},
    {},
    false,
  ),
  ConditionVector('all: empty list', {'all': <Object?>[]}, {}, true),
  ConditionVector(
    'unknown operator counts as met',
    {'field': 'a', 'op': 'contains', 'value': 'x'},
    {'a': 'y'},
    true,
  ),
  ConditionVector(
    'no field named (web reads values[undefined])',
    {'op': 'eq', 'value': 'x'},
    {'a': 'x'},
    false,
  ),
];
