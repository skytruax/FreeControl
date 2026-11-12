local _, ns = ...
local Layout = ns.Layout

-- The buttons themselves. Every action slot gets two frames:
--
--   * a visible button that draws the action and answers the mouse (click on release, drag and
--     drop, tooltip), and
--   * an invisible "key" button on top of it that the controller is bound to, which acts on press.
--
-- Both are plain SecureActionButtonTemplate buttons whose click runs Blizzard's own
-- SecureActionButton_OnClick and nothing else, so nothing of ours runs before the protected
-- call and casting keeps working in combat. Two rules follow from that:
--
--   * everything this addon stores on a button lives under button.fc, and
--   * no field that Blizzard's click path reads (popup, isExtra, buttonType) is ever written.
local Buttons = {}
ns.Buttons = Buttons

Buttons.action = {} -- [set][index] = visible action button
Buttons.proxy = {}  -- [set][index] = key button
Buttons.role = {}   -- [index] = stand-in shown for a no-trigger button that is not an action slot

local ART = ns.ART
local CIRCLE_MASK = ART .. "Round-Mask" -- a white disc: clips round icons and shapes their cooldown sweep
local ICON_INSET = 3

local all = {}     -- every visible action button
local bySlot = {}  -- [slot] = { [button] = true }, for events that name a slot
local activeSet = 0

---------------------------------------------------------------------------
-- Drawing an action
---------------------------------------------------------------------------
local function UpdateUsable(button)
	local fc = button.fc
	if not fc.hasAction then
		return
	end
	if fc.outOfRange then
		fc.icon:SetVertexColor(0.9, 0.25, 0.25)
		return
	end
	local usable, lackingResources = C_ActionBar.IsUsableAction(fc.slot)
	if usable then
		fc.icon:SetVertexColor(1, 1, 1)
	elseif lackingResources then
		fc.icon:SetVertexColor(0.5, 0.5, 1)
	else
		fc.icon:SetVertexColor(0.4, 0.4, 0.4)
	end
end

local function UpdateCooldown(button)
	local fc = button.fc
	if not fc.hasAction then
		return
	end
	-- Same shape as Blizzard's ActionButton_ApplyCooldown: branch on isActive, hand the numbers
	-- straight to the cooldown frame.
	local info = C_ActionBar.GetActionCooldown(fc.slot)
	if info and info.isActive then
		fc.cooldown:SetCooldown(info.startTime, info.duration, info.modRate)
	else
		fc.cooldown:Clear()
	end
end

local function UpdateCount(button)
	local fc = button.fc
	if fc.hasAction then
		fc.count:SetText(C_ActionBar.GetActionDisplayCount(fc.slot))
	end
end

local function UpdateState(button)
	local fc = button.fc
	if fc.hasAction then
		button:SetChecked(C_ActionBar.IsCurrentAction(fc.slot) or C_ActionBar.IsAutoRepeatAction(fc.slot))
	else
		button:SetChecked(false)
	end
end

local function UpdateBadge(button)
	local fc = button.fc
	fc.badge:SetShown(fc.round and fc.hasAction and fc.set == activeSet)
end

-- The icon and the empty-slot glyph swap by alpha, not Show/Hide. They are anchored to the
-- protected button and this runs in combat (a slot can change mid-fight); alpha is never a
-- protected property, whatever the client thinks of regions anchored to protected frames.
local GLYPH_ALPHA = 0.5
local function ShowIcon(fc, shown)
	fc.icon:SetAlpha(shown and 1 or 0)
	fc.glyph:SetAlpha(shown and 0 or GLYPH_ALPHA)
end

local ShowTooltip

local function Update(button)
	local fc = button.fc
	local slot = fc.slot
	fc.hasAction = slot ~= nil and C_ActionBar.HasAction(slot)
	if fc.hasAction then
		fc.icon:SetTexture(C_ActionBar.GetActionTexture(slot))
		ShowIcon(fc, true)
		fc.cooldown:SetHideCountdownNumbers(not GetCVarBool("countdownForCooldowns"))
		local text = C_ActionBar.UsesActionText(slot) and C_ActionBar.GetActionText(slot)
		fc.name:SetText(text or "")
		if C_ActionBar.IsEquippedAction(slot) then
			button:GetNormalTexture():SetVertexColor(0.45, 1, 0.45)
		else
			button:GetNormalTexture():SetVertexColor(1, 1, 1)
		end
		UpdateUsable(button)
		UpdateCooldown(button)
		UpdateCount(button)
	else
		ShowIcon(fc, false)
		fc.cooldown:Clear()
		fc.count:SetText("")
		fc.name:SetText("")
		button:GetNormalTexture():SetVertexColor(1, 1, 1)
	end
	UpdateState(button)
	UpdateBadge(button)
	if GameTooltip:GetOwner() == button then
		ShowTooltip(button)
	end
end

local function ForEachWithAction(fn)
	for _, button in ipairs(all) do
		if button.fc.hasAction then
			fn(button)
		end
	end
end

local function UpdateAll()
	for _, button in ipairs(all) do
		Update(button)
	end
end

---------------------------------------------------------------------------
-- Which slot a button shows
---------------------------------------------------------------------------
-- The client only reports range changes for slots that asked for them, and counts the requests,
-- so every "on" is paired with exactly one "off".
local function SetRangeSlot(button, slot)
	local fc = button.fc
	if fc.rangeSlot == slot then
		return
	end
	if fc.rangeSlot then
		C_ActionBar.EnableActionRangeCheck(fc.rangeSlot, false)
	end
	fc.rangeSlot = slot
	fc.outOfRange = false
	if slot then
		C_ActionBar.EnableActionRangeCheck(slot, true)
	end
end

local function SetSlot(button, slot)
	local fc = button.fc
	if fc.slot ~= slot then
		if fc.slot then
			bySlot[fc.slot][button] = nil
		end
		fc.slot = slot
		if slot then
			bySlot[slot] = bySlot[slot] or {}
			bySlot[slot][button] = true
		end
	end
	SetRangeSlot(button, slot)
	Update(button)
end

-- The "action" attribute is the single source of truth for the slot: it is set by us out of
-- combat and by the stance driver at any time, and the picture follows it from here.
local function OnAttributeChanged(button, name, value)
	if name == "action" then
		SetSlot(button, tonumber(value))
	end
end

---------------------------------------------------------------------------
-- Mouse: tooltip, drag and drop
---------------------------------------------------------------------------
function ShowTooltip(button)
	local fc = button.fc
	GameTooltip_SetDefaultAnchor(GameTooltip, button)
	if fc.hasAction and GameTooltip:SetAction(fc.slot) then
		GameTooltip:AddLine(Layout.GetButtonName(fc.set, fc.index), 0.37, 0.84, 1)
		GameTooltip:Show()
		button.UpdateTooltip = ShowTooltip -- the tooltip calls this while it stays up (cooldown text)
	else
		GameTooltip:SetText(Layout.GetButtonName(fc.set, fc.index), 0.37, 0.84, 1)
		GameTooltip:AddLine("Empty. Drop a spell, item or macro here.", 1, 1, 1, true)
		GameTooltip:Show()
		button.UpdateTooltip = nil
	end
end

local function HideTooltip(button)
	button.UpdateTooltip = nil
	if GameTooltip:GetOwner() == button then
		GameTooltip:Hide()
	end
end

local function WarnInCombat()
	UIErrorsFrame:AddMessage("You can't move actions on the FreeControl bar in combat.", 1, 0.1, 0.1)
end

local function OnDragStart(button)
	local slot = button.fc.slot
	if not slot or not button.fc.hasAction then
		return
	end
	-- Same rule as the regular action bars: locked bars need the pick-up modifier (Shift by default).
	if Settings.GetValue("lockActionBars") and not IsModifiedClick("PICKUPACTION") then
		return
	end
	if InCombatLockdown() then
		WarnInCombat()
		return
	end
	PickupAction(slot)
end

local function OnReceiveDrag(button)
	local slot = button.fc.slot
	if not slot or not GetCursorInfo() then
		return
	end
	if InCombatLockdown() then
		WarnInCombat()
		return
	end
	PlaceAction(slot)
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local secureClickMissing = false

-- Both templates define OnClick and the one listed last wins, which has to be the secure one.
-- If a client ever resolved that the other way round the buttons would silently do nothing, so
-- it is checked once and reported instead.
local SECURE_TEMPLATES = "FlyoutButtonTemplate, SecureActionButtonTemplate"

local function CheckSecureClick(frame)
	if frame:GetScript("OnClick") ~= SecureActionButton_OnClick then
		secureClickMissing = true
	end
end

function Buttons:IsSecureClickMissing()
	return secureClickMissing
end

local function AddArt(frame, round)
	local shape = round and "Round" or "Square"
	local fc = frame.fc

	fc.base = frame:CreateTexture(nil, "BACKGROUND")
	fc.base:SetAllPoints()
	fc.base:SetTexture(ART .. shape .. "-Base")

	fc.icon = frame:CreateTexture(nil, "BORDER")
	fc.icon:SetPoint("TOPLEFT", ICON_INSET, -ICON_INSET)
	fc.icon:SetPoint("BOTTOMRIGHT", -ICON_INSET, ICON_INSET)
	if round then
		local mask = frame:CreateMaskTexture()
		mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(fc.icon)
		fc.icon:AddMaskTexture(mask)
	else
		fc.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- trims the built-in border most spell icons have
	end

	-- What the button is, shown while the slot is empty.
	fc.glyph = frame:CreateTexture(nil, "BORDER", nil, 2)
	fc.glyph:SetPoint("CENTER")
	fc.glyph:SetSize(20, 20)
	fc.glyph:SetAlpha(GLYPH_ALPHA)

	frame:SetNormalTexture(ART .. shape .. "-Border")
	frame:SetPushedTexture(ART .. shape .. "-Pushed")
	frame:SetHighlightTexture(ART .. shape .. "-Highlight", "ADD")
end

local function CreateActionButton(set, index, parent)
	local round = Layout.IsRound(index)
	local button = CreateFrame("CheckButton", ("FreeControlButton%d_%d"):format(set, index), parent, SECURE_TEMPLATES)
	CheckSecureClick(button)
	button:SetSize(Layout.BUTTON_SIZE, Layout.BUTTON_SIZE)
	button:SetPoint("CENTER", parent, "CENTER", unpack(Layout.BUTTON_OFFSET[index]))

	button:SetAttribute("type", "action")
	-- A mouse click acts on release, so a drag can pick the action up without casting it first.
	button:SetAttribute("useOnKeyDown", false)
	button:SetAttribute("checkselfcast", true)
	button:SetAttribute("checkfocuscast", true)
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton", "RightButton")

	local fc = { set = set, index = index, round = round, hasAction = false, outOfRange = false }
	button.fc = fc
	AddArt(button, round)
	button:SetCheckedTexture(ART .. (round and "Round" or "Square") .. "-Checked")

	fc.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	fc.cooldown:SetAllPoints(fc.icon)
	fc.cooldown:SetDrawEdge(false)
	fc.cooldown:SetDrawBling(false)
	fc.cooldown:SetSwipeColor(0, 0, 0, 0.72)
	if round then
		fc.cooldown:SetSwipeTexture(CIRCLE_MASK)
		fc.cooldown:SetUseCircularEdge(true)
	end

	-- Text and the corner badge sit above the cooldown sweep.
	fc.overlay = CreateFrame("Frame", nil, button)
	fc.overlay:SetAllPoints()
	fc.overlay:SetFrameLevel(button:GetFrameLevel() + 4)

	fc.count = fc.overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	fc.count:SetPoint("BOTTOMRIGHT", -2, 3)

	fc.name = fc.overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
	fc.name:SetPoint("BOTTOMLEFT", 2, 3)
	fc.name:SetPoint("BOTTOMRIGHT", -2, 3)
	fc.name:SetHeight(10)
	fc.name:SetWordWrap(false)

	-- Anchored to the overlay, not the button, so showing it never touches a protected frame.
	fc.badge = fc.overlay:CreateTexture(nil, "OVERLAY")
	fc.badge:SetSize(15, 15)
	fc.badge:SetPoint("CENTER", fc.overlay, "TOPRIGHT", -4, -4)
	fc.badge:Hide()

	-- HookScript keeps the flyout template's own handlers (they track hover and press for its arrow).
	button:HookScript("OnEnter", ShowTooltip)
	button:HookScript("OnLeave", HideTooltip)
	button:HookScript("OnDragStart", OnDragStart)
	button:SetScript("OnReceiveDrag", OnReceiveDrag)
	button:SetScript("PostClick", UpdateState)
	button:HookScript("OnAttributeChanged", OnAttributeChanged)

	all[#all + 1] = button
	return button
end

local function CreateKeyButton(set, index, button)
	local proxy = CreateFrame("Button", ("FreeControlKey%d_%d"):format(set, index), button:GetParent(), SECURE_TEMPLATES)
	CheckSecureClick(proxy)
	-- Same rectangle as the visible button, so a spell flyout opened from the controller lands
	-- in the right place, but never in the mouse's way.
	proxy:SetAllPoints(button)
	proxy:EnableMouse(false)
	proxy:SetAttribute("type", "action")
	-- No useOnKeyDown here: the key acts on press or on release as the player's own
	-- "cast on key down" setting says, like the regular action bars.
	proxy:RegisterForClicks("AnyDown", "AnyUp")
	proxy:SetScript("PostClick", function(_, _, down)
		button:SetButtonState(down and "PUSHED" or "NORMAL")
		if not down then
			UpdateState(button)
		end
	end)
	return proxy
end

---------------------------------------------------------------------------
-- Stand-ins for no-trigger buttons that run a command or are left alone
---------------------------------------------------------------------------
local function RoleTooltip(widget)
	local index = widget.fc.index
	local kind, command = Layout.ParseRole(ns.db.roles[index])
	GameTooltip_SetDefaultAnchor(GameTooltip, widget)
	GameTooltip:SetText(Layout.GetButtonName(0, index), 0.37, 0.84, 1)
	if kind == "cmd" then
		GameTooltip:AddLine(Layout.GetCommandInfo(command), 1, 1, 1, true)
	else
		local bound = GetBindingAction(ns.db.keys[index], true)
		if bound and bound ~= "" then
			GameTooltip:AddLine("Your own key binding: " .. GetBindingName(bound), 1, 1, 1, true)
		else
			GameTooltip:AddLine("Left to your own key bindings (nothing is bound yet).", 1, 1, 1, true)
		end
	end
	GameTooltip:AddLine("Click to change what this button does.", 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

local function CreateRoleWidget(index, parent)
	local widget = CreateFrame("Button", nil, parent)
	widget:SetSize(Layout.BUTTON_SIZE, Layout.BUTTON_SIZE)
	widget:SetPoint("CENTER", parent, "CENTER", unpack(Layout.BUTTON_OFFSET[index]))
	widget.fc = { index = index, round = Layout.IsRound(index) }
	AddArt(widget, widget.fc.round)
	widget:SetScript("OnEnter", RoleTooltip)
	widget:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	widget:SetScript("OnClick", function(self)
		ns.Options:OpenRoleMenu(self, index)
	end)
	return widget
end

local function UpdateRoleWidget(widget)
	local fc = widget.fc
	local kind, command = Layout.ParseRole(ns.db.roles[fc.index])
	if kind == "cmd" then
		local _, art = Layout.GetCommandInfo(command)
		fc.icon:SetTexture(ART .. art)
	end
	ShowIcon(fc, kind == "cmd")
end

---------------------------------------------------------------------------
-- Module interface
---------------------------------------------------------------------------
-- Out of combat. Needs ns.Bars:Create() to have made the set frames.
function Buttons:Create()
	for _, set in ipairs(Layout.SETS) do
		local parent = ns.Bars.sets[set]
		self.action[set], self.proxy[set] = {}, {}
		for index = 1, 8 do
			local button = CreateActionButton(set, index, parent)
			self.action[set][index] = button
			self.proxy[set][index] = CreateKeyButton(set, index, button)
			if set == Layout.SET_NONE then
				self.role[index] = CreateRoleWidget(index, parent)
			end
		end
	end
	if secureClickMissing then
		ns.Print("|cffff4040The secure click handler is missing from the buttons, so they cannot cast. Please report this with the output of /fc status.|r")
	end
end

-- True when a no-trigger button is an action slot; the other sets always are.
function Buttons:IsActionSlot(set, index)
	return set ~= Layout.SET_NONE or Layout.ParseRole(ns.db.roles[index]) == "action"
end

-- Out of combat. Points every button at its slot and shows the right widget for each position.
function Buttons:Assign()
	Layout.Prepare()
	local stanceSet = Layout.GetStanceSet()
	for _, set in ipairs(Layout.SETS) do
		for index = 1, 8 do
			local button, proxy = self.action[set][index], self.proxy[set][index]
			if self:IsActionSlot(set, index) then
				-- The plain slot is always written first. A stance driver only takes over on the
				-- client's next update, and a button with no "action" would fall back to slot 1.
				local slot = Layout.GetSlot(set, index)
				UnregisterAttributeDriver(button, "action")
				UnregisterAttributeDriver(proxy, "action")
				button:SetAttribute("action", slot)
				proxy:SetAttribute("action", slot)
				if set == stanceSet then
					local driver = Layout.GetStanceDriver(set, index)
					RegisterAttributeDriver(button, "action", driver)
					RegisterAttributeDriver(proxy, "action", driver)
				end
				button:Show()
				proxy:Show()
			else
				UnregisterAttributeDriver(button, "action")
				UnregisterAttributeDriver(proxy, "action")
				button:Hide()
				proxy:Hide()
				SetSlot(button, nil)
			end
			-- A driver may not have written the attribute yet; read back whatever is there now.
			if button:IsShown() then
				SetSlot(button, tonumber(button:GetAttribute("action")))
			end
			if set == Layout.SET_NONE then
				local widget = self.role[index]
				widget:SetShown(not button:IsShown())
				UpdateRoleWidget(widget)
			end
		end
	end
	self:UpdateGlyphs()
end

-- Glyphs follow the controller style (Xbox letters, PlayStation shapes, ...).
function Buttons:UpdateGlyphs()
	for _, button in ipairs(all) do
		local file = ART .. Layout.GetGlyph(button.fc.index)
		button.fc.glyph:SetTexture(file)
		button.fc.badge:SetTexture(file)
	end
	for index, widget in pairs(self.role) do
		widget.fc.glyph:SetTexture(ART .. Layout.GetGlyph(index))
	end
end

-- Called (in combat too) when a different set becomes the held one. Nothing protected in here.
function Buttons:OnSetChanged(set)
	activeSet = set
	for _, button in ipairs(all) do
		UpdateBadge(button)
		-- The keys now point at another set, so a release may never reach a button that was
		-- being held; do not leave it looking pressed.
		button:SetButtonState("NORMAL")
	end
end

-- Out of combat. Used when the bars are switched off: stops the stance drivers and stops asking
-- the client for range updates. Assign puts both back.
function Buttons:Release()
	for _, set in ipairs(Layout.SETS) do
		for index = 1, 8 do
			UnregisterAttributeDriver(self.action[set][index], "action")
			UnregisterAttributeDriver(self.proxy[set][index], "action")
			SetRangeSlot(self.action[set][index], nil)
		end
	end
end

function Buttons:GetSlot(set, index)
	local button = self.action[set] and self.action[set][index]
	return button and button.fc.slot
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.On("ACTIONBAR_SLOT_CHANGED", function(_, slot)
	if slot == 0 then -- 0 means "all of them"
		UpdateAll()
	elseif bySlot[slot] then
		for button in pairs(bySlot[slot]) do
			Update(button)
		end
	end
end)

for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_SHAPESHIFT_FORM", "SPELL_UPDATE_ICON", "PLAYER_EQUIPMENT_CHANGED" }) do
	ns.On(event, UpdateAll)
end

for _, event in ipairs({ "ACTIONBAR_UPDATE_COOLDOWN" }) do
	ns.On(event, function() ForEachWithAction(UpdateCooldown) end)
end

for _, event in ipairs({ "ACTIONBAR_UPDATE_STATE", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT", "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL" }) do
	ns.On(event, function() ForEachWithAction(UpdateState) end)
end

for _, event in ipairs({ "ACTIONBAR_UPDATE_USABLE", "PLAYER_MOUNT_DISPLAY_CHANGED" }) do
	ns.On(event, function() ForEachWithAction(UpdateUsable) end)
end

ns.On("ACTION_USABLE_CHANGED", function(_, changes)
	for _, change in ipairs(changes) do
		if bySlot[change.slot] then
			for button in pairs(bySlot[change.slot]) do
				UpdateUsable(button)
			end
		end
	end
end)

ns.On("ACTION_RANGE_CHECK_UPDATE", function(_, slot, inRange, checksRange)
	if bySlot[slot] then
		for button in pairs(bySlot[slot]) do
			button.fc.outOfRange = checksRange and not inRange
			UpdateUsable(button)
		end
	end
end)

for _, event in ipairs({ "SPELL_UPDATE_CHARGES", "BAG_UPDATE" }) do
	ns.On(event, function() ForEachWithAction(UpdateCount) end)
end
