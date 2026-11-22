# Changelog

## v1.5.0

- New: pages. The bar has the Gamepad UI's three pages now, each with its own buttons. Two arrows in the middle of the bar turn the page, with the number of the page between them. They work in a fight, and after page 3 comes page 1 again. The page you were on is the page you log back in to. `/fc page` and the Page choice on the settings page still work.
- The two arrows can go on any button. They are in the game's Key Bindings screen under FreeControl, as "next page" and "previous page", and on the new Other buttons page. Those two entries are all FreeControl adds to that screen.
- New: an Other buttons page, under FreeControl in the settings (`/fc buttons`). The bumpers, stick clicks, Start, Back and paddles have always been ordinary buttons that do whatever you bind them to, but nothing said so. The page lists them with what each one does and offers the common jobs in a menu: turn the page, the mouse pointer, targeting, the map, your bags and more. "Press it..." takes any other button or key, and one more button opens the game's Key Bindings screen. A job picked there is a normal key binding of your own, and stays when FreeControl is switched off.
- The left bumper: out of the box the game uses LB as a stand-in for the Ctrl key (`GamePadEmulateCtrl`), which is why it can seem to do nothing. The Other buttons page says so. Give LB a job there, or bind it to one of FreeControl's page arrows in Key Bindings, and FreeControl makes it a plain button while it is active. Your own setting is put back when you log out or switch FreeControl off, like the other settings it touches. The same goes for a button you have set to stand in for Shift or Alt (`GamePadEmulateShift`, `GamePadEmulateAlt`).
- Stances and forms: a shapeshift on a button that changes with your form now stays on that button. Before, a Druid who put Cat Form on the right set lost that button the moment they shifted, and the way back out with it. A form, Stealth or a stance now stays where you put it, in every stance or form that has nothing of its own on that button. Drop something on the button while you are in a form to give that form its own. Chat explains this the first time it comes up.
- Changed: stance sets change on one page only, as the game's own bars do: page 1, or the page **Options > Gamepad > Stance bar** names. The other pages are the same in every stance or form. Before, a set you picked by hand changed on whichever page was showing.
- With "Regular action bars" as the slots, a stance set you pick by hand now changes: one set, and the D-pad if you choose that, kept in the slots the game's own bar uses in that stance. Automatic still changes nothing there. Before, the setting did nothing with those slots and the page did not say so.
- The Stance sets tooltip now says what the setting comes to on your character. `/fc status` lists the stances or forms the game reports, which one you are in, which stance bar is up and whether the bar followed it, along with the page and the buttons that turn it. If your forms do not behave, that is the part to send.
- A Druid reported that the stance sets did not seem to work as intended. Run against Blizzard's own interface code with a stand-in for the forms, the changing itself worked, in 1.4.0 as well; what turned up was the vanishing shapeshift above. Which bar each form brings up is the game's own data and could not be checked without the game.

## v1.4.0

- Fixed: when you learned a new rank of a spell, the copy on the bar stayed at the old rank. The game moves spells on its regular action bars up by itself, but not the ones on the controller's slots while you are outside Gamepad UI mode, and those are the slots FreeControl shows. FreeControl now moves them up itself, out of combat, and chat names the spells it moved.
- The first time each character logs in with this version, every spell on its controller slots that is on a lower rank is moved up once, since nothing kept them current before. After that, a lower rank you put on a slot yourself is left alone. `/fc ranks` moves everything up on request, and "Keep spells at their newest rank" on the settings page switches the whole thing off.
- New: a button glows gold while its spell has procced. FreeControl follows the game's own proc signal, the one its regular action bars use, so what lights up there lights up here.
- New: Overpower, Victory Rush, Riposte, Counterattack and Mongoose Bite glow for the moment they can be used, and Ambush when it can be used outside stealth. The game only lights those buttons up, which is easy to miss. This part goes by the abilities' English names, so it works on an English client only.
- "Glow when a spell procs" on the settings page, or `/fc glow off`, switches the glow off. `/fc status` says what is glowing and which spells are on a lower rank.

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
