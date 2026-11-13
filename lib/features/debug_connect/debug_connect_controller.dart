import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import '../../core/routes/deep_link_service.dart';
import '../../core/utils/connect_code.dart';
import '../../core/utils/install_referrer.dart';
import '../../data/models/connect_lookup.dart';
import '../connect_target/connect_target_controller.dart';
import '../invite_code/invite_code_sheet.dart';

/// Debug only: shows how [ConnectLinkParser] reads a typed or pasted link, and
/// opens the confirm sheet on sample links. Nothing here calls the server.
class DebugConnectController extends GetxController {
  DebugConnectController({required this.links});

  /// (label, referrer, code, org, branch); a null code means "rejected".
  static const referrerVectors = [
    ('Code only', 'connect_code=7K2M9QWX', '7K2M9QWX', null, null),
    (
      'Person: code and org',
      'connect_code=KVZDHDQD&connect_org=7K2M9QWX',
      'KVZDHDQD',
      '7K2M9QWX',
      null,
    ),
    (
      'Branch with %20',
      'connect_code=7K2M9QWX&connect_branch=Main%20Clinic',
      '7K2M9QWX',
      null,
      'Main Clinic',
    ),
    (
      'Branch with +',
      'connect_code=7K2M9QWX&connect_branch=Main+Clinic',
      '7K2M9QWX',
      null,
      'Main Clinic',
    ),
    (
      'Non-ASCII branch',
      'connect_code=7K2M9QWX&connect_branch=Caf%C3%A9%20Z%C3%BCrich',
      '7K2M9QWX',
      null,
      'Café Zürich',
    ),
    (
      'Unknown parameters ignored',
      'utm_source=google-play&connect_code=7K2M9QWX&utm_medium=organic',
      '7K2M9QWX',
      null,
      null,
    ),
    (
      'Encoded once more',
      'connect_code%3D7K2M9QWX%26connect_org%3DKVZDHDQD',
      '7K2M9QWX',
      'KVZDHDQD',
      null,
    ),
    (
      'Branch with spaces, umlauts and &',
      'connect_code=7K2M9QWX&connect_org=KVZDHDQD&connect_branch=Z%C3%BCrich%20S%C3%BCd%20%26%20Co',
      '7K2M9QWX',
      'KVZDHDQD',
      'Zürich Süd & Co',
    ),
    ('Garbage', '%%%=&&??', null, null, null),
    ('Lowercase code', 'connect_code=7k2m9qwx', '7K2M9QWX', null, null),
    ('Bad code', 'connect_code=7K2M9QW', null, null, null),
    ('Letter U in code', 'connect_code=7K2M9QWU', null, null, null),
    ('No connect_code', 'utm_source=google-play', null, null, null),
    ('Empty', '', null, null, null),
  ];

  /// (label, referrer, claim token); a null claim means "ignored".
  static const claimVectors = [
    ('Claim form', 'connect_claim=aB3dE5gH7jK9mN2p', 'aB3dE5gH7jK9mN2p'),
    (
      'Claim with utm keys',
      'utm_source=x&connect_claim=aB3dE5gH7jK9mN2p',
      'aB3dE5gH7jK9mN2p',
    ),
    (
      'Code wins over claim',
      'connect_code=7K2M9QWX&connect_claim=aB3dE5gH7jK9mN2p',
      null,
    ),
    ('Claim too short', 'connect_claim=abc', null),
  ];

  /// (label, is in the person's organisation, status there, next step).
  static const personVectors = [
    (
      'Person QR, not a member: join, then continue',
      false,
      null,
      PendingPersonStep.join,
    ),
    (
      'Person QR, joined and active: enter, then confirm',
      false,
      'active',
      PendingPersonStep.enter,
    ),
    (
      'Person QR, pending approval: keep, resume after approval',
      false,
      'pending',
      PendingPersonStep.wait,
    ),
    (
      'Person QR, already a member: confirm sheet',
      true,
      'active',
      PendingPersonStep.confirm,
    ),
    (
      'Person QR, rejected: clear and show the notice',
      false,
      'rejected',
      PendingPersonStep.rejected,
    ),
  ];

  /// (label, is a person's link, status in the other organisation, what the
  /// one tap does).
  static const otherOrganisationVectors = [
    (
      'Person QR, member of the other org: one sheet, switch then scan',
      true,
      'active',
      OtherOrganisationPlan.connectAfterSwitch,
    ),
    (
      'Org QR, member of the other org: one tap switch, no scan',
      false,
      'active',
      OtherOrganisationPlan.switchOnly,
    ),
    (
      'Approved while in another org: same sheet, no early switch',
      true,
      'active',
      OtherOrganisationPlan.connectAfterSwitch,
    ),
    ('Not a member: join flow', true, null, OtherOrganisationPlan.join),
    ('Pending: wait', true, 'pending', OtherOrganisationPlan.wait),
  ];

  final DeepLinkService links;

  final input = TextEditingController();
  final result = Rxn<ConnectParse>();
  final referrer = TextEditingController();
  final referrerResult = RxnString();
  final vectorLines = <String>[].obs;

  void read() => result.value = ConnectLinkParser.parse(input.text);

  void openSheet() {
    final parsed = result.value?.value;
    if (parsed != null) links.receiveCode(parsed);
  }

  /// A sample link: read it and open its sheet.
  void useSample(String link) {
    input.text = link;
    read();
    openSheet();
  }

  /// Keeps [link] as the pending target and opens [route] on it.
  void showInvite(String link, String route) {
    final target = ConnectLinkParser.parse(link).value;
    if (target == null) return;
    links.keep(target);
    Get.toNamed(route);
  }

  void openInviteSheet() {
    final context = Get.context;
    if (context != null) InviteCodeSheet.show(context);
  }

  Future<void> runVectors() async {
    vectorLines.assignAll([
      for (final (label, raw, code, org, branch) in referrerVectors)
        _check(label, raw, code, org, branch),
      for (final (label, raw, claim) in claimVectors)
        '${InstallReferrerParser.read(raw).claim == claim ? 'ok' : 'FAIL'}: $label',
      for (final (label, isInOrg, status, expected) in personVectors)
        '${DeepLinkService.stepFor(isInOrg: isInOrg, status: status) == expected ? 'ok' : 'FAIL'}: $label',
      for (final (label, isPerson, status, expected)
          in otherOrganisationVectors)
        '${ConnectTargetController.planFor(isPerson: isPerson, status: status) == expected ? 'ok' : 'FAIL'}: $label',
      ..._switchLines(),
      ..._expiryLines(),
    ]);
    vectorLines.addAll(await _flowLines());
  }

  /// The connect flow's state rules on the real service with a stub scan (no
  /// server). The pending target and the scanner are put back afterwards.
  Future<List<String>> _flowLines() async {
    const raw = 'https://connectum.app/connect/KVZDHDQD?org=7K2M9QWX';
    final target = ConnectLinkParser.parse(raw).value;
    if (target == null) return ['FAIL: sample link'];
    final link = target.linkText;
    final savedPending = links.pending.value;
    final savedScanner = links.scanner;
    final lines = <String>[];
    void check(String label, bool isOk) =>
        lines.add('${isOk ? 'ok' : 'FAIL'}: $label');
    var scans = 0;
    ConnectOutcome connected() => ConnectOutcome(
      link: link,
      person: const ConnectPerson(name: 'Sample', username: 'sample'),
      isNew: true,
    );
    try {
      links.scanner = (_) async {
        scans++;
        return connected();
      };

      links.keep(target);
      links.confirmedLink = link;
      var next = links.closeSheet(isUser: false);
      check(
        'Sheet removed by a reload keeps the target and reopens',
        next == SheetClose.reopen &&
            links.pending.value?.linkText == link &&
            links.confirmedLink == link,
      );

      final held = links.outcome.value = ConnectOutcome(
        link: link,
        failure: ConnectTargetFailure.offline,
      );
      next = links.closeSheet(isUser: false);
      check(
        'Reload while the sheet is open: reopens with the same state',
        next == SheetClose.reopen &&
            links.pending.value?.linkText == link &&
            links.confirmedLink == link &&
            identical(links.outcome.value, held),
      );
      next = SheetClose.reopen;
      for (var i = 0; i < 4 && next == SheetClose.reopen; i++) {
        next = links.closeSheet(isUser: false);
      }
      check('Reopening is capped', next != SheetClose.reopen);

      links.keep(target);
      next = links.closeSheet(isUser: true);
      check(
        'Cancel by the person clears the target',
        next == SheetClose.none &&
            links.pending.value == null &&
            links.confirmedLink == null &&
            links.outcome.value == null,
      );

      links.keep(target);
      links.closeSheet(isUser: true, isKept: true);
      check(
        'Cancel while offline keeps the target',
        links.pending.value != null,
      );

      links.keep(target);
      await links.scan(target);
      check(
        'Final answer clears the target and keeps the answer',
        links.pending.value == null && links.outcome.value?.isFinal == true,
      );
      next = links.closeSheet(isUser: false);
      check(
        'Sheet lost after the answer: a notice, not a reopen',
        next == SheetClose.notice,
      );
      links.outcome.value = null;

      check(
        'Double resume: the second claim is refused',
        links.tryClaimSheet() && !links.tryClaimSheet(),
      );
      links.releaseSheetClaim();

      scans = 0;
      links.keep(target);
      final unconfirmed = await links.scanIfConfirmed(
        target,
        currentOrg: '7K2M9QWX',
      );
      check('No confirm tap: no scan', unconfirmed == null && scans == 0);
      links.confirmedLink = link;
      final wrongOrg = await links.scanIfConfirmed(
        target,
        currentOrg: 'CMYDZ063',
      );
      check(
        'Switch not landed: no scan, target kept',
        wrongOrg == null && scans == 0 && links.pending.value != null,
      );
      final landed = await links.scanIfConfirmed(
        target,
        currentOrg: '7K2M9QWX',
      );
      await links.scanIfConfirmed(target, currentOrg: '7K2M9QWX');
      check(
        'Confirmed, landed: one scan from the service, result kept',
        landed?.isNew == true &&
            scans == 1 &&
            links.pending.value == null &&
            links.confirmedLink == null &&
            links.outcome.value != null,
      );
    } finally {
      links.scanner = savedScanner;
      links.outcome.value = null;
      links.confirmedLink = null;
      if (savedPending != null) {
        links.keep(savedPending);
      } else {
        await links.clear();
      }
    }
    return lines;
  }

  /// The scan after a switch needs the confirm tap and a landing in the
  /// link's organisation: a failed switch (still in the old org) scans nothing.
  static List<String> _switchLines() {
    const link = 'https://connectum.app/connect/KVZDHDQD?org=7K2M9QWX';
    return [
      for (final (label, confirmed, current, expected) in [
        ('Switched, confirmed: scan in the new org', link, '7K2M9QWX', true),
        (
          'Switch failed (still in old org): target kept, no scan',
          link,
          'CMYDZ063',
          false,
        ),
        ('Switch failed (offline, no org): no scan', link, null, false),
        (
          'Landed in the new org without a tap: no scan',
          null,
          '7K2M9QWX',
          false,
        ),
      ])
        '${ConnectTargetController.shouldScanAfterSwitch(confirmedLink: confirmed, link: link, currentOrg: current, linkOrg: '7K2M9QWX') == expected ? 'ok' : 'FAIL'}: $label',
    ];
  }

  static List<String> _expiryLines() {
    final now = DateTime(2026, 1, 2, 12);
    return [
      for (final (label, savedAt, expected) in [
        (
          'Pending 23 h old is kept',
          now.subtract(const Duration(hours: 23)),
          false,
        ),
        (
          'Pending 24 h old expires',
          now.subtract(const Duration(hours: 24)),
          true,
        ),
        ('Pending without a time expires', null, true),
      ])
        '${DeepLinkService.isExpired(savedAt, now) == expected ? 'ok' : 'FAIL'}: $label',
    ];
  }

  static String _check(
    String label,
    String raw,
    String? code,
    String? org,
    String? branch,
  ) {
    final got = InstallReferrerParser.parse(raw);
    final isOk = code == null
        ? got == null
        : got != null &&
              got.code == code &&
              got.org == org &&
              got.branch == branch;
    return '${isOk ? 'ok' : 'FAIL'}: $label';
  }

  /// Runs the typed referrer through the first-start logic: no Play, no
  /// server (a claim token is only shown, never exchanged), and the
  /// once-per-install flag is left alone.
  Future<void> simulateReferrer() async {
    final invite = InstallReferrerParser.read(referrer.text);
    await links.clear();
    await links.startWith(referrer.text, shouldClaim: false);
    final target = links.pending.value;
    final lines = <String>[
      if (target != null) ...[
        'accepted code: ${target.display}',
        'org: ${target.org ?? 'none'}',
        'branch: ${target.branch ?? 'none'}',
      ] else if (invite.claim != null)
        'accepted claim token: the app would call the claim endpoint once'
      else
        'nothing accepted; the scan hint shows: ${links.showScanHint.value}',
      if (target != null && referrer.text.contains('connect_claim'))
        'claim ignored: the code form wins',
      'other keys ignored',
    ];
    referrerResult.value = lines.join('\n');
  }

  void openWelcome() => Get.toNamed(AppRoutes.onboarding);

  void openSignIn() => Get.toNamed(AppRoutes.authentication);

  @override
  void onClose() {
    input.dispose();
    referrer.dispose();
    super.onClose();
  }
}
