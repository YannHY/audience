#!/usr/bin/env python3
"""Regenerate Resources/AppIcon.icon, the Icon Composer icon shared by the Mac and iPad apps.

Scene: a presenter behind a lectern on a round stage, lit by a spotlight, facing two rows
of audience silhouettes. Each element is drawn as a white 1024 x 1024 PNG mask (4x supersampled);
icon.json gives every layer its colour (light and dark appearances) and its Liquid Glass settings.
actool accepts at most four groups.

Usage: python3 scripts/generate-icon.py   (requires Pillow)
Preview: ictool Resources/AppIcon.icon --export-image --output-file out.png \
         --platform iOS --rendition Default --width 1024 --height 1024 --scale 1
"""
import json, math, os, shutil
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ICON = Path(__file__).resolve().parents[1] / 'Resources/AppIcon.icon'
ASSETS = ICON / 'Assets'
SS = 4      # supersampling factor
CX = 512    # horizontal centre

def new():
    m = Image.new('L', (1024*SS, 1024*SS), 0)
    return m, ImageDraw.Draw(m)

def save(name, m, blur=0):
    if blur:
        m = m.filter(ImageFilter.GaussianBlur(blur*SS))
    m = m.resize((1024, 1024), Image.LANCZOS)
    im = Image.new('RGBA', (1024, 1024), (255, 255, 255, 0))
    im.putalpha(m)
    im.save(ASSETS / name)

def P(pts): return [(x*SS, y*SS) for x, y in pts]

def bez(p0, p1, p2, p3, n=48):
    return [tuple((1-s)**3*a + 3*(1-s)**2*s*b + 3*(1-s)*s*s*c + s**3*e for a, b, c, e in zip(p0, p1, p2, p3))
            for s in [i/n for i in range(n+1)]]

def ellipse_arc(cx, cy, rx, ry, a0, a1, n=80):
    return [(cx + rx*math.cos(math.radians(a0 + (a1-a0)*i/n)), cy + ry*math.sin(math.radians(a0 + (a1-a0)*i/n)))
            for i in range(n+1)]

def bust(d, x, y, r, bottom=1100):
    """Audience member seen from behind: head joined to rounded shoulders."""
    d.ellipse([(x-r)*SS, (y-r)*SS, (x+r)*SS, (y+r)*SS], fill=255)
    t, w = y + 0.82*r, 1.8*r
    pts = [(x-w, bottom), (x-w, t+0.95*r)] + bez((x-w, t+0.95*r), (x-w, t+0.2*r), (x-0.75*r, t), (x, t)) \
        + bez((x, t), (x+0.75*r, t), (x+w, t+0.2*r), (x+w, t+0.95*r)) + [(x+w, bottom)]
    d.polygon(P(pts), fill=255)

if ICON.exists():
    shutil.rmtree(ICON)
ASSETS.mkdir(parents=True)

# Stage: elliptical top and front face.
SY, SRX, SRY, TH = 560, 300, 62, 46
m, d = new(); d.ellipse(P([(CX-SRX, SY-SRY), (CX+SRX, SY+SRY)]), fill=255); save('estrade.png', m)
m, d = new()
front = ellipse_arc(CX, SY, SRX, SRY, 0, 180) + [(x, y+TH) for x, y in ellipse_arc(CX, SY, SRX, SRY, 180, 0)]
d.polygon(P(front), fill=255); save('face.png', m)

# Spotlight beam (behind the stage).
m, d = new()
d.polygon(P([(CX-70, -20), (CX+70, -20), (CX+220, SY), (CX-220, SY)]), fill=150)
d.ellipse(P([(CX-230, SY-48), (CX+230, SY+48)]), fill=200)
save('lumiere.png', m, blur=14)

# Presenter, lectern and microphone, scaled up around the lectern's base.
FEET, KS = SY + 12, 1.15
_P0 = P
def P(pts): return _P0([(CX + (x-CX)*KS, FEET + (y-FEET)*KS) for x, y in pts])
LIP0, LIP1 = 404, 426   # lectern rim
m, d = new()
hr, hy = 34, 318
d.ellipse(P([(CX-hr, hy-hr), (CX+hr, hy+hr)]), fill=255)
top, sw, bot = hy + hr + 10, 70, LIP1 - 4      # shoulders end hidden behind the rim
dome = [(CX-sw, bot)] + bez((CX-sw, bot), (CX-sw, top+30), (CX-sw*0.62, top), (CX, top)) \
     + bez((CX, top), (CX+sw*0.62, top), (CX+sw, top+30), (CX+sw, bot))
d.polygon(P(dome), fill=255)
save('orateur.png', m)
m, d = new()
d.rounded_rectangle(P([(CX-108, LIP0), (CX+108, LIP1)]), radius=8*SS, fill=255)
d.polygon(P([(CX-90, LIP1-2), (CX+90, LIP1-2), (CX+72, FEET-14), (CX-72, FEET-14)]), fill=255)
d.rounded_rectangle(P([(CX-90, FEET-18), (CX+90, FEET)]), radius=6*SS, fill=255)
save('pupitre.png', m)
m, d = new()
d.line(P(bez((CX+8, LIP0+2), (CX+8, LIP0-12), (CX+6, LIP0-22), (CX-1, LIP0-30), 20)), fill=255, width=int(7*KS*SS), joint='curve')
d.ellipse(P([(CX-1-8, LIP0-30-9), (CX-1+8, LIP0-30+7)]), fill=255)
save('micro.png', m)
P = _P0

# Contact shadow and pool of light on the stage.
m, d = new(); d.ellipse(P([(CX-110, FEET-14), (CX+110, FEET+10)]), fill=200); save('ombre.png', m, blur=6)
m, d = new(); d.ellipse(P([(CX-210, SY-44), (CX+210, SY+40)]), fill=200); save('flaque.png', m, blur=16)

# Audience: the first row slightly overlaps the stage, the second bleeds off the bottom edge.
def curve(x, k): return -k*((x-512)/420)**2
m, d = new(); [bust(d, x, 696 + curve(x, 40), 50) for x in [CX + 160*k - 80 for k in range(-3, 5)]]; save('rang1.png', m)
m, d = new(); [bust(d, x, 852 + curve(x, 60), 78) for x in [CX + 250*k for k in range(-2, 3)]]; save('rang2.png', m)

FILL = {'fill-specializations': [
    {'value': {'linear-gradient': ['display-p3:0.36,0.29,0.88,1.0', 'display-p3:0.13,0.09,0.42,1.0'],
               'orientation': {'start': {'x': 0.5, 'y': 0.0}, 'stop': {'x': 0.5, 'y': 1.0}}}},
    {'appearance': 'dark', 'value': {'linear-gradient': ['display-p3:0.20,0.18,0.28,1.0', 'display-p3:0.05,0.05,0.07,1.0'],
               'orientation': {'start': {'x': 0.5, 'y': 0.0}, 'stop': {'x': 0.5, 'y': 1.0}}}}]}

def g(layers, transl=False, shadow=0.5):
    return {'layers': layers, 'shadow': {'kind': 'neutral', 'opacity': shadow},
            'translucency': {'enabled': transl, 'value': 0.3}}

def L(name, img, light, dark, glass=True):
    return {'name': name, 'image-name': img, 'glass': glass,
            'fill-specializations': [{'value': {'solid': light}}, {'appearance': 'dark', 'value': {'solid': dark}}]}

WARM = 'display-p3:1.0,0.90,0.70,1'
# Groups are listed front to back.
json.dump({**FILL, 'groups': [
    g([L('rang2', 'rang2.png', 'display-p3:0.07,0.04,0.24,1', 'display-p3:0.03,0.03,0.04,1'),
       L('rang1', 'rang1.png', 'display-p3:0.12,0.08,0.36,1', 'display-p3:0.08,0.08,0.10,1')]),
    g([L('micro', 'micro.png', 'display-p3:0.20,0.15,0.50,1', 'display-p3:0.12,0.11,0.16,1'),
       L('pupitre', 'pupitre.png', 'display-p3:0.58,0.52,0.98,1', 'display-p3:0.40,0.37,0.50,1'),
       L('orateur', 'orateur.png', 'display-p3:1,1,1,1', WARM)]),
    g([L('ombre', 'ombre.png', 'display-p3:0.10,0.06,0.35,0.45', 'display-p3:0,0,0,0.5', glass=False),
       L('flaque', 'flaque.png', 'display-p3:1,1,1,0.45', 'display-p3:1.0,0.88,0.65,0.3', glass=False),
       L('estrade', 'estrade.png', 'display-p3:0.80,0.76,1.0,1', 'display-p3:0.36,0.33,0.44,1'),
       L('face', 'face.png', 'display-p3:0.50,0.44,0.95,1', 'display-p3:0.22,0.20,0.28,1')], shadow=0.3),
    {'layers': [L('lumiere', 'lumiere.png', 'display-p3:1,1,1,0.55', 'display-p3:1.0,0.88,0.65,0.35', glass=False)]},
], 'supported-platforms': {'squares': 'shared'}}, open(ICON / 'icon.json', 'w'), indent=2)
print(ICON)
