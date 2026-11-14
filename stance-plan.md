# Stance plan

Written 2026-11-14, before any stance code was changed. It was then built as written, in
version 1.3.0; the three places where the build ended up different are listed at the end.

## The short version

Today one set of eight buttons changes when you change stance or form, and the other 24 stay
the same. That is enough for a Rogue, a Priest and a Warrior. It is not enough for a Druid: in
Cat or Bear form none of the caster spells work, so 24 of the 32 buttons are dead.

The plan: let up to **two sets and the D-pad** change with your stance or form (20 buttons), and
make that the automatic choice for Druids. Every other class keeps what it has now unless the
player asks for more.

## What each class needs

This follows the classic rules. I have no list of what Forever changed, so the code does not
depend on this table: it asks the game which stance bar is active and follows the answer.

| Class | Stances or forms that change the bar | Abilities that only work there | What it gets automatically |
| --- | --- | --- | --- |
| Druid | Cat, Bear, Moonkin (Travel and Aquatic do not change the bar) | 10 to 13 each for Cat and Bear, and no caster spell works in either | RT set, LT set and the D-pad change (20 buttons) |
| Warrior | Battle, Defensive, Berserker (always in one of them) | About 5 each | One set changes, as now |
| Rogue | Stealth | About 6 | One set changes, as now |
| Priest | Shadowform | A few | One set changes, as now |
| Hunter, Mage, Paladin, Shaman, Warlock | none | none | Nothing changes, as now |

## Where the stance buttons are stored

A button that changes with your stance needs a separate place to keep its action for each
stance. The game already has two such places, and the plan uses both rather than inventing one.

| What changes | Where its actions are kept | Shared with |
| --- | --- | --- |
| The first stance set (RT set unless Options > Gamepad > Stance bar says another) | The controller stance bars: 8 slots for each stance | Blizzard's Gamepad UI mode, exactly as now |
| The second stance set (the other trigger set) | The first 8 of the 12 slots the regular action bar uses in that stance | Blizzard's main action bar in that stance |
| The D-pad with no trigger held | The last 4 of those 12 slots | Blizzard's main action bar in that stance |

Two things follow from that:

- A Druid who already set up Cat and Bear bars in the normal interface finds those abilities
  on the second set and the D-pad straight away.
- Anything dropped on those buttons while in a form also changes Blizzard's main action bar
  for that form. The "your regular action bars are never touched" promise gets that one
  exception, and the settings page and README will say so.

The both-triggers set and the face buttons never change. That is where the things you need in
every form go: the shapeshifts themselves, a mount, a trinket.

## The setting

"Stance set" on the settings page becomes "Stance sets", with these choices:

| Choice | What changes with your stance or form |
| --- | --- |
| Automatic | Druid: RT set, LT set and the D-pad. Every other class: the one set picked in Options > Gamepad > Stance bar |
| Nothing | Nothing |
| Left trigger set | That set (as now) |
| Right trigger set | That set (as now) |
| Both triggers set | That set (as now) |
| Left and right trigger sets | Both of them |
| Left and right sets and the D-pad | Both of them and the four D-pad slots |

Existing setups are on "Automatic" unless the player changed it, so:

- Rogues, Warriors and Priests see no change at all.
- Druids get the three changing groups the next time they log in, and a line in chat that
  says so once, because their LT set and D-pad will look different in a form.

## What changes in the code

1. `Layout.lua`: work out which groups of buttons change (one, two, or two and the D-pad) and
   the slot each one uses in each stance. Today it knows about one set only.
2. `Buttons.lua`: give every changing button its stance driver. Today only the one set gets
   one. The driver itself is the same kind as now and already works in a fight.
3. `Options.lua`: the new choices, the wording above, and `/fc status` lines that list the
   changing groups and their slots.
4. `Core.lua`: accept the new saved values, and the one-time chat line for Druids.
5. Tests: scenarios for each choice, for each class default, for a stance change in combat,
   for a no-trigger D-pad button that the player turned into something other than an action
   slot, and for switching back.
6. README, CurseForge description and changelog.

## What I cannot check from here

There is no game on this machine, so these go on the list to try after the release:

- That Forever numbers its stance bars the way classic does (Cat 1, Bear 3, Moonkin 4, and so
  on). The code does not assume the numbers, but the table above does.
- That the regular action bar's stance slots are where they have always been (73 to 120). I
  read this in Blizzard's interface code for Forever; I have not seen it in the game.
- Whether Cat form with Prowl has a bar of its own in Forever. If it does, it will simply be
  one more stance with its own buttons.

## Left out of this version

- A third changing set. There is nowhere left to store it without taking over your regular
  action bars.
- Stance changes when the slots are set to "Regular action bars" instead of the controller
  slots. That mode has never had them.
- A vehicle or possess bar.

## How the build differs from this plan

- The setting's two new choices are called "Left and right sets" and "Left, right and D-pad"
  on the settings page (`ltrt` and `all` for `/fc stance`), to fit the button.
- The game has five stance bars, not four, so the regular action bar's stance slots run from
  73 to 132, twelve for each.
- `/fc status` checks both kinds of stance slot against what the game reports for the stance
  you are in, and says so in red if they differ. That is how the first two points under "What I
  cannot check from here" get checked: shift into a form and type `/fc status`.
