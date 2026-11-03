import '../../data/repositories/form_options_repository.dart';

/// The kept lists of `form.options`: the key, how long a list is reused, the
/// two-day limit offline and every rule that drops them. The drop rules run
/// against the real table under an organisation id of their own, removed
/// afterwards.
class CacheVector {
  const CacheVector(this.name, this.isOk, [this.detail = '']);

  final String name;
  final bool isOk;
  final String detail;

  String get line =>
      '${isOk ? 'PASS' : 'FAIL'}  $name'
      '${detail.isEmpty ? '' : '\n  $detail'}';
}

class CacheVectors {
  CacheVectors._();

  static const _org = '__cache_vectors__';
  static const _other = '__cache_vectors_other__';
  static const _user = 'u1';

  static Future<List<CacheVector>> run(FormOptionsRepository repo) async {
    final out = <CacheVector>[];
    void check(String name, bool isOk, [String detail = '']) =>
        out.add(CacheVector(name, isOk, isOk ? '' : detail));

    String key(Map<String, dynamic> v) => FormOptionsRepository.cacheKey(v);
    check(
      'key: same values in another order are one list',
      key({'a': '1', 'b': '2'}) == key({'b': '2', 'a': '1'}),
    );
    check(
      'key: another parent value is another list',
      key({'department': 'Sales'}) != key({'department': 'Ops'}),
    );

    bool fresh(int age, int sec) => FormOptionsRepository.isFresh(0, sec, age);
    check('expiry: cacheSec 60 reused at 59.999 s', fresh(59999, 60));
    check('expiry: cacheSec 60 asked again at 60 s', !fresh(60000, 60));
    check('expiry: cacheSec 0 reused for 5 minutes', fresh(299999, 0));
    check('expiry: cacheSec 0 asked again at 5 minutes', !fresh(300000, 0));

    const day = 24 * 60 * 60 * 1000;
    check(
      'offline: a list of 2 days is still shown',
      FormOptionsRepository.isUsableOffline(0, 2 * day),
    );
    check(
      'offline: older than 2 days is not shown',
      !FormOptionsRepository.isUsableOffline(0, 2 * day + 1),
    );

    try {
      await _clean(repo);
      Future<void> keep(
        String org,
        String user,
        String form,
        String field,
        String k, {
        String rev = 'r1',
      }) => repo.keepChoices(
        org,
        user,
        form,
        field,
        k,
        {
          'options': [
            {'value': 'x', 'label': 'X'},
          ],
        },
        etag: 'e1',
        cacheSec: 60,
        rev: rev,
      );
      Future<bool> has(
        String org,
        String user,
        String form,
        String field,
        String k, {
        String rev = 'r1',
      }) async => (await repo.keptFor(org, user, form, field, k, rev)) != null;

      await keep(_org, _user, 'f', 'a', 'k1');
      check(
        'rev: the list is read with the rev it was kept with',
        await has(_org, _user, 'f', 'a', 'k1'),
      );
      check(
        'rev: another rev finds nothing',
        !await has(_org, _user, 'f', 'a', 'k1', rev: 'r2'),
      );
      check(
        'rev: and the old list is gone for good',
        !await has(_org, _user, 'f', 'a', 'k1'),
      );

      await keep(_org, _user, 'f', 'a', 'k1');
      await keep(_org, _user, 'f', 'a', 'k2');
      await keep(_org, _user, 'f', 'b', 'k1');
      await keep(_org, _user, 'g', 'a', 'k1');
      await repo.dropField('f', 'a', org: _org, user: _user);
      check(
        'refused choice: every list of that field goes',
        !await has(_org, _user, 'f', 'a', 'k1') &&
            !await has(_org, _user, 'f', 'a', 'k2'),
      );
      check(
        'refused choice: other fields and forms stay',
        await has(_org, _user, 'f', 'b', 'k1') &&
            await has(_org, _user, 'g', 'a', 'k1'),
      );

      await repo.dropForm('f', org: _org, user: _user);
      check(
        'rev changed: everything of that form goes',
        !await has(_org, _user, 'f', 'b', 'k1'),
      );
      check(
        'rev changed: other forms stay',
        await has(_org, _user, 'g', 'a', 'k1'),
      );

      await keep(_org, 'u2', 'g', 'a', 'k1');
      await keep(_other, _user, 'g', 'a', 'k1');
      await repo.clearOrg(org: _org);
      check(
        'options_changed: every list of the organisation goes',
        !await has(_org, _user, 'g', 'a', 'k1') &&
            !await has(_org, 'u2', 'g', 'a', 'k1'),
      );
      check(
        'options_changed: another organisation stays',
        await has(_other, _user, 'g', 'a', 'k1'),
      );

      await keep(_org, _user, 'g', 'a', 'k1');
      await keep(_org, 'u2', 'g', 'a', 'k1');
      await repo.clearScope(_org, _user);
      check(
        'organisation change: that person\'s lists go',
        !await has(_org, _user, 'g', 'a', 'k1'),
      );
      check(
        'organisation change: another person\'s stay',
        await has(_org, 'u2', 'g', 'a', 'k1'),
      );
    } on Object catch (e) {
      check('the table could be used', false, '$e');
    } finally {
      await _clean(repo);
    }
    return out;
  }

  static Future<void> _clean(FormOptionsRepository repo) async {
    await repo.clearOrg(org: _org);
    await repo.clearOrg(org: _other);
  }
}
