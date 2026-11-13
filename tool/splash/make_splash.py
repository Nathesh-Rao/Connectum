#!/usr/bin/env python3
"""Re-renders the native splash logo from assets/images/connectum_logo_blue.png (needs Pillow).

Usage: python3 tool/splash/make_splash.py
Writes android drawable-*/splash_logo.png (pre-Android 12 launch_background), the
Android 12+ splash icon drawable-*/splash_icon.png (288 dp canvas, logo inside the
192 dp circular mask) and the iOS LaunchImage 1x/2x/3x. LOGO_SCALE scales the logo from
its original size (148 x 154 dp). LOGO_SCALE = 0 writes a BLANK native splash (fully
transparent images, white background from splash_background / the storyboard).
Does not touch the launcher or notification icons.
"""
import pathlib
import re
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "assets/images/connectum_logo_blue.png"
RES = ROOT / "android/app/src/main/res"
IOS = ROOT / "ios/Runner/Assets.xcassets/LaunchImage.imageset"
STORYBOARD = ROOT / "ios/Runner/Base.lproj/LaunchScreen.storyboard"

LOGO_SCALE = 0.6        # TUNE ME: native logo size relative to the original; 0 = blank splash
BASE_W, BASE_H = 148, 154   # dp of the original splash logo
ICON_CANVAS = 288       # dp, Android 12 splash icon (no icon background)
ANDROID = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
IOS_SCALES = {"": 1, "@2x": 2, "@3x": 3}

logo = Image.open(SRC).convert("RGBA")


def sized(density):
    if LOGO_SCALE == 0:
        return (1, 1)
    return (round(BASE_W * LOGO_SCALE * density), round(BASE_H * LOGO_SCALE * density))


def scaled(density):
    if LOGO_SCALE == 0:
        return Image.new("RGBA", (1, 1), (0, 0, 0, 0))
    return logo.resize(sized(density), Image.LANCZOS)


for name, d in ANDROID.items():
    out = RES / f"drawable-{name}"
    scaled(d).save(out / "splash_logo.png", optimize=True)
    side = round(ICON_CANVAS * d)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    if LOGO_SCALE != 0:
        mark = scaled(d)
        canvas.alpha_composite(mark, ((side - mark.width) // 2, (side - mark.height) // 2))
    canvas.save(out / "splash_icon.png", optimize=True)
    print(name, "splash_logo", sized(d), "splash_icon", (side, side))

for suffix, d in IOS_SCALES.items():
    scaled(d).save(IOS / f"LaunchImage{suffix}.png", optimize=True)
    print("ios", suffix or "1x", sized(d))
w, h = sized(1)
text = STORYBOARD.read_text()
text = re.sub(r'(<image name="LaunchImage" width=")\d+(" height=")\d+(")', rf"\g<1>{w}\g<2>{h}\g<3>", text)
STORYBOARD.write_text(text)
print("iOS storyboard <image> size: %d x %d" % (w, h))
