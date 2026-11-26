# Stance plan

First written 2026-11-14, before any stance code was changed, and built in version 1.3.0. Revised
2026-11-23 for versions 1.5.0 and 1.6.0, after a Druid reported that the stance sets did not seem
to work as intended and the design was checked against every class that has stances. What changed
since the first plan is listed at the end.

## Fork implementation plan

### Character settings and talent groups

- `FreeControlCharacterDB` is saved per character. The first load copies the legacy account
  settings, including bindings and button roles. Edits on the Other buttons and Combinations
  pages save WoW's active binding map to the character binding set.
- Forever's `C_SpecializationInfo.GetActiveSpecGroup()` and
  `ACTIVE_TALENT_GROUP_CHANGED` identify primary and secondary talents even if both builds use
  the same class specialization. The event and API were present on the live client. The test
  character had one talent group.
- The active talent group selects that group's saved page, paging options, slot source and
  stance-set configuration. Controller keys and button jobs belong to the character. Changing
  groups reapplies the bar outside combat.
- Action contents still live in Blizzard's action slots. Blizzard documents a [Secondary Talents
  action-bar persistence fix](https://worldofwarcraft.blizzard.com/en-us/news/24315281/wow-forever-hotfixes-november-13-2026).
  Verify a two-group character by placing different actions at the same slot in each group,
  switching both ways and relogging. Check a standard action slot, a controller-page slot, a
  standard stance slot and a controller stance slot separately. If any family is shared, it needs
  explicit profile storage before it can be counted as independent.

### Eight-button main bar

The existing layout consumes gamepad storage 181–304 on the live client. The client reported
181–360 as valid gamepad action storage. The pinned Forever UI source used by the simulator
defines three 28-slot standard pages and five 8-slot stance bars. It uses a separate pet-action
index for the possess bar. That leaves 305–360 as candidates for the additional layouts.
The validity check establishes the range. Ownership, secure use and persistence of those slots
still need verification.

The fork allocates one empty eight-slot block per form spell ID, skipping occupied blocks.
A secure form driver swaps all eight Main slots on every page and restores normal Main on
exit. Trigger sets retain their bonus-bar mapping. The Layout selector under Button assignments
lets each form's eight Main buttons mix commands and action slots. Existing action slots
are left in place. The mock covers drag and drop, combat switching, forms without a bonus bar,
and reordered Warrior stances. Live casting and persistence of these slots still need testing.

### Trigger locking

Press either configured trigger to lock its set. Press the second while the first is held to lock
the combined set. Releasing the triggers preserves the selection. Press the same trigger or
both triggers again to unlock its layer. Assign **Return to main layer**
under Other buttons, Combinations, or WoW's Key Bindings. Both selection and release run through
secure click handlers in and out of combat.

Uncheck **Toggle layers** in FreeControl settings for the original hold-to-shift behavior.

## The short version

- Some buttons change when you change stance or form, so each stance has its own abilities. For
  most classes that is one set of eight. For a Druid it is two sets and the D-pad, 20 buttons.
- They change on **one page only**, page 1 unless the Gamepad options say otherwise. Pages 2 and
  3, the both-triggers set and the face buttons are the same in every stance.
- A stance or form you put on a button that changes **stays on that button** in every stance that
  has nothing of its own there. The way back out of a form is never lost.
- A stance can also have **a button of its own**: any no-trigger button, bumper or paddle can be
  given "Stance or form: Bear Form". Nothing on the bar can cover it.

## What each class needs

This follows the classic rules. I have no list of what Forever changed, so the code does not
depend on this table: it asks the game which stance bar is up and follows the answer.

| Class | Stances or forms | Which change the bar | What that asks of the addon |
| --- | --- | --- | --- |
| Warrior | Battle, Defensive, Berserker | All three, and the Warrior is **always in one** | One changing set. Stance buttons put on it in one stance have to show in the other two. |
| Druid | Bear, Aquatic, Cat, Travel, Moonkin (and more) | Bear, Cat, Moonkin; Travel and Aquatic do not | No caster spell works in Cat or Bear, so two sets and the D-pad change. The forms themselves have to stay reachable. |
| Rogue | Stealth | Stealth | One changing set. Stealth itself should not vanish while stealthed. |
| Priest | Shadowform | Shadowform | One changing set. |
| Paladin | Auras, which the game lists on its stance bar | None | Nothing changes. An aura can still have a button of its own. |
| Hunter, Mage, Shaman, Warlock | none | none | Nothing. |

The two classes with more than one stance are the Warrior and the Druid, and they pull in
different directions. The Druid is in no form most of the time and steps into one; the Warrior
is never outside a stance. Anything that works from "the buttons you have while in no stance"
works for the Druid and does nothing for the Warrior. That was the gap in 1.5.0.

## What changes, and where

"Change with stance" on the settings page (called "Stance sets" up to 1.8.0). Its menu has
Automatic, Nothing and a tick for each of the four layouts; the other choices below are still
there for `/fc stance`:

| Choice | What changes with your stance or form |
| --- | --- |
| Automatic | Druid: RT set, LT set and the D-pad. Every other class: the one set picked in Options > Gamepad > Stance bar |
| Nothing | Nothing |
| Left trigger set, Right trigger set, Both triggers set | That set |
| Left and right sets | Both of them |
| Left, right and D-pad | Both of them and the four D-pad slots |
| My own pick | The layouts ticked at the bottom of the menu (`/fc stance custom main lt rt both`): Main and up to two of the three trigger sets |

With the player's own pick, Main changes with the form on the stance page alone, as the trigger
sets do, so the other pages are the same in every stance. With a ready-made choice Main still
changes on every page. Two trigger sets is the limit because the game has two places to keep a
set's buttons for each stance: the controller's stance bars and the regular action bar's stance
slots. The first set ticked (left, right, both, in that order) is kept in the first, the second
in the second.

They change on the **stance page**: the page Options > Gamepad > Stance bar puts the stance bar
on, which is page 1 unless the player moved it. This is how the game's own bars behave: its
regular action bar turns to a stance's slots on its first page only, and the Gamepad UI's stance
bar sits on one bar of one page. The other pages are the same in every stance, which gives a
Druid two pages that no form touches.

Since 1.7.0 pages can be switched off, which keeps the bar on one page of the player's choosing.
The stance page is then that page, whichever it is: there is no other for the player to go to,
and a bar that never changed with the stance would be the worse surprise.

With "Regular action bars" as the slots there is one page and Automatic changes nothing (those
bars have never followed the stance, and a Warrior would lose a set for good). A set picked by
hand does change there, with the D-pad if asked for.

## Where a stance's buttons are stored

A button that changes needs a separate place to keep its action for each stance. The game
already has two such places, and both are used rather than inventing one.

| What changes | Where its actions are kept | Shared with |
| --- | --- | --- |
| The first stance set | The controller stance bars: 8 slots for each stance | Blizzard's Gamepad UI mode |
| The second stance set | The first 8 of the 12 slots the regular action bar uses in that stance | Blizzard's main action bar in that stance |
| The D-pad with no trigger held | The last 4 of those 12 slots | Blizzard's main action bar in that stance |

So a Druid who already set up Cat and Bear bars in the normal interface finds those abilities on
the second set and the D-pad straight away, and what is dropped on those buttons in a form also
changes Blizzard's main action bar for that form.

## Stances that stay on their button

The trap, for every class: a stance is a spell like any other and can be dropped on a button that
changes with the stance. If the button then simply changed, the stance button would be gone the
moment it was used, and the way back with it.

The rule, since 1.6.0:

> A button that changes has up to six slots: one for no stance and one for each stance bar. In a
> stance where its own slot is empty, it shows the first of its slots that holds a stance or
> form. Where its own slot holds anything, it shows that.

What follows from it:

- **Druid:** Cat Form put on RT + A as a caster is still on RT + A as a cat and as a bear.
- **Warrior:** the three stances dropped on the right set in Battle Stance (which puts them in
  Battle's slots, there being no others to see) are on the same three buttons in Defensive and
  Berserker.
- **Rogue:** Stealth on the stance set is still there while stealthed, to leave stealth with.
- Dropping something on such a button while in a stance gives that stance its own, which covers
  the kept one in that stance alone. Taking it off again uncovers it.
- Only stances and forms are kept this way. An ordinary spell gives way as before, and an empty
  stance button stays empty: some players leave one empty on purpose, so that a stray press in
  stealth or in a form does nothing.

What counts as a stance or form is whatever the game lists on its own stance bar
(`GetShapeshiftFormInfo`), directly or through a macro that casts it.

## A button of its own for a stance

Blizzard's Gamepad UI gives Druids, Warriors and Paladins a control of their own for this: a
flyout of the class's forms on LB + LT or RB + RT. FreeControl leaves the bumpers to the player,
so it offers the same thing in its own terms: a button whose **job** is a stance.

- The game has commands for it, the ones its own stance bar is bound through: "change to the
  first stance or form", the second, and so on up to ten (`SHAPESHIFTBUTTON1` to `10`).
- Any of the eight no-trigger buttons can be given one (click the button on the bar), and so can
  a bumper, a stick click, Start, Back or a paddle (the Other buttons page). The menus list the
  character's own stances by name.
- Such a button is not an action slot. It wears the stance's icon, is lit while the character is
  in that stance, is dark while the stance cannot be used, and is the same on every page and in
  every stance. Nothing on the bar can cover it.
- The D-pad with no trigger held is the natural place: four buttons, always there. A Druid's
  D-pad buttons that are stance buttons are simply not part of what changes with the form.

Considered and left out for now:

- **One button that steps through the stances.** Handy for a Warrior, but there is no game
  command for it; it would need a secure button that works out the next stance itself. The
  direct buttons cover the need with code the game already runs.
- **A flyout or wheel of the forms**, as in the Gamepad UI. It needs a way to pick from it with
  the controller, which FreeControl does not have (see "Spell flyouts" under Known limits).

The buttons' jobs are shared by every character on the account, so a stance button set up on a
Druid is "the first stance" on a Warrior too, and does nothing on a Mage, where its tooltip says
so.

## How it works

Which slot each button shows is decided by the secure header that also rebinds the keys, because
the page and the stance can both change in a fight.

1. `Layout.lua` works out the groups that change, the stance page, and where each stance keeps
   its slots.
2. `Buttons:Assign` hands the header every button's slot on every page, and for a button that
   changes, where its stance slots are. Outside combat it also works out, for every such button
   and every stance, whether the button is to show a kept stance, and hands that over too.
3. A state driver tells the header which stance bar is up (`[bonusbar:1]` to `[bonusbar:5]`).
4. A restricted snippet then sets each button's `action`, for the visible button and for the
   key button on top of it. It asks the game nothing.
5. A stance button is bound straight to the game's command, like Jump or Interact.

## What has been checked, and what cannot be

There is no game on this machine. What stands in for it:

- **The mock client** has each class's stances by the classic rules and a port of Blizzard's
  state driver. One scenario walks seven kinds of character (Druid, a Druid whose Prowl has a
  bar, a Druid whose every form has one, Warrior, Rogue, Priest, Mage) through every stance
  setting, Gamepad option, page and form, in and out of combat, and checks every button and
  every key. Another scatters stances over a character's buttons at random and checks the rule
  above in every stance.
- **The simulator** runs Blizzard's real secure code but has no stances at all. Its test helper
  answers `[bonusbar:N]` from secure code, so Blizzard's own driver runs the stance snippets,
  with a stance bar coming up in the middle of a fight. The released 1.4.0 was run through the
  same test and passed: no defect in the changing itself was found.

What neither can say:

- Which stance bar each form of each class brings up in Forever, and whether Cat form with Prowl
  has one of its own. The code follows the game's answer, 1 to 5.
- Whether the regular action bar's stance slots are where they have always been (73 to 132), and
  the controller's stance bars where the plan expects them. `/fc status`, typed in a stance,
  compares both with what the game reports and says so in red if they differ. It also lists the
  stances the game reports and whether the bar followed the one that is up.

## Left out

- A third changing set. There is nowhere left to store it without taking over the regular action
  bars.
- A vehicle or possess bar.
- A button that steps through the stances, and a wheel of forms (see above).

## How the build has differed from the plan

Version 1.3.0, against the first plan:

- The setting's two new choices are called "Left and right sets" and "Left, right and D-pad"
  (`ltrt` and `all` for `/fc stance`), to fit the button.
- The game has five stance bars, not four, so the regular action bar's stance slots run from 73
  to 132, twelve for each.
- `/fc status` checks both kinds of stance slot against what the game reports for the stance you
  are in.

Version 1.5.0:

- Stance sets change on one page only. Before, a set picked by hand changed on whichever page was
  showing.
- The buttons are moved by one piece of secure code from one state driver, instead of a driver
  on each of forty buttons, so that turning the page and changing stance go through the same
  place.
- A stance put on a changing button while in no stance stays there (the Druid's case).
- A stance set picked by hand works with the regular action bars as the slots.

Version 1.6.0:

- The kept-stance rule works from any stance, which is what a Warrior needs.
- A stance can have a button of its own.

Version 1.7.0:

- With pages switched off, the stance page is the page the bar is on.
