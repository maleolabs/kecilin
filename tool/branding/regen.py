#!/usr/bin/env python3
"""Regenerate every branded asset from the official logo source.

Run after the official logo is updated:

    python3 tool/branding/regen.py

Source (never edit the generated PNGs by hand):
  kecilin-official-logo.png  as supplied by the brand owner (1254x1254)

Outputs:
  assets/logo/kecilin-header.png          in-app header (wordmark + tagline, alpha)
  res/mipmap-*/ic_launcher_foreground.png adaptive launcher foreground (full artwork)
  res/mipmap-*/ic_launcher.png            legacy launcher icon (full artwork)
  res/drawable-*/splash_icon.png          splash logo, 288dp canvas / 192dp artwork

Design rules:
  * The launcher icon keeps the logo exactly as supplied, including the white to
    mint gradient background. Nothing is keyed out. The adaptive foreground is
    scaled into the inner 72dp safe area so the launcher mask cannot clip the
    wordmark.
  * The splash asset is a 288dp canvas with the artwork inside the middle 192dp,
    so Android 12+ can apply its circular mask without clipping the wordmark.
  * Only the header crop is alpha-keyed, because it sits on a light chip and a
    square gradient card would be unreadable at that size.
"""
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
RES = ROOT / "android" / "app" / "src" / "main" / "res"
SRC = ROOT / "tool" / "branding" / "kecilin-official-logo.png"

# Crops tuned against the 1254x1254 source.
HEADER_CROP = (110, 445, 1234, 824)  # wordmark + "Maleo Labs" tagline
LOCKUP_CROP = (0, 430, 1254, 1254)  # wordmark + tagline + mint texture

# 2px of export artifact (a grey hairline) around the top/left/right edges.
ARTIFACT_TRIM = 2

# Launcher: 108dp adaptive canvas / 48dp legacy icon.
# The system only guarantees the inner 72dp of the adaptive canvas is visible
# (the outer 18dp is parallax/bleed), so the artwork is scaled into that square.
# At 72dp the wordmark still clears the circular mask by ~7dp per side.
LAUNCHER_DP = [("mdpi", 1.0), ("hdpi", 1.5), ("xhdpi", 2.0),
               ("xxhdpi", 3.0), ("xxxhdpi", 4.0)]
ADAPTIVE_DP = 108
ADAPTIVE_SAFE_DP = 72
LEGACY_DP = 48

# Splash: 288dp canvas with the artwork inside the middle 160dp.
# Android 12+ masks the splash icon to a circle of roughly 190dp; at 160dp the
# whole lockup (including the mint texture) stays inside that circle.
SPLASH_CANVAS_DP = 288
SPLASH_ART_DP = 160

# In-app header: 40dp tall, so 160px is enough for a 4x screen.
HEADER_MAX_HEIGHT_PX = 160


def to_alpha(im, k=8.0):
    """Near-white background -> transparent, edges anti-aliased."""
    im = im.convert("RGB")
    out = Image.new("RGBA", im.size)
    sp, op = im.load(), out.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b = sp[x, y]
            op[x, y] = (r, g, b, min(255, int((255 - min(r, g, b)) * k)))
    return out


def dark_variant(im):
    """Recolor the wordmark for dark backgrounds.

    The header artwork is keyed for a light chip: navy wordmark, grey tagline.
    On a dark surface (GitHub dark theme, dark documentation sites) that navy
    all but disappears. Cool-hue pixels are remapped to neutral light greys by
    luminance; the teal accent is left alone, because the brand colour is the
    one thing that must not drift between the two variants.
    """
    out = im.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a == 0 or b <= g + 5:  # transparent, or the teal accent
                continue
            luma = 0.299 * r + 0.587 * g + 0.114 * b
            px[x, y] = (230, 237, 243, a) if luma < 90 else (154, 164, 178, a)
    return out


def scaled(im, width):
    return im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)


def main():
    src = Image.open(SRC).convert("RGB")
    w, h = src.size
    if (w, h) != (1254, 1254):
        print(f"WARNING: source is {w}x{h}, crops were tuned for 1254x1254",
              file=sys.stderr)
        trim = 0
    else:
        trim = ARTIFACT_TRIM

    # Full artwork, background and gradient untouched.
    full = src.crop((trim, trim, w - trim, h - trim))

    lockup = to_alpha(src.crop(LOCKUP_CROP))
    header = to_alpha(src.crop(HEADER_CROP))

    # The header renders at 40dp; 160px covers xxxhdpi (4x) without upscaling.
    # The full 1124x379 crop shipped ~365 KB of APK for pixels no device could
    # ever display.
    if header.height > HEADER_MAX_HEIGHT_PX:
        header = header.resize(
            (round(header.width * HEADER_MAX_HEIGHT_PX / header.height),
             HEADER_MAX_HEIGHT_PX),
            Image.LANCZOS,
        )

    (ROOT / "assets" / "logo").mkdir(parents=True, exist_ok=True)
    header.save(ROOT / "assets" / "logo" / "kecilin-header.png", optimize=True)
    lockup.save(ROOT / "tool" / "branding" / "kecilin-lockup.png")

    # README hero, dark-theme companion. Documentation-only, never bundled.
    docs_brand = ROOT / "docs" / "assets" / "brand"
    docs_brand.mkdir(parents=True, exist_ok=True)
    dark_variant(header).save(docs_brand / "kecilin-logo-dark.png", optimize=True)

    for dpi, scale in LAUNCHER_DP:
        out = RES / f"mipmap-{dpi}"
        out.mkdir(parents=True, exist_ok=True)

        adaptive_px = round(ADAPTIVE_DP * scale)
        safe_px = round(ADAPTIVE_SAFE_DP * scale)
        canvas = Image.new("RGBA", (adaptive_px, adaptive_px), (0, 0, 0, 0))
        art = scaled(full, safe_px).convert("RGBA")
        canvas.alpha_composite(art, ((adaptive_px - art.width) // 2,
                                     (adaptive_px - art.height) // 2))
        canvas.save(out / "ic_launcher_foreground.png")

        legacy_px = round(LEGACY_DP * scale)
        scaled(full, legacy_px).save(out / "ic_launcher.png")

        splash_dir = RES / f"drawable-{dpi}"
        splash_dir.mkdir(parents=True, exist_ok=True)
        canvas_px = round(SPLASH_CANVAS_DP * scale)
        art_px = round(SPLASH_ART_DP * scale)
        splash = Image.new("RGBA", (canvas_px, canvas_px), (0, 0, 0, 0))
        art = scaled(lockup, art_px)
        splash.alpha_composite(art, ((canvas_px - art.width) // 2,
                                     (canvas_px - art.height) // 2))
        splash.save(splash_dir / "splash_icon.png")

    print("branded assets regenerated")


if __name__ == "__main__":
    main()
