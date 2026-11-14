local _, ns = ...
local Layout = ns.Layout

-- Turns controller presses into button clicks.
--
-- The eight slot keys (D-pad and face buttons) are bound to whichever set is selected by the
-- triggers. The triggers are ordinary bindable buttons here, not Shift/Ctrl stand-ins, so holding
-- one changes nothing else in the game. Because the selection has to change in the middle of a
-- fight, the rebinding is done by a secure header in the restricted environment; this file's
-- normal Lua only hands it its settings, out of combat.
local Bindings = {}
ns.Bindings = Bindings

-- Restricted snippet, self = header. Works out the held set from the two trigger flags, points
-- the slot keys at that set, and resizes the sets so the held one stands out.
--   fc-kind-<set>-<i>    "click" (press that set's key button), "cmd" (run a game command) or nil
--   fc-target-<set>-<i>  the key button's name, or the command
-- A slot with no kind is unbound, which hands the key back to the player's own key binding.
--
-- Mouse mode (Mouse.lua) rides on the same snippet. While fc-mouse is set, the two click buttons
-- are bound to the commands the real mouse buttons run, so they click the world as well:
--   fc-click-<side>      the button, or nil when that click is left to the game
--   fc-clickcmd-<side>   the command
--   fc-clickslot-<side>  set when the button is also one of the eight slot keys, which the loop
--                        above has just bound and which is therefore not to be cleared
local APPLY = [=[
	local left, right = self:GetAttribute("fc-l"), self:GetAttribute("fc-r")
	local set = 0
	if left and right then
		set = 3
	elseif left then
		set = 1
	elseif right then
		set = 2
	end

	if self:GetAttribute("fc-enabled") then
		for i = 1, 8 do
			local key = self:GetAttribute("fc-key-" .. i)
			local kind = self:GetAttribute("fc-kind-" .. set .. "-" .. i)
			local target = self:GetAttribute("fc-target-" .. set .. "-" .. i)
			if kind == "click" then
				self:SetBindingClick(true, key, target, "LeftButton")
			elseif kind == "cmd" then
				self:SetBinding(true, key, target)
			else
				self:ClearBinding(key)
			end
		end

		local mouse = self:GetAttribute("fc-mouse")
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

-- Restricted snippet, self = one of the two trigger buttons. It is clicked on press and again on
-- release, and records which of the two it is on the header.
local TRIGGER_ONCLICK = [=[
	local header = self:GetFrameRef("fc-header")
	if down then
		header:SetAttribute(self:GetAttribute("fc-flag"), 1)
	else
		header:SetAttribute(self:GetAttribute("fc-flag"), nil)
	end
	header:RunAttribute("fc-apply")
]=]

-- Restricted snippet, self = the mouse button. Like a trigger it is clicked on press and again on
-- release; only the press counts. It flips mouse mode on the header, which rebinds the click
-- buttons. Bringing the pointer out is ordinary code and follows in the button's PostClick.
local MOUSE_ONCLICK = [=[
	if not down then
		return
	end
	local header = self:GetFrameRef("fc-header")
	if header:GetAttribute("fc-mouse") then
		header:SetAttribute("fc-mouse", nil)
	else
		header:SetAttribute("fc-mouse", 1)
	end
	header:RunAttribute("fc-apply")
]=]

-- Out of combat. Needs the set frames and the buttons to exist.
function Bindings:Create()
	local header = CreateFrame("Frame", "FreeControlHeader", UIParent, "SecureHandlerStateTemplate")
	self.header = header
	header:SetAttribute("fc-apply", APPLY)
	for _, set in ipairs(Layout.SETS) do
		header:SetFrameRef("fc-set" .. set, ns.Bars.sets[set])
	end

	-- Called from the snippet above for the parts that are not protected (glow, labels, badges).
	function header:FreeControl_OnSet(set)
		ns.Bars:OnSetChanged(set)
	end

	self.triggers = {}
	for side, flag in ipairs({ "fc-l", "fc-r" }) do
		local trigger = CreateFrame("Button", "FreeControlTrigger" .. side, header, "SecureHandlerClickTemplate")
		trigger:RegisterForClicks("AnyDown", "AnyUp")
		trigger:SetAttribute("fc-flag", flag)
		trigger:SetFrameRef("fc-header", header)
		trigger:SetAttribute("_onclick", TRIGGER_ONCLICK)
		self.triggers[side] = trigger
	end

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

-- Out of combat. Hands the header the current settings and binds everything.
function Bindings:Apply()
	local db = ns.db
	local header = self.header
	ClearOverrideBindings(header)

	for index = 1, 8 do
		header:SetAttribute("fc-key-" .. index, db.keys[index])
		for _, set in ipairs(Layout.SETS) do
			local kind, target
			if ns.Buttons:IsActionSlot(set, index) then
				kind, target = "click", ns.Buttons.proxy[set][index]:GetName()
			else
				local roleKind, command = Layout.ParseRole(db.roles[index])
				if Layout.IsCursorRole(db.roles[index]) then
					-- Not a game command. Without a pointer in this client the button is left alone.
					if ns.Mouse:IsAvailable() then
						kind, target = "click", self.mouse:GetName()
					end
				elseif roleKind == "cmd" then
					kind, target = "cmd", command
				end
			end
			header:SetAttribute(("fc-kind-%d-%d"):format(set, index), kind)
			header:SetAttribute(("fc-target-%d-%d"):format(set, index), target)
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

	header:SetAttribute("fc-scale-active", db.activeScale)
	header:SetAttribute("fc-alpha-inactive", db.inactiveAlpha)
	header:SetAttribute("fc-l", nil)
	header:SetAttribute("fc-r", nil)
	header:SetAttribute("fc-enabled", true)

	for side = 1, 2 do
		SetOverrideBindingClick(header, true, db.modKeys[side], self.triggers[side]:GetName(), "LeftButton")
	end
	header:Execute([[ self:RunAttribute("fc-apply") ]])
end

-- Out of combat. Gives every key back to the player's own bindings.
function Bindings:Clear()
	local header = self.header
	header:SetAttribute("fc-enabled", nil)
	header:SetAttribute("fc-l", nil)
	header:SetAttribute("fc-r", nil)
	ClearOverrideBindings(header)
end

-- The set currently selected by the triggers (0 none, 1 left, 2 right, 3 both).
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
	for index = 1, 8 do
		if Layout.IsCursorRole(db.roles[index])
			and (db.keys[index] == ns.Mouse:GetManagedKey(1) or db.keys[index] == ns.Mouse:GetManagedKey(2)) then
			problems[#problems + 1] = ("%s is both the mouse button and a click button. While the pointer is out it clicks, so jump to put the pointer away."):format(
				Layout.GetButtonName(0, index))
		end
	end
	if ns.Mouse:IsAvailable() and not ns.Mouse:GetBarButtonName() then
		problems[#problems + 1] = "No button brings the mouse pointer out. Click a no-trigger button on the bar and choose \"Mouse pointer on / off\"."
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
