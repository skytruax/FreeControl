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
-- left trigger is Shift. A button used that way only reports a press when it is tapped, so a held
-- trigger would never select a set. The stand-in is switched off for buttons FreeControl uses and
-- left alone for every other button.
local function WithoutStandIn(name)
	return function()
		return IsOurKey(OwnValue(name)) and NO_BUTTON or nil
	end
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
	{ "GamePadEmulateShift", WithoutStandIn("GamePadEmulateShift") },
	{ "GamePadEmulateCtrl", WithoutStandIn("GamePadEmulateCtrl") },
	{ "GamePadEmulateAlt", WithoutStandIn("GamePadEmulateAlt") },
	-- The two buttons the client turns into mouse clicks while its stick pointer is out. It starts
	-- with RT and RB, and RT is a trigger here; see Mouse.lua.
	{ "GamePadCursorLeftClick", function() return ns.Mouse:GetManagedKey(1) end },
	{ "GamePadCursorRightClick", function() return ns.Mouse:GetManagedKey(2) end },
	-- With this on the client pins the pointer to the middle of the screen and the stick cannot
	-- move it. It is off unless something turned it on.
	{ "GamePadCursorCentering", function() return ns.Mouse:IsAvailable() and "0" or nil end },
	{ "GamePadCursorSpeedStart", PointerSpeed("GamePadCursorSpeedStart") },
	{ "GamePadCursorSpeedAccel", PointerSpeed("GamePadCursorSpeedAccel") },
	{ "GamePadCursorSpeedMax", PointerSpeed("GamePadCursorSpeedMax") },
	{ "SoftTargetInteract", function(db) return db.softInteract and SOFT_TARGET_ANY or nil end },
	-- The reach the Gamepad UI uses (Blizzard_Gamepad/Core.lua): in front of you, out to 20 yards,
	-- and with the interact icon on objects as well as creatures.
	{ "SoftTargetInteractArc", function(db) return db.softInteract and db.interactReach and "1" or nil end },
	{ "SoftTargetInteractRange", function(db) return db.softInteract and db.interactReach and "20" or nil end },
	{ "SoftTargetIconGameObject", function(db) return db.softInteract and db.interactReach and "1" or nil end },
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
