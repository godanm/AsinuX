#!/usr/bin/env python3
"""
Generates the Play Store feature graphic (1024x500px) for AsinuX.
Dark crimson gradient background, gold logo, card suit decorations.
"""

from PIL import Image, ImageDraw, ImageFont
import math, os

W, H = 1024, 500

def radial_gradient(w, h, cx_ratio, cy_ratio, center_color, edge_color):
    img = Image.new('RGBA', (w, h))
    cx, cy = w * cx_ratio, h * cy_ratio
    max_r = math.sqrt(max(cx, w-cx)**2 + max(cy, h-cy)**2)
    for y in range(h):
        for x in range(w):
            r = math.sqrt((x - cx)**2 + (y - cy)**2)
            t = min(r / max_r, 1.0)
            def lerp(a, b): return int(a + (b - a) * t)
            color = tuple(lerp(c, e) for c, e in zip(center_color, edge_color))
            img.putpixel((x, y), color)
    return img

# Background
img = radial_gradient(W, H, 0.35, 0.5, (90, 10, 30, 255), (8, 0, 6, 255))
draw = ImageDraw.Draw(img)

# Subtle grid lines
for x in range(0, W, 60):
    draw.line([(x, 0), (x, H)], fill=(255, 255, 255, 6), width=1)
for y in range(0, H, 60):
    draw.line([(0, y), (W, y)], fill=(255, 255, 255, 6), width=1)

# Decorative suit symbols — large, faint, right side
suits = ['♠', '♥', '♦', '♣']
suit_positions = [(700, 60), (820, 180), (680, 300), (800, 380)]
suit_colors = [
    (255, 255, 255, 18),
    (230, 57, 70, 22),
    (230, 57, 70, 18),
    (255, 255, 255, 15),
]

deco_font = None
for path in [
    '/System/Library/Fonts/Apple Color Emoji.ttc',
    '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
]:
    try:
        deco_font = ImageFont.truetype(path, 130)
        break
    except:
        pass

if deco_font:
    for (sx, sy), color, suit in zip(suit_positions, suit_colors, suits):
        draw.text((sx, sy), suit, font=deco_font, fill=color)

# Crimson glow blob behind logo
for r in range(120, 0, -10):
    alpha = int(60 * (1 - r / 120))
    draw.ellipse([200 - r, H//2 - r, 200 + r, H//2 + r],
                 fill=(230, 57, 70, alpha))

# Logo circle
logo_r = 80
logo_cx, logo_cy = 200, H // 2
draw.ellipse(
    [logo_cx - logo_r, logo_cy - logo_r, logo_cx + logo_r, logo_cy + logo_r],
    fill=(60, 5, 20, 255)
)
draw.ellipse(
    [logo_cx - logo_r, logo_cy - logo_r, logo_cx + logo_r, logo_cy + logo_r],
    outline=(230, 57, 70, 180), width=3
)

# "A" in logo
logo_font = None
for path in [
    '/System/Library/Fonts/Supplemental/Impact.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
]:
    try:
        logo_font = ImageFont.truetype(path, 100)
        break
    except:
        pass

if logo_font:
    bbox = draw.textbbox((0, 0), 'A', font=logo_font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = logo_cx - tw // 2 - bbox[0]
    ty = logo_cy - th // 2 - bbox[1] - 6
    draw.text((tx + 3, ty + 3), 'A', font=logo_font, fill=(0, 0, 0, 100))
    draw.text((tx, ty), 'A', font=logo_font, fill=(255, 210, 80, 255))

# App name
title_font = None
for path in [
    '/System/Library/Fonts/Supplemental/Impact.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
]:
    try:
        title_font = ImageFont.truetype(path, 88)
        break
    except:
        pass

if title_font:
    name = 'AsinuX'
    bbox = draw.textbbox((0, 0), name, font=title_font)
    tw = bbox[2] - bbox[0]
    tx = 310
    ty = H // 2 - (bbox[3] - bbox[1]) // 2 - bbox[1] - 10
    # Shadow
    draw.text((tx + 3, ty + 4), name, font=title_font, fill=(0, 0, 0, 140))
    # Gold gradient effect — draw twice with slight offset for depth
    draw.text((tx, ty), name, font=title_font, fill=(255, 210, 80, 255))

# Tagline
tag_font = None
for path in [
    '/System/Library/Fonts/Supplemental/Arial.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
]:
    try:
        tag_font = ImageFont.truetype(path, 28)
        break
    except:
        pass

if tag_font:
    tagline = "Don't be the Donkey  🫏"
    draw.text((312, H // 2 + 56), tagline, font=tag_font, fill=(255, 255, 255, 160))

# Bottom red bar
draw.rectangle([0, H - 8, W, H], fill=(230, 57, 70, 200))

# Save
out_path = os.path.join(os.path.dirname(__file__), 'feature_graphic_1024x500.png')
img.save(out_path)
print(f'✓ Saved: {out_path}')
