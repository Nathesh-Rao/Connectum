#!/usr/bin/env python3
"""Re-renders the launcher icons from assets/images/connectum_logo_blue.png (needs Pillow).

Usage: python3 tool/icons/make_icons.py
Writes the Android mipmaps/adaptive layers, the iOS AppIcon set, the Play icon, the
branding/icon sources and the preview sheet. It does not touch the notification icon.
"""
import json, pathlib
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "assets/images/connectum_logo_blue.png"

# TUNE: logo height as a fraction of the icon size (measured from the previous icons).
ADAPTIVE_FG = 0.50      # adaptive foreground and monochrome layers (108dp canvas)
LEGACY = 0.75           # legacy + round mipmaps, iOS set, Play icon
BRAND_FG, BRAND_LEGACY, BRAND_IOS, BRAND_PLAY, BRAND_1024 = 0.54, 0.70, 0.62, 0.62, 0.75
CORNER = 0.17           # legacy launcher corner radius, fraction of size
BG = (255, 255, 255, 255)
SS = 4                  # supersampling

logo = Image.open(SRC).convert("RGBA")


def with_logo(size, frac, bg=None):
    """Canvas of size x size with the logo centred, height = frac * size."""
    big = size * SS
    canvas = Image.new("RGBA", (big, big), bg or (0, 0, 0, 0))
    h = round(big * frac)
    w = round(h * logo.width / logo.height)
    mark = logo.resize((w, h), Image.LANCZOS)
    canvas.alpha_composite(mark, ((big - w) // 2, (big - h) // 2))
    return canvas


def down(img, size):
    return img.resize((size, size), Image.LANCZOS)


def mask(size, shape):
    big = size * SS
    m = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(m)
    if shape == "circle":
        d.ellipse((0, 0, big - 1, big - 1), fill=255)
    elif shape == "rounded":
        d.rounded_rectangle((0, 0, big - 1, big - 1), radius=big * CORNER, fill=255)
    return m


def masked(img, m):
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), m)
    return out


def save(img, path):
    path = ROOT / path
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)


RES = "android/app/src/main/res"
for d, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    icon = with_logo(px, LEGACY, BG)
    save(down(masked(icon, mask(px, "rounded")), px), f"{RES}/mipmap-{d}/ic_launcher.png")
    save(down(masked(icon, mask(px, "circle")), px), f"{RES}/mipmap-{d}/ic_launcher_round.png")
for d, px in {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}.items():
    fg = down(with_logo(px, ADAPTIVE_FG), px)
    save(fg, f"{RES}/drawable-{d}/ic_launcher_foreground.png")
    mono = Image.new("RGBA", fg.size, (255, 255, 255, 0))
    mono.putalpha(fg.getchannel("A"))
    save(mono, f"{RES}/drawable-{d}/ic_launcher_monochrome.png")

colors = ROOT / RES / "values/colors.xml"
colors.write_text(colors.read_text().replace("#FBF8F5", "#FFFFFF"))

ios = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
if ios.exists():
    for e in json.loads((ios / "Contents.json").read_text())["images"]:
        w = float(e["size"].split("x")[0]) * int(e["scale"].rstrip("x"))
        px = round(w)
        save(down(with_logo(px, LEGACY, BG), px).convert("RGB"), (ios / e["filename"]).relative_to(ROOT))

play = down(with_logo(512, LEGACY, BG), 512)
save(play, "design/store/out/play_icon_512.png")
save(down(with_logo(512, BRAND_PLAY, BG), 512), "branding/play_store_icon_512.png")
save(down(with_logo(1024, BRAND_1024), 1024), "branding/icon/connectum_1024_logo.png")
save(down(with_logo(1024, BRAND_FG), 1024), "branding/icon/foreground.png")
save(down(masked(with_logo(1024, BRAND_LEGACY, BG), mask(1024, "rounded")), 1024), "branding/icon/legacy.png")
save(down(with_logo(1024, BRAND_IOS, BG), 1024).convert("RGB"), "branding/icon/ios.png")


def squircle(size):
    big = size * SS
    m = Image.new("L", (big, big), 0)
    px = m.load()
    c, n = big / 2, 4.7
    for y in range(big):
        for x in range(big):
            if abs((x + .5 - c) / c) ** n + abs((y + .5 - c) / c) ** n <= 1:
                px[x, y] = 255
    return m


# Preview sheet: six 192px tiles on grey, as before.
T = 192
fg = down(with_logo(432, ADAPTIVE_FG), 432)
adaptive = Image.new("RGBA", (432, 432), BG)
adaptive.alpha_composite(fg)
window = adaptive.crop((72, 72, 360, 360)).resize((T * SS, T * SS), Image.LANCZOS)  # 72dp of 108dp
mono_fg = Image.new("RGBA", fg.size, (0, 0, 0, 0))
mono_fg.putalpha(fg.getchannel("A"))


def themed(bg, tint):
    tile = Image.new("RGBA", (432, 432), bg)
    layer = Image.new("RGBA", fg.size, tint)
    layer.putalpha(fg.getchannel("A"))
    tile.alpha_composite(layer)
    return tile.crop((72, 72, 360, 360)).resize((T * SS, T * SS), Image.LANCZOS)


legacy_tile = with_logo(T, LEGACY, BG)
tiles = [
    ("adaptive circle", masked(window, mask(T, "circle"))),
    ("adaptive squircle", masked(window, squircle(T))),
    ("adaptive rounded sq", masked(window, mask(T, "rounded").point(lambda v: v))),
    ("legacy", masked(legacy_tile, mask(T, "rounded"))),
    ("themed (light)", masked(themed((237, 229, 249, 255), (82, 69, 121, 255)), mask(T, "circle"))),
    ("themed (dark)", masked(themed((67, 59, 87, 255), (218, 207, 249, 255)), mask(T, "circle"))),
]
sheet = Image.new("RGBA", (1320, 268), (224, 224, 228, 255))
font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 13)
draw = ImageDraw.Draw(sheet)
for i, (label, tile) in enumerate(tiles):
    x = 24 + i * 216
    t = tile.resize((T, T), Image.LANCZOS)
    sheet.alpha_composite(t, (x, 24))
    draw.text((x, 220), label, fill=(0, 0, 0, 255), font=font)
save(sheet, "design/store/out/icon_preview.png")
print("done")
