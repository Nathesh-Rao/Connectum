import 'dart:ui';

import 'app_countries.dart';

/// Finds a country by ISO code or by the name the geo endpoint (or a person)
/// uses. Names are compared loosely (case, accents, "the", "of", "&") and a
/// short alias table covers the common differences.
class CountryLookup {
  CountryLookup._();

  static const fallbackIso = 'IN';

  static const _accents = {
    'å': 'a',
    'ä': 'a',
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ã': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'ö': 'o',
    'õ': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
    'ñ': 'n',
  };

  // Name as people or the geo list write it -> ISO, for names that differ
  // from the list's spelling. Keys are normalised when the table is built.
  static const _aliasNames = {
    'Cabo Verde': 'CV',
    'Czech Republic': 'CZ',
    'Democratic Republic of the Congo': 'CD',
    'DR Congo': 'CD',
    'Republic of the Congo': 'CG',
    'Hong Kong': 'HK',
    'Ivory Coast': 'CI',
    'Myanmar': 'MM',
    'Burma': 'MM',
    'Palestine': 'PS',
    'Saint Kitts and Nevis': 'KN',
    'Saint Lucia': 'LC',
    'Saint Vincent and the Grenadines': 'VC',
    'Turkey': 'TR',
    'Turkiye': 'TR',
    'United States of America': 'US',
    'USA': 'US',
    'US': 'US',
    'UK': 'GB',
    'Great Britain': 'GB',
    'England': 'GB',
    'UAE': 'AE',
    'Russian Federation': 'RU',
    'Republic of Korea': 'KR',
    'Viet Nam': 'VN',
    'Swaziland': 'SZ',
    'Macedonia': 'MK',
    'East Timor': 'TL',
    'Vatican': 'VA',
  };

  static String _normalise(String name) {
    final lower = name.toLowerCase();
    final plain = lower.split('').map((c) => _accents[c] ?? c).join();
    return plain
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'\b(the|of)\b'), '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static final _aliases = {
    for (final e in _aliasNames.entries) _normalise(e.key): e.value,
  };

  static final _byName = {for (final c in appCountries) _normalise(c.name): c};

  static AppCountry? byIso(String? iso) {
    if (iso == null) return null;
    final upper = iso.toUpperCase();
    for (final c in appCountries) {
      if (c.iso == upper) return c;
    }
    return null;
  }

  /// Null when the name is empty or unknown.
  static AppCountry? matchName(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final key = _normalise(name);
    return _byName[key] ??
        byIso(_aliases[key]) ??
        byIso(name.length == 2 ? name : null);
  }

  /// The device region if it is in the list, else India.
  static AppCountry deviceDefault() =>
      byIso(PlatformDispatcher.instance.locale.countryCode) ??
      byIso(fallbackIso)!;

  static List<AppCountry> search(String query) {
    final q = query.trim().toLowerCase().replaceAll('+', '');
    if (q.isEmpty) return appCountries;
    final name = _normalise(query);
    return appCountries.where((c) {
      return (name.isNotEmpty && _normalise(c.name).contains(name)) ||
          c.iso.toLowerCase() == q ||
          c.dial.startsWith(q);
    }).toList();
  }
}
