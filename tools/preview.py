#!/usr/bin/env python3
"""Renders a picture of the bar from the shipped textures and the layout numbers in Layout.lua.

    python3 tools/preview.py                  # writes docs/preview.png and docs/textures.png
    python3 tools/preview.py --placeholders   # the same, with drawn stand-ins for the spell icons

This is a mock-up, not the game: it places the same textures at the same offsets the addon uses,
so the art and the spacing can be judged without launching the client. The filled slots show a
Rogue's spell icons, which are Blizzard's and are fetched by tools/game_icons.py, or stand-ins
drawn by tools/placeholder_icons.py. tools/make_listing.py builds the store and README pictures
with the Painter class below.
"""
import functools
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # the sibling modules, also under python -I
import game_icons  # noqa: E402
import placeholder_icons  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "FreeControl", "Art")
DOCS = os.path.join(ROOT, "docs")

ACTIVE_SCALE, INACTIVE_ALPHA = 1.2, 0.8  # the addon's defaults (Core.lua)
ICON_INSET = 2  # bar units between a button's edge and its icon (Buttons.lua)
STYLES = {  # face buttons left, top, right, bottom, then the two triggers; as in Layout.lua
    "xbox": (["X", "Y", "B", "A"], ["LT", "RT"]),
    "playstation": (["Square", "Triangle", "Circle", "Cross"], ["L2", "R2"]),
    "nintendo": (["Y", "X", "A", "B"], ["ZL", "ZR"]),
}
DPAD = ["DpadLeft", "DpadUp", "DpadRight", "DpadDown"]
# What Buttons.lua multiplies an icon's colour by in each state.
TINTS = {"unusable": (0.4, 0.4, 0.4), "nomana": (0.5, 0.5, 1.0), "range": (0.9, 0.25, 0.25)}


# ---------------------------------------------------------------------------
# Layout numbers, read from the addon so the picture cannot drift from the code
# ---------------------------------------------------------------------------
def read_layout():
    src = open(os.path.join(ROOT, "FreeControl", "Layout.lua")).read()

    def numbers(pattern):
        return [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", re.search(pattern, src, re.S).group(1))]

    def pairs(values):
        return [tuple(values[i:i + 2]) for i in range(0, len(values), 2)]

    offsets = numbers(r"Layout\.SET_OFFSET = \{(.*?)\n\}")
    return {
        "button": numbers(r"Layout\.BUTTON_SIZE = (\d+)")[0],
        "root": numbers(r"Layout\.ROOT_SIZE = \{(.*?)\}"),
        "set": numbers(r"Layout\.SET_SIZE = \{(.*?)\}"),
        # each entry reads "[n] = { x, y }", so drop the index
        "set_offset": {int(offsets[i]): (offsets[i + 1], offsets[i + 2]) for i in range(0, len(offsets), 3)},
        "button_offset": pairs(numbers(r"Layout\.BUTTON_OFFSET = \{(.*?)\n\}")),
        "label_offset": numbers(r"Layout\.LABEL_OFFSET = \{(.*?)\}"),
    }


LAYOUT = read_layout()


@functools.lru_cache(maxsize=None)
def tex(name):
    """A shipped texture, exactly as the game loads it."""
    return Image.open(os.path.join(ART, name + ".tga")).convert("RGBA")


def sized(img, w, h):
    return img.resize((max(1, round(w)), max(1, round(h))), Image.LANCZOS)


def faded(img, alpha):
    if alpha == 1.0:
        return img
    img = img.copy()
    img.putalpha(img.getchannel("A").point(lambda v: int(v * alpha)))
    return img


def paste(canvas, img, cx, cy, alpha=1.0, add=False):
    """Composites img centred on (cx, cy); with add, lightens instead, like an additive texture."""
    img = faded(img, alpha)
    x, y = round(cx - img.width / 2), round(cy - img.height / 2)
    if add:
        region = np.asarray(canvas.crop((x, y, x + img.width, y + img.height))).astype(np.float32)
        src = np.asarray(img).astype(np.float32)
        region[..., :3] = np.clip(region[..., :3] + src[..., :3] * src[..., 3:4] / 255.0, 0, 255)
        canvas.paste(Image.fromarray(region.astype(np.uint8), "RGBA"), (x, y))
    else:
        canvas.alpha_composite(img, (x, y))


@functools.lru_cache(maxsize=None)
def game_icon(name):
    """The game's icon for an ability named in game_icons.FILES."""
    return game_icons.icon(name)


def placeholder_icon(name):
    """A drawn stand-in for the same ability: always the same one for the same name."""
    return placeholder_icons.icon(list(game_icons.FILES).index(name))


def FONT(size, weight="SemiBold"):
    for path in (os.path.expanduser("~/.local/share/fonts/Inter/Inter-%s.ttf" % weight),
                 "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    raise FileNotFoundError("no font found; add one to FONT() in tools/preview.py")


# ---------------------------------------------------------------------------
# The bar, composited the way Buttons.lua and Bars.lua stack their textures
# ---------------------------------------------------------------------------
class Painter:
    """Draws buttons and whole bars at `k` pixels per bar unit.

    `textures` maps a texture name to an image. It defaults to the shipped files; a caller that
    draws large can pass sharper renderings of the same art. `icons` maps an ability name to its
    icon: game_icon or placeholder_icon.
    """

    def __init__(self, k=2.0, textures=tex, icons=game_icon):
        self.k = k
        self.textures = textures
        self.icons = icons
        self._sized = functools.lru_cache(maxsize=None)(lambda name, w, h: sized(self.textures(name), w, h))

    def tex(self, name, w, h):
        return self._sized(name, max(1, round(w)), max(1, round(h)))

    def button(self, canvas, cx, cy, index, face, content, scale=1.0, alpha=1.0, state="normal", active=False,
               count=None):
        """One button. index is 1-4 for the D-pad (square) and 5-8 for the face buttons (round).

        content: None or ("pass",) for an empty slot, ("icon", ability) or ("role", name).
        state: normal, cooldown, unusable, nomana, range, checked, pushed or hover; or
        ("cooldown", "14") to print the seconds left as the addon's cooldown numbers do.
        """
        countdown = None
        if isinstance(state, tuple):
            state, countdown = state
        k = self.k * scale
        round_shape = index > 4
        shape = "Round" if round_shape else "Square"
        size = LAYOUT["button"] * k
        paste(canvas, self.tex(shape + "-Base", size, size), cx, cy, alpha)

        glyph = "Glyph-" + (DPAD[index - 1] if index <= 4 else face[index - 5])
        icon = None
        if content and content[0] == "icon":
            icon = self.icons(content[1])
        elif content and content[0] == "role":
            icon = self.textures("Role-" + content[1])
        if icon is not None:
            inner = round(size - 2 * ICON_INSET * k)
            clip = self.tex(shape + "-Mask", inner, inner).getchannel("A")
            if round_shape:
                icon = sized(icon, inner, inner)
            else:
                w = icon.width
                icon = sized(icon.crop((round(w * 0.07), round(w * 0.07), round(w * 0.93), round(w * 0.93))), inner, inner)
            icon.putalpha(Image.fromarray(np.minimum(np.asarray(icon.getchannel("A")), np.asarray(clip))))
            if state in TINTS:
                bands = icon.split()
                icon = Image.merge("RGBA", [band.point(lambda v, m=m: int(v * m)) for band, m in zip(bands, TINTS[state])]
                                   + [bands[3]])
            paste(canvas, icon, cx, cy, alpha)
            if state == "cooldown":
                sweep = Image.new("RGBA", (inner, inner), (0, 0, 0, 0))
                ImageDraw.Draw(sweep).pieslice((-inner, -inner, inner * 2, inner * 2), -90, 150, fill=(0, 0, 0, 184))
                sweep.putalpha(Image.fromarray(np.minimum(np.asarray(sweep.getchannel("A")), np.asarray(clip))))
                paste(canvas, sweep, cx, cy, alpha)
        else:
            paste(canvas, self.tex(glyph, 20 * k, 20 * k), cx, cy, alpha * 0.5)

        paste(canvas, self.tex(shape + "-Border", size, size), cx, cy, alpha)
        if state == "pushed":
            paste(canvas, self.tex(shape + "-Pushed", size, size), cx, cy, alpha)
        if countdown is not None:
            ImageDraw.Draw(canvas).text((cx, cy), countdown, anchor="mm", font=FONT(round(15 * k), "Bold"),
                                        fill=(255, 255, 255, round(255 * alpha)), stroke_width=max(1, round(0.9 * k)),
                                        stroke_fill=(0, 0, 0, round(255 * alpha)))
        if state == "checked":
            paste(canvas, self.tex(shape + "-Checked", size, size), cx, cy, alpha)
        if state == "hover":
            paste(canvas, self.tex(shape + "-Highlight", size, size), cx, cy, alpha, add=True)
        if count is not None:
            d = ImageDraw.Draw(canvas)
            d.text((cx + size / 2 - 4.5 * k, cy + size / 2 - 5 * k), count, anchor="rs", font=FONT(round(10 * k), "Bold"),
                   fill=(255, 255, 255, 255), stroke_width=max(1, round(0.8 * k)), stroke_fill=(0, 0, 0, 255))
        if active and round_shape and content and content[0] == "icon":
            reach = (LAYOUT["button"] / 2 - 4) * k
            paste(canvas, self.tex(glyph, 15 * k, 15 * k), cx + reach, cy - reach, alpha)

    def set_centre(self, ox, oy, set_id):
        sx, sy = LAYOUT["set_offset"][set_id]
        return ox + sx * self.k, oy - sy * self.k

    def one_set(self, canvas, cx, cy, set_id, style, contents, active=False, states=None, counts=None, glow=True):
        """One set of eight buttons centred on (cx, cy), with its trigger badges. states and counts
        are keyed by button index."""
        face, triggers = STYLES[style]
        states, counts = states or {}, counts or {}
        scale, alpha = (ACTIVE_SCALE, 1.0) if active else (1.0, INACTIVE_ALPHA)
        k = self.k * scale
        lx, ly = LAYOUT["label_offset"]
        if active and glow:  # the faint dark patch behind the held set
            paste(canvas, self.tex("Set-Shade", (LAYOUT["set"][0] + 88) * k, (LAYOUT["set"][1] + 68) * k), cx, cy)
        badges = {1: [(0, triggers[0])], 2: [(0, triggers[1])], 3: [(-23, triggers[0]), (23, triggers[1])]}.get(set_id, [])
        for dx, name in badges:
            paste(canvas, self.tex("Badge-" + name, 34 * k, 17 * k), cx + (lx + dx) * k, cy - ly * k, alpha)
        if set_id == 3:
            ImageDraw.Draw(canvas).text((cx + lx * k, cy - ly * k), "+", anchor="mm", font=FONT(round(11 * k)),
                                        fill=(255, 255, 255, round(255 * alpha)))
        for index in range(1, 9):
            bx, by = LAYOUT["button_offset"][index - 1]
            self.button(canvas, cx + bx * k, cy - by * k, index, face, contents[index - 1], scale, alpha,
                        states.get(index, "normal"), active, counts.get(index))

    def button_centre(self, ox, oy, set_id, index, active=False):
        """Where a button of the bar centred on (ox, oy) is drawn."""
        cx, cy = self.set_centre(ox, oy, set_id)
        k = self.k * (ACTIVE_SCALE if active else 1.0)
        bx, by = LAYOUT["button_offset"][index - 1]
        return cx + bx * k, cy - by * k

    def bar(self, canvas, ox, oy, held, style, content, states=None, counts=None, glow=True):
        """The whole bar centred on (ox, oy). held is the set shown as selected: 0 none, 1 the left
        trigger, 2 the right, 3 both. content[set] lists what the eight buttons of a set hold;
        states and counts are keyed by (set, button index)."""
        states, counts = states or {}, counts or {}
        for set_id in (0, 1, 2, 3):
            cx, cy = self.set_centre(ox, oy, set_id)
            self.one_set(canvas, cx, cy, set_id, style, content.get(set_id, [None] * 8), set_id == held,
                         {i: v for (s, i), v in states.items() if s == set_id},
                         {i: v for (s, i), v in counts.items() if s == set_id}, glow)


def spells(*names):
    return [("icon", name) if name else None for name in names]


# A Rogue's bar, mostly filled: what the pictures show unless they say otherwise. Each row lists
# D-pad left, up, right, down, then the face buttons left, top, right, bottom.
CONTENT = {
    0: spells("Sinister Strike", "Healing Potion", "Eviscerate", "Slice and Dice")
       + [("role", "Interact"), ("role", "Cursor"), ("role", "Cancel"), ("role", "Jump")],
    1: spells("Backstab", "Gouge", "Kick", "Feint", "Sprint", "Evasion", None, "Vanish"),
    2: spells("Cheap Shot", "Kidney Shot", "Ambush", "Garrote", "Rupture", "Expose Armor", "Blind", "Stealth"),
    3: spells("Sap", "Distract", None, "Pick Pocket", "Instant Poison", "Bandage", "Mount", None),
}
# Kidney Shot and Sprint on cooldown; Ambush dark, as it is out of stealth.
STATES = {(2, 2): ("cooldown", "14"), (1, 5): ("cooldown", "38"), (2, 3): "unusable"}
COUNTS = {(0, 2): "5", (3, 6): "12"}


def background(w, h):
    rng = np.random.default_rng(7)
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    dist = np.hypot((x - w / 2) / (w / 2), (y - h / 2) / (h / 2))
    base = np.array((40, 46, 60), dtype=np.float32) * np.clip(1.1 - 0.45 * dist, 0.4, 1.1)[..., None]
    grain = rng.normal(0, 2.5, (h // 3 + 1, w // 3 + 1)).astype(np.float32)
    base = base + np.asarray(Image.fromarray(grain).resize((w, h), Image.BICUBIC))[..., None]
    return Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def render(held, style, title, k=2.0, icons=game_icon):
    rw, rh = int(LAYOUT["root"][0] * k), int(LAYOUT["root"][1] * k)
    pad = 26
    canvas = background(rw + 2 * pad, rh + 2 * pad + 22)
    Painter(k, icons=icons).bar(canvas, pad + rw / 2, pad + 22 + rh / 2, held, style, CONTENT, STATES, COUNTS)
    ImageDraw.Draw(canvas).text((pad, 12), title, fill=(235, 235, 235, 255), font=FONT(15))
    return canvas


def texture_sheet():
    names = sorted(f[:-4] for f in os.listdir(ART) if f.endswith(".tga"))
    cell, cols = 112, 9
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * (cell + 16)), (58, 62, 70, 255))
    d = ImageDraw.Draw(sheet)
    for i, name in enumerate(names):
        img = tex(name).copy()
        img.thumbnail((96, 96), Image.LANCZOS)
        cx, cy = (i % cols) * cell + cell // 2, (i // cols) * (cell + 16) + cell // 2
        sheet.alpha_composite(img, (cx - img.width // 2, cy - img.height // 2))
        d.text((cx, cy + 58), name, anchor="mm", fill=(220, 220, 220, 255), font=FONT(10))
    return sheet


if __name__ == "__main__":
    os.makedirs(DOCS, exist_ok=True)
    source = placeholder_icon if "--placeholders" in sys.argv[1:] else game_icon
    frames = [
        render(0, "xbox", "No trigger held", icons=source),
        render(2, "xbox", "Right trigger held", icons=source),
        render(3, "playstation", "Both triggers held (PlayStation labels)", icons=source),
    ]
    out = Image.new("RGBA", (frames[0].width, sum(f.height for f in frames)), (0, 0, 0, 255))
    y = 0
    for frame in frames:
        out.alpha_composite(frame, (0, y))
        y += frame.height
    out.convert("RGB").save(os.path.join(DOCS, "preview.png"))
    texture_sheet().convert("RGB").save(os.path.join(DOCS, "textures.png"))
    print("wrote", os.path.join(DOCS, "preview.png"), "and textures.png")
