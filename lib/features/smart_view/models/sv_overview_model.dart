import 'package:get/get.dart';

import '../../../data/smart_view/models/sv_source.dart';
import '../../../data/smart_view/overview/sv_overview.dart';
import '../../../core/log/app_log.dart';

enum SvCardPhase { loading, ready, error }

/// One structure's card on the Overview.
class SvOverviewCard {
  SvOverviewCard(this.source);

  final SvSource source;
  final phase = SvCardPhase.loading.obs;
  final stats = Rxn<SvOverviewStats>();
}

/// The Overview's data: one card per structure, read one after another
/// through [read] (the repository's gate paces them), kept in memory for the
/// session. [reset] drops everything; a read still in flight is ignored.
class SvOverviewModel {
  SvOverviewModel({
    required this.read,
    DateTime Function()? clock,
    this.isPendingShown = true,
  }) : clock = clock ?? DateTime.now;

  final Future<SvOverviewRead> Function(SvSource source) read;
  final DateTime Function() clock;
  final bool isPendingShown;

  final cards = <SvOverviewCard>[].obs;
  final updatedAt = Rxn<DateTime>();
  final isRunning = false.obs;

  int _gen = 0;

  /// Every card has finished, read or failed.
  bool get isSettled =>
      cards.every((c) => c.phase.value != SvCardPhase.loading);

  bool get hasFailed => cards.any((c) => c.phase.value == SvCardPhase.error);

  /// Some totals are of the newest records only, or a card failed.
  bool get isPartial =>
      hasFailed || cards.any((c) => c.stats.value?.isPartial ?? false);

  /// The pending tile exists when at least one structure has an approval
  /// flow of its own.
  bool get hasPendingSource =>
      isPendingShown && cards.any((c) => c.source.hasStatus);

  int get structures => cards.length;

  int get records => cards.fold(0, (a, c) => a + (c.stats.value?.count ?? 0));

  int get week => cards.fold(0, (a, c) => a + (c.stats.value?.weekCount ?? 0));

  int get pending =>
      cards.fold(0, (a, c) => a + (c.stats.value?.pendingCount ?? 0));

  void reset() {
    _gen++;
    cards.clear();
    updatedAt.value = null;
    isRunning.value = false;
  }

  /// Builds the cards (all loading) and reads them in order, one at a time.
  Future<void> start(List<SvSource> sources) async {
    final gen = ++_gen;
    cards.assignAll([for (final s in sources) SvOverviewCard(s)]);
    updatedAt.value = null;
    isRunning.value = true;
    for (final c in cards.toList()) {
      if (gen != _gen) return;
      await _readOne(c, gen);
    }
    if (gen != _gen) return;
    updatedAt.value = clock();
    isRunning.value = false;
  }

  /// Reads one card again (its Retry).
  Future<void> retry(SvOverviewCard c) async {
    final gen = _gen;
    c.phase.value = SvCardPhase.loading;
    await _readOne(c, gen);
    if (gen == _gen && isSettled) updatedAt.value = clock();
  }

  Future<void> _readOne(SvOverviewCard c, int gen) async {
    SvOverviewRead got;
    try {
      got = await read(c.source);
    } catch (e, st) {
      AppLog.e('sv_overview_model', e, st);
      got = const SvOverviewRead(isOk: false);
    }
    if (gen != _gen) return;
    if (!got.isOk) {
      c.phase.value = SvCardPhase.error;
      return;
    }
    c.stats.value = SvOverview.stats(
      c.source,
      got.rows,
      total: got.total,
      now: clock(),
    );
    c.phase.value = SvCardPhase.ready;
  }
}
