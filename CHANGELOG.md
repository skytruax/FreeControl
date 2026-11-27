# Changelog

## Unreleased

- New: each talent group (spec) has a layout of its own, like another character. Before, switching spec changed only the few buttons the game keeps on its regular action bars and left everything else on the bar as it was. Now what is on every button, on every page and in every stance, and which buttons have jobs, is kept for each talent group and put back when you switch to it. A talent group starts as a copy of what you had the first time you switch to it, and is its own from then on. A spell the talent group does not have leaves its button empty, and chat says how many. `/fc specs off` goes back to one shared layout.

- Changed: the Other buttons page and the Combinations page are for the account now, not for one character. The jobs of the bumpers, stick clicks, paddles and extra buttons, the combinations and the buttons to hold are the same on all your characters: set them once, and each character is given them when it enters the world. The first character you play with this version is the one the account starts from; a character that comes after it gets the account's in place of its own.
- Fixed: a Paladin's auras were taken for stances. With Main ticked under Change with stance, switching aura swapped the Main buttons for an empty set, as if the Paladin had shapeshifted. Layouts now change with the stance only for the classes whose stances change what they can cast: Warrior (stances), Druid (forms) and Rogue (Stealth). For every other class nothing changes, whatever is ticked: a Priest's Shadowform is not a stance either, since the same Shadow spells are cast in it. An aura or Shadowform can still be given a button of its own.

- New: while the mouse pointer is out, the two triggers are the mouse wheel: the left one turns it up, the right one down, and holding one keeps turning. Over the map, a list or the chat it scrolls or zooms that window; over the world it zooms the camera. Put the pointer away and they are triggers again. "The triggers are the mouse wheel" on the Mouse mode page, or `/fc scroll off`, switches it off.
- New jobs for an item the group is rolling for: "Loot roll: Need", "Loot roll: Greed" and "Loot roll: Pass". A press answers the roll; with several items up, each press answers the next one, and chat says which item it was. For an item that binds when picked up the game asks first: press the same job again to confirm, or another of the three to change your answer.
- Fixed: a face button with no trigger held that you made an action slot (X, Y, B or A; Y is one with mouse mode off) no longer shares its slot with LT + RT + the same button on the page before. What you put on LT + RT + X on page 1 used to turn up on X on page 2, and changing one changed the other. Each of those buttons now has a slot of its own on every page, on the second page of the game's main action bar (slots 13 to 24). After updating they show whatever is in those slots, most likely nothing: what they showed before is still on the LT + RT buttons, where it can be dragged from.
- New jobs for grouping up with your target, on the bar or any other button, in a fight too: "Invite target" (`/invite`), "Ask to join target's group" (`/requestinvite`), "Leave party", and "Invite target, or ask to join", which invites a target who is alone and asks to join one who is already in a group. Out of combat it does only the one that applies; in a fight it cannot look, so it tries both and the game refuses the other with a line of red text.
- New job: "Accept group invite or request" presses Accept on the game's dialog when you are invited to a group, or when someone asks to join yours. It answers no other dialog.
- New job: "Target's menu" opens the game's own menu for your target (inspect, mark, whisper, trade and the rest) where the mouse pointer is, and brings the pointer out to pick from it.
- New: a keyboard for the chat. Give a button the job "Chat keyboard" (click a button on the bar, or use Other buttons) and it opens the chat with an on-screen keyboard; it also comes up whenever the chat is opened another way, such as a name clicked to whisper. The D-pad or the left stick moves a highlight over the keys, A types the key it is on, X deletes, Y sends, and B empties the message and then closes the chat. Space, Shift and 123 are keys like the rest. Its settings are on the new Chat page (`/fc chat`).
- The keyboard suggests words as you type, in English, French, German, Spanish or Italian, and learns the ones you use: move up from the top row of keys to reach them, and A takes one. `/fc keyboard forget` empties what it learned.
- A row of channels under the keys (`/s /y /p /ra /g /1 /w /r`): LB and RB go through it. The channel you wrote on last is the one the keyboard opens on next time, for each character, after logging in again too ("Come back to the last channel" on the Chat page).
- New: quick phrases. The job "Quick phrases" (or `/fc phrases`) opens a window of ready-made phrases, five a row by theme. The D-pad or the left stick picks one, LB and RB the channel, A sends it and closes. X rewrites a phrase or a row's name, Y opens the keyboard with the phrase, and rows of your own can be added, up to eight. A phrase that starts with `/` is run as a command. The phrases are the same for all your characters.
- While the keyboard or the phrases window is open the controller is its own: the bar lets go of every button, triggers included, and has them back on its main layer when the window closes. Neither works in a fight: an open one closes when a fight starts, and the keyboard comes back afterwards if the chat is still being typed in.
- `/fc keyboard` opens or closes the keyboard from chat; `on | off`, `unlock | lock | reset` and `scale` switch it, move it and size it.
- The keyboard's frame, its word prediction, its channel row and the quick phrases are ported from Easy Controller - Forever by moust4ki (MIT), with its word lists from FrequencyWords (CC-BY-SA-4.0); the notices are in `Chat/LICENSE-EasyController.txt`. The keys and their buttons are FreeControl's own: that addon's two keyboards, a daisywheel and a split keyboard typed with the sticks and triggers, are not in it. Also left out: its quest links, drafts, keyboard for the game's other fields, and its other languages for the text on screen.

## v1.8.0

- New: button combinations. Two or three buttons pressed together can have a job of their own: LB + D-pad Up to target a party member, or LB + RB + D-pad Right to turn the page. They are made on the new Combinations page (under FreeControl in the settings, or `/fc combos`): click "Press one...", hold the first button and press the second, and give the combination a job from the menu. A combination can end in any button, FreeControl's D-pad and face buttons included. The button on its own goes on doing what it did.
- How that works: the game can treat a controller button as the Ctrl, Alt or Shift key while it is held, and out of the box the left bumper is its Ctrl. A combination is then an ordinary key binding of yours, which the game's Key Bindings screen spells CTRL-, ALT- or SHIFT- and the button, so anything that screen offers can go on one too. The game has no screen for choosing the buttons to hold, so the Combinations page has three choices for that (`/fc hold ctrl | alt | shift <BUTTON>` from chat). Pick RB as Alt, say, and LB + RB + another button is a combination of three.
- Your choice of buttons to hold is in force while FreeControl is active, and the game's own setting is put back when you log out or switch it off. A button that is held has no job of its own, and the buttons FreeControl uses itself cannot be held.
- New jobs in the menus: Target party member 1 to 4, and Ping. Ping is the game's own Ping key: a press pings, and holding it brings up the wheel.
- New: the game can be told not to bring its mouse pointer out by itself. Whatever FreeControl's mouse mode is set to, the game brings its stick pointer out when a window opens, and to aim a spell that is cast on the ground. Untick "The game may bring the pointer out" on the Mouse mode page (`/fc gamepointer off`) and it stops doing that while FreeControl is active. With Mouse mode unticked as well, nothing on the controller takes the mouse pointer, which is the setup for playing with a real mouse beside the controller. Switching Mouse mode off now says in chat that this second switch exists.
- New: "Gamepad UI enemy targeting" on the settings page (`/fc front on`). The game picks an enemy for you by where you face, and out of the box it can be one anywhere around you. Gamepad UI mode narrows that to the enemies in front of you, and with this ticked FreeControl does the same. It is off unless you tick it. What Gamepad UI mode also does, and an addon is not allowed to, is make that enemy your target the moment you attack.
- On the settings page, "Other buttons..." has moved to the bottom of the left column to make room.
- `/fc status` lists the buttons that are held for combinations and the combinations that have a job, and shows both of the game's pointer settings. If a combination does nothing for you, those are the lines to send.

## v1.7.0

- New: pages can be switched off. Untick "Pages" on the settings page, or type `/fc pages off`, and the bar stays on one page: the one picked under Page. The page selector goes, and a button you gave a page arrow does nothing. A stance or form then changes the buttons of that page, whichever it is.
- New: the page selector can be taken off the bar while the pages stay. Untick "Page selector on the bar", or type `/fc pager off`. A button you gave "next page" or "previous page" still turns the page, in a fight too.
- New: mouse mode can be switched off. Untick "Mouse mode" on the settings page, or type `/fc mouse off`, and the mouse button (Y unless you moved it) is an ordinary action slot: drop a spell, an item or a macro on it. It has an action of its own on each page. Tick it again and the button is the mouse button again, unless you gave it another job in between; what you had put on the slot is still there for next time.
- Where that slot keeps its action: the game's controller slots have no place for the four face buttons with no trigger held, so such a slot borrows the LT + RT slot of the same button on the page before. Y on page 1 is the same slot as LT + RT + Y on page 3, Y on page 2 the same as LT + RT + Y on page 1, and Y on page 3 the same as LT + RT + Y on page 2. What you put on one shows on the other.
- With mouse mode off, no button of FreeControl's brings the mouse pointer out: a bumper or paddle you gave that job does nothing, and its row on the Other buttons page says why. The game still brings out its own pointer when a window needs one, and the two click buttons you chose still click then, so RT does not turn into the left mouse button.
- Changed: a face button you turned into an action slot (X, Y, B or A with no trigger held) now has an action of its own on each of the three pages. Up to 1.6.0 pages 1 and 2 showed the same one. Only page 2 is different from before: there the button now shows what LT + RT + that button holds on page 1. What it showed on page 2 before has not gone anywhere: it is still on the same button on page 1.
- Mouse mode has a settings page of its own, under FreeControl: its switch, the two click buttons and the pointer speed. The main page keeps the switch and a button that opens the new page, which made room for the two new page settings.
- `/fc status` says whether pages are on, whether the page selector is shown, and when mouse mode is off. `/fc pages on | off`, `/fc pager on | off` and `/fc mouse on | off` do from chat what the three new tick boxes do.
- The `/fc` help still said the page arrows were in the middle of the bar, where they have not been since 1.6.0.

## v1.6.0

- Fixed: on the settings page, pointing at one of the eight "With no trigger held" buttons raised an error instead of showing its tooltip (new in 1.5.0; thanks to ichene for the report). Those tooltips are now headed by the button's name.
- The page arrows have moved out of the middle of the bar, which is yours again. They hang under the LT + RT set now, smaller, and drawn like the page indicator of the game's own action bar: a small bronze-rimmed plate with the page number on it in gold and a gold arrow at each end.
- New: a button of its own for a stance or form. Any no-trigger button (click it on the bar) and any bumper or paddle (Other buttons in the settings) can be given "Stance or form: Bear Form", "Battle Stance" and so on. It uses the game's own command for its stance bar, wears the stance's icon, is lit while you are in that stance, and is the same button on every page and in every stance. A Paladin's auras are on the game's stance bar too, so they can have buttons the same way.
- A stance or form you put on a button that changes with your stance now shows there in every stance, whichever stance you were in when you put it there. In 1.5.0 this only worked for one put there while in no stance at all, which a Warrior never is: a Warrior's stance buttons, dropped on the right set in Battle Stance, were gone in the other two. As before, a stance that has something of its own on the button shows that instead.
- The pictures on the page were drawn again with the pager where it is now.

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
