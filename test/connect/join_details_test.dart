import 'package:connectum/core/routes/deep_link_service.dart';
import 'package:connectum/core/utils/connect_code.dart';
import 'package:connectum/data/api/api_client.dart';
import 'package:connectum/data/models/connect_card.dart';
import 'package:connectum/data/models/identity_info.dart';
import 'package:connectum/data/models/join_page.dart';
import 'package:connectum/data/repositories/auth_repository.dart';
import 'package:connectum/data/repositories/session_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/features/connect/connect_controller.dart';
import 'package:connectum/features/connect/models/join_flow.dart';
import 'package:connectum/features/connect/widgets/join_steps.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

class _Auth extends Fake implements AuthRepository {
  Map<String, dynamic> page = {};
  Map<String, dynamic> checkAnswer = {'ok': true, 'fields': {}};
  Object? checkError;
  Object? joinError;
  Map<String, dynamic> joinAnswer = {
    'joined': true,
    'status': 'pending',
    'nextStep': 'approval',
  };
  String? scannedBranch;
  final checks = <Map<String, dynamic>>[];
  final joins = <Map<String, dynamic>>[];

  @override
  Future<ConnectCard> connectCard(ConnectCode link) async => ConnectCard(
    code: 'Y2NHGHP6',
    display: 'Y2NH-GHP6',
    name: 'Acme Clinic',
    location: '',
    categories: const ['Customer'],
    branch: scannedBranch,
  );

  @override
  Future<Map<String, dynamic>> publicPage(String id) async => page;

  @override
  Future<Map<String, dynamic>> joinCheck(
    String enterprise,
    Map<String, dynamic> fields,
  ) async {
    checks.add({...fields});
    final e = checkError;
    if (e != null) throw e;
    return checkAnswer;
  }

  @override
  Future<Map<String, dynamic>> join(
    String enterprise,
    Map<String, dynamic> fields, {
    String? branch,
  }) async {
    joins.add({...fields, 'connectBranch': ?branch});
    final e = joinError;
    if (e != null) throw e;
    return joinAnswer;
  }

  @override
  Future<IdentityInfo?> refreshMe() async => null;

  @override
  Future<List<String>> countries() async => ['India', 'Kenya'];

  @override
  Future<List<String>> cities(String country) async => ['Pune'];
}

class _Session extends Fake implements SessionRepository {}

class _Links extends Fake implements DeepLinkService {}

const _allKinds = [
  'address',
  'gender',
  'dob',
  'education',
  'skills',
  'branch',
  'department',
];

Map<String, dynamic> _page({
  Map<String, dynamic> onboarding = const {},
  bool codeRequired = false,
}) => {
  'categories': ['Customer', 'Vendor'],
  'affiliates': [],
  'branches': ['North', 'South'],
  'departments': ['Sales', 'Ops'],
  'designationRules': [
    {'name': 'Manager', 'acrossOrg': true, 'branches': []},
    {
      'name': 'Clerk',
      'acrossOrg': false,
      'branches': ['North'],
    },
    {'name': 'Guard', 'acrossOrg': false, 'branches': []},
  ],
  'employeeSignup': {'codeRequired': codeRequired},
  'onboarding': {
    'Customer': {'requiredFields': _allKinds},
    'Vendor': {'requiredFields': []},
    ...onboarding,
  },
};

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Auth auth;
  late ConnectController c;

  Future<void> open(
    Map<String, dynamic> page, {
    String? scanned,
    IdentityInfo? identity,
  }) async {
    auth = _Auth()
      ..page = page
      ..scannedBranch = scanned;
    final store = SessionStore();
    if (identity != null) store.identity.value = identity;
    c = ConnectController(
      auth: auth,
      store: store,
      session: _Session(),
      connectivity: FakeConnectivity(),
      links: _Links(),
    );
    c.open(link: ConnectLinkParser.parse('connectum:Y2NHGHP6').value);
    await _settle();
  }

  JoinFlow flow() => c.joinFlow.value!;

  /// Associate, category [cat], to the details step.
  Future<void> toDetails([String cat = 'Customer']) async {
    c.chooseAssociate();
    c.pickCategory(cat);
    await c.nextStep();
  }

  group('details step: every field kind', () {
    test('each required kind is needed, with the web text', () async {
      await open(_page());
      await toDetails();
      expect(flow().step, JoinStep.details);
      expect(flow().wanted, _allKinds);
      await c.nextStep();
      expect(c.fieldErrors['name'], 'Enter your full name.');
      for (final k in _allKinds) {
        expect(c.fieldErrors[k], 'This is needed.', reason: k);
      }
      expect(flow().step, JoinStep.details);
      expect(auth.checks.where((b) => b['final'] == true), isEmpty);
    });

    test('a category with no required fields only needs the name', () async {
      await open(_page());
      await toDetails('Vendor');
      expect(flow().wanted, isEmpty);
      c.setValue('name', 'Ana');
      await c.nextStep();
      expect(flow().step, JoinStep.review);
    });

    test('kinds the app does not know are ignored', () async {
      await open(
        _page(
          onboarding: {
            'Vendor': {
              'requiredFields': ['passport'],
            },
          },
        ),
      );
      await toDetails('Vendor');
      expect(flow().wanted, isEmpty);
    });

    test('skills of only commas are not an answer', () async {
      await open(_page());
      await toDetails();
      c.setValue('skills', ' , ,');
      await c.nextStep();
      expect(c.fieldErrors['skills'], 'This is needed.');
      c.setValue('skills', 'dart, flutter');
      expect(flow().checkBody()!['skills'], ['dart', 'flutter']);
    });

    test(
      'a wrong mobile number stops the step, an empty one does not',
      () async {
        await open(_page());
        await toDetails('Vendor');
        c.setValue('name', 'Ana');
        c.setValue('mobile', '12');
        await c.nextStep();
        expect(c.fieldErrors['mobile'], 'Enter a valid mobile number.');
        c.setValue('mobile', '');
        await c.nextStep();
        expect(flow().step, JoinStep.review);
      },
    );

    test(
      'final check carries final:true, the category and what was typed',
      () async {
        await open(_page());
        await toDetails();
        c.setValue('name', 'Ana');
        c.setValue('username', 'ana_r');
        c.setValue('mobileIso', 'IN');
        c.setValue('mobile', '98860 12345');
        c.setValue('address', '1 High St');
        c.setValue('gender', 'Female');
        c.setValue('dob', '1990-04-05');
        c.setValue('education', 'BSc');
        c.setValue('skills', 'dart, flutter');
        c.setValue('branch', 'North');
        c.setValue('department', 'Sales');
        await c.nextStep();
        expect(flow().step, JoinStep.review);
        expect(auth.checks.last, {
          'mobile': '+919886012345',
          'username': 'ana_r',
          'final': true,
          'category': 'Customer',
          'address': '1 High St',
          'gender': 'Female',
          'dob': '1990-04-05',
          'education': 'BSc',
          'skills': ['dart', 'flutter'],
          'branch': 'North',
          'department': 'Sales',
        });
        await c.join();
        expect(auth.joins.single, {
          'name': 'Ana',
          'mobile': '+919886012345',
          'username': 'ana_r',
          'isEmployee': false,
          'category': 'Customer',
          'address': '1 High St',
          'gender': 'Female',
          'dob': '1990-04-05',
          'education': 'BSc',
          'skills': ['dart', 'flutter'],
          'branch': 'North',
          'department': 'Sales',
        });
      },
    );

    test('country, city and PIN are optional and sent when given', () async {
      await open(_page());
      await toDetails('Vendor');
      c.setValue('name', 'Ana');
      c.pickCountry('India');
      c.setValue('city', 'Pune');
      c.setValue('pin', '411001');
      await c.nextStep();
      await c.join();
      expect(auth.joins.single, {
        'name': 'Ana',
        'isEmployee': false,
        'category': 'Vendor',
        'country': 'India',
        'city': 'Pune',
        'pin': '411001',
      });
    });

    test('final:true is sent on the details check only', () async {
      await open(_page());
      await toDetails('Vendor');
      c.setValue('name', 'Ana');
      await c.nextStep();
      final finals = [for (final b in auth.checks) b['final'] == true];
      expect(finals, [false, true]);
    });

    test('name and username start from the account', () async {
      await open(
        _page(),
        identity: const IdentityInfo(
          token: 't',
          email: 'ana@x.com',
          enterprises: [],
          name: 'Ana Rao',
          username: 'ana_r',
        ),
      );
      c.chooseAssociate();
      expect(flow().value('name'), 'Ana Rao');
      expect(flow().value('username'), 'ana_r');
      expect(c.textFor('name').text, 'Ana Rao');
    });
  });

  group('details step: server answers', () {
    test(
      'a per-field message from the final check shows under its field',
      () async {
        await open(_page());
        await toDetails('Vendor');
        c.setValue('name', 'Ana');
        auth.checkAnswer = {
          'ok': false,
          'fields': {'username': 'That username is taken.'},
        };
        await c.nextStep();
        expect(flow().step, JoinStep.details);
        expect(c.fieldErrors['username'], 'That username is taken.');
        expect(c.joinMessage.value, isNull);
      },
    );

    test(
      'a message for a field with no input here shows as the message',
      () async {
        await open(_page());
        await toDetails('Vendor');
        c.setValue('name', 'Ana');
        auth.checkAnswer = {
          'ok': false,
          'fields': {'category': 'For Vendor these are required: address.'},
        };
        await c.nextStep();
        expect(flow().step, JoinStep.details);
        expect(c.joinMessage.value, 'For Vendor these are required: address.');
      },
    );

    test('typing in a field clears its message', () async {
      await open(_page());
      await toDetails('Vendor');
      c.setValue('name', 'Ana');
      auth.checkAnswer = {
        'ok': false,
        'fields': {'username': 'taken'},
      };
      await c.nextStep();
      c.setValue('username', 'ana2');
      expect(c.fieldErrors['username'], isNull);
    });

    test(
      'a refused join with detail messages goes back to the details',
      () async {
        await open(_page());
        await toDetails('Vendor');
        c.setValue('name', 'Ana');
        await c.nextStep();
        auth.joinError = const ApiException(
          'invalid',
          'That username is taken.',
          status: 400,
          details: {
            'fields': {'username': 'That username is taken.'},
          },
        );
        await c.join();
        expect(flow().step, JoinStep.details);
        expect(c.fieldErrors['username'], 'That username is taken.');
      },
    );

    test('an unreachable check does not block the details', () async {
      await open(_page());
      await toDetails('Vendor');
      c.setValue('name', 'Ana');
      auth.checkError = const ApiException('network', '');
      await c.nextStep();
      expect(flow().step, JoinStep.review);
      expect(c.joinMessage.value, isNotNull);
    });

    test('a rate-limited details check goes on without a message', () async {
      await open(_page());
      await toDetails('Vendor');
      c.setValue('name', 'Ana');
      auth.checkError = const ApiException('rate_limited', '', status: 429);
      await c.nextStep();
      expect(flow().step, JoinStep.review);
      expect(c.joinMessage.value, isNull);
    });
  });

  group('details step: back and forward', () {
    test('what was typed and picked is kept', () async {
      await open(_page());
      await toDetails();
      c.setValue('name', 'Ana');
      c.setValue('address', '1 High St');
      c.setValue('gender', 'Female');
      c.backStep();
      expect(flow().step, JoinStep.category);
      await c.nextStep();
      expect(flow().step, JoinStep.details);
      expect(flow().value('name'), 'Ana');
      expect(flow().value('gender'), 'Female');
      expect(c.textFor('address').text, '1 High St');
    });

    test('choosing the kind again starts the values over', () async {
      await open(_page());
      await toDetails();
      c.setValue('name', 'Ana');
      c.backStep();
      c.backStep();
      expect(flow().step, JoinStep.type);
      c.chooseEmployee();
      expect(flow().value('name'), '');
      expect(c.textFor('name').text, '');
    });
  });

  group('branch-bound category', () {
    final bound = {
      'Vendor': {
        'branchBound': true,
        'requiredFields': ['branch'],
      },
    };

    test('asks for a branch from the list and sends it', () async {
      await open(_page(onboarding: bound));
      await toDetails('Vendor');
      c.setValue('name', 'Ana');
      await c.nextStep();
      expect(c.fieldErrors['branch'], 'This is needed.');
      expect(auth.checks.where((b) => b['final'] == true), isEmpty);
      c.setValue('branch', 'South');
      await c.nextStep();
      expect(auth.checks.last['branch'], 'South');
      expect(auth.checks.last['final'], true);
      await c.join();
      expect(auth.joins.single['branch'], 'South');
    });

    test(
      'the scanned branch is chosen already, spelt as the organisation does',
      () async {
        await open(_page(onboarding: bound), scanned: 'south');
        await toDetails('Vendor');
        expect(flow().value('branch'), 'South');
        c.setValue('name', 'Ana');
        await c.nextStep();
        expect(flow().step, JoinStep.review);
        await c.join();
        expect(auth.joins.single['connectBranch'], 'south');
      },
    );

    test(
      'a scanned branch the organisation does not have is not chosen',
      () async {
        await open(_page(onboarding: bound), scanned: 'Elsewhere');
        expect(flow().value('branch'), '');
      },
    );
  });

  group('employee path', () {
    test(
      'the card is there for every organisation, the Associate card is not',
      () async {
        await open({'categories': [], 'affiliates': []});
        expect(flow().isAssociateOffered, isFalse);
        c.chooseEmployee();
        expect(flow().step, JoinStep.employee);
        expect(flow().total, 4);
      },
    );

    test(
      'without a code needing one: code, or branch, department and designation',
      () async {
        await open(_page());
        c.chooseEmployee();
        await c.nextStep();
        expect(
          c.fieldErrors['employeeCode'],
          'Enter your employee code, or choose your branch, department and designation.',
        );
        expect(auth.checks, isEmpty);
        c.setValue('branch', 'North');
        c.setValue('department', 'Sales');
        await c.nextStep();
        expect(c.fieldErrors['employeeCode'], isNotNull);
        c.setValue('designation', 'Clerk');
        await c.nextStep();
        expect(flow().step, JoinStep.details);
        expect(auth.checks.single, {'isEmployee': true});
      },
    );

    test('a required code stops with its own text', () async {
      await open(_page(codeRequired: true));
      c.chooseEmployee();
      await c.nextStep();
      expect(c.fieldErrors['employeeCode'], 'Enter your employee code.');
    });

    test('designations follow the branch', () async {
      await open(_page());
      c.chooseEmployee();
      expect(flow().designations, ['Manager', 'Clerk', 'Guard']);
      c.setValue('branch', 'South');
      expect(flow().designations, ['Manager', 'Guard']);
      c.setValue('branch', 'North');
      expect(flow().designations, ['Manager', 'Clerk', 'Guard']);
      c.setValue('designation', 'Clerk');
      c.setValue('branch', 'South');
      expect(flow().value('designation'), '');
    });

    test('with a code: checks, claims, sends the code and no place', () async {
      await open(_page());
      c.chooseEmployee();
      c.setValue('employeeCode', ' EMP-1042 ');
      await c.nextStep();
      expect(auth.checks.single, {
        'isEmployee': true,
        'employeeCode': 'EMP-1042',
      });
      expect(flow().step, JoinStep.details);
      expect(flow().isClaiming, isTrue);
      await c.nextStep();
      expect(flow().step, JoinStep.review);
      expect(auth.checks.last, {
        'isEmployee': true,
        'employeeCode': 'EMP-1042',
        'final': true,
      });
      auth.joinAnswer = {
        'joined': true,
        'status': 'active',
        'claimed': true,
        'nextStep': 'enter',
      };
      await c.join();
      expect(auth.joins.single, {
        'isEmployee': true,
        'employeeCode': 'EMP-1042',
      });
      expect(c.outcome.value, ConnectOutcome.joined);
      expect(c.phase.value, ConnectPhase.done);
    });

    test(
      'without a code: sends branch, department, designation and the details',
      () async {
        await open(_page());
        c.chooseEmployee();
        c.setValue('branch', 'North');
        c.setValue('department', 'Sales');
        c.setValue('designation', 'Clerk');
        await c.nextStep();
        c.setValue('name', 'Ana');
        c.setValue('username', 'ana_r');
        await c.nextStep();
        expect(auth.checks.last, {'username': 'ana_r', 'final': true});
        await c.join();
        expect(auth.joins.single, {
          'name': 'Ana',
          'username': 'ana_r',
          'isEmployee': true,
          'branch': 'North',
          'department': 'Sales',
          'designation': 'Clerk',
        });
        expect(c.outcome.value, ConnectOutcome.requestSent);
      },
    );

    test('the name is optional when claiming, needed otherwise', () async {
      await open(_page());
      c.chooseEmployee();
      c.setValue('employeeCode', 'EMP-1');
      await c.nextStep();
      await c.nextStep();
      expect(flow().step, JoinStep.review);
      c.chooseEmployee();
      c.setValue('branch', 'North');
      c.setValue('department', 'Sales');
      c.setValue('designation', 'Manager');
      await c.nextStep();
      await c.nextStep();
      expect(c.fieldErrors['name'], 'Enter your full name.');
    });

    test(
      'a code the server does not know shows under the code field',
      () async {
        await open(_page());
        c.chooseEmployee();
        c.setValue('employeeCode', 'NOPE');
        auth.checkAnswer = {
          'ok': false,
          'fields': {'employeeCode': 'No employee has that code.'},
        };
        await c.nextStep();
        expect(flow().step, JoinStep.employee);
        expect(c.fieldErrors['employeeCode'], 'No employee has that code.');
        expect(c.joinMessage.value, isNull);
      },
    );

    test(
      'a join refused for a missing code goes back to the code step',
      () async {
        await open(_page(codeRequired: true));
        c.chooseEmployee();
        c.setValue('employeeCode', 'EMP-1');
        await c.nextStep();
        await c.nextStep();
        auth.joinError = const ApiException(
          'code_required',
          'Enter your employee code.',
          status: 400,
        );
        await c.join();
        expect(flow().step, JoinStep.employee);
        expect(c.fieldErrors['employeeCode'], 'Enter your employee code.');
      },
    );

    test('an unreachable check does not block the employee step', () async {
      await open(_page());
      c.chooseEmployee();
      c.setValue('employeeCode', 'EMP-1');
      auth.checkError = const ApiException('network', '');
      await c.nextStep();
      expect(flow().step, JoinStep.details);
    });
  });

  group('page parsing', () {
    test(
      'reads branches, departments, designation rules and the code rule',
      () {
        final p = JoinPage.fromJson(_page(codeRequired: true));
        expect(p.branches, ['North', 'South']);
        expect(p.departments, ['Sales', 'Ops']);
        expect(p.designations.length, 3);
        expect(p.isCodeRequired, isTrue);
        expect(p.branchNamed(' north '), 'North');
        expect(p.branchNamed('x'), isNull);
      },
    );

    test('falls back to plain designation names, tolerates bad shapes', () {
      final p = JoinPage.fromJson({
        'designations': ['A', 'B'],
        'branches': 'x',
        'employeeSignup': 3,
      });
      expect(p.designationsFor('any'), ['A', 'B']);
      expect(p.branches, isEmpty);
      expect(p.isCodeRequired, isFalse);
    });
  });

  group('screen at 320 px, text scale 1.5', () {
    Future<void> pump(WidgetTester t, {double keyboard = 0}) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      t.view.viewInsets = FakeViewPadding(bottom: keyboard);
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: JoinSteps(card: c.card.value!, controller: c),
            ),
          ),
        ),
      );
      await t.pump();
    }

    testWidgets('the type step offers both cards', (t) async {
      await t.runAsync(() => open(_page()));
      await pump(t);
      expect(find.text("I'm an employee of Acme Clinic"), findsOneWidget);
      expect(find.text("I'm an associate"), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets(
      'the details step with every field kind draws, and its fields take text',
      (t) async {
        await t.runAsync(() => open(_page()));
        await pump(t);
        await t.runAsync(() async {
          c.chooseAssociate();
          c.pickCategory('Customer');
          await c.nextStep();
        });
        await t.pump();
        expect(find.text('Step 4 of 5: Your details'), findsNothing);
        expect(find.text('Step 3 of 4: Your details'), findsOneWidget);
        for (final label in [
          'Full name',
          'Your username here',
          'Mobile number',
          'Country (optional)',
          'City (optional)',
          'Postal PIN (optional)',
          'Address',
          'Gender',
          'Date of birth',
          'Education',
          'Skills',
          'Branch',
          'Department',
        ]) {
          expect(find.text(label), findsWidgets, reason: label);
        }
        await t.enterText(find.widgetWithText(TextField, '').first, 'Ana');
        await t.pump();
        expect(c.joinFlow.value!.value('name'), 'Ana');
        await t.runAsync(() => c.nextStep());
        await t.pump();
        expect(find.text('This is needed.'), findsWidgets);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('the keyboard does not cover the field being typed in', (
      t,
    ) async {
      await t.runAsync(() => open(_page()));
      await pump(t, keyboard: 300);
      await t.runAsync(() async {
        c.chooseAssociate();
        c.pickCategory('Customer');
        await c.nextStep();
      });
      await t.pump();
      final education = find.widgetWithText(TextField, '').at(7);
      await t.ensureVisible(education);
      await t.tap(education);
      await t.pumpAndSettle();
      final rect = t.getRect(education);
      expect(rect.bottom, lessThanOrEqualTo(640 - 300 + 1));
      expect(t.takeException(), isNull);
    });

    testWidgets('server messages show under their fields without overflow', (
      t,
    ) async {
      await t.runAsync(() => open(_page()));
      await pump(t);
      await t.runAsync(() async {
        c.chooseAssociate();
        c.pickCategory('Vendor');
        await c.nextStep();
        c.setValue('name', 'Ana');
        auth.checkAnswer = {
          'ok': false,
          'fields': {
            'username':
                'That username is already used by someone in this enterprise.',
          },
        };
        await c.nextStep();
      });
      await t.pump();
      expect(
        find.text(
          'That username is already used by someone in this enterprise.',
        ),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('the employee step draws in both modes', (t) async {
      await t.runAsync(() => open(_page()));
      await pump(t);
      c.chooseEmployee();
      await t.pump();
      expect(find.text('Step 2 of 4: Your employee code'), findsOneWidget);
      expect(find.text('Employee code'), findsOneWidget);
      expect(find.text('Designation'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, 'EMP-1');
      await t.pump();
      expect(find.text('Designation'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('a required code hides the place pickers', (t) async {
      await t.runAsync(() => open(_page(codeRequired: true)));
      await pump(t);
      c.chooseEmployee();
      await t.pump();
      expect(find.text('Branch'), findsNothing);
      expect(
        find.text('Your administrator gave you this code.'),
        findsOneWidget,
      );
    });

    testWidgets('the employee review says Activate when claiming', (t) async {
      await t.runAsync(() => open(_page()));
      await pump(t);
      await t.runAsync(() async {
        c.chooseEmployee();
        c.setValue('employeeCode', 'EMP-1');
        await c.nextStep();
        await c.nextStep();
      });
      await t.pump();
      expect(find.text('Activate my account'), findsOneWidget);
      expect(find.text('EMP-1'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
