import '../../data/e2e/e2e_models.dart';
import '../../data/e2e/e2e_texts.dart';
import '../security/device_limit_controller.dart';
import '../security/widgets/device_card.dart';

/// Self-test of the device-limit sheet and the sample data behind the debug
/// button. No server: the removal and the registration are stand-ins.
class LimitSheetVectors {
  LimitSheetVectors(this._check);

  final Future<void> Function(String name, Future<String?> Function() body)
  _check;

  static const _day = 24 * 60 * 60 * 1000;

  /// A full list (5 of 5): this phone, one used a minute ago, and three that
  /// nobody has used for weeks or months.
  static List<E2eDevicePublic> sampleDevices() {
    final now = DateTime.now().millisecondsSinceEpoch;
    E2eDevicePublic d(String id, String label, int addedDays, int seenDays) =>
        E2eDevicePublic(
          id: id,
          ecdh: '',
          sign: '',
          label: label,
          ts: now - addedDays * _day,
          seen: now - seenDays * _day,
        );
    return [
      d('sample-this', 'Connectum mobile (Pixel 8)', 1, 0),
      d('sample-chrome', 'Chrome on Mac', 60, 0),
      d('sample-old-pixel', 'Connectum mobile (Pixel 4)', 400, 130),
      d('sample-firefox', 'Firefox on Windows', 200, 45),
      d('sample-ipad', 'Safari on iPad', 300, 9),
    ];
  }

  static DeviceLimitController sample({
    Future<bool> Function(E2eDevicePublic)? remove,
    Future<String?> Function()? retry,
    Duration hold = const Duration(milliseconds: 1500),
  }) {
    final devices = sampleDevices();
    return DeviceLimitController(
      thisDeviceId: 'sample-this',
      maxDevices: devices.length,
      devices: devices,
      hold: hold,
      isOffline: () => false,
      load: () async => devices,
      removeDevice: remove ?? (_) async => true,
      retry: retry ?? () async => null,
    );
  }

  Future<void> run() async {
    await _check('limit sheet: repeated triggers open one sheet', () async {
      final gate = LimitSheetGate();
      final opened = [
        gate.tryOpen('org-a'),
        gate.tryOpen('org-a'),
        gate.tryOpen('org-a'),
      ];
      if (opened.where((o) => o).length != 1) return 'opened $opened';
      gate.closed();
      if (gate.tryOpen('org-a')) return 'opened again after close';
      if (!gate.tryOpen('org-a', isRequested: true)) {
        return 'a requested open was refused';
      }
      if (gate.tryOpen('org-a', isRequested: true)) {
        return 'two sheets at once';
      }
      return null;
    });
    await _check(
      'limit sheet: org switch shows one sheet for that org',
      () async {
        final gate = LimitSheetGate();
        if (!gate.tryOpen('org-a')) return 'first org did not open';
        if (gate.tryOpen('org-b')) return 'second org opened over the first';
        gate.closed();
        if (!gate.tryOpen('org-b')) return 'second org did not open';
        if (gate.tryOpen('org-b')) return 'second org opened twice';
        gate.closed();
        if (gate.tryOpen('org-a')) return 'first org opened twice';
        gate.settled('org-a');
        return gate.tryOpen('org-a')
            ? null
            : 'did not open after the state changed';
      },
    );
    await _check('limit sheet: remove then retry registers', () async {
      final removed = <String>[];
      var tries = 0;
      final c = sample(
        hold: Duration.zero,
        remove: (d) async {
          removed.add(d.id);
          return true;
        },
        retry: () async {
          tries++;
          return null;
        },
      );
      var isClosed = false;
      c.onFinished = () => isClosed = true;
      final stale = c.devices.firstWhere((d) => d.id == 'sample-old-pixel');
      c.ask(stale);
      if (c.step.value != DeviceLimitStep.confirm) return 'no confirmation';
      await c.confirmRemove();
      if (removed.length != 1 || removed.first != stale.id) {
        return 'not removed';
      }
      if (c.devices.length != 4) return 'list not updated';
      if (tries != 1) return 'registration tried $tries times';
      if (c.step.value != DeviceLimitStep.done) return 'not done';
      return isClosed ? null : 'sheet not closed';
    });
    await _check(
      'limit sheet: a refused registration shows the reason',
      () async {
        final c = sample(
          hold: Duration.zero,
          retry: () async => E2eTexts.rateLimited,
        );
        c.ask(c.devices[1]);
        await c.confirmRemove();
        return c.step.value == DeviceLimitStep.failed &&
                c.failure.value == E2eTexts.rateLimited
            ? null
            : 'step ${c.step.value}';
      },
    );
    await _check(
      "limit sheet: this phone's entry has no remove action",
      () async {
        final c = sample();
        final mine = c.devices.firstWhere((d) => c.isThisPhone(d));
        if (c.canRemove(mine)) return 'removable';
        c.ask(mine);
        if (c.step.value != DeviceLimitStep.list) return 'asked to remove it';
        return c.canRemove(c.devices[1]) ? null : 'others not removable';
      },
    );
    await _check('limit sheet: least recently used first', () async {
      final sorted = DeviceFacts.staleFirst(sampleDevices());
      return sorted.first.id == 'sample-old-pixel' &&
              sorted.last.id == 'sample-this'
          ? null
          : 'order ${sorted.map((d) => d.id)}';
    });
    await _check('limit sheet: the web wording for the limit', () async {
      final text = E2eTexts.registrationFailure('limit', '', 10);
      return text == 'At most 10 devices per person: remove one first.' &&
              E2eTexts.registrationFailure('rate_limited', '', 10) ==
                  E2eTexts.rateLimited
          ? null
          : text;
    });
    await _check('limit sheet: relative times', () async {
      final now = DateTime(2026, 11, 5, 12);
      int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;
      final got = [
        E2eTexts.ago(ago(const Duration(seconds: 10)), now),
        E2eTexts.ago(ago(const Duration(minutes: 5)), now),
        E2eTexts.ago(ago(const Duration(hours: 3)), now),
        E2eTexts.ago(ago(const Duration(days: 1)), now),
        E2eTexts.ago(ago(const Duration(days: 20)), now),
        E2eTexts.ago(ago(const Duration(days: 130)), now),
      ];
      const want = [
        'just now',
        '5 minutes ago',
        '3 hours ago',
        'yesterday',
        '2 weeks ago',
        '4 months ago',
      ];
      return got.join('|') == want.join('|') ? null : got.join('|');
    });
  }
}
