import 'dart:math';

String idText(Object? value) => value == null ? '' : value.toString();

int? idNumber(Object? value) => int.tryParse(idText(value));

int intOf(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(idText(value)) ?? 0;
}

final _random = Random.secure();

/// A client id for one composed message: `m-` plus a UUID v4 (38 characters
/// from `a-f 0-9 -`, inside the server's 1 to 64 letters, digits and `- _ . :`).
String newCid() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return 'm-${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
