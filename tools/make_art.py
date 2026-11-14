#!/usr/bin/env python3
"""Draws FreeControl's textures into FreeControl/Art as 32-bit TGA files.

    python3 tools/make_art.py

Needs Pillow and numpy. Everything is drawn at several times its final size and scaled down,
which is what gives the edges their smoothing. Sizes are powers of two because that is what the
game client is happiest with.
"""
import colorsys
import math
import os
import struct

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

SS = 6  # every shape is drawn this many times larger, then scaled down
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "FreeControl", "Art")

FONT_CANDIDATES = [
    os.path.expanduser("~/.local/share/fonts/Inter/Inter-Bold.ttf"),
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf",
]

# Palette
BRONZE_LIGHT = (226, 200, 138)  # the addon-list icon's frame
BRONZE_DARK = (84, 62, 32)
RIM_TOP = (58, 60, 68)          # a button's rim is nearly black; its upper edge catches a little light
RIM_BOTTOM = (10, 10, 13)
GOLD = (255, 214, 96)           # the ring around the action in progress
INK = (6, 6, 8)
SLOT_TOP = (22, 26, 36)
SLOT_BOTTOM = (9, 11, 16)
DISC = (17, 19, 26)
WHITE = (255, 255, 255)

FACE_COLORS = {
    "A": (124, 204, 84), "B": (236, 82, 70), "X": (84, 156, 246), "Y": (246, 200, 62),
    "Cross": (108, 160, 246), "Circle": (240, 92, 88), "Square": (232, 132, 196), "Triangle": (96, 208, 160),
}


def font(size):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    raise FileNotFoundError("No bold font found; add one to FONT_CANDIDATES in tools/make_art.py")


# ---------------------------------------------------------------------------
# Drawing helpers. Coordinates are in final pixels; the helpers scale them up.
# ---------------------------------------------------------------------------
def blank(w, h):
    return Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))


def mask(w, h):
    return Image.new("L", (w * SS, h * SS), 0)


def s(*values):
    return [v * SS for v in values]


def shape_mask(w, h, shape, inset, radius=0):
    """Filled rounded square or circle, `inset` pixels inside the w x h box."""
    m = mask(w, h)
    d = ImageDraw.Draw(m)
    box = s(inset, inset, w - inset, h - inset)
    if shape == "round":
        d.ellipse(box, fill=255)
    else:
        d.rounded_rectangle(box, radius=radius * SS, fill=255)
    return m


def vgradient(w, h, top, bottom, y0=0.0, y1=1.0):
    """Vertical gradient image, `top` at fraction y0 of the height and `bottom` at y1."""
    t = np.clip((np.linspace(0, 1, h * SS) - y0) / max(y1 - y0, 1e-6), 0, 1)[:, None, None]
    row = np.array(top, dtype=np.float32) * (1 - t) + np.array(bottom, dtype=np.float32) * t
    return Image.fromarray(np.broadcast_to(row, (h * SS, w * SS, 3)).astype(np.uint8), "RGB")


def layer(fill, alpha_mask, opacity=1.0):
    """RGBA layer: `fill` (a colour or an RGB image) shown through `alpha_mask`."""
    if isinstance(fill, tuple):
        fill = Image.new("RGB", alpha_mask.size, fill)
    out = fill.convert("RGBA")
    if opacity != 1.0:
        alpha_mask = alpha_mask.point(lambda v: int(v * opacity))
    out.putalpha(alpha_mask)
    return out


def over(*layers):
    out = layers[0]
    for top in layers[1:]:
        out = Image.alpha_composite(out, top)
    return out


def blur(img, radius):
    return img.filter(ImageFilter.GaussianBlur(radius * SS))


def subtract(a, b):
    return ImageChops.subtract(a, b)


def finish(img, w, h):
    """Scales a drawing down to its final size and gives transparent pixels the colour of their
    neighbours, so the game's texture filtering does not pull a dark fringe in from them."""
    img = img.resize((w, h), Image.LANCZOS)
    rgba = np.asarray(img).astype(np.float32)
    alpha = rgba[..., 3:4] / 255.0
    premultiplied = Image.fromarray((rgba[..., :3] * alpha).astype(np.uint8), "RGB")
    coverage = Image.fromarray((alpha[..., 0] * 255).astype(np.uint8), "L")
    spread_rgb = np.asarray(premultiplied.filter(ImageFilter.GaussianBlur(2))).astype(np.float32)
    spread_a = np.asarray(coverage.filter(ImageFilter.GaussianBlur(2))).astype(np.float32)[..., None] / 255.0
    bled = np.where(spread_a > 0.002, spread_rgb / np.maximum(spread_a, 0.002), 0)
    rgb = np.where(alpha > 0, rgba[..., :3], np.clip(bled, 0, 255))
    return Image.fromarray(np.concatenate([rgb, rgba[..., 3:4]], axis=-1).astype(np.uint8), "RGBA")


def save_tga(img, name):
    """Uncompressed 32-bit TGA, rows stored bottom-up: the plainest form of the format."""
    w, h = img.size
    rgba = np.asarray(img.convert("RGBA"))
    bgra = rgba[::-1, :, [2, 1, 0, 3]]
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    with open(os.path.join(OUT, name + ".tga"), "wb") as f:
        f.write(header)
        f.write(bgra.tobytes())


def centered_text(d, cx, cy, text, size, fill):
    f = font(size * SS)
    box = d.textbbox((0, 0), text, font=f)
    d.text((cx * SS - (box[0] + box[2]) / 2, cy * SS - (box[1] + box[3]) / 2), text, font=f, fill=fill)


def poly(d, points, fill):
    d.polygon([(x * SS, y * SS) for x, y in points], fill=fill)


def line(d, points, width, fill):
    d.line([(x * SS, y * SS) for x, y in points], fill=fill, width=int(width * SS), joint="curve")
    r = width * SS / 2
    for x, y in (points[0], points[-1]):  # round caps
        d.ellipse([x * SS - r, y * SS - r, x * SS + r, y * SS + r], fill=fill)


# ---------------------------------------------------------------------------
# Button frames: 128 x 128, drawn for a button that is 36 units across in game
# ---------------------------------------------------------------------------
B = 128
RING_OUT = 3      # the rim's outer edge, inside the texture
RING_W = 5.5      # rim thickness, about a pixel and a half on screen; the icon starts 7.1 px in, just under its inner edge
R_OUT, R_IN = 21, 16  # corner radii of the square rim


def ring_masks(shape):
    outer = shape_mask(B, B, shape, RING_OUT, R_OUT)
    inner = shape_mask(B, B, shape, RING_OUT + RING_W, R_IN)
    return outer, inner, subtract(outer, inner)


def rim(shape, top, bottom, glint=0.2):
    """A button's rim: shaded from top to bottom, a dark line on both edges, a little light on its upper edge."""
    outer, inner, ring = ring_masks(shape)
    body = layer(vgradient(B, B, top, bottom, 0.05, 0.95), ring)
    within = subtract(shape_mask(B, B, shape, RING_OUT + 1.2, R_OUT - 1.2),
                      shape_mask(B, B, shape, RING_OUT + RING_W - 1.2, R_IN + 1.2))
    body = over(body, layer(INK, subtract(ring, within), 0.8))
    upper = vgradient(B, B, (255, 255, 255), (0, 0, 0), 0.0, 0.42).convert("L")
    return over(body, layer(WHITE, ImageChops.multiply(within, upper), glint))


def round_mask():
    """A white disc filling the texture. Buttons.lua lays it over the icon area of a round button,
    where it clips the icon to a circle and gives the cooldown sweep its shape."""
    disc = shape_mask(B, B, "round", 0.5)
    return layer(WHITE, disc)


def square_mask():
    """The same for a square button: a white rounded square. Its corners follow the rim's, so
    neither the icon nor the cooldown sweep shows past the rim's rounded corners. The icon area
    starts 7.1 px inside the 128 px button, where a corner concentric with the rim has a radius
    of 16.9 px; stretched over this texture that is 19 px."""
    return layer(WHITE, shape_mask(B, B, "square", 0.5, 19))


def button_art(shape):
    """The five layers of a button frame, by the last part of their file name."""
    outer, inner, ring = ring_masks(shape)

    # Base: the dark well an icon sits in, visible when the slot is empty.
    well = shape_mask(B, B, shape, RING_OUT + 2, R_OUT - 2)
    base = layer(vgradient(B, B, SLOT_TOP, SLOT_BOTTOM), well)
    shade = blur(subtract(well, shape_mask(B, B, shape, RING_OUT + RING_W + 6, R_IN - 4)), 3)
    base = over(base, layer((0, 0, 0), ImageChops.multiply(shade, well), 0.6))

    border = rim(shape, RIM_TOP, RIM_BOTTOM)

    # Pushed: laid over a held button. The inside darkens from the top, with a shadow line under
    # the rim, as if the button had sunk into its frame.
    dip = ImageChops.multiply(vgradient(B, B, (255, 255, 255), (70, 70, 70)).convert("L"), inner)
    sunk = subtract(inner, shape_mask(B, B, shape, RING_OUT + RING_W + 2.4, R_IN - 2.4))
    pressed = over(layer((0, 0, 0), dip, 0.5), layer((0, 0, 0), sunk, 0.45))

    # Highlight: drawn additively on mouse-over; tinted green, it also marks an equipped item.
    glow = over(layer((255, 244, 214), ring, 0.5), layer((255, 250, 235), inner, 0.12))

    # Checked: a gold rim with a soft halo, for the action in progress.
    halo = blur(ring, 2.2)
    checked = over(layer(GOLD, halo, 0.45), rim(shape, (255, 244, 190), (196, 138, 34), 0.45))
    return {"Base": base, "Border": border, "Pushed": pressed, "Highlight": glow, "Checked": checked}


# ---------------------------------------------------------------------------
# Glyphs: 64 x 64 discs naming a controller button
# ---------------------------------------------------------------------------
G = 64


def disc():
    body = layer(vgradient(G, G, (32, 36, 48), DISC), shape_mask(G, G, "round", 3), 0.94)
    edge = subtract(shape_mask(G, G, "round", 3), shape_mask(G, G, "round", 5.2))
    return over(body, layer((208, 212, 224), edge, 0.6))


def glyph_letter(letter):
    img = disc()
    centered_text(ImageDraw.Draw(img), G / 2, G / 2 + 0.5, letter, 34, FACE_COLORS[letter] + (255,))
    return img


def glyph_shape(name):
    img = disc()
    d = ImageDraw.Draw(img)
    c, r, w = G / 2, 13, 5
    color = FACE_COLORS[name] + (255,)
    if name == "Cross":
        line(d, [(c - r, c - r), (c + r, c + r)], w, color)
        line(d, [(c - r, c + r), (c + r, c - r)], w, color)
    elif name == "Circle":
        d.ellipse(s(c - r - 2, c - r - 2, c + r + 2, c + r + 2), outline=color, width=int(w * SS))
    elif name == "Square":
        d.rounded_rectangle(s(c - r, c - r, c + r, c + r), radius=2 * SS, outline=color, width=int(w * SS))
    elif name == "Triangle":
        top, left, right = (c, c - r - 3), (c - r - 2, c + r - 1), (c + r + 2, c + r - 1)
        line(d, [top, right, left, top], w, color)
    return img


def glyph_dpad(direction):
    img = disc()
    d = ImageDraw.Draw(img)
    c = G / 2
    # An arrowhead pointing up, turned to the direction asked for.
    points = [(0, -15), (14, 9), (0, 3), (-14, 9)]
    turns = {"Up": 0, "Right": 1, "Down": 2, "Left": 3}[direction]
    for _ in range(turns):
        points = [(-y, x) for x, y in points]
    poly(d, [(c + x, c + y) for x, y in points], (240, 242, 248, 255))
    return img


# ---------------------------------------------------------------------------
# Trigger badges: 64 x 32 pills
# ---------------------------------------------------------------------------
def badge(text):
    w, h = 64, 32
    m = mask(w, h)
    ImageDraw.Draw(m).rounded_rectangle(s(2, 3, w - 2, h - 3), radius=9 * SS, fill=255)
    inner = mask(w, h)
    ImageDraw.Draw(inner).rounded_rectangle(s(3.6, 4.6, w - 3.6, h - 4.6), radius=7.4 * SS, fill=255)
    img = over(layer(vgradient(w, h, RIM_TOP, RIM_BOTTOM), m), layer(vgradient(w, h, (50, 54, 66), (26, 28, 36)), inner))
    centered_text(ImageDraw.Draw(img), w / 2, h / 2 + 0.5, text, 17, (244, 240, 228, 255))
    return img


# ---------------------------------------------------------------------------
# Role icons: 64 x 64, used like a spell icon for buttons that run a command
# ---------------------------------------------------------------------------
# Each is a small copy of the addon's emblem (ring_logo, further down): the same bronze compass
# ring, drawn in ink, around a glazed disc in the button's own colour, with a white symbol where
# the emblem has its four buttons. The four the bar starts with take the colours of those four
# buttons, so X, Y, B and A on the bar are the emblem's blue, yellow, red and green.
RING_OUTER = 31.0   # the ring's outer edge, in pixels from the middle of the 64 px tile
RING_INNER = 25.0
SYMBOL_SIZE = 0.76  # the symbols are drawn across the whole tile and set into the disc at this size


def mix(a, b, t):
    return tuple(int(round(x + (y - x) * t)) for x, y in zip(a, b))


def field(fn):
    """A mask computed from fn(x, y), with x and y in final pixels over the tile."""
    n = G * SS
    y, x = (np.mgrid[0:n, 0:n].astype(np.float32) + 0.5) / SS
    return Image.fromarray((np.clip(fn(x, y), 0, 1) * 255).astype(np.uint8), "L")


def tones(colour):
    """The light and the deep tone a glazed disc of this colour runs between. Yellows and oranges
    deepen towards amber: darkened as they are they would turn olive."""
    hue, saturation, value = colorsys.rgb_to_hsv(*(v / 255 for v in colour))
    warm = -0.05 if 0.08 < hue < 0.25 else 0
    light = colorsys.hsv_to_rgb(hue, saturation * 0.8, min(1, value * 1.12 + 0.08))
    deep = colorsys.hsv_to_rgb((hue + warm) % 1, min(1, saturation * 1.2), value * 0.4)
    return tuple(int(v * 255) for v in light), tuple(int(v * 255) for v in deep)


def round_spot(radius, cx=G / 2, cy=G / 2):
    m = mask(G, G)
    ImageDraw.Draw(m).ellipse(s(cx - radius, cy - radius, cx + radius, cy + radius), fill=255)
    return m


def medallion(colour):
    c = G / 2
    # What shows in the corners of a square button: the dark of an empty slot.
    img = vgradient(G, G, SLOT_TOP, SLOT_BOTTOM).convert("RGBA")
    img = over(img, layer(INK, round_spot(RING_OUTER + 0.6)))

    # The ring: bronze, lighter above than below, a bright line inside its outer edge, a dark one
    # along its inner edge, and the graduations of a compass card.
    band = subtract(round_spot(RING_OUTER), round_spot(RING_INNER))
    img = over(img, layer(vgradient(G, G, BRONZE_LIGHT, BRONZE_DARK, 0.02, 0.98), band))
    d = ImageDraw.Draw(img)
    for radius, ink, width in ((RING_OUTER - 0.9, (252, 236, 190, 165), 0.55), (RING_INNER + 0.7, (40, 28, 12, 180), 0.6)):
        d.ellipse(s(c - radius, c - radius, c + radius, c + radius), outline=ink, width=max(1, round(width * SS)))
    for tick in range(32):
        angle = math.radians(tick * 11.25)
        if tick % 8 == 0:
            continue  # a stud sits here
        r0, r1 = (RING_INNER + 1.5, RING_OUTER - 1.5) if tick % 4 == 0 else (RING_INNER + 2.1, RING_OUTER - 2.1)
        d.line(s(c + math.cos(angle) * r0, c + math.sin(angle) * r0, c + math.cos(angle) * r1, c + math.sin(angle) * r1),
               fill=(52, 36, 16, 215), width=max(1, round(0.62 * SS)))
    # A faceted stud at each quarter, lit from the upper left like the emblem's.
    middle, half = (RING_OUTER + RING_INNER) / 2, 2.7
    for step in range(4):
        angle = math.radians(step * 90 - 90)
        sx, sy = c + math.cos(angle) * middle, c + math.sin(angle) * middle
        poly(d, [(sx, sy - half - 0.6), (sx + half + 0.6, sy), (sx, sy + half + 0.6), (sx - half - 0.6, sy)], INK + (255,))
        top, right, bottom, left = (sx, sy - half), (sx + half, sy), (sx, sy + half), (sx - half, sy)
        poly(d, [top, (sx, sy), left], (240, 214, 152, 255))
        poly(d, [top, right, (sx, sy)], (196, 160, 96, 255))
        poly(d, [left, (sx, sy), bottom], (150, 112, 60, 255))
        poly(d, [(sx, sy), right, bottom], (92, 66, 34, 255))

    # The disc: light in its upper middle and deep at the rim, under the ring's shadow, with the
    # shine of a glazed surface on its upper left.
    img = over(img, layer(INK, round_spot(RING_INNER + 0.3)))
    inside = round_spot(RING_INNER - 0.45)
    light, deep = tones(colour)
    fall = field(lambda x, y: (np.hypot(x - c, y - (c - 5)) / (RING_INNER * 1.12)) ** 1.25)
    glaze = Image.composite(Image.new("RGB", fall.size, deep), Image.new("RGB", fall.size, light), fall)
    img = over(img, layer(glaze, inside))
    shadow = blur(subtract(round_spot(RING_INNER), round_spot(RING_INNER - 3.4)), 1.25)
    img = over(img, layer((0, 0, 0), ImageChops.multiply(shadow, inside), 0.6))
    shine = blur(round_spot(RING_INNER * 0.5, c - RING_INNER * 0.2, c - RING_INNER * 0.38), 2.6)
    return over(img, layer(WHITE, ImageChops.multiply(shine, inside), 0.2))


def grow(alpha, pixels):
    """The mask made `pixels` wider all round, with smooth corners."""
    return blur(alpha, pixels * 0.7).point(lambda v: min(255, int(v * 4.5)))


def role(colour, draw):
    art = blank(G, G)
    draw(ImageDraw.Draw(art))
    # Set into the disc: smaller, about the middle of the tile.
    n = G * SS
    small = art.resize((round(n * SYMBOL_SIZE),) * 2, Image.LANCZOS)
    art = blank(G, G)
    art.alpha_composite(small, ((n - small.width) // 2,) * 2)
    alpha = art.getchannel("A")
    # An ink line round the symbol and its shadow on the disc, as the emblem's letters have. A
    # part drawn see-through keeps a line as faint as it is.
    nearby = alpha.filter(ImageFilter.MaxFilter(int(1.4 * SS) * 2 + 1))
    edge = layer(mix(colour, INK, 0.86), ImageChops.multiply(subtract(grow(alpha, 1.05), alpha), nearby), 0.9)
    shadow = ImageChops.offset(layer(mix(colour, INK, 0.9), blur(alpha, 1.0), 0.7), 0, int(1.5 * SS))
    return over(medallion(colour), shadow, edge, art)


W = (250, 250, 252, 255)


def faint(alpha):
    return (250, 250, 252, alpha)


def turned(points, degrees, cx=32, cy=32):
    a = math.radians(degrees)
    return [(cx + (x - cx) * math.cos(a) - (y - cy) * math.sin(a), cy + (x - cx) * math.sin(a) + (y - cy) * math.cos(a))
            for x, y in points]


def spark(d, cx, cy, r, fill):
    """A four-pointed glint."""
    k = r * 0.2
    poly(d, [(cx, cy - r), (cx + k, cy - k), (cx + r, cy), (cx + k, cy + k), (cx, cy + r), (cx - k, cy + k), (cx - r, cy), (cx - k, cy - k)], fill)


def draw_jump(d):
    # Leaving the ground: two chevrons going up, and the shadow left behind on it.
    line(d, [(17.5, 26.5), (32, 12), (46.5, 26.5)], 6.6, W)
    line(d, [(21, 38.5), (32, 27.5), (43, 38.5)], 5.2, faint(205))
    d.ellipse(s(20.5, 46, 43.5, 53), fill=faint(105))


def draw_interact(d):
    # An open hand reaching for something: palm, four spread fingers and a thumb, and the glint
    # of what it is about to pick up.
    points = lambda base, length, angle: [base, (base[0] + length * math.sin(math.radians(angle)),
                                                 base[1] - length * math.cos(math.radians(angle)))]
    d.rounded_rectangle(s(20.5, 31, 41.5, 51.5), radius=8.5 * SS, fill=W)
    for base, length, angle in (((23.6, 35), 15, -11), ((29, 34), 19, -4), ((34.4, 34), 18, 3), ((39, 35.5), 14, 11)):
        line(d, points(base, length, angle), 4.8, W)
    line(d, points((22.5, 45.5), 11, -68), 5, W)
    spark(d, 49, 17, 7, faint(240))
    spark(d, 53.5, 29, 3.6, faint(200))


def draw_cancel(d):
    # A heavy cross with cut ends, the way a mark is struck through.
    for degrees in (45, -45):
        poly(d, turned([(10.5, 28.2), (53.5, 28.2), (53.5, 35.8), (10.5, 35.8)], degrees), W)


def draw_target(d):
    d.ellipse(s(17, 17, 47, 47), outline=W, width=int(4.5 * SS))
    for a, b in (((32, 10), (32, 22)), ((32, 42), (32, 54)), ((10, 32), (22, 32)), ((42, 32), (54, 32))):
        line(d, [a, b], 4.5, W)
    d.ellipse(s(29, 29, 35, 35), fill=W)


def draw_friend(d):
    d.ellipse(s(17, 17, 47, 47), outline=W, width=int(4.5 * SS))
    line(d, [(32, 24), (32, 40)], 5.5, W)
    line(d, [(24, 32), (40, 32)], 5.5, W)


def draw_attack(d):
    line(d, [(18, 46), (44, 20)], 6, W)            # blade
    poly(d, [(41, 17), (49, 15), (47, 23)], W)     # point
    line(d, [(19, 35), (29, 45)], 5, W)            # guard
    d.ellipse(s(12, 46, 20, 54), fill=W)           # pommel


def draw_run(d):
    line(d, [(17, 20), (29, 32), (17, 44)], 6, W)
    line(d, [(33, 20), (45, 32), (33, 44)], 6, W)


def draw_cursor(d):
    # A mouse pointer as the desktop draws it: a white arrow with a dark edge, so it reads as
    # "the mouse" at a glance and at the size of a bar button. The three strokes at its tip are a
    # click.
    tip, size = (22.5, 14.5), 1.0
    for degrees in (180, 225, 270):
        x, y = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
        line(d, [(tip[0] + 5.6 * x, tip[1] + 5.6 * y), (tip[0] + 10.4 * x, tip[1] + 10.4 * y)], 2.6, faint(235))
    points = [(tip[0] + x * size, tip[1] + y * size)
              for x, y in ((0, 0), (0, 33), (7.8, 26.2), (13.3, 39), (20.2, 36.2), (14.7, 23.8), (25.2, 23.8))]
    edge = (10, 12, 18, 255)
    line(d, points + points[:1], 5.6, edge)
    poly(d, points, edge)
    poly(d, points, W)


def draw_map(d):
    poly(d, [(13, 20), (25, 15), (25, 46), (13, 51)], W)
    poly(d, [(28, 16), (37, 20), (37, 51), (28, 47)], (250, 250, 252, 215))
    poly(d, [(40, 20), (51, 15), (51, 46), (40, 51)], W)


def draw_bags(d):
    d.rounded_rectangle(s(16, 25, 48, 51), radius=7 * SS, fill=W)
    d.arc(s(24, 12, 40, 32), 180, 360, fill=W, width=int(4.5 * SS))
    d.rounded_rectangle(s(27, 31, 37, 39), radius=2 * SS, fill=(120, 84, 48, 255))


def draw_generic(d):
    d.rounded_rectangle(s(17, 17, 47, 47), radius=8 * SS, outline=W, width=int(4.5 * SS))
    d.ellipse(s(28, 28, 36, 36), fill=W)


# name -> (the disc's colour, what is drawn on it). The first four are the buttons the bar starts
# with, in the colours the emblem gives X, Y, B and A.
ROLES = {
    "Interact": (FACE_COLORS["X"], draw_interact),
    "Cursor": (FACE_COLORS["Y"], draw_cursor),
    "Cancel": (FACE_COLORS["B"], draw_cancel),
    "Jump": (FACE_COLORS["A"], draw_jump),
    "TargetEnemy": ((226, 110, 62), draw_target),
    "TargetFriend": ((70, 190, 150), draw_friend),
    "Attack": ((232, 150, 56), draw_attack),
    "Run": ((150, 118, 226), draw_run),
    "Map": ((206, 176, 112), draw_map),
    "Bags": ((178, 124, 76), draw_bags),
    "Generic": ((132, 138, 152), draw_generic),
}


# ---------------------------------------------------------------------------
# Shade behind the held set, and the addon icon
# ---------------------------------------------------------------------------
def set_shade():
    """A soft patch drawn behind the held set: black and almost transparent, meant to go unnoticed."""
    w, h = 256, 128
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    dist = np.sqrt(((x - w / 2 + 0.5) / (w / 2)) ** 2 + ((y - h / 2 + 0.5) / (h / 2)) ** 2)
    rgba = np.zeros((h, w, 4), dtype=np.float32)
    rgba[..., 3] = np.clip(1 - dist, 0, 1) ** 1.5 * 0.22 * 255
    return Image.fromarray(rgba.astype(np.uint8), "RGBA")


def ring_logo(size, ss=3):
    """The addon's emblem, size x size: a bronze compass ring with a stud at each quarter, a
    sea-blue disc inside it, and the four face buttons of a controller in the middle."""
    n = size * ss
    c = n / 2
    ink = INK + (255,)
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def disc_mask(radius, cx=c, cy=c):
        m = Image.new("L", (n, n), 0)
        ImageDraw.Draw(m).ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=255)
        return m

    def shaded(top, bottom, y0, y1):
        """A top-to-bottom gradient between two heights, as a full-size picture."""
        rows = np.clip((np.arange(n, dtype=np.float32) - y0) / max(1.0, y1 - y0), 0, 1)[:, None]
        rgb = np.asarray(top, np.float32) * (1 - rows) + np.asarray(bottom, np.float32) * rows
        return Image.fromarray(np.broadcast_to(rgb[:, None, :], (n, n, 3)).astype(np.uint8), "RGB")

    # Studs first, so the ring overlaps their inner halves: a faceted diamond at each quarter
    # and a smaller one between.
    for step in range(8):
        angle = math.radians(step * 45 - 90)
        major = step % 2 == 0
        reach, half = (0.418 if major else 0.392) * n, (0.082 if major else 0.040) * n
        sx, sy = c + math.cos(angle) * reach, c + math.sin(angle) * reach
        corners = [(sx, sy - half), (sx + half, sy), (sx, sy + half), (sx - half, sy)]
        d.polygon(corners, fill=ink)
        inset = half * 0.86
        top, right, bottom, left = (sx, sy - inset), (sx + inset, sy), (sx, sy + inset), (sx - inset, sy)
        d.polygon([top, (sx, sy), left], fill=(240, 214, 152, 255))     # lit from the upper left
        d.polygon([top, right, (sx, sy)], fill=(196, 160, 96, 255))
        d.polygon([left, (sx, sy), bottom], fill=(150, 112, 60, 255))
        d.polygon([(sx, sy), right, bottom], fill=(92, 66, 34, 255))

    # The ring.
    outer, inner = 0.392 * n, 0.305 * n
    band = subtract(disc_mask(outer), disc_mask(inner))
    img.paste(ink, mask=disc_mask(outer + 0.008 * n))
    img.paste(shaded(BRONZE_LIGHT, BRONZE_DARK, c - outer, c + outer), mask=band)
    d = ImageDraw.Draw(img)
    for radius, colour, width in ((outer - 0.016 * n, (252, 236, 190, 150), 0.006), (inner + 0.012 * n, (40, 28, 12, 170), 0.006)):
        d.ellipse([c - radius, c - radius, c + radius, c + radius], outline=colour, width=max(1, round(width * n)))
    for tick in range(48):  # the graduations of a compass card
        angle = math.radians(tick * 7.5)
        r0, r1 = (0.326 if tick % 4 == 0 else 0.336) * n, (0.370 if tick % 4 == 0 else 0.360) * n
        d.line([(c + math.cos(angle) * r0, c + math.sin(angle) * r0), (c + math.cos(angle) * r1, c + math.sin(angle) * r1)],
               fill=(52, 36, 16, 210), width=max(1, round(0.006 * n)))

    # The disc: light in its upper middle, deep at the rim, with the ring's shadow on its edge.
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    fall = np.clip(np.hypot(xx - c, yy - (c - 0.07 * n)) / (inner * 1.15), 0, 1)[..., None] ** 1.2
    sea = np.array((96, 208, 228), np.float32) * (1 - fall) + np.array((5, 58, 88), np.float32) * fall
    img.paste(ink, mask=disc_mask(inner + 0.004 * n))
    img.paste(Image.fromarray(sea.astype(np.uint8), "RGB"), mask=disc_mask(inner - 0.006 * n))
    rim = blur_px(subtract(disc_mask(inner), disc_mask(inner - 0.045 * n)), 0.016 * n)
    img.alpha_composite(layer((0, 0, 0), ImageChops.multiply(rim, disc_mask(inner - 0.006 * n)), 0.55))

    # The four face buttons, in their colours, as they sit on a controller.
    reach, radius = 0.128 * n, 0.080 * n
    letters = ImageDraw.Draw(img)
    for name, (dx, dy) in (("Y", (0, -1)), ("X", (-1, 0)), ("B", (1, 0)), ("A", (0, 1))):
        bx, by = c + dx * reach, c + dy * reach
        shadow = blur_px(disc_mask(radius * 1.10, bx, by + 0.016 * n), 0.014 * n)
        img.alpha_composite(layer((0, 0, 0), shadow, 0.6))
        img.paste(ink, mask=disc_mask(radius + 0.011 * n, bx, by))
        colour = np.asarray(FACE_COLORS[name], np.float32)
        img.paste(shaded(np.clip(colour * 1.22 + 14, 0, 255), colour * 0.70, by - radius, by + radius), mask=disc_mask(radius, bx, by))
        gloss = blur_px(disc_mask(radius * 0.50, bx - radius * 0.18, by - radius * 0.34), 0.012 * n)
        img.alpha_composite(layer((255, 255, 255), ImageChops.multiply(gloss, disc_mask(radius, bx, by)), 0.30))
        letters = ImageDraw.Draw(img)
        f = font(max(6, int(radius * 1.25)))
        box = letters.textbbox((0, 0), name, font=f)
        at = (bx - (box[0] + box[2]) / 2, by - (box[1] + box[3]) / 2)
        letters.text((at[0], at[1] + 0.004 * n), name, font=f, fill=(10, 14, 20, 150))
        letters.text(at, name, font=f, fill=(255, 255, 255, 255))
    return img.resize((size, size), Image.LANCZOS)


def blur_px(img, radius):
    return img.filter(ImageFilter.GaussianBlur(radius))


def logo():
    return ring_logo(G * SS, 2)


def drawings(supersample=None):
    """Every drawn texture: file name -> (drawing at SS times its final size, final width, final
    height). tools/make_listing.py asks for a larger `supersample` and scales the drawings down
    less, for its large pictures."""
    global SS
    shipped = SS
    SS = supersample or shipped
    try:
        return _drawings()
    finally:
        SS = shipped


def _drawings():
    out = {}
    for shape, prefix in (("square", "Square"), ("round", "Round")):
        for part, img in button_art(shape).items():
            out[prefix + "-" + part] = (img, B, B)
    out["Round-Mask"] = (round_mask(), B, B)
    out["Square-Mask"] = (square_mask(), B, B)
    for letter in "ABXY":
        out["Glyph-" + letter] = (glyph_letter(letter), G, G)
    for name in ("Cross", "Circle", "Square", "Triangle"):
        out["Glyph-" + name] = (glyph_shape(name), G, G)
    for direction in ("Up", "Down", "Left", "Right"):
        out["Glyph-Dpad" + direction] = (glyph_dpad(direction), G, G)
    for text in ("LT", "RT", "L2", "R2", "ZL", "ZR"):
        out["Badge-" + text] = (badge(text), 64, 32)
    for name, (colour, draw) in ROLES.items():
        out["Role-" + name] = (role(colour, draw), G, G)
    out["Logo"] = (logo(), G, G)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (img, w, h) in drawings().items():
        save_tga(finish(img, w, h), name)
    save_tga(set_shade(), "Set-Shade")  # computed at its final size, so there is nothing to scale
    print("wrote %d textures to %s" % (len([f for f in os.listdir(OUT) if f.endswith(".tga")]), OUT))


if __name__ == "__main__":
    main()
