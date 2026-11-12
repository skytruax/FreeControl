#!/usr/bin/env python3
"""Draws the pictures for the CurseForge page and the README.

    python3 tools/make_listing.py              # all of them
    python3 tools/make_listing.py hero sets    # only the ones named

  curseforge/logo.png                    the project avatar: 400 x 400, as CurseForge requires
  curseforge/gallery/01-hero.png         title picture
  curseforge/gallery/02-sets.png         the four sets
  curseforge/gallery/03-drop.png         drag and drop
  curseforge/gallery/04-interact.png     the Interact button
  curseforge/gallery/05-normal-mode.png  what stays as it is
  curseforge/gallery/06-combat.png       what a slot shows in combat
  curseforge/gallery/07-controllers.png  Xbox, PlayStation and Nintendo labels
  curseforge/gallery/08-controls.png     a labelled diagram of the empty bar
  docs/banner.png                        the README header
  docs/demo.gif                          the README animation: the four sets, one after the other
  docs/social.png                        for GitHub's Settings > Social preview

Every one is an illustration built from the addon's own textures and layout numbers, with stand-in
spell icons, and says so on the picture. Screenshots have to come from the game.
"""
import functools
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

import make_art
import placeholder_icons
import preview
from preview import CONTENT, COUNTS, LAYOUT, STATES, Painter, paste, sized

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "curseforge")
GALLERY = os.path.join(OUT, "gallery")
DOCS = os.path.join(ROOT, "docs")

W, H = 1920, 1080
BRONZE_LIGHT = (232, 206, 144)
BRONZE_DARK = (82, 60, 30)
INK = (8, 8, 10)
WHITE = (246, 246, 250, 255)
SOFT = (184, 192, 210, 255)
DIM = (140, 148, 168, 255)
GOLD = (255, 214, 96, 255)
TAGLINE = "Play with a controller. Keep the rest of your game."
NOTE = "Illustration made from the addon's own artwork. Spell icons are placeholders. Not a screenshot."


# ---------------------------------------------------------------------------
# Small drawing helpers
# ---------------------------------------------------------------------------
def font(size, weight="Bold"):
    for path in (os.path.expanduser("~/.local/share/fonts/Inter/Inter-%s.ttf" % weight),
                 "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
        if os.path.exists(path):
            return ImageFont.truetype(path, round(size))
    raise FileNotFoundError("no font found; add one to font() in tools/make_listing.py")


def vertical(size, top, bottom):
    w, h = size
    t = np.linspace(0, 1, h)[:, None, None]
    row = np.array(top, dtype=np.float32) * (1 - t) + np.array(bottom, dtype=np.float32) * t
    return Image.fromarray(np.broadcast_to(row, (h, w, 3)).astype(np.uint8), "RGB")


def masked(fill, mask, opacity=1.0):
    if isinstance(fill, tuple):
        fill = Image.new("RGB", mask.size, fill)
    out = fill.convert("RGBA")
    out.putalpha(mask.point(lambda v: int(v * opacity)) if opacity != 1.0 else mask)
    return out


def noise(size, strength, seed):
    rng = np.random.default_rng(seed)
    w, h = size
    grain = rng.normal(0, strength, (h // 3 + 1, w // 3 + 1)).astype(np.float32)
    return np.asarray(Image.fromarray(grain).resize((w, h), Image.BICUBIC))[..., None]


def drawn(w, h, paint, ss=4):
    """A w x h layer that `paint(draw, scale)` drew on. It is drawn `ss` times larger and scaled
    down, because the drawing calls themselves do not smooth their edges."""
    w, h = round(w), round(h)
    layer = Image.new("RGBA", (w * ss, h * ss), (0, 0, 0, 0))
    paint(ImageDraw.Draw(layer), ss)
    return layer.resize((w, h), Image.LANCZOS)


def box(canvas, rect, radius, fill, outline=None, width=2):
    """A rounded rectangle, blended onto the canvas."""
    x0, y0, x1, y1 = [round(v) for v in rect]
    w, h = x1 - x0, y1 - y0
    canvas.alpha_composite(drawn(w, h, lambda d, s: d.rounded_rectangle(
        (0, 0, w * s - 1, h * s - 1), radius=radius * s, fill=fill, outline=outline, width=width * s)), (x0, y0))


def text(canvas, xy, string, size, fill=WHITE, weight="Bold", anchor="mm"):
    ImageDraw.Draw(canvas).text(xy, string, font=font(size, weight), fill=fill, anchor=anchor)


def shadow_text(canvas, xy, string, size, fill=WHITE, weight="Bold", anchor="mm", spread=10, strength=0.75):
    """Text with a soft dark halo, for writing over a picture."""
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).text((xy[0], xy[1] + size * 0.05), string, font=font(size, weight),
                               fill=(0, 0, 0, round(255 * strength)), anchor=anchor)
    canvas.alpha_composite(layer.filter(ImageFilter.GaussianBlur(spread)))
    text(canvas, xy, string, size, fill, weight, anchor)


def headline(canvas, cx, y, parts, size):
    """One centred line made of (text, colour) parts."""
    d, f = ImageDraw.Draw(canvas), font(size, "Black")
    widths = [d.textlength(string, font=f) for string, _ in parts]
    x = cx - sum(widths) / 2
    for (string, colour), width in zip(parts, widths):
        d.text((x, y), string, font=f, fill=colour, anchor="lm")
        x += width


def pills(canvas, cx, cy, labels, size=28, height=58, fill=(255, 255, 255, 18), outline=(255, 255, 255, 64)):
    """A centred row of rounded labels."""
    f, pad, gap = font(size, "SemiBold"), 30, 18
    widths = [ImageDraw.Draw(canvas).textlength(label, font=f) + 2 * pad for label in labels]
    x = cx - (sum(widths) + gap * (len(labels) - 1)) / 2
    for label, width in zip(labels, widths):
        box(canvas, (x, cy - height / 2, x + width, cy + height / 2), height / 2, fill, outline)
        ImageDraw.Draw(canvas).text((x + width / 2, cy), label, font=f, fill=WHITE, anchor="mm")
        x += width + gap


@functools.lru_cache(maxsize=None)
def big_art():
    """The addon's textures drawn at three times their shipped size, for the large pictures."""
    out = {name: img.resize((w * 3, h * 3), Image.LANCZOS) for name, (img, w, h) in make_art.drawings(12).items()}
    out["Set-Glow"] = preview.tex("Set-Glow")  # a smooth gradient; nothing to gain from redrawing it
    return out


def big(name):
    return big_art()[name]


# ---------------------------------------------------------------------------
# Logo
# ---------------------------------------------------------------------------
@functools.lru_cache(maxsize=None)
def logo():
    ss, n = 4, 400
    size = (n * ss, n * ss)

    def shape(kind, rect, radius=0):
        m = Image.new("L", size, 0)
        d = ImageDraw.Draw(m)
        rect = [v * ss for v in rect]
        if kind == "round":
            d.ellipse(rect, fill=255)
        else:
            d.rounded_rectangle(rect, radius=radius * ss, fill=255)
        return m

    def blur(img, radius):
        return img.filter(ImageFilter.GaussianBlur(radius * ss))

    def ring(kind, rect, width, radius=0, light=BRONZE_LIGHT, dark=BRONZE_DARK):
        x0, y0, x1, y1 = rect
        outer = shape(kind, rect, radius)
        inner = shape(kind, (x0 + width, y0 + width, x1 - width, y1 - width), max(radius - width, 0))
        band = ImageChops.subtract(outer, inner)
        # Shade over the ring's own height, so every ring is lit the same way.
        grad = Image.new("RGB", size, dark)
        grad.paste(vertical((size[0], int((y1 - y0) * ss)), light, dark), (0, int(y0 * ss)))
        body = masked(grad, band)
        edge = ImageChops.subtract(outer, shape(kind, (x0 + 1.5, y0 + 1.5, x1 - 1.5, y1 - 1.5), max(radius - 1.5, 0)))
        inner_edge = ImageChops.subtract(
            shape(kind, (x0 + width - 1.5, y0 + width - 1.5, x1 - width + 1.5, y1 - width + 1.5), max(radius - width + 1.5, 0)), inner)
        return Image.alpha_composite(Image.alpha_composite(body, masked(INK, edge, 0.85)), masked(INK, inner_edge, 0.7)), inner

    # Plate: dark slate with grain and a warm light from the lit button, inside a bronze frame.
    plate_mask = shape("square", (6, 6, n - 6, n - 6), 74)
    base = np.asarray(vertical(size, (46, 52, 70), (12, 14, 22))).astype(np.float32) + noise(size, 5, 3)
    img = masked(Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB"), plate_mask)

    centre, reach, radius = (200, 214), 82, 56
    spots = {"top": (0, -reach), "left": (-reach, 0), "right": (reach, 0), "bottom": (0, reach)}
    lit = "left"

    lx, ly = centre[0] + spots[lit][0], centre[1] + spots[lit][1]
    glow = blur(shape("round", (lx - 96, ly - 96, lx + 96, ly + 96)), 34)
    img = Image.alpha_composite(img, masked((255, 196, 96), ImageChops.multiply(glow, plate_mask), 0.5))

    for name, (dx, dy) in spots.items():
        cx, cy = centre[0] + dx, centre[1] + dy
        rect = (cx - radius, cy - radius, cx + radius, cy + radius)
        shadow = blur(shape("round", (rect[0] - 4, rect[1] + 2, rect[2] + 4, rect[3] + 12)), 7)
        img = Image.alpha_composite(img, masked((0, 0, 0), ImageChops.multiply(shadow, plate_mask), 0.6))
        if name == lit:
            band, well = ring("round", rect, 13, light=(255, 246, 198), dark=(196, 138, 34))
            fill = vertical(size, (255, 226, 130), (214, 140, 30))
        else:
            band, well = ring("round", rect, 13)
            fill = vertical(size, (40, 46, 62), (14, 16, 24))
        img = Image.alpha_composite(img, masked(fill, well))
        # A soft shade inside the rim gives the well some depth.
        rim = blur(ImageChops.subtract(well, shape("round", (rect[0] + 26, rect[1] + 30, rect[2] - 26, rect[3] - 18))), 5)
        img = Image.alpha_composite(img, masked((0, 0, 0), ImageChops.multiply(rim, well), 0.4 if name == lit else 0.55))
        img = Image.alpha_composite(img, band)

    # The two triggers, as pills above the buttons; the left one is held.
    for side, x in (("left", 62), ("right", 226)):
        rect = (x, 54, x + 112, 100)
        held = side == "left"
        shadow = blur(shape("square", (rect[0] - 3, rect[1] + 2, rect[2] + 3, rect[3] + 9), 23), 5)
        img = Image.alpha_composite(img, masked((0, 0, 0), ImageChops.multiply(shadow, plate_mask), 0.55))
        band, well = ring("square", rect, 9, 23, *(((255, 246, 198), (196, 138, 34)) if held else (BRONZE_LIGHT, BRONZE_DARK)))
        fill = vertical(size, (255, 226, 130), (214, 140, 30)) if held else vertical(size, (40, 46, 62), (14, 16, 24))
        img = Image.alpha_composite(Image.alpha_composite(img, masked(fill, well)), band)

    frame, _ = ring("square", (6, 6, n - 6, n - 6), 12, 74)
    img = Image.alpha_composite(img, frame)
    return img.resize((n, n), Image.LANCZOS)


# ---------------------------------------------------------------------------
# Backgrounds
# ---------------------------------------------------------------------------
def backdrop(w, h, glows=(), seed=11):
    """Dark slate, lighter towards the middle. glows: (x, y, radius x, radius y, strength) of warm light."""
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    dist = np.hypot((x - w / 2) / (w / 2), (y - h * 0.52) / (h / 2))
    base = np.array((38, 44, 60), dtype=np.float32) * np.clip(1.08 - 0.5 * dist, 0.35, 1.1)[..., None]
    for gx, gy, rx, ry, strength in glows:
        fall = np.clip(1 - np.hypot((x - gx) / rx, (y - gy) / ry), 0, 1)[..., None] ** 2
        base = base + np.array((255, 190, 100), dtype=np.float32) * fall * strength
    base = base + noise((w, h), 2.5, seed)
    return Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def ridge(w, rng, sharp):
    """The outline of a line of hills as heights from 0 to 1; sharp gives pointed peaks."""
    x = np.linspace(0, 1, w, dtype=np.float32)
    total = np.zeros(w, np.float32)
    amp, knots = 1.0, 4
    for _ in range(6):
        values = rng.uniform(-1, 1, knots + 1).astype(np.float32)
        pos = x * knots
        i = np.minimum(pos.astype(np.int32), knots - 1)
        t = (1 - np.cos((pos - i) * np.pi)) / 2
        total += amp * (values[i] * (1 - t) + values[i + 1] * t)
        amp *= 0.5
        knots *= 2
    if sharp:
        total = -np.abs(total)
    total -= total.min()
    return total / total.max()


def landscape(w, h, seed=4):
    """A flat, stylised dusk: sky, stars and five lines of hills. It stands in for the game world
    behind the bar and is plainly a drawing."""
    rng = np.random.default_rng(seed)
    stops = [(0.0, (8, 11, 28)), (0.30, (22, 25, 62)), (0.50, (66, 46, 100)), (0.62, (166, 88, 104)),
             (0.72, (240, 152, 98)), (1.0, (240, 152, 98))]
    rows = np.linspace(0, 1, h, dtype=np.float32)
    sky = np.stack([np.interp(rows, [p for p, _ in stops], [c[i] for _, c in stops]) for i in range(3)], axis=-1)
    sky = np.broadcast_to(sky[:, None, :], (h, w, 3)).astype(np.float32)
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    sun = np.clip(1 - np.hypot((x - 0.66 * w) / (0.42 * w), (y - 0.62 * h) / (0.36 * h)), 0, 1)[..., None] ** 2
    img = Image.fromarray(np.clip(sky + np.array((255, 176, 110), np.float32) * sun * 0.45, 0, 255).astype(np.uint8),
                          "RGB").convert("RGBA")

    stars = Image.new("RGBA", (w * 2, h * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(stars)
    for _ in range(int(w * h / 8000)):
        sx, sy = rng.uniform(0, w), rng.uniform(0, h * 0.46)
        alpha = rng.uniform(0.25, 1.0) * (1 - sy / (h * 0.46)) ** 1.3
        r = rng.choice([0.8, 1.0, 1.0, 1.7])
        d.ellipse([(sx - r) * 2, (sy - r) * 2, (sx + r) * 2, (sy + r) * 2], fill=(255, 250, 240, int(255 * alpha)))
    img.alpha_composite(stars.resize((w, h), Image.LANCZOS))

    haze = np.array((196, 128, 140), np.float32)
    # base line and height as fractions of the picture, colour, pointed peaks, haze, number of trees
    layers = [(0.66, 0.21, (98, 80, 132), True, 0.40, 0), (0.71, 0.15, (70, 62, 114), True, 0.34, 0),
              (0.77, 0.11, (46, 48, 92), False, 0.26, 0), (0.84, 0.08, (27, 32, 64), False, 0.14, 50),
              (0.93, 0.07, (13, 17, 36), False, 0.0, 80)]
    for base, amp, colour, sharp, mist, trees in layers:
        top = base * h - amp * h * ridge(w, rng, sharp)
        alpha = np.clip(y - top[None, :] + 0.5, 0, 1)
        t = np.clip((y - (base - amp) * h) / ((amp + 0.07) * h), 0, 1)[..., None] * mist
        fill = np.array(colour, np.float32) * (1 - t) + haze * t  # mistier lower down, where the next line begins
        layer = Image.fromarray(np.concatenate([fill, alpha[..., None] * 255], axis=-1).clip(0, 255).astype(np.uint8), "RGBA")
        if trees:
            forest = Image.new("RGBA", (w * 2, h * 2), (0, 0, 0, 0))
            d = ImageDraw.Draw(forest)
            for _ in range(trees):
                tx = rng.uniform(0, w - 1)
                ty, th = top[int(tx)] + 3, rng.uniform(0.022, 0.05) * h
                d.polygon([(tx * 2, (ty - th) * 2), ((tx - th * 0.21) * 2, ty * 2), ((tx + th * 0.21) * 2, ty * 2)],
                          fill=colour + (255,))
            layer = Image.alpha_composite(forest.resize((w, h), Image.LANCZOS), layer)
        img.alpha_composite(layer)

    rgb = np.asarray(img.convert("RGB")).astype(np.float32)
    dist = np.hypot((x - w / 2) / (w / 2), (y - h / 2) / (h / 2))
    rgb = rgb * np.clip(1.06 - 0.26 * dist ** 2, 0, 1.06)[..., None] + noise((w, h), 2.0, seed)
    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


# ---------------------------------------------------------------------------
# Title pictures: the bar over the landscape
# ---------------------------------------------------------------------------
def hero(w=W, h=H, k=2.2, title_y=150, title_size=150, tagline_size=46, bar_y=650, chips=(), note_size=18):
    canvas = landscape(w, h)
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    shade = np.clip(1 - np.hypot((x - w / 2) / (0.62 * w), (y - bar_y) / (0.44 * h)), 0, 1) ** 1.2 * 0.52
    scrim = np.zeros((h, w, 4), np.float32)
    scrim[..., :3] = (6, 8, 18)
    scrim[..., 3] = shade * 255
    canvas.alpha_composite(Image.fromarray(scrim.astype(np.uint8), "RGBA"))  # keeps the bar readable

    Painter(k, big).bar(canvas, w / 2, bar_y, 2, "xbox", CONTENT, STATES, COUNTS)
    shadow_text(canvas, (w / 2, title_y), "FreeControl", title_size, WHITE, "Black")
    shadow_text(canvas, (w / 2, title_y + title_size * 0.76), TAGLINE, tagline_size, (238, 240, 248, 255), "SemiBold", spread=7)
    if chips:
        pills(canvas, w / 2, h - 96, chips, 28, 58, (8, 10, 20, 150), (255, 255, 255, 76))
    shadow_text(canvas, (w / 2, h - 26), NOTE, note_size, (206, 210, 224, 255), "Medium", spread=4, strength=0.9)
    return canvas


def gallery_hero():
    return hero(chips=("32 buttons on two triggers", "Drag and drop spells, items and macros", "Gamepad UI mode stays off"))


def banner():
    return hero(1600, 600, 1.5, 84, 96, 31, 388, note_size=15)


def social():
    return hero(1280, 640, 1.28, 96, 104, 31, 420, note_size=14)


# ---------------------------------------------------------------------------
# Feature pictures
# ---------------------------------------------------------------------------
def slide(parts, sub, glows=()):
    canvas = backdrop(W, H, glows)
    canvas.alpha_composite(logo().resize((56, 56), Image.LANCZOS), (72, 50))
    text(canvas, (142, 79), "FreeControl", 30, WHITE, "Bold", "lm")
    headline(canvas, W / 2, 196, parts, 84)
    text(canvas, (W / 2, 278), sub, 32, SOFT, "Medium")
    text(canvas, (W / 2, H - 34), NOTE, 20, DIM, "Medium")
    return canvas


def hold_label(canvas, x, y, label, badges, size=30):
    """"Hold" followed by trigger badges, starting at x."""
    d, f = ImageDraw.Draw(canvas), font(size)
    d.text((x, y), label, font=f, fill=WHITE, anchor="lm")
    x += d.textlength(label, font=f) + 14
    for i, name in enumerate(badges):
        if i:
            d = ImageDraw.Draw(canvas)
            d.text((x + 2, y), "+", font=f, fill=WHITE, anchor="lm")
            x += d.textlength("+", font=f) + 14
        canvas.alpha_composite(sized(big("Badge-" + name), 76, 38), (round(x), round(y - 19)))
        x += 76 + 10


def sets():
    canvas = slide([("Hold a trigger. ", WHITE), ("Get a new set.", GOLD)],
                   "Four sets of eight on the D-pad and face buttons. The one you hold grows and lights up.")
    painter = Painter(1.08, big)
    panels = [(0, "No trigger", [], "4 action slots, Interact, Cancel and Jump"), (1, "Hold", ["LT"], "8 action slots"),
              (2, "Hold", ["RT"], "8 action slots"), (3, "Hold", ["LT", "RT"], "8 action slots")]
    pw, ph, gap = 880, 320, 32
    x0 = (W - 2 * pw - gap) / 2
    for i, (held, label, badges, sub) in enumerate(panels):
        x, y = x0 + (i % 2) * (pw + gap), 336 + (i // 2) * (ph + 20)
        box(canvas, (x, y, x + pw, y + ph), 28, (255, 255, 255, 10), (255, 255, 255, 32))
        painter.bar(canvas, x + pw / 2, y + 198, held, "xbox", CONTENT, STATES, COUNTS)
        hold_label(canvas, x + 34, y + 46, label, badges)
        text(canvas, (x + pw - 34, y + 46), sub, 22, SOFT, "Medium", "rm")
    return canvas


def cubic(p0, p1, p2, p3, n=120):
    t = np.linspace(0, 1, n)[:, None]
    return (1 - t) ** 3 * np.array(p0) + 3 * (1 - t) ** 2 * t * np.array(p1) + 3 * (1 - t) * t ** 2 * np.array(p2) + t ** 3 * np.array(p3)


def dashed(canvas, points, colour, width=5, dash=18, gap=14):
    """A dashed line through `points`, ending in an arrowhead."""
    ss = 3
    layer = Image.new("RGBA", (canvas.width * ss // 2, canvas.height * ss // 2), (0, 0, 0, 0))  # at 1.5x: enough for a soft line
    scale = ss / 2
    d = ImageDraw.Draw(layer)
    lengths = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(points, axis=0).T))])
    for a, b, start in zip(points[:-1], points[1:], lengths[:-1]):
        if start % (dash + gap) < dash and start < lengths[-1] - 22:
            d.line([tuple(a * scale), tuple(b * scale)], fill=colour, width=round(width * scale))
            r = width * scale / 2
            d.ellipse([b[0] * scale - r, b[1] * scale - r, b[0] * scale + r, b[1] * scale + r], fill=colour)
    tip, back = points[-1], points[-8]
    along = (tip - back) / np.hypot(*(tip - back))
    across = np.array([-along[1], along[0]])
    d.polygon([tuple(tip * scale), tuple((tip - along * 26 + across * 13) * scale), tuple((tip - along * 26 - across * 13) * scale)],
              fill=colour)
    canvas.alpha_composite(layer.resize(canvas.size, Image.LANCZOS))


def rounded_icon(number, size, radius=16, alpha=1.0):
    """A stand-in icon as it would look in a spellbook or bag: a plain tile with a dark edge."""
    icon = sized(placeholder_icons.icon(number), size, size)
    mask = drawn(size, size, lambda d, s: d.rounded_rectangle((0, 0, size * s - 1, size * s - 1), radius=radius * s, fill=(255, 255, 255, 255)))
    icon.putalpha(mask.getchannel("A"))
    edge = drawn(size, size, lambda d, s: d.rounded_rectangle((0, 0, size * s - 1, size * s - 1), radius=radius * s,
                                                              outline=(8, 9, 14, 255), width=3 * s))
    return preview.faded(Image.alpha_composite(icon, edge), alpha)


def cursor(size=58):
    """A mouse pointer with a soft shadow."""
    outline = [(4, 2), (4, 44), (14, 34), (22, 52), (31, 48), (23, 31), (38, 31)]
    k = size / 58
    arrow = drawn(size, size, lambda d, s: d.polygon([(x * k * s, y * k * s) for x, y in outline], fill=(250, 250, 252, 255),
                                                     outline=(14, 16, 24, 255), width=round(3 * k * s)))
    shadow = Image.new("RGBA", arrow.size, (0, 0, 0, 255))
    shadow.putalpha(arrow.getchannel("A").filter(ImageFilter.GaussianBlur(4)).point(lambda v: int(v * 0.6)))
    out = Image.new("RGBA", (size + 12, size + 12), (0, 0, 0, 0))
    out.alpha_composite(shadow, (9, 10))
    out.alpha_composite(arrow, (4, 4))
    return out


def drop():
    canvas = slide([("Drop anything, ", WHITE), ("anywhere.", GOLD)],
                   "Drag spells, items and macros onto any slot. Cooldowns, counts and range show like a normal action bar.")
    groups = [("SPELLS", [1, 0, 7, 4]), ("ITEMS", [9, 28, 26]), ("MACROS", [27, 18, 6])]
    tile, gap, group_gap, top = 100, 14, 64, 372
    total = sum(len(icons) * tile + (len(icons) - 1) * gap for _, icons in groups) + group_gap * (len(groups) - 1)
    x = (W - total) / 2
    picked = None
    for label, icons in groups:
        width = len(icons) * tile + (len(icons) - 1) * gap
        text(canvas, (x + width / 2, top - 26), label, 19, DIM, "Bold")
        for n, number in enumerate(icons):
            first = picked is None
            canvas.alpha_composite(rounded_icon(number, tile, alpha=0.32 if first else 1.0), (round(x + n * (tile + gap)), top))
            if first:
                picked = (number, x + tile / 2, top + tile)
        x += width + group_gap

    # The bar with the slot under the picked spell still empty; that is where it is headed.
    content = {set_id: list(row) for set_id, row in CONTENT.items()}
    content[1][0] = None
    painter = Painter(1.72, big)
    ox, oy = W / 2, 748
    tx, ty = painter.button_centre(ox, oy, 1, 1)
    painter.bar(canvas, ox, oy, 0, "xbox", content, {**STATES, (1, 1): "hover"}, COUNTS)

    number, sx, sy = picked
    path = cubic((sx, sy + 12), (sx + 90, sy + 90), (tx + 90, ty - 150), (tx, ty - 46))
    dashed(canvas, path, GOLD)
    fx, fy = path[52]
    flying = rounded_icon(number, 92).rotate(8, resample=Image.BICUBIC, expand=True)
    shadow = Image.new("RGBA", flying.size, (0, 0, 0, 255))
    shadow.putalpha(flying.getchannel("A").filter(ImageFilter.GaussianBlur(8)).point(lambda v: int(v * 0.55)))
    paste(canvas, shadow, fx + 6, fy + 12)
    paste(canvas, flying, fx, fy)
    canvas.alpha_composite(cursor(), (round(fx + 6), round(fy + 2)))
    text(canvas, (W / 2, 978), "The same slots as Blizzard's controller bars: anything you set up in Gamepad UI mode is already here.",
         24, DIM, "Medium")
    return canvas


def interact():
    bx, by = 430, 630
    canvas = slide([("One button ", WHITE), ("for the world.", GOLD)],
                   "Press Interact and the game picks what is in reach. Loot, talk and open without the mouse.",
                   glows=[(bx, by, 520, 420, 0.42)])
    Painter(7.4, big).button(canvas, bx, by, 5, preview.STYLES["xbox"][0], ("role", "Interact"))
    canvas.alpha_composite(sized(big("Glyph-X"), 64, 64), (bx - 128, by + 168))
    text(canvas, (bx - 50, by + 200), "Interact", 46, WHITE, "Black", "lm")
    text(canvas, (bx, by + 258), "the left face button, with no trigger held", 23, SOFT, "Medium")

    arrow = np.array([(bx + 178 + i, by) for i in range(0, 121, 4)], dtype=np.float64)
    dashed(canvas, arrow, GOLD, 6, 1000, 0)

    cards = [(28, "Loot", "the corpse next to you"), (31, "Talk", "to the NPC facing you"),
             (30, "Open", "the chest in reach"), (3, "Attack", "when nothing else is near")]
    cw, ch, gap, x0, y0 = 536, 184, 24, 772, 430
    for i, (number, title, sub) in enumerate(cards):
        x, y = x0 + (i % 2) * (cw + gap), y0 + (i // 2) * (ch + gap)
        box(canvas, (x, y, x + cw, y + ch), 26, (255, 255, 255, 12), (255, 255, 255, 34))
        canvas.alpha_composite(rounded_icon(number, 112, 20), (x + 36, y + (ch - 112) // 2))
        text(canvas, (x + 180, y + ch / 2 - 22), title, 40, WHITE, "Bold", "lm")
        text(canvas, (x + 180, y + ch / 2 + 26), sub, 24, SOFT, "Medium", "lm")
    text(canvas, (x0 + cw + gap / 2, y0 + 2 * ch + gap + 58),
         "The game's own Interact command, with the reach Gamepad UI mode gives it.", 24, DIM, "Medium")
    return canvas


def tick(size=48):
    return drawn(size, size, lambda d, s: (
        d.ellipse((0, 0, size * s - 1, size * s - 1), fill=GOLD),
        d.line([(13 * s, 25 * s), (21 * s, 33 * s), (36 * s, 16 * s)], fill=(24, 22, 16, 255), width=5 * s, joint="curve")))


def normal_mode():
    canvas = slide([("Your game stays ", WHITE), ("in normal mode.", GOLD)],
                   "FreeControl adds one bar. Gamepad UI mode stays off, and everything else stays the way you set it up.")
    rows = [("Targeting stays yours", "Bind bumpers and stick clicks in the usual Key Bindings."),
            ("The menus you know", "Bags, map, character sheet, vendors: the regular windows."),
            ("Your layout and addons", "Nothing is moved, hidden or replaced."),
            ("Your action bars", "Untouched. FreeControl uses the controller bars' own slots."),
            ("Your settings", "The few it changes are put back when you log out.")]
    for i, (title, sub) in enumerate(rows):
        y = 404 + i * 112
        canvas.alpha_composite(tick(), (104, y - 24))
        text(canvas, (176, y - 15), title, 34, WHITE, "Bold", "lm")
        text(canvas, (176, y + 25), sub, 23, SOFT, "Medium", "lm")

    # A schematic of the screen: the game's own interface in grey, the one added bar in colour.
    sx, sy, sw, sh = 990, 372, 850, 478
    box(canvas, (sx, sy, sx + sw, sy + sh), 22, (10, 12, 22, 255), (255, 255, 255, 56), 3)
    grey, edge = (255, 255, 255, 16), (255, 255, 255, 46)

    def block(rect, radius=8):
        x0, y0, x1, y1 = rect
        box(canvas, (sx + x0, sy + y0, sx + x1, sy + y1), radius, grey, edge)

    def label(x, y, string, anchor="mm"):
        text(canvas, (sx + x, sy + y), string, 16, DIM, "Medium", anchor)

    for x in (28, 222):                                   # player and target frames
        block((x, 28, x + 176, 80))
        block((x + 8, 36, x + 44, 72), 18)
        block((x + 54, 40, x + 166, 52), 5)
        block((x + 54, 58, x + 140, 68), 5)
    label(213, 98, "Unit frames")
    block((sw - 142, 26, sw - 30, 138), 56)              # minimap
    label(sw - 86, 156, "Minimap")
    for i, width in enumerate((120, 96, 132)):            # quest list
        block((sw - 162, 196 + i * 22, sw - 162 + width, 208 + i * 22), 5)
    block((28, 300, 168, 426))                            # chat
    for i, width in enumerate((116, 88, 122, 72)):
        block((38, 314 + i * 26, 38 + width, 326 + i * 26), 5)
    label(98, 446, "Chat")
    bar_w = 12 * 30 + 11 * 5                              # the regular action bar
    for i in range(12):
        x = (sw - bar_w) / 2 + i * 35
        block((x, 396, x + 30, 426), 6)
    label(sw / 2, 446, "Your action bars")
    for i in range(5):                                    # menu buttons and bags
        block((sw - 170 + i * 29, 400, sw - 170 + i * 29 + 24, 424), 5)
    label(sw - 100, 446, "Menus and bags")

    cx, cy = sx + sw / 2, sy + 262
    Painter(0.58, big).bar(canvas, cx, cy, 2, "xbox", CONTENT, STATES)
    box(canvas, (cx - 244, cy - 76, cx + 244, cy + 74), 16, (0, 0, 0, 0), GOLD, 3)
    text(canvas, (cx, cy - 100), "FreeControl: the one thing added", 22, GOLD, "Bold")
    text(canvas, (sx + sw / 2, sy + sh + 44), "Everything in grey is the game's normal interface, as you have it.", 24, DIM, "Medium")
    return canvas


def combat():
    canvas = slide([("Made for ", WHITE), ("combat.", GOLD)],
                   "Every slot shows what a normal action bar shows, and your abilities fire on the press.")
    shown = [(1, ("icon", 0), "cooldown", None, "Cooldowns", "the familiar sweep"),
             (5, ("icon", 10), "range", None, "Out of range", "turns red"),
             (2, ("icon", 6), "nomana", None, "Not enough mana", "turns blue"),
             (6, ("icon", 3), "unusable", None, "Not usable yet", "goes dark"),
             (3, ("icon", 9), "normal", "5", "Item counts", "how many are left"),
             (7, ("icon", 14), "checked", None, "In progress", "gold ring while it runs")]
    painter, face = Painter(4.6, big), preview.STYLES["xbox"][0]
    for i, (index, content, state, count, title, sub) in enumerate(shown):
        x = 235 + i * 290
        painter.button(canvas, x, 560, index, face, content, state=state, count=count)
        text(canvas, (x, 694), title, 29, WHITE, "Bold")
        text(canvas, (x, 732), sub, 22, SOFT, "Medium")
    pills(canvas, W / 2, 880, ["Abilities fire on the press", "Sets switch in the middle of a fight",
                               "One set can follow your stance or form"], 28, 62)
    return canvas


def controllers():
    canvas = slide([("Speaks ", WHITE), ("your controller.", GOLD)],
                   "Xbox, PlayStation and Nintendo labels: matched to the pad you plug in, or picked in the settings.")
    painter = Painter(1.72, big)
    contents = [("icon", 1), ("icon", 2), ("icon", 3), ("icon", 4), ("icon", 5), None, ("icon", 7), None]
    pw, ph, gap, y = 560, 520, 40, 356
    x0 = (W - 3 * pw - 2 * gap) / 2
    for i, (style, name) in enumerate((("xbox", "Xbox"), ("playstation", "PlayStation"), ("nintendo", "Nintendo"))):
        x = x0 + i * (pw + gap)
        box(canvas, (x, y, x + pw, y + ph), 28, (255, 255, 255, 10), (255, 255, 255, 32))
        text(canvas, (x + pw / 2, y + 64), name, 42, WHITE, "Bold")
        painter.one_set(canvas, x + pw / 2, y + 236, 0, style, contents, active=True)
        text(canvas, (x + pw / 2, y + 380), "TRIGGERS", 18, DIM, "Bold")
        for n, trigger in enumerate(preview.STYLES[style][1]):
            canvas.alpha_composite(sized(big("Badge-" + trigger), 132, 66), (round(x + pw / 2 - 142 + n * 152), y + 402))
    text(canvas, (W / 2, 946), "The game names controller buttons by position, so every pad works the same. Only the labels change.",
         24, DIM, "Medium")
    return canvas


# ---------------------------------------------------------------------------
# Controls diagram: the empty bar, labelled
# ---------------------------------------------------------------------------
def controls():
    canvas = backdrop(W, H)
    painter = Painter(2.25, big)
    ox, oy = W / 2, 570
    content = {0: [None, None, None, None, ("role", "Interact"), ("pass",), ("role", "Cancel"), ("role", "Jump")]}
    painter.bar(canvas, ox, oy, 2, "xbox", content)

    text(canvas, (W / 2, 84), "FreeControl", 66, WHITE, "Black")
    text(canvas, (W / 2, 146), "A controller cross hotbar for the normal interface", 32, SOFT, "Medium")

    def callout(title, sub, x, y, colour=WHITE):
        text(canvas, (x, y), title, 33, colour, "Bold")
        text(canvas, (x, y + 42), sub, 24, SOFT, "Medium")

    half = LAYOUT["set"][1] * painter.k / 2
    cx0, cy0 = painter.set_centre(ox, oy, 0)
    cx1, cy1 = painter.set_centre(ox, oy, 1)
    cx2, cy2 = painter.set_centre(ox, oy, 2)
    cx3, cy3 = painter.set_centre(ox, oy, 3)
    callout("No trigger", "4 action slots · Interact · Cancel · Jump · one button left to you", cx0, cy0 - half - 112)
    callout("Hold LT", "8 action slots", cx1, cy1 + half + 76)
    callout("Hold RT", "8 action slots (shown held)", cx2, cy2 + half * 1.2 + 86, GOLD)
    callout("Hold LT + RT", "8 action slots", cx3, cy3 + half + 76)

    text(canvas, (W / 2, H - 98), "Drop spells, items and macros onto any slot · Gamepad UI mode stays off", 29, WHITE, "Medium")
    text(canvas, (W / 2, H - 46), "Diagram drawn from the addon's own artwork, with every slot empty. Not a screenshot.", 21, DIM, "Medium")
    return canvas


# ---------------------------------------------------------------------------
# README animation: the four sets, one after the other. The game switches sets at once, with no
# tween, so the frames do too.
# ---------------------------------------------------------------------------
def demo_frames():
    w, h = 1200, 452
    painter = Painter(1.45, big)
    frames = []
    for held in (0, 1, 3, 2):
        canvas = Image.new("RGBA", (w, h), (24, 28, 40, 255))  # flat, so the 256 colours go to the buttons
        text(canvas, (w / 2 - 150, 46), "Held:", 25, SOFT, "SemiBold", "rm")
        for side, name in ((1, "LT"), (2, "RT")):
            x = w / 2 - 128 + (side - 1) * 132
            lit = held in (side, 3)
            if lit:
                paste(canvas, sized(preview.tex("Set-Glow"), 250, 120), x + 58, 46, add=True)
            canvas.alpha_composite(preview.faded(sized(big("Badge-" + name), 116, 58), 1.0 if lit else 0.32), (round(x), 17))
        painter.bar(canvas, w / 2, 258, held, "xbox", CONTENT, STATES, COUNTS)
        text(canvas, (w / 2, h - 20), "Illustration, not a screenshot. Spell icons are placeholders.", 15, DIM, "Medium")
        frames.append(canvas.convert("RGB"))
    return frames


def save_gif(frames, path, milliseconds=1150):
    """One palette for all the frames, dithered, so the dark gradient does not band."""
    strip = Image.new("RGB", (frames[0].width, frames[0].height * len(frames)))
    for i, frame in enumerate(frames):
        strip.paste(frame, (0, i * frame.height))
    palette = strip.quantize(256, method=Image.Quantize.MEDIANCUT)
    reduced = [frame.quantize(palette=palette, dither=Image.Dither.FLOYDSTEINBERG) for frame in frames]
    reduced[0].save(path, save_all=True, append_images=reduced[1:], duration=milliseconds, loop=0, optimize=False)


# ---------------------------------------------------------------------------
PICTURES = {
    "logo": (logo, os.path.join(OUT, "logo.png")),
    "hero": (gallery_hero, os.path.join(GALLERY, "01-hero.png")),
    "sets": (sets, os.path.join(GALLERY, "02-sets.png")),
    "drop": (drop, os.path.join(GALLERY, "03-drop.png")),
    "interact": (interact, os.path.join(GALLERY, "04-interact.png")),
    "normal-mode": (normal_mode, os.path.join(GALLERY, "05-normal-mode.png")),
    "combat": (combat, os.path.join(GALLERY, "06-combat.png")),
    "controllers": (controllers, os.path.join(GALLERY, "07-controllers.png")),
    "controls": (controls, os.path.join(GALLERY, "08-controls.png")),
    "banner": (banner, os.path.join(DOCS, "banner.png")),
    "social": (social, os.path.join(DOCS, "social.png")),
    "demo": (demo_frames, os.path.join(DOCS, "demo.gif")),
}


def main(names):
    unknown = [name for name in names if name not in PICTURES]
    if unknown:
        raise SystemExit("unknown picture: %s (known: %s)" % (", ".join(unknown), ", ".join(PICTURES)))
    os.makedirs(GALLERY, exist_ok=True)
    os.makedirs(DOCS, exist_ok=True)
    for name in names or PICTURES:
        make, path = PICTURES[name]
        result = make()
        if name == "demo":
            save_gif(result, path)
        elif name == "logo":
            result.save(path)  # keeps its transparent corners
        else:
            result.convert("RGB").save(path, optimize=True)
        print("wrote %s (%d KB)" % (os.path.relpath(path, ROOT), os.path.getsize(path) // 1024))


if __name__ == "__main__":
    main(sys.argv[1:])
