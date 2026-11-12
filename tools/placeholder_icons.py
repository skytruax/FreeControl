#!/usr/bin/env python3
"""Stand-in spell icons for the mock-ups: plain emblems on coloured tiles.

The game's own icons are Blizzard's artwork and are not used anywhere in this repository. These
are drawn here instead, and every picture that shows them says they are placeholders.

    python3 tools/placeholder_icons.py     # writes docs/placeholder-icons.png, a sheet of them all
"""
import colorsys
import functools
import math
import os
import re

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SS = 4  # emblems are drawn this many times larger, then scaled down


# ---------------------------------------------------------------------------
# A small drawing surface. Emblems are described in a 100 x 100 box.
# ---------------------------------------------------------------------------
def flatten(path, steps=24):
    """Points along an SVG-style path made of absolute M, L and C commands."""
    tokens = re.findall(r"[MLCZ]|-?\d+(?:\.\d+)?", path)
    points, here, i = [], None, 0
    while i < len(tokens):
        command = tokens[i]
        i += 1
        if command in "ML":
            here = (float(tokens[i]), float(tokens[i + 1]))
            i += 2
            points.append(here)
        elif command == "C":
            a, b, c = [(float(tokens[i + n]), float(tokens[i + n + 1])) for n in (0, 2, 4)]
            i += 6
            for step in range(1, steps + 1):
                t = step / steps
                u = 1 - t
                points.append(tuple(u ** 3 * here[n] + 3 * u * u * t * a[n] + 3 * u * t * t * b[n] + t ** 3 * c[n]
                                    for n in (0, 1)))
            here = c
    return points


def star_points(cx, cy, outer, inner, tips, start=-90):
    points = []
    for i in range(tips * 2):
        r = outer if i % 2 == 0 else inner
        a = math.radians(start + i * 180 / tips)
        points.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return points


def on_circle(cx, cy, r, degrees):
    """A point on a circle; 0 degrees is to the right and 90 is down, as on screen."""
    a = math.radians(degrees)
    return (cx + r * math.cos(a), cy + r * math.sin(a))


class Mask:
    """An 8-bit drawing: 255 is the emblem, 0 is cut away."""

    def __init__(self, px):
        self.k = px / 100.0
        self.img = Image.new("L", (px, px), 0)
        self.d = ImageDraw.Draw(self.img)

    def _box(self, x0, y0, x1, y1):
        return [x0 * self.k, y0 * self.k, x1 * self.k, y1 * self.k]

    def poly(self, points, v=255):
        self.d.polygon([(x * self.k, y * self.k) for x, y in points], fill=v)

    def path(self, text, v=255):
        self.poly(flatten(text), v)

    def circle(self, cx, cy, r, v=255):
        self.d.ellipse(self._box(cx - r, cy - r, cx + r, cy + r), fill=v)

    def ring(self, cx, cy, r, width, v=255):
        self.d.ellipse(self._box(cx - r, cy - r, cx + r, cy + r), outline=v, width=round(width * self.k))

    def rect(self, x0, y0, x1, y1, r=0, v=255):
        self.d.rounded_rectangle(self._box(x0, y0, x1, y1), radius=r * self.k, fill=v)

    def chord(self, cx, cy, r, start, end, v=255):
        self.d.chord(self._box(cx - r, cy - r, cx + r, cy + r), start, end, fill=v)

    def line(self, points, width, v=255):
        self.d.line([(x * self.k, y * self.k) for x, y in points], fill=v, width=round(width * self.k), joint="curve")
        for x, y in (points[0], points[-1]):  # round caps
            self.circle(x, y, width / 2, v)

    def turn(self, clockwise):
        """Turns everything drawn so far about the middle of the box."""
        self.img = self.img.rotate(-clockwise, resample=Image.BICUBIC)
        self.d = ImageDraw.Draw(self.img)


# ---------------------------------------------------------------------------
# Emblems
# ---------------------------------------------------------------------------
def flame(m):
    m.path("M50 4 C56 24 82 38 80 62 C78 82 64 96 50 96 C34 96 20 82 20 64 C20 50 29 42 33 28 "
           "C40 36 43 42 44 50 C51 38 54 22 50 4 Z")
    m.path("M50 56 C56 64 63 70 61 80 C60 88 55 92 50 92 C44 92 39 87 39 79 C39 69 47 65 50 56 Z", 0)


def bolt(m):
    m.poly([(62, 2), (20, 54), (45, 54), (34, 98), (82, 40), (56, 40), (70, 2)])


def shield(m):
    m.path("M50 4 L88 17 C88 52 77 80 50 96 C23 80 12 52 12 17 Z")
    m.path("M50 15 L78 25 C77 51 69 71 50 84 C31 71 23 51 22 25 Z", 0)
    m.rect(45, 26, 55, 72)
    m.rect(32, 37, 68, 47)


def sword(m):
    m.poly([(50, 0), (58, 12), (58, 60), (42, 60), (42, 12)])
    m.rect(24, 60, 76, 69, r=4)
    m.rect(45, 69, 55, 88)
    m.circle(50, 92, 7)
    m.turn(45)


def heart(m):
    m.path("M50 92 C16 68 4 46 10 28 C17 8 42 8 50 30 C58 8 83 8 90 28 C96 46 84 68 50 92 Z")


def leaf(m):
    m.path("M14 88 C8 44 40 10 90 10 C92 58 60 92 14 88 Z")
    m.line([(18, 84), (72, 28)], 4, 0)
    for a, b in (((36, 66), (38, 46)), ((36, 66), (56, 64)), ((54, 47), (56, 30)), ((54, 47), (72, 46))):
        m.line([a, b], 3, 0)


def sparkle(m):
    m.poly(star_points(44, 54, 44, 10, 4))
    m.poly(star_points(80, 20, 17, 4.5, 4))
    m.poly(star_points(82, 80, 11, 3, 4))


def star(m):
    m.poly(star_points(50, 54, 48, 20, 5))


def snowflake(m):
    for i in range(6):
        a = i * 60 - 90
        m.line([(50, 50), on_circle(50, 50, 44, a)], 7)
        for spread in (-24, 24):
            m.line([on_circle(50, 50, 26, a), on_circle(50, 50, 40, a + spread)], 6)


def moon(m):
    m.circle(46, 52, 40)
    m.circle(63, 40, 34, 0)
    m.poly(star_points(76, 30, 12, 3.5, 4))


def potion(m):
    m.rect(36, 4, 64, 15, r=3)
    m.rect(42, 13, 58, 40)
    m.circle(50, 64, 32)
    m.circle(50, 64, 24, 0)
    m.chord(50, 64, 24, 8, 172)  # the liquid
    m.circle(42, 54, 3.2)
    m.circle(56, 50, 2.4)


def arrow(m):
    m.line([(20, 80), (68, 32)], 7)
    m.poly([(90, 10), (56, 22), (78, 44)])
    for tail in ((20, 80), (30, 70)):
        m.line([tail, (tail[0] - 8, tail[1] - 14)], 6)
        m.line([tail, (tail[0] + 14, tail[1] + 8)], 6)


def paw(m):
    m.path("M50 50 C66 50 80 66 76 80 C72 92 60 86 50 86 C40 86 28 92 24 80 C20 66 34 50 50 50 Z")
    for x, y, r in ((19, 46, 10), (38, 26, 11), (62, 26, 11), (81, 46, 10)):
        m.circle(x, y, r)


def eye(m):
    m.path("M3 50 C24 18 76 18 97 50 C76 82 24 82 3 50 Z")
    m.circle(50, 50, 20, 0)
    m.circle(50, 50, 10)


def plus(m):
    m.rect(36, 10, 64, 90, r=7)
    m.rect(10, 36, 90, 64, r=7)


def swirl(m):
    points = []
    for i in range(160):
        t = i / 159
        points.append(on_circle(50, 50, 5 + 38 * t, t * 2.4 * 360))
    m.line(points, 9)


def hammer(m):
    m.rect(22, 14, 78, 42, r=7)
    m.rect(44, 42, 56, 92, r=3)
    m.turn(35)


def sun(m):
    m.circle(50, 50, 21)
    for i in range(8):
        m.line([on_circle(50, 50, 31, i * 45), on_circle(50, 50, 44, i * 45)], 7)


def drop(m):
    m.path("M50 3 C60 26 82 46 82 64 C82 84 68 97 50 97 C32 97 18 84 18 64 C18 46 40 26 50 3 Z")
    m.line([(32, 62), (35, 74), (45, 83)], 5, 0)


def target(m):
    m.ring(50, 50, 34, 8)
    m.circle(50, 50, 8)
    for a, b in (((50, 7), (50, 24)), ((50, 76), (50, 93)), ((7, 50), (24, 50)), ((76, 50), (93, 50))):
        m.line([a, b], 8)


def claw(m):
    for dx in (-26, 0, 26):
        m.path("M%g 6 C%g 34 %g 66 %g 94 C%g 66 %g 36 %g 6 Z"
               % (58 + dx, 72 + dx, 58 + dx, 32 + dx, 42 + dx, 50 + dx, 58 + dx))


def rune(m):
    m.poly([(50, 4), (90, 50), (50, 96), (10, 50)])
    m.poly([(50, 22), (74, 50), (50, 78), (26, 50)], 0)
    m.poly([(50, 36), (62, 50), (50, 64), (38, 50)])


def skull(m):
    m.circle(50, 42, 34)
    m.rect(32, 60, 68, 90, r=7)
    m.circle(36, 44, 10, 0)
    m.circle(64, 44, 10, 0)
    m.poly([(50, 54), (44, 66), (56, 66)], 0)
    for x in (42, 50, 58):
        m.line([(x, 80), (x, 92)], 2.6, 0)


def wave(m):
    for y in (28, 50, 72):
        m.line([(10 + i, y + 9 * math.sin((10 + i) / 80 * math.pi * 3)) for i in range(0, 81, 2)], 8)


def bomb(m):
    m.circle(46, 60, 32)
    m.rect(40, 20, 56, 32, r=2)
    m.line([(50, 20), (56, 10), (68, 8)], 4)
    m.poly(star_points(78, 10, 10, 3, 4))
    m.line([(28, 52), (32, 44), (40, 38)], 5, 0)


def crown(m):
    m.poly([(10, 74), (8, 26), (30, 50), (50, 16), (70, 50), (92, 26), (90, 74)])
    m.rect(10, 78, 90, 90, r=3)


def horseshoe(m):
    m.line([on_circle(50, 46, 31, a) for a in range(125, 416, 5)], 16)
    for a in (160, 215, 270, 325, 380):
        x, y = on_circle(50, 46, 31, a)
        m.circle(x, y, 2.6, 0)


def gear(m):
    for i in range(8):
        a = math.radians(i * 45)
        ca, sa = math.cos(a), math.sin(a)
        m.poly([(50 + r * ca - w * sa, 50 + r * sa + w * ca) for r, w in ((24, -9), (46, -7), (46, 7), (24, 9))])
    m.circle(50, 50, 33)
    m.circle(50, 50, 14, 0)


def bag(m):
    m.path("M32 38 C10 54 8 94 50 94 C92 94 90 54 68 38 Z")
    m.rect(32, 28, 68, 38, r=4)
    m.poly([(36, 28), (26, 8), (42, 16), (50, 6), (58, 16), (74, 8), (64, 28)])
    m.ring(50, 68, 12, 5, 0)


def bubble(m):
    m.rect(6, 12, 94, 72, r=18)
    m.poly([(26, 70), (20, 94), (50, 70)])
    for x in (30, 50, 70):
        m.circle(x, 42, 6, 0)


def chest(m):
    m.path("M10 46 C10 24 24 14 40 14 L60 14 C76 14 90 24 90 46 Z")
    m.rect(10, 52, 90, 90, r=5)
    m.rect(42, 40, 58, 64, r=4, v=0)
    m.rect(45, 43, 55, 61, r=3)
    m.circle(50, 51, 2.6, 0)


EMBLEMS = {f.__name__: f for f in (
    flame, bolt, shield, sword, heart, leaf, sparkle, star, snowflake, moon, potion, arrow, paw, eye, plus, swirl,
    hammer, sun, drop, target, claw, rune, skull, wave, bomb, crown, horseshoe, gear, bag, bubble, chest)}

# The icons the mock-ups use, by number: (emblem, hue from 0 to 1).
ICONS = [
    ("flame", 0.04), ("bolt", 0.61), ("shield", 0.57), ("sword", 0.00), ("heart", 0.94), ("leaf", 0.32),
    ("sparkle", 0.76), ("snowflake", 0.53), ("moon", 0.68), ("potion", 0.98), ("arrow", 0.22), ("paw", 0.08),
    ("eye", 0.82), ("plus", 0.13), ("swirl", 0.47), ("hammer", 0.11), ("sun", 0.14), ("drop", 0.56),
    ("target", 0.02), ("claw", 0.96), ("rune", 0.72), ("skull", 0.78), ("star", 0.12), ("wave", 0.50),
    ("bomb", 0.06), ("crown", 0.15), ("horseshoe", 0.09), ("gear", 0.62), ("bag", 0.10), ("potion", 0.58),
    ("chest", 0.07), ("bubble", 0.58),
]


# ---------------------------------------------------------------------------
# Tiles
# ---------------------------------------------------------------------------
def hsv(h, s, v):
    return tuple(int(round(c * 255)) for c in colorsys.hsv_to_rgb(h % 1.0, s, v))


def solid(colour, mask, opacity=1.0):
    out = Image.new("RGBA", mask.size, colour + (255,))
    out.putalpha(mask.point(lambda v: int(v * opacity)) if opacity != 1.0 else mask)
    return out


@functools.lru_cache(maxsize=None)
def emblem(name, px=256):
    """The bare emblem as an 8-bit mask."""
    mask = Mask(px * SS)
    EMBLEMS[name](mask)
    return mask.img.resize((px, px), Image.LANCZOS)


@functools.lru_cache(maxsize=None)
def tile(name, hue, px=256):
    """An emblem on a tile of the given hue, lit from the upper left and darker towards the rim."""
    y, x = np.mgrid[0:px, 0:px].astype(np.float32) / (px - 1)
    lit = (1 - np.clip(np.hypot(x - 0.40, y - 0.34) / 0.80, 0, 1))[..., None] ** 1.25
    rgb = np.array(hsv(hue, 0.60, 0.96), np.float32) * lit + np.array(hsv(hue + 0.035, 0.88, 0.20), np.float32) * (1 - lit)
    rim = np.maximum(np.abs(x - 0.5), np.abs(y - 0.5))[..., None] * 2
    rgb *= 1 - 0.38 * np.clip((rim - 0.72) / 0.28, 0, 1) ** 1.5
    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").convert("RGBA")

    inner = round(px * 0.74)
    art = Image.new("L", (px, px), 0)
    art.paste(emblem(name, inner), ((px - inner) // 2, (px - inner) // 2))
    glow = art.filter(ImageFilter.GaussianBlur(px * 0.06))
    shadow = ImageChops.offset(art.filter(ImageFilter.GaussianBlur(px * 0.025)), 0, round(px * 0.03))
    for layer in (solid(hsv(hue, 0.18, 1.0), glow, 0.45), solid((0, 0, 0), shadow, 0.55)):
        img = Image.alpha_composite(img, layer)

    t = np.linspace(0, 1, px, dtype=np.float32)[:, None, None]
    fill = np.array((255, 255, 255), np.float32) * (1 - t) + np.array(hsv(hue, 0.20, 0.90), np.float32) * t
    face = Image.fromarray(np.broadcast_to(fill, (px, px, 3)).astype(np.uint8), "RGB").convert("RGBA")
    face.putalpha(art)
    return Image.alpha_composite(img, face)


def icon(number, px=256):
    """Stand-in icon by number; the numbers wrap around."""
    name, hue = ICONS[number % len(ICONS)]
    return tile(name, hue, px)


def sheet():
    cell, cols = 128, 8
    rows = (len(ICONS) + cols - 1) // cols
    out = Image.new("RGBA", (cols * cell, rows * cell), (38, 42, 52, 255))
    for i in range(len(ICONS)):
        out.alpha_composite(icon(i, 112), ((i % cols) * cell + 8, (i // cols) * cell + 8))
    return out


if __name__ == "__main__":
    path = os.path.join(ROOT, "docs", "placeholder-icons.png")
    sheet().convert("RGB").save(path)
    print("wrote", path)
