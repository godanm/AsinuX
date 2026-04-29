"""
Generates Tricksy app icons for web and Android.
Design: dark card-game background, a tilted white playing card,
bold red "T" on the card, gold star pip in top-left corner.
"""
from PIL import Image, ImageDraw, ImageFont
import os, math

FONT_PATH = '/System/Library/Fonts/Helvetica.ttc'
BG_DARK   = (13, 0, 8)       # #0d0008
BG_MID    = (32, 0, 18)      # #200012
RED       = (230, 57, 70)    # #E63946
GOLD      = (255, 210, 80)   # #FFD250
CARD_BG   = (255, 252, 245)  # warm white
CARD_PIP  = (200, 30, 45)    # deep red for pips on card


def font(size):
    return ImageFont.truetype(FONT_PATH, size)


def draw_rounded_rect(draw, xy, radius, fill):
    x0, y0, x1, y1 = xy
    draw.rectangle([x0 + radius, y0, x1 - radius, y1], fill=fill)
    draw.rectangle([x0, y0 + radius, x1, y1 - radius], fill=fill)
    draw.ellipse([x0, y0, x0 + 2*radius, y0 + 2*radius], fill=fill)
    draw.ellipse([x1 - 2*radius, y0, x1, y0 + 2*radius], fill=fill)
    draw.ellipse([x0, y1 - 2*radius, x0 + 2*radius, y1], fill=fill)
    draw.ellipse([x1 - 2*radius, y1 - 2*radius, x1, y1], fill=fill)


def draw_card(size):
    """Draw a white playing card with T and star pip, return RGBA image."""
    card_img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(card_img)

    # Card dimensions relative to size
    cw = int(size * 0.68)
    ch = int(cw * 1.35)
    cx = (size - cw) // 2
    cy = (size - ch) // 2
    cr = max(4, int(size * 0.055))

    # Card shadow
    shadow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    off = max(2, size // 40)
    draw_rounded_rect(sd, [cx+off, cy+off, cx+cw+off, cy+ch+off], cr, (0, 0, 0, 90))
    card_img = Image.alpha_composite(card_img, shadow)
    d = ImageDraw.Draw(card_img)

    # Card face
    draw_rounded_rect(d, [cx, cy, cx+cw, cy+ch], cr, CARD_BG)

    # Red border on card
    border = max(1, size // 80)
    for b in range(border):
        d.rectangle([cx+b, cy+b, cx+cw-b, cy+ch-b], outline=(200, 30, 45, 180))

    # Big "T" centred on card
    t_size = int(cw * 0.72)
    try:
        tf = font(t_size)
    except:
        tf = ImageFont.load_default()
    bbox = d.textbbox((0, 0), 'T', font=tf)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = cx + (cw - tw) // 2 - bbox[0]
    ty = cy + (ch - th) // 2 - bbox[1] - int(size * 0.02)
    d.text((tx, ty), 'T', font=tf, fill=CARD_PIP)

    # Gold diamond pip top-left (drawn geometrically)
    pip_r = max(4, int(size * 0.055))
    pip_x = cx + int(size * 0.045)
    pip_y = cy + int(size * 0.038)
    d.ellipse([pip_x, pip_y, pip_x + pip_r*2, pip_y + pip_r*2], fill=GOLD)

    # Mirror pip bottom-right
    d.ellipse([cx + cw - pip_x + cx - pip_r*2,
               cy + ch - pip_y + cy - pip_r*2,
               cx + cw - pip_x + cx,
               cy + ch - pip_y + cy], fill=GOLD)

    return card_img


def make_icon(size, maskable=False):
    img = Image.new('RGBA', (size, size), BG_DARK)
    draw = ImageDraw.Draw(img)

    # Background rounded rect (or full square for maskable)
    if maskable:
        corner = size // 8
        safe_pad = int(size * 0.12)
    else:
        corner = size // 5
        safe_pad = 0

    # Dark gradient background
    for y in range(size):
        t = y / size
        r = int(BG_DARK[0] + (BG_MID[0] - BG_DARK[0]) * (1 - t))
        g = int(BG_DARK[1] + (BG_MID[1] - BG_DARK[1]) * (1 - t))
        b = int(BG_DARK[2] + (BG_MID[2] - BG_DARK[2]) * (1 - t))
        draw.rectangle([0, y, size, y+1], fill=(r, g, b))

    # Rounded rect mask for non-maskable
    if not maskable:
        mask = Image.new('L', (size, size), 0)
        md = ImageDraw.Draw(mask)
        md.rounded_rectangle([0, 0, size-1, size-1], radius=corner, fill=255)
        img.putalpha(mask)

    # Subtle red glow at top
    glow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for i in range(size // 3):
        alpha = int(35 * (1 - i / (size // 3)))
        gd.rectangle([0, i, size, i+1], fill=(*RED, alpha))
    img = Image.alpha_composite(img if maskable else img.convert('RGBA'), glow)

    # Draw tilted card
    card_size = int(size * (0.75 if maskable else 0.85))
    card_layer = draw_card(size)

    # Rotate card slightly
    rotated = card_layer.rotate(-8, resample=Image.BICUBIC, expand=False)
    img = Image.alpha_composite(img.convert('RGBA'), rotated)

    if maskable:
        # For maskable, background should be a full square (no transparent corners)
        final = Image.new('RGBA', (size, size), BG_DARK)
        final = Image.alpha_composite(final, img)
        return final.convert('RGB')

    return img


def save_png(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print(f"  Saved: {path}")


base = '/Users/godansudha/Projects/AsinuX/donkey_master'

print("Generating Tricksy icons...")

# Web icons
save_png(make_icon(192),             f'{base}/web/icons/Icon-192.png')
save_png(make_icon(512),             f'{base}/web/icons/Icon-512.png')
save_png(make_icon(192, maskable=True), f'{base}/web/icons/Icon-maskable-192.png')
save_png(make_icon(512, maskable=True), f'{base}/web/icons/Icon-maskable-512.png')

# Android mipmap sizes
android_sizes = {
    'mipmap-mdpi':    48,
    'mipmap-hdpi':    72,
    'mipmap-xhdpi':   96,
    'mipmap-xxhdpi':  144,
    'mipmap-xxxhdpi': 192,
}
for folder, sz in android_sizes.items():
    save_png(make_icon(sz), f'{base}/android/app/src/main/res/{folder}/ic_launcher.png')

print("Done.")
