import 'dart:typed_data';

import 'package:webcrypto/webcrypto.dart';

/// The random source for [E2eCrypto]. The default draws from the system CSPRNG.
/// [E2eRandom.fixed] replays given values in call order so the self-test can
/// reproduce the vectors byte for byte.
class E2eRandom {
  E2eRandom() : _queue = null;

  E2eRandom.fixed(List<Object> values) : _queue = List.of(values);

  final List<Object>? _queue;

  Uint8List bytes(int length) {
    final queue = _queue;
    if (queue == null) {
      final out = Uint8List(length);
      fillRandomBytes(out);
      return out;
    }
    final next = queue.removeAt(0);
    if (next is! Uint8List || next.length != length) {
      throw StateError('fixed random value does not fit');
    }
    return next;
  }

  /// The fixed ephemeral key (private scalar and public point), or null when
  /// the CSPRNG is used and a fresh key pair should be generated.
  ({Uint8List scalar, Uint8List publicPoint})? takeEphemeral() {
    final queue = _queue;
    if (queue == null) return null;
    final next = queue.removeAt(0);
    if (next is! ({Uint8List scalar, Uint8List publicPoint})) {
      throw StateError('fixed random value does not fit');
    }
    return next;
  }
}
