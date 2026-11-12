#!/usr/bin/env python3
"""Writes name_blue.json next to each Lottie that holds warm colours or has
violet rules below.

1. Maps every orange, peach, brown, sand or olive colour to a role of the blue
   palette (listed below) and leaves other colours alone; the ivory page tone
   becomes pure white (the page is white).
2. Then turns a subset of the lighter blues into violet #8B5CF6 and purple
   #6A3FD4 (VIOLET_RULES: colour, step, offset, target; the n-th occurrence of
   a colour, in file order, matches when n % step == offset). The bright blue
   stays the main colour. Prints the mapping and the violet share.

Originals are never touched. Run from the repo root: python3 tool/lottie/recolor_lottie.py
"""
import colorsys
import glob
import json
import os
import sys

# Explicit mapping (hex of the old colour -> hex of the new role).
EXPLICIT = {
    "FF700F": "0078E8", "F66510": "0078E8",  # orange -> primaryBright
    "FF8E3A": "0078E8",
    "FFA96E": "00B4F1", "FCB080": "00B4F1", "FA9558": "00B4F1",  # light orange -> primaryLight
    "FFD0B0": "BDD2F2",  # apricot -> primaryBorder
    "FFE5D2": "D6E3F7",  # peach -> primaryTintStrong
    "F5E7D8": "E6EEFA",  # sand -> primaryTint
    "FFF8F1": "FFFFFF",  # ivory -> white page
    "D8D0C5": "CBD5E4",  # taupe -> slateLight
    "7E8965": "5B6B91",  # olive -> slate blue
    "ABAD95": "A9B4C8", "C6C2B2": "C4CCDA", "D8D7C7": "D5DBE6",  # olive greys -> cool greys
    "1C0311": "071F50",  # near-black magenta -> ink
    "D3CDA6": "BDD2F2", "FEF5BD": "C9ECFC",  # sage / pale yellow -> tints
}
ROLES = ["0078E8", "00B4F1", "BDD2F2", "D6E3F7", "E6EEFA", "FFFFFF", "0052CC", "00338D"]

VIOLET = "8B5CF6"
PURPLE = "6A3FD4"
# file stem -> [(blue hex, step, offset, violet/purple hex)]
VIOLET_RULES = {
    "loading": [("0078E8", 4, 0, PURPLE), ("00B4F1", 1, 0, VIOLET)],
    "qr_loading": [("0078E8", 6, 1, VIOLET), ("0078E8", 6, 4, PURPLE)],
}
# Onboarding is blue only: the same step rules, but the accents are blues
# (cyanBlue #00A1E8, primary #0052CC, primaryStrong #00338D, primaryLight
# #00B4F1), so the slides keep their depth without violet or purple.
CYAN, PRIMARY, STRONG, LIGHT = "00A1E8", "0052CC", "00338D", "00B4F1"
BLUE_ONLY_RULES = {
    "onboarding_enterprises": [
        ("0078E8", 3, 0, CYAN), ("0078E8", 6, 1, PRIMARY), ("0078E8", 9, 5, STRONG),
        ("BDD2F2", 6, 2, LIGHT),
    ],
    "onboarding_network": [
        ("0078E8", 4, 1, CYAN), ("0078E8", 8, 3, PRIMARY), ("0078E8", 8, 6, STRONG),
        ("00B4F1", 2, 0, CYAN),
    ],
    "onboarding_security": [
        ("0078E8", 3, 1, PRIMARY), ("0078E8", 3, 0, CYAN), ("0078E8", 9, 2, STRONG),
        ("D6E3F7", 4, 0, "BDD2F2"),
    ],
}
# Safeguard: any violet/purple colour left in an onboarding file goes to the
# blue of the nearest luminance.
BLUE_LADDER = ["00338D", "0052CC", "0078E8", "00A1E8", "00B4F1", "BDD2F2",
               "D6E3F7", "E6EEFA"]
BLUE_FAMILY = {"0078E8", "00B4F1", "BDD2F2", "D6E3F7", "E6EEFA", "0052CC",
               "00338D", "C9ECFC"}


def is_warm(rgb):
    h, l, s = colorsys.rgb_to_hls(*[c / 255 for c in rgb])
    return 5 <= h * 360 <= 62 and s > 0.15


def lum(rgb):
    return colorsys.rgb_to_hls(*[c / 255 for c in rgb])[1]


def to_hex(rgb):
    return "%02X%02X%02X" % tuple(rgb)


def from_hex(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def is_violet(rgb):
    h, l, s = colorsys.rgb_to_hls(*[c / 255 for c in rgb])
    return 245 <= h * 360 <= 300 and s > 0.1


def map_color(rgb, log, blue_only=False):
    key = to_hex(rgb)
    if blue_only and is_violet(rgb):
        new = min(BLUE_LADDER, key=lambda r: abs(lum(from_hex(r)) - lum(rgb)))
    elif key in EXPLICIT:
        new = EXPLICIT[key]
    elif is_warm(rgb):
        new = min(ROLES, key=lambda r: abs(lum(from_hex(r)) - lum(rgb)))
    else:
        return None
    log[key] = new
    return [c / 255 for c in from_hex(new)]


def recolor_stops(values, count, log, blue_only=False):
    """Gradient stops are [offset, r, g, b] * count, then optional alpha stops."""
    for i in range(count):
        at = i * 4
        if at + 3 >= len(values):
            break
        new = map_color([round(x * 255) for x in values[at + 1:at + 4]], log, blue_only)
        if new:
            values[at + 1:at + 4] = new


def recolor_gradient(node, log, blue_only=False):
    count = node["g"]["p"]
    k = node["g"]["k"].get("k")
    if isinstance(k, list) and k and isinstance(k[0], (int, float)):
        recolor_stops(k, count, log, blue_only)
    elif isinstance(k, list):
        for kf in k:
            for field in ("s", "e"):
                if isinstance(kf, dict) and isinstance(kf.get(field), list):
                    recolor_stops(kf[field], count, log, blue_only)


def recolor(node, log, blue_only=False):
    if isinstance(node, dict):
        if node.get("ty") in ("gf", "gs") and isinstance(node.get("g"), dict):
            recolor_gradient(node, log, blue_only)
        if node.get("ty") in ("fl", "st") and isinstance(node.get("c"), dict):
            k = node["c"].get("k")
            if isinstance(k, list) and k and isinstance(k[0], (int, float)):
                new = map_color([round(x * 255) for x in k[:3]], log, blue_only)
                if new:
                    node["c"]["k"] = new + k[3:]
            elif isinstance(k, list):
                for kf in k:
                    for field in ("s", "e"):
                        v = kf.get(field) if isinstance(kf, dict) else None
                        if isinstance(v, list) and len(v) >= 3:
                            new = map_color([round(x * 255) for x in v[:3]], log, blue_only)
                            if new:
                                kf[field] = new + v[3:]
        for v in node.values():
            recolor(v, log, blue_only)
    elif isinstance(node, list):
        for v in node:
            recolor(v, log, blue_only)


def accent(node, rules, counts, log, tally):
    """Static fills, strokes and gradient stops only (animated colours stay)."""

    def pick(rgb):
        key = to_hex(rgb)
        if key not in BLUE_FAMILY and key not in (VIOLET, PURPLE):
            return None
        tally["blue"] += 1
        n = counts.get(key, 0)
        counts[key] = n + 1
        for colour, step, offset, target in rules:
            if colour == key and n % step == offset:
                log[(key, target)] = log.get((key, target), 0) + 1
                tally["violet"] += 1
                return [c / 255 for c in from_hex(target)]
        return None

    if isinstance(node, dict):
        if node.get("ty") in ("fl", "st") and isinstance(node.get("c"), dict):
            k = node["c"].get("k")
            if isinstance(k, list) and k and isinstance(k[0], (int, float)):
                new = pick([round(x * 255) for x in k[:3]])
                if new:
                    node["c"]["k"] = new + k[3:]
        if node.get("ty") in ("gf", "gs") and isinstance(node.get("g"), dict):
            k = node["g"]["k"].get("k")
            if isinstance(k, list) and k and isinstance(k[0], (int, float)):
                for i in range(node["g"]["p"]):
                    at = i * 4
                    new = pick([round(x * 255) for x in k[at + 1:at + 4]])
                    if new:
                        k[at + 1:at + 4] = new
        for v in node.values():
            accent(v, rules, counts, log, tally)
    elif isinstance(node, list):
        for v in node:
            accent(v, rules, counts, log, tally)


def main():
    root = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "lottie")
    for path in sorted(glob.glob(os.path.join(root, "*.json"))):
        if path.endswith("_blue.json"):
            continue
        with open(path) as f:
            data = json.load(f)
        log = {}
        stem = os.path.basename(path)[:-5]
        blue_only = stem in BLUE_ONLY_RULES
        recolor(data, log, blue_only)
        rules = BLUE_ONLY_RULES.get(stem) or VIOLET_RULES.get(stem)
        violet_log, tally = {}, {"blue": 0, "violet": 0}
        if rules:
            accent(data, rules, {}, violet_log, tally)
        if not log and not violet_log:
            print("unchanged (no warm colours, no violet rules):", os.path.basename(path))
            continue
        out = path[:-5] + "_blue.json"
        with open(out, "w") as f:
            json.dump(data, f, separators=(",", ":"))
        print(os.path.basename(out))
        for old, new in sorted(log.items()):
            print("   #%s -> #%s" % (old, new))
        for (old, new), n in sorted(violet_log.items()):
            print("   #%s -> #%s  x%d (%s)" % (old, new, n, "blue accent" if blue_only else "violet"))
        if rules:
            print("   accent share: %d of %d blue-family colours (%.0f%%)" % (
                tally["violet"], tally["blue"], 100 * tally["violet"] / max(1, tally["blue"])))

if __name__ == "__main__":
    sys.exit(main())
