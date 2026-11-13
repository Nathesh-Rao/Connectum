#!/usr/bin/env python3
"""Recolour lib/core/widgets/logo_loader/logo_data.dart from an SVG with the same 57 paths.

Usage: python3 tool/logo/recolor_logo_data.py [svg] [--check]
Default svg: design/brand/connectum_logo_blue.svg. Verifies that the SVG matches the
geometry already in logo_data.dart (same path count/order, bounding boxes equal after one
uniform scale + translate, 1 % tolerance), then rewrites only the colour ints.
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
DART = ROOT / "lib/core/widgets/logo_loader/logo_data.dart"
DEFAULT_SVG = ROOT / "design/brand/connectum_logo_blue.svg"
TOL = 0.01
NUM = re.compile(r"-?\d*\.?\d+(?:e-?\d+)?", re.I)


def bbox(points):
    xs, ys = zip(*points)
    return min(xs), min(ys), max(xs), max(ys)


def svg_points(d):
    """All anchor and control points of an absolute/relative M, L, H, V, C, Z path."""
    pts, cmd, nums, cur = [], None, [], (0.0, 0.0)
    for tok in re.findall(r"[A-Za-z]|-?\d*\.?\d+(?:e-?\d+)?", d):
        if tok.isalpha():
            cmd = tok
            continue
        per = {"M": 2, "L": 2, "C": 6, "H": 1, "V": 1}.get(cmd.upper() if cmd else "")
        if per is None:
            raise SystemExit(f"unsupported SVG command {cmd}")
        nums.append(float(tok))
        if len(nums) == per:
            ox, oy = cur if cmd.islower() else (0.0, 0.0)
            if cmd.upper() == "H":
                pts.append((nums[0] + ox, cur[1]))
            elif cmd.upper() == "V":
                pts.append((cur[0], nums[0] + oy))
            else:
                for i in range(0, per, 2):
                    pts.append((nums[i] + ox, nums[i + 1] + oy))
            cur = pts[-1]
            nums = []
            if cmd.upper() == "M":
                cmd = "l" if cmd.islower() else "L"
    return pts


def dart_paths(src):
    body = src.split("buildOriginalPaths()", 1)[1].split("];", 1)[0]
    paths = []
    for line in body.splitlines():
        if "Path()" not in line:
            continue
        pts = []
        for m in re.finditer(r"\.\.(?:moveTo|lineTo|cubicTo)\(([^)]*)\)", line):
            v = [float(x) for x in m.group(1).split(",")]
            pts += [(v[i], v[i + 1]) for i in range(0, len(v), 2)]
        paths.append(pts)
    return paths


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check_only = "--check" in sys.argv
    svg_file = pathlib.Path(args[0]) if args else DEFAULT_SVG
    svg = svg_file.read_text()
    items = re.findall(r"<path\b[^>]*>", svg)
    d_list = [re.search(r'\bd="([^"]+)"', p).group(1) for p in items]
    fills = [re.search(r'\bfill="(#[0-9A-Fa-f]{6})"', p).group(1).upper() for p in items]
    src = DART.read_text()
    old = dart_paths(src)
    if len(d_list) != len(old):
        raise SystemExit(f"MISMATCH: svg has {len(d_list)} paths, logo_data.dart has {len(old)}")
    new = [bbox(svg_points(d)) for d in d_list]
    olb = [bbox(p) for p in old]
    ox0, oy0 = min(b[0] for b in olb), min(b[1] for b in olb)
    ox1, oy1 = max(b[2] for b in olb), max(b[3] for b in olb)
    nx0, ny0 = min(b[0] for b in new), min(b[1] for b in new)
    nx1, ny1 = max(b[2] for b in new), max(b[3] for b in new)
    sx, sy = (nx1 - nx0) / (ox1 - ox0), (ny1 - ny0) / (oy1 - oy0)
    print(f"overall scale x={sx:.5f} y={sy:.5f} (uniform diff {abs(sx - sy) / sx * 100:.3f} %)")
    worst, bad = 0.0, []
    for i, (o, n) in enumerate(zip(olb, new)):
        pred = ((o[0] - ox0) * sx + nx0, (o[1] - oy0) * sy + ny0, (o[2] - ox0) * sx + nx0, (o[3] - oy0) * sy + ny0)
        err = max(abs(a - b) for a, b in zip(pred, n)) / max(nx1 - nx0, ny1 - ny0)
        worst = max(worst, err)
        if err > TOL:
            bad.append((i + 1, err))
    print(f"paths {len(d_list)}; worst bbox error {worst * 100:.3f} % of logo size")
    if abs(sx - sy) / sx > TOL or bad:
        raise SystemExit(f"MISMATCH: uniform={abs(sx - sy) / sx <= TOL}, bad paths={bad}")
    if check_only:
        return
    it = iter(fills)
    def sub(m):
        return f"LogoPoly(0xFF{next(it)[1:]}, // el-"
    out = re.sub(r"LogoPoly\(0x[0-9A-Fa-f]{8}, // el-", sub, src, count=len(fills))
    out = re.sub(r"^// GENERATED FILE.*$", "// GENERATED FILE – geometry derived from the original logo SVG (57 paths, 1024×1024); colours from design/brand/connectum_logo_blue.svg via tool/logo/recolor_logo_data.py. Do not edit by hand.", out, count=1, flags=re.M)
    DART.write_text(out)
    print("recoloured", len(fills), "polygons")


main()
