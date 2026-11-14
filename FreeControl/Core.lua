local ADDON, ns = ...

-- Exposed for /run debugging. Blizzard code never reads it.
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
	stanceSet = "auto",    -- what changes with your stance or form: one of Layout.STANCE_CHOICES
	manageGamepad = true,  -- turn controller input (GamePadEnable) on while FreeControl is active
	softInteract = true,   -- make the Interact command pick nearby loot, NPCs and objects by itself
	interactReach = true,  -- use the Gamepad UI's wider interact arc and range
	keys = { "PADDLEFT", "PADDUP", "PADDRIGHT", "PADDDOWN", "PAD3", "PAD4", "PAD2", "PAD1" },
	modKeys = { "PADLTRIGGER", "PADRTRIGGER" },
	-- What the eight buttons do while no trigger is held:
	--   "action"      an action slot you can drop things into
	--   "pass"        FreeControl leaves the button to your own key binding
	--   "cmd:<NAME>"  run a game command (the names used by the Key Bindings screen)
	-- The top face button (Y) is the mouse button; its role is Layout.CURSOR_ROLE, see Mouse.lua.
	roles = { "action", "action", "action", "action", "cmd:INTERACTTARGET", "cmd:FREECONTROL_TOGGLECURSOR", "cmd:TOGGLEGAMEMENU", "cmd:JUMP" },
	-- The two buttons that are the mouse buttons while the controller's mouse cursor is out: a
	-- button name, or "game" to leave that one to the game's own setting.
	clickLeft = "PADLSTICK",
	clickRight = "PADRSTICK",
	cursorSpeed = 1,       -- how fast the stick moves the mouse cursor, as a multiple of the player's own setting
	mouseHintShown = false, -- the chat line that explains the clicks, said the first time the pointer comes out
	mouseStep = 0,         -- how far this setup has been brought along by GiveMouseButton
	stanceNoteShown = false, -- the chat line telling a Druid which buttons change with the form
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
local function IsRole(value)
	return type(value) == "string" and (value == "action" or value == "pass" or value:match("^cmd:[%w_]+$") ~= nil)
end

local function Sanitize(db)
	local function Reset(key)
		local default = DEFAULTS[key]
		db[key] = type(default) == "table" and CopyTable(default) or default
	end
	if type(db.scale) ~= "number" or db.scale < 0.4 or db.scale > 2.5 then Reset("scale") end
	if type(db.activeScale) ~= "number" or db.activeScale < 1 or db.activeScale > 1.6 then Reset("activeScale") end
	if type(db.inactiveAlpha) ~= "number" or db.inactiveAlpha < 0.2 or db.inactiveAlpha > 1 then Reset("inactiveAlpha") end
	if type(db.cursorSpeed) ~= "number" or db.cursorSpeed < 0.25 or db.cursorSpeed > 4 then Reset("cursorSpeed") end
	if not IsOneOf(db.page, 1, 2, 3) then Reset("page") end
	if not IsOneOf(db.labelStyle, "auto", "xbox", "playstation", "nintendo") then Reset("labelStyle") end
	if not IsOneOf(db.slotSource, "gamepad", "bars") then Reset("slotSource") end
	if not IsOneOf(db.stanceSet, unpack(ns.Layout.STANCE_CHOICES)) then Reset("stanceSet") end
	if type(db.point[1]) ~= "number" or type(db.point[2]) ~= "number" then
		Reset("point")
	end
	for i = 1, 8 do
		if type(db.keys[i]) ~= "string" or db.keys[i] == "" then db.keys[i] = DEFAULTS.keys[i] end
		if not IsRole(db.roles[i]) then
			db.roles[i] = DEFAULTS.roles[i]
		end
	end
	for i = 1, 2 do
		if type(db.modKeys[i]) ~= "string" or db.modKeys[i] == "" then db.modKeys[i] = DEFAULTS.modKeys[i] end
	end
	-- A click button has to be a button name. It cannot be a trigger (a held trigger must stay a
	-- trigger) and the two clicks cannot share one; either falls back to the game's own setting.
	for _, key in ipairs({ "clickLeft", "clickRight" }) do
		local value = db[key]
		if type(value) ~= "string" or value == "" or (value ~= "game" and value ~= value:upper()) then
			value = DEFAULTS[key]
		end
		if value == db.modKeys[1] or value == db.modKeys[2] then
			value = "game"
		end
		db[key] = value
	end
	if db.clickLeft == db.clickRight then
		db.clickRight = "game"
	end
	db.mouseTipShown = nil -- used by 1.2.0 only
	-- Version 1.3.0 kept its own notes on the mouse button. Its "given" meant the button had no
	-- job before, which is what "pass" says now; anything else it wrote is dropped.
	db.mouseButtonSet = nil
	if db.mouseNews == "given" then
		db.mouseNews = "pass"
	end
	if type(db.mouseStep) ~= "number" then Reset("mouseStep") end
	if db.mouseNews ~= nil and not IsRole(db.mouseNews) then db.mouseNews = nil end
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
-- Sealed values
---------------------------------------------------------------------------
-- While the game's addon restrictions are in force (in combat, among other times) some of what
-- it tells an addon comes back sealed: a "secret" value that can be stored and passed on, but not
-- compared, calculated with or handed to most game functions. Doing any of that is an error on
-- the spot. Blizzard's interface code marks which answers can be sealed (SecretWhen... in
-- Blizzard_APIDocumentationGenerated); nothing in this addon may read one of those.
function ns.IsSealed(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

-- For /fc status and /fc trace: "yes", "no", or that this client cannot say.
function ns.DescribeSealing()
	local secrets = C_Secrets
	if not (secrets and secrets.HasSecretRestrictions) then
		return "this client does not say"
	end
	if not secrets.HasSecretRestrictions() then
		return "no"
	end
	return secrets.ShouldCooldownsBeSecret and secrets.ShouldCooldownsBeSecret() and "yes, and cooldowns are sealed right now"
		or "yes, but cooldowns are not sealed right now"
end

---------------------------------------------------------------------------
-- Errors
---------------------------------------------------------------------------
-- The game hides addon errors unless the player has switched them on, so an error in the code
-- that draws the bar would end that update without anyone seeing why. Code run through ns.Try
-- still hands every error to the game's own error handler, exactly as an uncaught one would be;
-- on top of that the first one is said in chat and they are kept for /fc status, so a problem
-- can be reported even with errors hidden. One failing handler or button does not stop the next.
local MAX_PROBLEMS = 8 -- different errors kept; repeats of a kept one are only counted
local problems = {}    -- { text = "...", count = n }, in order of first appearance
local problemByText = {}

local function Record(text)
	local problem = problemByText[text]
	if problem then
		problem.count = problem.count + 1
	elseif #problems < MAX_PROBLEMS then
		problem = { text = text, count = 1 }
		problems[#problems + 1] = problem
		problemByText[text] = problem
		if #problems == 1 then
			ns.Print("|cffff4040Something went wrong inside FreeControl|r, so part of the bar may not be updating. Type /fc status to see the error.")
		end
		if ns.Trace then
			ns.Trace:Add("ERROR " .. text)
		end
	end
end

local function OnError(message)
	Record(tostring(message))
	geterrorhandler()(message)
	return message
end

-- Runs fn(...). Returns true and what it returned, or false after reporting what went wrong.
function ns.Try(fn, ...)
	return xpcall(fn, OnError, ...)
end

function ns.GetProblems()
	return problems
end

-- The game refuses some calls from addons, in a fight above all. That is not an error in Lua:
-- the call simply does nothing and the game announces it with one of these events, which nobody
-- sees. They are kept with the errors, so that a button that quietly does nothing can be traced.
local function OnBlocked(_, addon, what)
	if addon == ADDON then
		Record(("The game refused to let FreeControl call %s."):format(tostring(what)))
	end
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
		ns.Try(fn, event, ...)
	end
end)

ns.On("ADDON_ACTION_BLOCKED", OnBlocked)
ns.On("ADDON_ACTION_FORBIDDEN", OnBlocked)

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
		ns.Mouse:Apply()
	else
		if built then
			ns.Bindings:Clear()
			ns.Buttons:Release()
			ns.Bars:Hide()
		end
		ns.Mouse:Release()
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

-- The top face button: Y, Triangle, or X on a Nintendo pad.
local MOUSE_INDEX = 6

-- The top face button is the mouse button for every setup, and FreeControl binds it, the way it
-- binds Interact. A new setup starts that way. One from an earlier version that has the mouse
-- button on no button at all is given it there, once, whatever the button was doing: up to 1.2
-- it was left to the player's own key binding, and 1.3.0 gave it the job only where it had none,
-- so a player whose Y did something else still had to find the menu entry. What the button was
-- is kept in db.mouseNews until the player has been told, so the chat line can say how to put it
-- back. After that the player's own choice stands, including taking the mouse button off again.
local MOUSE_STEP = 2 -- 1 was version 1.3.0's

local function GiveMouseButton(db)
	if db.mouseStep >= MOUSE_STEP then
		return
	end
	db.mouseStep = MOUSE_STEP
	for index = 1, 8 do
		if ns.Layout.IsCursorRole(db.roles[index]) then
			return
		end
	end
	db.mouseNews = db.roles[MOUSE_INDEX]
	db.roles[MOUSE_INDEX] = ns.Layout.CURSOR_ROLE
end

ns.On("ADDON_LOADED", function(_, name)
	if name ~= ADDON then
		return
	end
	FreeControlDB = CopyDefaults(type(FreeControlDB) == "table" and FreeControlDB or {}, DEFAULTS)
	ns.db = FreeControlDB
	Sanitize(ns.db)
	GiveMouseButton(ns.db)
end)

-- Said at the first login at which FreeControl is in use, which need not be the one that made the change.
local function SayMouseNews()
	local was = ns.db.mouseNews
	if not was or not ns.Mouse:IsAvailable() then
		return
	end
	ns.db.mouseNews = nil
	local name = ns.Layout.GetButtonName(ns.Layout.SET_NONE, MOUSE_INDEX)
	local kind, command = ns.Layout.ParseRole(was)
	local before
	if kind == "cmd" then
		before = ("It was \"%s\" before: to put that back, click %s on the bar."):format(ns.Layout.GetCommandInfo(command), name)
	elseif kind == "action" then
		before = ("It was an action slot before, and what was in it is still there: to put that back, click %s on the bar."):format(name)
	else
		before = ("To give %s another job, click it on the bar."):format(name)
	end
	ns.Print(("New: %s is now the mouse button. Press it and the right stick steers a mouse pointer; %s. Press it again to put the pointer away. %s"):format(
		name, ns.Mouse:DescribeClicks(), before))
end

-- Said once, the first time a Druid logs in: more of their bar changes with the form than a
-- player coming from another class, or from an earlier version, would expect.
local function SayStanceNote()
	local db = ns.db
	if db.stanceNoteShown or db.stanceSet ~= "auto" then
		return
	end
	-- On automatic only a class whose forms replace the whole bar has more than one group.
	local groups = ns.Layout.GetStanceGroups()
	if #groups < 2 then
		return
	end
	db.stanceNoteShown = true
	ns.Print(("Druid: %s change with your form, so each form has its own buttons. The %s set and the face buttons stay the same in every form: put your shapeshifts there. Stance sets on the settings page (/fc) changes this."):format(
		ns.Layout.DescribeStanceGroups(groups), ns.Layout.GetSetName(ns.Layout.SET_BOTH)))
end

ns.On("PLAYER_LOGIN", function()
	ns.Options:Create()
	ns.RunOutOfCombat("refresh", ns.Refresh)
	if ns.IsGamepadUI() and ns.db.enabled then
		ns.Print("Gamepad UI mode is on, so FreeControl is idle. Turn off Options > Gamepad > Enable Gamepad UI to use it.")
		return
	elseif not ns.db.enabled then
		return
	end
	if not ns.db.introShown then
		ns.db.introShown = true
		ns.db.mouseNews = nil -- these lines cover the mouse button
		ns.Print("Hold a trigger to switch sets and drop spells, items or macros onto any slot. /fc opens the settings; /fc unlock lets you drag the bar.")
		if ns.Mouse:IsAvailable() and ns.Mouse:GetBarButtonName() then
			ns.Print(("%s brings out a mouse pointer that the right stick steers; %s."):format(ns.Mouse:GetBarButtonName(), ns.Mouse:DescribeClicks()))
		end
	end
	SayMouseNews()
	ns.Layout.Prepare()
	SayStanceNote()
end)

-- Console variables are saved by the client on the way out, so the player's own values go back first.
ns.On("PLAYER_LOGOUT", function()
	ns.CVars:RestoreAll()
end)
