local _, ns = ...

-- The few console variables FreeControl needs while it is active. The player's own value is
-- remembered the first time one is changed and put back at logout or when FreeControl is turned
-- off, so removing the addon leaves the game exactly as it was.
local CVars = {}
ns.CVars = CVars

-- Enum.SoftTargetEnableFlags.Any: the Interact command picks a nearby target with any input device
-- (the same thing as Options > Controls > Enable Interact Key).
local SOFT_TARGET_ANY = "3"
local NO_BUTTON = "none"

-- The player's own value of a variable: what it was before we changed it, or what it is now.
local function OwnValue(name)
	local backup = ns.db.cvarBackup[name]
	if backup ~= nil then
		return backup
	end
	return GetCVar(name)
end

local function IsOurKey(button)
	if not button then
		return false
	end
	button = button:upper()
	-- A button the player gave a job on the Other buttons page (Options.lua), or bound to one of
	-- FreeControl's own commands in the game's Key Bindings screen.
	if ns.db.plainKeys[button] or ns.Bindings:IsOwnCommand(GetBindingAction(button)) then
		return true
	end
	-- A button the chat keyboard or the quick phrases window is using while it is open (LB deletes,
	-- held to go on deleting): for that long it is no stand-in either (Chat/Input.lua).
	if ns.Chat and ns.Chat:HoldsKey(button) then
		return true
	end
	for _, key in ipairs(ns.db.keys) do
		if key:upper() == button then
			return true
		end
	end
	for _, key in ipairs(ns.db.modKeys) do
		if key:upper() == button then
			return true
		end
	end
	for side = 1, 2 do
		local key = ns.Mouse:GetManagedKey(side)
		if key and key:upper() == button then
			return true
		end
	end
	return false
end

-- The client can make a controller button stand in for Shift, Ctrl or Alt, and out of the box the
-- left trigger is Shift and the left bumper is Ctrl. Held together with another button, such a
-- button makes a combination with a binding of its own (CTRL-PADDRIGHT), as the key on the
-- keyboard would. But a button used that way only reports a press of its own when it is tapped,
-- so a held trigger would never select a set, and a job given to the bumper would come late or
-- not at all. The stand-in is therefore switched off for the buttons FreeControl uses and for
-- those the player gave a job on the Other buttons page, and left alone for every other.
--
-- The player can also choose the three buttons, on the Combinations page (Options.lua): the game
-- has no screen for it. A choice is kept in db.standIns, by modifier, as a button name or "none",
-- and stands in place of the game's own setting for that modifier while FreeControl is active.
local STAND_INS = { { "GamePadEmulateShift", "Shift" }, { "GamePadEmulateCtrl", "Ctrl" }, { "GamePadEmulateAlt", "Alt" } }

-- A value of one of those settings that names a button.
local function IsButton(value)
	return value ~= nil and value ~= "" and value:upper() ~= NO_BUTTON:upper()
end

-- The button meant to stand in for a modifier, in upper case, or nil for none: the player's
-- choice, else the game's own setting unless the player chose that same button for another
-- modifier (a button is one thing at a time). Whether the button is free to be held is not
-- looked at here.
local function Intended(name, modifier)
	local db = ns.db
	local chosen = db.standIns[modifier]
	if chosen then
		return IsButton(chosen) and chosen or nil
	end
	local own = OwnValue(name)
	if not IsButton(own) then
		return nil
	end
	own = own:upper()
	for _, button in pairs(db.standIns) do -- the choices for the other modifiers: this one has none
		if button == own then
			return nil
		end
	end
	return own
end

-- What the console variable for a modifier is to be while FreeControl is active.
local function WantedStandIn(name, modifier)
	return function(db)
		local button = Intended(name, modifier)
		if db.standIns[modifier] then
			-- The player's choice: that button, unless it is not free to be held.
			return (button and not IsOurKey(button)) and button or NO_BUTTON
		end
		-- The game's own setting is left alone (nil) unless its button cannot be held: because it is
		-- one of FreeControl's or has a job, or because the player chose it for another modifier.
		local own = OwnValue(name)
		if IsOurKey(own) or (not button and IsButton(own)) then
			return NO_BUTTON
		end
		return nil
	end
end

for _, entry in ipairs(STAND_INS) do
	entry[3] = WantedStandIn(entry[1], entry[2])
end

-- The modifier key ("Shift", "Ctrl" or "Alt") this button is meant to stand in for, by the
-- player's choice or by the game's own setting, or nil; and the console variable that says so.
function CVars:GetStandIn(button)
	for _, entry in ipairs(STAND_INS) do
		if Intended(entry[1], entry[2]) == button then
			return entry[2], entry[1]
		end
	end
	return nil
end

-- Whether the game is using this button as Shift, Ctrl or Alt at this very moment, whoever set
-- that and whether or not FreeControl is active.
function CVars:IsStandInNow(button)
	for _, entry in ipairs(STAND_INS) do
		local value = GetCVar(entry[1])
		if value and value:upper() == button then
			return true
		end
	end
	return false
end

-- The button that is held as a modifier ("Shift", "Ctrl" or "Alt") while FreeControl is active:
-- the one meant for it, if it is free to be held. Nil for none.
function CVars:GetCombinationButton(modifier)
	for _, entry in ipairs(STAND_INS) do
		if entry[2] == modifier then
			local button = Intended(entry[1], entry[2])
			return (button and not IsOurKey(button)) and button or nil
		end
	end
	return nil
end

-- How fast the stick moves the mouse cursor. The client has three settings for it: the speed it
-- starts at, how quickly it picks up, and where it tops out. Multiplying all three by the same
-- amount makes the cursor that much faster or slower without changing how it handles. At 100%
-- they are left exactly as the player has them.
local function PointerSpeed(name)
	return function(db)
		local own = tonumber(OwnValue(name))
		if db.cursorSpeed == 1 or not own then
			return nil
		end
		return ("%.3f"):format(own * db.cursorSpeed)
	end
end

-- { name, function(db) returning the value wanted, or nil to leave the variable alone }
local MANAGED = {
	-- Lets the client read the controller at all. This is not Gamepad UI mode.
	{ "GamePadEnable", function(db) return db.manageGamepad and "1" or nil end },
	{ "GamePadEmulateShift", STAND_INS[1][3] },
	{ "GamePadEmulateCtrl", STAND_INS[2][3] },
	{ "GamePadEmulateAlt", STAND_INS[3][3] },
	-- The two buttons the client turns into mouse clicks while its stick pointer is out. It starts
	-- with RT and RB, and RT is a trigger here; see Mouse.lua.
	{ "GamePadCursorLeftClick", function() return ns.Mouse:GetManagedKey(1) end },
	{ "GamePadCursorRightClick", function() return ns.Mouse:GetManagedKey(2) end },
	-- With this on the client pins the pointer to the middle of the screen and the stick cannot
	-- move it. It is off unless something turned it on.
	{ "GamePadCursorCentering", function() return ns.Mouse:IsAvailable() and "0" or nil end },
	-- The game brings its stick pointer out by itself, when a window opens and to aim a spell that
	-- is cast on the ground. A player with a real mouse beside the controller can switch that off
	-- (the Mouse mode page); with FreeControl's own mouse button off as well, nothing takes the
	-- pointer from the mouse.
	{ "GamePadCursorAutoEnable", function(db) return not db.gamePointer and "0" or nil end },
	{ "GamePadCursorForTargeting", function(db) return not db.gamePointer and "0" or nil end },
	{ "GamePadCursorSpeedStart", PointerSpeed("GamePadCursorSpeedStart") },
	{ "GamePadCursorSpeedAccel", PointerSpeed("GamePadCursorSpeedAccel") },
	{ "GamePadCursorSpeedMax", PointerSpeed("GamePadCursorSpeedMax") },
	{ "SoftTargetInteract", function(db) return db.softInteract and SOFT_TARGET_ANY or nil end },
	-- The reach the Gamepad UI uses (Blizzard_Gamepad/Core.lua): in front of you, out to 20 yards,
	-- and with the interact icon on objects as well as creatures.
	{ "SoftTargetInteractArc", function(db) return db.softInteract and db.interactReach and "1" or nil end },
	{ "SoftTargetInteractRange", function(db) return db.softInteract and db.interactReach and "20" or nil end },
	{ "SoftTargetIconGameObject", function(db) return db.softInteract and db.interactReach and "1" or nil end },
	-- The enemy the game picks for you by where you face (its "soft target") can be anywhere around
	-- you unless told otherwise. Gamepad UI mode narrows that to the arc in front of you
	-- (Blizzard_Gamepad/Core.lua); this is the same setting, for those who ask for it.
	{ "SoftTargetEnemyArc", function(db) return db.frontTargeting and "1" or nil end },
}

-- Names this client does not have, kept for the status report.
CVars.missing = {}

-- Some variables are stored as "20.000000"; the same number is not a change.
local function Same(a, b)
	if a == b then
		return true
	end
	local x, y = tonumber(a), tonumber(b)
	return x ~= nil and x == y
end

local function Set(name, value)
	local current = GetCVar(name)
	if current == nil then
		CVars.missing[name] = true
		return
	end
	local db = ns.db
	if not Same(current, value) then
		if db.cvarBackup[name] == nil then
			db.cvarBackup[name] = current
		end
		SetCVar(name, value)
	end
	db.cvarApplied[name] = value
end

local function Release(name)
	local db = ns.db
	local backup, applied = db.cvarBackup[name], db.cvarApplied[name]
	db.cvarBackup[name], db.cvarApplied[name] = nil, nil
	-- If the player changed it again after we did, their newer choice stands.
	if backup ~= nil and Same(GetCVar(name), applied) then
		SetCVar(name, backup)
	end
end

function CVars:Apply()
	wipe(self.missing)
	for _, entry in ipairs(MANAGED) do
		local name, wanted = entry[1], entry[2](ns.db)
		if wanted then
			Set(name, wanted)
		else
			Release(name)
		end
	end
end

function CVars:RestoreAll()
	for _, entry in ipairs(MANAGED) do
		Release(entry[1])
	end
end

-- The player's own key bindings changed. One of them may have put a page arrow on a button the
-- game uses as a stand-in, or taken it off again, and the stand-in has to follow. This is looked
-- at once, after the client has finished with the change; nobody's bindings change in a fight.
local looking = false

local function LookAtStandIns()
	looking = false
	if not ns.IsActive() then
		return
	end
	for _, entry in ipairs(STAND_INS) do
		local name = entry[1]
		if entry[3](ns.db) ~= ns.db.cvarApplied[name] then
			ns.RunOutOfCombat("cvars", function()
				CVars:Apply()
			end)
			return
		end
	end
end

ns.On("UPDATE_BINDINGS", function()
	if looking or not ns.db or InCombatLockdown() then
		return
	end
	looking = true
	C_Timer.After(0, function()
		ns.Try(LookAtStandIns)
	end)
end)

-- For the status report: name, current value, and the player's own value where we changed it.
function CVars:Describe()
	local lines = {}
	for _, entry in ipairs(MANAGED) do
		local name = entry[1]
		local current = GetCVar(name)
		local note = ""
		if current == nil then
			note = " (not in this client)"
		elseif ns.db.cvarBackup[name] ~= nil then
			note = (" (yours: %s)"):format(ns.db.cvarBackup[name])
		end
		lines[#lines + 1] = ("%s = %s%s"):format(name, tostring(current), note)
	end
	return lines
end
