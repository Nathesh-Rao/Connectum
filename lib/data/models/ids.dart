String idText(Object? value) => value == null ? '' : value.toString();

int? idNumber(Object? value) => int.tryParse(idText(value));

int intOf(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(idText(value)) ?? 0;
}
