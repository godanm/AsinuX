"""
Generates the Play Store feature graphic (1024x500px) for Tricksy.
Dark crimson background, Tricksy logo + tagline, 6 game names, card suits.
"""
from PIL import Image, ImageDraw, ImageFont
import math, os

W, H = 1024, 500
FONT = '/System/Library/Fonts/Helvetica.ttc'


def lerp_color(c1, c2, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def make_bg():
    img = Image.new('RGB', (W, H), (8, 0, 6))
    draw = ImageDraw.Draw(img)
    # Horizontal gradient: deep red-maroon centre-left → near-black right
    for x in range(W):
        t = x / W
        col = lerp_color((70, 8, 24), (8, 0, 6), t)
        draw.rectangle([x, 0, x+1, H], fill=col)
    # Subtle vertical fade darker at bottom
    overlay = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    for y in range(H):
        a = int(60 * (y / H))
        od.rectangle([0, y, W, y+1], fill=(0, 0, 0, a))
    img = Image.alpha_composite(img.convert('RGBA'), overlay).convert('RGB')
    return img


def f(size):
    return ImageFont.truetype(FONT, size)


img = make_bg()
draw = ImageDraw.Draw(img)

# ── Grid lines (subtle) ────────────────────────────────────────────
for x in range(0, W, 60):
    draw.line([(x, 0), (x, H)], fill=(255, 255, 255, 5), width=1)
for y in range(0, H, 60):
    draw.line([(0, y), (W, y)], fill=(255, 255, 255, 5), width=1)

# ── Decorative faint suit symbols (right side) ─────────────────────
suits_cfg = [
    ('♠', 730, 30,  (255, 255, 255, 14), 140),
    ('♥', 860, 150, (230, 57,  70,  18), 150),
    ('♦', 720, 290, (230, 57,  70,  14), 130),
    ('♣', 840, 360, (255, 255, 255, 12), 120),
]
for sym, sx, sy, col, fsize in suits_cfg:
    try:
        sf = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial Unicode.ttf', fsize)
    except:
        try:
            sf = f(fsize)
        except:
            sf = None
    if sf:
        draw.text((sx, sy), sym, font=sf, fill=col)

# ── Subtle red glow behind logo ───────────────────────────────────
glow_cx, glow_cy = 185, H // 2
for r in range(100, 0, -5):
    t = 1 - r / 100
    rc = int(lerp_color((8, 0, 6), (180, 30, 50), t**2)[0])
    gc = int(lerp_color((8, 0, 6), (180, 30, 50), t**2)[1])
    bc = int(lerp_color((8, 0, 6), (180, 30, 50), t**2)[2])
    draw.ellipse([glow_cx-r, glow_cy-r, glow_cx+r, glow_cy+r], fill=(rc, gc, bc))

# ── Logo circle with "T" ───────────────────────────────────────────
logo_r = 72
logo_cx, logo_cy = 185, H // 2
draw.ellipse([logo_cx-logo_r, logo_cy-logo_r, logo_cx+logo_r, logo_cy+logo_r],
             fill=(40, 3, 14))
draw.ellipse([logo_cx-logo_r, logo_cy-logo_r, logo_cx+logo_r, logo_cy+logo_r],
             outline=(230, 57, 70), width=3)
try:
    lf = f(90)
    bbox = draw.textbbox((0,0), 'T', font=lf)
    tx = logo_cx - (bbox[2]-bbox[0])//2 - bbox[0]
    ty = logo_cy - (bbox[3]-bbox[1])//2 - bbox[1] - 5
    draw.text((tx+2, ty+3), 'T', font=lf, fill=(0,0,0,120))
    draw.text((tx, ty), 'T', font=lf, fill=(255, 210, 80))
except:
    pass

# ── "Tricksy" title ────────────────────────────────────────────────
try:
    title_f = f(92)
    title = 'Tricksy'
    bbox = draw.textbbox((0,0), title, font=title_f)
    tx = 285
    ty = H//2 - (bbox[3]-bbox[1])//2 - bbox[1] - 18
    draw.text((tx+3, ty+4), title, font=title_f, fill=(0,0,0,160))
    draw.text((tx, ty), title, font=title_f, fill=(255, 210, 80))
except:
    pass

# ── Tagline ────────────────────────────────────────────────────────
try:
    tag_f = f(26)
    draw.text((288, H//2 + 52), 'Outsmart the table.', font=tag_f,
              fill=(255, 255, 255, 170))
except:
    pass

# ── Divider line ───────────────────────────────────────────────────
draw.rectangle([282, H//2 + 88, 680, H//2 + 90], fill=(230, 57, 70, 120))

# ── 6 game names in two rows ───────────────────────────────────────
games = ['Kazhutha', 'Rummy', 'Teen Patti', '28', 'Blackjack', 'Bluff']
try:
    gf = f(21)
    cols = 3
    col_w = 132
    start_x = 286
    start_y = H//2 + 102
    row_h = 32
    for i, g in enumerate(games):
        col = i % cols
        row = i // cols
        gx = start_x + col * col_w
        gy = start_y + row * row_h
        # Bullet dot
        draw.ellipse([gx, gy+8, gx+6, gy+14], fill=(230, 57, 70))
        draw.text((gx+12, gy), g, font=gf, fill=(255, 255, 255, 200))
except:
    pass

# ── Bottom red bar ─────────────────────────────────────────────────
draw.rectangle([0, H-6, W, H], fill=(230, 57, 70))

# ── Save ───────────────────────────────────────────────────────────
out = os.path.join(os.path.dirname(__file__), 'tricksy_feature_graphic_1024x500.png')
img.save(out)
print(f'✓ Saved: {out}')
