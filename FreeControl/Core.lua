local ADDON, ns = ...

-- Exposed for /run debugging and for Bindings.xml. Blizzard code never reads it.
_G.FreeControl = ns

ns.name = ADDON
ns.version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "dev"
ns.ART = "Interface\\AddOns\\" .. ADDON .. "\\Art\\"

---------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------
-- Slot order everywhere in this addon (same as Blizzard's controller bars):
--        2            6
--     1     3      5     7        1-4 = D-pad left/up/right/down
--        4            8           5-8 = face left/top/right/bottom
local DEFAULTS = {
	enabled = true,
	locked = true,
	scale = 1,
	point = { 0, 270 },    -- centre of the bar, measured from the bottom-centre of the screen
	activeScale = 1.2,     -- the set you are holding grows by this much
	inactiveAlpha = 0.8,   -- the other sets fade to this
	cooldownNumbers = true, -- count down the seconds left on a slot that is on cooldown
	labelStyle = "auto",   -- auto | xbox | playstation | nintendo
	slotSource = "gamepad", -- gamepad (Blizzard's controller-bar slots) | bars (regular action bar slots)
	page = 1,              -- which of Blizzard's three controller-bar pages to show (gamepad source only)
	stanceSet = "auto",    -- auto | none | lt | rt | both: the set that swaps with your stance or form
	manageGamepad = true,  -- turn controller input (GamePadEnable) on while FreeControl is active
	softInteract = true,   -- make the Interact command pick nearby loot, NPCs and objects by itself
	interactReach = true,  -- use the Gamepad UI's wider interact arc and range
	keys = { "PADDLEFT", "PADDUP", "PADDRIGHT", "PADDDOWN", "PAD3", "PAD4", "PAD2", "PAD1" },
	modKeys = { "PADLTRIGGER", "PADRTRIGGER" },
	-- What the eight buttons do while no trigger is held:
	--   "action"      an action slot you can drop things into
	--   "pass"        FreeControl leaves the button to your own key binding
	--   "cmd:<NAME>"  run a game command (the names used by the Key Bindings screen)
	roles = { "action", "action", "action", "action", "cmd:INTERACTTARGET", "pass", "cmd:TOGGLEGAMEMENU", "cmd:JUMP" },
	cvarBackup = {},       -- the player's own value of every console variable we changed
	cvarApplied = {},      -- the value we changed it to
	introShown = false,
}
ns.DEFAULTS = DEFAULTS

local function CopyDefaults(dst, src)
	for key, value in pairs(src) do
		if type(value) == "table" then
			if type(dst[key]) ~= "table" then
				dst[key] = {}
			end
			CopyDefaults(dst[key], value)
		elseif dst[key] == nil then
			dst[key] = value
		end
	end
	return dst
end

local function IsOneOf(value, ...)
	for i = 1, select("#", ...) do
		if value == select(i, ...) then
			return true
		end
	end
	return false
end
ns.IsOneOf = IsOneOf

-- Saved variables are plain text the player can edit, and they outlive versions of this addon,
-- so anything out of range goes back to its default instead of breaking the bars later.
local function Sanitize(db)
	local function Reset(key)
		local default = DEFAULTS[key]
		db[key] = type(default) == "table" and CopyTable(default) or default
	end
	if type(db.scale) ~= "number" or db.scale < 0.4 or db.scale > 2.5 then Reset("scale") end
	if type(db.activeScale) ~= "number" or db.activeScale < 1 or db.activeScale > 1.6 then Reset("activeScale") end
	if type(db.inactiveAlpha) ~= "number" or db.inactiveAlpha < 0.2 or db.inactiveAlpha > 1 then Reset("inactiveAlpha") end
	if not IsOneOf(db.page, 1, 2, 3) then Reset("page") end
	if not IsOneOf(db.labelStyle, "auto", "xbox", "playstation", "nintendo") then Reset("labelStyle") end
	if not IsOneOf(db.slotSource, "gamepad", "bars") then Reset("slotSource") end
	if not IsOneOf(db.stanceSet, "auto", "none", "lt", "rt", "both") then Reset("stanceSet") end
	if type(db.point[1]) ~= "number" or type(db.point[2]) ~= "number" then
		Reset("point")
	end
	for i = 1, 8 do
		if type(db.keys[i]) ~= "string" or db.keys[i] == "" then db.keys[i] = DEFAULTS.keys[i] end
		local role = db.roles[i]
		if type(role) ~= "string" or not (role == "action" or role == "pass" or role:match("^cmd:[%w_]+$")) then
			db.roles[i] = DEFAULTS.roles[i]
		end
	end
	for i = 1, 2 do
		if type(db.modKeys[i]) ~= "string" or db.modKeys[i] == "" then db.modKeys[i] = DEFAULTS.modKeys[i] end
	end
end

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------
local PREFIX = "|cff5fd7ffFreeControl|r: "
function ns.Print(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	print(PREFIX .. table.concat(parts, " "))
end

---------------------------------------------------------------------------
-- Events: modules register handlers here, Core owns the single event frame
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		eventFrame:RegisterEvent(event)
	end
	table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event]) do
		fn(event, ...)
	end
end)

---------------------------------------------------------------------------
-- Combat: protected frames and bindings can only be changed out of combat
---------------------------------------------------------------------------
local pending, order = {}, {}

-- Runs fn now, or as soon as combat ends. A later call with the same key replaces the earlier one.
-- Returns true when it ran right away.
function ns.RunOutOfCombat(key, fn)
	if InCombatLockdown() then
		if not pending[key] then
			order[#order + 1] = key
		end
		pending[key] = fn
		return false
	end
	fn()
	return true
end

ns.On("PLAYER_REGEN_ENABLED", function()
	local keys = order
	order = {}
	for _, key in ipairs(keys) do
		local fn = pending[key]
		pending[key] = nil
		fn()
	end
end)

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
-- Blizzard's own Gamepad UI ("Enable Gamepad UI" in Options > Gamepad) has its own cross hotbar and
-- rebinds the same buttons. FreeControl is for the normal interface, so it stands down while that is on.
-- Changing that option reloads the UI, so checking once per load is enough.
function ns.IsGamepadUI()
	return C_InputInterfaceStyle ~= nil
		and Enum.InputDeviceInterfaceType ~= nil
		and C_InputInterfaceStyle.GetCurrentStyle() == Enum.InputDeviceInterfaceType.Gamepad
end

function ns.IsActive()
	return ns.db.enabled and not ns.IsGamepadUI()
end

local built = false

-- Applies every setting. Out of combat only; use ns.RequestRefresh from anywhere else.
function ns.Refresh()
	if ns.IsActive() then
		if not built then
			ns.Bars:Create()
			ns.Buttons:Create()
			ns.Bindings:Create()
			built = true
		end
		ns.CVars:Apply()
		ns.Buttons:Assign()
		ns.Bars:Apply()
		ns.Bindings:Apply()
	else
		if built then
			ns.Bindings:Clear()
			ns.Buttons:Release()
			ns.Bars:Hide()
		end
		ns.CVars:RestoreAll()
	end
	if ns.Options then
		ns.Options:Sync()
	end
end

-- Returns true when the change was applied right away, false when it waits for combat to end.
function ns.RequestRefresh()
	local ranNow = ns.RunOutOfCombat("refresh", ns.Refresh)
	if not ranNow then
		ns.Print("In combat; the change is applied when the fight ends.")
	end
	return ranNow
end

function ns.IsBuilt()
	return built
end

ns.On("ADDON_LOADED", function(_, name)
	if name ~= ADDON then
		return
	end
	FreeControlDB = CopyDefaults(type(FreeControlDB) == "table" and FreeControlDB or {}, DEFAULTS)
	ns.db = FreeControlDB
	Sanitize(ns.db)
end)

ns.On("PLAYER_LOGIN", function()
	ns.Options:Create()
	ns.RunOutOfCombat("refresh", ns.Refresh)
	if ns.IsGamepadUI() and ns.db.enabled then
		ns.Print("Gamepad UI mode is on, so FreeControl is idle. Turn off Options > Gamepad > Enable Gamepad UI to use it.")
	elseif ns.db.enabled and not ns.db.introShown then
		ns.db.introShown = true
		ns.Print("Hold a trigger to switch sets and drop spells, items or macros onto any slot. /fc opens the settings; /fc unlock lets you drag the bar.")
	end
end)

-- Console variables are saved by the client on the way out, so the player's own values go back first.
ns.On("PLAYER_LOGOUT", function()
	ns.CVars:RestoreAll()
end)
