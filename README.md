<p align="center">
  <img src="docs/banner.png" alt="FreeControl: four sets of eight buttons, with the right-trigger set selected" width="100%">
</p>

<h1 align="center">FreeControl</h1>

<p align="center">
  <b>The controller cross hotbar for World of Warcraft: Forever, in the normal interface.</b><br>
  Hold LT, RT or both for 32 buttons. Gamepad UI mode stays off, and your targeting, menus and layout stay yours.
</p>

<p align="center">
  <a href="https://github.com/skytruax/FreeControl/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/skytruax/FreeControl?label=release&color=d9a441"></a>
  <a href="https://www.curseforge.com/projects/1800965"><img alt="CurseForge downloads" src="https://img.shields.io/curseforge/dt/1800965?label=CurseForge&color=f16436"></a>
  <a href="https://github.com/skytruax/FreeControl/actions/workflows/tests.yml"><img alt="Tests" src="https://github.com/skytruax/FreeControl/actions/workflows/tests.yml/badge.svg"></a>
  <img alt="World of Warcraft: Forever 1.60.1" src="https://img.shields.io/badge/WoW%20Forever-1.60.1-3b82c4">
  <a href="LICENSE"><img alt="Licence: MIT" src="https://img.shields.io/badge/licence-MIT-3fa55b"></a>
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#how-it-plays">How it plays</a> ·
  <a href="#settings">Settings</a> ·
  <a href="#how-it-compares">How it compares</a> ·
  <a href="#developing">Developing</a>
</p>

---

Forever's built-in Gamepad UI has a great idea at its heart: hold a trigger, and the D-pad and face
buttons become a new set of abilities. It is the layout console MMO players know from Final Fantasy
XIV. Switching that mode on also takes over your targeting, your menus and your interface layout.

**FreeControl is that hotbar on its own.** The game stays in its normal mode, and you pick up the
controller and play.

<p align="center">
  <img src="docs/demo.gif" alt="The bar with no trigger held, then LT, then LT and RT, then RT. The held set grows and the others fade." width="900">
</p>

## What you get

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="curseforge/gallery/02-sets.png" alt="The four sets: no trigger, LT, RT, and LT with RT">
      <b>32 buttons under your thumbs.</b> Four sets of eight on the D-pad and face buttons: no
      trigger, LT, RT, and both. The set you are holding grows, and the others step back.
    </td>
    <td width="50%" valign="top">
      <img src="curseforge/gallery/03-drop.png" alt="A spell being dragged onto an empty slot of the bar">
      <b>Drop anything, anywhere.</b> Spells, items and macros go on any slot by drag and drop, and
      show cooldowns with a countdown, counts and range like a normal action bar.
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <img src="curseforge/gallery/04-interact.png" alt="The Interact button: loot, talk, open, attack">
      <b>One button for the world.</b> Interact loots the corpse next to you, talks to the NPC in
      front of you, opens the chest, and attacks your target when nothing else is in reach.
    </td>
    <td width="50%" valign="top">
      <img src="curseforge/gallery/05-normal-mode.png" alt="A sketch of the normal interface with the FreeControl bar as the one thing added">
      <b>Everything else stays yours.</b> Bumpers and stick clicks are free for whatever targeting
      you like, the menus are the ones you know, and your action bars are not rearranged.
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <img src="curseforge/gallery/06-combat.png" alt="Slots showing a cooldown, out of range, not enough mana, not usable, an item count and an action in progress">
      <b>Made for combat.</b> Sets switch in the middle of a fight, the button sinks under your
      thumb, and its cooldown shows the moment it starts. The bar follows your stance or form: one
      set for most classes, two sets and the D-pad for a Druid.
    </td>
    <td width="50%" valign="top">
      <img src="curseforge/gallery/07-controllers.png" alt="The same set with Xbox, PlayStation and Nintendo labels">
      <b>Speaks your controller.</b> Xbox, PlayStation and Nintendo labels, matched to the pad you
      plug in or picked in the settings.
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <img src="curseforge/gallery/09-mouse-mode.png" alt="Mouse mode: Y brings the pointer out, the left stick click is the left mouse button and the right stick click the right">
      <b>A mouse on your sticks.</b> Press Y and the right stick steers the pointer. Click the left
      stick to left-click and drag, the right stick to right-click. Move or jump and it is gone.
    </td>
    <td width="50%" valign="top">
      <img src="curseforge/gallery/08-controls.png" alt="The empty bar with each set labelled">
      <b>Yours to rearrange.</b> Every no-trigger button can be an action slot, a command or your
      own key binding, and the settings page covers the rest.
    </td>
  </tr>
</table>

<sub>The pictures on this page are illustrations, not screenshots, drawn by <code>tools/make_listing.py</code>
from the addon's own textures and layout numbers. The spell icons in them are Blizzard's, and the
title lettering is LifeCraft, a typeface by Eliot Truelove.</sub>

## Install

**With the CurseForge app:** search for FreeControl, or start from its
[CurseForge page](https://www.curseforge.com/projects/1800965). It installs and updates there like
any other addon.

**By hand**

1. Download the zip from the [latest release](https://github.com/skytruax/FreeControl/releases/latest).
2. Unzip it into `World of Warcraft\_forever_\Interface\AddOns\`, so that you end up with
   `...\AddOns\FreeControl\FreeControl.toc`.
3. Enable FreeControl on the character screen.

Leave **Options > Gamepad > Enable Gamepad UI** off. FreeControl stands down while that mode is on,
because Blizzard's bar would be bound to the same buttons.

## How it plays

| Hold | You get |
| --- | --- |
| nothing | D-pad: four action slots. X: Interact. Y: mouse pointer on / off. B: Cancel / game menu. A: Jump. |
| LT | eight action slots (left set) |
| RT | eight action slots (right set) |
| LT + RT | eight action slots (bottom set) |

- **Filling slots:** drag spells, items and macros from the spellbook or bags onto a slot. As on
  the regular action bars, dragging one *off* a slot needs Shift while the action bars are locked.
- **Same slots as the Gamepad UI:** the slots are the ones Blizzard's controller bars use, which
  are separate from your normal action bars. Anything you already set up in Gamepad UI mode is
  there when you log in, and your regular bars are left alone (the one exception is under
  *Stances and forms* below).
- **Interact:** X runs the game's Interact command with "Enable Interact Key" behaviour switched
  on, so it loots the corpse next to you, talks to the NPC in front of you or opens the chest, and
  attacks your target when there is nothing to interact with.
- **Mouse mode:** press Y, the button that wears FreeControl's mascot (a little black dog that is
  half chihuahua, half beetle), and the right stick steers the mouse pointer. Click the left stick for
  the left mouse button (hold it to drag a spell onto the bar) and the right stick for the right
  one. Press Y again and the pointer goes away; the game also puts it away when you jump. The Y
  button on the bar is lit while it is out. FreeControl binds Y itself, the way it binds
  Interact: there is nothing to set up in the Key Bindings screen. Both click buttons and the
  pointer's speed can be changed on the settings page. To have Y do something else, click it on
  the bar; any other no-trigger button can be the mouse button instead (choose *Mouse pointer
  on / off*).
- **Stances and forms:** buttons change to different slots when you change stance or form, so
  each one has its own abilities. For most classes that is one set (the right-trigger set,
  unless **Options > Gamepad > Stance bar** names another). A Druid cannot use a single caster
  spell in Cat or Bear form, so for a Druid the right set, the left set and the D-pad all
  change, and the both-triggers set and the face buttons stay the same in every form: that is
  where shapeshifts, a mount or a trinket go. The left set and the D-pad show the slots of the
  game's own action bar for that form, so a bar you already set up there is waiting for you.
  *Stance sets* on the settings page offers the same to any class.
- **Targeting and everything else:** bind the bumpers and stick clicks to whatever you like in
  **Options > Key Bindings**; controller buttons can be bound there like keys. The stick clicks
  keep those bindings except while the mouse pointer is out.
- **Changing the no-trigger buttons:** click one on the bar, or use the settings page. Each can be
  an action slot, a command (Jump, Interact, Cancel, Target nearest enemy or friend, Auto-run,
  World map, Bags, ...) or left to your own key binding.

<details>
<summary><b>Three game defaults worth knowing when you set up the rest of your buttons</b></summary>

- **The game's own mouse-click buttons are RT and RB** (`GamePadCursorLeftClick` and
  `GamePadCursorRightClick`). RT is a hotbar trigger, so while it is active FreeControl points
  those two settings at the stick clicks instead, and puts yours back when you log out. To keep
  the game's own choice for one of them, pick *Leave to the game* on the settings page.
- **LB stands in for Ctrl out of the box** (`GamePadEmulateCtrl`). That lets you bind Ctrl
  combinations such as LB + D-pad in Key Bindings, but a button used that way only fires its own
  binding on a quick tap. To use LB as an ordinary button: `/console GamePadEmulateCtrl none`.
- **LT stands in for Shift out of the box.** FreeControl switches that off for the buttons it
  uses while it is active, because a trigger used that way would not register as held.

</details>

## Settings

`/fc` opens the page (also under **Options > AddOns > FreeControl**).

| Command | |
| --- | --- |
| `/fc on`, `/fc off` | Switch FreeControl on or off. Off hands every button back to your own bindings. |
| `/fc unlock`, `/fc lock` | Show or hide the handle for dragging the bar. |
| `/fc scale 1.2` | Size of the bar (0.5 to 2). |
| `/fc reset` | Put the bar back where it started. |
| `/fc page 2` | Show another of Blizzard's three controller-bar pages. |
| `/fc slots bars` | Use the regular Left / Bottom Left / Bottom Right / Right action bar slots instead (`gamepad` to go back). |
| `/fc numbers off` | Hide the countdown numbers on slots that are on cooldown (`on` to show them again). |
| `/fc stance all` | What changes with your stance or form: `auto`, `none`, `lt`, `rt`, `both`, `ltrt` (both trigger sets) or `all` (both and the D-pad). |
| `/fc mouse` | Bring the mouse pointer out or put it away, like the Y button. |
| `/fc click left PADLSHOULDER` | Use another button as the left (`left`) or right (`right`) mouse click while the pointer is out. `game` leaves that click to the game's own setting. |
| `/fc pointer 150` | How fast the stick moves the mouse pointer, in percent (50 to 300). |
| `/fc key lt PADLSHOULDER` | Use another button as a trigger (`lt`, `rt`) or for a slot (`1`-`8`). Keyboard keys work too, for Steam Input layouts that send keys. |
| `/fc status` | What FreeControl sees: controller, slots, keys, anything that would get in the way, and any error it ran into. Include this in bug reports. |
| `/fc trace` | Records what the game reports about the next abilities you use, for twenty seconds. Type it again to see the result in a box you can copy from. For reports about cooldowns. |

Other settings on the page: how much the held set grows, how far the others fade, button labels
(Xbox, PlayStation, Nintendo, or matched to your controller), cooldown numbers, what changes
with your stance or form (*Stance sets*: automatic unless you choose otherwise), and a **Mouse
mode** section with the two click buttons and the pointer speed.

## What it changes, and puts back

While active, FreeControl sets a few console variables and restores your own values at logout or
when you switch it off:

| Variable | Why |
| --- | --- |
| `GamePadEnable = 1` | Lets the game read the controller. This is controller *input*, not Gamepad UI mode. Forever ships with it on, so this usually changes nothing. |
| `GamePadEmulateShift` / `Ctrl` / `Alt = none` | Only where one of them names a button FreeControl uses (by default: LT as Shift). |
| `GamePadCursorLeftClick`, `GamePadCursorRightClick` | The two buttons that click while the mouse pointer is out: the stick clicks unless you choose others. |
| `GamePadCursorCentering = 0` | With it on, the game pins the mouse pointer to the middle of the screen. It is off unless something turned it on. |
| `GamePadCursorSpeedStart`, `...Accel`, `...Max` | Only when you change the pointer speed: all three are scaled together from your own values. |
| `SoftTargetInteract = 3` | The Interact command picks nearby things by itself (Options > Controls > Enable Interact Key). |
| `SoftTargetInteractArc = 1`, `SoftTargetInteractRange = 20`, `SoftTargetIconGameObject = 1` | The reach Gamepad UI mode uses for Interact. |

The first and the Interact ones have checkboxes on the settings page. FreeControl binds the D-pad,
face buttons and triggers with *override* bindings, which sit on top of your saved key bindings
without changing them.

## How it compares

- **Blizzard's Gamepad UI mode** is the game's whole controller interface: hotbar, menus,
  targeting and layout together. FreeControl is only the hotbar. It shows the same action slots
  and stands down whenever that mode is on, so you can go back and forth without setting anything
  up twice.
- **[ConsolePort](https://github.com/seblindfors/ConsolePort)** is a complete controller interface
  addon, with its own bars, cursor, menus and targeting tools. If you want the whole game built
  around the pad, that is the one to look at. FreeControl is for players who want the stock
  interface plus a cross hotbar and nothing more. The two have not been tried together, and both
  bind the controller's buttons, so run one at a time.

## Known limits

- Spell flyouts (a slot holding a group of spells) open below the button and need the mouse
  pointer to pick from. Put the individual spells on the bar instead.
- Mouse mode clicks windows through the game's own controller mouse, which needs a plain button:
  a trigger combination cannot be a click button.
- A second changing set and the D-pad keep their stance actions in the slots of the game's own
  action bar for that stance, so what you drop on them in a form also shows on that bar. The
  rest of your regular action bars is never touched.
- Stances and forms change the bar only with the controller-bar slots, not with `/fc slots bars`.
- No vehicle or possess bar yet: use the game's own bar for those.
- Triggers are hold-to-select; there is no tap-to-toggle.
- Hold-to-cast ("press and hold casting") is a client feature reserved for Blizzard's own bars.

Found something else? [Open an issue](https://github.com/skytruax/FreeControl/issues) and paste
what `/fc status` prints.

## Developing

The addon is the [FreeControl/](FreeControl/) folder; everything else in the repository is
tooling. `Layout.lua` holds the fixed facts (sets, geometry, which action slot each button shows),
`Buttons.lua` the buttons, `Bars.lua` the frames around them, and `Bindings.lua` the secure header
that rebinds the eight slot keys when a trigger is pressed, which is what lets the sets switch in
combat. Each file's header comment explains its part.

What keeps the bar feeling immediate:

- The keys always act on the press (`useOnKeyDown`), as Blizzard's own controller buttons do.
- Cooldowns are drawn without being read. In combat the game seals a cooldown's start and length
  from addons ("secret values"), and a cooldown frame refuses sealed numbers from addon code with
  an error. So the bar asks only whether a cooldown is running (`isActive`, which is never sealed)
  and hands the frame the game's duration object (`C_ActionBar.GetActionCooldownDuration`,
  `Cooldown:SetCooldownFromDurationObject`). The frame draws the sweep and the countdown itself.
- Cooldowns follow `ACTIONBAR_UPDATE_COOLDOWN`, `SPELL_UPDATE_COOLDOWN` and `BAG_UPDATE_COOLDOWN`.
  Nothing is polled.

Mouse mode ([Mouse.lua](FreeControl/Mouse.lua)) is the game's own stick pointer with a way to
click. The game keeps two things apart: whether a stick steers the pointer (`SetGamePadCursorControl`)
and whether the controller is steering the camera (`SetGamePadFreeLook`), during which the pointer
is hidden. Version 1.2.0 asked for the first without ending the second, and a player pressing the
button in the middle of play saw nothing. The pointer is now brought out by ending camera mode
first, the order ConsolePort uses, and `/fc status` prints what the game says about both, how
often the button was pressed and what came of it.

The game treats a mouse button as two things: a click on a window comes from the two buttons named
by `GamePadCursorLeftClick` and `GamePadCursorRightClick`, and a click on the world goes through
key bindings to the commands the real mouse buttons run. FreeControl sets the first pair and, while
the pointer is out, binds the same buttons to the second, from the secure header so that it works
in a fight. That two-part behaviour is how ConsolePort describes the client to its users. None of
mouse mode can be tried without the game, so treat it as the least proven part of the addon.

Stances ([Layout.lua](FreeControl/Layout.lua)) are state drivers on the buttons' `action`
attribute, one `[bonusbar:N]` clause per stance, so they switch in a fight. A changing button
needs somewhere to keep its action for each stance, and the game has two such places: the
controller stance bars (eight slots per stance, the ones the Gamepad UI shows) and the twelve
slots its regular action bar turns to in that stance (73 to 132). The first changing set uses the
former; a second set and the D-pad use the latter. `/fc status` compares both with what the game
reports for the stance you are in.

An error while drawing the bar is never silent: it goes to the game's error handler as usual, the
first one is also said in chat, and `/fc status` lists them. The game hides addon errors by
default, which is how the bar went on passing sealed numbers to its sweeps up to version 1.1.1.
[LibActionButton](https://github.com/Nevcairiel/LibActionButton-1.0), the button library behind
Bartender4 and ConsolePort, draws cooldowns from duration objects on this client; reading how it
does that is what pointed to the cause.

    python3 tools/make_art.py        # redraw FreeControl/Art/*.tga      (Pillow, numpy, cairosvg or Inkscape)
    python3 tools/preview.py         # docs/preview.png: the bar as the addon lays it out
    python3 tools/make_listing.py    # the README and CurseForge pictures (uses the Inter font if installed)

The mascot on the mouse button is drawn by hand as an SVG, `tools/art/chihuahua-beetle.svg`;
`make_art.py` sets it into the button's ring, which is what needs cairosvg or Inkscape.

The pictures show a Rogue's spell icons. `tools/game_icons.py` downloads those from a public mirror
of the game's interface art into a git-ignored folder the first time they are needed; add
`--placeholders` to draw stand-ins instead and download nothing.

There are two test suites, and neither needs the game. The addon has also been played in the
Forever 1.60.1 client.

**Mock client** (fast, 118 scenarios, runs on every push):

    pip install lupa
    python3 tools/tests/run.py       # add --globals to list every client API the addon touches

It loads the addon into Lua 5.1 against `tools/tests/wowmock.lua`, a strict stand-in for the
client set to a fresh Forever install's defaults: protected frames refuse protected calls in
combat, secure snippets run in a restricted environment, a button standing in for Shift does not
report being held, key presses travel through override bindings to button clicks, in combat
cooldown numbers come back sealed and are refused by cooldown frames, using the controller puts
the client in camera mode where the pointer stays hidden until that is ended, and while the stick
pointer is out its two click buttons become mouse clicks. It is a model, so a pass shows the addon
is consistent with that model, not that the game agrees.

**Simulator** (Blizzard's real interface code, 29 tests, about six seconds):

    tools/sim/lab/build-image.sh     # once: fetches the simulator (about 180 MB) and builds its image
    tools/sim/run.sh

<details>
<summary>What the simulator run covers, and what it cannot</summary>

This loads FreeControl next to all 272 of Blizzard's Forever interface addons (build
1.60.1.70707) in [wow-ui-sim](https://github.com/Osso/wow-ui-sim), inside throw-away Docker
containers with no network. The secure templates, the restricted environment, the state drivers
and the settings panel are Blizzard's own Lua there, and the simulator models combat lockdown and
taint, so it checks things the mock cannot: that the buttons really end up with Blizzard's secure
click handler, that the trigger snippets are accepted and can rebind keys in combat, that a key
press reaches `UseAction` untainted, and that nothing is refused along the way. It also compares
every API, console variable and event the addon names against the Forever client's own lists.
`docs/sim-screenshot.png` is the bar as that run draws it; the simulator has no game art, so
filled slots are blank there.

What it cannot show: it implements about half of the client's API, does not seal anything in
combat, has no stick pointer of its own (the tests stand in for it), has no real key or controller
input (the tests click the bound button from a secure call stack instead), has no controller-slot validity check (so FreeControl falls back to the regular
bar slots there unless a test stands in for it), and never evaluates stance conditions as true.
`tools/sim/lab/run-sim.sh --help` lists its options; `tools/sim/tests/` holds the tests and the
screenshot scenario.

[UIForever](https://uiforever.com/) is a hosted alternative: a browser simulator for Forever that
you drop an AddOns folder into. Its site says the files stay in the browser; it was not tried here.

</details>

**Releasing:** pushing a tag such as `v1.0.1` runs `.github/workflows/release.yml`. The
[BigWigs packager](https://github.com/BigWigsMods/packager) builds the zip, attaches it to a
GitHub release with `CHANGELOG.md` as the notes, and uploads it to CurseForge once the project id
is in `FreeControl.toc`. The listing text, form fields and pictures live in [curseforge/](curseforge/).

## Licence and credits

FreeControl is released under the [MIT licence](LICENSE). One file is the exception:
`tools/sim/lab/image/Dockerfile` is adapted from [wow-ui-sim](https://github.com/Osso/wow-ui-sim)
and stays under the GPL 3.0, whose text sits next to it. It is test tooling and is not part of the
addon you install.

The addon's artwork is drawn by the scripts in `tools/`, and the addon ships no Blizzard art. The
spell icons that appear in the pictures are Blizzard Entertainment's, shown the way any screenshot
of the game shows them; they are not part of the addon and are not covered by the MIT licence.
World of Warcraft is a trademark of Blizzard Entertainment. FreeControl is a fan-made addon and is
not affiliated with or endorsed by Blizzard.
