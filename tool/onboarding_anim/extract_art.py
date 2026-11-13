#!/usr/bin/env python3
"""Generates the onboarding art data files from the hand-made HTML/SVG animations.

Usage: python3 tool/onboarding_anim/extract_art.py [--src DIR] [--out DIR]
Defaults: incoming/onboarding-animations -> lib/core/widgets/onboarding_art/generated

For each HTML file the <svg> element is parsed and written as a const ArtEl tree
(every element, id, d, fill, stroke, dash, transform, group membership kept as
authored). The `const CFG = {...}` JSON constant of the script, when present, is
written next to it. Standard library only; output is deterministic.
"""
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter

FILES = [
    ('shield-security.html', 'shield_art_data.dart', 'shieldArt', 'shieldArtCfg'),
    ('network-icons.html', 'network_art_data.dart', 'networkArt', 'networkArtCfg'),
    ('buildings-switching.html', 'buildings_art_data.dart', 'buildingsArt', 'buildingsArtCfg'),
]
SVG_NS = '{http://www.w3.org/2000/svg}'


def dart_str(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$').replace('\n', ' ') + "'"


def strip(tag):
    return tag[len(SVG_NS):] if tag.startswith(SVG_NS) else tag


def emit_el(el, indent):
    pad = '  ' * indent
    attrs = {k: v for k, v in el.attrib.items() if not k.startswith('{http://www.w3.org/2000/xmlns')}
    if 'xmlns' in attrs:
        del attrs['xmlns']
    kids = [c for c in el if isinstance(c.tag, str)]
    a = ', '.join('%s: %s' % (dart_str(k.split('}')[-1]), dart_str(v)) for k, v in attrs.items())
    out = "%s%sArtEl(%s, {%s}" % (pad, '', dart_str(strip(el.tag)), a)
    if kids:
        out += ', [\n' + ',\n'.join(emit_el(c, indent + 1) for c in kids) + ',\n%s]' % pad
    return out + ')'


def extract_cfg(text):
    m = re.search(r'const CFG = ', text)
    if not m:
        return None
    i = m.end()
    depth = 0
    for j in range(i, len(text)):
        if text[j] == '{':
            depth += 1
        elif text[j] == '}':
            depth -= 1
            if depth == 0:
                return json.loads(text[i:j + 1])
    return None


def dart_value(v, indent=0):
    if isinstance(v, dict):
        return '{' + ', '.join('%s: %s' % (dart_str(k), dart_value(x)) for k, x in v.items()) + '}'
    if isinstance(v, list):
        return '[' + ', '.join(dart_value(x) for x in v) + ']'
    if isinstance(v, str):
        return dart_str(v)
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if v is None:
        return 'null'
    return repr(v)


def summarise(root, text):
    els = [e for e in root.iter() if isinstance(e.tag, str)]
    tags = Counter(strip(e.tag) for e in els)
    ids = [e.get('id') for e in els if e.get('id')]
    path_ids = [i for i in ids if re.fullmatch(r'p\d+', i)]
    cols = Counter()
    for e in els:
        for k in ('fill', 'stroke'):
            v = e.get(k)
            if v and v not in ('none',):
                cols[v.upper()] += 1
    for m in re.finditer(r"'(#[0-9A-Fa-f]{6})'", text):
        cols[m.group(1).upper() + ' (js)'] += 1
    dashed = sum(1 for e in els if e.get('stroke-dasharray'))
    return {
        'viewBox': root.get('viewBox'),
        'elements': dict(tags),
        'ids': len(ids),
        'path_ids': len(path_ids),
        'dashed': dashed,
        'colours': dict(sorted(cols.items())),
        'id_list': ids,
    }


DRAWABLE = {'path', 'rect', 'circle', 'ellipse', 'line', 'polygon', 'polyline'}


class Node:
    """A tiny element tree, filled from ElementTree or from a generated Dart file."""

    def __init__(self, tag, attrs, children):
        self.tag = tag
        self.attrs = attrs
        self.children = children


def from_et(el):
    attrs = {k.split('}')[-1]: v for k, v in el.attrib.items() if 'xmlns' not in k}
    return Node(strip(el.tag), attrs, [from_et(c) for c in el if isinstance(c.tag, str)])


def parse_dart_tree(text):
    """Reads back the ArtEl literal this tool writes (format is strict)."""
    i = text.index('ArtEl(')
    pos = [i]

    def ws():
        while text[pos[0]] in ' \n,':
            pos[0] += 1

    def string():
        assert text[pos[0]] == "'"
        pos[0] += 1
        out = []
        while text[pos[0]] != "'":
            if text[pos[0]] == '\\':
                pos[0] += 1
            out.append(text[pos[0]])
            pos[0] += 1
        pos[0] += 1
        return ''.join(out)

    def el():
        assert text.startswith('ArtEl(', pos[0])
        pos[0] += len('ArtEl(')
        tag = string()
        ws()
        assert text[pos[0]] == '{'
        pos[0] += 1
        attrs = {}
        ws()
        while text[pos[0]] != '}':
            k = string()
            ws()
            assert text[pos[0]] == ':'
            pos[0] += 1
            ws()
            attrs[k] = string()
            ws()
        pos[0] += 1
        ws()
        kids = []
        if text[pos[0]] == '[':
            pos[0] += 1
            ws()
            while text[pos[0]] != ']':
                kids.append(el())
                ws()
            pos[0] += 1
            ws()
        assert text[pos[0]] == ')'
        pos[0] += 1
        return Node(tag, attrs, kids)

    return el()


def sig(n):
    return (n.tag, n.attrs.get('id') or '', n.attrs.get('d') or n.attrs.get('x') or '',
            n.attrs.get('fill') or '', n.attrs.get('transform') or '')


def drawables(root):
    """Drawable elements the browser would paint, after resolving <use>, minus
    display=none; plus the drawable content of the clipPaths and masks it references.
    Returns (scene, referenced_defs) as lists of signatures (ids where present)."""
    byid = {}

    def index(n):
        if n.attrs.get('id'):
            byid[n.attrs['id']] = n
        for c in n.children:
            index(c)

    index(root)
    scene, refs, seen_defs = [], [], set()

    def ref_defs(n):
        for key in ('clip-path', 'mask', 'filter'):
            v = n.attrs.get(key)
            m = re.search(r'url\(#([^)]+)\)', v or '')
            if m and m.group(1) not in seen_defs:
                seen_defs.add(m.group(1))
                d = byid.get(m.group(1))
                if d is not None:
                    for c in walk_defs(d):
                        refs.append(sig(c))

    def walk_defs(d):
        for c in d.children:
            if c.tag in DRAWABLE:
                yield c
            elif c.tag == 'use':
                t = byid.get(c.attrs.get('href', '#')[1:])
                if t is not None:
                    yield from walk_defs(Node('g', {}, [t]))
            else:
                yield from walk_defs(c)

    def walk(n):
        if n.attrs.get('display') == 'none':
            return
        ref_defs(n)
        if n.tag in DRAWABLE:
            scene.append(sig(n))
        elif n.tag == 'use':
            t = byid.get(n.attrs.get('href', '#')[1:])
            if t is not None:
                walk(t)
        elif n.tag not in ('defs', 'clipPath', 'mask', 'filter'):
            for c in n.children:
                walk(c)

    walk(root)
    return scene, refs


JS_CREATE = re.compile(r"mk\('(\w+)'|createElementNS\([^,]+,\s*'(\w+)'|cloneNode|innerHTML")


def js_created(text):
    m = re.search(r'<script>(.*)</script>', text, re.S)
    out = Counter()
    if m:
        for g in JS_CREATE.finditer(m.group(1)):
            out[g.group(1) or g.group(2) or g.group(0)] += 1
    return out


def coverage(name, html_root, dart_text, script_text):
    """Compares the HTML with the generated data; returns a list of problems."""
    gen_root = parse_dart_tree(dart_text)
    hs, hr = drawables(html_root)
    gs, gr = drawables(gen_root)
    problems = []
    for label, a, b in (('scene drawables', hs, gs), ('referenced clip/mask drawables', hr, gr)):
        ca, cb = Counter(a), Counter(b)
        miss = list((ca - cb).elements())
        extra = list((cb - ca).elements())
        print('  coverage %s: HTML %d, generated %d' % (label, len(a), len(b)))
        if miss:
            problems.append('%s: %s missing from generated data: %s' % (name, label, [m[1] or m[0] for m in miss][:20]))
        if extra:
            problems.append('%s: %s extra in generated data: %s' % (name, label, [m[1] or m[0] for m in extra][:20]))
    ids_html = Counter(e.attrs['id'] for e in iter_nodes(html_root) if 'id' in e.attrs)
    ids_gen = Counter(e.attrs['id'] for e in iter_nodes(gen_root) if 'id' in e.attrs)
    if ids_html != ids_gen:
        problems.append('%s: ids differ: %s' % (name, sorted(set(ids_html.elements()) ^ set(ids_gen.elements()))))
    dup = [i for i, c in ids_html.items() if c > 1]
    if dup:
        print('  note: duplicate ids in the HTML (a lookup by id keeps the last):', dup)
    print('  created by the script (call sites): %s' % dict(js_created(script_text)))
    return problems


def iter_nodes(n):
    yield n
    for c in n.children:
        yield from iter_nodes(c)


def generate(src, out):
    os.makedirs(out, exist_ok=True)
    report = {}
    problems = []
    for html, dart, name, cfg_name in FILES:
        text = open(os.path.join(src, html), encoding='utf-8').read()
        m = re.search(r'<svg\b.*?</svg>', text, re.S)
        root = ET.fromstring(m.group(0))
        cfg = extract_cfg(text)
        lines = [
            '// GENERATED by tool/onboarding_anim/extract_art.py from %s, do not edit.' % html,
            '// ignore_for_file: lines_longer_than_80_chars',
            '',
            "import '../svg_scene.dart';",
            '',
            'const ArtEl %s =' % name,
            emit_el(root, 1) + ';',
        ]
        if cfg is not None:
            lines += ['', 'const Map<String, Object?> %s = %s;' % (cfg_name, dart_value(cfg))]
        with open(os.path.join(out, dart), 'w', encoding='utf-8', newline='\n') as f:
            f.write('\n'.join(lines) + '\n')
        report[html] = summarise(root, text)
        print('%s' % html)
        problems += coverage(html, from_et(root), '\n'.join(lines), text)
    # The network's symmetric layout (network_tiers.dart) re-places the baked
    # people in the painter: the avatars/badges/links of top, tr, br, bl, l and
    # the 40 background people are intentionally not drawn at their authored
    # spots, so they are expected, not missing; the coverage above is HTML vs data.
    print('network symmetric layout: persons placed by network_tiers.dart (hub c on the axis, left half mirrored); '
          'authored top/tr/br/bl/l positions, the chat link and the lateral links are intentionally unused')
    if problems:
        print('COVERAGE FAILED:')
        for p in problems:
            print('  ' + p)
        sys.exit(1)
    return report


if __name__ == '__main__':
    args = sys.argv[1:]
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.dirname(os.path.dirname(here))
    src = os.path.join(repo, 'incoming', 'onboarding-animations')
    out = os.path.join(repo, 'lib', 'core', 'widgets', 'onboarding_art', 'generated')
    while args:
        a = args.pop(0)
        if a == '--src':
            src = args.pop(0)
        elif a == '--out':
            out = args.pop(0)
    rep = generate(src, out)
    for html, r in rep.items():
        print('%s: viewBox=%s ids=%d path-ids=%d dashed=%d' % (html, r['viewBox'], r['ids'], r['path_ids'], r['dashed']))
        print('  elements:', r['elements'])
        print('  colours:', r['colours'])
