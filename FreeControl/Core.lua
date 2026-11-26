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
	toggleLayers = true,
	locked = true,
	scale = 1,
	point = { 0, 270 },    -- centre of the bar, measured from the bottom-centre of the screen
	activeScale = 1.2,     -- the set you are holding grows by this much
	inactiveAlpha = 0.8,   -- the other sets fade to this
	cooldownNumbers = true, -- count down the seconds left on a slot that is on cooldown
	procGlow = true,       -- glow a button whose spell has procced, or has come free for a moment
	keepRanks = true,      -- move a spell on the controller's slots up when a new rank of it is learned
	ranks = {},            -- per character, what Ranks.lua last saw in each slot
	labelStyle = "auto",   -- auto | xbox | playstation | nintendo
	slotSource = "gamepad", -- gamepad (Blizzard's controller-bar slots) | bars (regular action bar slots)
	page = 1,              -- which of Blizzard's three controller-bar pages to show (gamepad source only)
	pages = true,          -- the page can be turned; off, the bar stays on the one above
	showPager = true,      -- the page selector under the bottom set (pages can be turned without it, by a bound button)
	-- What changes with your stance or form: one of Layout.STANCE_CHOICES. Out of the box it is
	-- "custom", the player's own pick of the four layouts (Layout.STANCE_LAYOUTS) with none of
	-- them ticked: nothing changes until the player says so. The other choices are older ones
	-- that picked for the player; /fc stance still takes them.
	stanceSet = "custom",
	stancePicked = false,  -- a setup saved by an older version has been turned into the player's own pick (Layout.AdoptStancePick)
	stanceMain = false,
	stanceLT = false,
	stanceRT = false,
	stanceBoth = false,
	manageGamepad = true,  -- turn controller input (GamePadEnable) on while FreeControl is active
	softInteract = true,   -- make the Interact command pick nearby loot, NPCs and objects by itself
	interactReach = true,  -- use the Gamepad UI's wider interact arc and range
	frontTargeting = false, -- the enemy the game picks for you has to be in front of you, as in Gamepad UI mode
	keys = { "PADDLEFT", "PADDUP", "PADDRIGHT", "PADDDOWN", "PAD3", "PAD4", "PAD2", "PAD1" },
	modKeys = { "PADLTRIGGER", "PADRTRIGGER" },
	-- What the eight buttons do while no trigger is held:
	--   "action"      an action slot you can drop things into
	--   "pass"        FreeControl leaves the button to your own key binding
	--   "cmd:<NAME>"  run a game command (the names used by the Key Bindings screen)
	-- The top face button (Y) is the mouse button; its role is Layout.CURSOR_ROLE, see Mouse.lua.
	roles = { "action", "action", "action", "action", "cmd:INTERACTTARGET", "cmd:FREECONTROL_TOGGLECURSOR", "cmd:TOGGLEGAMEMENU", "cmd:JUMP" },
	layerRoles = {},       -- [trigger set][button]; absent entries are action slots
	-- What a button does on one page instead of the two above: [page][set 0-3][button]. A job
	-- given on the bar or in the settings goes here (Layout.SetRole).
	pageRoles = {},
	rolesPaged = false,    -- the trigger layouts' jobs of an older version have been moved to their page
	mainRolesPaged = false, -- and Main's, the ones the bar starts with among them
	mainFormSlots = {},    -- [form spell ID] = reserved eight-slot block
	mainFormRoles = {},    -- [form spell ID][button]; absent entries are action slots
	-- The two buttons that are the mouse buttons while the controller's mouse cursor is out: a
	-- button name, or "game" to leave that one to the game's own setting.
	mouseMode = true,      -- a button on the bar brings the mouse pointer out; off, that button is an action slot
	mouseIndex = 6,        -- the no-trigger button that was the mouse button when mouse mode was switched off
	gamePointer = true,    -- the game may bring its own mouse pointer out (a window opens, a spell is aimed); off, it is told not to
	clickLeft = "PADLSTICK",
	clickRight = "PADRSTICK",
	cursorSpeed = 1,       -- how fast the stick moves the mouse cursor, as a multiple of the player's own setting
	mouseHintShown = false, -- the chat line that explains the clicks, said the first time the pointer comes out
	mouseStep = 0,         -- how far this setup has been brought along by GiveMouseButton
	stanceNoteShown = false, -- the chat line telling a Druid which buttons change with the form
	formNotes = {},        -- per character: has been told about a shapeshift on a button that changes with the form
	plainKeys = {},        -- buttons given a job on the Other buttons page: they are no modifier stand-ins while we are active
	standIns = {},         -- [Ctrl | Alt | Shift] = the button chosen to be held for combinations, or "none"; one not in here is as the game has it
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
	return type(value) == "string" and (value == "action" or value == "pass" or value == "none" or value:match("^cmd:[%w_]+$") ~= nil)
end

local BAR_SETTINGS = {
	page = true, pages = true, showPager = true, slotSource = true, stanceSet = true,
	stanceMain = true, stanceLT = true, stanceRT = true, stanceBoth = true, stancePicked = true,
}

local function SanitizeBarSettings(bar)
	if not IsOneOf(bar.page, 1, 2, 3) then bar.page = DEFAULTS.page end
	if type(bar.pages) ~= "boolean" then bar.pages = DEFAULTS.pages end
	if type(bar.showPager) ~= "boolean" then bar.showPager = DEFAULTS.showPager end
	if not IsOneOf(bar.slotSource, "gamepad", "bars") then bar.slotSource = DEFAULTS.slotSource end
	if not IsOneOf(bar.stanceSet, unpack(ns.Layout.STANCE_CHOICES)) then bar.stanceSet = DEFAULTS.stanceSet end
	for _, entry in ipairs(ns.Layout.STANCE_LAYOUTS) do
		if type(bar[entry[1]]) ~= "boolean" then bar[entry[1]] = DEFAULTS[entry[1]] end
	end
	ns.Layout.LimitStanceSets(bar)
	if type(bar.stancePicked) ~= "boolean" then bar.stancePicked = DEFAULTS.stancePicked end
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
	if not IsOneOf(db.labelStyle, "auto", "xbox", "playstation", "nintendo") then Reset("labelStyle") end
	SanitizeBarSettings(db)
	if type(db.point[1]) ~= "number" or type(db.point[2]) ~= "number" then
		Reset("point")
	end
	for i = 1, 8 do
		if type(db.keys[i]) ~= "string" or db.keys[i] == "" then db.keys[i] = DEFAULTS.keys[i] end
		if not IsRole(db.roles[i]) then
			db.roles[i] = DEFAULTS.roles[i]
		end
	end
	for _, layouts in ipairs({ db.layerRoles, db.mainFormRoles }) do
		for id, roles in pairs(layouts) do
			if type(id) ~= "number" or id % 1 ~= 0 or id < 1
				or (layouts == db.layerRoles and id > 3) or type(roles) ~= "table" then
				layouts[id] = nil
			else
				for index, role in pairs(roles) do
					if type(index) ~= "number" or index < 1 or index > 8 or index % 1 ~= 0 or not IsRole(role) then
						roles[index] = nil
					end
				end
			end
		end
	end
	for page, sets in pairs(db.pageRoles) do
		if type(page) ~= "number" or page % 1 ~= 0 or page < 1 or page > ns.Layout.NUM_PAGES or type(sets) ~= "table" then
			db.pageRoles[page] = nil
		else
			for set, roles in pairs(sets) do
				if type(set) ~= "number" or set % 1 ~= 0 or set < 0 or set > 3 or type(roles) ~= "table" then
					sets[set] = nil
				else
					for index, role in pairs(roles) do
						if type(index) ~= "number" or index < 1 or index > 8 or index % 1 ~= 0 or not IsRole(role) then
							roles[index] = nil
						end
					end
				end
			end
		end
	end
	-- Up to 1.8.0 a job was on its button on every page. Jobs belong to a page now, and the ones
	-- there were are moved to the page they were most likely given on: the first, or the page the
	-- bar was kept on with pages switched off. That goes for Main as well, the jobs the bar starts
	-- with among them (Interact, the game menu, Jump): on the other pages those buttons are slots.
	-- The jobs that are on every page by their nature stay where they are (Layout.IsEveryPageJob).
	-- Main's are moved by PageMainRoles, once the mouse button has been seen to.
	local page = db.pages == false and IsOneOf(db.page, 1, 2, 3) and db.page or 1
	if not db.rolesPaged then
		db.rolesPaged = true
		for set, roles in pairs(db.layerRoles) do
			for index, role in pairs(roles) do
				db.pageRoles[page] = db.pageRoles[page] or {}
				db.pageRoles[page][set] = db.pageRoles[page][set] or {}
				if db.pageRoles[page][set][index] == nil then
					db.pageRoles[page][set][index] = role
				end
			end
			db.layerRoles[set] = nil
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
	for character, record in pairs(db.ranks) do
		if type(record) ~= "table" then db.ranks[character] = nil end
	end
	for character, told in pairs(db.formNotes) do
		if told ~= true then db.formNotes[character] = nil end
	end
	for key, plain in pairs(db.plainKeys) do
		if type(key) ~= "string" or key ~= key:upper() or plain ~= true then db.plainKeys[key] = nil end
	end
	local seen = {}
	for _, key in ipairs(ns.Layout.OTHER_KEYS) do seen[key] = true end
	local extraKeys = {}
	if type(db.extraKeys) == "table" then
		for _, key in ipairs(db.extraKeys) do
			if type(key) == "string" and key ~= "" and key == key:upper() and not seen[key] then
				extraKeys[#extraKeys + 1] = key
				seen[key] = true
			end
		end
	else
		-- Earlier versions kept the bindings but only displayed the last captured key.
		for key in pairs(db.plainKeys) do
			if key ~= "" and not seen[key] then extraKeys[#extraKeys + 1] = key end
		end
		table.sort(extraKeys)
	end
	db.extraKeys = extraKeys
	db.mouseTipShown = nil -- used by 1.2.0 only
	-- Version 1.3.0 kept its own notes on the mouse button. Its "given" meant the button had no
	-- job before, which is what "pass" says now; anything else it wrote is dropped.
	db.mouseButtonSet = nil
	if db.mouseNews == "given" then
		db.mouseNews = "pass"
	end
	if type(db.mouseStep) ~= "number" then Reset("mouseStep") end
	if db.mouseNews ~= nil and not IsRole(db.mouseNews) then db.mouseNews = nil end
	for _, key in ipairs({ "mouseMode", "gamePointer", "frontTargeting", "toggleLayers" }) do
		if type(db[key]) ~= "boolean" then Reset(key) end
	end
	for modifier, button in pairs(db.standIns) do
		local isName = type(button) == "string" and button ~= "" and (button == "none" or button == button:upper())
		if not IsOneOf(modifier, "Ctrl", "Alt", "Shift") or not isName then db.standIns[modifier] = nil end
	end
	if not IsOneOf(db.mouseIndex, 1, 2, 3, 4, 5, 6, 7, 8) then Reset("mouseIndex") end
	-- With mouse mode off no button is the mouse button: one that still says so is an action slot.
	if not db.mouseMode then
		for index = 8, 1, -1 do
			if ns.Layout.IsCursorRole(db.roles[index]) then
				db.roles[index], db.mouseIndex = "action", index
			end
		end
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
		ns.Ranks:CheckSoon() -- ranks learned while FreeControl was off or idle
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

function ns.GetBarProfile()
	return ns.barProfile or ns.db
end

function ns.GetSettingStore(key)
	return BAR_SETTINGS[key] and ns.GetBarProfile() or ns.db
end

-- Forever's primary and secondary talent groups can have the same class specialization.
local function SelectBarProfile()
	local getGroup = C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup
	local group = getGroup and getGroup()
	if ns.IsSealed(group) or not IsOneOf(group, 1, 2) or ns.activeSpecGroup == group then
		return false
	end
	local db = ns.db
	if type(db.barProfiles) ~= "table" then db.barProfiles = {} end
	local profile = db.barProfiles[group]
	if type(profile) ~= "table" then
		profile = {}
		for key in pairs(BAR_SETTINGS) do profile[key] = db[key] end
		db.barProfiles[group] = profile
	end
	SanitizeBarSettings(profile)
	ns.activeSpecGroup, ns.barProfile = group, profile
	return true
end

local function RefreshBarProfile()
	if not ns.db then return end
	ns.RunOutOfCombat("bar-profile", function()
		if SelectBarProfile() then ns.Refresh() end
	end)
end

if C_EventUtils and C_EventUtils.IsEventValid and C_EventUtils.IsEventValid("ACTIVE_TALENT_GROUP_CHANGED") then
	ns.On("ACTIVE_TALENT_GROUP_CHANGED", RefreshBarProfile)
end
ns.On("PLAYER_ENTERING_WORLD", RefreshBarProfile)

-- Called by the secure header (in combat too) each time it has pointed the buttons at their
-- slots, with the page they now show. The page is remembered for the next login; with the
-- regular action bars as the slots there is only one, and the saved page is kept for later.
function ns.OnPageShown(page)
	ns.Bars:OnPageChanged(page)
	local profile = ns.GetBarProfile()
	if ns.Layout.GetPageCount() > 1 and profile.page ~= page then
		profile.page = page
		-- A button's job belongs to the page: the pictures of the jobs follow it. (Which button
		-- is a job and which a slot was changed by the secure header already.)
		ns.Buttons:UpdateRoleWidgets()
		ns.Options:Sync()
	end
end

-- The top face button: Y, Triangle, or X on a Nintendo pad.
local MOUSE_INDEX = 6

-- Switches mouse mode on or off. Off, the button that was the mouse button becomes an ordinary
-- action slot: on each page it holds whatever the player drops on it. Which button that was is
-- remembered, and it is the mouse button again when the mode is switched back on, unless the
-- player has given it another job in between, or another button has the job by then.
function ns.SetMouseMode(on)
	local db = ns.db
	local Layout = ns.Layout
	db.mouseMode = on
	if on then
		local has = false
		for index = 1, 8 do
			has = has or Layout.IsCursorRole(db.roles[index])
		end
		if not has and not ns.Mouse:GetBarButtonName() and db.roles[db.mouseIndex] == "action" then
			db.roles[db.mouseIndex] = Layout.CURSOR_ROLE
		end
	else
		for index = 8, 1, -1 do
			if Layout.IsCursorRole(db.roles[index]) then
				db.roles[index], db.mouseIndex = "action", index
			end
		end
		-- This setting does not reach the pointer the game brings out by itself. A player who wants
		-- no stick pointer at all is told where the switch for that one is.
		if db.gamePointer and ns.Mouse:IsAvailable() then
			ns.Print("Mouse mode is off. The game still brings its own pointer out when a window opens: to stop that too, untick \"The game may bring the pointer out\" on the Mouse mode page, or type /fc gamepointer off.")
		end
	end
	return ns.RequestRefresh()
end

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
	if not db.mouseMode then
		return -- the player wants no mouse button
	end
	for index = 1, 8 do
		if ns.Layout.IsCursorRole(db.roles[index]) then
			return
		end
	end
	db.mouseNews = db.roles[MOUSE_INDEX]
	db.roles[MOUSE_INDEX] = ns.Layout.CURSOR_ROLE
end

-- Once. Moves Main's jobs to their page, as Sanitize does for the trigger layouts: the first
-- page, or the one the bar was kept on with pages switched off. It runs after GiveMouseButton,
-- which looks at what Y was doing before; the mouse button itself is on every page and stays.
local function PageMainRoles(db)
	if db.mainRolesPaged then
		return
	end
	db.mainRolesPaged = true
	local page = db.pages == false and IsOneOf(db.page, 1, 2, 3) and db.page or 1
	for index = 1, 8 do
		local role = db.roles[index]
		if role ~= "action" and not ns.Layout.IsEveryPageJob(role) then
			db.pageRoles[page] = db.pageRoles[page] or {}
			db.pageRoles[page][0] = db.pageRoles[page][0] or {}
			if db.pageRoles[page][0][index] == nil then
				db.pageRoles[page][0][index] = role
			end
			db.roles[index] = "action"
		end
	end
end

ns.On("ADDON_LOADED", function(_, name)
	if name ~= ADDON then
		return
	end
	if type(FreeControlCharacterDB) ~= "table" then
		-- Each character gets its own copy of the old account settings on first login.
		local legacy = type(FreeControlDB) == "table" and FreeControlDB
		FreeControlCharacterDB = legacy and CopyTable(legacy) or {}
	end
	ns.db = CopyDefaults(FreeControlCharacterDB, DEFAULTS)
	ns.activeSpecGroup, ns.barProfile = nil, nil
	Sanitize(ns.db)
	GiveMouseButton(ns.db)
	PageMainRoles(ns.db)
end)

-- Said at the first login at which FreeControl is in use, which need not be the one that made the change.
local function SayMouseNews()
	local was = ns.db.mouseNews
	if not was or not ns.Mouse:IsEnabled() then
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
	if db.stanceNoteShown or ns.GetBarProfile().stanceSet ~= "auto" then
		return
	end
	-- On automatic only a class whose forms replace the whole bar has more than one group.
	local groups = ns.Layout.GetStanceGroups()
	if #groups < 2 then
		return
	end
	db.stanceNoteShown = true
	if ns.IsBuilt() and ns.Bindings.header:GetAttribute("fc-main-forms") then
		ns.Print("All eight Main buttons have their own action slots in each form. Leave the form to get your normal Main layout back.")
		return
	end
	ns.Print(("Druid: %s change with your form on page %d, so each form has its own buttons there. The %s set, the face buttons and the other pages stay the same in every form: put your shapeshifts there. Stance sets on the settings page (/fc) changes this."):format(
		ns.Layout.DescribeStanceGroups(groups), ns.Layout.GetStancePage(), ns.Layout.GetSetName(ns.Layout.SET_BOTH)))
end

ns.On("PLAYER_LOGIN", function()
	SelectBarProfile()
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
		ns.Print("Press a trigger to toggle its layer, or press both to toggle the combined layer. Assign Return to main layer under /fc buttons or Key Bindings.")
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
