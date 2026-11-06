import 'package:connectum/core/routes/deep_link_service.dart';
import 'package:connectum/core/utils/connect_code.dart';
import 'package:connectum/core/utils/install_referrer.dart';
import 'package:connectum/data/models/connect_card.dart';
import 'package:connectum/data/models/connect_lookup.dart';
import 'package:flutter_test/flutter_test.dart';

ConnectCode? _parse(String raw) => ConnectLinkParser.parse(raw).value;

void main() {
  group('branch in links and scans', () {
    test('organisation https link keeps the branch', () {
      final t = _parse(
        'https://connectum.app/connect/Y2NHGHP6?branch=Head%20office',
      );
      expect(t?.code, 'Y2NHGHP6');
      expect(t?.org, isNull);
      expect(t?.branch, 'Head office');
    });

    test('person link keeps org and branch', () {
      final t = _parse(
        'https://connectum.app/connect/KVZDHDQD?org=Y2NH-GHP6&branch=Madurai',
      );
      expect(t?.isPersonLink, isTrue);
      expect(t?.org, 'Y2NHGHP6');
      expect(t?.branch, 'Madurai');
    });

    test('custom scheme forms keep the branch', () {
      expect(_parse('connectum:Y2NHGHP6?branch=Chennai')?.branch, 'Chennai');
      expect(
        _parse('connectum://connect/Y2NHGHP6?branch=Chennai')?.branch,
        'Chennai',
      );
    });

    test('decoding: %20, plus and accents', () {
      expect(_parse('connectum:Y2NHGHP6?branch=A%20B')?.branch, 'A B');
      expect(_parse('connectum:Y2NHGHP6?branch=A+B')?.branch, 'A B');
      expect(_parse('connectum:Y2NHGHP6?branch=Caf%C3%A9')?.branch, 'Café');
    });

    test('case is kept, ends are trimmed, empty is ignored', () {
      expect(_parse('connectum:Y2NHGHP6?branch=hEAD')?.branch, 'hEAD');
      expect(_parse('connectum:Y2NHGHP6?branch=%20Pune%20')?.branch, 'Pune');
      expect(_parse('connectum:Y2NHGHP6?branch=')?.branch, isNull);
      expect(_parse('connectum:Y2NHGHP6?branch=%20')?.branch, isNull);
      expect(_parse('connectum:Y2NHGHP6')?.branch, isNull);
    });

    test('too long or control characters drop the branch, not the code', () {
      final long = 'x' * 61;
      expect(_parse('connectum:Y2NHGHP6?branch=$long')?.code, 'Y2NHGHP6');
      expect(_parse('connectum:Y2NHGHP6?branch=$long')?.branch, isNull);
      expect(_parse('connectum:Y2NHGHP6?branch=a%00b')?.branch, isNull);
    });

    test('a bare typed code has no branch', () {
      expect(_parse('y2nh-ghp6')?.branch, isNull);
    });

    test('linkText writes a space in the branch as %20, never a plus', () {
      const t = ConnectCode(code: 'Y2NHGHP6', branch: 'Head office');
      expect(t.linkText, contains('branch=Head%20office'));
      expect(t.linkText, isNot(contains('+')));
    });

    test('linkText escapes accents, & and + in the branch', () {
      const t = ConnectCode(code: 'Y2NHGHP6', branch: 'Café & Bar+Co');
      expect(t.linkText, contains('branch=Caf%C3%A9%20%26%20Bar%2BCo'));
      expect(_parse(t.linkText)?.branch, 'Café & Bar+Co');
    });

    test('parsing a link accepts both %20 and + as a space', () {
      expect(
        _parse(
          'https://connectum.app/connect/Y2NHGHP6?branch=Head+office',
        )?.branch,
        'Head office',
      );
      expect(
        _parse(
          'https://connectum.app/connect/Y2NHGHP6?branch=Head%20office',
        )?.branch,
        'Head office',
      );
    });

    test('bare CODE?branch=X, CODE?org=Y&branch=X and CODE?org=Y', () {
      final a = _parse('y2nh-ghp6?branch=Head office');
      expect(a?.code, 'Y2NHGHP6');
      expect(a?.branch, 'Head office');
      final b = _parse('Y2NHGHP6?org=kvzd-hdqd&branch=Head%20office');
      expect(b?.org, 'KVZDHDQD');
      expect(b?.branch, 'Head office');
      final c = _parse('y2nhghp6?org=KVZDHDQD');
      expect(c?.org, 'KVZDHDQD');
      expect(c?.branch, isNull);
    });

    test('bare code with a query still rejects other text', () {
      expect(_parse('hello world?branch=X'), isNull);
      expect(_parse('Y2NH?branch=X'), isNull);
    });

    test('withoutBranch drops only the branch', () {
      const t = ConnectCode(code: 'Y2NHGHP6', org: 'KVZDHDQD', branch: 'A');
      final plain = t.withoutBranch();
      expect(plain.branch, isNull);
      expect(plain.org, 'KVZDHDQD');
    });

    test('linkText round-trips code, org and branch', () {
      for (final branch in [
        'Head office',
        'Café & Co',
        'A+B',
        'Chennai/Anna',
      ]) {
        final first = ConnectCode(
          code: 'KVZDHDQD',
          org: 'Y2NHGHP6',
          branch: branch,
        );
        final again = _parse(first.linkText)!;
        expect(again.code, first.code);
        expect(again.org, first.org);
        expect(again.branch, branch);
        expect(again.linkText, first.linkText);
      }
    });
  });

  group('install referrer', () {
    test('reads connect_branch with code and org', () {
      final t = InstallReferrerParser.parse(
        'connect_code=KVZDHDQD&connect_org=Y2NHGHP6&connect_branch=Head%20office',
      );
      expect(t?.code, 'KVZDHDQD');
      expect(t?.org, 'Y2NHGHP6');
      expect(t?.branch, 'Head office');
    });

    test('organisation code with a branch only', () {
      final t = InstallReferrerParser.parse(
        'connect_code=Y2NHGHP6&connect_branch=Madurai',
      );
      expect(t?.isPersonLink, isFalse);
      expect(t?.branch, 'Madurai');
    });

    test('whole referrer percent-encoded still reads the branch', () {
      final t = InstallReferrerParser.parse(
        'connect_code%3DY2NHGHP6%26connect_branch%3DHead%2520office',
      );
      expect(t?.branch, 'Head office');
    });

    test('empty branch and unknown parameters are ignored', () {
      final t = InstallReferrerParser.parse(
        'utm_source=x&connect_code=Y2NHGHP6&connect_branch=',
      );
      expect(t?.code, 'Y2NHGHP6');
      expect(t?.branch, isNull);
    });

    test('a claim token is not a target', () {
      final invite = InstallReferrerParser.read('connect_claim=abcdefgh1234');
      expect(invite.target, isNull);
      expect(invite.claim, 'abcdefgh1234');
    });
  });

  group('pending target', () {
    test('the stored text parses back to the same target with the branch', () {
      const target = ConnectCode(code: 'Y2NHGHP6', branch: 'Head office');
      final loaded = _parse(target.linkText)!;
      expect(loaded.linkText, target.linkText);
      expect(loaded.branch, 'Head office');
    });

    test('24 hour expiry', () {
      final now = DateTime(2026, 11, 6, 12);
      expect(DeepLinkService.isExpired(null, now), isTrue);
      expect(
        DeepLinkService.isExpired(now.subtract(const Duration(hours: 23)), now),
        isFalse,
      );
      expect(
        DeepLinkService.isExpired(now.subtract(const Duration(hours: 24)), now),
        isTrue,
      );
    });

    test('where a pending person goes next', () {
      expect(
        DeepLinkService.stepFor(isInOrg: false, status: null),
        PendingPersonStep.join,
      );
      expect(
        DeepLinkService.stepFor(isInOrg: false, status: 'pending'),
        PendingPersonStep.wait,
      );
      expect(
        DeepLinkService.stepFor(isInOrg: false, status: 'active'),
        PendingPersonStep.enter,
      );
      expect(
        DeepLinkService.stepFor(isInOrg: false, status: 'rejected'),
        PendingPersonStep.rejected,
      );
    });
  });

  group('card replies', () {
    test('the card reads the branch the server spelled', () {
      final card = ConnectCard.fromJson({
        'enterprise': {
          'name': 'Acme',
          'code': 'Y2NH-GHP6',
          'branch': 'Head Office',
        },
      });
      expect(card.branch, 'Head Office');
    });

    test('no branch, or an empty one, is null', () {
      expect(
        ConnectCard.fromJson({
          'enterprise': {'name': 'Acme', 'code': 'Y2NHGHP6'},
        }).branch,
        isNull,
      );
      expect(
        ConnectCard.fromJson({
          'enterprise': {'name': 'Acme', 'code': 'Y2NHGHP6', 'branch': ''},
        }).branch,
        isNull,
      );
    });

    test('branchUnavailable leaves the card without a branch', () {
      final lookup = ConnectLookup.fromJson({
        'type': 'enterprise',
        'enterprise': {
          'name': 'Acme',
          'code': 'Y2NHGHP6',
          'branchUnavailable': true,
        },
      });
      expect(lookup.card?.branch, isNull);
      expect(lookup.card?.isBranchUnavailable, isTrue);
    });

    test('branchUnavailable at the top level is read too', () {
      final card = ConnectCard.fromJson({
        'branchUnavailable': true,
        'enterprise': {'name': 'Acme', 'code': 'Y2NHGHP6', 'branch': 'Old'},
      });
      expect(card.isBranchUnavailable, isTrue);
      expect(card.branch, isNull);
    });

    test('person card shows the branch, skipping empty parts', () {
      final full = ConnectLookup.fromJson({
        'type': 'person',
        'user': {
          'username': 'asha',
          'designation': 'Manager',
          'department': 'Sales',
          'branch': 'Head office',
        },
      });
      expect(full.person?.summary, '@asha - Manager - Sales - Head office');
      final none = ConnectLookup.fromJson({
        'type': 'person',
        'user': {'username': 'asha', 'branch': null, 'department': ''},
      });
      expect(none.person?.branch, '');
      expect(none.person?.summary, '@asha');
    });
  });
}
