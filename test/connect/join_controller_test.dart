import 'package:connectum/core/utils/connect_code.dart';
import 'package:connectum/data/api/api_client.dart';
import 'package:connectum/data/models/connect_card.dart';
import 'package:connectum/data/models/identity_info.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/data/repositories/auth_repository.dart';
import 'package:connectum/data/repositories/session_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/core/routes/deep_link_service.dart';
import 'package:connectum/features/connect/connect_controller.dart';
import 'package:connectum/features/connect/models/join_flow.dart';
import 'package:connectum/features/connect/widgets/join_steps.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

class _Auth extends Fake implements AuthRepository {
  Map<String, dynamic> page = {};
  Object? pageError;
  Object? checkError;
  Map<String, dynamic> checkAnswer = {'ok': true, 'fields': {}};
  Object? joinError;
  final checks = <Map<String, dynamic>>[];
  final joins = <Map<String, dynamic>>[];
  var pageReads = 0;

  @override
  Future<ConnectCard> connectCard(ConnectCode link) async => const ConnectCard(
    code: 'Y2NHGHP6',
    display: 'Y2NH-GHP6',
    name: 'Acme Clinic',
    location: '',
    categories: ['Customer', 'Vendor'],
  );

  @override
  Future<Map<String, dynamic>> publicPage(String id) async {
    pageReads++;
    final e = pageError;
    if (e != null) throw e;
    return page;
  }

  @override
  Future<Map<String, dynamic>> joinCheck(
    String enterprise,
    Map<String, dynamic> fields,
  ) async {
    checks.add({'enterprise': enterprise, ...fields});
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
    joins.add({'enterprise': enterprise, ...fields, 'connectBranch': ?branch});
    final e = joinError;
    if (e != null) throw e;
    return {'joined': true, 'status': 'pending', 'nextStep': 'approval'};
  }

  @override
  Future<IdentityInfo?> refreshMe() async => null;
}

class _Session extends Fake implements SessionRepository {}

class _Links extends Fake implements DeepLinkService {}

const _full = {
  'categories': ['Customer', 'Vendor'],
  'affiliates': [
    {'name': 'Acme', 'category': 'Vendor', 'branches': []},
    {
      'name': 'Twin',
      'category': 'Vendor',
      'branches': ['North', 'South'],
    },
  ],
};

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Auth auth;
  late FakeConnectivity net;
  late ConnectController c;

  Future<void> open([Map<String, dynamic> page = _full]) async {
    auth = _Auth()..page = page;
    net = FakeConnectivity();
    c = ConnectController(
      auth: auth,
      store: SessionStore(),
      session: _Session(),
      connectivity: net,
      links: _Links(),
    );
    c.open(link: ConnectLinkParser.parse('connectum:Y2NHGHP6').value);
    await _settle();
  }

  JoinFlow flow() => c.joinFlow.value!;

  Future<void> toReview({String? affiliate, String? branch}) async {
    c.chooseAssociate();
    c.pickCategory('Customer');
    await c.nextStep();
    if (affiliate != null) c.pickAffiliate(affiliate);
    if (branch != null) c.pickBranch(branch);
    await c.nextStep();
  }

  test('the card is read once and the flow starts on the Associate card', () async {
    await open();
    expect(auth.pageReads, 1);
    expect(flow().step, JoinStep.type);
    expect(flow().steps.length, 4);
  });

  test('no affiliate: checks category, then affiliate step, joins with category only', () async {
    await open();
    await toReview();
    expect(flow().step, JoinStep.review);
    expect(auth.checks, [
      {'enterprise': 'Y2NH-GHP6', 'isEmployee': false, 'category': 'Customer'},
      {'enterprise': 'Y2NH-GHP6', 'isEmployee': false, 'category': 'Customer'},
    ]);
    await c.join();
    expect(auth.joins, [
      {'enterprise': 'Y2NH-GHP6', 'isEmployee': false, 'category': 'Customer'},
    ]);
  });

  test('category and affiliate with branch are sent to check and join', () async {
    await open();
    await toReview(affiliate: 'Twin', branch: 'South');
    expect(auth.checks.last, {
      'enterprise': 'Y2NH-GHP6',
      'isEmployee': false,
      'category': 'Customer',
      'affiliate': 'Twin',
      'affiliateBranch': 'South',
    });
    await c.join();
    expect(auth.joins.single['affiliate'], 'Twin');
    expect(auth.joins.single['affiliateBranch'], 'South');
    expect(auth.joins.single['category'], 'Customer');
  });

  test('a missing branch stops the step with the web text and sends nothing', () async {
    await open();
    c.chooseAssociate();
    c.pickCategory('Customer');
    await c.nextStep();
    c.pickAffiliate('Twin');
    final before = auth.checks.length;
    await c.nextStep();
    expect(c.fieldErrors['affiliateBranch'], 'Choose your branch.');
    expect(flow().step, JoinStep.affiliate);
    expect(auth.checks.length, before);
  });

  test('a missing category stops the first step', () async {
    await open();
    c.chooseAssociate();
    await c.nextStep();
    expect(c.fieldErrors['category'], 'Choose what describes you.');
    expect(auth.checks, isEmpty);
  });

  test('category only organisation (old path): no affiliate step, joins with category', () async {
    await open({
      'categories': ['Customer'],
      'affiliates': [],
    });
    c.chooseAssociate();
    c.pickCategory('Customer');
    await c.nextStep();
    expect(flow().step, JoinStep.review);
    await c.join();
    expect(auth.joins.single, {
      'enterprise': 'Y2NH-GHP6',
      'isEmployee': false,
      'category': 'Customer',
    });
  });

  test('affiliate-only organisation: no category is sent', () async {
    await open({
      'categories': [],
      'affiliates': [
        {'name': 'Acme', 'category': 'Vendor', 'branches': []},
      ],
    });
    c.chooseAssociate();
    expect(flow().step, JoinStep.affiliate);
    await c.nextStep();
    expect(c.fieldErrors['affiliate'], 'Choose your affiliate.');
    c.pickAffiliate('Acme');
    await c.nextStep();
    expect(auth.checks.single.containsKey('category'), isFalse);
    await c.join();
    expect(auth.joins.single, {
      'enterprise': 'Y2NH-GHP6',
      'isEmployee': false,
      'affiliate': 'Acme',
    });
  });

  test('server field errors from the check are shown and the step stays', () async {
    await open();
    auth.checkAnswer = {
      'ok': false,
      'fields': {'affiliate': 'That affiliate organisation is deactivated.'},
    };
    c.chooseAssociate();
    c.pickCategory('Customer');
    auth.checkAnswer = {'ok': true, 'fields': {}};
    await c.nextStep();
    auth.checkAnswer = {
      'ok': false,
      'fields': {'affiliate': 'That affiliate organisation is deactivated.'},
    };
    c.pickAffiliate('Acme');
    await c.nextStep();
    expect(
      c.fieldErrors['affiliate'],
      'That affiliate organisation is deactivated.',
    );
    expect(flow().step, JoinStep.affiliate);
  });

  test('a refused join shows its field message and keeps the review', () async {
    await open();
    await toReview(affiliate: 'Acme');
    auth.joinError = const ApiException(
      'invalid',
      'Unknown affiliate organisation.',
      status: 400,
      details: {
        'fields': {'affiliate': 'Unknown affiliate organisation.'},
      },
    );
    await c.join();
    expect(c.fieldErrors['affiliate'], 'Unknown affiliate organisation.');
    expect(c.joinMessage.value, 'Unknown affiliate organisation.');
    expect(c.isJoining.value, isFalse);
  });

  test('an unreachable check does not block; the join decides', () async {
    await open();
    auth.checkError = const ApiException('network', '');
    c.chooseAssociate();
    c.pickCategory('Customer');
    await c.nextStep();
    expect(flow().step, JoinStep.affiliate);
    expect(c.joinMessage.value, isNotNull);
  });

  test('a rate-limited check goes on without a message', () async {
    await open();
    auth.checkError = const ApiException('rate_limited', '', status: 429);
    c.chooseAssociate();
    c.pickCategory('Customer');
    await c.nextStep();
    expect(flow().step, JoinStep.affiliate);
    expect(c.joinMessage.value, isNull);
  });

  test('a category that needs details the app lacks stops with the old message', () async {
    await open({
      ..._full,
      'onboarding': {
        'Customer': {
          'requiredFields': ['address'],
        },
      },
    });
    c.chooseAssociate();
    c.pickCategory('Customer');
    await c.nextStep();
    expect(flow().step, JoinStep.category);
    expect(
      c.joinMessage.value,
      'Joining as Customer needs more details than the mobile app supports yet.',
    );
    expect(auth.checks, isEmpty);
  });

  test('offline: the page is not read and the notice shows; online it reads', () async {
    await open();
    final reads = auth.pageReads;
    c.joinFlow.value = null;
    net.state.value = AppConnectivity.offline;
    await c.loadJoinPage();
    expect(auth.pageReads, reads);
    expect(c.pageMessage.value, 'Connect to the internet to join.');
    net.state.value = AppConnectivity.online;
    await c.loadJoinPage();
    expect(c.joinFlow.value, isNotNull);
    expect(c.pageMessage.value, isNull);
  });

  test('the page failing shows its message and Try again reads it again', () async {
    await open();
    auth.pageError = const ApiException('network', '');
    c.joinFlow.value = null;
    await c.loadJoinPage();
    expect(c.pageMessage.value, isNotNull);
    expect(c.joinFlow.value, isNull);
    auth.pageError = null;
    await c.loadJoinPage();
    expect(c.joinFlow.value, isNotNull);
    expect(c.pageMessage.value, isNull);
  });

  group('screen at 320 px, text scale 1.5', () {
    Future<void> pump(WidgetTester t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
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
              child: JoinSteps(
                card: c.card.value!,
                controller: c,
              ),
            ),
          ),
        ),
      );
      await t.pump();
    }

    testWidgets('every step draws without overflow and the flow can be tapped', (
      t,
    ) async {
      await t.runAsync(() => open({
        'categories': ['Customer', 'Vendor', 'A very long category name for a small screen'],
        'affiliates': [
          {
            'name': 'A partner organisation with a long name',
            'category': 'Vendor',
            'branches': ['North side branch', 'South side branch'],
          },
        ],
      }));
      await pump(t);
      expect(find.text('Step 1 of 4: Who are you here?'), findsOneWidget);
      expect(find.text("I'm an associate"), findsOneWidget);
      await t.tap(find.text("I'm an associate"));
      await t.pump();
      expect(find.text('Step 2 of 4: What describes you?'), findsOneWidget);
      await t.tap(find.text('Next'));
      await t.pump();
      expect(find.text('Choose what describes you.'), findsOneWidget);
      await t.tap(find.text('Vendor'));
      await t.pump();
      await t.runAsync(() => c.nextStep());
      await t.pump();
      expect(find.text('Step 3 of 4: Your partner organisation'), findsOneWidget);
      expect(find.text(JoinFlow.individual), findsOneWidget);
      expect(find.text('Search partner organisations'), findsOneWidget);
      await t.tap(find.text('A partner organisation with a long name'));
      await t.pump();
      await t.ensureVisible(find.text('Next'));
      await t.tap(find.text('Next'));
      await t.pump();
      expect(find.text('Choose your branch.'), findsOneWidget);
      await t.tap(find.text('South side branch'));
      await t.pump();
      await t.runAsync(() => c.nextStep());
      await t.pump();
      expect(find.text('Step 4 of 4: Check and send'), findsOneWidget);
      expect(find.text('South side branch'), findsOneWidget);
      expect(find.text('Join Acme Clinic'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('typing in the affiliate search narrows the rows, "individual" stays', (
      t,
    ) async {
      await t.runAsync(() => open());
      await pump(t);
      c.chooseAssociate();
      c.pickCategory('Customer');
      await t.runAsync(() => c.nextStep());
      await t.pump();
      expect(find.text('Acme'), findsOneWidget);
      expect(find.text('Twin'), findsOneWidget);
      await t.enterText(find.byType(EditableText), 'tw');
      await t.pump();
      expect(find.text('Acme'), findsNothing);
      expect(find.text('Twin'), findsOneWidget);
      expect(find.text(JoinFlow.individual), findsOneWidget);
      await t.enterText(find.byType(EditableText), 'zzz');
      await t.pump();
      expect(find.textContaining('Nothing matches'), findsOneWidget);
      expect(find.text(JoinFlow.individual), findsOneWidget);
    });

    testWidgets('an organisation with nothing to choose says so', (t) async {
      await t.runAsync(() => open({'categories': [], 'affiliates': []}));
      await pump(t);
      expect(
        find.text("This enterprise isn't open for joining from the app yet."),
        findsOneWidget,
      );
    });

    testWidgets('a page that failed shows the error and Try again', (t) async {
      auth = _Auth()..pageError = const ApiException('network', '');
      net = FakeConnectivity();
      c = ConnectController(
        auth: auth,
        store: SessionStore(),
        session: _Session(),
        connectivity: net,
        links: _Links(),
      );
      await t.runAsync(() async {
        c.open(link: ConnectLinkParser.parse('connectum:Y2NHGHP6').value);
        await _settle();
      });
      await pump(t);
      expect(find.text('Try again'), findsOneWidget);
      expect(
        find.text("Can't reach the server. Check your connection and try again."),
        findsOneWidget,
      );
    });
  });
}
