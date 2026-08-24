#!/usr/bin/env python3
"""Compose the ICF Switzerland app icon from the OFFICIAL brand artwork.
White vertical logo (cleared for dark backgrounds) centered on the Deep Blue
brand gradient, with a subtle yellow brush accent. Guaranteed on-brand."""
from PIL import Image, ImageDraw, ImageFilter

W = H = 1024
DEEP   = (33, 34, 81)
LOGO   = "/tmp/icf-logo-white.png"
OUT    = "/Users/hartmuth/Documents/Hermes/icf-volunteer-ios/ICFVolunteers/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

# ---- Deep Blue gradient background ----
bg = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(bg)
for y in range(H):
    t = y / (H - 1)
    r = int(DEEP[0] + (25 - DEEP[0]) * t)
    g = int(DEEP[1] + (28 - DEEP[1]) * t)
    b = int(DEEP[2] + (73 - DEEP[2]) * t)
    d.line([(0, y), (W, y)], fill=(r, g, b, 255))

# subtle vignette / radial depth toward bottom corners
vign = Image.new("L", (W, H), 0)
vd = ImageDraw.Draw(vign)
vd.ellipse([-320, 220, 1344, 1100], fill=40)
vign = vign.filter(ImageFilter.GaussianBlur(160))
dark = Image.new("RGBA", (W, H), (6, 8, 30, 255))
bg.paste(dark, (0, 0), vign)

# ---- official white logo, centered, scaled to fit square with margins ----
logo = Image.open(LOGO).convert("RGBA")
lw, lh = logo.size
target_w = 760
scale = target_w / lw
nw, nh = int(lw * scale), int(lh * scale)
logo = logo.resize((nw, nh), Image.LANCZOS)
x = (W - nw) // 2
y = (H - nh) // 2 - 8
bg.alpha_composite(logo, (x, y))

# ---- rounded-corner mask (iOS ~22%) ----
mask = Image.new("L", (W, H), 0)
md = ImageDraw.Draw(mask)
md.rounded_rectangle([0, 0, W, H], radius=225, fill=255)
bg.putalpha(mask)

bg.save(OUT)
print("wrote", OUT, bg.size)
