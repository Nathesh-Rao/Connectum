import 'package:connectum/core/debug/seed_messages.dart';
import 'package:connectum/core/debug/seed_tickets.dart';
import 'package:connectum/data/api/api_client.dart';
import 'package:connectum/data/models/session_info.dart';
import 'package:connectum/data/repositories/auth_repository.dart';
import 'package:connectum/data/repositories/session_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/demo/demo_ai_repository.dart';
import 'package:connectum/demo/demo_auth_repository.dart';
import 'package:connectum/demo/demo_feed_repository.dart';
import 'package:connectum/demo/demo_mode.dart';
import 'package:connectum/demo/demo_replies.dart';
import 'package:connectum/demo/demo_services.dart';
import 'package:connectum/data/ai/ai_models.dart';
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_socket.dart';

class _Session extends Fake implements SessionRepository {
  _Session(this.store);

  @override
  final SessionStore store;

  @override
  Future<void> signIn({
    required String orgId,
    required String userId,
    required String token,
    int? expiresTs,
    String? orgName,
  }) => store.save(SessionInfo(orgId: orgId, userId: userId), token);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DemoSessionStore store;
  late DemoSocketService socket;
  late DemoAuthRepository auth;

  setUp(() {
    Get.reset();
    Get.testMode = true;
    store = DemoSessionStore();
    final api = ApiClient(store);
    socket = Get.put(DemoSocketService(store, DemoConnectivityService(), api));
    auth = DemoAuthRepository(api, store, _Session(store));
  });

  test('any email and code sign in, and entering gives a session', () async {
    final start = await auth.startLogin('someone@example.com');
    expect(start.kind, LoginStartKind.codeSent);
    final identity = await auth.verifyLogin('someone@example.com', '000000');
    expect(identity.enterprises.length, 2);
    expect(store.hasIdentity, isTrue);
    await auth.enter(identity.enterprises.first.enterprise);
    expect(store.hasEnterpriseSession, isTrue);
    expect(store.userId, DemoMode.username);
    expect(socket.isOnline, isTrue);
    await auth.signOutIdentity();
    expect(store.hasIdentity, isFalse);
    await auth.verifyLogin('again@example.com', '123456');
    expect(store.hasIdentity, isTrue);
  });

  test('the notifications cover every category and change locally', () async {
    await auth.verifyLogin('a@b.co', '123456');
    await auth.enter(DemoMode.orgs.first.$2);
    final feed = Get.put(DemoFeedRepository(socket, store, FakeE2e()));
    await feed.refresh();
    expect(
      feed.items.map((i) => i.category).toSet(),
      containsAll([
        'approvals',
        'tickets',
        'tasks',
        'messages',
        'reminders',
        'security',
      ]),
    );
    expect(feed.items.any((i) => i.priority == 'high' && !i.isRead), isTrue);
    final unread = feed.counts.value.unread;
    await feed.setRead(['demo-1'], isRead: true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(feed.counts.value.unread, unread - 1);
    await feed.resolve('demo-3');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(feed.items.firstWhere((i) => i.id == 'demo-3').isResolved, isTrue);
    expect(feed.counts.value.resolved, 2);
  });

  test('a message sent in a chat is added and answered', () {
    fakeAsync((async) {
      final before = SeedMessages.of('dm:priya').length;
      SeedMessages.send('dm:priya', 'See you at the demo');
      DemoReplies.after('dm:priya');
      expect(SeedMessages.of('dm:priya').length, before + 1);
      async.elapse(const Duration(milliseconds: 1600));
      final last = SeedMessages.of('dm:priya').last;
      expect(last.isMine, isFalse);
      expect(last.sender, 'priya');
      async.flushTimers();
    });
  });

  test('a ticket action updates the ticket', () async {
    await SeedTickets.start();
    addTearDown(SeedTickets.stop);
    final repo = TicketRepository(socket, store, FakeConversations());
    final page = await repo.mine(as: 'with');
    expect(page.tickets, isNotEmpty);
    final id = page.tickets.first.id;
    final before = (await repo.get(id)).ticket.values['state'];
    final result = await repo.update({
      'requestId': 'r-1',
      'id': id,
      'action': 'Complete',
    });
    expect(result, isNotNull);
    final after = (await repo.get(id)).ticket.values['state'];
    expect(after, isNot(before));
  });

  test('the AI answers in turn: text, chart, error', () async {
    final ai = DemoAiRepository();
    const request = AiSummaryRequest(
      chatId: 'dm:priya',
      title: 'Priya',
      range: AiRange.everything,
    );
    final first = await ai.summarize(request).last;
    expect(first.text, contains('Summary'));
    final second = await ai.summarize(request).last;
    expect(second.text, contains('```chart'));
    expect(ai.summarize(request).last, throwsA(isA<AiError>()));
  });
}
