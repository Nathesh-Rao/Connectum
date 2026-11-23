import 'package:connectum/data/models/ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a fresh cid per attempt: unique, 1-64 chars, allowed charset', () {
    final seen = <String>{};
    final ok = RegExp(r'^[A-Za-z0-9\-_.:;]{1,64}$');
    for (var i = 0; i < 500; i++) {
      final cid = newCid();
      expect(ok.hasMatch(cid), isTrue, reason: cid);
      expect(seen.add(cid), isTrue, reason: 'repeated $cid');
    }
  });
}
