import 'dart:async';

import '../core/debug/seed_messages.dart';

/// The other person answers about 1.5 s after a send, so the chat feels alive.
class DemoReplies {
  DemoReplies._();

  static const _lines = [
    'Got it, thanks!',
    'Sounds good to me.',
    'Let me check and get back to you.',
    'Perfect, that works.',
    'Noted. I will follow up shortly.',
  ];
  static int _n = 0;

  static void after(String convId) {
    final from = convId.startsWith('dm:')
        ? convId.substring(3)
        : SeedMessages.of(
                convId,
              ).where((m) => !m.isMine).map((m) => m.sender).firstOrNull ??
              'priya';
    Timer(const Duration(milliseconds: 1500), () {
      SeedMessages.incoming(convId, from, _lines[_n++ % _lines.length]);
    });
  }
}
