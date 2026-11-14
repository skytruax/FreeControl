# Changelog

## v1.3.2

- The mouse button now wears FreeControl's mascot where the arrow was: a little black dog that is half chihuahua, half beetle. The button does what it did: it brings the mouse pointer out, puts it away, and is lit while the pointer is out.

## v1.3.1

- New icons for the buttons that run a command. Each is a small copy of the FreeControl emblem: its bronze compass ring around a glazed disc, with the symbol in white. Interact, the mouse pointer, Cancel and Jump take the colours the emblem gives X, Y, B and A, so the four buttons the bar starts with are blue, yellow, red and green.
- Y is now the mouse button on every setup that has no mouse button, including one where Y had another job. Version 1.3.0 left those alone, so the pointer had no button until you picked one from the menu. This happens once, and chat says what Y was doing before; to put that back, click Y on the bar. After that your choice stands.
- A command button on the D-pad shows its whole icon. The edge was trimmed before, as it is for spell icons.

## v1.3.0

- Fixed: the mouse pointer did not come out when you pressed its button while playing with the controller. The game hides the pointer for as long as the controller is steering the camera, and version 1.2.0 asked for the pointer without taking the camera off the stick first. It now does that first, and hands the stick back to the camera when you put the pointer away.
- Y is the mouse button for everyone, and FreeControl binds it, the same way it binds Interact. There is nothing to set up: the entry in the game's Key Bindings screen is gone. If you set FreeControl up before this version and Y had no job, it is the mouse button now, and chat says so once. If you had given Y a job of your own it keeps it; click any no-trigger button on the bar and choose "Mouse pointer on / off".
- To put the pointer away, press Y again or jump. The notes for 1.2.0 also said that moving puts it away; that was wrong.
- While it is active, FreeControl now switches off the game's option that pins the controller pointer to the middle of the screen (`GamePadCursorCentering`), in case something had switched it on. Your own value is put back when you log out, like the other settings it touches.
- Druids: the right set, the left set and the D-pad now all change with your form, so each form has 20 buttons of its own. Before, one set of eight changed and the other 24 buttons held caster spells you could not use in a form. The both-triggers set and the face buttons stay the same in every form: put your shapeshifts there. The left set and the D-pad show the slots of the game's own action bar for that form, so a bar you set up there is already filled in.
- Every other class keeps one changing set, as before. "Stance sets" on the settings page (it was "Stance set") lets any class pick more: both trigger sets, or both and the D-pad. `/fc stance` does the same from chat.
- Fixed: the ring around an equipped item was always green. It now has the colour of the item's rarity, so a rare item is blue and an epic one purple.
- `/fc status` now shows what the game says about its pointer and its camera mode, how often the mouse button was pressed and what came of it, and whether the game keeps a stance's slots where FreeControl expects them. If the game refuses to bring the pointer out, chat says so once.
- If the game refuses a call from FreeControl, which it does without raising an error, that is now kept for `/fc status` too.

## v1.2.0

- New: mouse mode with a way to click. Press Y (the top face button, with no trigger held) and the right stick steers the mouse pointer. Click the left stick for the left mouse button, and hold it to drag; click the right stick for the right mouse button. Press Y again, or move or jump, to put the pointer away. The Y button on the bar shows a pointer and is lit while the pointer is out.
- If you set FreeControl up before this version, your Y button is left as you had it. Click it on the bar and choose "Mouse cursor on / off", or keep using the key binding.
- The two click buttons can be changed on the settings page, under the new "Mouse mode" heading: stick clicks, bumpers, Y or paddles. A click button you can hold while your right thumb steers is what makes dragging possible.
- New: pointer speed, on the settings page and as `/fc pointer <50-300>`.
- RT no longer turns into the left mouse button whenever the game brings its pointer out. FreeControl now points the game's two click settings at the stick clicks while it is active and puts yours back when you log out.
- `/fc mouse` brings the pointer out or puts it away, `/fc click left|right <button>` changes a click button, and `/fc status` shows the click buttons and what they are bound to.
- New emblem.

## v1.1.2

- Cooldowns in a fight: the sweep of an ability such as Kick or Gouge could be missing until the fight was over. In combat the game hides a cooldown's exact numbers from addons, and the bar was handing those numbers to the sweep, which the game refuses without showing an error. The bar now hands the sweep the game's own timer object instead, which is how addons are meant to show cooldowns in combat. Versions 1.1.0 and 1.1.1 changed other things for this and did not help.
- The bar no longer reads a pressed button's cooldown again after the press (added in 1.1.1), and no longer registers its slots with the game (added in 1.1.0). Neither was the cause, and neither is needed.
- If something goes wrong inside FreeControl it now says so once in chat, and `/fc status` shows the error, even when the game is set to hide addon errors.
- New: `/fc trace` records what the game reports about the next abilities you use, for bug reports about cooldowns.

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
