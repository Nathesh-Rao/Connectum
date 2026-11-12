// Regenerates the data files of design-guide-mobile/ from the Dart source:
//   flutter test tool/design_guide/generate.dart
// Values come from the real classes where they can be imported and from the
// source text for the flat const tables; no number is typed here.
import 'dart:convert';
import 'dart:io';

import 'package:connectum/core/theme/app_chart_colors.dart';
import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/theme/app_motion.dart';
import 'package:connectum/core/theme/app_shadows.dart';
import 'package:connectum/core/theme/app_tones.dart';
import 'package:connectum/core/utils/avatar_palette.dart';
import 'package:connectum/core/widgets/app_bubble_surface.dart';
import 'package:connectum/core/widgets/logo_loader/logo_data.dart';
import 'package:connectum/core/widgets/logo_loader/logo_loader.dart';
import 'package:connectum/features/notifications/notification_style.dart';
import 'package:connectum/features/notifications/notification_texts.dart';
import 'package:connectum/features/notifications/widgets/feed_priority_pill.dart';
import 'package:connectum/features/splash/splash_controller.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'avatar_vectors.dart';

const _out = 'design-guide-mobile';

String _read(String path) => File(path).readAsStringSync();

String _kebab(String s) => s.replaceAllMapped(
  RegExp(r'[A-Z]'),
  (m) => '-${m.group(0)!.toLowerCase()}',
);

Map<String, Object?> _color(Color c) => {
  'hex': hexOf(c),
  'alpha': double.parse(c.a.toStringAsFixed(3)),
};

String _css(Color c) {
  if (c.a >= 0.999) return hexOf(c).toLowerCase();
  final r = (c.r * 255).round(), g = (c.g * 255).round(), b = (c.b * 255).round();
  return 'rgba($r, $g, $b, ${c.a.toStringAsFixed(3)})';
}

/// The body of `class [name] {...}`.
String _classBody(String src, String name) {
  final start = src.indexOf('class $name');
  final next = src.indexOf(RegExp(r'\nclass '), start + 1);
  return src.substring(start, next < 0 ? src.length : next);
}

/// `static const double x = 4;` and `static const int x = 6;`
Map<String, num> _numbers(String body) => {
  for (final m in RegExp(
    r'static const (?:double|int) (\w+) = ([\d.]+);',
  ).allMatches(body))
    m.group(1)!: num.parse(m.group(2)!),
};

/// Scalar colours of a class: `Color(0x...)` or an alias of an earlier one.
Map<String, Color> _colors(String body) {
  final out = <String, Color>{};
  for (final m in RegExp(
    r'static const (\w+) = (Color\(0x([0-9A-Fa-f]{8})\)|(\w+));',
  ).allMatches(body)) {
    final hex = m.group(3);
    if (hex != null) {
      out[m.group(1)!] = Color(int.parse(hex, radix: 16));
    } else if (out.containsKey(m.group(4))) {
      out[m.group(1)!] = out[m.group(4)]!;
    }
  }
  return out;
}

double _eval(String expr, Map<String, num> consts) {
  var total = 0.0;
  var sign = 1.0;
  for (final t in expr.trim().split(RegExp(r'\s+'))) {
    if (t == '+') {
      sign = 1;
    } else if (t == '-') {
      sign = -1;
    } else {
      final v = double.tryParse(t) ?? consts[t]?.toDouble();
      if (v == null) throw StateError('cannot evaluate "$expr" at "$t"');
      total += sign * v;
      sign = 1;
    }
  }
  return total;
}

Map<String, Object?> _textStyles(
  String src,
  Map<String, num> sizes,
  Map<String, Color> colors,
) {
  final out = <String, Object?>{};
  for (final m in RegExp(
    r'static const (\w+) = TextStyle\(([\s\S]*?)\n  \);',
  ).allMatches(src)) {
    final body = m.group(2)!;
    String? field(String key) =>
        RegExp('$key: ([^,\\n]+),').firstMatch(body)?.group(1)?.trim();
    final size = _eval(field('fontSize')!, sizes);
    final height = _eval(field('height')!, sizes);
    final family = field('fontFamily')!;
    final weight = RegExp(r'w(\d00)').firstMatch(field('fontWeight')!)!.group(1)!;
    final spacing = field('letterSpacing');
    final colorName = RegExp(r'AppColors\.(\w+)').firstMatch(field('color')!)!.group(1)!;
    out[m.group(1)!] = {
      'family': family == 'fontFamily' ? 'PlusJakartaSans' : 'SpaceGrotesk',
      'size': size,
      'weight': int.parse(weight),
      'height': double.parse(height.toStringAsFixed(3)),
      'lineHeightPx': double.parse((size * height).toStringAsFixed(2)),
      'letterSpacing': spacing == null ? 0 : _eval(spacing, sizes),
      'color': colorName,
      'colorHex': hexOf(colors[colorName]!),
    };
  }
  return out;
}

Map<String, Object?> _shadow(List<BoxShadow> layers) => {
  'layers': [
    for (final s in layers)
      {
        'color': _color(s.color),
        'blur': s.blurRadius,
        'spread': s.spreadRadius,
        'dx': s.offset.dx,
        'dy': s.offset.dy,
      },
  ],
  'css': layers
      .map(
        (s) =>
            '${s.offset.dx.toStringAsFixed(0)}px ${s.offset.dy.toStringAsFixed(0)}px '
            '${s.blurRadius.toStringAsFixed(0)}px ${s.spreadRadius.toStringAsFixed(0)}px ${_css(s.color)}',
      )
      .join(', '),
};

Map<String, Object?> _tone(AppTone t) => {
  'solid': hexOf(t.solid),
  'strong': hexOf(t.strong),
  'tint': hexOf(t.tint),
  'tintStrong': hexOf(t.tintStrong),
};

String _toneName(AppTone t) {
  const all = {
    'red': AppTones.red,
    'green': AppTones.green,
    'blue': AppTones.blue,
    'violet': AppTones.violet,
    'purple': AppTones.purple,
    'teal': AppTones.teal,
    'indigo': AppTones.indigo,
    'slate': AppTones.slate,
  };
  return all.entries
      .firstWhere((e) => e.value.solid == t.solid && e.value.strong == t.strong)
      .key;
}

Map<String, Object?> _tokens() {
  final colorsSrc = _read('lib/core/theme/app_colors.dart');
  final colors = _colors(_classBody(colorsSrc, 'AppColors'));
  final spacing = _numbers(_classBody(_read('lib/core/theme/app_spacing.dart'), 'AppSpacing'));
  final radius = _numbers(_classBody(_read('lib/core/theme/app_radius.dart'), 'AppRadius'));
  final textSrc = _read('lib/core/theme/app_text.dart');
  final sizes = _numbers(_classBody(textSrc, 'AppText'));
  final motionSrc = _read('lib/core/theme/app_motion.dart');
  final durations = {
    for (final m in RegExp(
      r'static const (\w+) = Duration\((milliseconds|seconds): (\d+)\)',
    ).allMatches(_classBody(motionSrc, 'AppDurations')))
      m.group(1)!: int.parse(m.group(3)!) * (m.group(2) == 'seconds' ? 1000 : 1),
  };
  final distances = _numbers(_classBody(motionSrc, 'AppDistances'));
  final tilePalettes = [
    for (final p in AppColors.tilePalettes)
      {
        'background': hexOf(p.background),
        'border': hexOf(p.border),
        'foreground': hexOf(p.foreground),
      },
  ];
  AppTilePalette? doc(String n) => {
    'docPdf': AppColors.docPdf,
    'docWord': AppColors.docWord,
    'docExcel': AppColors.docExcel,
    'docSlides': AppColors.docSlides,
    'docText': AppColors.docText,
    'docArchive': AppColors.docArchive,
    'docOther': AppColors.docOther,
  }[n];
  const docNames = [
    'docPdf', 'docWord', 'docExcel', 'docSlides', 'docText', 'docArchive', 'docOther',
  ];

  const toneObjects = {
    'red': AppTones.red,
    'green': AppTones.green,
    'blue': AppTones.blue,
    'violet': AppTones.violet,
    'purple': AppTones.purple,
    'teal': AppTones.teal,
    'indigo': AppTones.indigo,
    'primary': AppTones.primary,
    'slate': AppTones.slate,
  };

  final noteSrc = _read('lib/features/notifications/notification_style.dart');
  final ruleStart = noteSrc.indexOf('const notificationRules');
  final ruleSrcPairs = RegExp(
    r'icon: Icons\.(\w+),\s*tone: AppTones\.(\w+)',
  ).allMatches(noteSrc.substring(ruleStart)).toList();
  if (ruleSrcPairs.length != notificationRules.length) {
    throw StateError('notification rules and source text disagree');
  }
  final rules = [
    for (var i = 0; i < notificationRules.length; i++)
      {
        'icon': ruleSrcPairs[i].group(1),
        'tone': ruleSrcPairs[i].group(2),
        'category': notificationRules[i].category,
        'types': notificationRules[i].types.toList(),
        'keywords': notificationRules[i].keywords,
      },
  ];

  final actionSrc = _read('lib/features/tickets/models/ticket_action_style.dart');
  final actionRules = [
    for (final m in RegExp(
      r'_Rule\(\s*\[([^\]]*)\],\s*Icons\.(\w+),\s*AppTones\.(\w+),?\s*\)',
    ).allMatches(actionSrc))
      {
        'keywords': RegExp(r"'(\w+)'").allMatches(m.group(1)!).map((k) => k.group(1)).toList(),
        'icon': m.group(2),
        'tone': m.group(3),
      },
  ];
  final fallback = RegExp(r'_fallback = ActionStyle\(Icons\.(\w+), AppTones\.(\w+)\)')
      .firstMatch(actionSrc)!;

  final cfg = const LogoLoaderConfig();

  return {
    'meta': {
      'note':
          'Generated by tool/design_guide/generate.dart from lib/core/theme/*, '
          'the widgets and the feature style tables. Do not edit by hand.',
      'unit': 'dp; 1 dp = 1 CSS px at mobile',
    },
    'colors': {for (final e in colors.entries) e.key: _color(e.value)},
    'tilePalettes': tilePalettes,
    'documentPalettes': {
      for (final n in docNames)
        n: {
          'background': hexOf(doc(n)!.background),
          'border': hexOf(doc(n)!.border),
          'foreground': hexOf(doc(n)!.foreground),
        },
    },
    'senderInks': [for (final c in AppColors.senderInks) hexOf(c)],
    'tones': {for (final e in toneObjects.entries) e.key: _tone(e.value)},
    'chartSeries': {
      'order': [
        'blue', 'violet', 'cyan', 'indigo', 'teal', 'rose', 'slate',
      ],
      'colors': [for (final c in AppChartColors.series) hexOf(c)],
      'grid': hexOf(AppChartColors.grid),
      'baseline': hexOf(AppChartColors.baseline),
    },
    'priorityPills': {
      for (final p in const ['high', 'medium', 'resolved', 'low'])
        p: FeedPriorityPill.of(p) == null
            ? null
            : {
                'label': FeedPriorityPill.of(p)!.$1,
                'tone': _toneName(FeedPriorityPill.of(p)!.$2),
                ..._tone(FeedPriorityPill.of(p)!.$2),
              },
    },
    'notificationRules': {
      'order': 'first match wins; types are looked up (actionType, icon, category) before keywords',
      'groupMessage': {
        'icon': 'groups_rounded',
        'tone': 'indigo',
        'category': NotificationTexts.categoryMessages,
      },
      'rules': rules,
      'fallback': {'icon': 'notifications_rounded', 'tone': 'slate', 'category': NotificationTexts.categoryGeneral},
    },
    'actionRules': {
      'order': 'first rule with a keyword contained in the lower-cased action name wins',
      'rules': actionRules,
      'fallback': {'icon': fallback.group(1), 'tone': fallback.group(2)},
    },
    'spacing': spacing,
    'radius': radius,
    'text': {
      'families': {'sans': 'PlusJakartaSans', 'display': 'SpaceGrotesk'},
      'sizes': {
        for (final e in sizes.entries)
          if (e.key.startsWith('size') || e.key.startsWith('height')) e.key: e.value,
      },
      'styles': _textStyles(textSrc, sizes, colors),
    },
    'shadows': {
      'focusRing': _shadow(AppShadows.focusRing),
      'sheet': _shadow(AppShadows.sheet),
      'card': _shadow(AppShadows.card),
      'fab': _shadow(AppShadows.fab),
      'soft': _shadow(AppShadows.soft),
    },
    'motion': {
      'durationsMs': durations,
      'distances': distances,
      'curves': {
        'out': _cubic(AppCurves.out),
        'easeIn': _cubic(AppCurves.easeIn),
        'inOut': _cubic(AppCurves.inOut),
      },
      'springs': {
        'sheet': {
          'mass': AppCurves.sheetSpring.mass,
          'stiffness': AppCurves.sheetSpring.stiffness,
          'damping': AppCurves.sheetSpring.damping,
          'settleMs': AppCurves.sheet.settle.inMilliseconds,
        },
        'press': {
          'mass': AppCurves.pressSpring.mass,
          'stiffness': AppCurves.pressSpring.stiffness,
          'damping': AppCurves.pressSpring.damping,
        },
      },
    },
    'bubbleSurface': {
      'base': hexOf(kBubbleBase),
      'opacityScale': kBubbleOpacityScale,
      'highlightAlignment': {'x': kBubbleHighlight.x, 'y': kBubbleHighlight.y},
      'edgeFalloff': kBubbleEdgeFalloff,
      'topHighlightOpacity': kBubbleTopHighlightOpacity,
      'pressedColor': hexOf(kBubblePressedColor),
      'pressedOpacity': kBubblePressedOpacity,
      'wideFromWidth': kBubbleWideFrom,
      'mediumFromWidth': kBubbleMediumFrom,
      'disabledFill': hexOf(AppColors.primaryDisabled),
      'sets': {
        'wide': _discs(kBubblesWide),
        'medium': _discs(kBubblesMedium),
        'narrow': _discs(kBubblesNarrow),
        'fab': _discs(kBubblesFab),
      },
      'discFields': 'dx, dy = centre as fraction of width / height; diameter = multiple of the surface height',
    },
    'avatarPalette': {
      'backgroundSaturation': AvatarPalette.backgroundSaturation,
      'backgroundLightness': AvatarPalette.backgroundLightness,
      'neutral': {
        'foreground': hexOf(AvatarPalette.neutral.foreground),
        'background': hexOf(AvatarPalette.neutral.background),
      },
      'hues': [
        for (var i = 0; i < AvatarPalette.hues.length; i++)
          {
            'index': i,
            'name': AvatarPalette.hues[i].name,
            'hue': AvatarPalette.hues[i].hue,
            'foregroundSaturation': AvatarPalette.hues[i].foregroundSaturation,
            'foregroundLightness': AvatarPalette.hues[i].foregroundLightness,
            'foreground': hexOf(AvatarPalette.colorsOf(AvatarPalette.hues[i]).foreground),
            'background': hexOf(AvatarPalette.colorsOf(AvatarPalette.hues[i]).background),
            'contrastForegroundOnBackground': double.parse(
              AvatarPalette.contrast(
                AvatarPalette.colorsOf(AvatarPalette.hues[i]).foreground,
                AvatarPalette.colorsOf(AvatarPalette.hues[i]).background,
              ).toStringAsFixed(2),
            ),
            'contrastWhiteOnForeground': double.parse(
              AvatarPalette.contrast(
                AppColors.white,
                AvatarPalette.colorsOf(AvatarPalette.hues[i]).foreground,
              ).toStringAsFixed(2),
            ),
          },
      ],
    },
    'contrast': _contrast(),
    'splash': {
      'startDelayMs': SplashController.startDelay.inMilliseconds,
      'extraRunMs': SplashController.extraRun.inMilliseconds,
      'endDelayMs': SplashController.endDelay.inMilliseconds,
      'reducedMotionDelayMs': SplashController.reducedMotionDelay.inMilliseconds,
    },
    'logoLoaderConfig': {
      'startMorph': cfg.startMorph,
      'morphRamp': cfg.morphRamp,
      'startSpeed': cfg.startSpeed,
      'baseSpeed': cfg.baseSpeed,
      'tau': cfg.tau,
      'maxAccel': cfg.maxAccel,
      'rhythm': cfg.rhythm,
      'burstMin': cfg.burstMin,
      'burstMax': cfg.burstMax,
      'minFactor': cfg.minFactor,
      'maxFactor': cfg.maxFactor,
      'stopMin': cfg.stopMin,
      'stopMax': cfg.stopMax,
      'segments': cfg.segments,
      'gap': cfg.gap,
      'swirl': cfg.swirl,
      'overlap': cfg.overlap,
      'tailBias': cfg.tailBias,
    },
  };
}

Map<String, Object?> _cubic(Cubic c) => {
  'a': c.a,
  'b': c.b,
  'c': c.c,
  'd': c.d,
  'css': 'cubic-bezier(${c.a}, ${c.b}, ${c.c}, ${c.d})',
};

List<Map<String, Object?>> _discs(List<BubbleDisc> list) => [
  for (final d in list)
    {
      'dx': d.dx,
      'dy': d.dy,
      'diameter': d.diameter,
      'color': hexOf(d.color),
      'opacity': d.opacity,
    },
];

List<Map<String, Object?>> _contrast() {
  final pairs = <(String, Color, Color)>[
    ('ink on white', AppColors.ink, AppColors.white),
    ('muted on white', AppColors.muted, AppColors.white),
    ('muted on surfaceSubtle', AppColors.muted, AppColors.surfaceSubtle),
    ('muted on fill', AppColors.muted, AppColors.fill),
    ('muted on bubbleIn', AppColors.muted, AppColors.bubbleIn),
    ('cardMuted on white', AppColors.cardMuted, AppColors.white),
    ('primary on white', AppColors.primary, AppColors.white),
    ('primary on surfaceSubtle', AppColors.primary, AppColors.surfaceSubtle),
    ('error on white', AppColors.error, AppColors.white),
    ('white on primary', AppColors.white, AppColors.primary),
    ('white on primaryBright', AppColors.white, AppColors.primaryBright),
    ('white on purple', AppColors.white, AppColors.purple),
    ('white on error', AppColors.white, AppColors.error),
    ('white on primaryStrong', AppColors.white, AppColors.primaryStrong),
    ('primaryStrong on primarySoft', AppColors.primaryStrong, AppColors.primarySoft),
    ('primaryStrong on primaryTint', AppColors.primaryStrong, AppColors.primaryTint),
    ('primaryStrong on primaryTintStrong', AppColors.primaryStrong, AppColors.primaryTintStrong),
    ('primary on primaryTintStrong', AppColors.primary, AppColors.primaryTintStrong),
    ('violetStrong on violetTint', AppColors.violetStrong, AppColors.violetTint),
    ('purple on white', AppColors.purple, AppColors.white),
    ('purple on violetTint', AppColors.purple, AppColors.violetTint),
    ('yesText on yesFill', AppColors.yesText, AppColors.yesFill),
    ('noText on noFill', AppColors.noText, AppColors.noFill),
    ('primaryBright on white (icons)', AppColors.primaryBright, AppColors.white),
    ('primaryBright on surfaceSubtle (icons)', AppColors.primaryBright, AppColors.surfaceSubtle),
    ('primaryBright on primaryTint (icons)', AppColors.primaryBright, AppColors.primaryTint),
    ('mention on bubbleIn', AppColors.mention, AppColors.bubbleIn),
    ('mention on bubbleOut', AppColors.mention, AppColors.bubbleOut),
    ('mentionMe on bubbleIn', AppColors.mentionMe, AppColors.bubbleIn),
    ('avatarText on avatarBg', AppColors.avatarText, AppColors.avatarBg),
    ('white on bubble surface, lightest wide stack', AppColors.white, bubbleLightestStack(const Size(320, 52))),
  ];
  return [
    for (final (label, fg, bg) in pairs)
      {
        'pair': label,
        'foreground': hexOf(fg),
        'background': hexOf(bg),
        'ratio': double.parse(AvatarPalette.contrast(fg, bg).toStringAsFixed(2)),
      },
  ];
}

String _tokensCss(Map<String, Object?> t) {
  final b = StringBuffer(
    '/* Generated by tool/design_guide/generate.dart. Do not edit by hand. */\n:root {\n',
  );
  void line(String k, Object v) => b.writeln('  --$k: $v;');
  final colors = _colors(_classBody(_read('lib/core/theme/app_colors.dart'), 'AppColors'));
  for (final e in colors.entries) {
    line('color-${_kebab(e.key)}', _css(e.value));
  }
  for (final e in (t['tones']! as Map).entries) {
    final tone = e.value as Map;
    for (final k in ['solid', 'strong', 'tint', 'tintStrong']) {
      line('tone-${e.key}-${_kebab(k)}', (tone[k]! as String).toLowerCase());
    }
  }
  final series = (t['chartSeries']! as Map)['colors']! as List;
  final order = (t['chartSeries']! as Map)['order']! as List;
  for (var i = 0; i < series.length; i++) {
    line('chart-${order[i]}', (series[i] as String).toLowerCase());
  }
  for (final e in (t['spacing']! as Map).entries) {
    line('space-${_kebab(e.key as String)}', '${_n(e.value as num)}px');
  }
  for (final e in (t['radius']! as Map).entries) {
    line('radius-${_kebab(e.key as String)}', '${_n(e.value as num)}px');
  }
  final text = t['text']! as Map;
  line('font-sans', "'PlusJakartaSans', system-ui, sans-serif");
  line('font-display', "'SpaceGrotesk', system-ui, sans-serif");
  for (final e in (text['styles']! as Map).entries) {
    final s = e.value as Map;
    final n = _kebab(e.key as String);
    line('text-$n-size', '${_n(s['size'] as num)}px');
    line('text-$n-weight', s['weight']!);
    line('text-$n-line-height', s['height']!);
    line('text-$n-letter-spacing', '${_n(s['letterSpacing'] as num)}px');
    line('text-$n-color', (s['colorHex']! as String).toLowerCase());
  }
  for (final e in (t['shadows']! as Map).entries) {
    line('shadow-${_kebab(e.key as String)}', (e.value as Map)['css']!);
  }
  final motion = t['motion']! as Map;
  for (final e in (motion['durationsMs']! as Map).entries) {
    line('duration-${_kebab(e.key as String)}', '${e.value}ms');
  }
  for (final e in (motion['curves']! as Map).entries) {
    line('ease-${_kebab(e.key as String)}', (e.value as Map)['css']!);
  }
  b.writeln('}');
  return b.toString();
}

String _n(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

Map<String, Object?> _logoPolys() {
  final src = _read('lib/core/widgets/logo_loader/logo_data.dart');
  final start = src.indexOf('buildOriginalPaths() => <Path>[');
  final end = src.indexOf('\n];', start);
  final paths = <String>[];
  for (final line in src.substring(start, end).split('\n').skip(1)) {
    final t = line.trim();
    if (!t.startsWith('Path()')) continue;
    final d = StringBuffer();
    for (final m in RegExp(r'\.\.(moveTo|cubicTo|lineTo|close)\(([^)]*)\)').allMatches(t)) {
      final args = m.group(2)!;
      d.write(switch (m.group(1)) {
        'moveTo' => 'M$args',
        'lineTo' => 'L$args',
        'cubicTo' => 'C$args',
        _ => 'Z',
      });
    }
    paths.add(d.toString().replaceAll(',', ' '));
  }
  if (paths.length != LogoGeo.count) {
    throw StateError('expected ${LogoGeo.count} original paths, got ${paths.length}');
  }
  return {
    'note': 'Generated by tool/design_guide/generate.dart from lib/core/widgets/logo_loader/logo_data.dart. Do not edit by hand.',
    'viewBox': [0, 0, 1024, 1024],
    'geo': {
      'cx': LogoGeo.cx,
      'cy': LogoGeo.cy,
      'phiC': LogoGeo.phiC,
      'g0': LogoGeo.g0,
      'rOut': LogoGeo.rOut,
      'rIn': LogoGeo.rIn,
      'count': LogoGeo.count,
    },
    'colors': {
      for (final c in kLogoPolys.map((p) => p.color).toSet())
        '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}': kLogoPolys
            .where((p) => p.color == c)
            .length,
    },
    'originalPaths': paths,
    'polys': [
      for (final p in kLogoPolys)
        {
          'color': '#${(p.color & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
          'r': p.r.map((v) => double.parse(v.toStringAsFixed(3))).toList(),
          'a': p.a.map((v) => double.parse(v.toStringAsFixed(5))).toList(),
          'rf': p.rf.map((v) => double.parse(v.toStringAsFixed(3))).toList(),
        },
    ],
  };
}

void _write(String path, String content) {
  final f = File('$_out/$path')..createSync(recursive: true);
  f.writeAsStringSync(content);
}

void main() {
  const pretty = JsonEncoder.withIndent('  ');
  test('generate design-guide-mobile data files', () {
    final tokens = _tokens();
    _write('tokens/tokens.json', '${pretty.convert(tokens)}\n');
    _write('tokens/tokens.css', _tokensCss(tokens));
    _write('logo-loader/logo_polys.json', '${jsonEncode(_logoPolys())}\n');
  });
  testWidgets('generate avatar colour vectors', (tester) async {
    final vectors = await buildAvatarVectors(tester);
    _write(
      'tokens/avatar-color-vectors.json',
      '${pretty.convert({
        'note': 'Generated by tool/design_guide/generate.dart by running the real Dart code. Do not edit by hand.',
        ...vectors,
      })}\n',
    );
  });
}
