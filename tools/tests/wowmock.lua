-- A small stand-in for the parts of the WoW client that FreeControl touches, strict enough to
-- catch real mistakes:
--
--   * frames only have the widget methods listed here, so a misspelt method is an error;
--   * protected frames refuse protected calls from addon code while "in combat";
--   * secure snippets run in a restricted environment (no tables, no functions, no addon globals)
--     against frame handles that only expose what the real restricted environment exposes;
--   * key presses are routed through override bindings to button clicks the way the client does,
--     honouring RegisterForClicks and delivering both press and release.
--
-- The secure click logic is a port of SecureActionButton_OnClick from Blizzard_FrameXML/
-- SecureTemplates.lua (build 1.60.1). It is a model of the client, not the client: a pass here
-- shows the addon's own logic is consistent, not that the game agrees with the model.

local M = {
	combat = false,
	secure = 0,            -- > 0 while Blizzard (secure) code is running
	bonusbar = 0,
	lockActionBars = true,
	pickupModifier = false,
	cursor = nil,
	gamepadUI = false,
	-- Defaults of a fresh Forever client (wowless's data for build 1.60.1.70888).
	cvars = {
		GamePadEnable = "1", SoftTargetInteract = "1", SoftTargetInteractArc = "0",
		SoftTargetInteractRange = "10.000000", SoftTargetIconGameObject = "0",
		ActionButtonUseKeyDown = "1", countdownForCooldowns = "0", GamepadStanceBarOverride = "3",
		GamePadCursorLeftClick = "PADRTRIGGER", GamePadCursorRightClick = "PADRSHOULDER",
		GamePadEmulateShift = "PADLTRIGGER", GamePadEmulateCtrl = "PADLSHOULDER", GamePadEmulateAlt = "none",
	},
	floatCVars = { SoftTargetInteractRange = true }, -- the client stores these as "20.000000"
	actions = {},          -- [slot] = { texture, usable, noMana, cooldown, count, current, equipped, text }
	used = {},             -- UseAction calls: { slot, unit, button }
	commands = {},         -- binding commands run: { name, "down" | "up" }
	bindings = {},         -- [key] = { owner, kind = "click" | "cmd", target, button }
	held = {},             -- [key] = the binding it was pressed with
	frames = {},           -- [name] = frame
	printed = {},
	errors = {},           -- UIErrorsFrame messages
	rangeRefs = {},        -- [slot] = number of outstanding EnableActionRangeCheck(slot, true)
	events = {},           -- [event] = { frame, ... }
	drivers = {},          -- { frame, attribute, values }
	picked = {}, placed = {},
	opened = {},
	firstGamepadSlot = 181,
	lastGamepadSlot = 304, -- three pages of 28 plus five stance bars of 8
	hasGamepadUI = true,
	cursorControl = false,
}
Mock = M

local function insecure()
	return M.secure == 0
end

---------------------------------------------------------------------------
-- Regions
---------------------------------------------------------------------------
local Region = {}
Region.__index = Region
for _, name in ipairs({ "SetPoint", "ClearAllPoints", "SetAllPoints", "SetSize", "SetWidth", "SetHeight",
	"SetTexCoord", "SetVertexColor", "SetBlendMode", "AddMaskTexture", "SetColorTexture", "SetDrawLayer",
	"SetWordWrap", "SetJustifyH", "SetFontObject" }) do
	Region[name] = function(self, ...) self.calls[name] = { ... } end
end
function Region:SetTexture(texture) self.texture = texture end
function Region:GetTexture() return self.texture end
function Region:SetAlpha(alpha) self.alpha = alpha end
function Region:GetAlpha() return self.alpha end
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:SetShown(shown) self.shown = shown and true or false end
function Region:IsShown() return self.shown end
function Region:SetText(text) self.text = text end
function Region:GetText() return self.text end

local function NewRegion(kind)
	return setmetatable({ kind = kind, shown = true, alpha = 1, calls = {} }, Region)
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local Frame = {}
Frame.__index = Frame

local function guard(self, what)
	if (self.__protected or self.__implicit) and M.combat and insecure() then
		error(("BLOCKED: %s on protected frame %s in combat"):format(what, tostring(self.__name)), 3)
	end
end

local function markAncestors(frame)
	local parent = frame.__parent
	while parent do
		parent.__implicit = true
		parent = parent.__parent
	end
end

-- Protected widget calls, per Blizzard_APIDocumentationGenerated (IsProtectedFunction).
for _, name in ipairs({ "SetPoint", "ClearAllPoints", "SetAllPoints", "SetSize", "SetWidth", "SetHeight",
	"SetFrameStrata", "EnableMouse", "SetID", "SetClampedToScreen", "RegisterForDrag", "SetMovable" }) do
	local isProtected = name ~= "RegisterForDrag" and name ~= "SetMovable"
	Frame[name] = function(self, ...)
		if isProtected then guard(self, name) end
		self.__calls[name] = { ... }
	end
end

function Frame:GetName() return self.__name end
function Frame:GetParent() return self.__parent end
function Frame:IsProtected() return (self.__protected or self.__implicit) and true or false, self.__protected and true or false end
function Frame:SetScale(scale) guard(self, "SetScale"); self.__scale = scale end
function Frame:GetScale() return self.__scale end
function Frame:SetAlpha(alpha) self.__alpha = alpha end
function Frame:GetAlpha() return self.__alpha end
function Frame:Show() guard(self, "Show"); self.__shown = true end
function Frame:Hide() guard(self, "Hide"); self.__shown = false end
function Frame:SetShown(shown) guard(self, "SetShown"); self.__shown = shown and true or false end
function Frame:IsShown() return self.__shown end
function Frame:IsVisible()
	local frame = self
	while frame do
		if not frame.__shown then return false end
		frame = frame.__parent
	end
	return true
end
function Frame:SetFrameLevel(level) guard(self, "SetFrameLevel"); self.__level = level end
function Frame:GetFrameLevel() return self.__level end
function Frame:GetWidth() return self.__width or 0 end
function Frame:GetCenter() return self.__center[1], self.__center[2] end
function Frame:StartMoving() guard(self, "StartMoving"); self.__moving = true end
function Frame:StopMovingOrSizing() guard(self, "StopMovingOrSizing"); self.__moving = false end
function Frame:RegisterEvent(event)
	M.events[event] = M.events[event] or {}
	table.insert(M.events[event], self)
end
function Frame:SetScript(name, fn) self.__scripts[name] = fn; self.__addonScript[name] = fn ~= nil end
function Frame:GetScript(name) return self.__scripts[name] end
function Frame:HookScript(name, fn)
	local old = self.__scripts[name]
	if old then
		self.__scripts[name] = function(...) old(...); fn(...) end
	else
		self.__scripts[name] = fn
	end
end
function Frame:SetAttribute(name, value)
	guard(self, "SetAttribute")
	self.__attrs[name] = value
	local handler = self.__scripts.OnAttributeChanged
	if handler then
		-- Addon-installed handlers run tainted even when Blizzard code set the attribute.
		local depth = M.secure
		M.secure = 0
		handler(self, name, value)
		M.secure = depth
	end
end
function Frame:GetAttribute(name) return self.__attrs[name] end
function Frame:CreateTexture() return NewRegion("Texture") end
function Frame:CreateMaskTexture() return NewRegion("MaskTexture") end
function Frame:CreateFontString() return NewRegion("FontString") end

-- Buttons
function Frame:RegisterForClicks(...)
	guard(self, "RegisterForClicks")
	self.__clicks = { down = false, up = false }
	for i = 1, select("#", ...) do
		local kind = select(i, ...)
		if kind:find("Down$") then self.__clicks.down = true end
		if kind:find("Up$") then self.__clicks.up = true end
	end
end
function Frame:SetNormalTexture(texture) self.__normal = NewRegion("Texture"); self.__normal.texture = texture end
function Frame:GetNormalTexture() return self.__normal end
function Frame:SetPushedTexture(texture) self.__pushed = texture end
function Frame:SetHighlightTexture(texture, mode) self.__highlight = texture end
function Frame:SetCheckedTexture(texture) self.__checkedTexture = texture end
function Frame:SetChecked(checked) self.__checked = checked and true or false end
function Frame:GetChecked() return self.__checked end
function Frame:SetButtonState(state) self.__state = state end
function Frame:GetButtonState() return self.__state end
function Frame:SetText(text) self.__text = text end
function Frame:GetText() return self.__text end

-- Cooldown frames
function Frame:SetCooldown(start, duration, modRate) self.__cooldown = { start, duration, modRate } end
function Frame:Clear() self.__cooldown = nil end
for _, name in ipairs({ "SetDrawEdge", "SetDrawBling", "SetSwipeColor", "SetSwipeTexture", "SetUseCircularEdge", "SetHideCountdownNumbers" }) do
	Frame[name] = function(self, ...) self.__calls[name] = { ... } end
end

---------------------------------------------------------------------------
-- Restricted environment
---------------------------------------------------------------------------
local RESTRICTED = {
	math = math, string = string, select = select, tonumber = tonumber, tostring = tostring, type = type,
	format = string.format, strsub = string.sub, strlen = string.len, floor = math.floor, max = math.max, min = math.min,
}

local RunSnippet

local function Handle(frame)
	if frame.__handle then return frame.__handle end
	local h = {}
	frame.__handle = h
	local function target()
		-- Handles of frames that are not explicitly protected stop working in combat.
		if M.combat and not frame.__protected then
			error("Invalid frame handle (frame is not explicitly protected): " .. tostring(frame.__name), 3)
		end
		return frame
	end
	function h:GetName() return frame.__name end
	function h:GetAttribute(name) return target().__attrs[name] end
	function h:SetAttribute(name, value)
		if type(name) ~= "string" or name:match("^_") then error("Invalid attribute name", 2) end
		local tv = type(value)
		if tv ~= "string" and tv ~= "nil" and tv ~= "number" and tv ~= "boolean" then error("Invalid attribute value", 2) end
		target():SetAttribute(name, value)
	end
	function h:GetFrameRef(label) return target().__attrs["frameref-" .. label] end
	function h:SetScale(scale) target():SetScale(tonumber(scale)) end
	function h:SetAlpha(alpha) target():SetAlpha(tonumber(alpha)) end
	function h:Show() target():Show() end
	function h:Hide() target():Hide() end
	function h:ClearBindings() ClearOverrideBindings(target()) end
	function h:ClearBinding(key) SetOverrideBinding(target(), true, key, nil) end
	function h:SetBindingClick(priority, key, name, button)
		if type(name) ~= "string" or name:match(":") then error("Invalid click target name", 2) end
		SetOverrideBindingClick(target(), priority, key, name, button)
	end
	function h:SetBinding(priority, key, action)
		if action ~= nil and type(action) ~= "string" then error("Invalid binding action", 2) end
		SetOverrideBinding(target(), priority, key, action)
	end
	function h:RunAttribute(name, ...)
		local body = target().__attrs[name]
		if type(body) ~= "string" then error("Invalid snippet body: " .. tostring(name), 2) end
		return RunSnippet(frame, "self,...", body, h, ...)
	end
	function h:CallMethod(name, ...)
		-- The method is addon code: it runs tainted, whatever called it.
		local depth = M.secure
		M.secure = 0
		target()[name](frame, ...)
		M.secure = depth
	end
	return h
end
M.Handle = Handle

function RunSnippet(frame, signature, body, ...)
	assert(not body:find("function"), "restricted snippets cannot define functions")
	assert(not body:find("{"), "restricted snippets cannot build tables")
	local factory = assert(loadstring("return function(" .. signature .. ")\n" .. body .. "\nend", "snippet"))
	frame.__env = frame.__env or setmetatable({}, { __index = RESTRICTED })
	local fn = factory()
	setfenv(fn, frame.__env)
	M.secure = M.secure + 1
	local ok, err = pcall(fn, ...)
	M.secure = M.secure - 1
	if not ok then error(err, 0) end
end

local function addHandlerMethods(frame)
	function frame:Execute(body)
		if M.combat then error("Cannot call Execute in combat", 2) end
		RunSnippet(self, "self", body, Handle(self))
	end
	function frame:SetFrameRef(label, ref)
		if M.combat then error("Cannot use SetFrameRef in combat", 2) end
		self.__attrs["frameref-" .. label] = Handle(ref)
	end
end

---------------------------------------------------------------------------
-- Secure action buttons (port of Blizzard's SecureActionButton_OnClick, type "action" only)
---------------------------------------------------------------------------
function UseAction(slot, unit, button)
	slot = tonumber(slot)
	if M.combat and insecure() then error("BLOCKED: UseAction from tainted code in combat", 2) end
	if M.cursor then
		M.placed[#M.placed + 1] = slot
		M.cursor = nil
		return
	end
	M.used[#M.used + 1] = { slot = slot, unit = unit, button = button }
end

function SecureActionButton_OnClick(self, inputButton, down, isKeyPress, isSecureAction)
	local isSecureMousePress = not isKeyPress and isSecureAction
	local pressAndHoldAction = self:GetAttribute("pressAndHoldAction")
	local useOnKeyDown = self:GetAttribute("useOnKeyDown")
	if useOnKeyDown == nil then
		useOnKeyDown = GetCVarBool("ActionButtonUseKeyDown")
	end
	useOnKeyDown = not isSecureMousePress and (useOnKeyDown or pressAndHoldAction)
	local clickAction = (down and useOnKeyDown) or (not down and not useOnKeyDown)
	if clickAction then
		assert(self:GetAttribute("type") == "action", "mock only models type=action")
		-- Fields the real click path reads; a tainted value here blocks the action in combat.
		assert(rawget(self, "popup") == nil and rawget(self, "isExtra") == nil and rawget(self, "buttonType") == nil,
			"a field read by the secure click path was written by the addon")
		UseAction(self:GetAttribute("action") or 1, nil, inputButton)
		return true
	end
	return false
end

local function Flyout_OnClick() error("the flyout template's OnClick must not be the one that runs") end
local function noop() end

local TEMPLATES = {
	SecureFrameTemplate = function(f) f.__protected = true end,
	SecureActionButtonTemplate = function(f)
		f.__protected = true
		f.__scripts.OnClick = SecureActionButton_OnClick
	end,
	FlyoutButtonTemplate = function(f)
		f.__scripts.OnClick = Flyout_OnClick
		for _, name in ipairs({ "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp", "OnDragStart", "OnHide" }) do
			f.__scripts[name] = noop
		end
	end,
	SecureHandlerStateTemplate = function(f) f.__protected = true; addHandlerMethods(f) end,
	SecureHandlerClickTemplate = function(f)
		f.__protected = true
		addHandlerMethods(f)
		f.__scripts.OnClick = function(self, button, down)
			local body = self:GetAttribute("_onclick")
			if body then RunSnippet(self, "self,button,down", body, Handle(self), button, down) end
		end
		f.__secureClick = true
	end,
	CooldownFrameTemplate = noop,
	UIPanelButtonTemplate = noop,
	UICheckButtonTemplate = function(f) f.Text = NewRegion("FontString") end,
}

function CreateFrame(kind, name, parent, templates)
	local frame = setmetatable({
		__kind = kind, __name = name, __parent = parent, __shown = true, __scale = 1, __alpha = 1, __level = 1,
		__attrs = {}, __scripts = {}, __addonScript = {}, __calls = {}, __clicks = { down = false, up = true },
		__center = { 400, 300 }, __state = "NORMAL",
	}, Frame)
	if parent then frame.__level = parent.__level + 1 end
	if templates then
		for template in templates:gmatch("[^,%s]+") do
			local apply = TEMPLATES[template]
			if not apply then error("unknown template " .. template, 2) end
			apply(frame)
		end
	end
	if frame.__protected then
		if M.combat and insecure() then
			-- allowed in the real client, but nothing here should need it
			error("creating protected frames in combat is not expected", 2)
		end
		markAncestors(frame)
	end
	if name then
		assert(not M.frames[name], "duplicate frame name " .. name)
		M.frames[name] = frame
		_G[name] = frame
	end
	return frame
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent.__width = 1600

---------------------------------------------------------------------------
-- Clicks and keys
---------------------------------------------------------------------------
local function runScript(frame, name, ...)
	local fn = frame.__scripts[name]
	if not fn then return end
	local secureHandler = not frame.__addonScript[name] and (fn == SecureActionButton_OnClick or (name == "OnClick" and frame.__secureClick))
	if secureHandler then
		M.secure = M.secure + 1
		local ok, err = pcall(fn, frame, ...)
		M.secure = M.secure - 1
		if not ok then error(err, 0) end
	else
		fn(frame, ...)
	end
end

-- Delivers one half of a click (press or release) if the button is registered for it.
function M.Click(frame, button, down)
	if not ((down and frame.__clicks.down) or (not down and frame.__clicks.up)) then
		return false
	end
	runScript(frame, "PreClick", button, down)
	runScript(frame, "OnClick", button, down)
	runScript(frame, "PostClick", button, down)
	return true
end

-- A full mouse click on a visible, mouse-enabled button.
function M.MouseClick(frame, button)
	assert(frame:IsVisible(), "cannot click a hidden frame")
	M.Click(frame, button or "LeftButton", true)
	M.Click(frame, button or "LeftButton", false)
end

-- A button standing in for Shift, Ctrl or Alt does not report a press while it is held.
local function isModifierStandIn(key)
	for _, name in ipairs({ "GamePadEmulateShift", "GamePadEmulateCtrl", "GamePadEmulateAlt" }) do
		if M.cvars[name] == key then return true end
	end
	return false
end

function M.KeyDown(key)
	if isModifierStandIn(key) then
		M.held[key] = false
		return "modifier"
	end
	local binding = M.bindings[key]
	M.held[key] = binding or false
	if not binding then return "unbound" end
	if binding.kind == "click" then
		M.Click(assert(M.frames[binding.target], "binding to unknown frame " .. binding.target), binding.button or "LeftButton", true)
	else
		M.commands[#M.commands + 1] = { binding.target, "down" }
	end
end

-- The release goes to whatever the key was bound to when it was pressed.
function M.KeyUp(key)
	local binding = M.held[key]
	M.held[key] = nil
	if not binding then return "unbound" end
	if binding.kind == "click" then
		M.Click(M.frames[binding.target], binding.button or "LeftButton", false)
	else
		M.commands[#M.commands + 1] = { binding.target, "up" }
	end
end

function M.Tap(key)
	local result = M.KeyDown(key)
	M.KeyUp(key)
	return result
end

function M.Fire(event, ...)
	for _, frame in ipairs(M.events[event] or {}) do
		frame.__scripts.OnEvent(frame, event, ...)
	end
end

function M.EnterCombat()
	M.Fire("PLAYER_REGEN_DISABLED") -- still out of lockdown while this event is handled
	M.combat = true
end

function M.LeaveCombat()
	M.combat = false
	M.Fire("PLAYER_REGEN_ENABLED")
end

---------------------------------------------------------------------------
-- Bindings
---------------------------------------------------------------------------
local function bindGuard(what)
	if M.combat and insecure() then error("BLOCKED: " .. what .. " in combat", 3) end
end

function SetOverrideBindingClick(owner, priority, key, name, button)
	bindGuard("SetOverrideBindingClick")
	assert(type(key) == "string" and key ~= "", "bad key")
	M.bindings[key] = { owner = owner, kind = "click", target = name, button = button }
end

function SetOverrideBinding(owner, priority, key, command)
	bindGuard("SetOverrideBinding")
	assert(type(key) == "string" and key ~= "", "bad key")
	M.bindings[key] = command and { owner = owner, kind = "cmd", target = command } or nil
end

function ClearOverrideBindings(owner)
	bindGuard("ClearOverrideBindings")
	for key, binding in pairs(M.bindings) do
		if binding.owner == owner then M.bindings[key] = nil end
	end
end

function GetBindingAction(key) return M.userBindings and M.userBindings[key] or "" end
function GetBindingName(command) return "<" .. command .. ">" end

---------------------------------------------------------------------------
-- State drivers
---------------------------------------------------------------------------
function RegisterAttributeDriver(frame, attribute, values)
	bindGuard("RegisterAttributeDriver")
	UnregisterAttributeDriver(frame, attribute)
	M.drivers[#M.drivers + 1] = { frame = frame, attribute = attribute, values = values }
end

function UnregisterAttributeDriver(frame, attribute)
	bindGuard("UnregisterAttributeDriver")
	for i = #M.drivers, 1, -1 do
		if M.drivers[i].frame == frame and M.drivers[i].attribute == attribute then table.remove(M.drivers, i) end
	end
end

-- What the client does on its next update: evaluate every driver and set changed attributes.
function M.RunDrivers()
	for _, driver in ipairs(M.drivers) do
		local result
		for clause in (driver.values .. ";"):gmatch("%s*([^;]+);") do
			local condition, value = clause:match("^%[(.-)%]%s*(.+)$")
			if not condition then
				result = clause
				break
			end
			local bar = tonumber(condition:match("^bonusbar:(%d+)$"))
			assert(bar, "mock only understands [bonusbar:N], got " .. condition)
			if bar == M.bonusbar then
				result = value
				break
			end
		end
		result = result and result:match("^%s*(.-)%s*$")
		if driver.frame.__attrs[driver.attribute] ~= result then
			M.secure = M.secure + 1
			driver.frame:SetAttribute(driver.attribute, result)
			M.secure = M.secure - 1
		end
	end
end


---------------------------------------------------------------------------
-- Action bar API
---------------------------------------------------------------------------
local function valid(slot)
	if type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > 360 then
		error("invalid action slot: " .. tostring(slot), 3)
	end
	return M.actions[slot]
end

C_ActionBar = {
	GetBonusBarOffset = function() return M.bonusbar end,
	HasAction = function(slot) return valid(slot) ~= nil end,
	GetActionTexture = function(slot) local a = valid(slot); return a and a.texture end,
	IsUsableAction = function(slot) local a = valid(slot); return a and a.usable ~= false or false, a and a.noMana or false end,
	GetActionCooldown = function(slot)
		local a = valid(slot)
		local cd = a and a.cooldown
		return { startTime = cd and cd[1] or 0, duration = cd and cd[2] or 0, modRate = 1, isActive = cd ~= nil, isEnabled = true }
	end,
	GetActionDisplayCount = function(slot) local a = valid(slot); return a and a.count or "" end,
	IsCurrentAction = function(slot) local a = valid(slot); return a and a.current or false end,
	IsAutoRepeatAction = function(slot) valid(slot); return false end,
	IsEquippedAction = function(slot) local a = valid(slot); return a and a.equipped or false end,
	UsesActionText = function(slot) local a = valid(slot); return a and a.text ~= nil or false end,
	GetActionText = function(slot) local a = valid(slot); return a and a.text end,
	EnableActionRangeCheck = function(slot, enable)
		valid(slot)
		M.rangeRefs[slot] = (M.rangeRefs[slot] or 0) + (enable and 1 or -1)
		assert(M.rangeRefs[slot] >= 0, "range check disabled more often than enabled for slot " .. slot)
	end,
}

C_GamepadUI = {
	GetFirstGamepadActionStorageSlotIndex = function() return M.firstGamepadSlot end,
	IsValidGamepadActionStorageSlotIndex = function(slot) return slot >= M.firstGamepadSlot and slot <= M.lastGamepadSlot end,
	GetFirstGamepadActionBarStorageSlotIndexForActiveStance = function()
		return M.bonusbar > 0 and (M.firstGamepadSlot + 84 + (M.bonusbar - 1) * 8) or nil
	end,
}

function PickupAction(slot)
	if M.combat and insecure() then error("BLOCKED: PickupAction in combat", 2) end
	M.picked[#M.picked + 1] = slot
	M.cursor = "action"
end
function PlaceAction(slot)
	if M.combat and insecure() then error("BLOCKED: PlaceAction in combat", 2) end
	M.placed[#M.placed + 1] = slot
	M.cursor = nil
end
function GetCursorInfo() return M.cursor end
function IsModifiedClick(action) return action == "PICKUPACTION" and M.pickupModifier end

---------------------------------------------------------------------------
-- Everything else
---------------------------------------------------------------------------
function InCombatLockdown() return M.combat end
function GetCVar(name) return M.cvars[name] end
function SetCVar(name, value)
	assert(M.cvars[name] ~= nil, "unknown cvar " .. tostring(name))
	if M.combat and insecure() then error("BLOCKED: SetCVar in combat", 2) end
	M.cvars[name] = M.floatCVars[name] and ("%.6f"):format(tonumber(value)) or tostring(value)
end
function GetCVarBool(name) return M.cvars[name] == "1" end
function GetBuildInfo() return "1.60.1", "70888", "Nov 10 2026", 16001 end

C_AddOns = { GetAddOnMetadata = function(_, field) return field == "Version" and "test" or nil end }
Enum = { InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 } }
C_InputInterfaceStyle = { GetCurrentStyle = function() return M.gamepadUI and 1 or 0 end }
C_GamePad = {
	IsEnabled = function() return M.cvars.GamePadEnable == "1" end,
	GetAllDeviceIDs = function() return { 1 } end,
	GetActiveDeviceID = function() return 1 end,
	GetDeviceMappedState = function() return { labelStyle = M.labelStyle or "Letters" } end,
}
function SetGamePadCursorControl(enabled) M.cursorControl = enabled end
function IsGamePadCursorControlEnabled() return M.cursorControl end

Settings = {
	GetValue = function(name) assert(name == "lockActionBars"); return M.lockActionBars end,
	RegisterCanvasLayoutCategory = function(frame, name) return { GetID = function() return name end, frame = frame } end,
	RegisterAddOnCategory = function(category) M.category = category end,
	OpenToCategory = function(id) M.opened[#M.opened + 1] = id end,
}

GameTooltip = { owner = nil, lines = {} }
function GameTooltip:SetOwner(owner) self.owner = owner; self.lines = {} end
function GameTooltip:GetOwner() return self.owner end
function GameTooltip:SetText(text) self.lines = { text } end
function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function GameTooltip:SetAction(slot) self.lines = { "action " .. slot }; return M.actions[slot] ~= nil end
function GameTooltip:Show() self.shown = true end
function GameTooltip:Hide() self.shown = false; self.owner = nil end
function GameTooltip_SetDefaultAnchor(tooltip, owner) tooltip:SetOwner(owner) end

UIErrorsFrame = { AddMessage = function(_, text) M.errors[#M.errors + 1] = text end }
SlashCmdList = {}

function print(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
	M.printed[#M.printed + 1] = table.concat(parts, " ")
end

function strtrim(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(separator, text)
	local out = {}
	for part in (text .. separator):gmatch("(.-)" .. separator:gsub("%p", "%%%0")) do out[#out + 1] = part end
	return unpack(out)
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function CopyTable(t)
	local copy = {}
	for k, v in pairs(t) do copy[k] = type(v) == "table" and CopyTable(v) or v end
	return copy
end
