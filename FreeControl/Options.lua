local _, ns = ...
local Layout = ns.Layout

-- The settings pages (Options > AddOns > FreeControl, with Mouse mode, Other buttons and
-- Combinations under it), the /fc command, and the menu for choosing what a no-trigger button does.
local Options = {}
ns.Options = Options

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
-- What changes with the stance, named by the four layouts as the rest of the page names them:
-- Main, and the three trigger layouts by the controller's own names for them (LT, RT, LT + RT).
-- The values are Layout.STANCE_CHOICES.
local function LayoutName(set)
	return set == Layout.SET_NONE and "Main" or Layout.GetSetName(set)
end

-- What the button shows: the layouts that change now, by name, whatever choice that comes
-- from. "Main, LT, RT"; "Nothing" for none. A choice typed with /fc stance can change the
-- D-pad alone, which is named too.
local function StanceLabel(value)
	local names = {}
	local flags = Layout.GetStanceFlags(value)
	for _, entry in ipairs(Layout.STANCE_LAYOUTS) do
		if flags[entry[1]] then
			names[#names + 1] = LayoutName(entry[3])
		end
	end
	for _, group in ipairs(Layout.GetStanceGroups(value)) do
		if group.set == Layout.SET_NONE then
			names[#names + 1] = "D-pad"
		end
	end
	return #names > 0 and table.concat(names, ", ") or "Nothing"
end

-- Every choice with its name, for the button that shows the current one.
local function StanceChoices()
	local choices = {}
	for index, value in ipairs(Layout.STANCE_CHOICES) do
		choices[index] = { value, StanceLabel(value) }
	end
	return choices
end
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

-- Buttons offered for the two mouse clicks. The stick clicks and bumpers can be held while the
-- right thumb steers, which dragging needs; the top face button and paddles are there for taste.
local function ClickChoices()
	local choices = {}
	for _, key in ipairs({ "PADLSTICK", "PADRSTICK", "PADLSHOULDER", "PADRSHOULDER", ns.db.keys[6], "PADPADDLE1", "PADPADDLE2" }) do
		choices[#choices + 1] = { key, Layout.GetKeyName(key) }
	end
	choices[#choices + 1] = { "game", "Leave to the game" }
	return choices
end

-- The stances or forms this character has, as jobs for a button: { the game's command, label }.
local function FormJobs()
	local jobs = {}
	for index = 1, math.min(Layout.GetNumForms(), Layout.NUM_FORM_COMMANDS) do
		local command = Layout.GetFormCommand(index)
		jobs[#jobs + 1] = { command, (Layout.GetCommandInfo(command)) }
	end
	return jobs
end

local function AddJobChoices(choices, asRole)
	for _, command in ipairs(Layout.COMMANDS) do
		if command[1] ~= Layout.CURSOR_COMMAND or ns.Mouse:IsEnabled() then
			local binding = command[1]
			if asRole then
				binding = "cmd:" .. binding
			elseif binding == Layout.CURSOR_COMMAND then
				binding = ns.Bindings.MOUSE_COMMAND
			end
			choices[#choices + 1] = { binding, command[2] }
		end
	end
	for _, job in ipairs(FormJobs()) do
		choices[#choices + 1] = { asRole and "cmd:" .. job[1] or job[1], job[2] }
	end
	for _, job in ipairs(Layout.MORE_JOBS) do
		-- One of FreeControl's own buttons (the party's, the chat's) is bound as a click on it, not
		-- as a game command.
		local binding = asRole and "cmd:" .. job[1] or ns.Bindings.PARTY_COMMANDS[job[1]] or ns.Bindings.CHAT_COMMANDS[job[1]]
			or ns.Bindings.GROUP_COMMANDS[job[1]] or ns.Bindings.LOOT_COMMANDS[job[1]] or job[1]
		choices[#choices + 1] = { binding, job[2] }
	end
end

local function RoleChoices()
	local choices = { { "action", "Action slot" }, { "pass", "My own key binding" } }
	AddJobChoices(choices, true)
	for _, command in ipairs(Layout.PAGE_ROLES) do
		choices[#choices + 1] = { "cmd:" .. command[1], command[2] }
	end
	choices[#choices + 1] = { "cmd:" .. Layout.RELEASE_ROLE_COMMAND, "Return to main layer" }
	choices[#choices + 1] = { "none", "Nothing" }
	choices[#choices + 1] = { "keybindings", "Something else...", true }
	return choices
end

-- Label of the current value; a value typed by hand (a key or command not in the list) shows as itself.
local function LabelFor(choices, value)
	for _, choice in ipairs(choices) do
		if choice[1] == value then
			return choice[2]
		end
	end
	-- A command that is not offered here: one typed by hand, or a stance this character lacks
	-- (the buttons' jobs are shared by every character on the account).
	local command = type(value) == "string" and value:match("^cmd:(.+)$")
	if command then
		return (Layout.GetCommandInfo(command))
	end
	return tostring(value)
end

---------------------------------------------------------------------------
-- Changing a setting
---------------------------------------------------------------------------
local function Set(key, value)
	ns.GetSettingStore(key)[key] = value
	ns.RequestRefresh()
end

local function SetIndexed(key, index, value)
	ns.db[key][index] = value
	ns.RequestRefresh()
end

-- Opens a menu of choices next to `owner`; get() returns the current value. A choice with a
-- third field is something to do, not a value to have: it is a plain entry in the menu. Without
-- the menu system the button steps through the values instead.
local function Choose(owner, choices, get, onPick)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, function(_, root)
			for _, choice in ipairs(choices) do
				if choice[3] then
					root:CreateButton(choice[2], function() onPick(choice[1]) end)
				else
					root:CreateRadio(choice[2], function() return choice[1] == get() end, function() onPick(choice[1]) end)
				end
			end
		end)
		return
	end
	local values, position = {}, 0
	for _, choice in ipairs(choices) do
		if not choice[3] then
			values[#values + 1] = choice[1]
			if choice[1] == get() then
				position = #values
			end
		end
	end
	onPick(values[position % #values + 1])
end

-- side 1 is the left click, 2 the right. Returns false, having said why, if the button cannot be used.
local function SetClick(side, value)
	local db = ns.db
	local mine, other = side == 1 and "clickLeft" or "clickRight", side == 1 and "clickRight" or "clickLeft"
	if value ~= "game" then
		if value == db.modKeys[1] or value == db.modKeys[2] then
			ns.Print(("%s is a trigger, so it cannot also be a mouse click."):format(Layout.GetKeyName(value)))
			return false
		end
		if db[other] == value then
			db[other] = db[mine] -- choosing the other click's button swaps the two
		end
	end
	db[mine] = value
	ns.RequestRefresh()
	return true
end

local function SetRole(set, index, value, spell)
	local openBindings = value == "keybindings"
	if openBindings then value = "pass" end
	if spell then
		-- A form's own Main layout is the same on every page.
		local roles = ns.db.mainFormRoles
		roles[spell] = roles[spell] or {}
		roles[spell][index] = value ~= "action" and value or nil
	else
		-- Any other job is for the page the bar is showing.
		Layout.SetRole(set, index, value)
	end
	ns.RequestRefresh()
	if openBindings then Options:OpenKeyBindings() end
end

function Options:OpenRoleMenu(owner, index, set, spell)
	if InCombatLockdown() then
		ns.Print("Buttons cannot be changed in combat.")
		return
	end
	set = set or Layout.SET_NONE
	Choose(owner, RoleChoices(), function() return Layout.GetRole(set, index, spell) end, function(value)
		SetRole(set, index, value, spell)
	end)
end

-- The controller's slots have no place for a face button with no trigger held; the regular
-- action bars do, and have one page.
local function MouseModeTip()
	local text = "A button on the bar (Y unless you changed it) brings out a mouse pointer that the right stick steers. Untick it and that button is an ordinary action slot instead"
	if Layout.GetSlotSource() ~= "gamepad" then
		return text .. ": it holds whatever you drop on it."
	end
	return text .. ": on each page it holds whatever you drop on it. It keeps that in a slot of its own for each page, on the second page of the game's main action bar (the controller's slots have no place for it)."
end

-- The explanation of a page setting, which says so while there are no pages for it to act on.
local function PageTip(text)
	return function()
		if Layout.GetSlotSource() ~= "gamepad" then
			return text .. " With the regular action bars as the slots there is one page, so this changes nothing."
		end
		return text
	end
end

-- What the Stance sets choice comes to on this character, said under its explanation.
local function StanceTooltip()
	local text = ("The bar has four layouts: Main (no trigger), %s, %s and %s. Tick the ones that show different buttons in each stance or form, so that a stance has its own abilities there. You can tick Main and two of the other three: that is all the game has room to store. Untick all four and nothing changes with your stance. They change on one page only, and the other pages are the same in every stance."):format(
		LayoutName(Layout.SET_LT), LayoutName(Layout.SET_RT), LayoutName(Layout.SET_BOTH))
	if Layout.GetSlotSource() ~= "gamepad" and ns.GetBarProfile().stanceSet == "auto" then
		text = text .. " With the regular action bars as the slots, nothing changes until you tick a layout."
	end
	if not Layout.HasStances() then
		return text .. "\n\nOn this character: nothing. This class has no stance or form that changes what it can cast (a Paladin's auras and a Priest's Shadowform do not), so every layout stays as it is."
	end
	return ("%s\n\nOn this character: %s."):format(text, Layout.DescribeStance())
end

-- The player's own pick of the layouts that change with the stance. `flags` is the four settings
-- of Layout.STANCE_LAYOUTS. More trigger sets than there is room for: the last are dropped, and
-- that is said.
local function SetStanceLayouts(flags)
	local dropped = Layout.LimitStanceSets(flags)
	local profile = ns.GetBarProfile()
	for _, entry in ipairs(Layout.STANCE_LAYOUTS) do
		profile[entry[1]] = flags[entry[1]] and true or false
	end
	profile.stanceSet = "custom"
	if dropped then
		ns.Print(("Only two of %s, %s and %s can change with your stance or form: the game has a place to keep the buttons of two. The third was left as it is."):format(
			LayoutName(Layout.SET_LT), LayoutName(Layout.SET_RT), LayoutName(Layout.SET_BOTH)))
	end
	-- In combat the change waits for the fight to end, and RequestRefresh has said so.
	if ns.RequestRefresh() then
		ns.Print(("Changes with your stance or form: %s."):format(Layout.DescribeStance()))
	end
end

-- Ticks or unticks one layout, starting from what changes now, whatever choice that came from.
local function ToggleStanceLayout(key)
	local flags = Layout.GetStanceFlags()
	local wanted = not flags[key]
	if wanted and key ~= "stanceMain" then
		local count = 0
		for index = 2, #Layout.STANCE_LAYOUTS do
			count = count + (flags[Layout.STANCE_LAYOUTS[index][1]] and 1 or 0)
		end
		if count >= Layout.MAX_STANCE_SETS then
			ns.Print(("Only two of %s, %s and %s can change with your stance or form: the game has a place to keep the buttons of two. Untick one of them first."):format(
				LayoutName(Layout.SET_LT), LayoutName(Layout.SET_RT), LayoutName(Layout.SET_BOTH)))
			return
		end
	end
	flags[key] = wanted
	SetStanceLayouts(flags)
end

-- The menu of what changes with the stance: a tick for each of the four layouts, and nothing
-- else. Nothing is picked for the player in it: the ticks show what changes now, and ticking or
-- unticking one makes the four the player's own from then on. Without the menu system the
-- button steps through the choices /fc stance has names for.
local function ChooseStance(owner)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		local profile = ns.GetBarProfile()
		local values, position = {}, 0
		for _, value in ipairs(Layout.STANCE_CHOICES) do
			if value ~= "custom" then
				values[#values + 1] = value
				if value == profile.stanceSet then position = #values end
			end
		end
		profile.stanceSet = values[position % #values + 1]
		ns.RequestRefresh()
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		-- A client whose menus have no tick boxes gets entries that toggle all the same.
		local add = root.CreateCheckbox or root.CreateRadio
		for _, entry in ipairs(Layout.STANCE_LAYOUTS) do
			add(root, LayoutName(entry[3]), function() return Layout.GetStanceFlags()[entry[1]] end, function() ToggleStanceLayout(entry[1]) end)
		end
	end)
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
local ROW = 26
local controls = {} -- every widget with a Sync function

-- A setting's label, tooltip or list of choices is given as it is, or as a function that works
-- it out when it is wanted (a button's name follows the controller style, for one).
local function Resolve(value)
	if type(value) == "function" then
		return value()
	end
	return value
end

-- `title` and `text` can be functions, for a tooltip that depends on the character or the moment.
-- Version 1.5.0 read the title back from the label on the page, and the game has nothing to give
-- back for a label that is empty: hovering a row without one raised an error instead.
local function AddTooltip(widget, title, text)
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(Resolve(title), 1, 1, 1)
		GameTooltip:AddLine(Resolve(text), nil, nil, nil, true)
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

-- A tick box for the setting `key`. `store(value)` is for a setting that takes more than being
-- written down; without it the value is saved and the settings applied.
local function Check(panel, x, y, label, tooltip, key, store)
	local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	check:SetSize(26, 26)
	check:SetPoint("TOPLEFT", x, y)
	check.Text:SetText(label)
	check.Text:SetFontObject("GameFontHighlight")
	AddTooltip(check, label, tooltip)
	check:SetScript("OnClick", function(self)
		local value = self:GetChecked() and true or false
		if store then
			store(value)
		else
			Set(key, value)
		end
	end)
	check.Sync = function(self)
		self:SetChecked(ns.GetSettingStore(key)[key])
	end
	controls[#controls + 1] = check
	return y - ROW
end

-- A label with a button showing the current choice. get() returns the value, set(value) stores it.
-- The label, the tooltip and the choices can each be a function (see Resolve); a label that is
-- one is brought up to date whenever the page is. Returns the next row's y, the button and the
-- label's font string.
local function Choice(panel, x, y, label, tooltip, choices, get, set, width)
	local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("TOPLEFT", x + 4, y - 6)
	text:SetText(Resolve(label))

	local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	button:SetSize(width or 170, 22)
	button:SetPoint("TOPLEFT", x + 130, y - 2)
	AddTooltip(button, label, tooltip)
	button:SetScript("OnClick", function(self)
		Choose(self, Resolve(choices), get, set)
	end)
	button.Sync = function(self)
		text:SetText(Resolve(label))
		self:SetText(LabelFor(Resolve(choices), get()))
	end
	controls[#controls + 1] = button
	return y - ROW, button, text
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

-- A button that does something, with an optional label in front of it.
local function Action(panel, x, y, label, tooltip, onClick, caption)
	if caption then
		local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		text:SetPoint("TOPLEFT", x + 4, y - 6)
		text:SetText(caption)
	end
	local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	button:SetSize(170, 22)
	button:SetPoint("TOPLEFT", x + 130, y - 2)
	button:SetText(label)
	AddTooltip(button, label, tooltip)
	button:SetScript("OnClick", onClick)
	return y - ROW, button
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
	note:SetText("Press a trigger to toggle its set, or press both together to toggle the combined set. Assign Return to main layer under Other buttons or Key Bindings. Unassigned bumpers, stick clicks, Start, Back and paddles keep their usual jobs.")

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
		function() return ns.GetBarProfile().slotSource end, function(value) Set("slotSource", value) end)
	y = Check(panel, left, y, "Pages", PageTip("The bar has three pages, each with its own buttons, and the page can be turned: by the selector under the LT + RT set, or by any button you give that job under Other buttons. Untick it to keep the bar on one page, the one picked under Page below. Nothing turns it then."), "pages")
	y = Check(panel, left, y, "Page selector on the bar", PageTip("The small plate under the LT + RT set that shows the page and turns it. Untick it to take it off the bar: the page can still be turned by a button you gave that job."), "showPager")
	y = Choice(panel, left, y, "Page", PageTip("Which of the three controller-bar pages the bar shows. Each page has its own buttons. With Pages ticked, the selector under the LT + RT set turns the page as well, in a fight too, and so does any button you give that job under Other buttons."), PAGES,
		function() return ns.GetBarProfile().page end, function(value) Set("page", value) end)
	local stanceButton
	y, stanceButton = Choice(panel, left, y, "Change with stance", StanceTooltip, StanceChoices,
		function() return ns.GetBarProfile().stanceSet end, function(value) Set("stanceSet", value) end)
	stanceButton:SetScript("OnClick", ChooseStance)

	y = Heading(panel, "Mouse mode and other buttons", left, y - 8)
	y = Check(panel, left, y, "Mouse mode", MouseModeTip, "mouseMode", ns.SetMouseMode)
	y = Action(panel, left, y, "Clicks and speed...", "Opens the Mouse mode page: which two buttons click while the mouse pointer is out, how fast the stick moves it, and whether the game may bring the pointer out by itself.", function()
		Options:OpenMouse()
	end, "Mouse pointer")
	y = Action(panel, left, y, "Other buttons...", "The bumpers, stick clicks, Start, Back and paddles are ordinary buttons: FreeControl does not use them, and each does whatever you bind it to. This opens the page where you give them jobs, such as turning the bar's page. Buttons pressed together can have a job as well: that is the Combinations page.", function()
		Options:OpenButtons()
	end, "Bumpers, paddles")

	y = -78
	y = Heading(panel, "Controller", right, y)
	y = Check(panel, right, y, "Turn on controller input", "Sets GamePadEnable while FreeControl is active so the game reads your controller. This is not Gamepad UI mode. Untick it if a tool such as Steam Input already turns your controller into key presses.", "manageGamepad")
	y = Check(panel, right, y, "Interact finds things by itself", "The Interact command picks the nearest corpse to loot, person to talk to or object to use, as in Gamepad UI mode (Options > Controls > Enable Interact Key).", "softInteract")
	y = Check(panel, right, y, "Gamepad UI interact reach", "Uses the wider arc and 20 yard range that Gamepad UI mode uses for Interact.", "interactReach")
	y = Check(panel, right, y, "Gamepad UI enemy targeting", "The game picks an enemy for you by where you face, and out of the box it can be one anywhere around you. Gamepad UI mode narrows that to the enemies in front of you. Tick this to do the same (console variable SoftTargetEnemyArc 1; your own value is put back when FreeControl is switched off). What Gamepad UI mode also does and an addon is not allowed to: make that enemy your target the moment you attack.", "frontTargeting")
	y = Choice(panel, right, y, "Left trigger", "Press to lock or unlock the left set. Press both triggers together to toggle the combined set.", TRIGGER_KEYS,
		function() return ns.db.modKeys[1] end, function(value) SetIndexed("modKeys", 1, value) end)
	y = Choice(panel, right, y, "Right trigger", "Press to lock or unlock the right set. Press both triggers together to toggle the combined set.", TRIGGER_KEYS,
		function() return ns.db.modKeys[2] end, function(value) SetIndexed("modKeys", 2, value) end)
	y = Check(panel, right, y, "Toggle layers", "Checked: press a trigger to lock its layer and press it again to unlock. Unchecked: hold triggers to shift layers and release them to return to Main.", "toggleLayers")

	y = Heading(panel, "Button assignments", right, y - 8)
	local editingSet = Layout.SET_NONE
	local function EditingLayer()
		if editingSet <= 3 then return editingSet end
		return Layout.SET_NONE, editingSet
	end
	y = Choice(panel, right, y, "Layout", "Choose a layer or a stance's Main layout to edit all eight buttons.", function()
		local choices = { { Layout.SET_NONE, "Main" } }
		for set = 1, 3 do
			choices[#choices + 1] = { set, Layout.GetSetName(set) }
		end
		local header = ns.Bindings.header
		if header then
			for form = 1, Layout.NUM_FORM_COMMANDS do
				local spell = header:GetAttribute("fc-main-spell-" .. form)
				if spell then
					choices[#choices + 1] = { spell, "Main: " .. Layout.GetFormInfo(form) }
				end
			end
		end
		return choices
	end, function() return editingSet end, function(set)
		editingSet = set
		Options:Sync()
	end)
	for index = 1, 8 do
		y = Choice(panel, right, y, function() return Layout.GetButtonName((EditingLayer()), index) end,
			"Choose a special command, an action slot, or your own key binding for this button on the selected layout. The job is for the page the bar is showing: the other pages keep their own. Something else opens WoW's Key Bindings and lets that binding take over on this layout.", RoleChoices,
			function()
				local set, spell = EditingLayer()
				return Layout.GetRole(set, index, spell)
			end, function(value)
				local set, spell = EditingLayer()
				SetRole(set, index, value, spell)
			end)
	end

	y = Heading(panel, "Spells", right, y - 8)
	y = Check(panel, right, y, "Glow when a spell procs", "A button glows while the game says its spell has procced, as on the regular action bars, and while an ability such as Overpower or Riposte has come free for a moment.", "procGlow")
	y = Check(panel, right, y, "Keep spells at their newest rank", "When you learn a new rank of a spell, the copies on these slots are moved up to it, as the game does for the regular action bars. A lower rank you put on a slot yourself is left alone.", "keepRanks")
end

---------------------------------------------------------------------------
-- The Other buttons page
---------------------------------------------------------------------------
-- FreeControl binds the D-pad, the face buttons and the two triggers itself. Every other button
-- on a controller is an ordinary button to the game: it has one of the player's own key
-- bindings, exactly as a key on the keyboard has. Players took their bumpers and paddles for
-- missing, so this page lists them with what each one does and offers the common jobs in a
-- menu. Picking one sets a real key binding, the same one the Key Bindings screen would set.

-- A button's name, or a combination's: "LB + RB + D-pad Right" for ALT-CTRL-PADDRIGHT, each
-- modifier by the button that is held for it, or by its own name where no button is.
local MODIFIER_NAMES = { ALT = "Alt", CTRL = "Ctrl", SHIFT = "Shift" }

local function KeyName(key)
	local modifiers, button = Layout.SplitChord(key)
	local parts = {}
	for index, modifier in ipairs(modifiers) do
		local held = ns.CVars:GetCombinationButton(MODIFIER_NAMES[modifier])
		parts[index] = held and Layout.GetKeyName(held) or MODIFIER_NAMES[modifier]
	end
	table.sort(parts) -- LB before RB, whichever of them is Ctrl
	parts[#parts + 1] = Layout.GetKeyName(button)
	return table.concat(parts, " + ")
end

-- What FreeControl itself uses a button for, in a few words, or nil for a button that is the
-- player's own. A combination is always the player's own, whatever button it ends in (the game
-- looks for the combination's binding before the button's), and its name is never a button's.
local function OwnUse(key)
	local db = ns.db
	if key == db.modKeys[1] then
		return "FreeControl's left trigger"
	elseif key == db.modKeys[2] then
		return "FreeControl's right trigger"
	end
	for index = 1, 8 do
		if key == db.keys[index] then
			return "FreeControl's " .. Layout.GetButtonName(Layout.SET_NONE, index)
		end
	end
	return nil
end

-- The game can be set to use a controller button as a stand-in for Shift, Ctrl or Alt, and uses
-- the left bumper for Ctrl unless told otherwise: the reason a bumper can seem to be missing.
-- Such a button has no job of its own until the player gives it one here (CVars.lua then makes
-- it a plain button for as long as FreeControl is active).
local function StandIn(key)
	if ns.db.plainKeys[key] then
		return nil
	end
	return ns.CVars:GetStandIn(key)
end

-- The jobs in the menu: { binding command, label }. "" is no job at all.
local function JobChoices(key)
	local modifier = StandIn(key)
	local choices = {
		{ "", modifier and ("Stand in for the %s key"):format(modifier) or "Nothing" },
		{ ns.Bindings.PAGE_COMMANDS.next, "FreeControl: next page" },
		{ ns.Bindings.PAGE_COMMANDS.prev, "FreeControl: previous page" },
		{ ns.Bindings.RELEASE_COMMAND, "Return to main layer" },
	}
	AddJobChoices(choices, false)
	-- A binding made somewhere else is listed too, so the menu always shows what the button does.
	local current = GetBindingAction(key)
	local listed = false
	for _, choice in ipairs(choices) do
		listed = listed or choice[1] == current
	end
	if not listed then
		local label = GetBindingName(current)
		if Layout.GetCommandForm(current) then
			label = (Layout.GetCommandInfo(current))
		elseif current == ns.Bindings.MOUSE_COMMAND then
			-- Given the job earlier; it does nothing now, and the row says why.
			label = ns.Mouse:IsAvailable() and "Mouse pointer on / off (mouse mode is off)" or "Mouse pointer on / off (this client has no pointer)"
		end
		table.insert(choices, 2, { current, label })
	end
	choices[#choices + 1] = { "keybindings", "Something else...", true }
	return choices
end

function Options:OpenKeyBindings()
	Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)
end

-- Saves the active key map for this character. On the first edit it inherits the account map.
-- Saving changes to the account map from here would also change other characters' controllers.
local function SaveCharacterBindings()
	SaveBindings(Enum.BindingSet and Enum.BindingSet.Character or 2)
end

-- Gives a button a job, as one of the player's character bindings. Returns true when it was done.
local function Bind(key, command)
	if command == "keybindings" then
		Options:OpenKeyBindings()
		return false
	elseif InCombatLockdown() then
		ns.Print("Key bindings cannot be changed in combat.")
		return false
	end
	local name = KeyName(key)
	local isChord = Layout.IsChord(key)
	local modifier = ns.CVars:GetStandIn(key) -- none for a combination
	local chosen = modifier and ns.db.standIns[modifier] == key
	if command == "" then
		SetBinding(key, nil)
	elseif not SetBinding(key, command) then
		ns.Print(("The game would not bind %s to that."):format(name))
		return false
	end
	SaveCharacterBindings()
	-- A button with a job is a plain button; one without is whatever the game makes of it.
	if not isChord then
		ns.db.plainKeys[key] = command ~= "" or nil
	end
	if command ~= "" then
		ns.Print(("%s now does this: %s.%s"):format(name, LabelFor(JobChoices(key), command),
			modifier and (" It no longer stands in for the %s key while FreeControl is active."):format(modifier) or ""))
	elseif modifier then
		ns.Print(("%s has no job of its own now, and stands in for the %s key again%s"):format(name, modifier,
			chosen and ", as you chose on the Combinations page." or ", as the game has it set."))
	else
		ns.Print(("%s now does nothing."):format(name))
	end
	if ns.IsActive() then
		ns.CVars:Apply() -- the stand-in follows the job
	end
	Options:RecordKeys()
	Options:Sync()
	return true
end
Options.Bind = Bind

-- A row for one button: its name, and a button showing its job that opens the menu of jobs.
-- getKey() names the button; a row without one (nothing caught yet) hides itself.
local function KeyRow(panel, x, y, getKey, width)
	local function Job()
		return GetBindingAction(getKey())
	end
	local function Tooltip()
		local key = getKey()
		local text = "What this button does. Pick a job from the list, or Something else to open the game's Key Bindings screen, where it can be given any command, spell or macro."
		if Layout.IsChord(key) then
			text = ("What these buttons do when they are pressed together. Pick a job from the list, or Something else to open the game's Key Bindings screen, where the combination is spelled %s."):format(key)
		end
		if key == ns.Mouse:GetManagedKey(1) or key == ns.Mouse:GetManagedKey(2) then
			text = text .. (" While the mouse pointer is out it is the %s mouse button instead."):format(key == ns.Mouse:GetManagedKey(1) and "left" or "right")
		end
		local modifier, cvar = StandIn(key)
		if modifier then
			text = text .. (" Right now the game uses it as a stand-in for the %s key (its %s setting), so a job of its own would come late or not at all. Pick a job here and FreeControl makes it a plain button while it is active."):format(modifier, cvar)
		end
		return text
	end
	local function Name()
		local key = getKey()
		return key and KeyName(key) or ""
	end
	local nextY, button, label = Choice(panel, x, y, Name, Tooltip, function() return JobChoices(getKey()) end, Job,
		function(command) Bind(getKey(), command) end, width or 230)
	local showJob = button.Sync
	button:SetScript("OnClick", function(self)
		local own = OwnUse(getKey())
		if own then
			ns.Print(("%s is %s, so a key binding on it would never be reached. The main page and /fc key change which buttons FreeControl uses; held together with another button it can have a job, on the Combinations page."):format(Layout.GetKeyName(getKey()), own))
			return
		end
		Choose(self, JobChoices(getKey()), Job, function(command) Bind(getKey(), command) end)
	end)
	button.Sync = function(self)
		local key = getKey()
		self:SetShown(key ~= nil)
		label:SetShown(key ~= nil)
		if not key then
			return
		end
		showJob(self) -- the name, and the job: for a stand-in with none, what it stands in for
		local own = OwnUse(key)
		if own then
			self:SetText(own)
		end
	end
	return nextY
end

-- Listens for the next button or key, for the row that takes any of them. It covers the page
-- while it listens, so that the press goes nowhere else; Escape or a click ends it.
local IGNORED_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true, RMETA = true, UNKNOWN = true }

local function CreateCatcher(panel, onKey)
	local catcher = CreateFrame("Frame", nil, panel)
	catcher:SetAllPoints()
	catcher:SetFrameStrata("DIALOG")
	catcher:EnableMouse(true)
	catcher:EnableKeyboard(true)
	if catcher.EnableGamePadButton then
		catcher:EnableGamePadButton(true)
	end
	catcher:Hide()

	local shade = catcher:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(0, 0, 0, 0.85)
	local text = catcher:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	text:SetPoint("CENTER")
	text:SetText("Press the button or key you want to give a job.\nFor a combination, hold the first button and press the second.\n\nEscape or a click cancels.")

	-- A button pressed while Ctrl, Alt or Shift is held (or a controller button that stands in for
	-- one of them) is a combination, named as the game names it: CTRL-PADDRIGHT. The key or button
	-- that is held is waited through. Whether the game reports a held stand-in button here at all
	-- is not known, so one that is reported is passed over like the Shift key itself.
	local function Caught(self, key)
		if IGNORED_KEYS[key] or ns.CVars:IsStandInNow(key) then
			return
		end
		self:Hide()
		if key ~= "ESCAPE" then
			onKey(Layout.JoinChord({ ALT = IsAltKeyDown(), CTRL = IsControlKeyDown(), SHIFT = IsShiftKeyDown() }, key))
		end
	end
	catcher:SetScript("OnKeyDown", Caught)
	catcher:SetScript("OnGamePadButtonDown", Caught)
	catcher:SetScript("OnMouseDown", catcher.Hide)
	return catcher
end

local EXTRA_KEY_ROWS = 12

local function BuildButtons(panel)
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", 16, -14)
	title:SetText("Other buttons")

	local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", 18, -40)
	note:SetPoint("RIGHT", -20, 0)
	note:SetJustifyH("LEFT")
	note:SetText("FreeControl uses the D-pad, the four face buttons and the two triggers. Every other button on your controller is an ordinary button: it does whatever it is bound to, like a key on the keyboard. Give each one a job here. A job picked here is a normal key binding, so it shows in the game's Key Bindings screen as well and stays when FreeControl is switched off. This page is the same for all your characters: FreeControl gives each of them these jobs when it enters the world.")

	local left, right = 16, 340
	local y = -90
	y = Heading(panel, "On most controllers", left, y)
	for _, key in ipairs(Layout.OTHER_KEYS) do
		y = KeyRow(panel, left, y, function() return key end, 180)
	end

	local page = 1
	local function PageCount()
		return math.max(1, math.ceil(#ns.db.extraKeys / EXTRA_KEY_ROWS))
	end
	local extraY = Heading(panel, "Any other button or key", right, -90)
	local catcher = CreateCatcher(panel, function(key)
		for _, ordinary in ipairs(Layout.OTHER_KEYS) do
			if ordinary == key then
				ns.Print(Layout.GetKeyName(key) .. " is already listed under On most controllers.")
				return
			end
		end
		local keys = ns.db.extraKeys
		local index = #keys + 1
		for i, known in ipairs(keys) do
			if known == key then
				index = i
				break
			end
		end
		keys[index] = key
		page = math.ceil(index / EXTRA_KEY_ROWS)
		Options:Sync()
	end)
	Options.catcher = catcher
	extraY = Action(panel, right, extraY, "Press it...", "Press a controller button or keyboard key to add it to the list. Use the list to assign or change its job.", function()
		if InCombatLockdown() then
			ns.Print("Key bindings cannot be changed in combat.")
			return
		end
		catcher:Show()
	end, "Add a button")

	local _, previous, nextPage
	local pageLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	pageLabel:SetPoint("TOPLEFT", right + 4, extraY - EXTRA_KEY_ROWS * ROW - 6)
	pageLabel.Sync = function(self)
		local count = PageCount()
		page = math.min(page, count)
		self:SetText(("%d / %d"):format(page, count))
		self:SetShown(count > 1)
		previous:SetShown(count > 1)
		nextPage:SetShown(count > 1)
		previous:SetEnabled(page > 1)
		nextPage:SetEnabled(page < count)
	end
	controls[#controls + 1] = pageLabel
	for row = 1, EXTRA_KEY_ROWS do
		extraY = KeyRow(panel, right, extraY, function()
			return ns.db.extraKeys[(page - 1) * EXTRA_KEY_ROWS + row]
		end, 170)
	end
	local function ChangePage(step)
		page = math.max(1, math.min(PageCount(), page + step))
		Options:Sync()
	end
	_, previous = Action(panel, right - 48, extraY, "Previous", "Show the previous extra buttons.", function() ChangePage(-1) end)
	previous:SetSize(90, 22)
	_, nextPage = Action(panel, right + 52, extraY, "Next", "Show the next extra buttons.", function() ChangePage(1) end)
	nextPage:SetSize(90, 22)

	y = Heading(panel, "Everything else", left, y - 8)
	y = Action(panel, left, y, "Combinations...", "Two or three buttons pressed together can have a job of their own: LB + D-pad Up, or LB + RB + D-pad Right. This opens the page where you pick the buttons to hold and give combinations their jobs.", function()
		Options:OpenCombos()
	end, "Buttons together")
	Action(panel, left, y, "Open Key Bindings", "The game's Key Bindings screen lists FreeControl's page buttons and Return to main layer.", function()
		Options:OpenKeyBindings()
	end, "Key Bindings")
end

---------------------------------------------------------------------------
-- The Combinations page
---------------------------------------------------------------------------
-- Two or three buttons pressed together can be a button of their own. The game does it with the
-- keyboard's modifier keys: a controller button can stand in for Ctrl, Alt or Shift (CVars.lua),
-- and a button pressed while one is held is a combination with a key binding of its own,
-- CTRL-PADDRIGHT for LB + D-pad Right. The game looks for the combination's binding before the
-- button's own, so FreeControl's buttons can end a combination too: its D-pad and face buttons
-- are only bound as themselves. This page picks the buttons to hold, hears a combination and
-- gives it a job, and lists the combinations that have one. The game has no screen for the
-- first part; the jobs are ordinary key bindings and show in its Key Bindings screen.
local HOLD_MODIFIERS = { "Ctrl", "Alt", "Shift" }
local COMBO_ROWS = 10

-- The buttons that can be held: the other buttons, less any FreeControl uses itself.
local function HoldChoices(modifier)
	local choices = { { "none", "No button" } }
	local current = ns.CVars:GetCombinationButton(modifier)
	local listed = current == nil
	for _, key in ipairs(Layout.OTHER_KEYS) do
		if not OwnUse(key) and key ~= ns.Mouse:GetManagedKey(1) and key ~= ns.Mouse:GetManagedKey(2) then
			choices[#choices + 1] = { key, Layout.GetKeyName(key) }
			listed = listed or key == current
		end
	end
	if not listed then
		choices[#choices + 1] = { current, Layout.GetKeyName(current) } -- one set by hand, with /console
	end
	return choices
end

-- Makes a button the one that is held as Ctrl, Alt or Shift, or (with "none") leaves that
-- modifier without a button. Returns true when it was done.
local function SetHold(modifier, key)
	if InCombatLockdown() then
		ns.Print("Combination buttons cannot be changed in combat.")
		Options:Sync()
		return false
	end
	local db = ns.db
	if key ~= "none" then
		local name = Layout.GetKeyName(key)
		if not key:find("^PAD") then
			ns.Print(("%s is not a button of the controller. They go by the game's names for them, such as PADRSHOULDER or PADPADDLE1; none is for no button."):format(key))
			Options:Sync()
			return false
		end
		if OwnUse(key) or key == ns.Mouse:GetManagedKey(1) or key == ns.Mouse:GetManagedKey(2) then
			ns.Print(("%s is one of the buttons FreeControl uses itself, so it cannot be held for combinations."):format(name))
			Options:Sync()
			return false
		end
		-- A button that is held has no job of its own: the game would only run it on a quick tap.
		local job = GetBindingAction(key)
		if job ~= "" then
			local label = LabelFor(JobChoices(key), job)
			SetBinding(key, nil)
			SaveCharacterBindings()
			ns.Print(("%s no longer does this: %s. A button that is held for combinations has no job of its own."):format(name, label))
		end
		db.plainKeys[key] = nil
		for _, other in ipairs(HOLD_MODIFIERS) do
			if other ~= modifier and db.standIns[other] == key then
				db.standIns[other] = nil
			end
		end
		ns.Print(("%s is the button to hold as %s now: hold it and press another button, and the two together are a combination."):format(name, modifier))
	else
		ns.Print(("No button is held as %s now."):format(modifier))
	end
	db.standIns[modifier] = key
	if ns.IsActive() then
		ns.CVars:Apply()
	end
	Options:RecordKeys()
	Options:Sync()
	return true
end
Options.SetHold = SetHold

-- Every combination that ends in a controller button and has a job, in the game's order.
local function BoundCombos()
	local seen, list = {}, {}
	local function Add(...)
		for index = 1, select("#", ...) do
			local key = select(index, ...)
			if key and not seen[key] and Layout.IsPadChord(key) then
				seen[key] = true
				list[#list + 1] = key
			end
		end
	end
	-- GetBinding gives a command, its category and then its keys. Everything after the command is
	-- looked at, so that nothing hangs on where the keys begin: a category is no combination.
	for index = 1, GetNumBindings() do
		Add(select(2, GetBinding(index)))
	end
	Add(GetBindingKey(ns.Bindings.MOUSE_COMMAND)) -- FreeControl's own, and not in the game's list
	table.sort(list)
	return list
end

---------------------------------------------------------------------------
-- The other buttons and the combinations belong to the account
---------------------------------------------------------------------------
-- Their jobs are key bindings, and the game keeps a character's bindings apart from every other
-- character's and lets none read another's. So what these two pages set is written down in a
-- file the whole account shares (FreeControlKeysDB), and every character is given it when it
-- enters the world: the jobs of the other buttons and of the combinations, the extra buttons
-- that were added to the list, and the buttons to hold.
--   { jobs = { [key or combination] = binding command }, extraKeys =, plainKeys =, standIns = }
-- (the last three as in ns.db). The first character played with this in place is the one the
-- account starts from. The buttons FreeControl uses itself on a character are left alone there.
Options.keysApplied = false -- this character has been given the account's; until then nothing is written down

-- This character's other buttons and combinations, as they are now.
local function CurrentKeys()
	local db = ns.db
	local keys = { jobs = {}, extraKeys = {}, plainKeys = {}, standIns = {} }
	local function Add(key)
		local job = not OwnUse(key) and GetBindingAction(key) or ""
		if job ~= "" then
			keys.jobs[key] = job
		end
	end
	for _, key in ipairs(Layout.OTHER_KEYS) do Add(key) end
	for index, key in ipairs(db.extraKeys) do
		keys.extraKeys[index] = key
		Add(key)
	end
	for _, key in ipairs(BoundCombos()) do Add(key) end
	for key in pairs(db.plainKeys) do keys.plainKeys[key] = true end
	for modifier, button in pairs(db.standIns) do keys.standIns[modifier] = button end
	return keys
end

local function AccountKeys()
	local saved = FreeControlKeysDB
	return type(saved) == "table" and type(saved.jobs) == "table" and saved or nil
end

-- Writes this character's down as the account's. A button FreeControl uses itself on this
-- character keeps the job the account has for it: it is another character's to use.
function Options:RecordKeys()
	if not (ns.db and Options.keysApplied) then
		return
	end
	local keys, before = CurrentKeys(), AccountKeys()
	for key, job in pairs(before and before.jobs or {}) do
		if type(key) == "string" and OwnUse(key) then
			keys.jobs[key] = job
		end
	end
	FreeControlKeysDB = keys
end

-- Out of combat. Makes this character's other buttons and combinations the account's: every
-- job the account has is given, and a job this character has where the account has none is
-- taken away. With nothing written down yet, this character's become the account's.
local function ApplyAccountKeys()
	local keys = AccountKeys()
	Options.keysApplied = true
	if not keys then
		Options:RecordKeys()
		return
	end
	local db = ns.db
	local mine = CurrentKeys()
	local touched, changed = {}, false
	for key in pairs(mine.jobs) do touched[key] = true end
	for key, job in pairs(keys.jobs) do
		if type(key) == "string" and type(job) == "string" and job ~= "" then touched[key] = true end
	end
	for key in pairs(touched) do
		local job = keys.jobs[key]
		if type(job) ~= "string" or job == "" then job = nil end
		if not OwnUse(key) and mine.jobs[key] ~= job then
			SetBinding(key, job)
			changed = true
		end
	end
	if changed then
		SaveCharacterBindings()
	end
	db.extraKeys, db.plainKeys, db.standIns = {}, {}, {}
	for _, key in ipairs(type(keys.extraKeys) == "table" and keys.extraKeys or {}) do
		if type(key) == "string" then db.extraKeys[#db.extraKeys + 1] = key end
	end
	for key in pairs(type(keys.plainKeys) == "table" and keys.plainKeys or {}) do
		if type(key) == "string" then db.plainKeys[key] = true end
	end
	for _, modifier in ipairs(HOLD_MODIFIERS) do
		local button = type(keys.standIns) == "table" and keys.standIns[modifier]
		if type(button) == "string" and (button == "none" or not OwnUse(button)) then
			db.standIns[modifier] = button
		end
	end
	if ns.IsActive() then
		ns.CVars:Apply()
	end
	Options:Sync()
end

ns.On("PLAYER_ENTERING_WORLD", function()
	if not Options.keysApplied then
		ns.RunOutOfCombat("account keys", ApplyAccountKeys)
	end
end)
-- A job given in the game's own Key Bindings screen is written down on the way out.
ns.On("PLAYER_LOGOUT", function() Options:RecordKeys() end)

-- The combinations the page lists: those, and before them the one that was just pressed here,
-- with or without a job yet. Worked out once for each time the page is brought up to date.
local comboCache

local function Combos()
	if comboCache then
		return comboCache
	end
	local list = BoundCombos()
	local caught = Options.caughtCombo
	if caught then
		for index, key in ipairs(list) do
			if key == caught then
				table.remove(list, index)
				break
			end
		end
		table.insert(list, 1, caught)
	end
	comboCache = list
	return list
end

-- The names of the buttons that are held for combinations right now: "LB or RB".
local function HeldNames()
	local names = {}
	for _, modifier in ipairs(HOLD_MODIFIERS) do
		local button = ns.CVars:GetCombinationButton(modifier)
		if button then
			names[#names + 1] = Layout.GetKeyName(button)
		end
	end
	return #names > 0 and table.concat(names, " or ") or nil
end

local function BuildCombos(panel)
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", 16, -14)
	title:SetText("Combinations")

	local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", 18, -40)
	note:SetPoint("RIGHT", -20, 0)
	note:SetJustifyH("LEFT")
	note:SetText("Buttons pressed together can be a button of their own, with a job of its own: LB + D-pad Up, or LB + RB + D-pad Right. One button is held and the other pressed. The game does this by letting a button stand in for the Ctrl, Alt or Shift key of a keyboard, so a combination is an ordinary key binding and shows in the game's Key Bindings screen, spelled CTRL-, ALT- or SHIFT- and the button. This page is the same for all your characters.")

	local left = 16
	local y = -90
	y = Heading(panel, "Buttons to hold", left, y)
	local tips = {
		Ctrl = "The button that counts as the Ctrl key while it is held. The game sets the left bumper for this itself.",
		Alt = "The button that counts as the Alt key while it is held. Held while you cast, Alt is also the game's self-cast key unless you changed that under Options > Combat.",
		Shift = "The button that counts as the Shift key while it is held. The game sets the left trigger for this itself, which FreeControl undoes while it is active: a trigger has to stay a trigger.",
	}
	for _, modifier in ipairs(HOLD_MODIFIERS) do
		y = Choice(panel, left, y, "Hold as " .. modifier, tips[modifier] .. " A button that is held this way has no job of its own, and the buttons FreeControl uses itself (D-pad, face buttons, triggers and the two click buttons) cannot be held. Your choice is in force while FreeControl is active, and the game's own setting is put back when it is not.",
			function() return HoldChoices(modifier) end,
			function() return ns.CVars:GetCombinationButton(modifier) or "none" end,
			function(value) SetHold(modifier, value) end)
	end

	y = Heading(panel, "Combinations", left, y - 8)
	local catcher = CreateCatcher(panel, function(key)
		local held = HeldNames()
		if not Layout.IsChord(key) then
			ns.Print(("That was %s on its own. %s"):format(Layout.GetKeyName(key),
				held and ("Hold %s and press another button with it."):format(held) or "No button is set to be held yet: pick one above."))
			return
		elseif not Layout.IsPadChord(key) then
			ns.Print("That one ends in a key of the keyboard. This page is for the controller's buttons: the game's Key Bindings screen takes any combination of keys.")
			return
		end
		Options.caughtCombo = key
		Options:Sync()
	end)
	Options.comboCatcher = catcher
	local press
	y, press = Action(panel, left, y, "Press one...", "Click this, then hold the first button and press the second. The combination appears below with its job. A combination can end in any button, FreeControl's D-pad and face buttons included.", function()
		if InCombatLockdown() then
			ns.Print("Key bindings cannot be changed in combat.")
			return
		end
		catcher:Show()
	end, "Find a combination")

	local empty = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	empty:SetPoint("LEFT", press, "RIGHT", 10, 0)
	empty.Sync = function(self)
		self:SetText(#Combos() == 0 and "No combination has a job yet." or "")
	end
	controls[#controls + 1] = empty
	for index = 1, COMBO_ROWS do
		y = KeyRow(panel, left, y, function() return Combos()[index] end)
	end
	local more = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	more:SetPoint("TOPLEFT", left + 4, y - 6)
	more.Sync = function(self)
		local hidden = #Combos() - COMBO_ROWS
		self:SetText(hidden > 0 and ("%d more are not shown here. The game's Key Bindings screen has them all."):format(hidden) or "")
	end
	controls[#controls + 1] = more
	Options.comboNotes = { empty = empty, more = more }
end

---------------------------------------------------------------------------
-- The Mouse mode page
---------------------------------------------------------------------------
-- What mouse mode is at the moment, in a few sentences: the first thing on its page.
local function MouseNote()
	if not ns.Mouse:IsAvailable() then
		return "This client has no controller mouse pointer, so there is no mouse mode here."
	elseif not ns.Mouse:IsEnabled() then
		local game = "The game still brings its own pointer out when a window needs one, and the two buttons below are what click then."
		if not ns.db.gamePointer then
			game = "The game is told not to bring its own pointer out either, so the controller leaves the mouse pointer to your mouse."
		end
		return "Mouse mode is switched off. No button of FreeControl's brings the mouse pointer out, and the button that did is an ordinary action slot that holds whatever you drop on it. " .. game
	end
	local button = ns.Mouse:GetBarButtonName()
	local how = button and (button .. " brings the mouse pointer out and puts it away; jumping puts it away too. FreeControl binds it: there is nothing to set up.")
		or "No button brings the mouse pointer out. Click a no-trigger button on the bar and choose \"Mouse pointer on / off\", or give a bumper or a paddle that job under Other buttons."
	if not ns.db.gamePointer then
		how = how .. " The game is told not to bring the pointer out by itself."
	end
	return how .. " While the pointer is out, the right stick moves it and the two buttons below click."
end

local function BuildMouse(panel)
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", 16, -14)
	title:SetText("Mouse mode")

	local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", 18, -40)
	note:SetPoint("RIGHT", -20, 0)
	note:SetJustifyH("LEFT")
	note.Sync = function(self)
		self:SetText(MouseNote())
	end
	controls[#controls + 1] = note
	Options.mouseNote = note

	local left = 16
	local y = -90
	y = Heading(panel, "The pointer", left, y)
	y = Check(panel, left, y, "Mouse mode", MouseModeTip, "mouseMode", ns.SetMouseMode)
	y = Check(panel, left, y, "The game may bring the pointer out", "Whatever FreeControl does, the game brings its stick pointer out by itself: when a window opens, and to aim a spell that is cast on the ground. Untick this to stop that while FreeControl is active (console variables GamePadCursorAutoEnable and GamePadCursorForTargeting are set to 0, and your own values put back afterwards). With Mouse mode unticked as well, nothing on the controller takes the mouse pointer: for playing with a real mouse beside the controller.", "gamePointer")

	y = Heading(panel, "While the pointer is out", left, y - 8)
	y = Check(panel, left, y, "The triggers are the mouse wheel", "While the mouse pointer is out, the left trigger turns the mouse wheel up and the right one down: to zoom the map, go through a list, or zoom the camera. Hold one to keep turning. Put the pointer away and they are triggers again. Unticked, they stay triggers while the pointer is out.", "mouseScroll")
	y = Choice(panel, left, y, "Left click", "The left mouse button while the mouse pointer is out. Pick a button you can hold while your right thumb steers, such as a stick click or a bumper, so you can drag spells and items. The rest of the time the button does whatever you bound it to.", ClickChoices,
		function() return ns.db.clickLeft end, function(value) SetClick(1, value) end)
	y = Choice(panel, left, y, "Right click", "The right mouse button while the mouse pointer is out. The rest of the time the button does whatever you bound it to.", ClickChoices,
		function() return ns.db.clickRight end, function(value) SetClick(2, value) end)
	Stepper(panel, left, y, "Pointer speed", "How fast the right stick moves the mouse pointer. 100% is the game's own speed, or whatever you had set it to.", "cursorSpeed", 0.5, 3, 0.25)
end

---------------------------------------------------------------------------
-- The Chat page
---------------------------------------------------------------------------
-- The chat keyboard and the quick phrases (the Chat folder). Their settings are the account's,
-- kept apart from the bar's (FreeControlChatDB): ns.Chat.db.settings.
local KEYBOARD_LAYOUTS = {
	{ "qwerty", "QWERTY" }, { "azerty", "AZERTY" }, { "qwertz", "QWERTZ" },
	{ "qwerty_es", "QWERTY (Spanish)" }, { "qwerty_it", "QWERTY (Italian)" },
}

local function KeyboardLanguages()
	local choices = {}
	for index, language in ipairs(ns.Chat.LANGUAGES) do
		choices[index] = { language.key, language.name }
	end
	return choices
end

-- Brings the keyboard on screen, if it is, in line with a setting that changes how it is drawn.
local function RedrawKeyboard()
	local chat = ns.Chat
	if chat.frame then
		chat:Layout()
		chat:UpdateLock()
		chat:UpdateMethod()
	end
end

-- A tick box for one of the chat settings: get() answers it, set(value) stores it.
local function ChatCheck(panel, x, y, label, tooltip, get, set)
	local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	check:SetSize(26, 26)
	check:SetPoint("TOPLEFT", x, y)
	check.Text:SetText(label)
	check.Text:SetFontObject("GameFontHighlight")
	AddTooltip(check, label, tooltip)
	check:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
		RedrawKeyboard()
		Options:Sync()
	end)
	check.Sync = function(self)
		self:SetChecked(get())
	end
	controls[#controls + 1] = check
	return y - ROW
end

-- The same for a setting that is just a name in the chat settings.
local function ChatSetting(panel, x, y, label, tooltip, key)
	return ChatCheck(panel, x, y, label, tooltip,
		function() return ns.Chat.db.settings[key] end,
		function(value) ns.Chat.db.settings[key] = value end)
end

-- The keyboard itself, on or off. Off, an open one is closed with the chat it is on.
local function SetKeyboard(on)
	local chat = ns.Chat
	chat.db.settings.modules.keyboard = on
	if not on and chat:IsOpen() then
		chat:CloseChat()
	end
end

local function BuildChat(panel)
	local chat = ns.Chat
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", 16, -14)
	title:SetText("Chat")

	local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", 18, -40)
	note:SetPoint("RIGHT", -20, 0)
	note:SetJustifyH("LEFT")
	note:SetText("A keyboard for the chat, and a window of ready-made phrases sent in one press. Give a button the job \"Chat keyboard\" or \"Quick phrases\": click a button on the bar, or use Other buttons. Neither works in a fight, and while one is open the controller is its own: the bar lets go of its buttons until it closes. On the keyboard the D-pad or the left stick moves the highlight, A types the key, X deletes, Y sends, B empties the message and then closes the chat, and LB and RB change the channel.")

	local left, right = 16, 340
	local y = -100
	y = Heading(panel, "The keyboard", left, y)
	y = ChatCheck(panel, left, y, "Chat keyboard", "The keyboard for the chat. Unticked, the chat opens without it and the Chat keyboard job does nothing; the quick phrases stay.",
		function() return chat.db.settings.modules.keyboard end, SetKeyboard)
	y = ChatSetting(panel, left, y, "Open with the chat", "The keyboard comes up whenever the chat is opened, by a key, a click on a name or a link. Unticked, only the Chat keyboard job brings it up.", "autoOpen")
	y = Choice(panel, left, y, "Key layout", "How the keyboard's keys are laid out.", KEYBOARD_LAYOUTS,
		function() return chat.db.settings.kbLayout end,
		function(value) chat.db.settings.kbLayout = value; RedrawKeyboard(); Options:Sync() end)
	y = Choice(panel, left, y, "Words", "The language of the words suggested above the keyboard, and of the accented letters on its 123 layer.", KeyboardLanguages,
		function() return chat:GetLanguage().key end,
		function(value) chat:SetLanguage(value); Options:Sync() end)
	y = ChatSetting(panel, left, y, "Learn the words I use", "Every message you send, from the keyboard or not, teaches the suggestions your words and the order you use them in. They are kept on this computer, for all your characters. /fc keyboard forget empties them.", "learn")
	y = ChatSetting(panel, left, y, "Come back to the last channel", "The keyboard opens on the channel you wrote on last (party, guild, a whisper...), on this character, the next time you play too. Unticked, it opens on the chat's own channel.", "stickyChannel")
	y = ChatSetting(panel, left, y, "Buttons for the mouse", "A row of buttons under the keys for a mouse or a touch screen: Shift, 123, Space, Delete, Send and close.", "showActions")
	ChatCheck(panel, left, y, "Keep the keyboard where it is", "Unticked, the keyboard shows a grip to drag it by. /fc keyboard reset puts it back beside the chat window.",
		function() return chat.db.settings.locked end,
		function(value) chat.db.settings.locked = value end)

	local ry = Heading(panel, "Quick phrases", right, -100)
	ry = ChatSetting(panel, right, ry, "Bubble in the keyboard", "A bubble at the end of the keyboard's suggestions opens the quick phrases: D-pad right up to it, then the right stick's click. The keyboard comes back after, with what it held.", "phrasesChip")
	ry = Action(panel, right, ry, "Open", "Opens the quick phrases window. In it: the D-pad picks, LB and RB change the channel, A sends, X rewrites a phrase or a row's name, Y opens the keyboard with the phrase, B closes.", function()
		chat.Phrases:Toggle()
	end, "The window")
	ry = Action(panel, right, ry, "Default phrases", "Puts the phrases and their rows back as they came. Yours are lost.", function()
		chat.Phrases:Reset()
		ns.Print("The quick phrases are the default ones again.")
	end, "Start over")

	ry = Heading(panel, "Buttons", right, ry - 8)
	Action(panel, right, ry, "Other buttons...", "Opens the page where a bumper, a stick click, Start, Back or a paddle is given a job: Chat keyboard and Quick phrases are in the list.", function()
		Options:OpenButtons()
	end, "Give a button the job")
end

---------------------------------------------------------------------------
-- Registering the pages
---------------------------------------------------------------------------
-- A page is built the first time it is opened; most sessions never open one.
local function CreatePanel(build)
	local panel = CreateFrame("Frame")
	panel:Hide()
	panel:SetScript("OnShow", function(self)
		if not self.built then
			self.built = true
			build(self)
		end
		Options:Sync()
	end)
	return panel
end

function Options:Create()
	self.panel = CreatePanel(Build)
	self.category = Settings.RegisterCanvasLayoutCategory(self.panel, "FreeControl")
	Settings.RegisterAddOnCategory(self.category)
	self.mousePanel = CreatePanel(BuildMouse)
	self.mouseCategory = Settings.RegisterCanvasLayoutSubcategory(self.category, self.mousePanel, "Mouse mode")
	self.buttonsPanel = CreatePanel(BuildButtons)
	self.buttonsCategory = Settings.RegisterCanvasLayoutSubcategory(self.category, self.buttonsPanel, "Other buttons")
	self.combosPanel = CreatePanel(BuildCombos)
	self.combosCategory = Settings.RegisterCanvasLayoutSubcategory(self.category, self.combosPanel, "Combinations")
	self.chatPanel = CreatePanel(BuildChat)
	self.chatCategory = Settings.RegisterCanvasLayoutSubcategory(self.category, self.chatPanel, "Chat")
end

-- Brings the pages in line with the saved settings and the player's key bindings. A page that
-- is not on screen is left for when it is opened: this is called on every setting change, and
-- when the page is turned in a fight.
function Options:Sync()
	comboCache = nil -- bindings or the buttons that are held may have changed
	local showing = false
	for _, panel in ipairs({ self.panel, self.mousePanel, self.buttonsPanel, self.combosPanel, self.chatPanel }) do
		showing = showing or panel:IsVisible()
	end
	if not showing then
		return
	end
	for _, control in ipairs(controls) do
		control:Sync()
	end
end

function Options:Open()
	Settings.OpenToCategory(self.category:GetID())
end

function Options:OpenButtons()
	Settings.OpenToCategory(self.buttonsCategory:GetID())
end

function Options:OpenMouse()
	Settings.OpenToCategory(self.mouseCategory:GetID())
end

function Options:OpenCombos()
	Settings.OpenToCategory(self.combosCategory:GetID())
end

function Options:OpenChat()
	Settings.OpenToCategory(self.chatCategory:GetID())
end

-- Bindings changed somewhere else, in the Key Bindings screen for one: the rows follow.
ns.On("UPDATE_BINDINGS", function()
	Options:Sync()
end)

---------------------------------------------------------------------------
-- /fc status
---------------------------------------------------------------------------
local function YesNo(value)
	return value and "yes" or "no"
end

-- The stances or forms the game lists for this character, and which one it is in. A form can be
-- on this list without having a bar of its own (a travel form): the bar only changes for those
-- that do.
local function DescribeForms()
	if not (GetNumShapeshiftForms and GetShapeshiftFormInfo) then
		return nil
	end
	local names = {}
	for index = 1, GetNumShapeshiftForms() do
		local _, active, _, spell = GetShapeshiftFormInfo(index)
		local name = spell and not ns.IsSealed(spell) and C_Spell.GetSpellName(spell) or ("number " .. index)
		names[index] = name .. ((not ns.IsSealed(active) and active) and " (in it now)" or "")
	end
	return "Stances or forms the game lists: " .. (#names > 0 and table.concat(names, ", ") or "none") .. "."
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
	local profile = ns.GetBarProfile()
	ns.Print(("Slots: %s (asked for %s). Controller-bar slots start at %s, usable: %s, stance slots usable: %s"):format(
		source, profile.slotSource, tostring(first), YesNo(Layout.HasGamepadSlots()), YesNo(Layout.HasStanceSlots())))
	local _, class = UnitClass("player")
	ns.Print(("Page %d of %d (pages: %s, page selector: %s). Class: %s. Changes with your stance or form (setting: %s): %s"):format(Layout.GetPage(), Layout.GetStoredPages(),
		profile.pages and "on" or "off", profile.showPager and "shown" or "hidden", tostring(class), profile.stanceSet, Layout.DescribeStance()))
	if ns.activeSpecGroup then
		ns.Print("Bar settings profile: talent group " .. ns.activeSpecGroup)
	end
	ns.Print(("Page buttons: next page is on %s, previous page on %s."):format(
		GetBindingKey(ns.Bindings.PAGE_COMMANDS.next) or "no button", GetBindingKey(ns.Bindings.PAGE_COMMANDS.prev) or "no button"))
	local held = {}
	for index, modifier in ipairs(HOLD_MODIFIERS) do
		held[index] = ("%s %s"):format(modifier, ns.CVars:GetCombinationButton(modifier) or "none")
	end
	local combos = {}
	for index, key in ipairs(BoundCombos()) do
		combos[index] = ("%s = %s"):format(key, GetBindingAction(key))
	end
	ns.Print(("Held for combinations: %s. Combinations with a job: %s"):format(table.concat(held, ", "), #combos > 0 and table.concat(combos, ", ") or "none"))
	local forms = DescribeForms()
	if forms then
		ns.Print(forms)
	end
	-- Which stance bar is up is asked of the game twice: here, and by the secure code that moves
	-- the buttons (a macro condition). Which slots a stance uses is worked out, not asked for;
	-- the client can confirm both kinds for the stance you are in right now.
	local bonus = C_ActionBar.GetBonusBarOffset()
	local differ = " |cffff4040- these differ, please report it|r"
	if bonus > 0 then
		if #Layout.GetStanceGroups() == 0 then
			ns.Print(("Stance bar %d is up. Nothing on the bar is set to change with it."):format(bonus))
		elseif ns.IsBuilt() then
			local following = tonumber(ns.Bindings.header:GetAttribute("state-fc-stance")) or 0
			ns.Print(("Stance bar %d is up. The bar is following stance bar %d%s"):format(bonus, following, following ~= bonus and differ or ""))
		end
		if bonus > Layout.NUM_STANCES then
			ns.Print(("|cffff4040FreeControl has slots for stance bars 1 to %d only, please report this one.|r"):format(Layout.NUM_STANCES))
		else
			local reported = Layout.HasStanceSlots() and C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance
				and C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance()
			if reported then
				local expected = Layout.GetStanceFirst("pad", bonus)
				ns.Print(("Stance %d: its controller slots start at %d (the game says %d)%s"):format(bonus, expected, reported,
					expected == reported and "" or differ))
			end
			local page = C_ActionBar.GetBonusBarIndex and C_ActionBar.GetBonusBarIndex()
			if page then
				local expected, reportedBar = Layout.GetStanceFirst("bar", bonus), (page - 1) * 12 + 1
				ns.Print(("Stance %d: its regular action bar slots start at %d (the game says %d)%s"):format(bonus, expected, reportedBar,
					expected == reportedBar and "" or differ))
			end
		end
	else
		ns.Print("No stance or form bar is up right now.")
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
		ns.Print("Active layer: " .. Layout.GetSetName(ns.Bindings:GetActiveSet()))
		local header = ns.Bindings.header
		local form = tonumber(header:GetAttribute("state-fc-main-form")) or 0
		local formStart = header:GetAttribute("fc-active-main-form")
		if formStart then
			ns.Print(("Main layer form %d uses slots %d–%d."):format(form, formStart, formStart + 7))
		elseif GetShapeshiftForm and profile.stanceSet ~= "none" then
			local current = GetShapeshiftForm()
			if not ns.IsSealed(current) and type(current) == "number" and current > 0 then
				ns.Print("No dedicated eight-slot Main layout is available for this form.")
			end
		end
	end
	ns.Print(("Cooldown numbers: %s. The game seals combat values from addons: %s"):format(
		YesNo(db.cooldownNumbers), ns.DescribeSealing()))
	ns.Print(("Proc glow: %s (the game's proc signal is there: %s). Glowing right now: %s"):format(YesNo(db.procGlow),
		YesNo(C_SpellActivationOverlay ~= nil), ns.IsBuilt() and ns.Buttons:DescribeGlows() or "nothing"))
	ns.Print(ns.Ranks:Describe())

	if ns.Mouse:IsAvailable() then
		local name, key = ns.Mouse:GetBarButtonName()
		local bound = key and GetBindingAction(key, true) or ""
		ns.Print(("Mouse pointer: %s. Mouse button: %s (%s), bound right now to: %s. Pointer speed: %d%%"):format(ns.Mouse:IsOut() and "out" or "away",
			name or "none", key or "-", bound ~= "" and bound or "nothing", db.cursorSpeed * 100 + 0.5))
		for side, setting in ipairs({ "clickLeft", "clickRight" }) do
			local click = GetCVar(side == 1 and "GamePadCursorLeftClick" or "GamePadCursorRightClick") or ""
			local clickBound = click ~= "" and GetBindingAction(click, true) or ""
			ns.Print(("  %s click: %s (setting: %s), bound right now to: %s"):format(side == 1 and "Left" or "Right",
				click ~= "" and click or "none", db[setting], clickBound ~= "" and clickBound or "nothing"))
		end
		for _, line in ipairs(ns.Mouse:Describe()) do
			ns.Print("  " .. line)
		end
	else
		ns.Print("Mouse pointer: this client has no controller mouse pointer.")
	end

	ns.Print("Keys: " .. table.concat(db.keys, " ") .. " | triggers: " .. table.concat(db.modKeys, " "))
	ns.Print("Return to main layer: " .. (GetBindingKey(ns.Bindings.RELEASE_COMMAND) or "unbound"))
	for _, problem in ipairs(ns.Bindings:FindProblems()) do
		ns.Print("|cffffd100Note:|r " .. problem)
	end
	for _, line in ipairs(ns.CVars:Describe()) do
		ns.Print("  " .. line)
	end

	local problems = ns.GetProblems()
	if #problems == 0 then
		ns.Print("Errors since login: none.")
	end
	for _, problem in ipairs(problems) do
		ns.Print(("|cffff4040Error|r since login, %d time(s): %s"):format(problem.count, problem.text))
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
	"/fc page <1-3> - which controller-bar page to show (the page selector under the LT + RT set turns it too)",
	"/fc buttons - give the bumpers, stick clicks, Start, Back and paddles their jobs",
	"/fc combos - give buttons pressed together a job",
	"/fc hold ctrl | alt | shift <BUTTON | none> - the button that is held for combinations, as that key",
	"/fc specs on | off - whether each talent group has its own layout: its own buttons and jobs, put back when you switch",
	"/fc slots gamepad | bars - where the slots are stored",
	"/fc numbers on | off - count down the seconds on slots that are on cooldown",
	"/fc glow on | off - glow a button whose spell has procced or come free for a moment",
	"/fc ranks - move every spell on the bar up to its newest rank now (on | off: do it by itself whenever you learn one)",
	"/fc key <1-8 | lt | rt> <KEY> - use a different key for a slot or trigger (1-4 D-pad left/up/right/down, 5-8 face left/top/right/bottom)",
	"/fc stance auto | none | lt | rt | both | ltrt | all - what changes with your stance or form (ltrt = both trigger sets, all = those and the D-pad)",
	"/fc stance custom [main] [lt] [rt] [both] - your own pick of the layouts that change, on the stance page only (two trigger sets at most)",
	"/fc pages on | off - whether the page can be turned (off: the bar stays on the page of /fc page)",
	"/fc pager on | off - show or hide the page selector under the LT + RT set",
	"/fc mouse - bring the controller's mouse pointer out or put it away (on | off: mouse mode itself; off makes its button an action slot)",
	"/fc gamepointer on | off - whether the game may bring the mouse pointer out by itself (off: for playing with a real mouse)",
	"/fc front on | off - have the game pick only enemies in front of you, as Gamepad UI mode does",
	"/fc click left | right <BUTTON> - the button that clicks while the mouse pointer is out (game = leave it to the game)",
	"/fc pointer <50-300> - how fast the stick moves the mouse pointer, in percent",
	"/fc scroll on | off - while the mouse pointer is out, the triggers are the mouse wheel: left up, right down",
	"/fc chat - the settings of the chat keyboard and the quick phrases",
	"/fc keyboard - open the chat with the keyboard, or close it (on | off: the keyboard itself)",
	"/fc keyboard unlock | lock | reset | scale <0.4-2> - move the keyboard, put it back, or change its size (forget: empty the words it learned)",
	"/fc phrases - open the quick phrases window, or close it",
	"/fc status - what FreeControl sees, for bug reports",
	"/fc trace - record what the game reports about the next abilities you use (type it again to see the result)",
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

local HOLD_NAMES = { ctrl = "Ctrl", alt = "Alt", shift = "Shift" }

-- /fc keyboard, and what can follow it. Alone it opens the chat with the keyboard, or closes it.
local function KeyboardCommand(what, value)
	local chat = ns.Chat
	local settings = chat.db.settings
	if what == nil or what == "" then
		-- The chat edit box is still sending this command: open once it has closed.
		C_Timer.After(0, function() ns.Try(chat.Toggle, chat) end)
	elseif what == "on" or what == "off" then
		SetKeyboard(what == "on")
		ns.Print(("The chat keyboard is switched %s."):format(what))
	elseif what == "lock" or what == "unlock" then
		settings.locked = what == "lock"
		chat:UpdateLock()
		if what == "unlock" then
			ns.Print("The chat keyboard can be dragged by its grip. /fc keyboard lock keeps it where it is.")
			-- Shown to be placed, once the chat that sent this has closed.
			C_Timer.After(0, function() ns.Try(chat.OpenStandalone, chat) end)
		else
			ns.Print("The chat keyboard stays where it is.")
		end
	elseif what == "reset" then
		chat.db.pos = nil
		settings.scale = 1
		if chat.frame then chat:RestorePosition() end
		ns.Print("The chat keyboard is back beside the chat window, at its own size.")
	elseif what == "scale" and tonumber(value) then
		settings.scale = math.max(0.4, math.min(2, tonumber(value)))
		if chat.frame then chat:RestorePosition() end
		ns.Print(("The chat keyboard is at %d%% of its size."):format(settings.scale * 100 + 0.5))
	elseif what == "forget" then
		chat.Predict:Forget()
		ns.Print("The words the chat keyboard learned from you are forgotten.")
	else
		ns.Print("/fc keyboard [on | off | unlock | lock | reset | scale <0.4-2> | forget]")
		return
	end
	Options:Sync()
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
	elseif command == "buttons" then
		Options:OpenButtons()
	elseif command == "combos" then
		Options:OpenCombos()
	elseif command == "specs" and ns.IsOneOf(first, "on", "off") then
		ns.db.specLayouts = first == "on"
		ns.Print(first == "on" and "Each talent group has its own layout: what is on the bar now is the active one's, and the other starts as a copy of it the first time you switch."
			or "The talent groups share one layout again: what is on the bar stays when you switch.")
		if first == "on" then ns.Specs:Record() end
	elseif command == "hold" and HOLD_NAMES[first] and second and second ~= "" then
		SetHold(HOLD_NAMES[first], second == "none" and "none" or second:upper())
	elseif command == "gamepointer" and ns.IsOneOf(first, "on", "off") then
		Set("gamePointer", first == "on")
	elseif command == "front" and ns.IsOneOf(first, "on", "off") then
		Set("frontTargeting", first == "on")
	elseif command == "slots" and ns.IsOneOf(first, "gamepad", "bars") then
		Set("slotSource", first)
	elseif command == "numbers" and ns.IsOneOf(first, "on", "off") then
		Set("cooldownNumbers", first == "on")
	elseif command == "glow" and ns.IsOneOf(first, "on", "off") then
		Set("procGlow", first == "on")
	elseif command == "ranks" and ns.IsOneOf(first, "on", "off") then
		Set("keepRanks", first == "on")
		ns.Ranks:CheckSoon()
	elseif command == "ranks" and first == nil then
		ns.Ranks:CheckAll()
	elseif command == "key" and SetKey(first, second) then
		ns.Print("Keys: " .. table.concat(ns.db.keys, " ") .. " | triggers: " .. table.concat(ns.db.modKeys, " "))
	elseif command == "stance" and first == "custom" then
		local flags = {}
		for word in strtrim(message):lower():gmatch("%S+") do
			for _, entry in ipairs(Layout.STANCE_LAYOUTS) do
				if word == entry[2] then flags[entry[1]] = true end
			end
		end
		SetStanceLayouts(flags)
	elseif command == "stance" and ns.IsOneOf(first, unpack(Layout.STANCE_CHOICES)) then
		-- In combat the change waits for the fight to end, and RequestRefresh has said so.
		Set("stanceSet", first)
		if not InCombatLockdown() then
			ns.Print(("Changes with your stance or form: %s."):format(Layout.DescribeStance()))
		end
	elseif command == "pages" and ns.IsOneOf(first, "on", "off") then
		Set("pages", first == "on")
	elseif command == "pager" and ns.IsOneOf(first, "on", "off") then
		Set("showPager", first == "on")
	elseif command == "mouse" and ns.IsOneOf(first, "on", "off") then
		ns.SetMouseMode(first == "on")
	elseif command == "mouse" then
		ns.Mouse:Toggle()
	elseif command == "pointer" and tonumber(first) then
		Set("cursorSpeed", math.max(0.5, math.min(3, tonumber(first) / 100)))
	elseif command == "click" and ns.IsOneOf(first, "left", "right") and second and second ~= "" then
		-- In combat the change waits for the fight to end, and RequestRefresh has said so.
		if SetClick(first == "left" and 1 or 2, second == "game" and "game" or second:upper()) and not InCombatLockdown() then
			ns.Print(("Mouse clicks: %s."):format(ns.Mouse:DescribeClicks()))
		end
	elseif command == "scroll" and ns.IsOneOf(first, "on", "off") then
		Set("mouseScroll", first == "on")
	elseif command == "chat" then
		Options:OpenChat()
	elseif command == "keyboard" then
		KeyboardCommand(first, second)
	elseif command == "phrases" then
		-- The chat edit box is still sending this command: open once it is done.
		C_Timer.After(0.1, function() ns.Try(ns.Chat.Phrases.Toggle, ns.Chat.Phrases) end)
	elseif command == "status" then
		PrintStatus()
	elseif command == "trace" then
		ns.Trace:Toggle()
	else
		for _, line in ipairs(HELP) do
			ns.Print(line)
		end
	end
end
