#!/usr/bin/env python3
"""Generates lib/core/widgets/logo_intro/logo_intro_data.dart from design/brand/connectum_logo_animated.svg.

Usage: python3 tool/logo/generate_logo_intro_data.py [svg] [out] [--check]
The first 57 filled paths are the C parts, the last path is the wordmark. The output is
deterministic. It fails (non-zero exit) on an unsupported path command or when the
expected structure (big / top parts) does not hold. No dependencies.
"""
import math, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_SVG = ROOT / "design/brand/connectum_logo_animated.svg"
DEFAULT_OUT = ROOT / "lib/core/widgets/logo_intro/logo_intro_data.dart"

# Keep in step with the TUNE ME block of logo_intro.dart (only used for the table here).
GROW_A, GROW_SPAN = 550, 1000
SEED_BEHIND = 24.0
HEAD_FRACTION = 0.42
TOP_S = 0.10
EXPECT_PARTS, EXPECT_TOP_END, EXPECT_BIG, EXPECT_TOP = 57, 2, {32}, {2, 7, 8, 9}
SAMPLES = 48

OP_MOVE, OP_LINE, OP_CUBIC, OP_QUAD, OP_CLOSE = 0, 1, 2, 3, 4
ARGS = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "Z": 0}


def die(msg):
    sys.exit("generate_logo_intro_data: " + msg)


def parse_path(d):
    """Absolute commands: list of (op, [numbers])."""
    toks = re.findall(r"[A-Za-z]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?", d)
    out, i, cmd = [], 0, None
    x = y = sx = sy = 0.0
    last_c = None  # last cubic second control point, for S
    while i < len(toks):
        if toks[i].isalpha():
            cmd = toks[i]
            i += 1
            if cmd.upper() not in ARGS:
                die("unsupported path command " + cmd)
            if cmd.upper() == "Z":
                out.append((OP_CLOSE, []))
                x, y = sx, sy
                last_c = None
                continue
        elif cmd is None:
            die("path data starts with a number")
        up, rel = cmd.upper(), cmd.islower()
        n = ARGS[up]
        if n == 0 or i + n > len(toks):
            die("bad argument count for " + cmd)
        a = [float(t) for t in toks[i:i + n]]
        i += n
        if up == "H":
            a = [a[0] + (x if rel else 0), y]
            up = "L"
        elif up == "V":
            a = [x, a[0] + (y if rel else 0)]
            up = "L"
        elif rel:
            a = [v + (x if k % 2 == 0 else y) for k, v in enumerate(a)]
        if up == "M":
            out.append((OP_MOVE, a))
            sx, sy = a
            cmd = "l" if rel else "L"  # extra pairs after M are lineto
            last_c = None
        elif up == "L":
            out.append((OP_LINE, a))
            last_c = None
        elif up == "C":
            out.append((OP_CUBIC, a))
            last_c = (a[2], a[3])
        elif up == "S":
            c1 = (2 * x - last_c[0], 2 * y - last_c[1]) if last_c else (x, y)
            a = [c1[0], c1[1]] + a
            out.append((OP_CUBIC, a))
            last_c = (a[2], a[3])
        elif up == "Q":
            out.append((OP_QUAD, a))
            last_c = None
        x, y = a[-2], a[-1]
    return out


def control_bbox(cmds):
    xs, ys = [], []
    for op, a in cmds:
        xs += a[0::2]
        ys += a[1::2]
    return min(xs), min(ys), max(xs), max(ys)


def flatten(cmds):
    """Polylines (one per subpath)."""
    subs, cur, x, y = [], [], 0.0, 0.0
    sx = sy = 0.0
    for op, a in cmds:
        if op == OP_MOVE:
            if len(cur) > 1:
                subs.append(cur)
            x, y = a
            sx, sy = x, y
            cur = [(x, y)]
        elif op == OP_LINE:
            x, y = a
            cur.append((x, y))
        elif op == OP_CUBIC:
            x0, y0 = x, y
            for k in range(1, 17):
                t = k / 16
                u = 1 - t
                cur.append((
                    u**3 * x0 + 3 * u * u * t * a[0] + 3 * u * t * t * a[2] + t**3 * a[4],
                    u**3 * y0 + 3 * u * u * t * a[1] + 3 * u * t * t * a[3] + t**3 * a[5]))
            x, y = a[4], a[5]
        elif op == OP_QUAD:
            x0, y0 = x, y
            for k in range(1, 17):
                t = k / 16
                u = 1 - t
                cur.append((u * u * x0 + 2 * u * t * a[0] + t * t * a[2],
                            u * u * y0 + 2 * u * t * a[1] + t * t * a[3]))
            x, y = a[2], a[3]
        else:
            if cur:
                cur.append((sx, sy))
            x, y = sx, sy
    if len(cur) > 1:
        subs.append(cur)
    return subs


def sample_outline(cmds, n):
    pts = [p for sub in flatten(cmds) for p in zip(sub, sub[1:])]
    lens = [math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in pts]
    total = sum(lens)
    if total <= 0:
        die("empty outline")
    out, acc, j = [], 0.0, 0
    for k in range(n):
        target = total * k / n
        while j < len(lens) - 1 and acc + lens[j] < target:
            acc += lens[j]
            j += 1
        t = 0 if lens[j] == 0 else (target - acc) / lens[j]
        a, b = pts[j]
        out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def num(v):
    r = round(v, 4)
    return repr(0.0 if r == 0 else r)


def build(svg_text):
    paths = re.findall(r'<path\s+d="([^"]*)"\s+fill="([^"]*)"', svg_text)
    if len(paths) != EXPECT_PARTS + 1:
        die("expected %d paths, found %d" % (EXPECT_PARTS + 1, len(paths)))
    vb = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', svg_text)
    vw, vh = float(vb.group(1)), float(vb.group(2))
    parts = []
    for i, (d, fill) in enumerate(paths[:EXPECT_PARTS]):
        if not re.fullmatch(r"#[0-9A-Fa-f]{6}", fill):
            die("part %d has fill %s" % (i, fill))
        cmds = parse_path(d)
        l, t, r, b = control_bbox(cmds)
        parts.append(dict(i=i, fill=int("FF" + fill[1:], 16), cmds=cmds, l=l, t=t, r=r, b=b,
                          fx=(l + r) / 2, fy=(t + b) / 2))
    word = parse_path(paths[-1][0])
    wl, wt, wr, wb = control_bbox(word)

    cx = (min(p["l"] for p in parts) + max(p["r"] for p in parts)) / 2
    cy = (min(p["t"] for p in parts) + max(p["b"] for p in parts)) / 2

    def ang(x, y):
        return math.degrees(math.atan2(cy - y, x - cx)) % 360

    cands = [p for p in parts if p["fx"] > cx and p["fy"] < cy]
    top = max(cands, key=lambda p: (p["r"] - p["l"]) * (p["b"] - p["t"]))
    if top["i"] != EXPECT_TOP_END:
        die("top-end part is %d, expected %d" % (top["i"], EXPECT_TOP_END))
    a_top = ang(top["fx"], top["fy"])
    a0 = a_top - 40

    def rel(a):
        return ((a - a0) % 360 + 360) % 360

    for p in parts:
        rels = [rel(ang(x, y)) for x, y in sample_outline(p["cmds"], SAMPLES)]
        rels = [v for v in rels if v < 345]
        if not rels:
            die("part %d has no outline points with rel < 345" % p["i"])
        p["rmin"], p["rmax"] = min(rels), max(rels)
        p["rc"] = rel(ang(p["fx"], p["fy"]))
    rmax_all = max(p["rmax"] for p in parts)
    for p in parts:
        p["big"] = (p["rmax"] - p["rmin"]) / rmax_all > 0.25
        base = (p["rmin"] / rmax_all if p["big"] else
                max(p["rmin"] / rmax_all, min(p["rc"], p["rmax"]) / rmax_all - 0.03))
        p["s"] = base + p["i"] * 0.0004
        p["top"] = p["s"] < TOP_S
        p["tstart"] = GROW_A + p["s"] * GROW_SPAN
        if p["top"]:
            p["sx"] = p["sy"] = None
        else:
            R = math.hypot(p["fx"] - cx, p["fy"] - cy)
            th = math.radians(a0 + p["rmin"] if p["big"] else ang(p["fx"], p["fy"]) - SEED_BEHIND)
            p["sx"], p["sy"] = cx + R * math.cos(th), cy - R * math.sin(th)

    print(" idx  fill     big  top  s        tStart")
    for p in parts:
        print("%4d  %06X  %-4s %-4s %.4f  %7.1f" % (
            p["i"], p["fill"] & 0xFFFFFF, "BIG" if p["big"] else "", "TOP" if p["top"] else "",
            p["s"], p["tstart"]))
    big = {p["i"] for p in parts if p["big"]}
    tops = {p["i"] for p in parts if p["top"]}
    if big != EXPECT_BIG:
        die("big parts %s, expected %s" % (sorted(big), sorted(EXPECT_BIG)))
    if tops != EXPECT_TOP:
        die("top parts %s, expected %s" % (sorted(tops), sorted(EXPECT_TOP)))

    hr = HEAD_FRACTION * min(top["r"] - top["l"], top["b"] - top["t"])
    lines = [
        "// GENERATED by tool/logo/generate_logo_intro_data.py from",
        "// design/brand/connectum_logo_animated.svg. Do not edit by hand.",
        "// Ops: 0 move(x y) 1 line(x y) 2 cubic(c1 c2 end) 3 quad(c end) 4 close.",
        "// Bounds are the control-point bounds (what Path.getBounds returns).",
        "",
        "class LogoIntroPart {",
        "  const LogoIntroPart({",
        "    required this.fill,",
        "    required this.ops,",
        "    required this.left,",
        "    required this.top,",
        "    required this.right,",
        "    required this.bottom,",
        "    required this.s,",
        "    required this.isBig,",
        "    required this.isTop,",
        "    required this.seedX,",
        "    required this.seedY,",
        "  });",
        "",
        "  final int fill;",
        "  final List<double> ops;",
        "  final double left, top, right, bottom;",
        "",
        "  /// Start order in 0..1 (add growA + s * growSpan for the start time).",
        "  final double s;",
        "  final bool isBig, isTop;",
        "",
        "  /// Where the part grows from; null for the top group (starts at the head circle).",
        "  final double? seedX, seedY;",
        "",
        "  double get focusX => (left + right) / 2;",
        "  double get focusY => (top + bottom) / 2;",
        "}",
        "",
        "const double logoIntroWidth = %s;" % num(vw),
        "const double logoIntroHeight = %s;" % num(vh),
        "const double logoIntroCenterX = %s;" % num(cx),
        "const double logoIntroCenterY = %s;" % num(cy),
        "const double logoIntroHeadX = %s;" % num(top["fx"]),
        "const double logoIntroHeadY = %s;" % num(top["fy"]),
        "const double logoIntroHeadRadius = %s;" % num(hr),
        "const double logoIntroTextLeft = %s;" % num(wl),
        "const double logoIntroTextTop = %s;" % num(wt),
        "const double logoIntroTextRight = %s;" % num(wr),
        "const double logoIntroTextBottom = %s;" % num(wb),
        "const double logoIntroTextCenterX = %s;" % num((wl + wr) / 2),
        "const double logoIntroTextCenterY = %s;" % num((wt + wb) / 2),
        "",
        "const List<double> logoIntroTextOps = <double>[%s];" % flat(word),
        "",
        "const List<LogoIntroPart> logoIntroParts = <LogoIntroPart>[",
    ]
    for p in parts:
        lines += [
            "  LogoIntroPart(",
            "    fill: 0x%08X," % p["fill"],
            "    ops: <double>[%s]," % flat(p["cmds"]),
            "    left: %s, top: %s, right: %s, bottom: %s," % (
                num(p["l"]), num(p["t"]), num(p["r"]), num(p["b"])),
            "    s: %s," % num(p["s"]),
            "    isBig: %s, isTop: %s," % (str(p["big"]).lower(), str(p["top"]).lower()),
            "    seedX: %s, seedY: %s," % ((num(p["sx"]), num(p["sy"])) if p["sx"] is not None
                                           else ("null", "null")),
            "  ),",
        ]
    lines += ["];", ""]
    return "\n".join(lines)


def flat(cmds):
    vals = []
    for op, a in cmds:
        vals.append(num(op))
        vals += [num(v) for v in a]
    return ", ".join(vals)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    svg = pathlib.Path(args[0]) if args else DEFAULT_SVG
    out = pathlib.Path(args[1]) if len(args) > 1 else DEFAULT_OUT
    text = build(svg.read_text())
    if "--check" in sys.argv:
        if out.read_text() != text:
            die("%s is out of date" % out)
        print("up to date")
        return
    out.write_text(text)
    print("wrote", out)


if __name__ == "__main__":
    main()
