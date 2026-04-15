#!/usr/bin/env python3
"""
Generates AsinuX app icons:
  - Dark crimson radial gradient background
  - Bold "A" in white/gold
  - Red heart (♥) beneath the A as a suit accent
Outputs: 512x512, 192x192, favicon 32x32
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, os

def radial_gradient(size, center_color, edge_color):
    img = Image.new('RGBA', (size, size))
    cx, cy = size / 2, size / 2
    max_r = math.sqrt(cx**2 + cy**2)
    for y in range(size):
        for x in range(size):
            r = math.sqrt((x - cx)**2 + (y - cy)**2)
            t = min(r / max_r, 1.0)
            def lerp(a, b): return int(a + (b - a) * t)
            color = tuple(lerp(c, e) for c, e in zip(center_color, edge_color))
            img.putpixel((x, y), color)
    return img

def make_icon(size):
    # Background: dark crimson radial gradient
    bg = radial_gradient(size, (80, 8, 24, 255), (10, 0, 8, 255))

    draw = ImageDraw.Draw(bg)

    # Rounded rect mask (for maskable version we skip clipping)
    radius = size * 0.22

    # Subtle inner glow ring
    ring_r = size * 0.44
    cx, cy = size / 2, size / 2
    for thickness in range(6, 0, -1):
        alpha = int(80 * (thickness / 6))
        draw.ellipse(
            [cx - ring_r - thickness, cy - ring_r - thickness,
             cx + ring_r + thickness, cy + ring_r + thickness],
            outline=(230, 57, 70, alpha), width=2
        )

    # "A" text — try system fonts, fallback to default
    font_size = int(size * 0.58)
    font = None
    for path in [
        '/System/Library/Fonts/Supplemental/Impact.ttf',
        '/System/Library/Fonts/Helvetica.ttc',
        '/System/Library/Fonts/Arial.ttf',
    ]:
        try:
            font = ImageFont.truetype(path, font_size)
            break
        except:
            pass
    if font is None:
        font = ImageFont.load_default()

    # Gold-to-white "A"
    letter = 'A'
    bbox = draw.textbbox((0, 0), letter, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = (size - tw) / 2 - bbox[0]
    ty = (size - th) / 2 - bbox[1] - size * 0.06

    # Shadow
    draw.text((tx + size*0.015, ty + size*0.015), letter, font=font, fill=(0, 0, 0, 120))
    # Gold colour
    draw.text((tx, ty), letter, font=font, fill=(255, 210, 80, 255))

    # Draw a heart shape using two circles + a rotated square
    hw = size * 0.14  # heart half-width
    hcx = cx
    hcy = ty + th + size * 0.035 + hw

    heart_color = (230, 57, 70, 230)
    r = hw * 0.52
    # Left lobe
    draw.ellipse([hcx - hw + r*0.1, hcy - r,
                  hcx - hw + r*0.1 + r*2, hcy - r + r*2], fill=heart_color)
    # Right lobe
    draw.ellipse([hcx - r*0.1, hcy - r,
                  hcx - r*0.1 + r*2, hcy - r + r*2], fill=heart_color)
    # Bottom triangle (polygon)
    draw.polygon([
        (hcx - hw, hcy),
        (hcx + hw, hcy),
        (hcx, hcy + hw * 1.2),
    ], fill=heart_color)

    return bg

def round_corners(img, radius):
    mask = Image.new('L', img.size, 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, img.size[0], img.size[1]], radius=radius, fill=255)
    result = img.copy()
    result.putalpha(mask)
    return result

out_dir = '/Users/godansudha/Projects/AsinuX/donkey_master/web/icons'
favicon_dir = '/Users/godansudha/Projects/AsinuX/donkey_master/web'

for size, name, maskable in [
    (512, 'Icon-512.png', False),
    (512, 'Icon-maskable-512.png', True),
    (192, 'Icon-192.png', False),
    (192, 'Icon-maskable-192.png', True),
]:
    icon = make_icon(size)
    if not maskable:
        icon = round_corners(icon, int(size * 0.18))
    icon.save(os.path.join(out_dir, name))
    print(f'  ✓ {name}')

# Favicon 32x32
fav = make_icon(256).resize((32, 32), Image.LANCZOS)
fav = round_corners(fav, 6)
fav.save(os.path.join(favicon_dir, 'favicon.png'))
print('  ✓ favicon.png')
print('Done.')
