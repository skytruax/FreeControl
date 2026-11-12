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
	},
	playstation = {
		face = { "Square", "Triangle", "Circle", "Cross" },
		triggers = { "L2", "R2" },
	},
	nintendo = {
		face = { "Y", "X", "A", "B" },
		triggers = { "ZL", "ZR" },
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
	{ "FREECONTROL_TOGGLECURSOR", "Mouse cursor on / off", "Role-Cursor" },
	{ "TOGGLEWORLDMAP", "World map", "Role-Map" },
	{ "OPENALLBAGS", "Bags", "Role-Bags" },
}

local COMMAND_BY_NAME = {}
for _, command in ipairs(Layout.COMMANDS) do
	COMMAND_BY_NAME[command[1]] = command
end

-- Splits a saved role into its kind ("action", "pass" or "cmd") and, for commands, the binding name.
function Layout.ParseRole(role)
	local command = role:match("^cmd:(.+)$")
	if command then
		return "cmd", command
	end
	return role, nil
end

-- Label and art file for a command; commands typed by hand get a generic icon and their binding name.
function Layout.GetCommandInfo(command)
	local known = COMMAND_BY_NAME[command]
	if known then
		return known[2], known[3]
	end
	return GetBindingName(command), "Role-Generic"
end

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

-- The slot source in use: the saved choice, or the regular bars when this client has no usable
-- controller slots.
function Layout.GetSlotSource()
	if ns.db.slotSource == "gamepad" and gamepad.pagesValid then
		return "gamepad"
	end
	return "bars"
end

local function GamepadSlot(first, page, set, index)
	local unit = set * 8 + index
	if unit >= 5 and unit <= 8 then
		-- Blizzard gives the top face buttons no storage, so when the player turns one into an
		-- action slot it borrows the bottom-bar face slots of a page that is not being shown.
		local donor = page == NUM_PAGES and NUM_PAGES - 1 or NUM_PAGES
		return first + PAGE_SLOTS * (donor - 1) + 24 + (unit - 5)
	end
	local offset = unit - 1
	if unit > 8 then
		offset = offset - 4
	end
	return first + PAGE_SLOTS * (page - 1) + offset
end

-- Action slot shown by a button outside any stance.
function Layout.GetSlot(set, index)
	if Layout.GetSlotSource() == "gamepad" then
		return GamepadSlot(gamepad.first, ns.db.page, set, index)
	end
	return BAR_FIRST[set] + index - 1
end

-- The set that swaps to stance-specific slots, or nil. "auto" follows the choice made in
-- Options > Gamepad > Stance bar, so the bars match what the Gamepad UI would show.
function Layout.GetStanceSet()
	if Layout.GetSlotSource() ~= "gamepad" or not gamepad.stanceValid then
		return nil
	end
	local choice = ns.db.stanceSet
	if choice == "none" then
		return nil
	elseif choice ~= "auto" then
		return Layout.SET_FROM_KEY[choice]
	end
	-- Enum.GamepadStanceBarOverride: 1 none, 2-4 page 1 left/right/bottom, 5-8 page 2 top/left/right/bottom,
	-- 9-12 page 3 top/left/right/bottom. The top bar is left alone: its face buttons are not action slots.
	local value = tonumber(GetCVar("GamepadStanceBarOverride"))
	if not value or value < 2 or value > 12 then
		return nil
	end
	local page, bar
	if value <= 4 then
		page, bar = 1, value - 1
	else
		page, bar = math.floor((value - 5) / 4) + 2, (value - 5) % 4
	end
	if page ~= ns.db.page or bar == 0 then
		return nil
	end
	return bar
end

-- Slot shown by a button of the stance set while stance (bonus bar) number `stance` is active.
function Layout.GetStanceSlot(stance, index)
	return gamepad.first + PAGE_SLOTS * NUM_PAGES + (stance - 1) * 8 + index - 1
end

-- Macro-condition string for RegisterAttributeDriver: the stance slots, then the normal slot.
function Layout.GetStanceDriver(set, index)
	local parts = {}
	for stance = 1, NUM_STANCE_BARS do
		parts[#parts + 1] = ("[bonusbar:%d] %d"):format(stance, Layout.GetStanceSlot(stance, index))
	end
	parts[#parts + 1] = tostring(Layout.GetSlot(set, index))
	return table.concat(parts, "; ")
end
