local _, ns = ...
local Layout = ns.Layout

-- The settings pages (Options > AddOns > FreeControl, and Other buttons under it), the /fc
-- command, and the menu for choosing what a no-trigger button does.
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
-- The values are Layout.STANCE_CHOICES.
local STANCE_SETS = {
	{ "auto", "Automatic" },
	{ "none", "Nothing" },
	{ "lt", "Left trigger set" },
	{ "rt", "Right trigger set" },
	{ "both", "Both triggers set" },
	{ "ltrt", "Left and right sets" },
	{ "all", "Left, right and D-pad" },
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

local function RoleChoices()
	local choices = {
		{ "action", "Action slot" },
		{ "pass", "My own key binding" },
	}
	for _, command in ipairs(Layout.COMMANDS) do
		choices[#choices + 1] = { "cmd:" .. command[1], command[2] }
	end
	for _, job in ipairs(FormJobs()) do
		choices[#choices + 1] = { "cmd:" .. job[1], job[2] }
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
	ns.db[key] = value
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

function Options:OpenRoleMenu(owner, index)
	if InCombatLockdown() then
		ns.Print("Buttons cannot be changed in combat.")
		return
	end
	Choose(owner, RoleChoices(), function() return ns.db.roles[index] end, function(value)
		SetIndexed("roles", index, value)
	end)
end

-- What the Stance sets choice comes to on this character, said under its explanation.
local function StanceTooltip()
	local text = "What changes to different slots in each stance or form. Automatic is the left and right trigger sets and the D-pad for a Druid, and for every other class the one set picked in Options > Gamepad > Stance bar. A second set and the D-pad use the slots of the game's own action bar for that stance, so they are shared with it. They change on one page only, as the game's own bars do; the other pages, the both-triggers set and the face buttons are the same in every stance."
	if Layout.GetSlotSource() ~= "gamepad" then
		text = text .. " With the regular action bars as the slots, Automatic changes nothing: pick a set yourself, and the D-pad can join it."
	end
	return ("%s\n\nOn this character: %s."):format(text, Layout.DescribeStance())
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
	note:SetText("A controller cross hotbar for the normal interface. Hold a trigger to switch sets; drop spells, items and macros onto any slot. The bumpers, stick clicks, Start, Back and paddles stay ordinary buttons: give them jobs under Other buttons.")

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
	y = Choice(panel, left, y, "Page", "Which of the three controller-bar pages the bar shows. Each page has its own buttons. The two arrows in the middle of the bar turn the page as well, in a fight too, and so does any button you give that job under Other buttons.", PAGES,
		function() return ns.db.page end, function(value) Set("page", value) end)
	y = Choice(panel, left, y, "Stance sets", StanceTooltip, STANCE_SETS,
		function() return ns.db.stanceSet end, function(value) Set("stanceSet", value) end)

	y = Heading(panel, "Mouse mode", left, y - 8)
	local mouseNote = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	mouseNote:SetPoint("TOPLEFT", left + 4, y - 2)
	mouseNote:SetWidth(296)
	mouseNote:SetJustifyH("LEFT")
	mouseNote.Sync = function(self)
		local button = ns.Mouse:GetBarButtonName()
		local how = button and (button .. " brings the mouse pointer out and puts it away. FreeControl binds it; there is nothing to set up.")
			or "No button brings the mouse pointer out. Give one \"Mouse pointer on / off\" in the list on the right."
		self:SetText(how .. " While it is out, the right stick moves it and these two buttons click.")
	end
	controls[#controls + 1] = mouseNote
	y = y - 52
	y = Choice(panel, left, y, "Left click", "The left mouse button while the mouse pointer is out. Pick a button you can hold while your right thumb steers, such as a stick click or a bumper, so you can drag spells and items. The rest of the time the button does whatever you bound it to.", ClickChoices,
		function() return ns.db.clickLeft end, function(value) SetClick(1, value) end)
	y = Choice(panel, left, y, "Right click", "The right mouse button while the mouse pointer is out. The rest of the time the button does whatever you bound it to.", ClickChoices,
		function() return ns.db.clickRight end, function(value) SetClick(2, value) end)
	y = Stepper(panel, left, y, "Pointer speed", "How fast the right stick moves the mouse pointer. 100% is the game's own speed, or whatever you had set it to.", "cursorSpeed", 0.5, 3, 0.25)

	y = -78
	y = Heading(panel, "Controller", right, y)
	y = Check(panel, right, y, "Turn on controller input", "Sets GamePadEnable while FreeControl is active so the game reads your controller. This is not Gamepad UI mode. Untick it if a tool such as Steam Input already turns your controller into key presses.", "manageGamepad")
	y = Check(panel, right, y, "Interact finds things by itself", "The Interact command picks the nearest corpse to loot, person to talk to or object to use, as in Gamepad UI mode (Options > Controls > Enable Interact Key).", "softInteract")
	y = Check(panel, right, y, "Gamepad UI interact reach", "Uses the wider arc and 20 yard range that Gamepad UI mode uses for Interact.", "interactReach")
	y = Choice(panel, right, y, "Left trigger", "The button that selects the left set.", TRIGGER_KEYS,
		function() return ns.db.modKeys[1] end, function(value) SetIndexed("modKeys", 1, value) end)
	y = Choice(panel, right, y, "Right trigger", "The button that selects the right set.", TRIGGER_KEYS,
		function() return ns.db.modKeys[2] end, function(value) SetIndexed("modKeys", 2, value) end)
	y = Action(panel, right, y, "Other buttons...", "The bumpers, stick clicks, Start, Back and paddles are ordinary buttons: FreeControl does not use them, and each does whatever you bind it to. This opens the page where you give them jobs, such as turning the bar's page.", function()
		Options:OpenButtons()
	end, "Bumpers, paddles")

	y = Heading(panel, "With no trigger held", right, y - 8)
	for index = 1, 8 do
		y = Choice(panel, right, y, function() return Layout.GetButtonName(Layout.SET_NONE, index) end,
			"What this button does while no trigger is held. Action slot makes it a slot you can drop things into; My own key binding leaves it to the Key Bindings screen.", RoleChoices,
			function() return ns.db.roles[index] end, function(value) SetIndexed("roles", index, value) end)
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

-- What FreeControl itself uses a button for, in a few words, or nil for a button that is the
-- player's own.
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
	}
	for _, command in ipairs(Layout.COMMANDS) do
		if command[1] == Layout.CURSOR_COMMAND then
			if ns.Mouse:IsAvailable() then
				choices[#choices + 1] = { ns.Bindings.MOUSE_COMMAND, command[2] }
			end
		else
			choices[#choices + 1] = { command[1], command[2] }
		end
	end
	for _, job in ipairs(FormJobs()) do
		choices[#choices + 1] = job
	end
	for _, job in ipairs(Layout.MORE_JOBS) do
		choices[#choices + 1] = job
	end
	-- A binding made somewhere else is listed too, so the menu always shows what the button does.
	local current = GetBindingAction(key)
	local listed = false
	for _, choice in ipairs(choices) do
		listed = listed or choice[1] == current
	end
	if not listed then
		local form = Layout.GetCommandForm(current)
		table.insert(choices, 2, { current, form and (Layout.GetCommandInfo(current)) or GetBindingName(current) })
	end
	choices[#choices + 1] = { "keybindings", "Something else...", true }
	return choices
end

function Options:OpenKeyBindings()
	Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)
end

-- Gives a button a job, as one of the player's own key bindings. Returns true when it was done.
local function Bind(key, command)
	if command == "keybindings" then
		Options:OpenKeyBindings()
		return false
	elseif InCombatLockdown() then
		ns.Print("Key bindings cannot be changed in combat.")
		return false
	end
	local name = Layout.GetKeyName(key)
	local modifier = ns.CVars:GetStandIn(key)
	if command == "" then
		SetBinding(key, nil)
	elseif not SetBinding(key, command) then
		ns.Print(("The game would not bind %s to that."):format(name))
		return false
	end
	SaveBindings(GetCurrentBindingSet())
	-- A button with a job is a plain button; one without is whatever the game makes of it.
	ns.db.plainKeys[key] = command ~= "" or nil
	if command ~= "" then
		ns.Print(("%s now does this: %s.%s"):format(name, LabelFor(JobChoices(key), command),
			modifier and (" It no longer stands in for the %s key while FreeControl is active."):format(modifier) or ""))
	elseif modifier then
		ns.Print(("%s has no job of its own now, and stands in for the %s key again, as the game has it set."):format(name, modifier))
	else
		ns.Print(("%s now does nothing."):format(name))
	end
	if ns.IsActive() then
		ns.CVars:Apply() -- the stand-in follows the job
	end
	Options:Sync()
	return true
end
Options.Bind = Bind

-- A row for one button: its name, and a button showing its job that opens the menu of jobs.
-- getKey() names the button; a row without one (nothing caught yet) hides itself.
local function KeyRow(panel, x, y, getKey)
	local function Job()
		return GetBindingAction(getKey())
	end
	local function Tooltip()
		local key = getKey()
		local text = "What this button does. Pick a job from the list, or Something else to open the game's Key Bindings screen, where it can be given any command, spell or macro."
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
		return key and Layout.GetKeyName(key) or ""
	end
	local nextY, button, label = Choice(panel, x, y, Name, Tooltip, function() return JobChoices(getKey()) end, Job,
		function(command) Bind(getKey(), command) end, 230)
	local showJob = button.Sync
	button:SetScript("OnClick", function(self)
		local own = OwnUse(getKey())
		if own then
			ns.Print(("%s is %s, so a key binding on it would never be reached. The main page and /fc key change which buttons FreeControl uses."):format(Layout.GetKeyName(getKey()), own))
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
	text:SetText("Press the button or key you want to give a job.\n\nEscape or a click cancels.")

	local function Caught(self, key)
		if IGNORED_KEYS[key] then
			return
		end
		self:Hide()
		if key ~= "ESCAPE" then
			onKey(key)
		end
	end
	catcher:SetScript("OnKeyDown", Caught)
	catcher:SetScript("OnGamePadButtonDown", Caught)
	catcher:SetScript("OnMouseDown", catcher.Hide)
	return catcher
end

local function BuildButtons(panel)
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", 16, -14)
	title:SetText("Other buttons")

	local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", 18, -40)
	note:SetPoint("RIGHT", -20, 0)
	note:SetJustifyH("LEFT")
	note:SetText("FreeControl uses the D-pad, the four face buttons and the two triggers. Every other button on your controller is an ordinary button: it does whatever it is bound to, like a key on the keyboard. Give each one a job here. A job picked here is a normal key binding, so it shows in the game's Key Bindings screen as well and stays when FreeControl is switched off.")

	local left = 16
	local y = -90
	y = Heading(panel, "On most controllers", left, y)
	for _, key in ipairs(Layout.OTHER_KEYS) do
		y = KeyRow(panel, left, y, function() return key end)
	end

	y = Heading(panel, "Any other button or key", left, y - 8)
	local catcher = CreateCatcher(panel, function(key)
		Options.caughtKey = key
		Options:Sync()
	end)
	Options.catcher = catcher
	y = Action(panel, left, y, "Press it...", "For a button that is not in the list above, or a key on the keyboard: click this, then press it. It appears below with its job.", function()
		if InCombatLockdown() then
			ns.Print("Key bindings cannot be changed in combat.")
			return
		end
		catcher:Show()
	end, "Find a button")
	y = KeyRow(panel, left, y, function() return Options.caughtKey end)

	y = Heading(panel, "Everything else", left, y - 8)
	Action(panel, left, y, "Open Key Bindings", "The game's own Key Bindings screen. Anything can be bound there, to any button: FreeControl's two page buttons are listed under FreeControl.", function()
		Options:OpenKeyBindings()
	end, "Key Bindings")
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
	self.buttonsPanel = CreatePanel(BuildButtons)
	self.buttonsCategory = Settings.RegisterCanvasLayoutSubcategory(self.category, self.buttonsPanel, "Other buttons")
end

-- Brings the pages in line with the saved settings and the player's key bindings. A page that
-- is not on screen is left for when it is opened: this is called on every setting change, and
-- when the page is turned in a fight.
function Options:Sync()
	if not ((self.panel and self.panel:IsVisible()) or (self.buttonsPanel and self.buttonsPanel:IsVisible())) then
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
	ns.Print(("Slots: %s (asked for %s). Controller-bar slots start at %s, usable: %s, stance slots usable: %s"):format(
		source, db.slotSource, tostring(first), YesNo(Layout.HasGamepadSlots()), YesNo(Layout.HasStanceSlots())))
	local _, class = UnitClass("player")
	ns.Print(("Page %d of %d. Class: %s. Changes with your stance or form (setting: %s): %s"):format(Layout.GetPage(), Layout.GetPageCount(),
		tostring(class), db.stanceSet, Layout.DescribeStance()))
	ns.Print(("Page buttons: next page is on %s, previous page on %s."):format(
		GetBindingKey(ns.Bindings.PAGE_COMMANDS.next) or "no button", GetBindingKey(ns.Bindings.PAGE_COMMANDS.prev) or "no button"))
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
		ns.Print("Set held right now: " .. Layout.GetSetName(ns.Bindings:GetActiveSet()))
	end
	ns.Print(("Cooldown numbers: %s. The game seals combat values from addons: %s"):format(
		YesNo(db.cooldownNumbers), ns.DescribeSealing()))
	ns.Print(("Proc glow: %s (the game's proc signal is there: %s). Glowing right now: %s"):format(YesNo(db.procGlow),
		YesNo(C_SpellActivationOverlay ~= nil), ns.IsBuilt() and ns.Buttons:DescribeGlows() or "nothing"))
	ns.Print(ns.Ranks:Describe())

	if ns.Mouse:IsAvailable() then
		local index, key
		for i = 1, 8 do
			if Layout.IsCursorRole(db.roles[i]) then
				index, key = i, db.keys[i]
				break
			end
		end
		local bound = key and GetBindingAction(key, true) or ""
		ns.Print(("Mouse pointer: %s. Mouse button: %s (%s), bound right now to: %s. Pointer speed: %d%%"):format(ns.Mouse:IsOut() and "out" or "away",
			index and Layout.GetButtonName(Layout.SET_NONE, index) or "none", key or "-", bound ~= "" and bound or "nothing", db.cursorSpeed * 100 + 0.5))
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
	"/fc page <1-3> - which controller-bar page to show (the arrows in the middle of the bar turn it too)",
	"/fc buttons - give the bumpers, stick clicks, Start, Back and paddles their jobs",
	"/fc slots gamepad | bars - where the slots are stored",
	"/fc numbers on | off - count down the seconds on slots that are on cooldown",
	"/fc glow on | off - glow a button whose spell has procced or come free for a moment",
	"/fc ranks - move every spell on the bar up to its newest rank now (on | off: do it by itself whenever you learn one)",
	"/fc key <1-8 | lt | rt> <KEY> - use a different key for a slot or trigger (1-4 D-pad left/up/right/down, 5-8 face left/top/right/bottom)",
	"/fc stance auto | none | lt | rt | both | ltrt | all - what changes with your stance or form (ltrt = both trigger sets, all = those and the D-pad)",
	"/fc mouse - bring the controller's mouse pointer out or put it away",
	"/fc click left | right <BUTTON> - the button that clicks while the mouse pointer is out (game = leave it to the game)",
	"/fc pointer <50-300> - how fast the stick moves the mouse pointer, in percent",
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
	elseif command == "stance" and ns.IsOneOf(first, unpack(Layout.STANCE_CHOICES)) then
		-- In combat the change waits for the fight to end, and RequestRefresh has said so.
		Set("stanceSet", first)
		if not InCombatLockdown() then
			ns.Print(("Changes with your stance or form: %s."):format(Layout.DescribeStance()))
		end
	elseif command == "mouse" then
		ns.Mouse:Toggle(false)
	elseif command == "pointer" and tonumber(first) then
		Set("cursorSpeed", math.max(0.5, math.min(3, tonumber(first) / 100)))
	elseif command == "click" and ns.IsOneOf(first, "left", "right") and second and second ~= "" then
		-- In combat the change waits for the fight to end, and RequestRefresh has said so.
		if SetClick(first == "left" and 1 or 2, second == "game" and "game" or second:upper()) and not InCombatLockdown() then
			ns.Print(("Mouse clicks: %s."):format(ns.Mouse:DescribeClicks()))
		end
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
