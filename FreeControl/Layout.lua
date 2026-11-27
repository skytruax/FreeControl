local _, ns = ...

-- Everything that is a fixed fact about the hotbar: which sets exist, where the buttons sit,
-- which action slot each one shows, and what the controller's buttons are called.
local Layout = {}
ns.Layout = Layout

---------------------------------------------------------------------------
-- Sets
---------------------------------------------------------------------------
-- A "set" is the group of eight buttons you get for one trigger combination. The numbers match
-- Blizzard's controller bars (top, left, right, bottom), so the same slots mean the same thing.
Layout.SET_NONE, Layout.SET_LT, Layout.SET_RT, Layout.SET_BOTH = 0, 1, 2, 3
Layout.SETS = { 0, 1, 2, 3 }
Layout.SET_KEY = { [0] = "none", [1] = "lt", [2] = "rt", [3] = "both" }
Layout.SET_FROM_KEY = { none = 0, lt = 1, rt = 2, both = 3 }

---------------------------------------------------------------------------
-- Geometry, in bar units (the whole bar is scaled by the "scale" setting)
---------------------------------------------------------------------------
Layout.BUTTON_SIZE = 36
Layout.ROOT_SIZE = { 760, 236 }
Layout.SET_SIZE = { 232, 74 }

-- Centre of each set, relative to the centre of the bar.
Layout.SET_OFFSET = {
	[0] = { 0, 54 },
	[1] = { -236, 0 },
	[2] = { 236, 0 },
	[3] = { 0, -54 },
}

-- Centre of each button, relative to the centre of its set.
Layout.BUTTON_OFFSET = {
	{ -98, 0 }, { -60, 19 }, { -22, 0 }, { -60, -19 },
	{ 22, 0 }, { 60, 19 }, { 98, 0 }, { 60, -19 },
}

-- The trigger label sits in the gap between the two lower buttons of a set.
Layout.LABEL_OFFSET = { 0, -30 }
Layout.LABEL_SIZE = { 34, 17 }

-- The pager hangs under the bottom set: a small plate with the page number on it and an arrow
-- at each end, like the page indicator of the game's own action bar. The middle of the bar is
-- left free: players put things of their own there.
Layout.PAGER_SIZE = { 64, 16 } -- the plate
Layout.PAGER_ARROW = 12        -- an arrowhead, drawn on its end of the plate
Layout.PAGER_STEP = 23         -- from the middle of the plate to the middle of an arrow
Layout.PAGER_HIT = 24          -- how wide an arrow's click target is: its end of the plate
Layout.PAGER_GAP = 2           -- between the pager and what is above it

-- Where the middle of the pager is, from the middle of the bar: just under the bottom set at
-- the size that set has while it is held. The set's trigger labels reach lower than its buttons.
function Layout.GetPagerOffset()
	local lowest = Layout.LABEL_OFFSET[2] - Layout.LABEL_SIZE[2] / 2
	return 0, Layout.SET_OFFSET[Layout.SET_BOTH][2] + lowest * ns.db.activeScale - Layout.PAGER_GAP - Layout.PAGER_SIZE[2] / 2
end

function Layout.IsRound(index)
	return index > 4
end

---------------------------------------------------------------------------
-- Controller button names
---------------------------------------------------------------------------
-- WoW names face buttons by position (PAD1 bottom, PAD2 right, PAD3 left, PAD4 top), so only the
-- printed label differs between controllers.
local STYLES = {
	xbox = {
		face = { "X", "Y", "B", "A" },         -- left, top, right, bottom
		triggers = { "LT", "RT" },
		bumpers = { "LB", "RB" },
		middle = { "Back", "Start" },          -- the two small buttons in the middle, left and right
	},
	playstation = {
		face = { "Square", "Triangle", "Circle", "Cross" },
		triggers = { "L2", "R2" },
		bumpers = { "L1", "R1" },
		middle = { "Share", "Options" },
	},
	nintendo = {
		face = { "Y", "X", "A", "B" },
		triggers = { "ZL", "ZR" },
		bumpers = { "L", "R" },
		middle = { "Minus", "Plus" },
	},
}
local DPAD = { "DpadLeft", "DpadUp", "DpadRight", "DpadDown" }
local DPAD_NAME = { "D-pad Left", "D-pad Up", "D-pad Right", "D-pad Down" }

-- The client reports how the connected controller labels its buttons, the same value Blizzard's
-- own controller icons follow.
local function DetectStyle()
	if C_GamePad and C_GamePad.GetActiveDeviceID and C_GamePad.GetDeviceMappedState then
		local state = C_GamePad.GetDeviceMappedState(C_GamePad.GetActiveDeviceID())
		local labelStyle = state and state.labelStyle
		if labelStyle == "Shapes" then
			return "playstation"
		elseif labelStyle == "Reverse" then
			return "nintendo"
		end
	end
	return "xbox"
end

function Layout.GetStyleKey()
	local key = ns.db.labelStyle
	if key == "auto" then
		key = DetectStyle()
	end
	return key
end

-- Art file (without path or extension) of the glyph printed on a button.
function Layout.GetGlyph(index)
	if index <= 4 then
		return "Glyph-" .. DPAD[index]
	end
	return "Glyph-" .. STYLES[Layout.GetStyleKey()].face[index - 4]
end

-- Art file of a trigger badge; side is 1 (left trigger) or 2 (right trigger).
function Layout.GetTriggerBadge(side)
	return "Badge-" .. STYLES[Layout.GetStyleKey()].triggers[side]
end

-- Name of a button as text, e.g. "LT + X" or "D-pad Up".
function Layout.GetButtonName(set, index)
	local style = STYLES[Layout.GetStyleKey()]
	local name = index <= 4 and DPAD_NAME[index] or style.face[index - 4]
	if set == Layout.SET_LT then
		return style.triggers[1] .. " + " .. name
	elseif set == Layout.SET_RT then
		return style.triggers[2] .. " + " .. name
	elseif set == Layout.SET_BOTH then
		return style.triggers[1] .. " + " .. style.triggers[2] .. " + " .. name
	end
	return name
end

-- Name of any controller button as text, by the name the game gives the button ("PADLSTICK").
-- A key this does not know, such as a keyboard key, is shown as it is.
local FACE_POSITION = { PAD3 = 1, PAD4 = 2, PAD2 = 3, PAD1 = 4 } -- place in a style's face list
local KEY_NAME = {
	PADLSTICK = "Left stick click", PADRSTICK = "Right stick click",
	PADDLEFT = DPAD_NAME[1], PADDUP = DPAD_NAME[2], PADDRIGHT = DPAD_NAME[3], PADDDOWN = DPAD_NAME[4],
	PADPADDLE1 = "Paddle 1", PADPADDLE2 = "Paddle 2", PADPADDLE3 = "Paddle 3", PADPADDLE4 = "Paddle 4",
}

function Layout.GetKeyName(key)
	local style = STYLES[Layout.GetStyleKey()]
	if FACE_POSITION[key] then
		return style.face[FACE_POSITION[key]]
	elseif key == "PADLTRIGGER" then
		return style.triggers[1]
	elseif key == "PADRTRIGGER" then
		return style.triggers[2]
	elseif key == "PADLSHOULDER" then
		return style.bumpers[1]
	elseif key == "PADRSHOULDER" then
		return style.bumpers[2]
	elseif key == "PADBACK" then
		return style.middle[1]
	elseif key == "PADFORWARD" then
		return style.middle[2]
	end
	return KEY_NAME[key] or key
end

---------------------------------------------------------------------------
-- The controller's other buttons
---------------------------------------------------------------------------
-- FreeControl binds the D-pad, the face buttons and the two triggers. Every other button is an
-- ordinary button to the game, bound like a key on the keyboard; these are the ones nearly every
-- controller has, in the order the Other buttons page lists them.
Layout.OTHER_KEYS = {
	"PADLSHOULDER", "PADRSHOULDER", "PADLSTICK", "PADRSTICK", "PADBACK", "PADFORWARD",
	"PADPADDLE1", "PADPADDLE2", "PADPADDLE3", "PADPADDLE4",
}

-- Game commands offered for them on top of Layout.COMMANDS: { binding name, label, art file }.
-- Each has a picture of its own, if only in its colour, so a row of them can be told apart. The names
-- are the ones the Key Bindings screen uses (Blizzard_FrameXML/Bindings_Camelot.xml).
--
-- The four in Layout.PARTY_JOBS are not game commands. They step through the party: next and
-- previous from the member picked last, and the first and the last there is, each skipping the
-- places nobody is in. Bindings.lua makes a secure button for each, so they work in a fight:
-- { the name a role is saved under, label, art file, the button's name after "FreeControlParty" }.
Layout.PARTY_JOBS = {
	{ "FREECONTROL_PARTYNEXT", "Target next party member", "Role-PartyNext", "Next" },
	{ "FREECONTROL_PARTYPREV", "Target previous party member", "Role-PartyPrev", "Prev" },
	{ "FREECONTROL_PARTYFIRST", "Target first party member", "Role-PartyFirst", "First" },
	{ "FREECONTROL_PARTYLAST", "Target last party member", "Role-PartyLast", "Last" },
}

-- FreeControl's own two for the chat (the Chat folder): the keyboard that types with the sticks,
-- and the window of ready-made phrases. Like the party jobs they are not game commands:
-- Bindings.lua binds each as a click on a button of its own. Neither works in a fight.
Layout.CHAT_JOBS = {
	{ "FREECONTROL_CHATKEYBOARD", "Chat keyboard", "Role-Chat" },
	{ "FREECONTROL_PHRASES", "Quick phrases", "Role-Phrases" },
}

-- Five more of FreeControl's own, for grouping up with whoever is targeted. Like the party jobs
-- each is a secure button Bindings.lua makes, so they work in a fight:
-- { the name a role is saved under, label, art file, the button's name after "FreeControlGroup" }.
-- The first four run what a player would otherwise keep a macro for (Bindings.GROUP_MACROS); the
-- last opens the game's own menu for the target, the one a right click on its portrait opens.
Layout.GROUP_JOBS = {
	{ "FREECONTROL_INVITE", "Invite target", "Role-Invite", "Invite" },
	{ "FREECONTROL_REQUESTINVITE", "Ask to join target's group", "Role-Request", "Request" },
	{ "FREECONTROL_INVITEORREQUEST", "Invite target, or ask to join", "Role-InviteOrRequest", "InviteOrRequest" },
	{ "FREECONTROL_LEAVEPARTY", "Leave party", "Role-Leave", "Leave" },
	{ "FREECONTROL_TARGETMENU", "Target's menu (inspect, mark, ...)", "Role-Menu", "Menu" },
	-- Says yes to the game's question about a group: an invitation that came, or someone asking to
	-- join yours. An ordinary button: it presses the question's own Accept.
	{ "FREECONTROL_ACCEPTGROUP", "Accept group invite or request", "Role-Accept", "Accept" },
}

-- Three for an item the group is rolling for: Need, Greed and Pass. Not game commands either:
-- Bindings.lua makes an ordinary button for each, which answers the roll the way a click on the
-- roll's own button does (Bindings:RollOnLoot):
-- { the name a role is saved under, label, art file, the button's name after "FreeControlLoot",
--   the kind of roll as the game numbers it }.
Layout.LOOT_JOBS = {
	{ "FREECONTROL_ROLLNEED", "Loot roll: Need", "Role-Need", "Need", 1 },
	{ "FREECONTROL_ROLLGREED", "Loot roll: Greed", "Role-Greed", "Greed", 2 },
	{ "FREECONTROL_ROLLPASS", "Loot roll: Pass", "Role-Pass", "Pass", 0 },
}

Layout.MORE_JOBS = {
	{ "ASSISTTARGET", "Target your target's target", "Role-Assist" },
	{ "TARGETPARTYMEMBER1", "Target party member 1", "Role-Party1" },
	{ "TARGETPARTYMEMBER2", "Target party member 2", "Role-Party2" },
	{ "TARGETPARTYMEMBER3", "Target party member 3", "Role-Party3" },
	{ "TARGETPARTYMEMBER4", "Target party member 4", "Role-Party4" },
	Layout.PARTY_JOBS[1], Layout.PARTY_JOBS[2], Layout.PARTY_JOBS[3], Layout.PARTY_JOBS[4],
	-- The game's own Ping key (Blizzard_PingUI/Bindings.xml): a press pings what is under the
	-- pointer or in the middle of the screen, and holding it brings up the wheel of pings.
	{ "TOGGLEPINGLISTENER", "Ping (hold for the wheel)", "Role-Ping" },
	{ "TOGGLECHARACTER0", "Character", "Role-Character" },
	{ "TOGGLESPELLBOOK", "Spellbook", "Role-Spellbook" },
	{ "TOGGLETALENTS", "Talents", "Role-Talents" },
	{ "TOGGLEQUESTLOG", "Quest log", "Role-Quests" },
	{ "TOGGLESOCIAL", "Friends and guild", "Role-Social" },
	{ "DISMOUNT", "Dismount", "Role-Dismount" },
	{ "SITORSTAND", "Sit or stand", "Role-Sit" },
	Layout.CHAT_JOBS[1], Layout.CHAT_JOBS[2],
	Layout.GROUP_JOBS[1], Layout.GROUP_JOBS[2], Layout.GROUP_JOBS[3], Layout.GROUP_JOBS[4], Layout.GROUP_JOBS[5],
	Layout.GROUP_JOBS[6],
	Layout.LOOT_JOBS[1], Layout.LOOT_JOBS[2], Layout.LOOT_JOBS[3],
}

---------------------------------------------------------------------------
-- Combinations
---------------------------------------------------------------------------
-- A combination is a button pressed while one or more modifiers are held, and the game names it
-- in a key binding as it names any key with modifiers: ALT-, CTRL- and SHIFT-, in that order,
-- and then the button. "ALT-CTRL-PADDRIGHT" is D-pad Right with Alt and Ctrl held. On a
-- controller the modifiers are buttons that stand in for those keys (CVars.lua).
local MODIFIER_ORDER = { "ALT", "CTRL", "SHIFT" }
local IS_MODIFIER = { ALT = true, CTRL = true, SHIFT = true }

-- The modifiers in a key's name, as a list, and the button they are held with.
function Layout.SplitChord(key)
	local modifiers = {}
	local button = key
	while true do
		local modifier, rest = button:match("^(%u+)%-(.+)$")
		if not modifier or not IS_MODIFIER[modifier] then
			break
		end
		modifiers[#modifiers + 1] = modifier
		button = rest
	end
	return modifiers, button
end

function Layout.IsChord(key)
	return #(Layout.SplitChord(key)) > 0
end

-- A combination that ends in a controller button.
function Layout.IsPadChord(key)
	local modifiers, button = Layout.SplitChord(key)
	return #modifiers > 0 and button:find("^PAD") ~= nil
end

-- The name of `button` pressed with modifiers held; held.ALT, held.CTRL and held.SHIFT say which.
function Layout.JoinChord(held, button)
	local parts = {}
	for _, modifier in ipairs(MODIFIER_ORDER) do
		if held[modifier] then
			parts[#parts + 1] = modifier
		end
	end
	parts[#parts + 1] = button
	return table.concat(parts, "-")
end

function Layout.GetSetName(set)
	local style = STYLES[Layout.GetStyleKey()]
	if set == Layout.SET_LT then
		return style.triggers[1]
	elseif set == Layout.SET_RT then
		return style.triggers[2]
	elseif set == Layout.SET_BOTH then
		return style.triggers[1] .. " + " .. style.triggers[2]
	end
	return "No trigger"
end

---------------------------------------------------------------------------
-- Commands a no-trigger button can run instead of holding an action
---------------------------------------------------------------------------
-- { binding name as used by the Key Bindings screen, label, art file }
Layout.COMMANDS = {
	{ "INTERACTTARGET", "Interact (loot, talk, use)", "Role-Interact" },
	{ "JUMP", "Jump", "Role-Jump" },
	{ "TOGGLEGAMEMENU", "Cancel / game menu", "Role-Cancel" },
	{ "TARGETNEARESTENEMY", "Target nearest enemy", "Role-TargetEnemy" },
	{ "TARGETPREVIOUSENEMY", "Target previous enemy", "Role-TargetEnemy" },
	{ "TARGETNEARESTFRIEND", "Target nearest friend", "Role-TargetFriend" },
	{ "TARGETSELF", "Target yourself", "Role-TargetFriend" },
	{ "STARTATTACK", "Start attacking", "Role-Attack" },
	{ "TOGGLEAUTORUN", "Auto-run", "Role-Run" },
	{ "FREECONTROL_TOGGLECURSOR", "Mouse pointer on / off", "Role-Cursor" }, -- see Mouse.lua
	{ "TOGGLEWORLDMAP", "World map", "Role-Map" },
	{ "OPENALLBAGS", "Bags", "Role-Bags" },
}

-- Not a game command: the name a button's role is saved under when it is the mouse button.
-- Bindings.lua binds such a button itself; see Mouse.lua.
Layout.CURSOR_COMMAND = "FREECONTROL_TOGGLECURSOR"
Layout.CURSOR_ROLE = "cmd:" .. Layout.CURSOR_COMMAND
Layout.PAGE_ROLES = { { "FREECONTROL_NEXTPAGE", "Next page", 1 }, { "FREECONTROL_PREVPAGE", "Previous page", -1 } }
Layout.RELEASE_ROLE_COMMAND = "FREECONTROL_RELEASELAYER"

function Layout.IsCursorRole(role)
	return role == Layout.CURSOR_ROLE
end

-- What a button does: "action", "pass", "none" or "cmd:<NAME>".
--
-- A job belongs to a page: db.pageRoles[page][set][index], which is where a job given on the bar
-- or in the settings goes (Layout.SetRole). So a job put on a button on page 1 is not on that
-- button on pages 2 and 3. db.roles (Main) and db.layerRoles (the trigger layouts) are what a
-- button does on every page that says nothing else: where versions up to 1.8.0 kept the jobs,
-- and where they are kept still when the slots have no pages. A saved setup's are moved to their
-- page once (Core.lua).
--
-- `spell` asks for a form's own Main layout, which is the same on every page. `page` is the page
-- to answer for; the one being shown without it.
local function BaseRole(set, index)
	local db = ns.db
	if set == Layout.SET_NONE then
		return db.roles[index]
	end
	local roles = db.layerRoles[set]
	return roles and roles[index] or "action"
end

function Layout.GetRole(set, index, spell, page)
	local db = ns.db
	if not spell then
		local paged = db.pageRoles[page or Layout.GetPage()]
		local roles = paged and paged[set]
		local role = roles and roles[index]
		if role then
			if not db.mouseMode and Layout.IsCursorRole(role) then
				return "action"
			end
			return role
		end
	end
	if set == Layout.SET_NONE and not spell then
		return db.roles[index]
	end
	local roles = spell and db.mainFormRoles[spell] or (not spell and db.layerRoles[set])
	local role = roles and roles[index]
	if not db.mouseMode and Layout.IsCursorRole(role) then
		return "action"
	end
	return role or "action"
end

-- True when some button, on some page, is the mouse button: in what is saved, whether or not
-- mouse mode is on.
function Layout.HasCursorRole()
	local db = ns.db
	for index = 1, 8 do
		if Layout.IsCursorRole(db.roles[index]) then
			return true
		end
	end
	for _, roles in pairs(db.layerRoles) do
		for _, role in pairs(roles) do
			if Layout.IsCursorRole(role) then
				return true
			end
		end
	end
	for _, sets in pairs(db.pageRoles) do
		for _, roles in pairs(sets) do
			for _, role in pairs(roles) do
				if Layout.IsCursorRole(role) then
					return true
				end
			end
		end
	end
	return false
end

-- Gives a button its job on the page being shown, and on that page only. That goes for every
-- job there is, the mouse button and turning the page among them. Only where the slots have no
-- pages (the regular action bars) is a job for every page, there being one.
function Layout.SetRole(set, index, value)
	local db = ns.db
	local base = BaseRole(set, index)
	if Layout.GetStoredPages() == 1 then
		if set == Layout.SET_NONE then
			db.roles[index] = value
		else
			db.layerRoles[set] = db.layerRoles[set] or {}
			db.layerRoles[set][index] = value ~= "action" and value or nil
		end
		for _, paged in pairs(db.pageRoles) do
			if paged[set] then
				paged[set][index] = nil
			end
		end
		return
	end
	local page = Layout.GetPage()
	db.pageRoles[page] = db.pageRoles[page] or {}
	db.pageRoles[page][set] = db.pageRoles[page][set] or {}
	db.pageRoles[page][set][index] = value ~= base and value or nil
end

-- The classes whose stances or forms change what they can cast, so that a stance is worth
-- buttons of its own: the ones the game itself turns the action bar for.
--   Warrior  Battle, Defensive and Berserker Stance: most abilities need one of them
--   Druid    Bear, Cat and the other forms: no caster spell can be used in one
--   Rogue    Stealth: the openers work from it alone
-- The game's stance bar holds more than that. A Paladin's auras are on it, and on some clients
-- a Hunter's aspects and a Shaman's Ghost Wolf: they are buffs, every spell stays as it was, and
-- the game turns no bar for them. A Priest's Shadowform is left out as well: in Forever it turns
-- no bar, and the Priest goes on casting the same Shadow spells, without the healing ones. Those get no layout of their own; a Mage and a Warlock have
-- nothing on the stance bar at all. Every class can still give a button to an entry on the
-- stance bar ("A button of its own for a stance or form", below).
local STANCE_CLASSES = { WARRIOR = true, DRUID = true, ROGUE = true }

function Layout.HasStances()
	local _, class = UnitClass("player")
	return STANCE_CLASSES[class] or false
end

function Layout.GetFormSpell(index)
	local _, _, _, spell = GetShapeshiftFormInfo(index)
	if not ns.IsSealed(spell) and type(spell) == "number" then return spell end
end

function Layout.GetActiveMainFormSpell()
	local header = ns.Bindings.header
	return header and header:GetAttribute("fc-active-main-spell")
end

local COMMAND_BY_NAME = {}
for _, command in ipairs(Layout.COMMANDS) do
	COMMAND_BY_NAME[command[1]] = command
end
for _, command in ipairs(Layout.PAGE_ROLES) do
	COMMAND_BY_NAME[command[1]] = { command[1], command[2], command[3] > 0 and "Role-PageNext" or "Role-PagePrev" }
end
for _, command in ipairs(Layout.MORE_JOBS) do
	COMMAND_BY_NAME[command[1]] = command
end
COMMAND_BY_NAME[Layout.RELEASE_ROLE_COMMAND] = { Layout.RELEASE_ROLE_COMMAND, "Return to main layer", "Role-Release" }

-- Splits a saved role into its kind ("action", "pass" or "cmd") and, for commands, the binding name.
function Layout.ParseRole(role)
	local command = role:match("^cmd:(.+)$")
	if command then
		return "cmd", command
	end
	return role, nil
end

---------------------------------------------------------------------------
-- A button of its own for a stance or form
---------------------------------------------------------------------------
-- The game has ten commands that change to the first, the second, ... stance or form the
-- character has: the ones its own stance bar is bound through ("Special Action Button 1" to 10
-- in the Key Bindings screen; each runs StanceBar:Select). A no-trigger button, a bumper or a
-- paddle that is given one is that stance's button on every page and in every stance: nothing
-- on the bar can cover it. That goes for a Paladin's auras too, which are on the game's stance
-- bar without changing any buttons.
local FORM_COMMAND = "SHAPESHIFTBUTTON"
Layout.NUM_FORM_COMMANDS = 10

function Layout.GetFormCommand(index)
	return FORM_COMMAND .. index
end

-- The number of the stance or form a command changes to; nil for any other command.
function Layout.GetCommandForm(command)
	return tonumber(command:match("^" .. FORM_COMMAND .. "(%d+)$"))
end

-- How many stances or forms the character has.
function Layout.GetNumForms()
	return GetNumShapeshiftForms and GetShapeshiftFormInfo and GetNumShapeshiftForms() or 0
end

-- What the game says about stance or form number `index`: its name, its icon, whether the
-- character is in it and whether it can be changed to right now. Nothing for one the character
-- does not have. What the game seals in a fight comes back as nil: not known just now.
function Layout.GetFormInfo(index)
	if index > Layout.GetNumForms() then
		return nil
	end
	local texture, active, castable, spell = GetShapeshiftFormInfo(index)
	local function Known(value)
		if ns.IsSealed(value) then
			return nil
		end
		return value
	end
	spell = Known(spell)
	return spell and C_Spell.GetSpellName(spell) or ("Stance or form " .. index), Known(texture), Known(active), Known(castable)
end

-- Label and art file for a command; commands typed by hand get a generic icon and their binding name.
function Layout.GetCommandInfo(command)
	local known = COMMAND_BY_NAME[command]
	if known then
		return known[2], known[3]
	end
	local form = Layout.GetCommandForm(command)
	if form then
		local name = Layout.GetFormInfo(form)
		return name and ("Stance or form: " .. name) or ("Stance or form %d (this character has none)"):format(form), "Role-Generic"
	end
	return GetBindingName(command), "Role-Generic"
end

---------------------------------------------------------------------------
-- Abilities that come free for a moment
---------------------------------------------------------------------------
-- Most procs are marked by the game itself, and a button glows for those whatever the spell is
-- (Buttons.lua). A few abilities are different: they cannot be used at all until something has
-- happened (the target dodged, the player parried, an enemy died), and all the game does then is
-- light the button up, which is easy to miss in a fight. These are glowed for as long as they stay
-- usable after coming free.
--
-- They are matched by name, in English, because that is all that is known about them here: on a
-- client in another language nothing in this list matches and nothing glows that should not.
-- The value is true, or "unstealthed" for an ability that is always usable from stealth and
-- counts as having come free only outside it.
Layout.REACTIVE = {
	["Overpower"] = true,
	["Victory Rush"] = true,
	["Riposte"] = true,
	["Counterattack"] = true,
	["Mongoose Bite"] = true,
	["Ambush"] = "unstealthed",
}
Layout.REACTIVE_TIME = 20 -- seconds a glow may last; the game takes the ability back sooner than that

---------------------------------------------------------------------------
-- Action slots
---------------------------------------------------------------------------
-- Blizzard's Gamepad UI keeps its cross hotbar in action slots of its own, away from the regular
-- action bars. Each page lays its buttons out like this (see Blizzard_GamepadActionBars):
--
--                 top:     1-4   (5-8)          the top face buttons (5-8) are reserved for
--     left:  9-12 13-16        right: 17-20 21-24      Interact / Inspect / Back / Jump and
--                 bottom: 25-28 29-32                  have no storage
--
-- so a page holds 28 slots, there are three pages, and five stance bars of eight follow them.
local PAGE_SLOTS = 28
local NUM_PAGES = 3
local NUM_STANCE_BARS = 5
local MAIN_FORM_BLOCKS = 7
Layout.NUM_PAGES = NUM_PAGES

-- Regular action bar slots used by the "bars" source: Bottom Left, Bottom Right, Right and Left bar.
local BAR_FIRST = { [0] = 37, [1] = 61, [2] = 49, [3] = 25 }

-- What the client says about its controller slots; filled in by Layout.Prepare.
local gamepad = { first = nil, pagesValid = false, stanceValid = false }

-- Asks the client where its controller slots are and whether it accepts them. Action functions
-- raise an error for a slot that does not exist, so nothing is handed a slot before this has run.
function Layout.Prepare()
	gamepad.first, gamepad.pagesValid, gamepad.stanceValid = nil, false, false
	if not (C_GamepadUI and C_GamepadUI.GetFirstGamepadActionStorageSlotIndex and C_GamepadUI.IsValidGamepadActionStorageSlotIndex) then
		return
	end
	local first = C_GamepadUI.GetFirstGamepadActionStorageSlotIndex()
	local isValid = C_GamepadUI.IsValidGamepadActionStorageSlotIndex
	local stanceFirst = first + PAGE_SLOTS * NUM_PAGES
	gamepad.first = first
	gamepad.pagesValid = isValid(first) and isValid(stanceFirst - 1)
	gamepad.stanceValid = gamepad.pagesValid and isValid(stanceFirst) and isValid(stanceFirst + NUM_STANCE_BARS * 8 - 1)
end

function Layout.GetFirstGamepadSlot()
	return gamepad.first
end

function Layout.HasGamepadSlots()
	return gamepad.pagesValid
end

function Layout.HasStanceSlots()
	return gamepad.stanceValid
end

-- The extra blocks follow the standard controller pages and Blizzard's stance bars.
-- Keep assignments keyed by spell ID so learning a form cannot move an existing layout.
-- `choice` is the stance choice to answer for; the one in force without it.
function Layout.GetMainFormSlots(choice)
	local slots = {}
	local profile = ns.GetBarProfile()
	choice = choice or profile.stanceSet
	if choice == "none" or (choice == "custom" and not profile.stanceMain) or not gamepad.stanceValid
		or not Layout.HasStances() then
		return slots
	end
	local first = gamepad.first + PAGE_SLOTS * NUM_PAGES + NUM_STANCE_BARS * 8
	local isValid = C_GamepadUI.IsValidGamepadActionStorageSlotIndex
	local saved = ns.db.mainFormSlots
	local used = {}
	local function BlockFirst(block)
		return first + (block - 1) * 8
	end
	local function CanUseBlock(block, requireEmpty)
		local start = BlockFirst(block)
		for slot = start, start + 7 do
			if not isValid(slot) or (requireEmpty and C_ActionBar.HasAction(slot)) then
				return false
			end
		end
		return true
	end
	for spell, block in pairs(saved) do
		if type(spell) ~= "number" or type(block) ~= "number" or block < 1
			or block > MAIN_FORM_BLOCKS or block % 1 ~= 0 or used[block] then
			saved[spell] = nil
		else
			used[block] = true
		end
	end
	for index = 1, math.min(Layout.GetNumForms(), Layout.NUM_FORM_COMMANDS) do
		local spell = Layout.GetFormSpell(index)
		if spell then
			local block = saved[spell]
			for candidate = 1, MAIN_FORM_BLOCKS do
				if block then break end
				if not used[candidate] and CanUseBlock(candidate, true) then
					block = candidate
					saved[spell], used[block] = block, true
				end
			end
			if block and CanUseBlock(block, false) then
				slots[index] = BlockFirst(block)
			end
		end
	end
	return slots
end

function Layout.GetMainFormCondition()
	local parts = {}
	for form = 1, Layout.NUM_FORM_COMMANDS do
		parts[#parts + 1] = ("[form:%d] %d"):format(form, form)
	end
	parts[#parts + 1] = "0"
	return table.concat(parts, "; ")
end

-- The first and the last of the controller's slots: its three pages and, where the client has
-- them, the stance bars after those. Nothing when the client has no usable controller slots.
function Layout.GetGamepadSlotRange()
	if not gamepad.pagesValid then
		return nil
	end
	local last = gamepad.first + PAGE_SLOTS * NUM_PAGES - 1
	if gamepad.stanceValid then
		last = last + NUM_STANCE_BARS * 8
	end
	return gamepad.first, last
end

-- Every slot the bar keeps an action in with the controller's slots in use, as a list: the
-- controller's own, and the twelve the no-trigger face buttons have (FACE_SLOTS, below). Empty
-- when the client has no usable controller slots.
function Layout.GetGamepadSlots()
	local slots = {}
	local first, last = Layout.GetGamepadSlotRange()
	if not first then
		return slots
	end
	for slot = first, last do
		slots[#slots + 1] = slot
	end
	for slot = Layout.FACE_SLOTS.first, Layout.FACE_SLOTS.last do
		slots[#slots + 1] = slot
	end
	return slots
end

-- The slot source in use: the saved choice, or the regular bars when this client has no usable
-- controller slots.
function Layout.GetSlotSource()
	if ns.GetBarProfile().slotSource == "gamepad" and gamepad.pagesValid then
		return "gamepad"
	end
	return "bars"
end

-- Blizzard gives the four face buttons with no trigger held no storage among the controller's
-- slots. When the player turns one into an action slot (or switches mouse mode off, which makes
-- the mouse button one) it needs a place of its own on each page: twelve slots. They are the
-- second page of the game's main action bar, slots 13 to 24, four for each of the three pages.
-- No button of FreeControl's shares them, so nothing put on one turns up on another.
--
-- Up to 1.8.0 such a button borrowed the LT + RT slot of the same button on the page before, and
-- what was put on LT + RT + X on page 1 was on X on page 2 as well: one slot under two buttons,
-- which a player who uses both has no way round. What those buttons held is still where it was,
-- on the LT + RT buttons.
local FACE_FIRST = 13
Layout.FACE_SLOTS = { first = FACE_FIRST, last = FACE_FIRST + NUM_PAGES * 4 - 1 }

local function GamepadSlot(first, page, set, index)
	local unit = set * 8 + index
	if unit >= 5 and unit <= 8 then
		return FACE_FIRST + (page - 1) * 4 + (unit - 5)
	end
	local offset = unit - 1
	if unit > 8 then
		offset = offset - 4
	end
	return first + PAGE_SLOTS * (page - 1) + offset
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
-- The controller's slots come in three pages, as in the Gamepad UI. The regular action bars
-- have nothing of the kind: with them as the slots there is one page.
--
-- Turning the page is a setting. With it off the bar stays on the page picked in the settings,
-- as it did up to version 1.4: the slots still come in three pages, but nothing turns them.
function Layout.GetStoredPages()
	return Layout.GetSlotSource() == "gamepad" and NUM_PAGES or 1
end

-- How many pages there are to turn through: three, or one when there is nothing to turn.
function Layout.GetPageCount()
	return ns.GetBarProfile().pages and Layout.GetStoredPages() or 1
end

-- The page being shown: the saved one, or the first when the slots in use have no such page.
function Layout.GetPage()
	local page = ns.GetBarProfile().page
	return page <= Layout.GetStoredPages() and page or 1
end

-- Action slot a button shows on a page (the one being shown, if none is given), outside any stance.
function Layout.GetSlot(set, index, page)
	if Layout.GetSlotSource() == "gamepad" then
		return GamepadSlot(gamepad.first, page or Layout.GetPage(), set, index)
	end
	return BAR_FIRST[set] + index - 1
end

---------------------------------------------------------------------------
-- Stances and forms
---------------------------------------------------------------------------
-- A button that changes with the stance needs a separate place to keep its action for each
-- stance. The game has two such places, and both are used:
--
--   "pad"  the controller stance bars: eight slots for each stance, after the three pages. The
--          Gamepad UI shows the same ones.
--   "bar"  the twelve slots the regular action bar shows in that stance. Blizzard's main bar
--          turns to them by itself (Blizzard_ActionBarController sets its page to the bonus
--          bar's), so they are shared with that bar.
--
-- Up to three groups of buttons change: one trigger set kept in "pad", the other trigger set
-- kept in the first eight "bar" slots, and the D-pad with no trigger held in the last four. The
-- both-triggers set and the face buttons never change, so there is always somewhere for what is
-- needed in every form.
--
-- They change on one page only, as the game's own bars do: the regular action bar turns to a
-- stance's slots on its first page alone, and the Gamepad UI's stance bar sits on one bar of one
-- page. Every other page is the same in every stance.
local BAR_STANCE_FIRST = 73 -- the first slot of the regular action bar in stance 1
local BAR_STANCE_SLOTS = 12
Layout.NUM_STANCES = NUM_STANCE_BARS

Layout.STANCE_CHOICES = { "auto", "none", "lt", "rt", "both", "ltrt", "all", "custom" }

-- "custom" is the player's own pick of the layouts that change on the stance page, one setting
-- each: { the setting, the word for it in /fc stance custom, the set }. Main changes by the form
-- (its eight buttons, kept in the spare controller slots: Layout.GetMainFormSlots); a trigger set
-- changes by the stance bar. There is room for two trigger sets, so two of the three at most.
-- Picked this way, Main changes on the stance page alone, like the trigger sets: every other
-- page is the same in every stance.
Layout.STANCE_LAYOUTS = {
	{ "stanceMain", "main", 0 },
	{ "stanceLT", "lt", 1 },
	{ "stanceRT", "rt", 2 },
	{ "stanceBoth", "both", 3 },
}
Layout.MAX_STANCE_SETS = 2

function Layout.IsCustomStance()
	return ns.GetBarProfile().stanceSet == "custom"
end

-- Drops the last of the trigger sets picked beyond the two there is room for. `flags` is a
-- table of the four settings. Returns true when one was dropped.
function Layout.LimitStanceSets(flags)
	local count, dropped = 0, false
	for index = 2, #Layout.STANCE_LAYOUTS do
		local key = Layout.STANCE_LAYOUTS[index][1]
		if flags[key] then
			count = count + 1
			if count > Layout.MAX_STANCE_SETS then
				flags[key], dropped = false, true
			end
		end
	end
	return dropped
end

-- Classes whose forms replace everything they can do. In Cat or Bear form a Druid cannot use a
-- single caster spell, so one changing set of eight would leave the other 24 buttons dead.
local FORM_CLASSES = { DRUID = true }

function Layout.IsFormClass()
	local _, class = UnitClass("player")
	return FORM_CLASSES[class] or false
end

-- What Options > Gamepad > Stance bar says: the page its stance bar is on, and the set that bar
-- takes the place of. No set for "none" and for a top bar, whose face buttons are not slots.
local function GetGamepadOption()
	-- Enum.GamepadStanceBarOverride: 1 none, 2-4 page 1 left/right/bottom, 5-8 page 2 top/left/right/bottom,
	-- 9-12 page 3 top/left/right/bottom.
	local value = tonumber(GetCVar("GamepadStanceBarOverride"))
	if not value or value < 2 or value > 12 then
		return 1, nil
	end
	local page, bar
	if value <= 4 then
		page, bar = 1, value - 1
	else
		page, bar = math.floor((value - 5) / 4) + 2, (value - 5) % 4
	end
	return page, bar ~= 0 and bar or nil
end

-- The one page whose buttons change with the stance: the page the Gamepad options put the stance
-- bar on, which is the first unless the player moved it. With nothing to turn, it is the page
-- the bar is on: there is no other for the player to go to.
function Layout.GetStancePage()
	if Layout.GetPageCount() == 1 then
		return Layout.GetPage()
	end
	return (GetGamepadOption())
end

-- The groups of buttons that change with the stance, in the order described above. Each is
--   { set =, last =, store = "pad" | "bar", offset = }
-- where the group is buttons 1 to `last` of the set, and `offset` is how far into a stance's
-- slots of that kind it starts.
-- `choice` is the stance choice to answer for; the one in force without it.
function Layout.GetStanceGroups(choice)
	local groups = {}
	local source = Layout.GetSlotSource()
	choice = choice or ns.GetBarProfile().stanceSet
	-- With the regular action bars as the slots nothing changes unless the player asks for it:
	-- those bars have never followed the stance, and a Warrior is always in one.
	-- And nothing changes for a class that has no stances: what a Paladin has on the stance bar
	-- are auras.
	if choice == "none" or (choice == "auto" and source ~= "gamepad") or not Layout.HasStances() then
		return groups
	end
	-- Where the trigger sets keep their actions. Without the controller's stance bars (the regular
	-- action bars are the slots, or this client has none) there is room for one set only.
	local stores = (source == "gamepad" and gamepad.stanceValid) and { "pad", "bar" } or { "bar" }
	if choice == "custom" then
		local profile = ns.GetBarProfile()
		for index = 2, #Layout.STANCE_LAYOUTS do
			local entry = Layout.STANCE_LAYOUTS[index]
			local store = stores[#groups + 1]
			if profile[entry[1]] and store then
				groups[#groups + 1] = { set = entry[3], last = 8, store = store, offset = 0 }
			end
		end
		return groups
	end
	local _, optionSet = GetGamepadOption()
	local first, pair, dpad
	if choice == "auto" then
		-- What the Gamepad options say, so the bar matches what the Gamepad UI would show; and
		-- for a class that needs it, the other trigger set and the D-pad as well.
		first = optionSet
		pair = Layout.IsFormClass()
		dpad = pair
	elseif choice == "ltrt" or choice == "all" then
		first = optionSet
		pair, dpad = true, choice == "all"
	else
		first = Layout.SET_FROM_KEY[choice]
	end
	if pair and first ~= Layout.SET_LT and first ~= Layout.SET_RT then
		first = Layout.SET_RT
	end
	if first then
		groups[#groups + 1] = { set = first, last = 8, store = stores[1], offset = 0 }
	end
	if pair and stores[2] then
		groups[#groups + 1] = { set = first == Layout.SET_RT and Layout.SET_LT or Layout.SET_RT, last = 8, store = stores[2], offset = 0 }
	end
	if dpad then
		groups[#groups + 1] = { set = Layout.SET_NONE, last = 4, store = "bar", offset = 8 }
	end
	return groups
end

-- The group a button belongs to, or nil for a button that never changes.
function Layout.FindStanceGroup(groups, set, index)
	for _, group in ipairs(groups) do
		if group.set == set and index <= group.last then
			return group
		end
	end
	return nil
end

-- The first of the slots of one kind that stance (bonus bar) number `stance` has; nothing for
-- the controller's stance bars on a client without them.
function Layout.GetStanceFirst(store, stance)
	if store == "pad" then
		return gamepad.stanceValid and gamepad.first + PAGE_SLOTS * NUM_PAGES + (stance - 1) * 8 or nil
	end
	return BAR_STANCE_FIRST + (stance - 1) * BAR_STANCE_SLOTS
end

-- Slot shown by button `index` of a group while stance number `stance` is active.
function Layout.GetStanceSlot(group, stance, index)
	return Layout.GetStanceFirst(group.store, stance) + group.offset + index - 1
end

-- Every slot the bar keeps an action in, whatever the page, the stance or the form: the ones a
-- talent group has a copy of its own of (Specs.lua). The controller's slots, the blocks Main has
-- for each form, and the regular action bar's stance slots, which a trigger set can be kept in.
function Layout.GetSpecSlots()
	local slots = Layout.GetGamepadSlots()
	if #slots == 0 then
		return slots
	end
	if gamepad.stanceValid then
		local first = gamepad.first + PAGE_SLOTS * NUM_PAGES + NUM_STANCE_BARS * 8
		for slot = first, first + MAIN_FORM_BLOCKS * 8 - 1 do
			if C_GamepadUI.IsValidGamepadActionStorageSlotIndex(slot) then
				slots[#slots + 1] = slot
			end
		end
	end
	for slot = BAR_STANCE_FIRST, BAR_STANCE_FIRST + NUM_STANCE_BARS * BAR_STANCE_SLOTS - 1 do
		slots[#slots + 1] = slot
	end
	return slots
end

-- Macro conditions for the secure header's stance state (Bindings.lua): the number of the stance
-- bar that is up, 0 for none.
function Layout.GetStanceCondition()
	local parts = {}
	for stance = 1, NUM_STANCE_BARS do
		parts[#parts + 1] = ("[bonusbar:%d] %d"):format(stance, stance)
	end
	parts[#parts + 1] = "0"
	return table.concat(parts, "; ")
end

-- What changes with the stance as the four settings of "custom", whatever the choice is: the
-- player's own pick, or what a ready-made choice comes to on this character. Ticking one of the
-- four on the settings page starts from this.
function Layout.GetStanceFlags(choice)
	local profile = ns.GetBarProfile()
	local flags = {}
	choice = choice or profile.stanceSet
	if choice == "custom" then
		for _, entry in ipairs(Layout.STANCE_LAYOUTS) do
			flags[entry[1]] = profile[entry[1]] and true or false
		end
		return flags
	end
	local changing = {}
	for _, group in ipairs(Layout.GetStanceGroups(choice)) do
		changing[group.set] = group.last == 8
	end
	for _, entry in ipairs(Layout.STANCE_LAYOUTS) do
		flags[entry[1]] = changing[entry[3]] or false
	end
	flags.stanceMain = next(Layout.GetMainFormSlots(choice)) ~= nil
	return flags
end

-- Once for each saved setup. Versions up to 1.8.0 picked what changes for the player (the
-- "auto" choice, by the game's Gamepad options and the class). Such a setup is turned into the
-- player's own pick of the four layouts, ticked as it stood, so that nothing changes on the bar
-- and nothing is picked for the player from then on. The pick is of whole layouts: a D-pad that
-- changed on its own no longer does, and that is said. Needs Layout.Prepare to have run.
function Layout.AdoptStancePick()
	local profile = ns.GetBarProfile()
	if profile.stancePicked then
		return
	end
	profile.stancePicked = true
	if profile.stanceSet == "custom" then
		return
	end
	local flags = { stanceMain = profile.stanceSet ~= "none" }
	local dpad = false
	for _, group in ipairs(Layout.GetStanceGroups()) do
		for index = 2, #Layout.STANCE_LAYOUTS do
			local entry = Layout.STANCE_LAYOUTS[index]
			if entry[3] == group.set then
				flags[entry[1]] = true
			end
		end
		dpad = dpad or group.set == Layout.SET_NONE
	end
	for _, entry in ipairs(Layout.STANCE_LAYOUTS) do
		profile[entry[1]] = flags[entry[1]] or false
	end
	profile.stanceSet = "custom"
	if dpad then
		ns.Print("What changes with your stance or form is now ticked by layout (Change with stance, in the settings). The D-pad no longer changes on its own: tick Main to have all eight Main buttons change.")
	end
end

-- "RT set, LT set and the D-pad", for the settings page, chat and /fc status; nil for none.
-- `main` puts Main first: "Main, LT set and RT set".
function Layout.DescribeStanceGroups(groups, main)
	local names = {}
	if main then
		names[1] = "Main"
	end
	for _, group in ipairs(groups) do
		names[#names + 1] = group.set == Layout.SET_NONE and "the D-pad" or (Layout.GetSetName(group.set) .. " set")
	end
	if #names == 0 then
		return nil
	elseif #names == 1 then
		return names[1]
	end
	return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

-- The same with the page they change on, where there is more than one page:
-- "RT set, LT set and the D-pad, on page 1". "nothing" for none.
function Layout.DescribeStance()
	local main = Layout.IsCustomStance() and ns.GetBarProfile().stanceMain and gamepad.stanceValid and Layout.HasStances()
	local described = Layout.DescribeStanceGroups(Layout.GetStanceGroups(), main)
	if not described then
		return "nothing"
	elseif Layout.GetPageCount() > 1 then
		return ("%s, on page %d"):format(described, Layout.GetStancePage())
	end
	return described
end
