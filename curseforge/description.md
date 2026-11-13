![FreeControl: the cross hotbar, with the right-trigger set selected](https://raw.githubusercontent.com/skytruax/FreeControl/main/curseforge/gallery/01-hero.png)

## Play Forever with a controller. Keep the rest of your game.

**FreeControl gives you the best part of Forever's controller mode, the trigger-driven cross hotbar, and leaves everything else exactly the way you like it.**

Forever's built-in Gamepad UI has a great idea at its heart: hold LT, RT or both, and your D-pad and face buttons become a whole new set of abilities. It is the layout console MMO players know from Final Fantasy XIV, and it feels fantastic on a controller. The catch is that switching Gamepad UI on also takes over your targeting, your menus and your whole interface layout.

FreeControl is that hotbar on its own. The game stays in normal mode. Your targeting stays yours. Your menus stay the ones you know. Pick up the controller and play.

![The bar with no trigger held, then LT, then LT and RT, then RT: the held set grows and the others fade](https://raw.githubusercontent.com/skytruax/FreeControl/main/docs/demo.gif)

## Why you will like it

- **32 buttons under your thumbs.** Four sets of eight on the D-pad and face buttons: one with no trigger, one for LT, one for RT, one for both. The set you are holding grows and the others step back, so you always know where you are.
- **Drop anything, anywhere.** Drag spells, items and macros straight from your spellbook and bags onto any slot. Cooldowns with a countdown, item counts, range and out-of-mana colouring all show, just like a normal action bar.
- **Nothing to rebuild.** FreeControl uses the same slots as Blizzard's controller bars, so whatever you already set up in Gamepad UI mode is waiting for you. Your regular action bars are never touched.
- **One button for the world.** Interact loots the corpse next to you, talks to the NPC in front of you, opens the chest, and attacks your target when there is nothing else to do.
- **Target your way.** Bumpers, stick clicks and every button FreeControl does not use are yours. Bind them in the normal Key Bindings screen, to whatever targeting you prefer.
- **Made for combat.** Sets switch and abilities fire on the press, in the middle of a fight. The button sinks under your thumb and its cooldown starts at once.
- **Stances and forms covered.** One set can swap to different slots for each stance or form.
- **Speaks your controller.** Xbox, PlayStation and Nintendo button labels, matched to the controller you plug in.
- **Leaves no mess.** Every game setting it touches is put back when you log out or switch it off.

## Up and running in a minute

1. Leave *Options > Gamepad > Enable Gamepad UI* **off**. FreeControl stands down while that mode is on.
2. Log in with your controller connected. The bar appears above your action bars.
3. Drag your spells onto the slots. Hold LT, RT or both to reach the other sets.
4. With no trigger held, the D-pad is four more action slots, X is Interact, B is Cancel / game menu, A is Jump, and Y is left for you to bind. Click any of them on the bar to change what it does.

Type `/fc` for the settings, `/fc unlock` to drag the bar where you want it, and `/fc status` to see what the addon sees, which helps in a bug report.

![The bar with every slot empty, labelled set by set](https://raw.githubusercontent.com/skytruax/FreeControl/main/curseforge/gallery/08-controls.png)

## FreeControl, Gamepad UI mode or ConsolePort?

- **Gamepad UI mode**, built into Forever, is the game's whole controller interface: hotbar, menus, targeting and layout together. FreeControl is only the hotbar. It shows the same action slots and stands down whenever that mode is on, so you can go back and forth without setting anything up twice.
- **ConsolePort** is a complete controller interface addon, with its own bars, cursor, menus and targeting tools. If you want the whole game built around the gamepad, that is the one to look at. FreeControl is for players who want the stock interface plus a cross hotbar and nothing more. The two have not been tried together, and both bind the controller's buttons, so run one at a time.

## What it changes in your game

While it is active, FreeControl sets a few console variables, and puts your own values back at logout or when you switch it off:

- controller input is turned on, if it was off (this is not Gamepad UI mode);
- the Interact key behaviour is turned on, with the reach Gamepad UI mode uses;
- the left trigger stops standing in for Shift, which is the game's default and would keep it from registering as held.

It binds the D-pad, the face buttons and the triggers with override bindings. Those sit on top of your saved key bindings without changing them.

## Good to know

- While the game's stick-driven mouse cursor is out, the right trigger is the left mouse button. That is a game default: it clicks in menus and selects the right set in play. `/fc status` mentions it, and the readme explains how to move it.
- Spell flyouts (one slot holding a group of spells) open below the button and need the mouse to choose from. Put the individual spells on the bar instead.
- There is no vehicle or possess bar yet. Use the game's own bar for those.
- Triggers are hold-to-select. There is no tap-to-toggle yet.

## Requirements

World of Warcraft: Forever and a controller the game recognises. No libraries or other addons needed.

The pictures on this page are illustrations built from the addon's own artwork, not screenshots. The spell icons in them are Blizzard's.

## Feedback

Found a bug or have an idea? The issue tracker and the source are on GitHub: [github.com/skytruax/FreeControl](https://github.com/skytruax/FreeControl)
