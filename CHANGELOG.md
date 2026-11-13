# Changelog

## v1.1.1

- Fixed: the cooldown of an ability that has one of its own, such as Kick or Gouge, could take seconds to appear on the bar. The bar followed only the action bar's cooldown event, which the game does not raise when such a cooldown starts. It now also follows the game's spell and item cooldown events, and reads every cooldown again for a moment after each press.

## v1.1.0

- Every slot is now registered with the game the way Blizzard's own action buttons are.
- Controller buttons always act on the press, even with "cast on key down" switched off in the game options.
- Buttons sink in when you press them and spring back when you let go.
- New option: a countdown on every slot that is on cooldown. It is on by default; untick "Cooldown numbers" on the settings page or type `/fc numbers off`.
- Quieter look: thinner, near-black button rims instead of gold, and only a faint dark shade behind the held set instead of the glow.
- An equipped item is marked with a green ring.

## v1.0.1

First version published on CurseForge. The addon itself is the same as v1.0.0.

## v1.0.0

First public release, for World of Warcraft: Forever 1.60.1.

- Cross hotbar with four sets of eight buttons: no trigger, LT, RT and LT + RT.
- Every slot takes spells, items and macros by drag and drop, and shares the slots Blizzard's Gamepad UI uses.
- Interact, Cancel / game menu and Jump on the face buttons with no trigger held; each no-trigger button can be changed to an action slot, another command, or left to your own key binding.
- One set can swap with your stance or form.
- Xbox, PlayStation and Nintendo button labels.
- Settings page and `/fc` commands for position, size and behaviour.
