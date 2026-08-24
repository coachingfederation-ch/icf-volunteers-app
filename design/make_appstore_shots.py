#!/usr/bin/env python3
"""Generate App Store marketing screenshots (1320x2868, 6.9") for ICF Volunteers.

Strategy: 1 retouched real-UI screen (expired banner painted over with the
page's cream bg) + 4 branded feature-callout screens (official white logo on
Deep Blue, headline + feature lines). All 1320x2868.
"""
from PIL import Image, ImageDraw, ImageFont
import os

SRC = "/Users/hartmuth/Documents/Hermes/icf-volunteer-ios/design/screenshots"
LOGO = "/Users/hartmuth/Documents/Hermes/icf-volunteer-ios/ICFVolunteers/Assets.xcassets/LaunchLogo.imageset/LaunchLogo.png"
OUT = SRC
W, H = 1320, 2868
DEEP = (33, 34, 81)        # #212251
CREAM = (248, 240, 228)    # page cream
WHITE = (255, 255, 255)

os.makedirs(OUT, exist_ok=True)

def font(size, bold=False):
    for p in [f"/System/Library/Fonts/SFNS{'-Bold' if bold else ''}.ttf",
              "/System/Library/Fonts/Helvetica.ttc"]:
        if os.path.exists(p):
            try: return ImageFont.truetype(p, size)
            except Exception: pass
    return ImageFont.load_default()

def center_text(d, y, text, f, fill, tracking=0):
    bbox = d.textbbox((0, 0), text, font=f)
    x = (W - (bbox[2]-bbox[0])) // 2
    d.text((x, y), text, font=f, fill=fill)
    return y + (bbox[3]-bbox[1]) + 20

# ---- 1. Real UI (sign-in), banner retouched, upscaled ----
im = Image.open(f"{SRC}/01-signin.png").convert("RGB")
# retouch: paint cream over the yellow alert banner region (~y 380-500 @1206px wide)
d = ImageDraw.Draw(im)
d.rectangle([0, 360, im.width, 520], fill=CREAM)
im = im.resize((W, H), Image.LANCZOS)
d = ImageDraw.Draw(im)
f_head = font(84, bold=True)
center_text(d, 110, "Mit QR-Code anmelden", f_head, DEEP)
im.save(f"{OUT}/app-store-1-anmelden.png")

# ---- feature screens ----
logo = Image.open(LOGO).convert("RGBA")
features = [
    ("app-store-2-livechat.png", "Live-Chat mit Besuchern",
     ["Anfragen sofort annehmen", "Direkt aus dem Chat antworten", "Immer da, wo die Community ist"]),
    ("app-store-3-push.png", "Push, wenn es darauf ankommt",
     ["Benachrichtigung bei neuen Anfragen", "Verpasste Anfragen gehören der Vergangenheit an", "Badge zeigt offene Chats"]),
    ("app-store-4-hintergrund.png", "Immer auf dem Laufenden",
     ["Aktualisiert sich im Hintergrund", "Neue Anfragen auch bei geschlossener App", "Batterieschonend integriert"]),
    ("app-store-5-brand.png", "Von ICF Switzerland",
     ["Für Freiwillige des Switzerland Chapters", "Sicher über die ICF Member-Plattform", "Offizielles Angebot der ICF Switzerland"]),
]
for fname, title, lines in features:
    img = Image.new("RGB", (W, H), DEEP)
    dr = ImageDraw.Draw(img)
    # logo block upper third
    lw = 560
    l = logo.resize((lw, int(lw*logo.height/logo.width)), Image.LANCZOS)
    img.paste(l, ((W-lw)//2, 620), l)
    y = 1500
    y = center_text(dr, y, title, font(92, bold=True), WHITE)
    y += 120
    fl = font(64)
    for line in lines:
        bbox = dr.textbbox((0,0), line, font=fl)
        dr.text(((W-(bbox[2]-bbox[0]))//2, y), line, font=fl, fill=(220, 222, 240))
        y += 130
    img.save(f"{OUT}/{fname}")

print("generated:", sorted(f for f in os.listdir(OUT) if f.startswith("app-store-")))
