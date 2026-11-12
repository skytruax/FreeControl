#!/usr/bin/env python3
"""The game's own spell icons, for the pictures that show a filled bar.

The icons are Blizzard Entertainment's artwork. They appear in the pictures the way they appear in
any screenshot of the game; they are not part of the addon and are not covered by this
repository's licence. For that reason the icon files are never committed: they are downloaded on
first use into tools/.icon-cache/ (git-ignored) from a public mirror of the game's interface art,
pinned to one commit so the pictures can be rebuilt the same way.

    python3 tools/game_icons.py     # fetch every icon the pictures use; writes nothing else

The set below is a Rogue's, by ability name. tools/make_listing.py --placeholders draws stand-ins
instead and needs none of this.
"""
import os
import sys
import urllib.request

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "tools", ".icon-cache")
# https://github.com/Gethe/wow-ui-textures, branch "classic", as of 2026-11-12
MIRROR = "https://raw.githubusercontent.com/Gethe/wow-ui-textures/312a6e61bab69370c65ccc0a08f1075d62196294/ICONS/"

# Ability or item -> its icon file in the mirror (the file names are case-sensitive there).
FILES = {
    "Sinister Strike": "Spell_Shadow_RitualOfSacrifice.PNG",
    "Eviscerate": "Ability_Rogue_Eviscerate.PNG",
    "Slice and Dice": "Ability_Rogue_SliceDice.PNG",
    "Backstab": "Ability_BackStab.PNG",
    "Gouge": "Ability_Gouge.PNG",
    "Kick": "Ability_Kick.PNG",
    "Feint": "Ability_Rogue_Feint.PNG",
    "Sprint": "Ability_Rogue_Sprint.PNG",
    "Evasion": "Spell_Shadow_ShadowWard.PNG",
    "Vanish": "Ability_Vanish.PNG",
    "Cheap Shot": "Ability_CheapShot.PNG",
    "Kidney Shot": "Ability_Rogue_KidneyShot.PNG",
    "Ambush": "Ability_Rogue_Ambush.PNG",
    "Garrote": "Ability_Rogue_Garrote.PNG",
    "Rupture": "Ability_Rogue_Rupture.PNG",
    "Expose Armor": "Ability_Warrior_Riposte.PNG",
    "Blind": "SPELL_SHADOW_MINDSTEAL.PNG",
    "Stealth": "Ability_Stealth.PNG",
    "Sap": "ABILITY_SAP.PNG",
    "Distract": "Ability_Rogue_Distract.PNG",
    "Pick Pocket": "INV_Misc_Bag_11.PNG",
    "Instant Poison": "ABILITY_POISONS.PNG",
    "Blade Flurry": "Ability_Warrior_PunishingBlow.PNG",
    "Adrenaline Rush": "Spell_Shadow_ShadowWordDominate.PNG",
    "Throw": "Ability_Throw.PNG",
    "Healing Potion": "INV_Potion_54.PNG",
    "Thistle Tea": "INV_Drink_Milk_05.PNG",
    "Bandage": "INV_Misc_Bandage_12.PNG",
    "Mount": "Ability_Mount_RidingHorse.PNG",
    "Macro": "INV_Misc_QuestionMark.PNG",
}


def fetch(name):
    """Path of the cached icon file for an ability, downloading it first if it is not there."""
    target = os.path.join(CACHE, FILES[name])
    if not os.path.exists(target):
        os.makedirs(CACHE, exist_ok=True)
        with urllib.request.urlopen(MIRROR + FILES[name], timeout=30) as response:
            data = response.read()
        if not data.startswith(b"\x89PNG\r\n\x1a\n"):
            raise ValueError("%s%s did not return a PNG file" % (MIRROR, FILES[name]))
        partial = target + ".part"
        with open(partial, "wb") as f:
            f.write(data)
        os.replace(partial, target)
    return target


def icon(name):
    """The icon for an ability as an RGBA image (64 x 64, the size the game ships them in)."""
    return Image.open(fetch(name)).convert("RGBA")


if __name__ == "__main__":
    for ability in FILES:
        fetch(ability)
    print("%d icons in %s" % (len(FILES), os.path.relpath(CACHE, ROOT)))
    sys.exit(0)
