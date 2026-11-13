local _, ns = ...

-- A short recording of what the game reports about one button's cooldown, for when the bar and
-- the game disagree: the game cannot be watched from outside, and it usually hides addon errors.
--
--   /fc trace      starts it (it stops by itself after twenty seconds)
--   use an ability on the FreeControl bar
--   /fc trace      stops it and shows what was seen, in a box the text can be copied from
--
-- Recording only looks; it changes nothing about how the bar behaves. Whatever the game has
-- sealed is written down as "sealed" and never read (see "Sealed values" in Core.lua).
local Trace = { active = false }
ns.Trace = Trace

local LENGTH = 20    -- seconds a recording runs before it stops by itself
local MAX_LINES = 45 -- what fits in the box
local STEP = 0.1     -- seconds between looks at the watched button
local EVENTS = {
	"ACTIONBAR_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN",
	"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
	"UNIT_SPELLCAST_SENT", -- only ever raised for the player's own casts
}
-- These are asked for the player only, so nobody else's casts arrive (theirs can be sealed).
local PLAYER_EVENTS = { "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED" }
-- Which of an event's values is worth writing down.
local DETAIL = {
	SPELL_UPDATE_COOLDOWN = 1,    -- spellID
	UNIT_SPELLCAST_SENT = 4,      -- unit, target, castGUID, spellID
	UNIT_SPELLCAST_SUCCEEDED = 3, -- unit, castGUID, spellID
	UNIT_SPELLCAST_FAILED = 3,
	ADDON_ACTION_BLOCKED = 2,     -- addon, what was refused
	ADDON_ACTION_FORBIDDEN = 2,
}

local lines = {}
local started = 0
local dropped = 0        -- lines that did not fit
local watched, lastState -- the button last used, and what was last written about it
local sinceLook = 0
local window

local watcher = CreateFrame("Frame")
watcher:Hide()

-- Text for the report. The test for a sealed value comes first: nothing else may touch one.
local function Plain(value)
	if ns.IsSealed(value) then
		return "sealed"
	end
	return tostring(value)
end

local function Seconds(value, scale)
	if ns.IsSealed(value) then
		return "sealed"
	end
	if type(value) ~= "number" then
		return tostring(value)
	end
	return ("%.1fs"):format(value / (scale or 1))
end

-- One of the game's cooldown answers. isActive, isEnabled and isOnGCD are never sealed.
local function Brief(info)
	if not info then
		return "nothing"
	end
	return (info.isActive and "running, " or "idle, ") .. Seconds(info.duration)
		.. (info.isEnabled == false and ", on hold" or "") .. (info.isOnGCD and ", global cooldown" or "")
end

local function SpellOf(slot)
	local spellID = C_ActionBar.GetSpell and C_ActionBar.GetSpell(slot)
	if ns.IsSealed(spellID) or type(spellID) ~= "number" or spellID <= 0 then
		return nil
	end
	return spellID
end

-- What the game says about a button's cooldown right now, asked by slot and by spell, and what
-- the button's own sweep is doing. Once a sealed cooldown has been put on a sweep, the game
-- seals what the sweep says about itself as well.
local function State(button)
	local fc = button.fc
	local text = "slot: " .. Brief(C_ActionBar.GetActionCooldown(fc.slot))
	local spellID = SpellOf(fc.slot)
	if spellID then
		text = text .. " | spell: " .. Brief(C_Spell.GetSpellCooldown(spellID))
	end
	local shown = fc.cooldown:IsShown()
	if ns.IsSealed(shown) then
		shown = "sealed"
	else
		shown = shown and "showing" or "hidden"
	end
	return text .. " | sweep: " .. shown .. ", " .. Seconds(fc.cooldown:GetCooldownDuration(), 1000)
end

function Trace:Add(text)
	if not self.active then
		return
	end
	if #lines < MAX_LINES then
		lines[#lines + 1] = ("%5.2f  %s"):format(GetTime() - started, text)
	else
		dropped = dropped + 1
	end
end

-- Called by Buttons.lua when a slot is used, by key or by mouse.
function Trace:Press(button)
	local fc = button.fc
	if not (self.active and fc.slot and fc.hasAction) then
		return
	end
	watched, lastState = button, State(button)
	self:Add(("USED %s, slot %d%s%s. %s"):format(
		ns.Layout.GetButtonName(fc.set, fc.index), fc.slot,
		SpellOf(fc.slot) and (", spell " .. SpellOf(fc.slot)) or "",
		InCombatLockdown() and ", in combat" or ", out of combat", lastState))
end

-- Writes a line if what the game or the button says has changed since the last one.
function Trace:Look(why)
	if not (self.active and watched and watched.fc.slot and watched.fc.hasAction) then
		return
	end
	local state = State(watched)
	if state ~= lastState then
		lastState = state
		self:Add(("   %s: %s"):format(why, state))
	end
end

local function OnEvent(_, event, ...)
	local detail = DETAIL[event]
	Trace:Add(detail and (event .. " " .. Plain((select(detail, ...)))) or event)
	Trace:Look("right after")
end

local function OnUpdate(_, elapsed)
	sinceLook = sinceLook + elapsed
	if sinceLook < STEP then
		return
	end
	sinceLook = 0
	Trace:Look("later")
	if GetTime() - started > LENGTH then
		Trace:Stop()
		Trace:Show()
	end
end

-- The recorder is new and cannot be tried in the game from where it is written, so it does not
-- get to carry on after an error of its own: that is reported like any other, and it stops.
watcher:SetScript("OnEvent", function(...)
	if not ns.Try(OnEvent, ...) then
		Trace:Stop()
	end
end)
watcher:SetScript("OnUpdate", function(...)
	if not ns.Try(OnUpdate, ...) then
		Trace:Stop()
	end
end)

function Trace:Start()
	wipe(lines)
	started, dropped, watched, lastState, sinceLook = GetTime(), 0, nil, nil, 0
	self.active = true
	for _, event in ipairs(EVENTS) do
		watcher:RegisterEvent(event)
	end
	for _, event in ipairs(PLAYER_EVENTS) do
		watcher:RegisterUnitEvent(event, "player")
	end
	watcher:Show()
	if window then
		window:Hide()
	end
	self:Add(("FreeControl %s, game interface %s, %s. The game seals combat values from addons: %s."):format(
		ns.version, Plain((select(4, GetBuildInfo()))), InCombatLockdown() and "in combat" or "out of combat",
		ns.DescribeSealing()))
end

function Trace:Stop()
	self.active = false
	watcher:UnregisterAllEvents()
	watcher:Hide()
end

function Trace:GetText()
	local text = table.concat(lines, "\n")
	if dropped > 0 then
		text = text .. ("\n(%d more lines did not fit)"):format(dropped)
	end
	for _, problem in ipairs(ns.GetProblems()) do
		text = text .. ("\nERROR since login, %d time(s): %s"):format(problem.count, problem.text)
	end
	return text
end

local function CreateWindow()
	local frame = CreateFrame("Frame", "FreeControlTrace", UIParent)
	frame:SetSize(860, 580)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:EnableMouse(true)

	local fill = frame:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(0.03, 0.03, 0.05, 0.95)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText("FreeControl trace. The text is selected: Ctrl+C copies it. Escape or Close shuts this.")

	local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	close:SetSize(70, 22)
	close:SetPoint("TOPRIGHT", -8, -6)
	close:SetText("Close")
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	local edit = CreateFrame("EditBox", nil, frame)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject("GameFontHighlightSmall")
	edit:SetPoint("TOPLEFT", 12, -34)
	edit:SetPoint("BOTTOMRIGHT", -12, 12)
	edit:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		frame:Hide()
	end)
	frame.edit = edit
	return frame
end

function Trace:Show()
	window = window or CreateWindow()
	window.edit:SetText(self:GetText())
	window:Show()
	window.edit:SetFocus()
	window.edit:HighlightText()
	ns.Print("Trace ready: press Ctrl+C to copy it (or take a screenshot), then Escape to close the box.")
end

-- /fc trace
function Trace:Toggle()
	if self.active then
		self:Stop()
		self:Show()
	else
		self:Start()
		ns.Print(("Recording for %d seconds. Use an ability on the FreeControl bar now, then type /fc trace again."):format(LENGTH))
	end
end
