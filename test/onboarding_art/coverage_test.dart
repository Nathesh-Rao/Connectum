import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:connectum/core/widgets/onboarding_art/network_icons_art.dart';
import 'package:connectum/core/widgets/onboarding_art/network_tiers.dart';
import 'package:connectum/core/widgets/onboarding_art/onboarding_art.dart';
import 'package:connectum/core/widgets/onboarding_art/onboarding_art_palette.dart';
import 'package:connectum/core/widgets/onboarding_art/svg_scene.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ground truth: tool/onboarding_anim/js_truth.js runs the HTML scripts and
/// writes this fixture.
final Map<String, dynamic> _truth =
    jsonDecode(File('test/onboarding_art/fixtures/js_truth.json').readAsStringSync())
        as Map<String, dynamic>;

/// The HTML's full network (6 people plus the 40 background people, no trim):
/// what the script's own numbers in the fixture describe.
const _fullNetwork = ['c', 'top', 'tr', 'br', 'bl', 'l', 'background'];

ArtScene _bindFull(SvgScene s) =>
    NetworkIcons.bind(s, visible: _fullNetwork, idleTrim: 0);

class _Frame {
  _Frame(this.scene, this.art, this.px, this.w, this.h);

  final SvgScene scene;
  final ArtScene art;
  final List<int> px;
  final int w, h;

  /// Non-transparent pixels inside [r] given in scene units.
  int drawnIn(Rect r) {
    final vb = scene.viewBox;
    final s = w / vb.width;
    final x0 = ((r.left - vb.left) * s).floor().clamp(0, w);
    final x1 = ((r.right - vb.left) * s).ceil().clamp(0, w);
    final y0 = ((r.top - vb.top) * s).floor().clamp(0, h);
    final y1 = ((r.bottom - vb.top) * s).ceil().clamp(0, h);
    var n = 0;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        if (px[(y * w + x) * 4 + 3] > 8) n++;
      }
    }
    return n;
  }
}

Future<_Frame> _frame(
  OnboardingArtKind kind,
  double t, {
  ArtScene Function(SvgScene)? binder,
}) async {
  final scene = kind.build(OnboardingArtPalette.authored);
  final art = (binder ?? kind.bind)(scene);
  const w = 1200;
  final h = (w * scene.viewBox.height / scene.viewBox.width).round();
  final rec = PictureRecorder();
  final c = Canvas(rec);
  c.clipRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
  c.scale(w / scene.viewBox.width);
  c.translate(-scene.viewBox.left, -scene.viewBox.top);
  art.render(t);
  SvgRenderer(scene).paint(c);
  final img = await rec.endRecording().toImage(w, h);
  final data = (await img.toByteData())!.buffer.asUint8List();
  return _Frame(scene, art, data, w, h);
}

bool _reachable(SvgScene s, String id) {
  final n = s.maybeId(id);
  if (n == null) return false;
  for (SvgNode? p = n; p != null; p = p.parent) {
    if (p == s.root) return true;
  }
  return false;
}

Rect _placed(SvgNode n) {
  final b = n.getBBox();
  return n.transform != null ? n.transform!.mapRect(b) : b;
}

void main() {
  group('element counts match what the HTML scripts build', () {
    test('network', () {
      final s = OnboardingArtKind.network.build(OnboardingArtPalette.authored);
      _bindFull(s);
      final want = Map<String, dynamic>.from(_truth['network']['created'] as Map);
      expect(s.createdByTag, want.map((k, v) => MapEntry(k, v as int)));
    });
    test('shield', () {
      final s = OnboardingArtKind.shield.build(OnboardingArtPalette.authored);
      OnboardingArtKind.shield.bind(s);
      final want = Map<String, dynamic>.from(_truth['shield']['created'] as Map);
      expect(s.createdByTag, want.map((k, v) => MapEntry(k, v as int)));
    });
    test('buildings builds nothing in script', () {
      final s = OnboardingArtKind.buildings.build(OnboardingArtPalette.authored);
      OnboardingArtKind.buildings.bind(s);
      expect(s.createdByTag, isEmpty);
    });
  });

  group('network, the HTML\'s full network (all 46 people)', () {
    final t = _truth['network'] as Map<String, dynamic>;

    test('45 nodes: 5 primary + 40 background people, per level 10/16/14', () {
      final s = OnboardingArtKind.network.build(OnboardingArtPalette.authored);
      final art = _bindFull(s);
      expect(art.info['nodes'], t['nodes']);
      expect(art.info['electrons'], t['electrons']);
      expect(art.info['lateral'], t['lateral']);
      final people = art.info['people']! as List;
      expect(people.length, t['people']);
      for (var l = 1; l <= 3; l++) {
        expect(people.where((p) => (p as List)[0] == l).length, (t['byLevel'] as List)[l]);
      }
      final groups = s.byId('bgAv').children.where((c) => c.tag == 'g');
      expect(groups.length, 40);
      expect(s.byId('bgAv').children.length, 80, reason: 'person + ripple each');
    });

    test('reveal times, kinds and places equal the script (all 40)', () {
      final art = _bindFull(
        OnboardingArtKind.network.build(OnboardingArtPalette.authored),
      );
      final got = art.info['people']! as List;
      final want = t['reveal'] as List;
      for (var i = 0; i < want.length; i++) {
        final g = got[i] as List, w = want[i] as List;
        expect(g[0], w[0], reason: 'level of #$i');
        expect(g[1], w[1], reason: 'kind of #$i');
        expect((g[2] as double), closeTo((w[2] as num).toDouble(), 1e-3), reason: 't0 of #$i');
        expect((g[3] as double), closeTo((w[3] as num).toDouble(), 1e-3), reason: 'ts of #$i');
        expect((g[4] as double), closeTo((w[4] as num).toDouble(), 0.06));
        expect((g[5] as double), closeTo((w[5] as num).toDouble(), 0.06));
      }
      // the first and the last icon
      expect((got.first as List)[2], closeTo(4.1, 1e-6));
      expect((got.last as List)[3], closeTo(6.84, 1e-6));
    });

    test('every person is drawn when the script shows them all (t = 9, 14.5)', () async {
      for (final time in [9.0, 14.5]) {
        final f = await _frame(OnboardingArtKind.network, time, binder: _bindFull);
        final groups = f.scene.byId('bgAv').children.where((c) => c.tag == 'g').toList();
        expect(groups.length, 40);
        for (var i = 0; i < groups.length; i++) {
          final r = _placed(groups[i]);
          expect(groups[i].opacity, greaterThan(0.5), reason: 'person $i at t=$time');
          expect(f.drawnIn(r), greaterThan(10), reason: 'person $i has no pixels at t=$time');
        }
        for (final k in ['c', 'top', 'tr', 'br', 'bl', 'l']) {
          expect(f.drawnIn(_placed(f.scene.byId('av_$k'))), greaterThan(50), reason: k);
        }
        for (final k in ['top', 'tr', 'br', 'bl', 'l']) {
          expect(f.drawnIn(_placed(f.scene.byId('ic_$k'))), greaterThan(50), reason: 'icon $k');
        }
      }
    });

    test('before the reveal none of the 40 is drawn (t = 3)', () async {
      final f = await _frame(OnboardingArtKind.network, 3.0, binder: _bindFull);
      final groups = f.scene.byId('bgAv').children.where((c) => c.tag == 'g');
      for (final g in groups) {
        expect(g.opacity, 0);
      }
    });

    test('first and last person appear at their time', () async {
      final people = _bindFull(
            OnboardingArtKind.network.build(OnboardingArtPalette.authored),
          ).info['people']! as List;
      final first = people.first as List, last = people.last as List;
      final late = await _frame(OnboardingArtKind.network, (last[3] as double) + 1.0, binder: _bindFull);
      final groups = late.scene.byId('bgAv').children.where((c) => c.tag == 'g').toList();
      expect(groups.first.opacity, greaterThan(0.5));
      expect(groups.last.opacity, greaterThan(0.5));
      final early = await _frame(OnboardingArtKind.network, (first[2] as double) - 0.2, binder: _bindFull);
      final eg = early.scene.byId('bgAv').children.where((c) => c.tag == 'g').toList();
      expect(eg.first.opacity, 0, reason: 'not yet at t0 - 0.2');
      final mid = await _frame(OnboardingArtKind.network, (first[3] as double) + 0.3, binder: _bindFull);
      expect(
        mid.scene.byId('bgAv').children.where((c) => c.tag == 'g').first.opacity,
        greaterThan(0),
      );
    });
  });

  group('network tiers (design decision: tier 1 + one tier of small people)', () {
    const tier1 = ['c', 'top', 'tr', 'br', 'bl'];
    const tier2 = ['top-0', 'top-1', 'tr-0', 'tr-1', 'br-0', 'br-1', 'bl-0', 'bl-1'];
    // the HTML's own reveal of the hubs: spawn start (+ 0.7 s to pop in)
    const hubSpawn = {'c': 0.0, 'top': 1.8, 'tr': 2.0, 'br': 2.2, 'bl': 2.4};

    ({SvgScene scene, ArtScene art, SvgRenderer renderer}) build({bool tier2On = true}) {
      final scene = OnboardingArtKind.network.build(OnboardingArtPalette.authored);
      final art = OnboardingArtKind.network.bind(scene, tier2: tier2On);
      return (scene: scene, art: art, renderer: SvgRenderer(scene));
    }

    Set<String> personsDrawn(
      ({SvgScene scene, ArtScene art, SvgRenderer renderer}) b,
      double t,
    ) {
      b.art.render(t);
      final groups = (b.art.info['personGroups']! as Map).cast<String, SvgNode>();
      final byNode = {for (final e in groups.entries) e.value: e.key};
      return {
        for (final d in b.renderer.drawnRects())
          for (final n in d.via)
            if (byNode.containsKey(n)) byNode[n]!,
      };
    }

    test('the config lists: tier 1 is the first five, tier 2 the one-hop people', () {
      expect(kNetworkTier1Persons, tier1);
      expect(kNetworkTier2Persons, tier2);
      expect(kNetworkVisiblePersons, [...tier1, ...tier2]);
      const spawn = {'c': 0.0, 'top': 1.8, 'tr': 2.0, 'br': 2.2, 'bl': 2.4, 'l': 2.6};
      final byTime = spawn.keys.toList()..sort((a, b) => spawn[a]!.compareTo(spawn[b]!));
      expect(byTime.take(5).toList(), tier1);
      // tier 2 = the people one hop out whose hub is in tier 1 (the HTML graph)
      final full = _bindFull(OnboardingArtKind.network.build(OnboardingArtPalette.authored));
      final levelOne = [
        for (final p in full.info['people']! as List)
          if ((p as List)[0] == 1) p[6] as String,
      ];
      expect(levelOne.length, 10);
      expect(
        {for (final id in levelOne) if (tier1.contains(id.split('-').first)) id},
        tier2.toSet(),
      );
      // left out: the two people of the hidden hub `l`, which would dangle
      expect(levelOne.where((id) => id.startsWith('l-')).toSet(), {'l-0', 'l-1'});
    });

    test('only tier 1 and tier 2 exist: no other person, link or mask', () {
      final b = build();
      final people = (b.art.info['people']! as List).map((p) => (p as List)[6] as String).toList();
      expect(people.toSet(), tier2.toSet());
      expect(b.scene.byId('bgAv').children.length, tier2.length * 2, reason: 'person + ripple each');
      // 8 links + 8 dots + 8 heads + the 2 links between kept people
      expect(b.scene.byId('bgLinks').children.length, tier2.length * 3 + 2);
      for (final k in tier1) {
        expect(_reachable(b.scene, 'av_$k'), isTrue, reason: k);
      }
      for (final k in tier1.where((k) => k != 'c')) {
        expect(_reachable(b.scene, 'ic_$k'), isTrue, reason: 'icon $k');
        expect(b.scene.findMasked('mk_$k'), isNotNull, reason: 'link $k');
      }
      expect(_reachable(b.scene, 'av_l'), isFalse);
      expect(_reachable(b.scene, 'ic_l'), isFalse);
      expect(b.scene.findMasked('mk_l'), isNull);
      expect(b.scene.findMasked('mk_ch'), isNull, reason: 'the chat link joins l and top');
      expect(b.art.info['lateral'], 2, reason: 'top-1<->tr-1 and tr-0<->br-1 stay, the two toward l go');
    });

    test('the created elements are exactly what the two tiers need', () {
      final b = build();
      final e = b.art.info['electrons']! as int;
      final pulses = b.art.info['pulses']! as int;
      final lat = b.art.info['lateral']! as int;
      const hubs = 5, persons = 8;
      expect(b.scene.createdByTag, {
        // flash + 3 ripples per hub, a ripple per person, the centre pulses
        'ellipse': hubs * 4 + persons + pulses,
        // spawn dots 14 + 4*9, 3 node ripples, 4 comets * 2, 4 icon effects * 3,
        // 9 electron slots * 10, an electron ripple each, a dot and a head per person
        'circle': 14 + 4 * 9 + 3 + 4 * 2 + 4 * 3 + 9 * 10 + e + persons * 2,
        'g': 4 + 9 + persons, // comets, electron slots, person groups
        'line': 4 + 4 + persons + lat, // comet streaks, flow lines, person links, lateral links
        'path': 4 * 7,
        'use': persons,
      });
    });

    test('only tier 1 and tier 2 are ever drawn across the whole loop; every tier-2 person shows', () {
      final b = build();
      final period = b.art.info['period']! as double;
      final seen = <String>{};
      final hubIds = <String>{};
      for (var t = 0.0; t < period; t += 0.05) {
        seen.addAll(personsDrawn(b, t));
        for (final d in b.renderer.drawnRects()) {
          hubIds.addAll(RegExp(r'av_(\w+)').allMatches(d.label).map((m) => m[1]!));
        }
      }
      expect(seen, tier2.toSet(), reason: 'exactly the tier-2 people, no other');
      expect(hubIds, tier1.toSet());
      for (final id in seen) {
        expect(tier1.contains(id.split('-').first), isTrue, reason: '$id hangs off a kept hub');
      }
    });

    test('tier 2 appears after tier 1 is established, at the HTML times', () {
      final b = build();
      final people = (b.art.info['people']! as List).cast<List>();
      final lastHub = hubSpawn.values.reduce((a, b) => a > b ? a : b) + 0.7;
      for (final p in people) {
        expect(p[2] as double, greaterThan(lastHub), reason: '${p[6]} starts after the hubs have popped in');
      }
      // the HTML's own times: match each by place to the script's output
      final truth = (_truth['network']['reveal'] as List).cast<List>();
      for (final p in people) {
        final hit = truth.firstWhere(
          (r) => ((r[4] as num) - (p[4] as double)).abs() < 0.06 && ((r[5] as num) - (p[5] as double)).abs() < 0.06,
        );
        expect(p[2] as double, closeTo((hit[2] as num).toDouble(), 1e-3), reason: '${p[6]} t0');
        expect(p[3] as double, closeTo((hit[3] as num).toDouble(), 1e-3), reason: '${p[6]} ts');
      }
    });

    test('every connector joins two visible people and is drawn before or with its person', () {
      final b = build();
      final connectors = (b.art.info['connectors']! as List).cast<List>();
      expect(connectors.length, 8 + 2);
      final visible = {...tier1, ...tier2};
      final ts = {
        for (final p in (b.art.info['people']! as List).cast<List>()) p[6] as String: p[3] as double,
      };
      for (final c in connectors) {
        expect(visible.contains(c[0]), isTrue, reason: 'start ${c[0]} of ${c[1]}');
        expect(visible.contains(c[1]), isTrue, reason: 'end ${c[1]}');
        final isLateral = tier2.contains(c[0]);
        if (isLateral) {
          // a link between two small people starts once both have popped in
          expect(c[2] as double, greaterThanOrEqualTo(ts[c[0]]!), reason: '${c[0]}-${c[1]}');
          expect(c[2] as double, greaterThanOrEqualTo(ts[c[1]]!), reason: '${c[0]}-${c[1]}');
        } else {
          // a hub link is drawn from the hub and reaches its person as it pops in
          expect(c[2] as double, lessThan(ts[c[1]]!), reason: 'link to ${c[1]} starts before the icon');
          expect(c[3] as double, closeTo(ts[c[1]]! + 0.12, 1e-6), reason: 'link to ${c[1]} arrives with the icon');
        }
      }
      // every tier-2 person has at least one connector
      for (final id in tier2) {
        expect(connectors.any((c) => c[1] == id || c[0] == id), isTrue, reason: id);
      }
    });

    test('no connector dangles: both ends sit on a drawn person (pixels, t = 9)', () async {
      final f = await _frame(OnboardingArtKind.network, 9.0);
      final groups = (f.art.info['personGroups']! as Map).cast<String, SvgNode>();
      final connectors = (f.art.info['connectors']! as List).cast<List>();
      Rect owner(String id) =>
          groups.containsKey(id) ? _placed(groups[id]!) : _placed(f.scene.byId('av_$id'));
      for (final c in connectors) {
        for (final (id, x, y) in [
          (c[0] as String, c[4] as double, c[5] as double),
          (c[1] as String, c[6] as double, c[7] as double),
        ]) {
          expect(
            owner(id).inflate(14).contains(Offset(x, y)),
            isTrue,
            reason: 'the end of ${c[0]}-${c[1]} at ($x, $y) is not on $id ${owner(id)}',
          );
          expect(f.drawnIn(owner(id)), greaterThan(50), reason: '$id is drawn');
        }
        final mid = Offset(((c[4] as double) + (c[6] as double)) / 2, ((c[5] as double) + (c[7] as double)) / 2);
        expect(f.drawnIn(Rect.fromCenter(center: mid, width: 20, height: 20)), greaterThan(0), reason: 'link ${c[0]}-${c[1]} is drawn');
      }
    });

    test('nothing of the hidden hub l is left: its ring, icon and chat link are empty', () async {
      for (final t in [4.6, 9.0]) {
        final f = await _frame(OnboardingArtKind.network, t);
        expect(f.drawnIn(const Rect.fromLTWH(150, 330, 330, 250)), 0, reason: 'empty at t=$t');
      }
    });

    test('the loop is seamless: empty at the start and at the end, equal after a wrap', () async {
      final b = build();
      final period = b.art.info['period']! as double;
      final start = await _frame(OnboardingArtKind.network, 0);
      final end = await _frame(OnboardingArtKind.network, period - 0.001);
      final wrapped = await _frame(OnboardingArtKind.network, period);
      // the HTML's first frame has a 1.5 percent flash of the centre; the end
      // is fully faded out: both are empty to the eye (alpha under 8 of 255)
      int maxAlpha(List<int> px) {
        var m = 0;
        for (var i = 3; i < px.length; i += 4) {
          if (px[i] > m) m = px[i];
        }
        return m;
      }

      expect(maxAlpha(start.px), lessThan(8), reason: 'start is empty');
      expect(maxAlpha(end.px), lessThan(8), reason: 'end is empty');
      expect(wrapped.px, start.px, reason: 'the wrap lands exactly on the start');
    });

    test('loop length: HTML 16.8 s, earlier tier-1 version 13.441 s, now 14.881 s; little idle time', () {
      final b = build();
      final period = b.art.info['period']! as double;
      expect(period, closeTo(14.881, 0.001));
      expect(period, lessThan(NetworkIcons.htmlPeriod));
      expect(b.art.info['idleTrim'], kNetworkIdleTrim);
      final introEnd = b.art.info['introEnd']! as double;
      final starts = (b.art.info['electronStarts']! as List).cast<double>();
      expect(starts.first - introEnd, lessThan(1.0), reason: 'the first electron follows the last reveal');
      // tier 1 alone still works (the lab switch); it shares the trim (1.0 s)
      final solo = build(tier2On: false);
      expect(solo.art.info['period'], closeTo(14.441, 0.001));
      expect((solo.art.info['people']! as List), isEmpty);
    });

    test('the HTML full network is unchanged by the config: 16.8 s loop, outro at 15.6', () {
      final art = _bindFull(OnboardingArtKind.network.build(OnboardingArtPalette.authored));
      expect(art.info['period'], closeTo(16.8, 1e-9));
      expect(art.info['outroStart'], closeTo(15.6, 1e-9));
    });
  });

  group('buildings', () {
    final t = _truth['buildings'] as Map<String, dynamic>;

    test('timeline equals the script', () {
      final art = OnboardingArtKind.buildings.bind(
        OnboardingArtKind.buildings.build(OnboardingArtPalette.authored),
      );
      expect(art.info['loopStart'] as double, closeTo((t['loopStart'] as num).toDouble(), 1e-9));
      expect(art.info['period'] as double, closeTo((t['period'] as num).toDouble(), 1e-9));
      final nodeT = art.info['nodeT']! as List;
      final want = t['nodeT'] as List;
      for (var i = 0; i < want.length; i++) {
        expect(nodeT[i] as double, closeTo((want[i] as num).toDouble(), 1e-9));
      }
      final hits = art.info['hits']! as List;
      final wantHits = t['hits'] as List;
      expect(hits.length, wantHits.length);
      for (var i = 0; i < wantHits.length; i++) {
        expect((hits[i] as List)[0] as double, closeTo(((wantHits[i] as List)[0] as num).toDouble(), 1e-3));
        expect((hits[i] as List)[1], (wantHits[i] as List)[1]);
      }
    });

    test('all buildings, nodes and bubbles are drawn once the intro is done', () async {
      final f = await _frame(OnboardingArtKind.buildings, 6.0);
      for (final n in ['wh', 't1', 'fa', 't2', 'tw', 't3', 'ho', 't4', 'mu']) {
        final els = f.scene.byClass('bg-$n');
        expect(els, isNotEmpty);
        var drawn = 0;
        for (final e in els) {
          drawn += f.drawnIn(_placed(e));
        }
        expect(drawn, greaterThan(100), reason: 'building $n');
      }
      for (final n in ['n0', 'n1', 'n2', 'nd', 'n4', 'n5']) {
        expect(f.drawnIn(_placed(f.scene.byId(n))), greaterThan(20), reason: 'node $n');
      }
      for (final b in ['bL', 'bC', 'bR']) {
        expect(f.drawnIn(_placed(f.scene.byId(b))), greaterThan(100), reason: 'bubble $b');
      }
    });
  });

  group('shield', () {
    test('arrival time equals the script', () {
      final art = OnboardingArtKind.shield.bind(
        OnboardingArtKind.shield.build(OnboardingArtPalette.authored),
      );
      final t = _truth['shield'] as Map<String, dynamic>;
      expect(art.info['arrival'] as double, closeTo((t['arrival'] as num).toDouble(), 1e-9));
      expect(art.info['loopStart'], t['loopStart']);
      expect(art.info['cycle'], t['cycle']);
    });

    test('shield, nodes, message tile and encrypted tile are drawn when they should be', () async {
      var f = await _frame(OnboardingArtKind.shield, 1.95);
      expect(f.drawnIn(f.scene.byId('shield').getBBox()), greaterThan(500));
      for (final n in ['n0', 'n1', 'n2']) {
        expect(f.drawnIn(_placed(f.scene.byId(n))), greaterThan(20), reason: n);
      }
      // message tile at the shield's edge (loop start + 0.9 s)
      f = await _frame(OnboardingArtKind.shield, 1.95 + 0.9);
      expect(f.scene.byId('msg').visible, isTrue);
      expect(f.drawnIn(_placed(f.scene.byId('msgT'))), greaterThan(200));
      // encrypted tile (loop start + 1.55 + 0.8 s)
      f = await _frame(OnboardingArtKind.shield, 1.95 + 1.55 + 0.8);
      expect(f.scene.byId('enc').visible, isTrue);
      expect(f.drawnIn(_placed(f.scene.byId('encT'))), greaterThan(200));
    });
  });

  group('generator coverage check', () {
    test('fails loudly when the generated data misses an element', () async {
      final r = await Process.run('python3', [
        '-I',
        '-c',
        '''
import sys, re
sys.path.insert(0, 'tool/onboarding_anim')
import extract_art as e
import xml.etree.ElementTree as ET
html = open('incoming/onboarding-animations/network-icons.html').read()
root = e.from_et(ET.fromstring(re.search(r'<svg\\b.*?</svg>', html, re.S).group(0)))
dart = open('lib/core/widgets/onboarding_art/generated/network_art_data.dart').read()
assert e.coverage('ok', root, dart, html) == []
broken = dart.replace("'id': 'av_top'", "'id': 'av_gone'")
problems = e.coverage('broken', root, broken, html)
assert any('av_top' in p or 'av_gone' in p for p in problems), problems
print('detected')
''',
      ]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}', contains('detected'));
    }, skip: Directory('incoming/onboarding-animations').existsSync()
        ? false
        : 'incoming/onboarding-animations is not present');
  });
}
