-- A small stand-in for the parts of the WoW client that FreeControl touches, strict enough to
-- catch real mistakes:
--
--   * frames only have the widget methods listed here, so a misspelt method is an error;
--   * protected frames refuse protected calls from addon code while "in combat";
--   * secure snippets run in a restricted environment (no tables, no functions, no addon globals)
--     against frame handles that only expose what the real restricted environment exposes;
--   * key presses are routed through override bindings to button clicks the way the client does,
--     honouring RegisterForClicks and delivering both press and release;
--   * in combat the cooldown API hands addon code sealed ("secret") numbers, which cooldown
--     frames refuse from addon code, as Blizzard's API documentation says the client does;
--   * an error the addon reports to the game's error handler fails the test that caused it;
--   * while the stick pointer is out, the two buttons named by the click console variables are
--     mouse buttons: a real click over the interface, the button's own binding over the world;
--   * using the controller puts the client in camera mode ("free look"), in which the pointer is
--     hidden even if a stick has been told to steer it. FreeControl 1.2.0 asked for the pointer
--     without ending camera mode, and a player pressing its button saw nothing;
--   * learning a new rank of a spell changes the spell book and nothing else: the controller's
--     slots keep the rank they hold, which is what players saw up to FreeControl 1.3.2. A slot is
--     filled through the cursor, outside combat, as a hand would fill it.
--   * a character has the stances or forms of its class (M.FORMS, the classic rules). Changing
--     form changes which stance bar is up for the forms that have one, announces it the way the
--     client does, and the state drivers follow on the client's next update;
--   * a key with none of the addon's override bindings on it runs the player's own binding, which
--     is saved the way the Key Bindings screen saves one and cannot be changed in a fight.
--
-- The secure click logic is a port of SecureActionButton_OnClick from Blizzard_FrameXML/
-- SecureTemplates.lua (build 1.60.1). It is a model of the client, not the client: a pass here
-- shows the addon's own logic is consistent, not that the game agrees with the model.

local M = {
	combat = false,
	secure = 0,            -- > 0 while Blizzard (secure) code is running
	bonusbar = 0,          -- the stance (bonus) bar that is up: what [bonusbar:N] and GetBonusBarOffset go by
	form = 0,              -- the shapeshift form the character is in: what [form:N] goes by
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
		GamePadCursorSpeedStart = "0.1", GamePadCursorSpeedAccel = "2", GamePadCursorSpeedMax = "1",
		GamePadCursorCentering = "0", GamePadCursorCenteredEmulation = "1", GamePadCursorAutoEnable = "1",
		GamePadCursorAutoDisableSticks = "2", GamePadCursorAutoDisableJump = "1", GamePadCursorForTargeting = "1",
		SoftTargetEnemy = "1", SoftTargetEnemyArc = "2", SoftTargetForce = "1",
		GamePadEmulateShift = "PADLTRIGGER", GamePadEmulateCtrl = "PADLSHOULDER", GamePadEmulateAlt = "none",
	},
	floatCVars = { SoftTargetInteractRange = true }, -- the client stores these as "20.000000"
	actions = {},          -- [slot] = { texture, usable, noMana, cooldown, count, current, equipped, text }
	used = {},             -- UseAction calls: { slot, unit, button }
	commands = {},         -- binding commands run: { name, "down" | "up" }
	units = {},            -- [unit] = true for the units there are besides the player: "party2"
	targeted = {},         -- the units secure "target" buttons targeted, in order
	bindings = {},         -- override bindings: [key] = { owner, kind = "click" | "cmd", target, button }
	userBindings = {},     -- the player's own key bindings: [key] = command, as the Key Bindings screen sets them
	savedBindings = {},    -- SaveBindings calls: the binding set each one saved
	refuseBinding = false, -- a client that will not make a binding
	held = {},             -- [key] = the binding it was pressed with
	mods = {},             -- [ALT | CTRL | SHIFT] = the key or controller button holding that modifier down
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
	cursorControl = false, -- a stick has been told to steer the mouse pointer
	freeLook = false,      -- the controller is steering the camera, which hides the pointer
	refuseCursor = 0,      -- how many more requests for the stick pointer the client ignores
	pointerCalls = {},     -- what the addon asked of the pointer and the camera, in order
	cursorOver = "interface", -- what the pointer is over while it is out: "interface" or "world"
	class = "ROGUE",       -- the player's class, as UnitClass names it
	itemQuality = {},      -- [item id] = rarity, for the items the client has loaded
	sealActionInfo = false, -- a client that seals what is in a slot while restrictions are in force
	book = {},             -- the spell book: { spell =, name =, low = true for a lower rank, passive =, offSpec = }
	spellNames = {},       -- [spell id] = name, for spells that are not in the book
	overlayed = {},        -- [spell id] = true while the game says the spell has procced
	stealthed = false,
	guid = "Player-1-00000001",
	refusePlace = false,   -- a client that will not take what is dropped on a slot
	refusePickup = false,  -- a client that will not hand over a spell from the spell book
	timers = {},           -- C_Timer.After calls waiting: { due =, fn = }
	clicks = {},           -- mouse clicks the client made out of controller buttons: { button, "down" | "up" }
	secretRestrictions = true, -- the client seals cooldown numbers from addons while in combat
	cooldownEvents = { "SPELL_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN" }, -- raised when one starts
	luaErrors = {},        -- what reached the game's error handler
	down = {},             -- [key] = true while the key is physically held
	all = {},              -- every frame, for M.Advance
	now = 100,             -- seconds on the game's clock
}
Mock = M

local function insecure()
	return M.secure == 0
end

---------------------------------------------------------------------------
-- Sealed ("secret") values
---------------------------------------------------------------------------
-- While addon restrictions are in force (modelled as: in combat, on a client that has them) the
-- cooldown API hands addon code sealed numbers. Addon code may store them and pass them on.
-- Calculating with one, ordering it, indexing it or joining it to a string is an error, as is
-- handing it to a game function that does not accept sealed values from addon code. (The real
-- client also refuses == on them and allows joining; Lua 5.1 cannot model the first, and the
-- addon is held to the stricter rule on the second.)
local sealedValue = setmetatable({}, { __mode = "k" }) -- [sealed] = what is inside
local SEALED = {
	__index = function() error("attempted to index a sealed value", 2) end,
	__newindex = function() error("attempted to index a sealed value", 2) end,
	__tostring = function() return "<sealed>" end,
}
local function Seal(value)
	local sealed = setmetatable({}, SEALED)
	sealedValue[sealed] = value
	return sealed
end
local function IsSealed(value) return type(value) == "table" and getmetatable(value) == SEALED end
local function Unseal(value)
	if IsSealed(value) then return sealedValue[value] end
	return value
end
local function restricted() return M.secretRestrictions and M.combat end
M.Seal, M.Unseal, M.IsSealed = Seal, Unseal, IsSealed

function issecretvalue(value) return IsSealed(value) end
C_Secrets = {
	HasSecretRestrictions = function() return M.secretRestrictions end,
	ShouldCooldownsBeSecret = function() return restricted() and true or false end,
}

-- Carries a cooldown's timing to a cooldown frame without exposing it. Addon code can do
-- nothing with one except hand it over.
local durationTiming = setmetatable({}, { __mode = "k" }) -- [object] = { start, duration, sealed }
local DURATION = {
	__index = function(_, key) error("this model's duration objects have no '" .. tostring(key) .. "'", 2) end,
	__tostring = function() return "LuaDurationObject" end,
}
local function NewDuration(start, duration)
	local object = setmetatable({}, DURATION)
	durationTiming[object] = { start = start, duration = duration, sealed = restricted() }
	return object
end

---------------------------------------------------------------------------
-- Regions
---------------------------------------------------------------------------
local Region = {}
Region.__index = Region
for _, name in ipairs({ "SetPoint", "ClearAllPoints", "SetAllPoints", "SetSize", "SetWidth", "SetHeight",
	"SetTexCoord", "SetVertexColor", "SetBlendMode", "AddMaskTexture", "SetColorTexture", "SetDrawLayer",
	"SetWordWrap", "SetJustifyH", "SetFontObject",
	-- What the chat keyboard and the quick phrases window draw with (the Chat folder).
	"SetFont", "SetShadowOffset", "SetShadowColor", "SetTextColor", "SetJustifyV", "SetMaxLines", "SetRotation",
	"SetGradient", "SetHorizTile", "SetVertTile", "SetThickness", "SetStartPoint", "SetEndPoint" }) do
	Region[name] = function(self, ...) self.calls[name] = { ... } end
end
-- Every picture the addon asks for is noted, so a test can check that the file is there: a
-- texture the game cannot find is drawn as a bright green square.
M.textures = {}
local function noteTexture(texture)
	if type(texture) == "string" then M.textures[texture] = true end
	return texture
end
function Region:SetTexture(texture, ...) self.texture = noteTexture(texture) end
function Region:GetTexture() return self.texture end
-- One of the game's own pictures, by name. Only the ones in M.atlases exist (C_Texture.GetAtlasInfo).
function Region:SetAtlas(name)
	assert(M.atlases[name], "no such atlas: " .. tostring(name))
	self.atlas = name
end
-- How wide a text is drawn: this model's letters are all 7 wide.
function Region:GetStringWidth() return #(self.text or "") * 7 end
function Region:SetAlpha(alpha) self.alpha = alpha end
function Region:GetAlpha() return self.alpha end
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:SetShown(shown) self.shown = shown and true or false end
function Region:IsShown() return self.shown end
function Region:SetText(text) self.text = text end
-- The client has no text to give back for a font string that was never given any, or was given
-- the empty string: it answers nil, not "". (FreeControl 1.5.0 took that answer for a title.)
function Region:GetText()
	if self.text == "" then return nil end
	return self.text
end

-- Animations: only what is played matters here, not how it looks.
local Animation = {}
Animation.__index = Animation
for _, name in ipairs({ "SetFromAlpha", "SetToAlpha", "SetDuration", "SetSmoothing" }) do
	Animation[name] = function(self, ...) self.calls[name] = { ... } end
end
local AnimationGroup = {}
AnimationGroup.__index = AnimationGroup
function AnimationGroup:SetLooping(kind) self.looping = kind end
function AnimationGroup:CreateAnimation(kind)
	local animation = setmetatable({ kind = kind, calls = {} }, Animation)
	self.animations[#self.animations + 1] = animation
	return animation
end
function AnimationGroup:Play() self.playing = true end
function AnimationGroup:Stop() self.playing = false end
function AnimationGroup:IsPlaying() return self.playing end
function Region:CreateAnimationGroup()
	return setmetatable({ animations = {}, playing = false }, AnimationGroup)
end

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
-- A frame that becomes visible or stops being so has its OnShow or OnHide script run.
local function setShown(self, shown)
	if self.__shown == shown then return end
	self.__shown = shown
	local fn = self.__scripts[shown and "OnShow" or "OnHide"]
	if fn then fn(self) end
end
function Frame:Show() guard(self, "Show"); setShown(self, true) end
function Frame:Hide() guard(self, "Hide"); setShown(self, false) end
function Frame:SetShown(shown) guard(self, "SetShown"); setShown(self, shown and true or false) end
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
	self:UnregisterEvent(event)
	M.events[event] = M.events[event] or {}
	table.insert(M.events[event], self)
end
-- Only delivered when the event's first value is this unit.
function Frame:RegisterUnitEvent(event, unit)
	self:RegisterEvent(event)
	self.__unitEvents = self.__unitEvents or {}
	self.__unitEvents[event] = unit
end
function Frame:UnregisterEvent(event)
	local frames = M.events[event] or {}
	for i = #frames, 1, -1 do
		if frames[i] == self then table.remove(frames, i) end
	end
	if self.__unitEvents then self.__unitEvents[event] = nil end
end
function Frame:UnregisterAllEvents()
	for event in pairs(M.events) do self:UnregisterEvent(event) end
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
local RunSnippet, Handle

function Frame:SetAttribute(name, value)
	guard(self, "SetAttribute")
	self.__attrs[name] = value
	-- SecureHandlerStateTemplate (port of SecureHandler_StateOnAttributeChanged): a "state-<id>"
	-- attribute runs the frame's "_onstate-<id>" snippet with the new value.
	local stateid = self.__stateHandler and type(name) == "string" and name:match("^state%-(.+)")
	if stateid then
		local body = self.__attrs["_onstate-" .. stateid]
		if body then
			RunSnippet(self, "self,stateid,newstate", body, Handle(self), stateid, value)
		end
	end
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
function Frame:CreateFontString()
	local region = NewRegion("FontString")
	self.__texts = self.__texts or {}
	self.__texts[#self.__texts + 1] = region
	return region
end

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
function Frame:SetNormalTexture(texture) self.__normal = NewRegion("Texture"); self.__normal.texture = noteTexture(texture) end
function Frame:GetNormalTexture() return self.__normal end
function Frame:SetPushedTexture(texture) self.__pushed = NewRegion("Texture"); self.__pushed.texture = noteTexture(texture) end
function Frame:GetPushedTexture() return self.__pushed end
function Frame:SetHighlightTexture(texture, mode) self.__highlight = noteTexture(texture) end
function Frame:SetCheckedTexture(texture) self.__checkedTexture = NewRegion("Texture"); self.__checkedTexture.texture = noteTexture(texture) end
function Frame:GetCheckedTexture() return self.__checkedTexture end
function Frame:SetChecked(checked) self.__checked = checked and true or false end
function Frame:GetChecked() return self.__checked end
function Frame:SetButtonState(state) self.__state = state end
function Frame:GetButtonState() return self.__state end
function Frame:SetText(text) self.__text = text end
function Frame:GetText()
	if self.__text == "" then return nil end
	return self.__text
end

-- Edit boxes
for _, name in ipairs({ "SetMultiLine", "SetAutoFocus", "SetFontObject", "HighlightText", "SetFont", "SetTextColor",
	"SetTextInsets", "SetMaxLetters" }) do
	Frame[name] = function(self, ...) self.__calls[name] = { ... } end
end
-- One edit box at a time is being typed in (M.focus), and a box is told when it becomes that one
-- and when it stops being it, as the client tells it.
function Frame:SetFocus()
	self.__calls.SetFocus = {}
	if M.focus == self then return end
	if M.focus then M.focus:ClearFocus() end
	M.focus = self
	local fn = self.__scripts.OnEditFocusGained
	if fn then fn(self) end
end
function Frame:ClearFocus()
	self.__calls.ClearFocus = {}
	if M.focus ~= self then return end
	M.focus = nil
	local fn = self.__scripts.OnEditFocusLost
	if fn then fn(self) end
end
function Frame:HasFocus() return M.focus == self end

-- What the chat keyboard's frames ask of the client (the Chat folder). A frame made without a
-- parent and given one afterwards is that parent's child from then on. Nothing here is laid out:
-- a frame has no place on the screen to report (GetLeft answers nothing), as one that has not
-- been drawn yet has none in the client.
function Frame:SetParent(parent)
	guard(self, "SetParent")
	self.__parent = parent
	if parent then self.__level = parent.__level + 1 end
	if self.__protected then markAncestors(self) end
end
function Frame:GetHeight() return self.__height or 0 end
function Frame:GetLeft() return nil end
function Frame:GetBottom() return nil end
function Frame:GetEffectiveScale() return self.__scale end
function Frame:GetPoint()
	local call = self.__calls.SetPoint
	if call then return unpack(call, 1, 5) end
end
function Frame:Raise() self.__raised = (self.__raised or 0) + 1 end
function Frame:IsMouseOver() return M.mouseOver == self end
-- A frame that asked for the sticks is told where they are (the scenario runs its OnGamePadStick).
function Frame:EnableGamePadStick(enable) guard(self, "EnableGamePadStick"); self.__sticks = enable and true or false end
function Frame:CreateLine() return NewRegion("Line") end

-- A frame that asked for the keyboard or the controller's buttons gets every press while it is
-- on screen, before any binding (M.KeyDown). Both calls are protected on a protected frame.
function Frame:EnableKeyboard(enable) guard(self, "EnableKeyboard"); self.__keyboard = enable and true or false end
function Frame:EnableGamePadButton(enable) guard(self, "EnableGamePadButton"); self.__gamepad = enable and true or false end
function Frame:SetEnabled(enabled) self.__enabled = enabled and true or false end
function Frame:IsEnabled() return self.__enabled ~= false end

-- Cooldown frames. Blizzard's documentation marks the setters that take numbers as accepting
-- sealed ones from Blizzard's own code only (SecretArguments = "AllowedWhenUntainted"), so addon
-- code has to hand over a duration object instead. A frame that was given sealed timing seals
-- what it reports about itself from then on. Tests look at __cooldown, which the addon cannot.
local function refuseSealed(what, ...)
	if not insecure() then return end
	for i = 1, select("#", ...) do
		if IsSealed((select(i, ...))) then
			error(what .. ": secret values are only allowed during untainted execution for this argument", 3)
		end
	end
end
function Frame:SetCooldown(start, duration, modRate)
	assert(self.__kind == "Cooldown", "SetCooldown on something that is not a cooldown frame")
	refuseSealed("Cooldown:SetCooldown", start, duration, modRate)
	self.__sealed = self.__sealed or IsSealed(start) or IsSealed(duration)
	self.__cooldown = { Unseal(start), Unseal(duration), Unseal(modRate) }
end
function Frame:SetCooldownFromDurationObject(object, clearIfZero)
	assert(self.__kind == "Cooldown", "SetCooldownFromDurationObject on something that is not a cooldown frame")
	local timing = durationTiming[object]
	if not timing then error("SetCooldownFromDurationObject wants a duration object, got " .. tostring(object), 2) end
	if timing.duration == 0 and clearIfZero ~= false then
		return self:Clear()
	end
	self.__sealed = self.__sealed or timing.sealed
	self.__cooldown = { timing.start, timing.duration, 1 }
end
function Frame:Clear() self.__cooldown = nil end
function Frame:GetCooldownDuration() -- milliseconds
	local duration = self.__cooldown and self.__cooldown[2] * 1000 or 0
	if self.__sealed and insecure() then return Seal(duration) end
	return duration
end
for _, name in ipairs({ "SetDrawEdge", "SetDrawBling", "SetSwipeColor", "SetSwipeTexture", "SetUseCircularEdge",
	"SetHideCountdownNumbers", "SetMinimumCountdownDuration" }) do
	Frame[name] = function(self, ...) self.__calls[name] = { ... } end
end

---------------------------------------------------------------------------
-- Restricted environment
---------------------------------------------------------------------------
local RESTRICTED = {
	math = math, string = string, select = select, tonumber = tonumber, tostring = tostring, type = type,
	format = string.format, strsub = string.sub, strlen = string.len, floor = math.floor, max = math.max, min = math.min,
	-- Blizzard_RestrictedAddOnEnvironment/RestrictedEnvironment.lua lets snippets ask this.
	UnitExists = function(unit) return unit == "player" or M.units[unit] == true end,
}

function Handle(frame)
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
	function h:IsShown() return target():IsShown() end
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
	-- Port of SecureHandlerWrapScript for a body that runs before the script it wraps: the body
	-- gets the wrapped frame as self and this frame as control, runs as secure code, and the
	-- frame's own script follows. (A body that returns false to stop the script is not modelled.)
	function frame:WrapScript(wrapped, name, body)
		if M.combat then error("Cannot call WrapScript in combat", 2) end
		assert(wrapped.__protected, "only an explicitly protected frame can be wrapped")
		assert(name == "OnClick", "mock only wraps OnClick")
		local original = assert(wrapped.__scripts[name], "nothing to wrap")
		local control = Handle(self)
		wrapped.__scripts[name] = function(button, inputButton, down, ...)
			RunSnippet(button, "self,control,button,down", body, Handle(button), control, inputButton, down)
			return original(button, inputButton, down, ...)
		end
		wrapped.__secureClick = true
	end
end

---------------------------------------------------------------------------
-- Secure action buttons (port of Blizzard's SecureActionButton_OnClick, type "action" only)
---------------------------------------------------------------------------
-- An ability's own cooldown begins, and the client announces it. Which events it raises for
-- which kind of cooldown is not something this model knows, so a test can narrow
-- M.cooldownEvents to check that any one of them is enough.
function M.StartCooldown(slot, duration)
	M.actions[slot].cooldown = { M.now, duration }
	local depth = M.secure
	M.secure = 0 -- event handlers are addon code: they run tainted, whatever raised the event
	for _, event in ipairs(M.cooldownEvents) do
		if event == "SPELL_UPDATE_COOLDOWN" then
			M.Fire(event, M.actions[slot].spell or slot)
		else
			M.Fire(event)
		end
	end
	M.secure = depth
end

function UseAction(slot, unit, button)
	slot = tonumber(slot)
	if M.combat and insecure() then error("BLOCKED: UseAction from tainted code in combat", 2) end
	if M.cursor then
		M.placed[#M.placed + 1] = slot
		M.cursor = nil
		return
	end
	M.used[#M.used + 1] = { slot = slot, unit = unit, button = button }
	local action = M.actions[slot]
	if action and action.cooldownOnUse then
		M.StartCooldown(slot, action.cooldownOnUse)
	end
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
		if self:GetAttribute("type") == "target" then
			-- SECURE_ACTIONS.target: a button with no unit targets nothing.
			local unit = self:GetAttribute("unit")
			if unit then M.targeted[#M.targeted + 1] = unit end
			return true
		end
		if self:GetAttribute("type") == "togglemenu" then
			-- SECURE_ACTIONS.togglemenu: the game's own menu for the button's unit, at the pointer.
			M.menusOpened = M.menusOpened or {}
			M.menusOpened[#M.menusOpened + 1] = self:GetAttribute("unit")
			return true
		end
		if self:GetAttribute("type") == "macro" then
			-- SECURE_ACTIONS.macro: the button's own text is run, line by line, as a macro's is.
			local text = self:GetAttribute("macrotext")
			if text and text ~= "" then M.RunMacroText(text) end
			return true
		end
		assert(self:GetAttribute("type") == "action", "mock only models type=action, type=target and type=macro")
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
	SecureHandlerStateTemplate = function(f) f.__protected = true; f.__stateHandler = true; addHandlerMethods(f) end,
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
	-- A tooltip of the addon's own. What it was asked to show is kept for the scenarios.
	GameTooltipTemplate = function(f)
		f.__shown = false
		function f:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
	end,
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
	M.all[#M.all + 1] = frame
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

-- True unless the frame was told not to answer the mouse (EnableMouse(false)).
function M.TakesMouse(frame)
	local call = frame.__calls.EnableMouse
	return not (call and call[1] == false)
end

-- A full mouse click on a visible, mouse-enabled button.
function M.MouseClick(frame, button)
	assert(frame:IsVisible(), "cannot click a hidden frame")
	assert(M.TakesMouse(frame), "cannot click a frame that does not take the mouse")
	M.Click(frame, button or "LeftButton", true)
	M.Click(frame, button or "LeftButton", false)
end

-- A button standing in for Shift, Ctrl or Alt does not report a press while it is held: it is
-- that modifier instead, as the key on the keyboard would be. Returns the modifier, or nil.
-- (The client does let a quick tap of such a button through as a press of its own, inside
-- GamePadEmulateTapWindowMs. This model never does, which is the worse case for a button that
-- was given a job: nothing here may rely on the tap.)
local STAND_INS = { { "GamePadEmulateAlt", "ALT" }, { "GamePadEmulateCtrl", "CTRL" }, { "GamePadEmulateShift", "SHIFT" } }
local KEYBOARD_MODIFIERS = { LALT = "ALT", RALT = "ALT", LCTRL = "CTRL", RCTRL = "CTRL", LSHIFT = "SHIFT", RSHIFT = "SHIFT" }

local function isModifierStandIn(key)
	for _, entry in ipairs(STAND_INS) do
		if M.cvars[entry[1]] == key then return entry[2] end
	end
	return nil
end

function IsAltKeyDown() return M.mods.ALT ~= nil end
function IsControlKeyDown() return M.mods.CTRL ~= nil end
function IsShiftKeyDown() return M.mods.SHIFT ~= nil end

-- The name a key has in a binding with the modifiers held right now: "ALT-CTRL-PADDRIGHT".
local function chordFor(key)
	local parts = {}
	for _, modifier in ipairs({ "ALT", "CTRL", "SHIFT" }) do
		if M.mods[modifier] then parts[#parts + 1] = modifier end
	end
	parts[#parts + 1] = key
	return table.concat(parts, "-")
end

-- The client's own mouse emulation, as ConsolePort describes it to its users (not confirmed in
-- play): while the stick cursor is out, the buttons named by GamePadCursorLeftClick and
-- GamePadCursorRightClick are the mouse buttons. Over the interface a press becomes a real mouse
-- click and the button's binding does not run. Over the world it goes to the binding as usual,
-- which is why a button has to be bound to the mouse commands to click things there.
local function clickButton(key)
	if not M.PointerVisible() or M.cursorOver ~= "interface" then return nil end
	if M.cvars.GamePadCursorLeftClick:upper() == key then return "LeftButton" end
	if M.cvars.GamePadCursorRightClick:upper() == key then return "RightButton" end
end

-- The pointer can be seen and used: a stick steers it and the client is not in camera mode.
function M.PointerVisible() return M.cursorControl and not M.freeLook end

-- The client brings the pointer out by itself (a window that needs it opened), or puts it away
-- (the character jumped).
function M.GameShowsPointer() M.freeLook = false; M.cursorControl = true end
function M.GameHidesPointer() M.cursorControl = false end

-- What a key by that exact name does: an override binding if there is one, else the player's own.
local function exactBinding(key)
	local binding = M.bindings[key]
	if binding then return binding end
	local command = M.userBindings and M.userBindings[key]
	if not command then return nil end
	local name, button = command:match("^CLICK (.-):(.+)$")
	if name then return { kind = "click", target = name, button = button } end
	return { kind = "cmd", target = command }
end

-- What a key does right now. With a modifier held the combination is looked for first, among
-- the overrides and the player's own bindings alike, and only a combination that has no binding
-- falls back to the key alone. That order is how the client is known to behave on a keyboard:
-- Shift + 2 turns the action bar page (a binding of the player's on SHIFT-2) under addons that
-- hold an override binding on 2. It has not been seen with a controller's stand-in buttons.
local function bindingFor(key)
	local chord = chordFor(key)
	return (chord ~= key and exactBinding(chord)) or exactBinding(key)
end

function M.KeyDown(key)
	M.down[key] = true
	-- A controller button standing in for a modifier is that modifier while it is held, and no
	-- press of its own as far as bindings go. Whether a frame that is listening for input is told
	-- of it is not known (the game's Key Bindings screen takes LB + D-pad as one combination, which
	-- suggests it is not). Here the frame is told, which is the harder case for a page that waits
	-- for a combination: it has to know a held button when it sees one.
	local standIn = isModifierStandIn(key)
	if standIn then
		if not M.cursorControl then M.freeLook = true end
		M.mods[standIn] = key
		M.held[key] = false
		for _, frame in ipairs(M.all) do
			local fn = frame.__gamepad and frame:IsVisible() and frame.__scripts.OnGamePadButtonDown
			if fn then
				fn(frame, key)
				break
			end
		end
		return "modifier"
	end
	if KEYBOARD_MODIFIERS[key] then M.mods[KEYBOARD_MODIFIERS[key]] = key end
	-- A frame listening for input takes the press, and no binding runs.
	for _, frame in ipairs(M.all) do
		local pad = key:find("^PAD") ~= nil
		if ((pad and frame.__gamepad) or (not pad and frame.__keyboard)) and frame:IsVisible() then
			local fn = frame.__scripts[pad and "OnGamePadButtonDown" or "OnKeyDown"]
			if fn then
				M.held[key] = false
				fn(frame, key)
				return "caught"
			end
		end
	end
	-- Using the controller puts the client in camera mode, unless a stick is steering the pointer.
	if key:find("^PAD") and not M.cursorControl then M.freeLook = true end
	local mouseButton = clickButton(key)
	if mouseButton then
		M.held[key] = { kind = "mouse", target = mouseButton }
		M.clicks[#M.clicks + 1] = { mouseButton, "down" }
		return "mouse"
	end
	local binding = bindingFor(key)
	M.held[key] = binding or false
	if not binding then return "unbound" end
	if binding.kind == "click" then
		M.Click(assert(M.frames[binding.target], "binding to unknown frame " .. binding.target), binding.button or "LeftButton", true)
	else
		M.commands[#M.commands + 1] = { binding.target, "down" }
		-- The game's own commands are run by the game: the ones for the stance bar change stance.
		local form = tonumber(binding.target:match("^SHAPESHIFTBUTTON(%d+)$"))
		if form then
			M.secure = M.secure + 1
			local ok, err = pcall(CastShapeshiftForm, form)
			M.secure = M.secure - 1
			if not ok then error(err, 0) end
		end
	end
end

-- The release goes to whatever the key was bound to when it was pressed.
function M.KeyUp(key)
	M.down[key] = nil
	for modifier, holder in pairs(M.mods) do
		if holder == key then M.mods[modifier] = nil end
	end
	local binding = M.held[key]
	M.held[key] = nil
	if not binding then return "unbound" end
	if binding.kind == "mouse" then
		M.clicks[#M.clicks + 1] = { binding.target, "up" }
	elseif binding.kind == "click" then
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

function IsKeyDown(key) return M.down[key] or false end

-- Lets time pass: runs the OnUpdate script of every visible frame that has one.
function M.Advance(seconds)
	M.now = M.now + seconds
	local due = {}
	for i = #M.timers, 1, -1 do
		if M.timers[i].due <= M.now then table.insert(due, 1, table.remove(M.timers, i).fn) end
	end
	for _, fn in ipairs(due) do fn() end
	for _, frame in ipairs(M.all) do
		local fn = frame.__scripts.OnUpdate
		if fn and frame:IsVisible() then fn(frame, seconds) end
	end
end

C_Timer = {
	After = function(seconds, fn)
		assert(type(seconds) == "number" and type(fn) == "function", "C_Timer.After(seconds, function)")
		M.timers[#M.timers + 1] = { due = M.now + seconds, fn = fn }
	end,
}

function M.Fire(event, ...)
	local frames = {}
	for i, frame in ipairs(M.events[event] or {}) do frames[i] = frame end -- handlers may unregister
	for _, frame in ipairs(frames) do
		local unit = frame.__unitEvents and frame.__unitEvents[event]
		if unit == nil or unit == (...) then
			frame.__scripts.OnEvent(frame, event, ...)
		end
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

-- An override binding belongs to the frame that made it, and a key can have one from each of
-- several frames at once: the one made last is the one in force (M.bindings), and when its frame
-- takes it back the one before it is in force again. That is how the chat keyboard borrows the
-- bar's keys while it is open and hands them back by clearing its own (Chat/Input.lua). The order
-- among owners is this model's reading of the client, not something seen in its code.
M.overrides = {}           -- [key] = every frame's override on it, oldest first

local function setOverride(owner, key, binding)
	local list = M.overrides[key] or {}
	M.overrides[key] = list
	for i = #list, 1, -1 do
		if list[i].owner == owner then table.remove(list, i) end
	end
	if binding then list[#list + 1] = binding end
	M.bindings[key] = list[#list]
end

function SetOverrideBindingClick(owner, priority, key, name, button)
	bindGuard("SetOverrideBindingClick")
	assert(type(key) == "string" and key ~= "", "bad key")
	setOverride(owner, key, { owner = owner, kind = "click", target = name, button = button })
end

function SetOverrideBinding(owner, priority, key, command)
	bindGuard("SetOverrideBinding")
	assert(type(key) == "string" and key ~= "", "bad key")
	setOverride(owner, key, command and { owner = owner, kind = "cmd", target = command } or nil)
end

function ClearOverrideBindings(owner)
	bindGuard("ClearOverrideBindings")
	for key in pairs(M.overrides) do
		setOverride(owner, key, nil)
	end
end

-- With checkOverride, an override binding on the key wins over the player's own.
function GetBindingAction(key, checkOverride)
	local override = checkOverride and M.bindings[key]
	if override then
		return override.kind == "cmd" and override.target or ("CLICK " .. override.target .. ":" .. (override.button or "LeftButton"))
	end
	return M.userBindings and M.userBindings[key] or ""
end
-- The name a command has in the Key Bindings screen: the global the addon or the game gave it.
function GetBindingName(command) return _G["BINDING_NAME_" .. command] or ("<" .. command .. ">") end

-- The keys the player has bound to a command, in a fixed order.
function GetBindingKey(command)
	local keys = {}
	for key, bound in pairs(M.userBindings or {}) do
		if bound == command then keys[#keys + 1] = key end
	end
	table.sort(keys)
	return unpack(keys)
end

-- The commands the Key Bindings screen lists, each with the keys bound to it: the game's own
-- commands, and those an addon's Bindings.xml adds. A binding to anything else (a click on a
-- frame the addon made, a spell, a macro) is as much the player's own, but is not in this list.
local function listedCommands()
	local seen, list = {}, {}
	local function add(command)
		if not seen[command] then
			seen[command] = true
			list[#list + 1] = command
		end
	end
	for name in ReadFile("FreeControl/Bindings.xml"):gmatch('<Binding name="([^"]+)"') do add(name) end
	for _, command in pairs(M.userBindings or {}) do
		if not command:find(" ") then add(command) end
	end
	table.sort(list)
	return list
end

function GetNumBindings() return #listedCommands() end
function GetBinding(index)
	local command = listedCommands()[index]
	if not command then return nil end
	return command, "category", GetBindingKey(command)
end

-- One of the player's own bindings is made or (with no command) taken away. Nothing is kept
-- past the session until SaveBindings.
function SetBinding(key, command)
	bindGuard("SetBinding")
	assert(type(key) == "string" and key ~= "", "bad key")
	assert(command == nil or (type(command) == "string" and command ~= ""), "a binding is a command name or nil")
	if M.refuseBinding and command then return nil end
	M.userBindings = M.userBindings or {}
	M.userBindings[key] = command
	local depth = M.secure
	M.secure = 0
	M.Fire("UPDATE_BINDINGS")
	M.secure = depth
	return true
end
function GetCurrentBindingSet() return 1 end -- Enum.BindingSet.Account
function SaveBindings(which)
	assert(which == 1 or which == 2, "SaveBindings wants the account's or the character's binding set")
	M.savedBindings[#M.savedBindings + 1] = which
end

---------------------------------------------------------------------------
-- State drivers (port of Blizzard_RestrictedAddOnEnvironment/SecureStateDriver.lua, build 1.60.1)
---------------------------------------------------------------------------
-- What a macro condition list comes to right now: the value after the first clause whose
-- conditions all hold. Only the conditions the tests need are modelled; any other is an error,
-- so that a condition this model cannot judge is never quietly taken for false.
local function conditionHolds(condition)
	local negated = condition:match("^no(.+)$")
	local name, argument = (negated or condition):match("^(%a+):?(.*)$")
	local holds
	if name == "bonusbar" then
		holds = argument == "" and M.bonusbar > 0 or tonumber(argument) == M.bonusbar
	elseif name == "form" or name == "stance" then
		holds = argument == "" and M.form > 0
		for wanted in argument:gmatch("[^/]+") do
			holds = holds or tonumber(wanted) == M.form
		end
	elseif name == "stealth" then
		holds = M.stealthed
	elseif name == "combat" then
		holds = M.combat
	else
		error("mock does not model the macro condition [" .. condition .. "]")
	end
	if negated then return not holds end
	return holds and true or false
end

function SecureCmdOptionParse(options)
	for clause in (options .. ";"):gmatch("%s*([^;]*);") do
		local conditions, value = clause:match("^%[(.-)%]%s*(.-)%s*$")
		if not conditions then
			return (clause:match("^%s*(.-)%s*$"))
		end
		local all = true
		for condition in conditions:gmatch("[^,%s]+") do
			all = all and conditionHolds(condition)
		end
		if all then return value end
	end
	return nil
end

local function resolveDriver(driver)
	local newValue = SecureCmdOptionParse(driver.values)
	if newValue == nil then return end
	if newValue == "nil" then
		newValue = nil
	else
		newValue = tonumber(newValue) or newValue
	end
	if driver.frame.__attrs[driver.attribute] ~= newValue then
		-- The driver manager is Blizzard's code: it may set attributes in a fight.
		M.secure = M.secure + 1
		local ok, err = pcall(driver.frame.SetAttribute, driver.frame, driver.attribute, newValue)
		M.secure = M.secure - 1
		if not ok then error(err, 0) end
	end
end

function UnregisterAttributeDriver(frame, attribute)
	bindGuard("UnregisterAttributeDriver")
	for i = #M.drivers, 1, -1 do
		if M.drivers[i].frame == frame and M.drivers[i].attribute == attribute then table.remove(M.drivers, i) end
	end
end

-- The value is worked out and set at once, and again whenever the client looks (M.RunDrivers).
function RegisterAttributeDriver(frame, attribute, values)
	bindGuard("RegisterAttributeDriver")
	assert(attribute:sub(1, 1) ~= "_", "a driver cannot write an attribute that begins with an underscore")
	UnregisterAttributeDriver(frame, attribute)
	local driver = { frame = frame, attribute = attribute, values = values }
	M.drivers[#M.drivers + 1] = driver
	resolveDriver(driver)
end

function RegisterStateDriver(frame, state, values) RegisterAttributeDriver(frame, "state-" .. state, values) end
function UnregisterStateDriver(frame, state) UnregisterAttributeDriver(frame, "state-" .. state) end

-- What the client does on its next update: evaluate every driver and set changed attributes.
function M.RunDrivers()
	local drivers = {}
	for i, driver in ipairs(M.drivers) do drivers[i] = driver end
	for _, driver in ipairs(drivers) do resolveDriver(driver) end
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

local function CooldownInfo(action)
	local cd = action and action.cooldown
	local start, duration, modRate = cd and cd[1] or 0, cd and cd[2] or 0, 1
	if restricted() then
		start, duration, modRate = Seal(start), Seal(duration), Seal(modRate)
	end
	return { startTime = start, duration = duration, modRate = modRate, isActive = cd ~= nil, isEnabled = true }
end

C_Spell = {
	-- Nothing at all for a spell the client does not know.
	GetSpellCooldown = function(spellID)
		for _, action in pairs(M.actions) do
			if action.spell == spellID then return CooldownInfo(action) end
		end
	end,
}

-- What is in a slot: its kind, an id and for some kinds a sub-kind.
function GetActionInfo(slot)
	local a = valid(slot)
	if not a then return nil end
	local kind, id, subKind = "spell", a.spell or slot, "spell"
	if a.item then
		kind, id, subKind = "item", a.item, nil
	elseif a.macro then
		kind, id, subKind = "macro", a.macro, nil
		if a.macroSpell then id, subKind = a.macroSpell, "spell" end -- a macro that casts a spell names the spell
	end
	if M.sealActionInfo and restricted() then id = Seal(id) end
	return kind, id, subKind
end

-- Rarity colours, by Enum.ItemQuality: poor, common, uncommon, rare, epic, legendary.
local QUALITY_COLORS = {
	[0] = { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 }, { 1, 0.5, 0 },
}
C_Item = {
	-- Nothing for an item the client has not loaded yet; GET_ITEM_INFO_RECEIVED follows when it has.
	GetItemQualityByID = function(item)
		if IsSealed(item) and insecure() then
			error("C_Item.GetItemQualityByID: secret values are only allowed during untainted execution for this argument", 2)
		end
		return M.itemQuality[item]
	end,
	GetItemQualityColor = function(quality)
		local color = assert(QUALITY_COLORS[quality], "unknown item quality " .. tostring(quality))
		return color[1], color[2], color[3], "ff000000"
	end,
}

C_ActionBar = {
	GetBonusBarOffset = function() return M.bonusbar end,
	-- The page the regular action bar turns to: 1 outside any stance, 6 + the stance otherwise.
	GetBonusBarIndex = function() return M.bonusbar > 0 and 6 + M.bonusbar or 1 end,
	HasAction = function(slot) return valid(slot) ~= nil end,
	GetActionTexture = function(slot) local a = valid(slot); return a and a.texture end,
	IsUsableAction = function(slot) local a = valid(slot); return a and a.usable ~= false or false, a and a.noMana or false end,
	-- SecretWhenCooldownsRestricted: the numbers are sealed, isActive and isEnabled never are.
	GetActionCooldown = function(slot) return CooldownInfo(valid(slot)) end,
	GetActionCooldownDuration = function(slot)
		local a = valid(slot)
		local cd = a and a.cooldown
		return NewDuration(cd and cd[1] or 0, cd and cd[2] or 0)
	end,
	GetSpell = function(slot) local a = valid(slot); return a and a.spell or 0 end,
	-- SecretWhenCooldownsRestricted as well: charges are cooldown information.
	GetActionDisplayCount = function(slot)
		local a = valid(slot)
		local count = a and a.count or ""
		if restricted() then return Seal(count) end
		return count
	end,
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

-- What the cursor carries: nothing, "action" (something picked up from a slot, which is all the
-- drag and drop tests need to know), or a spell taken from the spell book: { kind = "spell", spell = }.
local function setCursor(carried)
	local was = M.cursor
	M.cursor = carried
	if (was ~= nil) ~= (carried ~= nil) then
		local depth = M.secure
		M.secure = 0
		M.Fire("CURSOR_CHANGED", carried == nil)
		M.secure = depth
	end
end
M.SetCursor = setCursor

function PickupAction(slot)
	if M.combat and insecure() then error("BLOCKED: PickupAction in combat", 2) end
	M.picked[#M.picked + 1] = slot
	-- The real client takes the action out of the slot. Most scenarios only ask what was picked
	-- up, so that part is modelled where a scenario asks for it (M.pickupRemoves).
	if M.pickupRemoves and M.actions[slot] then
		M.actions[slot] = nil
		setCursor("action")
		local depth = M.secure
		M.secure = 0
		M.Fire("ACTIONBAR_SLOT_CHANGED", slot)
		M.secure = depth
		return
	end
	setCursor("action")
end
-- Dropping a spell on a slot puts it there and leaves what was in the slot on the cursor.
function PlaceAction(slot)
	if M.combat and insecure() then error("BLOCKED: PlaceAction in combat", 2) end
	M.placed[#M.placed + 1] = slot
	local carried = M.cursor
	if type(carried) == "table" and carried.kind == "spell" then
		if M.refusePlace then return end
		local was = M.actions[slot]
		M.actions[slot] = { texture = "spell " .. carried.spell, spell = carried.spell }
		setCursor(was and was.spell and { kind = "spell", spell = was.spell } or nil)
		local depth = M.secure
		M.secure = 0
		M.Fire("ACTIONBAR_SLOT_CHANGED", slot)
		M.secure = depth
	else
		setCursor(nil)
	end
end
function ClearCursor() setCursor(nil) end
function GetCursorInfo()
	if type(M.cursor) == "table" then return M.cursor.kind, nil, nil, M.cursor.spell end
	return M.cursor
end

-- The spell book. One skill line holds everything in M.book.
C_SpellBook = {
	GetNumSpellBookSkillLines = function() return #M.book > 0 and 1 or 0 end,
	GetSpellBookSkillLineInfo = function(line)
		if line ~= 1 then return nil end
		return { name = "Class", itemIndexOffset = 0, numSpellBookItems = #M.book, isGuild = false, shouldHide = false }
	end,
	GetSpellBookItemInfo = function(index, bank)
		assert(bank == 0, "mock only has the player's spell book")
		local item = M.book[index]
		if not item then return nil end
		return { actionID = item.spell, spellID = item.spell, itemType = item.passive == "future" and 2 or 1, name = item.name,
			subName = "", iconID = 1, isPassive = item.passive == true, isOffSpec = item.offSpec or false, skillLineIndex = 1 }
	end,
	IsSpellBookItemLowRank = function(index, bank)
		assert(bank == 0, "mock only has the player's spell book")
		return M.book[index] ~= nil and M.book[index].low == true
	end,
	PickupSpellBookItem = function(index, bank)
		if M.combat and insecure() then error("BLOCKED: PickupSpellBookItem in combat", 2) end
		if M.refusePickup then return end
		setCursor({ kind = "spell", spell = assert(M.book[index], "no such spell book item").spell })
	end,
}

-- A character learns a spell: a new rank makes the one before it a lower rank. The book changes
-- and the client says so; no slot is touched.
function M.Learn(spell, name)
	for _, item in ipairs(M.book) do
		if item.name == name then item.low = true end
	end
	M.book[#M.book + 1] = { spell = spell, name = name }
	local depth = M.secure
	M.secure = 0
	M.Fire("LEARNED_SPELL_IN_SKILL_LINE", spell, 1, false)
	M.Fire("SPELLS_CHANGED")
	M.secure = depth
end

C_Spell = C_Spell or {}
-- Picks a spell up by its number: nothing for one the character does not have right now
-- (M.unknownSpells, for a spell of the other talent group).
function C_Spell.PickupSpell(spell)
	if M.combat and insecure() then error("BLOCKED: PickupSpell in combat", 2) end
	if M.unknownSpells and M.unknownSpells[spell] then return end
	setCursor({ kind = "spell", spell = spell })
end
function C_Spell.GetSpellName(spell)
	for _, item in ipairs(M.book) do
		if item.spell == spell then return item.name end
	end
	for _, form in ipairs(M.GetForms()) do
		if form[2] == spell then return form[1] end
	end
	return M.spellNames[spell]
end

-- Procs, as the game marks them for its own action buttons.
C_SpellActivationOverlay = {
	IsSpellOverlayed = function(spell)
		if IsSealed(spell) and insecure() then
			error("IsSpellOverlayed: secret values are only allowed during untainted execution for this argument", 2)
		end
		assert(type(spell) == "number", "IsSpellOverlayed wants a spell id")
		return M.overlayed[spell] == true
	end,
}
function M.Proc(spell, on)
	M.overlayed[spell] = on or nil
	local depth = M.secure
	M.secure = 0
	M.Fire(on and "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", spell)
	M.secure = depth
end
function IsStealthed() return M.stealthed end

---------------------------------------------------------------------------
-- Stances and forms
---------------------------------------------------------------------------
-- By class, in the order the game lists them: { name, spell, bar } where bar is the stance
-- (bonus) bar the form brings up, 0 for a form that has none. These are the classic rules; what
-- Forever changed is not known here, so a test can put any list in M.forms.
M.FORMS = {
	DRUID = {
		{ "Bear Form", 5487, 3 }, { "Aquatic Form", 1066, 0 }, { "Cat Form", 768, 1 }, { "Travel Form", 783, 0 },
		{ "Moonkin Form", 24858, 4 },
	},
	WARRIOR = { { "Battle Stance", 2457, 1 }, { "Defensive Stance", 71, 2 }, { "Berserker Stance", 2458, 3 } },
	ROGUE = { { "Stealth", 1784, 1 } },
	PRIEST = { { "Shadowform", 15473, 0 } }, -- in Forever it turns no bar
	PALADIN = { { "Devotion Aura", 465, 0 }, { "Retribution Aura", 7294, 0 } },
}
local function forms() return M.forms or M.FORMS[M.class] or {} end
M.GetForms = forms

function GetNumShapeshiftForms() return #forms() end
function GetShapeshiftForm() return M.form end
-- Icon, in it now, can be changed to now, spell. A test can make a form unusable
-- (M.uncastable[index]) or have the client seal the lot in a fight (M.sealForms), which nobody
-- here has seen it do: the addon has to cope either way.
M.uncastable = {}
function GetShapeshiftFormInfo(index)
	local form = forms()[index]
	if not form then return nil end
	local texture, active, castable, spell = "icon " .. form[2], M.form == index, not M.uncastable[index], form[2]
	if M.sealForms and restricted() and insecure() then
		return Seal(texture), Seal(active), Seal(castable), Seal(spell)
	end
	return texture, active, castable, spell
end

-- The character changes form (0 leaves every form). The game says so with these events, the
-- handlers of which are addon code; the state drivers are looked at on the client's next update,
-- which is modelled as happening right after.
function M.Shapeshift(index)
	local form = index > 0 and assert(forms()[index], "this class has no form " .. index) or nil
	M.form = index
	M.bonusbar = form and form[3] or 0
	M.stealthed = form ~= nil and form[1] == "Stealth"
	local depth = M.secure
	M.secure = 0
	for _, event in ipairs({ "UPDATE_SHAPESHIFT_FORM", "UPDATE_BONUS_ACTIONBAR", "ACTIONBAR_UPDATE_USABLE" }) do M.Fire(event) end
	M.secure = depth
	M.RunDrivers()
end

-- What the game's stance bar does when one of its buttons is used (StanceBar:Select, which the
-- commands SHAPESHIFTBUTTON1 to 10 run): change to that stance. A form the character is already
-- in is left by using it again; a Warrior is always in a stance and stays in it. A protected
-- call: addon code may not make it in a fight.
function CastShapeshiftForm(index)
	if M.combat and insecure() then error("BLOCKED: CastShapeshiftForm from tainted code in combat", 2) end
	if not forms()[index] then return end
	if M.form == index then
		if M.class ~= "WARRIOR" then M.Shapeshift(0) end
		return
	end
	M.Shapeshift(index)
end

-- By name, for tests that read better that way: M.ShapeshiftTo("Cat Form"), M.ShapeshiftTo(nil).
function M.ShapeshiftTo(name)
	if not name then return M.Shapeshift(0) end
	for index, form in ipairs(forms()) do
		if form[1] == name then return M.Shapeshift(index) end
	end
	error("this class has no form called " .. name)
end
-- The player, and whoever is targeted (M.target: a name, or nil for nobody). In a fight on a
-- client that seals things, who the target is comes back sealed.
function UnitGUID(unit)
	if unit == "target" then
		if not M.target then return nil end
		local guid = "Player-1-" .. M.target
		if M.sealTarget and M.combat and M.secure == 0 then return M.Seal(guid) end
		return guid
	end
	assert(unit == "player", "mock only knows the player and the target")
	return M.guid
end
-- What the game's own menu for a player offers: to invite them, or, for one who is in a group
-- already (M.grouped[name]), to ask to join it. Blizzard's function, in its interface code.
M.grouped = {}
function GetDisplayedInviteType(guid)
	assert(type(guid) == "string", "GetDisplayedInviteType wants a GUID that can be read")
	local name = guid:match("^Player%-1%-(.+)$")
	return M.grouped[name] and "REQUEST_INVITE" or "INVITE"
end
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
function GetTime() return M.now end

-- What the addon reports here is what the player would see with errors switched on.
function geterrorhandler()
	return function(message) M.luaErrors[#M.luaErrors + 1] = tostring(message) end
end

-- The client's xpcall hands extra arguments on to the function; plain Lua 5.1's does not.
local plainXpcall = xpcall
function xpcall(fn, handler, ...)
	local count, arguments = select("#", ...), { ... }
	return plainXpcall(function() return fn(unpack(arguments, 1, count)) end, handler)
end

C_AddOns = { GetAddOnMetadata = function(_, field) return field == "Version" and "test" or nil end }
Enum = {
	InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 },
	SpellBookSpellBank = { Player = 0, Pet = 1 },
	SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
}
C_InputInterfaceStyle = { GetCurrentStyle = function() return M.gamepadUI and 1 or 0 end }
C_GamePad = {
	IsEnabled = function() return M.cvars.GamePadEnable == "1" end,
	GetAllDeviceIDs = function() return { 1 } end,
	GetActiveDeviceID = function() return 1 end,
	GetDeviceMappedState = function() return { labelStyle = M.labelStyle or "Letters" } end,
}
-- Asking for the pointer does not end camera mode: that is a separate request.
function SetGamePadCursorControl(enabled)
	M.pointerCalls[#M.pointerCalls + 1] = "pointer " .. tostring(enabled)
	if enabled and M.refuseCursor > 0 then
		M.refuseCursor = M.refuseCursor - 1
		return
	end
	M.cursorControl = enabled and true or false
end
function IsGamePadCursorControlEnabled() return M.cursorControl end
function SetGamePadFreeLook(enabled)
	M.pointerCalls[#M.pointerCalls + 1] = "camera " .. tostring(enabled)
	M.freeLook = enabled and true or false
end
function IsGamePadFreelookEnabled() return M.freeLook end
function IsUsingGamepad() return M.freeLook or M.cursorControl end
function IsUsingMouse() return false end
function UnitClass(unit)
	assert(unit == "player", "mock only knows the player's class")
	return "Class", M.class
end

Settings = {
	GetValue = function(name) assert(name == "lockActionBars"); return M.lockActionBars end,
	RegisterCanvasLayoutCategory = function(frame, name) return { GetID = function() return name end, frame = frame } end,
	RegisterAddOnCategory = function(category) M.category = category end,
	RegisterCanvasLayoutSubcategory = function(parent, frame, name)
		local category = { GetID = function() return name end, frame = frame, parent = parent }
		M.subcategories = M.subcategories or {}
		M.subcategories[#M.subcategories + 1] = category
		return category, {}
	end,
	KEYBINDINGS_CATEGORY_ID = "Keybindings",
	OpenToCategory = function(id) M.opened[#M.opened + 1] = id end,
}

GameTooltip = { owner = nil, lines = {} }
function GameTooltip:SetOwner(owner) self.owner = owner; self.lines = {} end
function GameTooltip:GetOwner() return self.owner end
-- A tooltip takes text and nothing else: handed nil, a function or a table, the client raises
-- "bad argument #1 to 'SetText' (Usage: self:SetText(text [, color, alpha, wrap]))".
local function tooltipText(method, text)
	local kind = type(text)
	if kind ~= "string" and kind ~= "number" then
		error(("bad argument #1 to '%s' (Usage: self:%s(text [, color, alpha, wrap])), got %s"):format(method, method, kind), 3)
	end
	return text
end
function GameTooltip:SetText(text) self.lines = { tooltipText("SetText", text) } end
function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = tooltipText("AddLine", text) end
function GameTooltip:SetAction(slot)
	local action = M.actions[slot]
	self.lines = { action and action.tooltip or "action " .. slot }
	return action and action.refreshTooltip or false
end
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

---------------------------------------------------------------------------
-- The chat
---------------------------------------------------------------------------
-- What the chat keyboard and the quick phrases (the Chat folder) need of the client:
--
--   * one chat edit box, ChatFrame1EditBox, with the channel it is on in its attributes as the
--     client keeps it (chatType, stickyType, tellTarget, channelTarget). Opening the chat shows
--     it and gives it the focus; its Escape handler empties it and lets the focus go;
--   * a message is sent by C_ChatInfo.SendChatMessage, which notes it in M.sent. The slash
--     commands a macro can hold are run through it (M.RunMacroText), the way the client runs a
--     macro's lines: the chat edit box's own channel is not moved by them;
--   * hooksecurefunc runs the hook after the function, as addon code.
M.atlases = {}             -- the game's own pictures this client has, by name
M.locale = "enUS"
M.sent = {}                -- chat messages sent: { text, chatType, target }
M.macroLines = {}          -- the other lines macros ran: "/wave"
M.inGroup, M.inRaid, M.inGuild = false, false, false
M.lastTell = nil           -- who whispered the player last
M.channels = { [1] = "General" }
M.mouseDown = false
M.registry = {}            -- EventRegistry callbacks: [event] = { fn, ... }

function GetLocale() return M.locale end
format = string.format
function IsInGroup() return M.inGroup or M.inRaid end
function IsInRaid() return M.inRaid end
function IsInGuild() return M.inGuild end
function GetNumGroupMembers() return 0 end
function UnitName(unit) return unit == "player" and (M.playerName or "Tester") or nil end
function GetRealmName() return "Testrealm" end
function GetChannelName(id)
	local name = M.channels[tonumber(id) or 0]
	if name then return tonumber(id), name end
	return 0, nil
end
function IsMouseButtonDown() return M.mouseDown end
C_Texture = { GetAtlasInfo = function(name) return M.atlases[name] and {} or nil end }
ChatTypeInfo = setmetatable({}, { __index = function() return { r = 1, g = 0.5, b = 0.25 } end })
NUM_CHAT_WINDOWS = 1

function hooksecurefunc(owner, name, hook)
	if type(owner) == "string" then owner, name, hook = _G, owner, name end
	local original = assert(owner[name], "nothing to hook: " .. tostring(name))
	owner[name] = function(...)
		local results = { original(...) }
		local depth = M.secure
		M.secure = 0
		hook(...)
		M.secure = depth
		return unpack(results)
	end
end

EventRegistry = {}
function EventRegistry:RegisterCallback(event, fn, owner)
	M.registry[event] = M.registry[event] or {}
	table.insert(M.registry[event], function(...) fn(owner, ...) end)
end

C_ChatInfo = {
	SendChatMessage = function(text, chatType, language, target)
		M.sent[#M.sent + 1] = { text = text, chatType = chatType or "SAY", target = target }
	end,
}

ChatFrame1 = CreateFrame("Frame", "ChatFrame1", UIParent)
ChatFrame1EditBox = CreateFrame("EditBox", "ChatFrame1EditBox", ChatFrame1)
ChatFrame1EditBox:Hide()
ChatFrame1EditBox.__attrs.chatType, ChatFrame1EditBox.__attrs.stickyType = "SAY", "SAY"
-- The box's own handlers are the game's, set before any addon's hooks.
ChatFrame1EditBox.__scripts.OnEscapePressed = function(self)
	self.__text = ""
	self.__attrs.chatType = self.__attrs.stickyType
	self:ClearFocus()
	self:Hide()
end

ChatFrameUtil = {
	GetActiveWindow = function() return M.focus == ChatFrame1EditBox and ChatFrame1EditBox or nil end,
	OpenChat = function(text)
		ChatFrame1EditBox.__text = text or ""
		ChatFrame1EditBox:Show()
		ChatFrame1EditBox:SetFocus()
	end,
	GetLastTellTarget = function() return M.lastTell end,
	GetLastToldTarget = function() return nil end,
}

-- The player opens the chat: on its usual channel, or on another one for this message only (a
-- name clicked to whisper; the box keeps that name afterwards, as the client's does). The
-- addon's timers that wait for the next frame are let run.
function M.OpenChat(chatType, target)
	local box = ChatFrame1EditBox
	box.__attrs.chatType = chatType or box.__attrs.stickyType
	if target then box.__attrs.tellTarget = target end
	ChatFrameUtil.OpenChat("")
	M.Advance(0)
end

-- The player types a slash command that moves the chat's own channel for good ("/g").
function M.SetChatSticky(chatType)
	ChatFrame1EditBox.__attrs.chatType, ChatFrame1EditBox.__attrs.stickyType = chatType, chatType
end

-- The lines of a macro, run by the game. A chat command sends its message; anything else is
-- noted as it is.
local MACRO_CHAT = { ["/s"] = "SAY", ["/y"] = "YELL", ["/p"] = "PARTY", ["/ra"] = "RAID", ["/g"] = "GUILD",
	["/o"] = "OFFICER", ["/i"] = "INSTANCE_CHAT", ["/rw"] = "RAID_WARNING", ["/e"] = "EMOTE" }
function M.RunMacroText(text)
	for line in text:gmatch("[^\n]+") do
		local command, rest = line:match("^(/%S+)%s*(.*)$")
		local number = command and tonumber(command:match("^/(%d+)$"))
		if command == "/r" then
			C_ChatInfo.SendChatMessage(rest, "WHISPER", nil, M.lastTell)
		elseif number then
			C_ChatInfo.SendChatMessage(rest, "CHANNEL", nil, number)
		elseif MACRO_CHAT[command] then
			C_ChatInfo.SendChatMessage(rest, MACRO_CHAT[command])
		else
			M.macroLines[#M.macroLines + 1] = line
		end
	end
end

-- Where a stick is: told to the frames that asked for the sticks and are on screen.
function M.Stick(stick, x, y)
	for _, frame in ipairs(M.all) do
		local fn = frame.__sticks and frame:IsVisible() and frame.__scripts.OnGamePadStick
		if fn then fn(frame, stick, x, y) end
	end
end
-- The game's dialogs that ask a question (static popups): the ones on screen, by kind
-- (M.popups[which] = a dialog), and the answers given them: { which, button }.
M.popups = {}
M.popupAnswers = {}
function StaticPopup_FindVisible(which) return M.popups[which] end
function StaticPopup_OnClick(dialog, index)
	assert(dialog and M.popups[dialog.which] == dialog, "StaticPopup_OnClick wants a dialog that is on screen")
	M.popupAnswers[#M.popupAnswers + 1] = { which = dialog.which, button = index }
	M.popups[dialog.which] = nil
end
-- The game asks: an invitation ("PARTY_INVITE"), someone asking to join ("GROUP_INVITE_CONFIRMATION").
function M.Ask(which) M.popups[which] = { which = which } end
-- Items the group is rolling for: M.rolls is the list still going, each { id =, name =, bop =,
-- canNeed =, canGreed = }; M.rollsMade is what was answered: { id, kind } (0 pass, 1 need,
-- 2 greed). An item that binds when picked up is not rolled for at once: the game asks first.
M.rolls = {}
M.rollsMade = {}
local function findRoll(id)
	for _, roll in ipairs(M.rolls) do
		if roll.id == id then return roll end
	end
	error("no such loot roll: " .. tostring(id), 3)
end
function GetActiveLootRollIDs()
	local ids = {}
	for index, roll in ipairs(M.rolls) do ids[index] = roll.id end
	return ids
end
function GetLootRollItemInfo(id)
	local roll = findRoll(id)
	return "icon", roll.name, 1, 3, roll.bop or false, roll.canNeed ~= false, roll.canGreed ~= false, false
end
function GetLootRollItemLink(id) return "[" .. findRoll(id).name .. "]" end
function RollOnLoot(id, kind)
	local roll = findRoll(id)
	M.rollsMade[#M.rollsMade + 1] = { id = id, kind = kind }
	if roll.bop and kind ~= 0 then M.Ask("CONFIRM_LOOT_ROLL") end
end
function StaticPopup_Hide(which) M.popups[which] = nil end
-- What the mouse pointer is on (M.mouseOver, a frame or nil for the world), as the client tells
-- an addon that asks; whether a frame has a handler of a kind; and the camera's zoom, which is
-- what the wheel turns over the world: M.zoomed counts the notches in (+) and out (-).
function GetMouseFoci() return { M.mouseOver } end
function Frame:HasScript(name) return name == "OnMouseWheel" or self.__scripts[name] ~= nil end
M.zoomed = 0
function CameraZoomIn(amount) M.zoomed = M.zoomed + amount end
function CameraZoomOut(amount) M.zoomed = M.zoomed - amount end