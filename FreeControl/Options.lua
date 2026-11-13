local _, ns = ...
local Layout = ns.Layout

-- The settings page (Options > AddOns > FreeControl), the /fc command, and the menu for choosing
-- what a no-trigger button does.
local Options = {}
ns.Options = Options

BINDING_NAME_FREECONTROL_TOGGLECURSOR = "Controller mouse cursor on / off"

---------------------------------------------------------------------------
-- Choices offered by the menus: { value, label }
---------------------------------------------------------------------------
local LABEL_STYLES = {
	{ "auto", "Match my controller" },
	{ "xbox", "Xbox (A B X Y)" },
	{ "playstation", "PlayStation (shapes)" },
	{ "nintendo", "Nintendo (B A Y X)" },
}
local SLOT_SOURCES = {
	{ "gamepad", "Controller-bar slots" },
	{ "bars", "Regular action bars" },
}
local PAGES = { { 1, "Page 1" }, { 2, "Page 2" }, { 3, "Page 3" } }
local STANCE_SETS = {
	{ "auto", "Same as Gamepad options" },
	{ "none", "None" },
	{ "lt", "Left trigger set" },
	{ "rt", "Right trigger set" },
	{ "both", "Both triggers set" },
}
local TRIGGER_KEYS = {
	{ "PADLTRIGGER", "Left trigger" },
	{ "PADRTRIGGER", "Right trigger" },
	{ "PADLSHOULDER", "Left bumper" },
	{ "PADRSHOULDER", "Right bumper" },
	{ "PADPADDLE1", "Paddle 1" },
	{ "PADPADDLE2", "Paddle 2" },
	{ "PADPADDLE3", "Paddle 3" },
	{ "PADPADDLE4", "Paddle 4" },
}

local function RoleChoices()
	local choices = {
		{ "action", "Action slot" },
		{ "pass", "My own key binding" },
	}
	for _, command in ipairs(Layout.COMMANDS) do
		choices[#choices + 1] = { "cmd:" .. command[1], command[2] }
	end
	return choices
end

-- Label of the current value; a value typed by hand (a key or command not in the list) shows as itself.
local function LabelFor(choices, value)
	for _, choice in ipairs(choices) do
		if choice[1] == value then
			return choice[2]
		end
	end
	return tostring(value)
end

---------------------------------------------------------------------------
-- Changing a setting
---------------------------------------------------------------------------
local function Set(key, value)
	ns.db[key] = value
	ns.RequestRefresh()
end

local function SetIndexed(key, index, value)
	ns.db[key][index] = value
	ns.RequestRefresh()
end

-- Opens a menu of choices next to `owner`; get() returns the current value. Without the menu
-- system the button steps through the choices instead.
local function Choose(owner, choices, get, onPick)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, function(_, root)
			for _, choice in ipairs(choices) do
				root:CreateRadio(choice[2], function() return choice[1] == get() end, function() onPick(choice[1]) end)
			end
		end)
		return
	end
	local position = 0
	for index, choice in ipairs(choices) do
		if choice[1] == get() then
			position = index
		end
	end
	onPick(choices[position % #choices + 1][1])
end

function Options:OpenRoleMenu(owner, index)
	if InCombatLockdown() then
		ns.Print("Buttons cannot be changed in combat.")
		return
	end
	Choose(owner, RoleChoices(), function() return ns.db.roles[index] end, function(value)
		SetIndexed("roles", index, value)
	end)
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
local ROW = 26
local controls = {} -- every widget with a Sync function

local function AddTooltip(widget, title, text)
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title, 1, 1, 1)
		GameTooltip:AddLine(text, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

local function Heading(panel, text, x, y)
	local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	heading:SetPoint("TOPLEFT", x, y)
	heading:SetText(text)
	return y - ROW
end

local function Check(panel, x, y, label, tooltip, key)
	local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	check:SetSize(26, 26)
	check:SetPoint("TOPLEFT", x, y)
	check.Text:SetText(label)
	check.Text:SetFontObject("GameFontHighlight")
	AddTooltip(check, label, tooltip)
	check:SetScript("OnClick", function(self)
		Set(key, self:GetChecked() and true or false)
	end)
	check.Sync = function(self)
		self:SetChecked(ns.db[key])
	end
	controls[#controls + 1] = check
	return y - ROW
end

-- A label with a button showing the current choice. get() returns the value, set(value) stores it.
local function Choice(panel, x, y, label, tooltip, choices, get, set)
	local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("TOPLEFT", x + 4, y - 6)
	text:SetText(label)

	local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	button:SetSize(170, 22)
	button:SetPoint("TOPLEFT", x + 130, y - 2)
	AddTooltip(button, label, tooltip)
	button:SetScript("OnClick", function(self)
		local list = type(choices) == "function" and choices() or choices
		Choose(self, list, get, set)
	end)
	button.Sync = function(self)
		local list = type(choices) == "function" and choices() or choices
		self:SetText(LabelFor(list, get()))
	end
	controls[#controls + 1] = button
	return y - ROW
end

-- A label with - and + buttons around a percentage.
local function Stepper(panel, x, y, label, tooltip, key, minimum, maximum, step)
	local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("TOPLEFT", x + 4, y - 6)
	text:SetText(label)

	local value = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	value:SetPoint("CENTER", panel, "TOPLEFT", x + 215, y - 13)

	local function Step(direction)
		local stepped = math.floor((ns.db[key] + direction * step) / step + 0.5) * step
		Set(key, math.max(minimum, math.min(maximum, stepped)))
	end
	local minus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	minus:SetSize(26, 22)
	minus:SetPoint("TOPLEFT", x + 130, y - 2)
	minus:SetText("-")
	minus:SetScript("OnClick", function() Step(-1) end)
	local plus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	plus:SetSize(26, 22)
	plus:SetPoint("TOPLEFT", x + 274, y - 2)
	plus:SetText("+")
	plus:SetScript("OnClick", function() Step(1) end)
	AddTooltip(minus, label, tooltip)
	AddTooltip(plus, label, tooltip)

	value.Sync = function(self)
		self:SetText(("%d%%"):format(ns.db[key] * 100 + 0.5))
	end
	controls[#controls + 1] = value
	return y - ROW
end

local function Action(panel, x, y, label, tooltip, onClick)
	local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	button:SetSize(170, 22)
	button:SetPoint("TOPLEFT", x + 130, y - 2)
	button:SetText(label)
	AddTooltip(button, label, tooltip)
	button:SetScript("OnClick", onClick)
	return y - ROW
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local function Build(panel)
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", 16, -14)
	title:SetText("FreeControl")

	local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", 18, -40)
	note:SetPoint("RIGHT", -20, 0)
	note:SetJustifyH("LEFT")
	note:SetText("A controller cross hotbar for the normal interface. Hold a trigger to switch sets, drop spells, items and macros onto any slot. Changes made in combat apply when the fight ends.")

	local left, right = 16, 340
	local y = -78

	y = Heading(panel, "Bar", left, y)
	y = Check(panel, left, y, "Enable FreeControl", "Shows the bar and binds the controller. Turn it off to hand every button back to your own key bindings.", "enabled")
	y = Check(panel, left, y, "Lock position", "Untick to show a handle you can drag the bar with.", "locked")
	y = Stepper(panel, left, y, "Size", "Size of the whole bar.", "scale", 0.5, 2, 0.05)
	y = Stepper(panel, left, y, "Held set size", "How much the set you are holding grows.", "activeScale", 1, 1.5, 0.05)
	y = Stepper(panel, left, y, "Other sets", "How visible the sets you are not holding stay.", "inactiveAlpha", 0.3, 1, 0.05)
	y = Choice(panel, left, y, "Button labels", "Which names and symbols are printed on the buttons.", LABEL_STYLES,
		function() return ns.db.labelStyle end, function(value) Set("labelStyle", value) end)
	y = Check(panel, left, y, "Cooldown numbers", "Counts down the seconds left on every slot that is on cooldown. Untick it if another addon already draws them.", "cooldownNumbers")
	y = Action(panel, left, y, "Reset position", "Puts the bar back where it started, at normal size.", function()
		ns.db.point = CopyTable(ns.DEFAULTS.point)
		Set("scale", ns.DEFAULTS.scale)
	end)

	y = Heading(panel, "Slots", left, y - 8)
	y = Choice(panel, left, y, "Stored in", "Controller-bar slots are the ones Blizzard's Gamepad UI uses, separate from your action bars, so anything you set up there shows up here. Regular action bars uses the Left, Bottom Left, Bottom Right and Right bars instead.", SLOT_SOURCES,
		function() return ns.db.slotSource end, function(value) Set("slotSource", value) end)
	y = Choice(panel, left, y, "Page", "Which of the three controller-bar pages the bar shows.", PAGES,
		function() return ns.db.page end, function(value) Set("page", value) end)
	y = Choice(panel, left, y, "Stance set", "The set that swaps to different slots in each stance or form.", STANCE_SETS,
		function() return ns.db.stanceSet end, function(value) Set("stanceSet", value) end)

	y = -78
	y = Heading(panel, "Controller", right, y)
	y = Check(panel, right, y, "Turn on controller input", "Sets GamePadEnable while FreeControl is active so the game reads your controller. This is not Gamepad UI mode. Untick it if a tool such as Steam Input already turns your controller into key presses.", "manageGamepad")
	y = Check(panel, right, y, "Interact finds things by itself", "The Interact command picks the nearest corpse to loot, person to talk to or object to use, as in Gamepad UI mode (Options > Controls > Enable Interact Key).", "softInteract")
	y = Check(panel, right, y, "Gamepad UI interact reach", "Uses the wider arc and 20 yard range that Gamepad UI mode uses for Interact.", "interactReach")
	y = Choice(panel, right, y, "Left trigger", "The button that selects the left set.", TRIGGER_KEYS,
		function() return ns.db.modKeys[1] end, function(value) SetIndexed("modKeys", 1, value) end)
	y = Choice(panel, right, y, "Right trigger", "The button that selects the right set.", TRIGGER_KEYS,
		function() return ns.db.modKeys[2] end, function(value) SetIndexed("modKeys", 2, value) end)

	y = Heading(panel, "With no trigger held", right, y - 8)
	for index = 1, 8 do
		y = Choice(panel, right, y, "", "What this button does while no trigger is held. Action slot makes it a slot you can drop things into; My own key binding leaves it to the Key Bindings screen.", RoleChoices,
			function() return ns.db.roles[index] end, function(value) SetIndexed("roles", index, value) end)
		local name = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		name:SetPoint("TOPLEFT", right + 4, y + ROW - 6)
		name.Sync = function(self)
			self:SetText(Layout.GetButtonName(0, index))
		end
		controls[#controls + 1] = name
	end
end

function Options:Create()
	local panel = CreateFrame("Frame")
	panel:Hide()
	-- Built the first time the page is opened; most sessions never open it.
	panel:SetScript("OnShow", function(self)
		if not self.built then
			self.built = true
			Build(self)
		end
		Options:Sync()
	end)
	self.panel = panel
	self.category = Settings.RegisterCanvasLayoutCategory(panel, "FreeControl")
	Settings.RegisterAddOnCategory(self.category)
end

-- Brings the page in line with the saved settings.
function Options:Sync()
	if not (self.panel and self.panel.built) then
		return
	end
	for _, control in ipairs(controls) do
		control:Sync()
	end
end

function Options:Open()
	Settings.OpenToCategory(self.category:GetID())
end

---------------------------------------------------------------------------
-- Controller mouse cursor (the "mouse cursor on / off" command and key binding)
---------------------------------------------------------------------------
-- The client can steer the mouse cursor with a stick by itself; this only switches that on and off.
function ns.ToggleCursor()
	if not (SetGamePadCursorControl and IsGamePadCursorControlEnabled) then
		ns.Print("This client has no controller mouse cursor.")
		return
	end
	SetGamePadCursorControl(not IsGamePadCursorControlEnabled())
end

---------------------------------------------------------------------------
-- /fc status
---------------------------------------------------------------------------
local function YesNo(value)
	return value and "yes" or "no"
end

local function PrintStatus()
	local db = ns.db
	ns.Print(("version %s, game interface %s"):format(ns.version, tostring(select(4, GetBuildInfo()))))
	if not db.enabled then
		ns.Print("State: switched off (/fc on).")
	elseif ns.IsGamepadUI() then
		ns.Print("State: idle, because Gamepad UI mode is on (Options > Gamepad).")
	else
		ns.Print("State: active.")
	end

	local connected = C_GamePad and C_GamePad.GetAllDeviceIDs and #C_GamePad.GetAllDeviceIDs() or 0
	ns.Print(("Controller input enabled: %s, controllers connected: %d"):format(
		YesNo(C_GamePad and C_GamePad.IsEnabled and C_GamePad.IsEnabled()), connected))

	Layout.Prepare()
	local source = Layout.GetSlotSource()
	local first = Layout.GetFirstGamepadSlot()
	ns.Print(("Slots: %s (asked for %s). Controller-bar slots start at %s, usable: %s, stance slots usable: %s"):format(
		source, db.slotSource, tostring(first), YesNo(Layout.HasGamepadSlots()), YesNo(Layout.HasStanceSlots())))
	if source == "gamepad" then
		local stanceSet = Layout.GetStanceSet()
		ns.Print(("Page %d, stance set: %s"):format(db.page, stanceSet and Layout.GetSetName(stanceSet) or "none"))
		-- Which slots a stance uses is worked out from the first slot; the client can confirm it
		-- for the stance you are in right now.
		local reported = C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance
			and C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance()
		local bonus = C_ActionBar.GetBonusBarOffset()
		if reported and bonus > 0 and Layout.HasStanceSlots() then
			local expected = Layout.GetStanceSlot(bonus, 1)
			ns.Print(("Stance %d slots start at %d (the game says %d)%s"):format(bonus, expected, reported,
				expected == reported and "" or " |cffff4040- these differ, please report it|r"))
		end
	end

	if ns.IsBuilt() then
		for _, set in ipairs(Layout.SETS) do
			local slots = {}
			for index = 1, 8 do
				slots[index] = tostring(ns.Buttons:GetSlot(set, index) or "-")
			end
			ns.Print(("  %s: %s"):format(Layout.GetSetName(set), table.concat(slots, " ")))
		end
		ns.Print("Secure click handler present: " .. YesNo(not ns.Buttons:IsSecureClickMissing()))
		ns.Print(("Buttons registered with the game: %s. Cooldown numbers: %s"):format(
			ns.Buttons:GetNativeStatus(), YesNo(db.cooldownNumbers)))
		ns.Print("Set held right now: " .. Layout.GetSetName(ns.Bindings:GetActiveSet()))
	end

	ns.Print("Keys: " .. table.concat(db.keys, " ") .. " | triggers: " .. table.concat(db.modKeys, " "))
	for _, problem in ipairs(ns.Bindings:FindProblems()) do
		ns.Print("|cffffd100Note:|r " .. problem)
	end
	for _, line in ipairs(ns.CVars:Describe()) do
		ns.Print("  " .. line)
	end
end

---------------------------------------------------------------------------
-- /fc
---------------------------------------------------------------------------
local HELP = {
	"/fc - open the settings page",
	"/fc on | off - switch FreeControl on or off",
	"/fc lock | unlock - hide or show the handle for dragging the bar",
	"/fc scale <0.5-2> - size of the bar",
	"/fc reset - put the bar back where it started",
	"/fc page <1-3> - which controller-bar page to show",
	"/fc slots gamepad | bars - where the slots are stored",
	"/fc numbers on | off - count down the seconds on slots that are on cooldown",
	"/fc key <1-8 | lt | rt> <KEY> - use a different key for a slot or trigger (1-4 D-pad left/up/right/down, 5-8 face left/top/right/bottom)",
	"/fc status - what FreeControl sees, for bug reports",
}

local function SetKey(which, key)
	key = key and key:upper() or ""
	if key == "" then
		return false
	end
	if which == "lt" then
		SetIndexed("modKeys", 1, key)
	elseif which == "rt" then
		SetIndexed("modKeys", 2, key)
	else
		local index = tonumber(which)
		if not index or index < 1 or index > 8 or index % 1 ~= 0 then
			return false
		end
		SetIndexed("keys", index, key)
	end
	return true
end

SLASH_FREECONTROL1 = "/fc"
SLASH_FREECONTROL2 = "/freecontrol"
SlashCmdList.FREECONTROL = function(message)
	local command, first, second = strsplit(" ", strtrim(message or ""):lower())
	if command == "" then
		Options:Open()
	elseif command == "on" then
		Set("enabled", true)
	elseif command == "off" then
		Set("enabled", false)
	elseif command == "lock" then
		Set("locked", true)
	elseif command == "unlock" then
		Set("locked", false)
	elseif command == "reset" then
		ns.db.point = CopyTable(ns.DEFAULTS.point)
		Set("scale", ns.DEFAULTS.scale)
	elseif command == "scale" and tonumber(first) then
		Set("scale", math.max(0.5, math.min(2, tonumber(first))))
	elseif command == "page" and ns.IsOneOf(tonumber(first), 1, 2, 3) then
		Set("page", tonumber(first))
	elseif command == "slots" and ns.IsOneOf(first, "gamepad", "bars") then
		Set("slotSource", first)
	elseif command == "numbers" and ns.IsOneOf(first, "on", "off") then
		Set("cooldownNumbers", first == "on")
	elseif command == "key" and SetKey(first, second) then
		ns.Print("Keys: " .. table.concat(ns.db.keys, " ") .. " | triggers: " .. table.concat(ns.db.modKeys, " "))
	elseif command == "status" then
		PrintStatus()
	else
		for _, line in ipairs(HELP) do
			ns.Print(line)
		end
	end
end
