#!/usr/bin/env python3
"""
AsinuX Logo Generator
Outputs:
  donkey_master/web/icons/Icon-512.png          — app icon 512 (rounded)
  donkey_master/web/icons/Icon-maskable-512.png — app icon 512 (full bleed)
  donkey_master/web/icons/Icon-192.png          — app icon 192 (rounded)
  donkey_master/web/icons/Icon-maskable-192.png — app icon 192 (full bleed)
  donkey_master/web/favicon.png                 — 32×32 favicon
  store_assets/logo_dark.png                    — horizontal lockup on dark bg
  store_assets/logo_light.png                   — horizontal lockup on white bg
  store_assets/logo_icon_512.png                — standalone icon (no rounding)
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, os

# ── Brand colours ──────────────────────────────────────────────────────────────
BG_DARK        = (13,  0,  7, 255)      # #0d0007  — app background
CRIMSON_DEEP   = (80,  8, 24, 255)      # centre of icon radial gradient
CRIMSON_EDGE   = (10,  0,  8, 255)      # edge of icon radial gradient
CRIMSON_ACCENT = (230, 57, 70, 255)     # #E63946  — ring / heart / wordmark X
GOLD           = (255, 210, 80, 255)    # #FFD250  — letter A
WHITE          = (255, 255, 255, 255)
SHADOW         = (0,   0,   0, 130)


# ── Helpers ────────────────────────────────────────────────────────────────────

def radial_gradient(size, center_color, edge_color):
    img = Image.new('RGBA', (size, size))
    cx, cy = size / 2, size / 2
    max_r = math.sqrt(cx**2 + cy**2)
    pixels = img.load()
    for y in range(size):
        for x in range(size):
            t = min(math.hypot(x - cx, y - cy) / max_r, 1.0)
            color = tuple(int(c + (e - c) * t) for c, e in zip(center_color, edge_color))
            pixels[x, y] = color
    return img


def best_font(size, bold=True):
    candidates = [
        '/System/Library/Fonts/Supplemental/Impact.ttf',
        '/System/Library/Fonts/Supplemental/Arial Bold.ttf',
        '/System/Library/Fonts/Supplemental/Arial.ttf',
        '/System/Library/Fonts/Helvetica.ttc',
        '/System/Library/Fonts/Arial.ttf',
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except Exception:
            pass
    return ImageFont.load_default()


def round_corners(img, radius):
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, *img.size], radius=radius, fill=255)
    out = img.copy().convert('RGBA')
    out.putalpha(mask)
    return out


def draw_heart(draw, cx, cy, hw, color):
    """Draw a heart centred at (cx, cy) with half-width hw."""
    r = hw * 0.52
    draw.ellipse([cx - hw + r*0.1,       cy - r,
                  cx - hw + r*0.1 + r*2, cy - r + r*2], fill=color)
    draw.ellipse([cx - r*0.1,            cy - r,
                  cx - r*0.1 + r*2,      cy - r + r*2], fill=color)
    draw.polygon([
        (cx - hw, cy),
        (cx + hw, cy),
        (cx,      cy + hw * 1.25),
    ], fill=color)


# ── Icon mark (square, any size) ───────────────────────────────────────────────

def make_icon(size):
    bg = radial_gradient(size, CRIMSON_DEEP, CRIMSON_EDGE)
    draw = ImageDraw.Draw(bg)
    cx, cy = size / 2, size / 2

    # Solid crimson ring (card-suit circle)
    ring_r = size * 0.40
    ring_w = max(3, int(size * 0.03))
    draw.ellipse([cx - ring_r, cy - ring_r, cx + ring_r, cy + ring_r],
                 outline=CRIMSON_ACCENT, width=ring_w)

    # "A" letter — smaller, well-centred
    font = best_font(int(size * 0.46))
    bbox = draw.textbbox((0, 0), 'A', font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]

    # Vertical centre of ring area, shifted up to leave room for heart
    tx = cx - tw / 2 - bbox[0]
    ty = cy - th / 2 - bbox[1] - size * 0.09

    # Subtle shadow
    draw.text((tx + size*0.012, ty + size*0.012), 'A', font=font,
              fill=(0, 0, 0, 90))
    # Gold letter
    draw.text((tx, ty), 'A', font=font, fill=GOLD)

    # Heart — small, just below the A
    hw = size * 0.10
    hcx = cx
    hcy = ty + th + size * 0.04 + hw
    draw_heart(draw, hcx, hcy, hw, CRIMSON_ACCENT)

    return bg


# ── Horizontal logo lockup ─────────────────────────────────────────────────────

def make_logo(dark_bg=True, height=160):
    icon_size = height          # square icon on left
    pad       = int(height * 0.18)
    gap       = int(height * 0.22)

    # Wordmark metrics — measure first
    name_font = best_font(int(height * 0.52))
    tag_font  = best_font(int(height * 0.175))
    name_text = 'AsinuX'
    tag_text  = 'THE DONKEY CARD GAME'

    dummy = Image.new('RGBA', (1, 1))
    dd = ImageDraw.Draw(dummy)
    nb = dd.textbbox((0, 0), name_text, font=name_font)
    tb = dd.textbbox((0, 0), tag_text,  font=tag_font)
    nw = nb[2] - nb[0]
    nh = nb[3] - nb[1]
    tw_tag = tb[2] - tb[0]

    text_block_w = max(nw, tw_tag)
    total_w = pad + icon_size + gap + text_block_w + pad
    total_h = icon_size + pad * 2

    bg_color = BG_DARK if dark_bg else (255, 255, 255, 255)
    canvas = Image.new('RGBA', (total_w, total_h), bg_color)

    # Paste icon (rounded)
    icon = make_icon(icon_size)
    icon_rounded = round_corners(icon, int(icon_size * 0.20))
    canvas.paste(icon_rounded, (pad, pad), icon_rounded)

    draw = ImageDraw.Draw(canvas)

    # Wordmark "AsinuX" — colour "X" in crimson, rest white/dark
    x_start = pad + icon_size + gap
    text_color = WHITE if dark_bg else (20, 0, 10, 255)

    # Paint whole name then repaint "X" in crimson
    name_y = pad + (icon_size - nh) // 2 - int(height * 0.06)
    draw.text((x_start - nb[0], name_y - nb[1]),
              name_text, font=name_font, fill=text_color)

    # Repaint "X" in crimson accent
    x_only_bbox = dd.textbbox((0, 0), name_text[:-1], font=name_font)  # "Asinu"
    x_offset = x_only_bbox[2] - x_only_bbox[0]
    draw.text((x_start - nb[0] + x_offset, name_y - nb[1]),
              'X', font=name_font, fill=CRIMSON_ACCENT)

    # Tagline
    tag_color = (*CRIMSON_ACCENT[:3], 180) if dark_bg else (*CRIMSON_ACCENT[:3], 200)
    tag_y = name_y + nh + int(height * 0.04)
    draw.text((x_start - tb[0], tag_y - tb[1]),
              tag_text, font=tag_font, fill=tag_color)

    return canvas


# ── Output paths ───────────────────────────────────────────────────────────────

ROOT        = os.path.dirname(os.path.abspath(__file__))
ICONS_DIR   = os.path.join(ROOT, 'donkey_master', 'web', 'icons')
WEB_DIR     = os.path.join(ROOT, 'donkey_master', 'web')
ASSETS_DIR  = os.path.join(ROOT, 'store_assets')

os.makedirs(ICONS_DIR,  exist_ok=True)
os.makedirs(WEB_DIR,    exist_ok=True)
os.makedirs(ASSETS_DIR, exist_ok=True)

# App icons
for size, name, maskable in [
    (512, 'Icon-512.png',          False),
    (512, 'Icon-maskable-512.png', True),
    (192, 'Icon-192.png',          False),
    (192, 'Icon-maskable-192.png', True),
]:
    icon = make_icon(size)
    out  = round_corners(icon, int(size * 0.20)) if not maskable else icon
    out.save(os.path.join(ICONS_DIR, name))
    print(f'  ✓ web/icons/{name}')

# Favicon
fav = round_corners(make_icon(256), 48).resize((32, 32), Image.LANCZOS)
fav.save(os.path.join(WEB_DIR, 'favicon.png'))
print('  ✓ web/favicon.png')

# Standalone icon (no rounding — for store_assets)
make_icon(512).save(os.path.join(ASSETS_DIR, 'logo_icon_512.png'))
print('  ✓ store_assets/logo_icon_512.png')

# Horizontal logo — dark
make_logo(dark_bg=True,  height=160).save(os.path.join(ASSETS_DIR, 'logo_dark.png'))
print('  ✓ store_assets/logo_dark.png')

# Horizontal logo — light
make_logo(dark_bg=False, height=160).save(os.path.join(ASSETS_DIR, 'logo_light.png'))
print('  ✓ store_assets/logo_light.png')

print('\nDone.')
