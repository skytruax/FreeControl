local _, ns = ...
local Layout = ns.Layout

-- Turns controller presses into button clicks, and decides which slot each button shows.
--
-- The eight slot keys (D-pad and face buttons) are bound to whichever set is selected by the
-- triggers. The triggers are ordinary bindable buttons here, not Shift/Ctrl stand-ins, so holding
-- one changes nothing else in the game. Because the selection has to change in the middle of a
-- fight, the rebinding is done by a secure header in the restricted environment; this file's
-- normal Lua only hands it its settings, out of combat.
--
-- The same header points every button at its slot, for the same reason: the page can be turned
-- and the stance can change in a fight, and only secure code may give a button another action then.
local Bindings = {}
ns.Bindings = Bindings

-- Restricted snippet, self = header. Points the slot keys at the selected set and highlights it.
--   fc-kind-<page>-<set>-<i>    "click" (press that set's key button), "cmd" (run a game command) or nil
--   fc-target-<page>-<set>-<i>  the key button's name, or the command
-- A button's job belongs to a page, so these are looked up for the page being shown (fc-page).
-- A slot with no kind is unbound, which hands the key back to the player's own key binding.
--
-- Mouse mode (Mouse.lua) rides on the same snippet. While fc-mouse is set, the two click buttons
-- are bound to the commands the real mouse buttons run, so they click the world as well:
--   fc-click-<side>      the button, or nil when that click is left to the game
--   fc-clickcmd-<side>   the command
--   fc-clickslot-<side>  set when the button is also one of the eight slot keys, which the loop
--                        above has just bound and which is therefore not to be cleared
local APPLY = [=[
	local set = self:GetAttribute("fc-locked-set") or 0
	if not self:GetAttribute("fc-toggle-layers") then
		local left, right = self:GetAttribute("fc-l"), self:GetAttribute("fc-r")
		set = (left and 1 or 0) + (right and 2 or 0)
	end

	if self:GetAttribute("fc-enabled") then
		local page = self:GetAttribute("fc-page") or 1
		for i = 1, 8 do
			local key = self:GetAttribute("fc-key-" .. i)
			local kind = self:GetAttribute("fc-kind-" .. page .. "-" .. set .. "-" .. i)
			local target = self:GetAttribute("fc-target-" .. page .. "-" .. set .. "-" .. i)
			local spell = set == 0 and self:GetAttribute("fc-active-main-spell")
			if spell then
				kind = self:GetAttribute("fc-form-kind-" .. spell .. "-" .. i)
				target = self:GetAttribute("fc-form-target-" .. spell .. "-" .. i)
			end
			if kind == "click" then
				self:SetBindingClick(true, key, target, "LeftButton")
			elseif kind == "cmd" then
				self:SetBinding(true, key, target)
			else
				self:ClearBinding(key)
			end
		end

		local mouse = self:GetAttribute("fc-mouse")
		-- While the pointer is out the two triggers are the mouse wheel, up and down (fc-scroll says
		-- the player wants that; Mouse.lua). Put away, they are triggers again.
		if self:GetAttribute("fc-scroll") then
			for side = 1, 2 do
				local key = self:GetAttribute(side == 1 and "fc-left-key" or "fc-right-key")
				if key then
					self:SetBindingClick(true, key, (mouse and "FreeControlScroll" or "FreeControlTrigger") .. side, "LeftButton")
				end
			end
		end
		for side = 1, 2 do
			local key = self:GetAttribute("fc-click-" .. side)
			if key then
				if mouse then
					self:SetBinding(true, key, self:GetAttribute("fc-clickcmd-" .. side))
				elseif not self:GetAttribute("fc-clickslot-" .. side) then
					self:ClearBinding(key)
				end
			end
		end
	end

	local grown = self:GetAttribute("fc-scale-active")
	local faded = self:GetAttribute("fc-alpha-inactive")
	for id = 0, 3 do
		local frame = self:GetFrameRef("fc-set" .. id)
		if id == set then
			frame:SetScale(grown)
			frame:SetAlpha(1)
		else
			frame:SetScale(1)
			frame:SetAlpha(faded)
		end
	end

	self:SetAttribute("fc-set", set)
	self:CallMethod("FreeControl_OnSet", set)
]=]

-- A press toggles its layer. For a two-trigger press, compare against the layer that was
-- active before the first trigger, since that first press already selected a single layer.
local TRIGGER_ONCLICK = [=[
	local header = self:GetFrameRef("fc-header")
	local flag = self:GetAttribute("fc-flag")
	if not header:GetAttribute("fc-toggle-layers") then
		header:SetAttribute(flag, down and true or nil)
		header:RunAttribute("fc-apply")
		return
	end
	if not down then
		header:SetAttribute(flag, nil)
	elseif not header:GetAttribute(flag) then
		local previous = header:GetAttribute("fc-locked-set")
		header:SetAttribute(flag, true)
		local set = self:GetAttribute("fc-side")
		if header:GetAttribute("fc-l") and header:GetAttribute("fc-r") then
			set = 3
			previous = header:GetAttribute("fc-before-triggers")
		else
			header:SetAttribute("fc-before-triggers", previous)
		end
		header:SetAttribute("fc-locked-set", previous ~= set and set or nil)
		header:RunAttribute("fc-apply")
	end
]=]

local RELEASE_ONCLICK = [=[
	local header = self:GetFrameRef("fc-header")
	if down and header:GetAttribute("fc-enabled") and header:GetAttribute("fc-toggle-layers") then
		header:SetAttribute("fc-locked-set", nil)
		header:SetAttribute("fc-before-triggers", nil)
		header:RunAttribute("fc-apply")
	end
]=]

-- Restricted snippet, self = the mouse button. Like a trigger it is clicked on press and again on
-- release; only the press counts. It flips mouse mode on the header, which rebinds the click
-- buttons. Bringing the pointer out is ordinary code and follows in the button's PostClick.
-- With mouse mode switched off in the settings (fc-mouse-on, see TellMouseMode) a button still
-- bound to it does nothing.
local MOUSE_ONCLICK = [=[
	if not down then
		return
	end
	local header = self:GetFrameRef("fc-header")
	if not header:GetAttribute("fc-mouse-on") then
		return
	end
	if header:GetAttribute("fc-mouse") then
		header:SetAttribute("fc-mouse", nil)
	else
		header:SetAttribute("fc-mouse", 1)
	end
	header:RunAttribute("fc-apply")
]=]

-- Restricted snippet, self = header. Points every action button, and the key button over it, at
-- the slot it shows now: its slot on the page being shown or, on the stance page while a stance
-- bar is up, the stance's own. It runs when the page changes, when the stance does, and after
-- Buttons:Assign has handed over new settings; the first two happen in the middle of a fight.
--   fc-page, fc-pages          the page shown, and how many there are
--   state-fc-stance            the stance bar that is up, 0 for none: kept by a state driver
--   fc-stance-page             the one page whose buttons change with the stance
--   fc-slot-<page>-<set>-<i>   a button's slot on each page; none for one that is not a slot
--   fc-store-<set>-<i>         "pad" or "bar" for a button that changes with the stance
--   fc-offset-<set>-<i>        how far into a stance's slots of that kind it sits
--   fc-pad-<stance>            where each stance's slots of the two kinds begin
--   fc-bar-<stance>
--   fc-main-stance-page        set when Main changes with the form on the stance page alone (the
--                              player's own pick of layouts); without it, on every page
--   fc-keep-<stance>-<set>-<i> the slot the button shows in that stance (0: in none) instead of
--                              its own there: one that holds a stance or form the player put on
--                              the button elsewhere, where this stance has nothing of its own
-- The pictures follow the "action" attribute by themselves (Buttons.lua). Nothing here asks the
-- game anything: what is in a slot is looked at by ordinary code, out of combat, which hands
-- over the answer as fc-keep.
local ASSIGN = [=[
	local page = self:GetAttribute("fc-page") or 1
	local stance = tonumber(self:GetAttribute("state-fc-stance")) or 0
	local form = tonumber(self:GetAttribute("state-fc-main-form")) or 0
	local main = self:GetAttribute("fc-main-form-" .. form)
	if main and self:GetAttribute("fc-main-stance-page") and page ~= self:GetAttribute("fc-stance-page") then
		main = nil
	end
	local spell = main and self:GetAttribute("fc-main-spell-" .. form)
	if not spell then main = nil end
	local previousSpell = self:GetAttribute("fc-active-main-spell")
	self:SetAttribute("fc-active-main-form", main)
	self:SetAttribute("fc-active-main-spell", spell)
	local changing = page == self:GetAttribute("fc-stance-page")
	for set = 0, 3 do
		for i = 1, 8 do
			local id = set .. "-" .. i
			local slot = changing and self:GetAttribute("fc-keep-" .. stance .. "-" .. id)
			local store = not slot and changing and stance > 0 and self:GetAttribute("fc-store-" .. id)
			if store then
				local first = self:GetAttribute("fc-" .. store .. "-" .. stance)
				if first then
					slot = first + self:GetAttribute("fc-offset-" .. id)
				end
			end
			if not slot then
				slot = self:GetAttribute("fc-slot-" .. page .. "-" .. id)
			end
			if set == 0 and main then
				slot = self:GetAttribute("fc-form-action-" .. spell .. "-" .. i) and main + i - 1 or nil
			end
			local button = self:GetFrameRef("fc-button-" .. id)
			if button:GetAttribute("action") ~= slot then
				button:SetAttribute("action", slot)
			end
			local key = self:GetFrameRef("fc-key-" .. id)
			if key:GetAttribute("action") ~= slot then
				key:SetAttribute("action", slot)
			end
			-- A button that is a slot on this page shows its action; one that has a job here, or in
			-- this form, shows the job's picture instead. Both change with the page and the form.
			do
				local role = self:GetFrameRef("fc-role-" .. id)
				if slot and not button:IsShown() then
					button:Show(true)
					key:Show(true)
					role:Hide(true)
				elseif not slot and button:IsShown() then
					button:Hide(true)
					key:Hide(true)
					role:Show(true)
				end
			end
		end
	end
	if spell ~= previousSpell then
		self:CallMethod("FreeControl_OnMainForm")
	end
	if spell ~= previousSpell and self:GetAttribute("fc-enabled") and (self:GetAttribute("fc-set") or 0) == 0 then
		self:RunAttribute("fc-apply")
	end
	self:CallMethod("FreeControl_OnPage", page)
]=]

-- Restricted snippet, self = one of the two page buttons. Like the triggers it is clicked on
-- press and again on release, by the mouse or by a key bound to it; only the press counts.
-- Past the last page comes the first again, as in the Gamepad UI. With nothing to turn (the
-- regular action bars are the slots, or the player switched pages off) the page stays as it is,
-- which need not be the first.
local PAGE_ONCLICK = [=[
	if not down then
		return
	end
	local header = self:GetFrameRef("fc-header")
	local pages = header:GetAttribute("fc-pages") or 1
	if pages < 2 or not header:GetAttribute("fc-enabled") then
		return
	end
	local page = (header:GetAttribute("fc-page") or 1) + self:GetAttribute("fc-step")
	if page > pages then
		page = 1
	elseif page < 1 then
		page = pages
	end
	header:SetAttribute("fc-page", page)
	header:RunAttribute("fc-assign")
	-- What each button does belongs to the page too: bind the keys for this one.
	header:RunAttribute("fc-apply")
]=]

-- Restricted snippet, run before the click of one of the four party buttons; self = the button,
-- control = the header. The button is a secure action button that targets its "unit", and this
-- says which unit that is: the party member the press moves to. It is worked out on the press,
-- which is also when the button acts (useOnKeyDown). A place nobody is in is skipped; with no
-- party at all the unit is cleared and the click targets nothing.
--   fc-move    on the button: "Next", "Prev", "First" or "Last"
--   fc-party   on the header: the member picked last (1 to 4), shared by the four buttons
-- Next and previous go on from that member, not from the target: this code cannot ask who the
-- target is.
local PARTY_ONCLICK = [=[
	if not down then
		return
	end
	local move = self:GetAttribute("fc-move")
	local at = control:GetAttribute("fc-party") or 0
	if move == "Prev" and at < 1 then
		at = 1
	end
	local found
	for step = 1, 4 do
		local index
		if move == "First" then
			index = step
		elseif move == "Last" then
			index = 5 - step
		elseif move == "Next" then
			index = (at + step - 1) % 4 + 1
		else
			index = (at - step - 1) % 4 + 1
		end
		if not found and UnitExists("party" .. index) then
			found = index
		end
	end
	if found then
		control:SetAttribute("fc-party", found)
		self:SetAttribute("unit", "party" .. found)
	else
		self:SetAttribute("unit", nil)
	end
]=]

-- What the two page buttons are called in the Key Bindings screen (Bindings.xml lists them).
Bindings.PAGE_COMMANDS = {
	next = "CLICK FreeControlPageNext:LeftButton",
	prev = "CLICK FreeControlPagePrev:LeftButton",
}
-- The mouse button as a binding of the player's own, for a button other than the eight on the
-- bar; not listed in the Key Bindings screen, offered on the Other buttons page.
Bindings.MOUSE_COMMAND = "CLICK FreeControlMouse:LeftButton"
Bindings.RELEASE_COMMAND = "CLICK FreeControlLayerRelease:LeftButton"
_G["BINDING_NAME_" .. Bindings.MOUSE_COMMAND] = "FreeControl: mouse pointer on / off"
_G["BINDING_NAME_" .. Bindings.RELEASE_COMMAND] = "FreeControl: Return to main layer"
_G["BINDING_NAME_" .. Bindings.PAGE_COMMANDS.next] = "FreeControl: next page"
_G["BINDING_NAME_" .. Bindings.PAGE_COMMANDS.prev] = "FreeControl: previous page"

-- The four party buttons (Layout.PARTY_JOBS) as bindings: [the role's name] = the click.
Bindings.PARTY_COMMANDS = {}
local IS_PARTY_COMMAND = {}
for _, job in ipairs(Layout.PARTY_JOBS) do
	local command = ("CLICK FreeControlParty%s:LeftButton"):format(job[4])
	Bindings.PARTY_COMMANDS[job[1]] = command
	IS_PARTY_COMMAND[command] = true
	_G["BINDING_NAME_" .. command] = "FreeControl: " .. job[2]:lower()
end

-- The chat keyboard and the quick phrases window (the Chat folder) as bindings: [the role's
-- name] = the click, on a button Chat/Chat.lua makes. Neither works in a fight, so the buttons
-- are ordinary ones; they are clicks all the same, like every other binding FreeControl lists.
Bindings.CHAT_BUTTONS = { FREECONTROL_CHATKEYBOARD = "FreeControlChatToggle", FREECONTROL_PHRASES = "FreeControlPhrasesToggle" }
Bindings.CHAT_COMMANDS = {}
local IS_CHAT_COMMAND = {}
for _, job in ipairs(Layout.CHAT_JOBS) do
	local command = ("CLICK %s:LeftButton"):format(Bindings.CHAT_BUTTONS[job[1]])
	Bindings.CHAT_COMMANDS[job[1]] = command
	IS_CHAT_COMMAND[command] = true
	_G["BINDING_NAME_" .. command] = "FreeControl: " .. job[2]:lower()
end

-- The five jobs for grouping up (Layout.GROUP_JOBS) as bindings: [the role's name] = the click.
Bindings.GROUP_COMMANDS = {}
local IS_GROUP_COMMAND = {}
for _, job in ipairs(Layout.GROUP_JOBS) do
	local command = ("CLICK FreeControlGroup%s:LeftButton"):format(job[4])
	Bindings.GROUP_COMMANDS[job[1]] = command
	IS_GROUP_COMMAND[command] = true
	_G["BINDING_NAME_" .. command] = "FreeControl: " .. job[2]:lower()
end

-- What three of them run: the lines a player would put in a macro for it. "/invite" alone invites
-- the target, and %t is the target's name. A secure button runs its macro text in a fight too,
-- as long as the text was there before the fight began.
Bindings.GROUP_MACROS = {
	Invite = "/invite",
	Request = "/requestinvite %t",
	Leave = "/run C_PartyInfo.LeaveParty()",
}
-- The fourth invites the target, or asks to join the group the target is in already. Which of
-- the two applies is what the game's own menu for a player shows (GetDisplayedInviteType), and
-- out of combat the button is given just that line for the press, and both lines again straight
-- after it. In a fight its text cannot be changed, and who the target is may be sealed: there it
-- holds both lines, as it does whenever it is not being pressed, of which the game carries out
-- the one that applies and refuses the other with a line of red text. (It is not left to the
-- start of a fight to put both back: a client can be locked down already when it says so.)
local INVITE_BOTH = Bindings.GROUP_MACROS.Invite .. "\n" .. Bindings.GROUP_MACROS.Request

local function PickInvite(button)
	if InCombatLockdown() then
		return
	end
	local text = Bindings.GROUP_MACROS.Invite
	local guid = UnitGUID("target")
	if guid and not ns.IsSealed(guid) and GetDisplayedInviteType and GetDisplayedInviteType(guid) == "REQUEST_INVITE" then
		text = Bindings.GROUP_MACROS.Request
	end
	button:SetAttribute("macrotext", text)
end

local function BothInvites(button)
	if not InCombatLockdown() then
		button:SetAttribute("macrotext", INVITE_BOTH)
	end
end

-- The sixth says yes to a question the game is asking about a group. There are two, each a
-- dialog of the game's with an Accept button: an invitation to a group (PARTY_INVITE), and, for
-- the one who leads, somebody asking to join or a member suggesting someone
-- (GROUP_INVITE_CONFIRMATION). The job presses that button the way a click would, through the
-- game's own function for it, so whatever the dialog does on Accept is done. With neither on
-- screen it does nothing, and no other dialog is ever answered by it.
local GROUP_QUESTIONS = { "PARTY_INVITE", "GROUP_INVITE_CONFIRMATION" }

function Bindings:AcceptGroup()
	if not (StaticPopup_FindVisible and StaticPopup_OnClick) then
		return false
	end
	for _, which in ipairs(GROUP_QUESTIONS) do
		local dialog = StaticPopup_FindVisible(which)
		if dialog then
			StaticPopup_OnClick(dialog, 1)
			return true
		end
	end
	return false
end

-- Need, Greed and Pass (Layout.LOOT_JOBS) as bindings: [the role's name] = the click.
Bindings.LOOT_COMMANDS = {}
local IS_LOOT_COMMAND = {}
for _, job in ipairs(Layout.LOOT_JOBS) do
	local command = ("CLICK FreeControlLoot%s:LeftButton"):format(job[4])
	Bindings.LOOT_COMMANDS[job[1]] = command
	IS_LOOT_COMMAND[command] = true
	_G["BINDING_NAME_" .. command] = "FreeControl: " .. job[2]:lower()
end

-- Answers a roll for loot: `kind` is 1 for Need, 2 for Greed, 0 for Pass, as the game numbers
-- them. With several items being rolled for it answers them one at a press, in the order the
-- game lists them, and says in chat which item each answer was for.
--
-- An item that binds when picked up is not rolled for at once: the game asks first, in a dialog
-- (CONFIRM_LOOT_ROLL). That dialog is worked with a pointer, so the same job pressed again is
-- its Accept; another of the three pressed instead takes the question back and gives that
-- answer. Nothing is confirmed that the player did not press for twice.
local ROLL_NAMES = { [0] = "Pass", [1] = "Need", [2] = "Greed" }
local rolled = {}  -- [roll] = true for the rolls answered here that are still going
local asked        -- the roll the game may be asking about: { id =, kind = }

-- What the game calls the item, for the chat line. In a fight it may not say.
local function RollItem(roll)
	local link = GetLootRollItemLink and GetLootRollItemLink(roll)
	if link and not ns.IsSealed(link) then
		return link
	end
	return "the item"
end

-- The game's own windows for the rolls, by roll, for the ones on screen: nil when none is found
-- (another interface's windows, or none up yet).
local function RollWindows()
	local found
	for index = 1, NUM_GROUP_LOOT_FRAMES or 4 do
		local frame = _G["GroupLootFrame" .. index]
		local roll = frame and frame:IsShown() and frame.rollID
		if roll and not ns.IsSealed(roll) then
			found = found or {}
			found[roll] = frame
		end
	end
	return found
end

-- The roll the next press answers, and the game's window for it where there is one: the first
-- still going that was not answered here. The game takes a roll's window away once it has been
-- answered, by a click as well, so where its windows can be seen a roll without one is passed
-- over. The rolls that have ended are forgotten.
function Bindings:NextRoll()
	if not GetActiveLootRollIDs then
		return nil
	end
	local windows = RollWindows()
	local going, roll = {}, nil
	for _, id in ipairs(GetActiveLootRollIDs() or {}) do
		going[id] = true
		if not roll and not rolled[id] and (not windows or windows[id]) then
			roll = id
		end
	end
	for id in pairs(rolled) do
		if not going[id] then rolled[id] = nil end
	end
	return roll, windows and roll and windows[roll] or nil
end

-- The roll the game is asking about right now (its question is on screen), or nil.
function Bindings:AskedRoll()
	if asked and StaticPopup_FindVisible and StaticPopup_FindVisible("CONFIRM_LOOT_ROLL") then
		return asked.id
	end
	return nil
end

function Bindings:RollOnLoot(kind)
	if not (GetActiveLootRollIDs and GetLootRollItemInfo and RollOnLoot) then
		return false
	end
	local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible("CONFIRM_LOOT_ROLL")
	if dialog and asked then
		if asked.kind == kind then
			StaticPopup_OnClick(dialog, 1)
			asked = nil
		else
			StaticPopup_Hide("CONFIRM_LOOT_ROLL")
			asked.kind = kind
			RollOnLoot(asked.id, kind)
			ns.Print(("%s instead: %s"):format(ROLL_NAMES[kind], RollItem(asked.id)))
		end
		return true
	end
	local roll = self:NextRoll()
	if not roll then
		ns.Print("No item is being rolled for.")
		return false
	end
	-- Need and Greed are not open to everyone for every item. What the game seals in a fight is
	-- taken as allowed: it refuses the roll itself if it is not.
	local _, _, _, _, _, canNeed, canGreed = GetLootRollItemInfo(roll)
	local can = kind == 0 or (kind == 1 and canNeed) or (kind == 2 and canGreed)
	if kind ~= 0 and ns.IsSealed(kind == 1 and canNeed or canGreed) then
		can = true
	end
	if not can then
		ns.Print(("You cannot roll %s on %s."):format(ROLL_NAMES[kind], RollItem(roll)))
		return false
	end
	RollOnLoot(roll, kind)
	rolled[roll] = true
	asked = { id = roll, kind = kind }
	ns.Print(("%s: %s"):format(ROLL_NAMES[kind], RollItem(roll)))
	return true
end

-- True for a command that clicks one of FreeControl's own buttons.
function Bindings:IsOwnCommand(command)
	return command == self.PAGE_COMMANDS.next or command == self.PAGE_COMMANDS.prev
		or command == self.MOUSE_COMMAND or command == self.RELEASE_COMMAND
		or IS_PARTY_COMMAND[command] == true or IS_CHAT_COMMAND[command] == true
		or IS_GROUP_COMMAND[command] == true or IS_LOOT_COMMAND[command] == true
end

-- Out of combat. Needs the set frames and the buttons to exist.
function Bindings:Create()
	local header = CreateFrame("Frame", "FreeControlHeader", UIParent, "SecureHandlerStateTemplate")
	self.header = header
	header:SetAttribute("fc-apply", APPLY)
	header:SetAttribute("fc-assign", ASSIGN)
	-- The stance bar that is up changed: the state driver registered by Buttons:Assign said so.
	header:SetAttribute("_onstate-fc-stance", [[ self:RunAttribute("fc-assign") ]])
	header:SetAttribute("_onstate-fc-main-form", [[ self:RunAttribute("fc-assign") ]])
	for _, set in ipairs(Layout.SETS) do
		header:SetFrameRef("fc-set" .. set, ns.Bars.sets[set])
		for index = 1, 8 do
			local id = set .. "-" .. index
			header:SetFrameRef("fc-button-" .. id, ns.Buttons.action[set][index])
			header:SetFrameRef("fc-key-" .. id, ns.Buttons.proxy[set][index])
			header:SetFrameRef("fc-role-" .. id, ns.Buttons.layerRole[set][index])
		end
	end

	-- Called from the snippets above for the parts that are not protected (glow, labels, badges,
	-- the page number).
	function header:FreeControl_OnSet(set)
		ns.Bars:OnSetChanged(set)
	end
	function header:FreeControl_OnPage(page)
		ns.OnPageShown(page)
	end
	function header:FreeControl_OnMainForm()
		ns.Buttons:UpdateRoleWidgets()
	end

	-- The two page buttons in the middle of the bar. Bars.lua made them and gave them their
	-- looks; what a click does is decided here, in secure code, so a page can be changed in a fight.
	self.pageButtons = {}
	for step, button in pairs(ns.Bars.pageButtons) do
		button:RegisterForClicks("AnyDown", "AnyUp")
		button:SetAttribute("fc-step", step)
		button:SetFrameRef("fc-header", header)
		button:SetAttribute("_onclick", PAGE_ONCLICK)
		self.pageButtons[step] = button
	end

	self.triggers = {}
	for side, flag in ipairs({ "fc-l", "fc-r" }) do
		local trigger = CreateFrame("Button", "FreeControlTrigger" .. side, header, "SecureHandlerClickTemplate")
		trigger:RegisterForClicks("AnyDown", "AnyUp")
		trigger:SetAttribute("fc-flag", flag)
		trigger:SetAttribute("fc-side", side)
		trigger:SetFrameRef("fc-header", header)
		trigger:SetAttribute("_onclick", TRIGGER_ONCLICK)
		self.triggers[side] = trigger
	end
	local release = CreateFrame("Button", "FreeControlLayerRelease", header, "SecureHandlerClickTemplate")
	release:RegisterForClicks("AnyDown", "AnyUp")
	release:SetFrameRef("fc-header", header)
	release:SetAttribute("_onclick", RELEASE_ONCLICK)
	self.release = release
	-- The four party buttons. Each targets the unit the snippet gives it just before the click;
	-- like the key buttons they hear the press and the release, and act on the press.
	self.partyButtons = {}
	for _, job in ipairs(Layout.PARTY_JOBS) do
		local party = CreateFrame("Button", "FreeControlParty" .. job[4], header, "SecureActionButtonTemplate")
		party:RegisterForClicks("AnyDown", "AnyUp")
		party:SetAttribute("type", "target")
		party:SetAttribute("useOnKeyDown", true)
		party:SetAttribute("fc-move", job[4])
		header:WrapScript(party, "OnClick", PARTY_ONCLICK)
		self.partyButtons[job[1]] = party
	end
	-- The six buttons for grouping up. Four run a macro's lines; the fifth opens the game's own
	-- menu for the target, where the pointer is, and since that menu is worked with a pointer it
	-- brings the controller's out (with mouse mode on; a real mouse needs nothing); the sixth
	-- answers the game's question about a group (Bindings:AcceptGroup).
	self.groupButtons = {}
	for _, job in ipairs(Layout.GROUP_JOBS) do
		local isAccept = job[4] == "Accept"
		local button = CreateFrame("Button", "FreeControlGroup" .. job[4], header, not isAccept and "SecureActionButtonTemplate" or nil)
		button:RegisterForClicks("AnyDown", "AnyUp")
		if isAccept then
			-- An ordinary button: answering the game's dialog is nothing an addon needs leave for.
			button:SetScript("OnClick", function(_, _, down)
				if down then
					ns.Try(self.AcceptGroup, self)
				end
			end)
		elseif job[4] == "Menu" then
			button:SetAttribute("useOnKeyDown", true)
			button:SetAttribute("type", "togglemenu")
			button:SetAttribute("unit", "target")
			button:SetScript("PostClick", function(_, _, down)
				-- With nobody targeted there is no menu. (In a fight the answer may be sealed, which
				-- cannot be compared with anything: sealed means there is someone.)
				local target = UnitGUID("target")
				local someone = ns.IsSealed(target) or target ~= nil
				if down and someone and ns.Mouse:IsEnabled() and not ns.Mouse:IsOut() then
					ns.Try(ns.Mouse.BringOut, ns.Mouse)
				end
			end)
		else
			button:SetAttribute("useOnKeyDown", true)
			button:SetAttribute("type", "macro")
			button:SetAttribute("macrotext", self.GROUP_MACROS[job[4]] or INVITE_BOTH)
			if job[4] == "InviteOrRequest" then
				button:SetScript("PreClick", function(clicked, _, down)
					if down then
						ns.Try(PickInvite, clicked)
					end
				end)
				button:SetScript("PostClick", function(clicked)
					ns.Try(BothInvites, clicked)
				end)
			end
		end
		self.groupButtons[job[1]] = button
	end
	-- The mouse wheel, up (1) and down (2): what the triggers click while the pointer is out. The
	-- press turns the wheel one notch and, held, goes on turning it (Mouse:StartScroll).
	for side = 1, 2 do
		local scroll = CreateFrame("Button", "FreeControlScroll" .. side, header)
		scroll:RegisterForClicks("AnyDown", "AnyUp")
		scroll:SetScript("OnClick", function(_, _, down)
			if down then
				ns.Try(ns.Mouse.StartScroll, ns.Mouse, side == 1 and 1 or -1)
			else
				ns.Mouse:StopScroll()
			end
		end)
	end
	-- Need, Greed and Pass: ordinary buttons, each answering a roll for loot on its press.
	self.lootButtons = {}
	for _, job in ipairs(Layout.LOOT_JOBS) do
		local button = CreateFrame("Button", "FreeControlLoot" .. job[4], header)
		button:RegisterForClicks("AnyDown", "AnyUp")
		button:SetScript("OnClick", function(_, _, down)
			if down then
				ns.Try(self.RollOnLoot, self, job[5])
			end
		end)
		self.lootButtons[job[1]] = button
	end
	-- An explicit empty role consumes the key on this layer without changing its WoW binding.
	self.noAction = CreateFrame("Button", "FreeControlNoAction", header, "SecureHandlerClickTemplate")

	-- What the mouse button on the bar (Y unless changed) is bound to. Ordinary code cannot rebind
	-- anything in a fight; this can. It is registered for the press and the release exactly as
	-- the triggers are, and acts on the press only: 1.2.0 asked for presses alone, which no
	-- other button here does.
	local mouse = CreateFrame("Button", "FreeControlMouse", header, "SecureHandlerClickTemplate")
	mouse:RegisterForClicks("AnyDown", "AnyUp")
	mouse:SetFrameRef("fc-header", header)
	mouse:SetAttribute("_onclick", MOUSE_ONCLICK)
	-- Runs after the snippet whether or not it got through, so the pointer never depends on it.
	mouse:SetScript("PostClick", function(_, _, down)
		if down then
			ns.Try(ns.Mouse.OnButtonPressed, ns.Mouse)
		end
	end)
	self.mouse = mouse
end

-- Whether a press of the mouse button counts: mouse mode is in use. Both halves of a press go by
-- this one answer, the secure snippet above and Mouse:OnButtonPressed, so they cannot disagree
-- while a change of the setting waits for a fight to end. Out of combat.
local function TellMouseMode(header)
	header:SetAttribute("fc-mouse-on", ns.Mouse:IsEnabled() or nil)
end

function Bindings:IsMouseButtonOn()
	return self.header:GetAttribute("fc-mouse-on") ~= nil
end

function Bindings:GetRoleBinding(role, set, index)
	local kind, command = Layout.ParseRole(role)
	if kind == "action" then
		return "click", ns.Buttons.proxy[set][index]:GetName()
	elseif kind == "none" then
		return "click", self.noAction:GetName()
	elseif command == Layout.CURSOR_COMMAND then
		if ns.Mouse:IsAvailable() then return "click", self.mouse:GetName() end
	elseif command == Layout.RELEASE_ROLE_COMMAND then
		return "click", self.release:GetName()
	elseif kind == "cmd" then
		if self.partyButtons[command] then return "click", self.partyButtons[command]:GetName() end
		if self.CHAT_BUTTONS[command] then return "click", self.CHAT_BUTTONS[command] end
		if self.groupButtons[command] then return "click", self.groupButtons[command]:GetName() end
		if self.lootButtons[command] then return "click", self.lootButtons[command]:GetName() end
		for _, page in ipairs(Layout.PAGE_ROLES) do
			if command == page[1] then return "click", self.pageButtons[page[3]]:GetName() end
		end
		return "cmd", command
	end
end

-- Out of combat. Hands the header the current settings and binds everything. While the bar's
-- buttons are lent out (Suspend, below) nothing is bound: Resume does it.
function Bindings:Apply()
	if self.suspended then
		return
	end
	local db = ns.db
	local header = self.header
	ClearOverrideBindings(header)

	for index = 1, 8 do
		header:SetAttribute("fc-key-" .. index, db.keys[index])
		for _, set in ipairs(Layout.SETS) do
			for page = 1, Layout.NUM_PAGES do
				local kind, target = self:GetRoleBinding(Layout.GetRole(set, index, nil, page), set, index)
				header:SetAttribute(("fc-kind-%d-%d-%d"):format(page, set, index), kind)
				header:SetAttribute(("fc-target-%d-%d-%d"):format(page, set, index), target)
			end
		end
	end

	for side = 1, 2 do
		local key = ns.Mouse:IsAvailable() and ns.Mouse:GetManagedKey(side) or nil
		local isSlotKey = false
		for index = 1, 8 do
			isSlotKey = isSlotKey or db.keys[index] == key
		end
		header:SetAttribute("fc-click-" .. side, key)
		header:SetAttribute("fc-clickcmd-" .. side, ns.Mouse.COMMANDS[side])
		header:SetAttribute("fc-clickslot-" .. side, isSlotKey or nil)
	end
	header:SetAttribute("fc-mouse", ns.Mouse:IsOut() and 1 or nil)
	header:SetAttribute("fc-scroll", (db.mouseScroll and ns.Mouse:IsAvailable()) or nil)
	TellMouseMode(header)

	header:SetAttribute("fc-scale-active", db.activeScale)
	header:SetAttribute("fc-alpha-inactive", db.inactiveAlpha)
	if header:GetAttribute("fc-toggle-layers") ~= db.toggleLayers
		or header:GetAttribute("fc-left-key") ~= db.modKeys[1] or header:GetAttribute("fc-right-key") ~= db.modKeys[2] then
		header:SetAttribute("fc-locked-set", nil)
	end
	header:SetAttribute("fc-toggle-layers", db.toggleLayers)
	header:SetAttribute("fc-left-key", db.modKeys[1])
	header:SetAttribute("fc-right-key", db.modKeys[2])
	header:SetAttribute("fc-l", nil)
	header:SetAttribute("fc-r", nil)
	header:SetAttribute("fc-before-triggers", nil)
	header:SetAttribute("fc-enabled", true)

	for side = 1, 2 do
		SetOverrideBindingClick(header, true, db.modKeys[side], self.triggers[side]:GetName(), "LeftButton")
	end
	header:Execute([[ self:RunAttribute("fc-apply") ]])
end

-- Out of combat. Gives every key back to the player's own bindings. A button the player bound
-- to the mouse button themselves is one of those, and still goes by the mouse mode setting.
function Bindings:Clear()
	local header = self.header
	TellMouseMode(header)
	header:SetAttribute("fc-enabled", nil)
	header:SetAttribute("fc-locked-set", nil)
	header:SetAttribute("fc-l", nil)
	header:SetAttribute("fc-r", nil)
	header:SetAttribute("fc-before-triggers", nil)
	ClearOverrideBindings(header)
end

-- The chat keyboard and the quick phrases window (the Chat folder) are worked with the D-pad and
-- the face buttons, which are the bar's. While one of them is open the bar lets go of every
-- button it has, triggers included, and binds none: the secure header binds the eight slot keys
-- again at each press or release of a trigger, and what is bound last is what a key does, so a
-- window that only bound its keys over the bar's lost them at the next trigger. Both are out of
-- combat only, as the windows are. The bar comes back on the main layer.
function Bindings:Suspend()
	if self.suspended then
		return
	end
	self.suspended = true
	if self.header then
		self:Clear()
	end
end

function Bindings:Resume()
	if not self.suspended then
		return
	end
	self.suspended = false
	if self.header and ns.IsActive() then
		self:Apply()
	end
end

function Bindings:IsSuspended()
	return self.suspended == true
end

-- The selected set (0 main, 1 left, 2 right, 3 both).
function Bindings:GetActiveSet()
	return self.header and self.header:GetAttribute("fc-set") or 0
end

---------------------------------------------------------------------------
-- Things that would stop the keys from reaching us; listed by /fc status
---------------------------------------------------------------------------
function Bindings:FindProblems()
	local db = ns.db
	local problems = {}

	local used = {}
	local function Claim(key, what)
		if used[key] then
			problems[#problems + 1] = ("%s is set for both %s and %s."):format(key, used[key], what)
		end
		used[key] = what
	end
	for index = 1, 8 do
		Claim(db.keys[index], Layout.GetButtonName(0, index))
	end
	Claim(db.modKeys[1], "the left trigger")
	Claim(db.modKeys[2], "the right trigger")

	-- While the controller is steering the mouse cursor the client turns these two buttons into
	-- mouse clicks and they never reach the key bindings.
	for _, cvar in ipairs({ "GamePadCursorLeftClick", "GamePadCursorRightClick" }) do
		local button = GetCVar(cvar)
		if button and button ~= "" and used[button] then
			problems[#problems + 1] = ("%s is also the controller's mouse-click button (%s), so it clicks instead while the mouse pointer is out."):format(button, cvar)
		end
	end
	for _, set in ipairs(Layout.SETS) do
		for index = 1, 8 do
			if Layout.IsCursorRole(Layout.GetRole(set, index))
				and (db.keys[index] == ns.Mouse:GetManagedKey(1) or db.keys[index] == ns.Mouse:GetManagedKey(2)) then
				problems[#problems + 1] = ("%s is both the mouse button and a click button. While the pointer is out it clicks, so jump to put the pointer away."):format(
					Layout.GetButtonName(set, index))
			end
		end
	end
	if ns.Mouse:IsEnabled() and not Layout.HasCursorRole() and not GetBindingKey(Bindings.MOUSE_COMMAND) then
		problems[#problems + 1] = "No button brings the mouse pointer out. Click a no-trigger button on the bar and choose \"Mouse pointer on / off\", or give another button that job under Other buttons in the settings."
	end
	-- A button chosen on the Combinations page that cannot be held after all: FreeControl uses it
	-- now, or it has been given a job of its own somewhere else.
	for _, modifier in ipairs({ "Ctrl", "Alt", "Shift" }) do
		local chosen = db.standIns[modifier]
		if chosen and chosen ~= "none" and ns.CVars:GetCombinationButton(modifier) ~= chosen then
			problems[#problems + 1] = ("%s was chosen to be held as %s, but FreeControl uses that button itself or it has a job of its own, so it is not held for combinations."):format(
				Layout.GetKeyName(chosen), modifier)
		end
	end
	-- With this on, the game pins the pointer to the middle of the screen instead of letting the
	-- stick move it. CVars.lua turns it off; this says so if something turned it back on.
	if GetCVar("GamePadCursorCentering") == "1" then
		problems[#problems + 1] = "GamePadCursorCentering is on, which pins the mouse pointer to the middle of the screen. Turn it off with: /console GamePadCursorCentering 0"
	end
	for side, setting in ipairs({ "clickLeft", "clickRight" }) do
		if db[setting] ~= "game" and not ns.Mouse:GetManagedKey(side) then
			problems[#problems + 1] = ("%s is a trigger, so it cannot also be the %s mouse click. That click is left to the game. Change it with /fc click."):format(
				db[setting], side == 1 and "left" or "right")
		end
	end

	-- Other controller setups make a button stand in for Shift, Ctrl or Alt. FreeControl does not
	-- need that, and a held modifier changes what every other key and click does.
	for _, cvar in ipairs({ "GamePadEmulateShift", "GamePadEmulateCtrl", "GamePadEmulateAlt" }) do
		local button = GetCVar(cvar)
		if button and used[button] then
			problems[#problems + 1] = ("%s is also set to act as a modifier key (%s). Clear it with: /console %s none"):format(button, cvar, cvar)
		end
	end
	return problems
end
