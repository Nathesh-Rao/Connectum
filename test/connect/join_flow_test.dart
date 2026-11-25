import 'package:connectum/data/models/join_page.dart';
import 'package:connectum/features/connect/models/join_flow.dart';
import 'package:flutter_test/flutter_test.dart';

const _acme = JoinAffiliate(name: 'Acme', category: 'Vendor');
const _twin = JoinAffiliate(
  name: 'Twin',
  category: 'Vendor',
  branches: ['North', 'South'],
);
const _solo = JoinAffiliate(name: 'Solo', branches: ['Only']);

JoinPage _page({
  List<String> categories = const ['Customer', 'Vendor'],
  List<JoinAffiliate> affiliates = const [_acme, _twin, _solo],
  Map<String, List<String>> required = const {},
}) => JoinPage(
  categories: categories,
  affiliates: affiliates,
  requiredFields: required,
);

void main() {
  group('which steps show', () {
    test('categories and affiliates: type, category, affiliate, review', () {
      expect(JoinFlow(page: _page()).steps, [
        JoinStep.type,
        JoinStep.category,
        JoinStep.affiliate,
        JoinStep.review,
      ]);
    });

    test('no affiliates: the affiliate step is left out', () {
      final f = JoinFlow(page: _page(affiliates: const []));
      expect(f.steps, [JoinStep.type, JoinStep.category, JoinStep.review]);
      expect(f.total, 3);
    });

    test('no categories: type, affiliate, review', () {
      final f = JoinFlow(page: _page(categories: const []));
      expect(f.steps, [JoinStep.type, JoinStep.affiliate, JoinStep.review]);
    });

    test('the Associate card shows only when there is a choice', () {
      expect(JoinFlow(page: _page()).isOpen, isTrue);
      expect(JoinFlow(page: _page(affiliates: const [])).isOpen, isTrue);
      expect(JoinFlow(page: _page(categories: const [])).isOpen, isTrue);
      expect(
        JoinFlow(
          page: _page(categories: const [], affiliates: const []),
        ).isOpen,
        isFalse,
      );
    });

    test('the Associate card goes to category, or to affiliate without one', () {
      expect(JoinFlow(page: _page()).chooseAssociate().step, JoinStep.category);
      expect(
        JoinFlow(page: _page(categories: const [])).chooseAssociate().step,
        JoinStep.affiliate,
      );
    });

    test('back from the first step stays on it (the view leaves)', () {
      final f = JoinFlow(page: _page());
      expect(f.isFirst, isTrue);
      expect(f.back().step, JoinStep.type);
    });
  });

  group('validation', () {
    JoinFlow at(JoinStep s, {JoinPage? page}) =>
        JoinFlow(page: page ?? _page(), step: s);

    test('category is required', () {
      expect(at(JoinStep.category).problems(), {
        'category': 'Choose what describes you.',
      });
      expect(at(JoinStep.category).pickCategory('Customer').problems(), isEmpty);
    });

    test('with categories an affiliate is optional (an individual)', () {
      expect(at(JoinStep.affiliate).problems(), isEmpty);
    });

    test('without categories an affiliate is required', () {
      final f = at(JoinStep.affiliate, page: _page(categories: const []));
      expect(f.problems(), {'affiliate': 'Choose your affiliate.'});
      expect(f.pickAffiliate('Acme').problems(), isEmpty);
    });

    test('an affiliate with several branches needs one', () {
      final f = at(JoinStep.affiliate).pickAffiliate('Twin');
      expect(f.needsBranch, isTrue);
      expect(f.problems(), {'affiliateBranch': 'Choose your branch.'});
      expect(f.pickBranch('South').problems(), isEmpty);
    });

    test('one or no branch: nothing to choose, shown as NA', () {
      expect(at(JoinStep.affiliate).pickAffiliate('Solo').needsBranch, isFalse);
      expect(at(JoinStep.affiliate).pickAffiliate('Acme').needsBranch, isFalse);
      expect(at(JoinStep.affiliate).pickAffiliate('Solo').problems(), isEmpty);
    });

    test('picking another affiliate clears the branch; none clears both', () {
      final f = at(
        JoinStep.affiliate,
      ).pickAffiliate('Twin').pickBranch('North').pickAffiliate('Acme');
      expect(f.affiliateBranch, '');
      final g = f.pickNoAffiliate();
      expect(g.affiliate, '');
    });
  });

  group('what is sent', () {
    JoinFlow at(JoinStep s) => JoinFlow(page: _page(), step: s);

    test('no affiliate: category only', () {
      final f = at(JoinStep.review).pickCategory('Customer');
      expect(f.joinBody(), {'isEmployee': false, 'category': 'Customer'});
    });

    test('category and affiliate', () {
      final f = at(
        JoinStep.review,
      ).pickCategory('Customer').pickAffiliate('Acme');
      expect(f.joinBody(), {
        'isEmployee': false,
        'category': 'Customer',
        'affiliate': 'Acme',
      });
    });

    test('category, affiliate with several branches: the branch goes too', () {
      final f = at(JoinStep.review)
          .pickCategory('Customer')
          .pickAffiliate('Twin')
          .pickBranch('North');
      expect(f.joinBody(), {
        'isEmployee': false,
        'category': 'Customer',
        'affiliate': 'Twin',
        'affiliateBranch': 'North',
      });
    });

    test('a branch of a single-branch affiliate is not sent', () {
      final f = at(JoinStep.review).pickCategory('Customer').pickAffiliate('Solo');
      expect(f.joinBody().containsKey('affiliateBranch'), isFalse);
    });

    test('affiliate only (organisation with no categories): no category key', () {
      final f = JoinFlow(
        page: _page(categories: const []),
        step: JoinStep.review,
      ).pickAffiliate('Acme');
      expect(f.joinBody(), {'isEmployee': false, 'affiliate': 'Acme'});
      expect(f.effectiveCategory, 'Vendor');
    });

    test('the old path (categories only, no affiliates): as before', () {
      final f = JoinFlow(
        page: _page(affiliates: const []),
        step: JoinStep.review,
      ).pickCategory('Vendor');
      expect(f.joinBody(), {'isEmployee': false, 'category': 'Vendor'});
    });

    test('the category step checks category; the affiliate step the web body', () {
      expect(
        at(JoinStep.category).pickCategory('Vendor').checkBody(),
        {'isEmployee': false, 'category': 'Vendor'},
      );
      expect(at(JoinStep.affiliate).checkBody(), {'isEmployee': false});
      expect(
        at(JoinStep.affiliate)
            .pickCategory('Vendor')
            .pickAffiliate('Twin')
            .pickBranch('South')
            .checkBody(),
        {
          'isEmployee': false,
          'category': 'Vendor',
          'affiliate': 'Twin',
          'affiliateBranch': 'South',
        },
      );
      expect(at(JoinStep.type).checkBody(), isNull);
      expect(at(JoinStep.review).checkBody(), isNull);
    });
  });

  group('details the app cannot collect', () {
    test('required fields of the chosen category (or the affiliate\'s)', () {
      final f = JoinFlow(
        page: _page(required: const {'Vendor': ['address']}),
      );
      expect(f.pickCategory('Customer').unsupportedFields, isEmpty);
      expect(f.pickCategory('Vendor').unsupportedFields, ['address']);
      final g = JoinFlow(
        page: _page(
          categories: const [],
          required: const {'Vendor': ['dob']},
        ),
      ).pickAffiliate('Acme');
      expect(g.unsupportedFields, ['dob']);
    });
  });

  group('JoinPage.fromJson', () {
    test('reads categories, affiliates with branches and required fields', () {
      final p = JoinPage.fromJson({
        'categories': ['A', 'B'],
        'affiliates': [
          {
            'name': 'X',
            'category': 'A',
            'branches': ['b1', 'b2'],
          },
          {'name': 'Y', 'category': null, 'branches': []},
          'Z',
        ],
        'onboarding': {
          'A': {
            'requiredFields': ['address'],
          },
          'B': {'requiredFields': []},
        },
      });
      expect(p.categories, ['A', 'B']);
      expect(p.affiliates.map((a) => a.name), ['X', 'Y', 'Z']);
      expect(p.affiliates.first.branches, ['b1', 'b2']);
      expect(p.requiredFields, {
        'A': ['address'],
      });
    });

    test('tolerates missing or wrong shapes', () {
      final p = JoinPage.fromJson({
        'categories': 'x',
        'affiliates': [1, null, {}],
        'onboarding': 5,
      });
      expect(p.categories, isEmpty);
      expect(p.requiredFields, isEmpty);
    });
  });
}
