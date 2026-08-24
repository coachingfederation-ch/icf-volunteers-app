#!/usr/bin/env python3
"""Generate the iOS launch (splash) screen images from the official white ICF
logo on the Deep Blue brand background. Produces the 3 required sizes:
  1179x2556 (iPhone 17 / 6.3"), 1284x2778 (Pro Max), 1290x2796 (Plus/Max)."""
from PIL import Image, ImageDraw, ImageFilter

LOGO = "/tmp/icf-logo-white.png"
OUT  = "/Users/hartmuth/Documents/Hermes/icf-volunteer-ios/ICFVolunteers/Assets.xcassets/LaunchImage.launchimage"

sizes = {
    "LaunchImage@3x~iphone.png":        (1290, 2796),
    "LaunchImage@2x~iphone.png":        (1290, 2796),
    "LaunchImage~iphone.png":           (1290, 2796),
}

logo = Image.open(LOGO).convert("RGBA")
lw, lh = logo.size

def render(w, h):
    bg = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(bg)
    for y in range(h):
        t = y / (h - 1)
        r = int(33 + (25 - 33) * t)
        g = int(34 + (28 - 34) * t)
        b = int(81 + (73 - 81) * t)
        d.line([(0, y), (w, y)], fill=(r, g, b, 255))
    # scale logo to ~40% width, centered
    target_w = int(w * 0.40)
    scale = target_w / lw
    nw, nh = int(lw * scale), int(lh * scale)
    lo = logo.resize((nw, nh), Image.LANCZOS)
    bg.alpha_composite(lo, ((w - nw) // 2, (h - nh) // 2))
    return bg

import os
os.makedirs(OUT, exist_ok=True)
for name, (w, h) in sizes.items():
    img = render(w, h)
    p = os.path.join(OUT, name)
    img.save(p)
    print("wrote", p, img.size)
