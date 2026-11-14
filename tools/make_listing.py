#!/usr/bin/env python3
"""Draws the pictures for the CurseForge page and the README.

    python3 tools/make_listing.py                 # all of them
    python3 tools/make_listing.py hero sets       # only the ones named
    python3 tools/make_listing.py --placeholders  # with drawn stand-ins for the spell icons

  curseforge/logo.png                    the project avatar: 400 x 400, as CurseForge requires
  curseforge/gallery/01-hero.png         title picture
  curseforge/gallery/02-sets.png         the four sets
  curseforge/gallery/03-drop.png         drag and drop
  curseforge/gallery/04-interact.png     the Interact button
  curseforge/gallery/05-normal-mode.png  what stays as it is
  curseforge/gallery/06-combat.png       what a slot shows in combat
  curseforge/gallery/07-controllers.png  Xbox, PlayStation and Nintendo labels
  curseforge/gallery/08-controls.png     a labelled diagram of the empty bar
  curseforge/gallery/09-mouse-mode.png   the mouse cursor and the buttons that click
  curseforge/web/*.jpg                   the same nine at 1280 x 720, a seventh of the size: what
                                         the description page loads, so it opens quickly
  docs/banner.png                        the README header
  docs/demo.gif                          the README animation: the four sets, one after the other
  docs/social.png                        for GitHub's Settings > Social preview
  curseforge/description.html            curseforge/description.md as HTML, for the page editor's
                                         source view (needs the "markdown" package)

Every picture is an illustration built from the addon's own textures and layout numbers, and says
so on the picture. The filled slots show a Rogue's spell icons. Those are Blizzard's: they are
fetched by tools/game_icons.py when the pictures are built and credited on each picture.
Screenshots have to come from the game.
"""
import functools
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # the sibling modules, also under python -I
import make_art  # noqa: E402
import placeholder_icons  # noqa: E402
import preview  # noqa: E402
from preview import CONTENT, COUNTS, LAYOUT, STATES, Painter, paste, sized, spells  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "curseforge")
GALLERY = os.path.join(OUT, "gallery")
WEB = os.path.join(OUT, "web")  # smaller copies of the gallery pictures, for the description page
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
PLACEHOLDERS = False  # set by --placeholders: draw stand-ins instead of the game's spell icons


def note(short=False, spell_icons=True):
    """The line every picture carries: what it is and, where it shows any, whose the spell icons are."""
    line = "Illustration, not a screenshot." if short else "Illustration built from the addon's own artwork, not a screenshot."
    if spell_icons:
        line += " Spell icons are placeholders." if PLACEHOLDERS else " Spell icons \u00a9 Blizzard Entertainment."
    return line


def spell_icon(name):
    return (preview.placeholder_icon if PLACEHOLDERS else preview.game_icon)(name)


def painter(k):
    return Painter(k, big, spell_icon)


# ---------------------------------------------------------------------------
# Small drawing helpers
# ---------------------------------------------------------------------------
def font(size, weight="Bold"):
    for path in (os.path.expanduser("~/.local/share/fonts/Inter/Inter-%s.ttf" % weight),
                 "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
        if os.path.exists(path):
            return ImageFont.truetype(path, round(size))
    raise FileNotFoundError("no font found; add one to font() in tools/make_listing.py")


# The title on the big pictures is set in LifeCraft, Eliot Truelove's Warcraft-style typeface. It
# is donationware (free to use; its author asks for a donation) and is somebody else's work, so
# the file is never committed: it is fetched once into tools/.font-cache/ (git-ignored).
TITLE_FONT_ZIP = "https://dl.dafont.com/dl/?f=lifecraft"
TITLE_FONT_FILE = "LifeCraft_Font.ttf"
FONT_CACHE = os.path.join(ROOT, "tools", ".font-cache")


@functools.lru_cache(maxsize=None)
def title_font_path():
    """Where the title typeface is, fetching it the first time; None if it cannot be had, in
    which case the title falls back to the ordinary typeface."""
    path = os.path.join(FONT_CACHE, TITLE_FONT_FILE)
    if not os.path.exists(path):
        import io
        import urllib.request
        import zipfile
        try:
            request = urllib.request.Request(TITLE_FONT_ZIP, headers={"User-Agent": "Mozilla/5.0 (picture build)"})
            with urllib.request.urlopen(request, timeout=40) as response:
                archive = zipfile.ZipFile(io.BytesIO(response.read()))
            names = [n for n in archive.namelist() if n.lower().endswith(".ttf")]
            os.makedirs(FONT_CACHE, exist_ok=True)
            with open(path, "wb") as f:
                f.write(archive.read(names[0]))
        except Exception as problem:  # no network, or the site has moved: say so and carry on plainer
            print("could not fetch the title typeface (%s); using the ordinary one" % problem)
            return None
    return path


def title_text(canvas, xy, string, size):
    """The big title: Warcraft-style letters, cream running to gold, with a dark edge and a soft
    shadow. Falls back to the ordinary bold typeface if the title one is not to be had."""
    path = title_font_path()
    if not path:
        shadow_text(canvas, xy, string, size * 0.86, WHITE, "Black")
        return
    face = ImageFont.truetype(path, round(size))
    edge_w = max(2, round(size * 0.030))
    fill = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(fill).text(xy, string, font=face, fill=255, anchor="mm")
    edge = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(edge).text(xy, string, font=face, fill=255, anchor="mm", stroke_width=edge_w)
    shadow = ImageChops.offset(edge.filter(ImageFilter.GaussianBlur(size * 0.045)), 0, round(size * 0.035))
    canvas.alpha_composite(masked((6, 26, 60), shadow, 0.70))
    canvas.alpha_composite(masked((48, 30, 14), edge))
    box_ = fill.getbbox() or (0, 0, canvas.width, canvas.height)
    tint = Image.new("RGB", canvas.size, (255, 250, 236))
    tint.paste(vertical((canvas.width, max(1, box_[3] - box_[1])), (255, 252, 240), (244, 206, 132)), (0, box_[1]))
    canvas.alpha_composite(masked(tint, fill))
    # A hairline of light along the top of the letters, as on an embossed sign.
    lip = ImageChops.subtract(fill, ImageChops.offset(fill, 0, max(1, round(size * 0.012))))
    canvas.alpha_composite(masked((255, 255, 255), lip, 0.55))


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
    out["Set-Shade"] = preview.tex("Set-Shade")  # a smooth gradient; nothing to gain from redrawing it
    return out


def big(name):
    return big_art()[name]


# ---------------------------------------------------------------------------
# Logo
# ---------------------------------------------------------------------------
@functools.lru_cache(maxsize=None)
def logo():
    """The project avatar: the addon's emblem, at the 400 x 400 CurseForge asks for."""
    return make_art.ring_logo(400, 4)


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


def cloud(w, h, rng, grain):
    """Soft blotches from 0 to 1: a small field of random numbers stretched over the picture.
    grain is how many blotches fit across its width."""
    small = rng.uniform(0, 1, (max(2, round(grain * h / w)), grain)).astype(np.float32)
    field = np.asarray(Image.fromarray(small).resize((w, h), Image.BICUBIC))
    return np.clip(field, 0, 1)


def landscape(w, h, seed=4):
    """A sunny city of white stone and blue roofs under a bright sky: a keep and a cathedral
    among lesser towers, gold on the spires, banners on the gate. It is a drawing of our own of
    the kind of city the game's humans live in, stands in for the game world behind the bar,
    and is plainly not a screenshot."""
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    sky_top, sky_low = np.array((22, 112, 188), np.float32), np.array((170, 226, 242), np.float32)
    air = np.array((176, 222, 240), np.float32)  # what distance fades things towards
    stone, shade, roof, roof_dark = (242, 236, 222), (204, 204, 212), (48, 108, 186), (30, 74, 140)
    gold, glass = (250, 204, 86), (52, 84, 128)

    def mix(a, b, amount):
        return np.asarray(a, np.float32) * (1 - amount) + np.asarray(b, np.float32) * amount

    def far(colour, depth):
        """A colour as it looks `depth` of the way from the horizon (0) to the near wall (1)."""
        return tuple(int(v) for v in mix(air, colour, 0.30 + 0.70 * depth)) + (255,)

    # Sky: a deep clear blue overhead, paling to the horizon, the sun off to the upper right.
    rows = np.clip(y / (0.80 * h), 0, 1)[..., None] ** 0.85
    sky = mix(sky_top, sky_low, rows)
    sun = np.clip(1 - np.hypot((x - 0.84 * w) / (0.50 * w), (y - 0.16 * h) / (0.46 * h)), 0, 1)[..., None] ** 2
    img = Image.fromarray(np.clip(mix(sky, (255, 252, 236), sun * 0.55), 0, 255).astype(np.uint8), "RGB").convert("RGBA")

    # Fair-weather clouds, kept to the sides so the title has clear sky behind it.
    clouds = Image.new("RGBA", (w * 2, h * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(clouds)
    for cx, cy, size in ((0.09, 0.30, 1.0), (0.26, 0.42, 0.62), (0.93, 0.36, 0.9), (0.76, 0.46, 0.55), (0.50, 0.50, 0.42)):
        puffs = [(dx, rng.uniform(0.55, 1.0)) for dx in np.linspace(-1, 1, 7)]
        for layer_colour, drop in (((196, 224, 242, 255), 0.012), ((255, 255, 255, 255), 0.0)):  # the shaded underside first
            for dx, big_r in puffs:
                r = 0.036 * h * size * big_r * (1 - 0.45 * abs(dx))
                px, py = (cx + dx * 0.075 * size) * w, (cy + drop) * h - r * 0.55
                d.ellipse([(px - r * 1.5) * 2, (py - r) * 2, (px + r * 1.5) * 2, (py + r) * 2], fill=layer_colour)
            d.rounded_rectangle([(cx - 0.085 * size) * w * 2, (cy + drop - 0.012 * size) * h * 2, (cx + 0.085 * size) * w * 2,
                                 (cy + drop + 0.012 * size) * h * 2], radius=0.012 * size * h * 2, fill=layer_colour)
    img.alpha_composite(clouds.resize((w, h), Image.LANCZOS).filter(ImageFilter.GaussianBlur(1.2)))

    # The mountains behind the city, blue with distance.
    for base, amp, colour, alpha in ((0.60, 0.22, (120, 176, 220), 255), (0.66, 0.14, (104, 168, 206), 255)):
        crest = (base - amp * ridge(w, rng, True)) * h
        sink = np.clip((y - crest[None, :]) / (0.20 * h), 0, 1)[..., None]
        fill = mix(np.array(colour, np.float32), air, sink * 0.7)
        hills = np.concatenate([fill, (np.clip(y - crest[None, :] + 0.5, 0, 1) * alpha)[..., None]], axis=-1)
        img.alpha_composite(Image.fromarray(hills.clip(0, 255).astype(np.uint8), "RGBA"))

    ss = 2
    row = Image.new("RGBA", (w * ss, h * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(row)

    def box(x0, top, x1, bottom, fill):
        d.rectangle([x0 * ss, top * ss, x1 * ss, bottom * ss], fill=fill)

    def tri(points, fill):
        d.polygon([(px * ss, py * ss) for px, py in points], fill=fill)

    def spire(cx, foot, wide, body, roof_h, depth, flag=False, lit=True):
        """A round tower: a pale shaft with its shaded side, a collar, a blue cone with its dark
        side, a gold ball on the point, and now and then a banner."""
        top = foot - body
        box(cx - wide / 2, top, cx + wide / 2, foot, far(stone, depth))
        box(cx + wide * 0.14, top, cx + wide / 2, foot, far(shade, depth))
        box(cx - wide * 0.64, top - wide * 0.16, cx + wide * 0.64, top + wide * 0.08, far(shade, depth))
        eave, tip = top - wide * 0.14, top - wide * 0.14 - roof_h
        tri([(cx - wide * 0.74, eave), (cx + wide * 0.74, eave), (cx, tip)], far(roof, depth))
        tri([(cx + wide * 0.10, eave), (cx + wide * 0.74, eave), (cx, tip)], far(roof_dark, depth))
        if lit and wide > 0.008 * w:
            for level in range(1, 1 + int(body / (wide * 1.6))):
                wy = top + level * wide * 1.5
                if wy + wide * 0.5 < foot:
                    box(cx - wide * 0.10, wy, cx + wide * 0.06, wy + wide * 0.42, far(glass, depth))
        r = max(1.0, wide * 0.12)
        d.ellipse([(cx - r) * ss, (tip - r) * ss, (cx + r) * ss, (tip + r) * ss], fill=far(gold, depth))
        if flag:
            mast = tip - wide * 0.62
            d.line([(cx * ss, tip * ss), (cx * ss, mast * ss)], fill=far(shade, depth), width=max(2, round(wide * 0.07 * ss)))
            tri([(cx, mast), (cx + wide * 0.70, mast + wide * 0.16), (cx, mast + wide * 0.34)], far(gold, depth))

    def house(cx, foot, half, body, depth, blue):
        box(cx - half, foot - body, cx + half, foot, far(stone if blue else (232, 220, 200), depth))
        tri([(cx - half * 1.18, foot - body), (cx + half * 1.18, foot - body), (cx, foot - body - half * 1.25)],
            far(roof if blue else (156, 96, 76), depth))
        tri([(cx, foot - body), (cx + half * 1.18, foot - body), (cx, foot - body - half * 1.25)],
            far(roof_dark if blue else (124, 72, 60), depth))

    def wall(x0, x1, top, foot, depth, tooth):
        box(x0, top, x1, foot, far(stone, depth))
        box(x0, top + (foot - top) * 0.10, x1, top + (foot - top) * 0.16, far(shade, depth))  # a string course
        at = x0
        while at < x1:
            box(at, top - tooth * 0.8, min(x1, at + tooth), top, far(stone, depth))
            at += tooth * 2

    def trees(foot, count, depth, x0=0.0, x1=1.0):
        for _ in range(count):
            tx, r = rng.uniform(x0, x1) * w, rng.uniform(0.010, 0.020) * h * (0.6 + 0.6 * depth)
            green = (rng.integers(70, 104), rng.integers(150, 182), rng.integers(84, 112))
            d.ellipse([(tx - r * 1.2) * ss, (foot - r * 1.9) * ss, (tx + r * 1.2) * ss, (foot + r * 0.3) * ss], fill=far(green, depth))

    def settle(centre=None, strength=0.0):
        """Puts the row just drawn on the picture, then a breath of haze over its feet."""
        nonlocal row, d
        img.alpha_composite(row.resize((w, h), Image.LANCZOS))
        row = Image.new("RGBA", (w * ss, h * ss), (0, 0, 0, 0))
        d = ImageDraw.Draw(row)
        if centre:
            band = np.exp(-((y - centre * h) / (0.03 * h)) ** 2) * (0.6 + 0.4 * cloud(w, h, rng, 6)) * strength
            fog = np.concatenate([np.full((h, w, 3), (236, 246, 250), np.float32), band[..., None] * 255], axis=-1)
            img.alpha_composite(Image.fromarray(fog.clip(0, 255).astype(np.uint8), "RGBA"))

    # The far quarter: a crowd of roofs and small towers, pale with distance.
    foot = 0.725 * h
    for _ in range(40):
        wide = rng.uniform(0.007, 0.012) * w
        spire(rng.uniform(0.02, 0.98) * w, foot, wide, rng.uniform(0.03, 0.09) * h, wide * rng.uniform(1.5, 2.4), 0.18, lit=False)
    for _ in range(90):
        house(rng.uniform(0, 1) * w, foot, rng.uniform(0.006, 0.011) * w, rng.uniform(0.012, 0.030) * h, 0.18, rng.uniform() < 0.8)
    box(0, foot - 0.004 * h, w, foot + 0.06 * h, far(stone, 0.18))
    settle(0.725, 0.5)

    # The keep and the cathedral, one to each side of the middle, with the town between.
    foot = 0.815 * h
    depth = 0.62
    kx = 0.225 * w  # the keep: a tall hall crowded with spires, the highest in the middle
    box(kx - 0.088 * w, foot - 0.125 * h, kx + 0.088 * w, foot, far(stone, depth))
    box(kx + 0.030 * w, foot - 0.125 * h, kx + 0.088 * w, foot, far(shade, depth))
    wall(kx - 0.108 * w, kx + 0.108 * w, foot - 0.062 * h, foot, depth, 0.006 * w)
    for dx, wide, body, roof_h, flag in ((0, 0.032, 0.300, 0.115, True), (-0.042, 0.020, 0.215, 0.078, False), (0.042, 0.020, 0.215, 0.078, False),
                                         (-0.076, 0.016, 0.160, 0.060, True), (0.076, 0.016, 0.160, 0.060, True),
                                         (-0.103, 0.014, 0.105, 0.046, False), (0.103, 0.014, 0.105, 0.046, False)):
        spire(kx + dx * w, foot, wide * w, body * h, roof_h * h, depth, flag)
    cx = 0.780 * w  # the cathedral: a long nave under a blue roof, two west towers, a spire over the crossing
    box(cx - 0.072 * w, foot - 0.108 * h, cx + 0.072 * w, foot, far(stone, depth))
    tri([(cx - 0.078 * w, foot - 0.108 * h), (cx + 0.078 * w, foot - 0.108 * h), (cx + 0.062 * w, foot - 0.156 * h),
         (cx - 0.062 * w, foot - 0.156 * h)], far(roof, depth))
    for nx in np.linspace(-0.058, 0.058, 7):  # the nave's tall windows
        box(cx + nx * w - 0.003 * w, foot - 0.085 * h, cx + nx * w + 0.003 * w, foot - 0.030 * h, far(glass, depth))
    for dx, wide, body, roof_h, flag in ((0.014, 0.023, 0.235, 0.140, True), (-0.060, 0.018, 0.178, 0.072, False), (-0.031, 0.018, 0.178, 0.072, False),
                                         (0.068, 0.013, 0.132, 0.052, False)):
        spire(cx + dx * w, foot, wide * w, body * h, roof_h * h, depth, flag)
    mx = 0.515 * w  # the mages' tower: taller and thinner than its neighbours, violet-roofed, on a green mound
    d.ellipse([(mx - 0.050 * w) * ss, (foot - 0.045 * h) * ss, (mx + 0.050 * w) * ss, (foot + 0.045 * h) * ss], fill=far((96, 170, 104), depth))
    box(mx - 0.007 * w, foot - 0.230 * h, mx + 0.007 * w, foot - 0.030 * h, far(stone, depth))
    box(mx + 0.002 * w, foot - 0.230 * h, mx + 0.007 * w, foot - 0.030 * h, far(shade, depth))
    for ring_y, ring_w in ((0.090, 0.012), (0.150, 0.011), (0.205, 0.010)):
        box(mx - ring_w * w, foot - ring_y * h, mx + ring_w * w, foot - ring_y * h + 0.008 * h, far(shade, depth))
    tri([(mx - 0.013 * w, foot - 0.230 * h), (mx + 0.013 * w, foot - 0.230 * h), (mx, foot - 0.300 * h)], far((122, 92, 190), depth))
    tri([(mx + 0.002 * w, foot - 0.230 * h), (mx + 0.013 * w, foot - 0.230 * h), (mx, foot - 0.300 * h)], far((88, 62, 150), depth))
    d.ellipse([(mx - 0.003 * w) * ss, (foot - 0.300 * h - 0.003 * w) * ss, (mx + 0.003 * w) * ss, (foot - 0.300 * h + 0.003 * w) * ss],
              fill=far(gold, depth))
    for _ in range(12):  # lesser towers of the same quarter
        tx = rng.choice([rng.uniform(0.02, 0.10), rng.uniform(0.36, 0.65), rng.uniform(0.90, 0.99)]) * w
        wide = rng.uniform(0.010, 0.016) * w
        spire(tx, foot, wide, rng.uniform(0.06, 0.13) * h, wide * rng.uniform(1.7, 2.6), depth, rng.uniform() < 0.3)
    for _ in range(70):
        house(rng.uniform(0, 1) * w, foot, rng.uniform(0.007, 0.013) * w, rng.uniform(0.016, 0.042) * h, depth, rng.uniform() < 0.75)
    trees(foot, 34, depth)
    box(0, foot - 0.004 * h, w, foot + 0.07 * h, far(stone, depth))
    settle(0.815, 0.42)

    # The outer wall, nearest and brightest: towers along it, and the great gate with its banners.
    depth = 1.0
    foot, top = 1.02 * h, 0.905 * h
    trees(top + 0.004 * h, 46, 0.9)
    wall(0, w, top, foot, depth, 0.009 * w)
    for tx in (0.035, 0.165, 0.335, 0.665, 0.835, 0.965):
        spire(tx * w, foot, 0.032 * w, foot - top + 0.050 * h, 0.066 * h, depth, tx in (0.165, 0.835))
    box(0.445 * w, top - 0.034 * h, 0.555 * w, foot, far(stone, depth))  # the gatehouse
    for side in (-1, 1):
        spire((0.5 + side * 0.062) * w, foot, 0.044 * w, foot - top + 0.090 * h, 0.092 * h, depth, True)
        bx = (0.5 + side * 0.030) * w  # a blue banner with a gold band to each side of the arch
        box(bx - 0.007 * w, top - 0.018 * h, bx + 0.007 * w, top + 0.046 * h, far((40, 92, 172), depth))
        box(bx - 0.007 * w, top + 0.006 * h, bx + 0.007 * w, top + 0.014 * h, far(gold, depth))
    d.rectangle([0.479 * w * ss, 0.936 * h * ss, 0.521 * w * ss, h * ss], fill=far((56, 84, 124), depth))  # the archway
    d.pieslice([0.479 * w * ss, (0.936 * h - 0.021 * w) * ss, 0.521 * w * ss, (0.936 * h + 0.021 * w) * ss], 180, 360,
               fill=far((56, 84, 124), depth))
    settle()

    rgb = np.asarray(img.convert("RGB")).astype(np.float32)
    rgb = mix(rgb, (22, 150, 186), 0.08)  # a breath of the game's own blue-green over everything, no more
    edge = np.hypot((x - w / 2) / (w / 2), (y - h / 2) / (h / 2))
    rgb = rgb * np.clip(1.03 - 0.16 * edge ** 2, 0, 1.03)[..., None] + noise((w, h), 1.6, seed)
    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


# ---------------------------------------------------------------------------
# Title pictures: the bar over the landscape
# ---------------------------------------------------------------------------
def hero(w=W, h=H, k=2.0, title_y=128, title_size=150, tagline_size=46, bar_y=478, chips=(), note_size=18, city=0.70):
    """The title, the bar in open sky, and the city along the bottom. `city` is how much of the
    picture's height the drawn scene takes; the rest, above it, is more of its sky."""
    scene = landscape(w, round(h * city))
    gap = h - scene.height
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    if gap > 0:
        # Carry the scene's top edge upward, smoothed sideways so its grain does not streak, and
        # a little deeper towards the top of the picture.
        strip = scene.convert("RGB").crop((0, 0, w, 8)).resize((max(2, w // 48), 1), Image.BOX).resize((w, 1), Image.BICUBIC)
        sky = np.asarray(strip.resize((w, gap), Image.NEAREST)).astype(np.float32)
        deepen = np.linspace(0.84, 1.0, gap, dtype=np.float32)[:, None, None]
        sky = sky * deepen + noise((w, gap), 1.6, 5)
        canvas.paste(Image.fromarray(np.clip(sky, 0, 255).astype(np.uint8), "RGB"), (0, 0))
    canvas.alpha_composite(scene, (0, gap))

    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    shade = np.clip(1 - np.hypot((x - w / 2) / (0.62 * w), (y - bar_y) / (0.40 * h)), 0, 1) ** 1.2 * 0.36
    scrim = np.zeros((h, w, 4), np.float32)
    scrim[..., :3] = (8, 30, 70)
    scrim[..., 3] = shade * 255
    canvas.alpha_composite(Image.fromarray(scrim.astype(np.uint8), "RGBA"))  # keeps the bar readable
    foot = np.zeros((h, w, 4), np.float32)  # and a darker strip along the bottom, for the small print
    foot[..., :3] = (8, 30, 70)
    foot[..., 3] = np.clip((y - (h - 0.13 * h)) / (0.13 * h), 0, 1) ** 1.4 * 0.80 * 255
    canvas.alpha_composite(Image.fromarray(foot.astype(np.uint8), "RGBA"))

    painter(k).bar(canvas, w / 2, bar_y, 2, "xbox", CONTENT, STATES, COUNTS)
    title_text(canvas, (w / 2, title_y), "FreeControl", title_size * 1.22)
    shadow_text(canvas, (w / 2, title_y + title_size * 0.76), TAGLINE, tagline_size, (238, 240, 248, 255), "SemiBold", spread=7)
    if chips:
        pills(canvas, w / 2, h - 96, chips, 28, 58, (8, 10, 20, 150), (255, 255, 255, 76))
    shadow_text(canvas, (w / 2, h - 26), note(), note_size, (206, 210, 224, 255), "Medium", spread=4, strength=0.9)
    return canvas


def gallery_hero():
    return hero(chips=("32 buttons on two triggers", "Drag and drop spells, items and macros", "Gamepad UI mode stays off"))


def banner():
    return hero(1600, 600, 1.35, 74, 92, 29, 318, note_size=15, city=0.56)


def social():
    return hero(1280, 640, 1.2, 84, 100, 30, 350, note_size=14, city=0.56)


# ---------------------------------------------------------------------------
# Feature pictures
# ---------------------------------------------------------------------------
def slide(parts, sub, glows=(), spell_icons=True):
    canvas = backdrop(W, H, glows)
    canvas.alpha_composite(logo().resize((56, 56), Image.LANCZOS), (72, 50))
    text(canvas, (142, 79), "FreeControl", 30, WHITE, "Bold", "lm")
    headline(canvas, W / 2, 196, parts, 84)
    text(canvas, (W / 2, 278), sub, 32, SOFT, "Medium")
    text(canvas, (W / 2, H - 34), note(spell_icons=spell_icons), 20, DIM, "Medium")
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
                   "Four sets of eight on the D-pad and face buttons. The one you hold grows; the others step back.")
    bars = painter(1.08)
    panels = [(0, "No trigger", [], "4 action slots, Interact, Mouse, Cancel and Jump"), (1, "Hold", ["LT"], "8 action slots"),
              (2, "Hold", ["RT"], "8 action slots"), (3, "Hold", ["LT", "RT"], "8 action slots")]
    pw, ph, gap = 880, 320, 32
    x0 = (W - 2 * pw - gap) / 2
    for i, (held, label, badges, sub) in enumerate(panels):
        x, y = x0 + (i % 2) * (pw + gap), 336 + (i // 2) * (ph + 20)
        box(canvas, (x, y, x + pw, y + ph), 28, (255, 255, 255, 10), (255, 255, 255, 32))
        bars.bar(canvas, x + pw / 2, y + 198, held, "xbox", CONTENT, STATES, COUNTS)
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


def rounded_icon(image, size, radius=16, alpha=1.0):
    """An icon as it would look in a spellbook or bag: a plain tile with a dark edge."""
    icon = sized(image, size, size)
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
    groups = [("SPELLS", ["Backstab", "Eviscerate", "Sprint", "Evasion"]),
              ("ITEMS", ["Healing Potion", "Thistle Tea", "Bandage"]),
              ("MACROS", ["Macro", "Blade Flurry", "Adrenaline Rush"])]
    tile, gap, group_gap, top = 100, 14, 64, 372
    total = sum(len(icons) * tile + (len(icons) - 1) * gap for _, icons in groups) + group_gap * (len(groups) - 1)
    x = (W - total) / 2
    picked = None
    for label, icons in groups:
        width = len(icons) * tile + (len(icons) - 1) * gap
        text(canvas, (x + width / 2, top - 26), label, 19, DIM, "Bold")
        for n, name in enumerate(icons):
            first = picked is None
            canvas.alpha_composite(rounded_icon(spell_icon(name), tile, alpha=0.32 if first else 1.0),
                                   (round(x + n * (tile + gap)), top))
            if first:
                picked = (name, x + tile / 2, top + tile)
        x += width + group_gap

    # The bar with the slot under the picked spell still empty; that is where it is headed.
    content = {set_id: list(row) for set_id, row in CONTENT.items()}
    content[1][0] = None
    bars = painter(1.72)
    ox, oy = W / 2, 748
    tx, ty = bars.button_centre(ox, oy, 1, 1)
    bars.bar(canvas, ox, oy, 0, "xbox", content, {**STATES, (1, 1): "hover"}, COUNTS)

    name, sx, sy = picked
    path = cubic((sx, sy + 12), (sx + 90, sy + 90), (tx + 90, ty - 150), (tx, ty - 46))
    dashed(canvas, path, GOLD)
    fx, fy = path[52]
    flying = rounded_icon(spell_icon(name), 92).rotate(8, resample=Image.BICUBIC, expand=True)
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
                   glows=[(bx, by, 520, 420, 0.42)], spell_icons=False)  # the four pictograms here are drawn, not the game's
    painter(7.4).button(canvas, bx, by, 5, preview.STYLES["xbox"][0], ("role", "Interact"))
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
        canvas.alpha_composite(rounded_icon(placeholder_icons.icon(number), 112, 20), (x + 36, y + (ch - 112) // 2))
        text(canvas, (x + 180, y + ch / 2 - 22), title, 40, WHITE, "Bold", "lm")
        text(canvas, (x + 180, y + ch / 2 + 26), sub, 24, SOFT, "Medium", "lm")
    text(canvas, (x0 + cw + gap / 2, y0 + 2 * ch + gap + 58),
         "The game's own Interact command, with the reach Gamepad UI mode gives it.", 24, DIM, "Medium")
    return canvas


def stick_tile(letter=None, size=112):
    """A drawn tile for a thumbstick seen from above: a ring and a cap, with the stick's letter on
    the cap or, with no letter, four arrows around it for "move"."""
    def paint(d, s):
        c = size * s / 2
        d.rounded_rectangle((0, 0, size * s - 1, size * s - 1), radius=20 * s, fill=(30, 35, 50, 255),
                            outline=(8, 9, 14, 255), width=3 * s)
        d.ellipse((c - 41 * s, c - 41 * s, c + 41 * s, c + 41 * s), outline=(196, 204, 222, 255), width=5 * s)
        d.ellipse((c - 25 * s, c - 25 * s, c + 25 * s, c + 25 * s), fill=(226, 104, 178, 255) if letter else (196, 204, 222, 255))
        if letter:
            d.text((c, c), letter, font=font(34 * s, "Black"), fill=(255, 255, 255, 255), anchor="mm")
        else:
            for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
                tip, back, wide = 37 * s, 29 * s, 7 * s
                d.polygon([(c + dx * tip, c + dy * tip), (c + dx * back - dy * wide, c + dy * back + dx * wide),
                           (c + dx * back + dy * wide, c + dy * back - dx * wide)], fill=(246, 246, 250, 255))
    return drawn(size, size, paint)


def fitted(canvas, xy, string, size, width, fill, weight):
    """Left-aligned text, set smaller until it is no wider than `width`."""
    d = ImageDraw.Draw(canvas)
    while size > 12 and d.textlength(string, font=font(size, weight)) > width:
        size -= 1
    text(canvas, xy, string, size, fill, weight, "lm")


def mouse_mode():
    bx, by = 430, 630
    canvas = slide([("A mouse ", WHITE), ("on your sticks.", GOLD)],
                   "Press the mouse button and the right stick steers the pointer. The two stick clicks are the two mouse buttons.",
                   glows=[(bx, by, 520, 420, 0.42)], spell_icons=False)  # everything here is drawn, none of it the game's
    painter(7.4).button(canvas, bx, by, 6, preview.STYLES["xbox"][0], ("role", "Cursor"), state="checked")
    canvas.alpha_composite(sized(big("Glyph-Y"), 64, 64), (bx - 196, by + 168))
    text(canvas, (bx - 118, by + 200), "Mouse pointer", 46, WHITE, "Black", "lm")
    text(canvas, (bx, by + 258), "the top face button, with no trigger held", 23, SOFT, "Medium")
    text(canvas, (bx, by + 292), "lit while the pointer is out", 23, SOFT, "Medium")

    arrow = np.array([(bx + 178 + i, by) for i in range(0, 121, 4)], dtype=np.float64)
    dashed(canvas, arrow, GOLD, 6, 1000, 0)

    cards = [(stick_tile("L"), "Left stick click", "Left click. Hold it to drag."),
             (stick_tile("R"), "Right stick click", "Right click: use, sell, loot."),
             (stick_tile(), "Right stick", "Moves the pointer."),
             (rounded_icon(big("Role-Cursor"), 112, 20), "Press Y again", "Puts it away. So does a jump.")]
    cw, ch, gap, x0, y0 = 536, 184, 24, 772, 430
    for i, (tile, title, sub) in enumerate(cards):
        x, y = x0 + (i % 2) * (cw + gap), y0 + (i // 2) * (ch + gap)
        box(canvas, (x, y, x + cw, y + ch), 26, (255, 255, 255, 12), (255, 255, 255, 34))
        canvas.alpha_composite(tile, (x + 36, y + (ch - 112) // 2))
        fitted(canvas, (x + 180, y + ch / 2 - 22), title, 40, cw - 180 - 28, WHITE, "Bold")
        fitted(canvas, (x + 180, y + ch / 2 + 26), sub, 24, cw - 180 - 28, SOFT, "Medium")
    text(canvas, (W / 2, 978), "The game's own controller mouse, so the clicks are real ones. The buttons and the pointer's speed are in the settings.",
         24, DIM, "Medium")
    return canvas


def tick(size=48):
    return drawn(size, size, lambda d, s: (
        d.ellipse((0, 0, size * s - 1, size * s - 1), fill=GOLD),
        d.line([(13 * s, 25 * s), (21 * s, 33 * s), (36 * s, 16 * s)], fill=(24, 22, 16, 255), width=5 * s, joint="curve")))


def normal_mode():
    canvas = slide([("Your game stays ", WHITE), ("in normal mode.", GOLD)],
                   "FreeControl adds one bar. Gamepad UI mode stays off, and everything else stays the way you set it up.")
    rows = [("Targeting stays yours", "Bind bumpers and stick clicks in the usual Key Bindings."),
            ("The menus you know", "The regular windows, with a mouse pointer on your stick for the clicks."),
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
    painter(0.58).bar(canvas, cx, cy, 2, "xbox", CONTENT, STATES)
    box(canvas, (cx - 244, cy - 76, cx + 244, cy + 74), 16, (0, 0, 0, 0), GOLD, 3)
    text(canvas, (cx, cy - 100), "FreeControl: the one thing added", 22, GOLD, "Bold")
    text(canvas, (sx + sw / 2, sy + sh + 44), "Everything in grey is the game's normal interface, as you have it.", 24, DIM, "Medium")
    return canvas


def combat():
    canvas = slide([("Made for ", WHITE), ("combat.", GOLD)],
                   "Every slot shows what a normal action bar shows, at a glance, in the middle of a fight.")
    shown = [(1, "Kidney Shot", ("cooldown", "14"), None, "Cooldowns", "sweep and countdown"),
             (5, "Sinister Strike", "range", None, "Out of range", "turns red"),
             (2, "Eviscerate", "nomana", None, "Not enough energy", "turns blue"),
             (6, "Ambush", "unusable", None, "Not usable yet", "goes dark"),
             (3, "Thistle Tea", "normal", "5", "Item counts", "how many are left"),
             (7, "Throw", "checked", None, "In progress", "gold ring while it runs")]
    buttons, face = painter(4.6), preview.STYLES["xbox"][0]
    for i, (index, ability, state, count, title, sub) in enumerate(shown):
        x = 235 + i * 290
        buttons.button(canvas, x, 560, index, face, ("icon", ability), state=state, count=count)
        text(canvas, (x, 694), title, 29, WHITE, "Bold")
        text(canvas, (x, 732), sub, 22, SOFT, "Medium")
    pills(canvas, W / 2, 880, ["Cooldowns show the moment they start", "Sets switch in the middle of a fight",
                               "Every stance and form has its own buttons"], 28, 62)
    return canvas


def controllers():
    canvas = slide([("Speaks ", WHITE), ("your controller.", GOLD)],
                   "Xbox, PlayStation and Nintendo labels: matched to the pad you plug in, or picked in the settings.")
    sets_painter = painter(1.72)
    contents = spells("Sinister Strike", "Gouge", "Eviscerate", "Slice and Dice", "Sprint", None, "Vanish", None)
    pw, ph, gap, y = 560, 520, 40, 356
    x0 = (W - 3 * pw - 2 * gap) / 2
    for i, (style, name) in enumerate((("xbox", "Xbox"), ("playstation", "PlayStation"), ("nintendo", "Nintendo"))):
        x = x0 + i * (pw + gap)
        box(canvas, (x, y, x + pw, y + ph), 28, (255, 255, 255, 10), (255, 255, 255, 32))
        text(canvas, (x + pw / 2, y + 64), name, 42, WHITE, "Bold")
        sets_painter.one_set(canvas, x + pw / 2, y + 236, 0, style, contents, active=True)
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
    bars = painter(2.25)
    ox, oy = W / 2, 570
    content = {0: [None, None, None, None, ("role", "Interact"), ("role", "Cursor"), ("role", "Cancel"), ("role", "Jump")]}
    bars.bar(canvas, ox, oy, 2, "xbox", content)

    text(canvas, (W / 2, 84), "FreeControl", 66, WHITE, "Black")
    text(canvas, (W / 2, 146), "A controller cross hotbar for the normal interface", 32, SOFT, "Medium")

    def callout(title, sub, x, y, colour=WHITE):
        text(canvas, (x, y), title, 33, colour, "Bold")
        text(canvas, (x, y + 42), sub, 24, SOFT, "Medium")

    half = LAYOUT["set"][1] * bars.k / 2
    cx0, cy0 = bars.set_centre(ox, oy, 0)
    cx1, cy1 = bars.set_centre(ox, oy, 1)
    cx2, cy2 = bars.set_centre(ox, oy, 2)
    cx3, cy3 = bars.set_centre(ox, oy, 3)
    callout("No trigger", "4 action slots · Interact · Mouse pointer · Cancel · Jump", cx0, cy0 - half - 112)
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
    bars = painter(1.45)
    frames = []
    for held in (0, 1, 3, 2):
        canvas = Image.new("RGBA", (w, h), (24, 28, 40, 255))  # flat, so the 256 colours go to the buttons
        text(canvas, (w / 2 - 150, 46), "Held:", 25, SOFT, "SemiBold", "rm")
        for side, name in ((1, "LT"), (2, "RT")):
            x = w / 2 - 128 + (side - 1) * 132
            lit = held in (side, 3)
            canvas.alpha_composite(preview.faded(sized(big("Badge-" + name), 116, 58), 1.0 if lit else 0.32), (round(x), 17))
        bars.bar(canvas, w / 2, 258, held, "xbox", CONTENT, STATES, COUNTS)
        text(canvas, (w / 2, h - 20), note(short=True), 15, DIM, "Medium")
        frames.append(canvas.convert("RGB"))
    return frames


def save_gif(frames, path, milliseconds=1150):
    """One palette for all the frames, refined with k-means (about 3 dB closer to the original
    than median cut alone) and dithered, so the gradients inside the icons do not band."""
    strip = Image.new("RGB", (frames[0].width, frames[0].height * len(frames)))
    for i, frame in enumerate(frames):
        strip.paste(frame, (0, i * frame.height))
    palette = strip.quantize(256, method=Image.Quantize.MEDIANCUT, kmeans=4)
    reduced = [frame.quantize(palette=palette, dither=Image.Dither.FLOYDSTEINBERG) for frame in frames]
    reduced[0].save(path, save_all=True, append_images=reduced[1:], duration=milliseconds, loop=0, optimize=False)


def description_html():
    """The listing text as HTML: CurseForge's editor takes HTML in its source view, not Markdown."""
    import markdown  # only this output needs it

    with open(os.path.join(OUT, "description.md"), encoding="utf-8") as f:
        return markdown.markdown(f.read(), extensions=["sane_lists"]) + "\n"


def web_copy(path):
    """Writes the 1280 x 720 JPEG copy of one gallery picture and returns where it went. The
    colour is kept at full resolution so the lettering stays crisp."""
    os.makedirs(WEB, exist_ok=True)
    out = os.path.join(WEB, os.path.splitext(os.path.basename(path))[0] + ".jpg")
    Image.open(path).convert("RGB").resize((1280, 720), Image.LANCZOS).save(out, quality=88, subsampling=0, optimize=True)
    return out


def web_copies():
    """The web copy of every gallery picture there is, without drawing any of them again."""
    return [web_copy(os.path.join(GALLERY, name)) for name in sorted(os.listdir(GALLERY)) if name.endswith(".png")]


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
    "mouse": (mouse_mode, os.path.join(GALLERY, "09-mouse-mode.png")),
    "banner": (banner, os.path.join(DOCS, "banner.png")),
    "social": (social, os.path.join(DOCS, "social.png")),
    "demo": (demo_frames, os.path.join(DOCS, "demo.gif")),
    "web": (web_copies, WEB),
    "description": (description_html, os.path.join(OUT, "description.html")),
}


def main(arguments):
    global PLACEHOLDERS
    PLACEHOLDERS = "--placeholders" in arguments
    names = [name for name in arguments if name != "--placeholders"]
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
        elif name == "web":
            for copy in result:
                print("wrote %s (%d KB)" % (os.path.relpath(copy, ROOT), os.path.getsize(copy) // 1024))
            continue
        elif name == "description":
            with open(path, "w", encoding="utf-8") as f:
                f.write(result)
        elif name == "logo":
            result.save(path)  # keeps its transparent corners
        else:
            result.convert("RGB").save(path, optimize=True)
            if os.path.dirname(path) == GALLERY:
                web_copy(path)
        print("wrote %s (%d KB)" % (os.path.relpath(path, ROOT), os.path.getsize(path) // 1024))


if __name__ == "__main__":
    main(sys.argv[1:])
