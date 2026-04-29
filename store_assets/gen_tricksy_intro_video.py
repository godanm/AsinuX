"""
Generates a ~90s Tricksy intro video (1280x720, 30fps).
Structure:
  0:00-0:07  Tricksy brand intro
  0:07-1:17  6 game showcases (~11s each)
  1:17-1:30  "6 games. One app." outro
PIL draws frames → ffmpeg encodes to MP4 with crossfade transitions.
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os, subprocess, shutil, math

W, H   = 1280, 720
FPS    = 30
FONT   = '/System/Library/Fonts/Helvetica.ttc'
ICON   = os.path.join(os.path.dirname(__file__), 'tricksy_icon_source.jpeg')
OUTDIR = '/tmp/tricksy_frames'
OUT    = os.path.join(os.path.dirname(__file__), 'tricksy_intro.mp4')

BG_DARK   = (13, 0, 8)
BG_MID    = (50, 5, 20)
GOLD      = (255, 210, 80)
RED       = (230, 57, 70)
WHITE     = (255, 255, 255)
LEATHER   = (72, 10, 22)

os.makedirs(OUTDIR, exist_ok=True)

def f(size):
    return ImageFont.truetype(FONT, size)

def lerp(a, b, t):
    if isinstance(a, tuple):
        return tuple(int(x + (y - x) * t) for x, y in zip(a, b))
    return a + (b - a) * t

def ease_out(t): return 1 - (1 - t) ** 2
def ease_in_out(t): return t * t * (3 - 2 * t)

# ── Background helpers ────────────────────────────────────────────────────────

def make_bg(accent=None):
    img = Image.new('RGB', (W, H), BG_DARK)
    draw = ImageDraw.Draw(img)
    # Horizontal gradient
    for x in range(W):
        t = x / W
        c = lerp(BG_MID, BG_DARK, t)
        draw.rectangle([x, 0, x+1, H], fill=c)
    # Subtle grid
    for x in range(0, W, 80):
        draw.line([(x, 0), (x, H)], fill=(255,255,255,6), width=1)
    for y in range(0, H, 80):
        draw.line([(0, y), (W, y)], fill=(255,255,255,6), width=1)
    if accent:
        # Soft glow at top
        glow = Image.new('RGBA', (W, H), (0,0,0,0))
        gd   = ImageDraw.Draw(glow)
        for i in range(H // 3):
            a = int(30 * (1 - i / (H // 3)))
            gd.rectangle([0, i, W, i+1], fill=(*accent, a))
        img = Image.alpha_composite(img.convert('RGBA'), glow).convert('RGB')
    return img

def draw_rounded_rect(draw, xy, r, fill, outline=None, ow=2):
    x0,y0,x1,y1 = xy
    draw.rounded_rectangle([x0,y0,x1,y1], radius=r, fill=fill)
    if outline:
        draw.rounded_rectangle([x0,y0,x1,y1], radius=r, outline=outline, width=ow)

def paste_icon(img, size, cx, cy, alpha=1.0):
    icon = Image.open(ICON).convert('RGBA')
    icon = icon.resize((size, size), Image.LANCZOS)
    if alpha < 1.0:
        r,g,b,a = icon.split()
        a = a.point(lambda x: int(x * alpha))
        icon.putalpha(a)
    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0,0,size-1,size-1],
                                           radius=size//6, fill=255)
    icon.putalpha(mask)
    img.paste(icon, (cx - size//2, cy - size//2), icon)

# ── Frame index tracker ───────────────────────────────────────────────────────

frame_idx = [0]

def save_frame(img):
    path = os.path.join(OUTDIR, f'frame_{frame_idx[0]:05d}.png')
    img.save(path)
    frame_idx[0] += 1

def hold(img, secs):
    for _ in range(int(secs * FPS)):
        save_frame(img)

def crossfade(img_a, img_b, secs=0.5):
    frames = int(secs * FPS)
    for i in range(frames):
        t = ease_in_out(i / frames)
        blended = Image.blend(img_a, img_b, t)
        save_frame(blended)

def slide_in_text(base_img, text, font_size, color, y_target, secs=0.6, direction=1):
    """Animate text sliding in from below (direction=1) or above (-1)."""
    tf = f(font_size)
    frames = int(secs * FPS)
    tmp = ImageDraw.Draw(Image.new('RGB', (W,H)))
    bbox = tmp.textbbox((0,0), text, font=tf)
    tw = bbox[2] - bbox[0]
    tx = (W - tw) // 2
    for i in range(frames):
        t = ease_out(i / frames)
        y_off = int(direction * 60 * (1 - t))
        frame = base_img.copy()
        d = ImageDraw.Draw(frame)
        a_val = int(255 * t)
        col = (*color, a_val)
        d.text((tx, y_target + y_off), text, font=tf, fill=col)
        save_frame(frame)
    # Return final with text drawn
    final = base_img.copy()
    d = ImageDraw.Draw(final)
    d.text((tx, y_target), text, font=tf, fill=color)
    return final

# ── Section 1: Brand intro (7s) ───────────────────────────────────────────────

print("Rendering intro...")
bg = make_bg(accent=RED)

# Icon scale-in (1s)
for i in range(FPS):
    t = ease_out(i / FPS)
    frame = bg.copy()
    sz = int(lerp(60, 180, t))
    a = t
    paste_icon(frame, sz, W//2, H//2 - 60, alpha=a)
    save_frame(frame)

# Icon settled frame
icon_frame = bg.copy()
paste_icon(icon_frame, 180, W//2, H//2 - 60)

# Title slide in
d = ImageDraw.Draw(icon_frame)
# "Tricksy" in gold
tf_big = f(80)
bbox = d.textbbox((0,0), 'Tricksy', font=tf_big)
tx = (W - (bbox[2]-bbox[0])) // 2
d.text((tx+3, H//2 + 100 + 3), 'Tricksy', font=tf_big, fill=(0,0,0,120))
d.text((tx, H//2 + 100), 'Tricksy', font=tf_big, fill=GOLD)

tf_tag = f(26)
tag = 'Outsmart the table.'
bbox2 = d.textbbox((0,0), tag, font=tf_tag)
tx2 = (W - (bbox2[2]-bbox2[0])) // 2
d.text((tx2, H//2 + 190), tag, font=tf_tag, fill=(*WHITE, 120))

hold(icon_frame, 4.5)

# ── Section 2: Game showcases ─────────────────────────────────────────────────

games = [
    {
        'name':  'Kazhutha',
        'sub':   'The Classic Trick-Taking Game',
        'desc':  ['Lead tricks, shed your cards.', 'Don\'t be the last one holding.'],
        'suit':  '♣',
        'color': RED,
        'bg':    (60, 5, 18),
    },
    {
        'name':  'Rummy',
        'sub':   'Draw · Discard · Go Out',
        'desc':  ['Form sets and sequences.', 'The timeless card classic.'],
        'suit':  '♦',
        'color': (230, 120, 57),
        'bg':    (50, 20, 5),
    },
    {
        'name':  'Teen Patti',
        'sub':   'India\'s Favourite Betting Game',
        'desc':  ['Three cards. Pure nerve.', 'Bluff, raise, or fold.'],
        'suit':  '♥',
        'color': (220, 60, 100),
        'bg':    (55, 5, 30),
    },
    {
        'name':  '28',
        'sub':   'South India\'s Trick Game',
        'desc':  ['Secret bids. Trump cards.', 'A true test of card sense.'],
        'suit':  '♠',
        'color': (100, 180, 230),
        'bg':    (5, 20, 55),
    },
    {
        'name':  'Blackjack',
        'sub':   'Beat the Dealer',
        'desc':  ['Hit or stand. Don\'t bust.', 'Play solo anytime.'],
        'suit':  '🂡',
        'color': GOLD,
        'bg':    (30, 25, 5),
    },
    {
        'name':  'Bluff',
        'sub':   'The Mind Game',
        'desc':  ['Lie. Call. Catch them out.', 'Pure psychological warfare.'],
        'suit':  '★',
        'color': (160, 230, 130),
        'bg':    (10, 40, 15),
    },
]

prev_frame = icon_frame

for g in games:
    print(f"  Rendering {g['name']}...")
    # Build game slide background
    gbg = Image.new('RGB', (W, H), g['bg'])
    gd  = ImageDraw.Draw(gbg)
    for x in range(W):
        t = x / W
        c = lerp(g['bg'], BG_DARK, t * 0.7)
        gd.rectangle([x, 0, x+1, H], fill=c)
    # Subtle grid
    for x in range(0, W, 80):
        gd.line([(x,0),(x,H)], fill=(255,255,255,4), width=1)
    for y in range(0, H, 80):
        gd.line([(0,y),(W,y)], fill=(255,255,255,4), width=1)

    # Large faint suit symbol right side
    try:
        sf = f(320)
        suit_bbox = gd.textbbox((0,0), g['suit'], font=sf)
        sw = suit_bbox[2] - suit_bbox[0]
        sh = suit_bbox[3] - suit_bbox[1]
        sx = W - sw - 40
        sy = (H - sh) // 2
        gd.text((sx, sy), g['suit'], font=sf, fill=(*g['color'], 22))
    except:
        pass

    # Colour accent bar on left
    gd.rectangle([0, 0, 6, H], fill=g['color'])

    # Game name
    nf = f(90)
    bbox = gd.textbbox((0,0), g['name'], font=nf)
    gd.text((80+2, 120+2), g['name'], font=nf, fill=(0,0,0,150))
    gd.text((80, 120), g['name'], font=nf, fill=g['color'])

    # Subtitle
    sf2 = f(28)
    gd.text((84, 220), g['sub'], font=sf2, fill=(*WHITE, 140))

    # Divider
    gd.rectangle([80, 264, 80 + min(len(g['name'])*30, 400), 267], fill=g['color'])

    # Description lines
    df = f(32)
    for li, line in enumerate(g['desc']):
        gd.text((80, 290 + li * 52), f'• {line}', font=df, fill=(*WHITE, 200))

    # Small icon bottom-right
    paste_icon(gbg, 120, W - 100, H - 80)

    # Crossfade from previous
    crossfade(prev_frame, gbg, secs=0.5)
    hold(gbg, 9.5)
    prev_frame = gbg

# ── Section 3: Outro (13s) ────────────────────────────────────────────────────

print("Rendering outro...")
outro = make_bg(accent=GOLD)
od = ImageDraw.Draw(outro)

# Large icon
paste_icon(outro, 160, W//2, H//2 - 80)

# "6 games. One app."
hf = f(64)
headline = '6 games.  One app.'
bbox = od.textbbox((0,0), headline, font=hf)
hx = (W - (bbox[2]-bbox[0])) // 2
od.text((hx+2, H//2+50+2), headline, font=hf, fill=(0,0,0,120))
od.text((hx, H//2+50), headline, font=hf, fill=GOLD)

# Tagline
tf2 = f(26)
tag2 = 'Outsmart the table.'
b2 = od.textbbox((0,0), tag2, font=tf2)
od.text(((W-(b2[2]-b2[0]))//2, H//2+130), tag2, font=tf2, fill=(*WHITE, 130))

# Download line
tf3 = f(22)
dl = 'tricksy.app'
b3 = od.textbbox((0,0), dl, font=tf3)
od.text(((W-(b3[2]-b3[0]))//2, H//2+175), dl, font=tf3, fill=(*RED, 200))

crossfade(prev_frame, outro, secs=0.7)
hold(outro, 7)

# Fade to black
black = Image.new('RGB', (W, H), (0,0,0))
crossfade(outro, black, secs=1.5)

# ── Encode with ffmpeg ────────────────────────────────────────────────────────

print(f"\nEncoding {frame_idx[0]} frames → {OUT}")
cmd = [
    'ffmpeg', '-y',
    '-framerate', str(FPS),
    '-i', os.path.join(OUTDIR, 'frame_%05d.png'),
    '-c:v', 'libx264',
    '-preset', 'slow',
    '-crf', '18',
    '-pix_fmt', 'yuv420p',
    '-vf', 'scale=1280:720',
    OUT
]
subprocess.run(cmd, check=True)

# Clean up frames
shutil.rmtree(OUTDIR)

duration = frame_idx[0] / FPS
print(f'\n✓ Video saved: {OUT}')
print(f'  Duration: {int(duration//60)}:{int(duration%60):02d}  |  Frames: {frame_idx[0]}')
