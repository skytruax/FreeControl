local _, ns = ...
local Layout = ns.Layout

-- The buttons themselves. Every action slot gets two frames:
--
--   * a visible button that draws the action and answers the mouse (click on release, drag and
--     drop, tooltip), and
--   * an invisible "key" button on top of it that the controller is bound to, which acts on press.
--
-- Cooldowns follow the game's events (the list at the end of this file) and are drawn without
-- reading them, because in combat the game seals their numbers; see UpdateCooldown.
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
local ICON_INSET = 2       -- the icon starts just under the inner edge of the rim
local ICON_CROP = 0.07     -- trims the built-in border most spell icons have (square buttons)
local MIN_COUNTDOWN = 1750 -- milliseconds: shorter cooldowns (the global cooldown) show no number
local PROC_SIZE = Layout.BUTTON_SIZE * 128 / 88 -- the glow's picture is larger than the button: see proc() in tools/make_art.py

local all = {}     -- every visible action button
local bySlot = {}  -- [slot] = { [button] = true }, for events that name a slot
local activeSet = 0

---------------------------------------------------------------------------
-- Drawing an action
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- The glow of a proc
---------------------------------------------------------------------------
-- A button glows while the game says its spell has procced: the same question Blizzard's own
-- action buttons ask (C_SpellActivationOverlay.IsSpellOverlayed), answered by the same two events,
-- so whatever lights up on the regular bars lights up here.
--
-- A handful of abilities are never marked that way: they simply cannot be used until something
-- has happened (Layout.REACTIVE). Those glow from the moment they come free until the game takes
-- them back, they are used, or Layout.REACTIVE_TIME has passed.
--
-- The glow is a picture on the button's overlay frame, shown by alpha and pulsed by an
-- animation, neither of which the game restricts in combat.
local function IsReactiveFree(fc)
	if not (fc.reactive and fc.ready and fc.freeSince) or GetTime() - fc.freeSince >= Layout.REACTIVE_TIME then
		return false
	end
	return fc.reactive ~= "unstealthed" or not IsStealthed()
end

local function UpdateGlow(button)
	local fc = button.fc
	local glow = false
	if fc.hasAction and ns.db.procGlow then
		glow = (fc.spell ~= nil and C_SpellActivationOverlay ~= nil and C_SpellActivationOverlay.IsSpellOverlayed(fc.spell))
			or IsReactiveFree(fc)
	end
	if glow == fc.glowing then
		return
	end
	fc.glowing = glow
	if glow then
		fc.proc:SetAlpha(1)
		fc.procPulse:Play()
	else
		fc.procPulse:Stop()
		fc.proc:SetAlpha(0)
	end
end

-- Follows an ability that can only be used for a moment after something has happened. "Locked"
-- is unusable for a reason other than power: that is its resting state. Coming out of it is the
-- moment it came free.
local function NoteReactive(button, usable, lackingResources)
	local fc = button.fc
	local locked = not usable and not lackingResources
	if locked then
		fc.freeSince = nil
	elseif fc.locked then
		fc.freeSince = GetTime()
		-- Nothing announces that the time is up, so the glow is looked at again when it is.
		C_Timer.After(Layout.REACTIVE_TIME, function()
			ns.Try(UpdateGlow, button)
		end)
	end
	fc.locked = locked
	fc.ready = usable
end

local function UpdateUsable(button)
	local fc = button.fc
	if not fc.hasAction then
		return
	end
	local usable, lackingResources = C_ActionBar.IsUsableAction(fc.slot)
	if fc.outOfRange then
		fc.icon:SetVertexColor(0.9, 0.25, 0.25)
	elseif usable then
		fc.icon:SetVertexColor(1, 1, 1)
	elseif lackingResources then
		fc.icon:SetVertexColor(0.5, 0.5, 1)
	else
		fc.icon:SetVertexColor(0.4, 0.4, 0.4)
	end
	if fc.reactive then
		NoteReactive(button, usable, lackingResources)
		UpdateGlow(button)
	end
end

-- A cooldown is drawn without ever reading it. In combat the game seals when a cooldown started
-- and how long it is (see "Sealed values" in Core.lua): C_ActionBar.GetActionCooldown still
-- answers, but startTime, duration and modRate come back sealed, and a cooldown frame refuses
-- sealed numbers from an addon with an error. Versions up to 1.1.1 handed it exactly those
-- (Cooldown:SetCooldown), so a sweep could not appear for as long as the numbers stayed sealed.
--
-- Two things are never sealed, and they are all a bar needs: isActive, which says whether there
-- is a cooldown to show, and a duration object, which carries the timing to the frame without
-- exposing it. The frame then draws the sweep and the countdown number itself.
local function UpdateCooldown(button)
	local fc = button.fc
	if not fc.hasAction then
		return
	end
	local info = C_ActionBar.GetActionCooldown(fc.slot)
	if info and info.isActive then
		fc.cooldown:SetCooldownFromDurationObject(C_ActionBar.GetActionCooldownDuration(fc.slot))
	else
		fc.cooldown:Clear()
	end
end

-- The count is sealed in combat as well (charges are cooldown information). It is only ever
-- passed on to the font string, which accepts a sealed text.
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

-- The ring around an equipped item has the colour of the item's rarity, as the item's border has
-- in the bags. Up to 1.2.0 it was always green, the one colour the regular action bars use, which
-- made a rare item look like an uncommon one. Green is kept for an item used through a macro, and
-- for one the game has not loaded yet: that one is coloured when GET_ITEM_INFO_RECEIVED arrives.
local EQUIPPED_COLOR = { 0.25, 1, 0.3 }

local function UpdateRing(button)
	local fc = button.fc
	fc.ringPending = nil
	if not (fc.hasAction and C_ActionBar.IsEquippedAction(fc.slot)) then
		fc.equipped:SetAlpha(0)
		return
	end
	local r, g, b = unpack(EQUIPPED_COLOR)
	local item = fc.item
	if item then
		local quality = C_Item.GetItemQualityByID(item)
		if quality then
			r, g, b = C_Item.GetItemQualityColor(quality)
		else
			fc.ringPending = item
		end
	end
	fc.equipped:SetVertexColor(r, g, b)
	fc.equipped:SetAlpha(1)
end

local ShowTooltip

-- What is in the slot, as far as the pictures need to know: the item for the ring, the spell for
-- the glow. On a client that seals what is in a slot, neither is known while it does.
local function ReadAction(fc)
	local item, spell
	if fc.hasAction then
		local kind, id, subKind = GetActionInfo(fc.slot)
		if id and not ns.IsSealed(id) then
			if kind == "item" then
				item = id
			elseif kind == "spell" or (kind == "macro" and subKind == "spell") then
				spell = id
			end
		end
	end
	if spell ~= fc.spell then
		-- A different spell: what was known about the old one coming free no longer applies. A
		-- redraw of the same spell must leave that alone, or it would end a glow in mid-fight.
		fc.reactive = spell and Layout.REACTIVE[C_Spell.GetSpellName(spell) or ""] or nil
		fc.locked, fc.ready, fc.freeSince = nil, nil, nil
	end
	fc.item, fc.spell = item, spell
end

local function Update(button)
	local fc = button.fc
	local slot = fc.slot
	fc.hasAction = slot ~= nil and C_ActionBar.HasAction(slot)
	ReadAction(fc)
	if fc.hasAction then
		fc.icon:SetTexture(C_ActionBar.GetActionTexture(slot))
		ShowIcon(fc, true)
		fc.cooldown:SetHideCountdownNumbers(not ns.db.cooldownNumbers)
		local text = C_ActionBar.UsesActionText(slot) and C_ActionBar.GetActionText(slot)
		fc.name:SetText(text or "")
		UpdateUsable(button)
		UpdateCooldown(button)
		UpdateCount(button)
	else
		ShowIcon(fc, false)
		fc.cooldown:Clear()
		fc.count:SetText("")
		fc.name:SetText("")
	end
	UpdateRing(button)
	UpdateGlow(button)
	UpdateState(button)
	UpdateBadge(button)
	if GameTooltip:GetOwner() == button then
		ShowTooltip(button)
	end
end

-- Each button on its own: if one cannot be drawn, that is reported and the rest still are.
local function ForEachWithAction(fn)
	for _, button in ipairs(all) do
		if button.fc.hasAction then
			ns.Try(fn, button)
		end
	end
end

local function UpdateAll()
	for _, button in ipairs(all) do
		Update(button)
	end
end

---------------------------------------------------------------------------
-- A shapeshift on a button that changes with the form
---------------------------------------------------------------------------
-- A Druid's forms, a Rogue's Stealth and a Warrior's stances are spells like any other, and can
-- be dropped on a button that changes with the form. If the button then simply changed, the
-- shapeshift would be gone the moment it was used, and the way back out with it: the first thing
-- a player new to this trips over. So a shapeshift stays where it is in every stance that has
-- nothing of its own on that button (UpdateKept, below), and the first time one is seen on such
-- a button the character is told how that works.
local function IsFormSpell(spell)
	if not (GetNumShapeshiftForms and GetShapeshiftFormInfo) then
		return false
	end
	for index = 1, GetNumShapeshiftForms() do
		local _, _, _, formSpell = GetShapeshiftFormInfo(index)
		if formSpell and not ns.IsSealed(formSpell) and formSpell == spell then
			return true
		end
	end
	return false
end

local function NoteFormSpell(button)
	local fc = button.fc
	if not (fc.group and fc.spell) or Layout.GetPage() ~= Layout.GetStancePage() then
		return
	end
	local character = UnitGUID("player")
	if not character or ns.db.formNotes[character] or not IsFormSpell(fc.spell) then
		return
	end
	ns.db.formNotes[character] = true
	ns.Print(("%s is on %s, a button that changes with your stance or form. It stays there in every one of them, until you put something else on that button while you are in one: that covers it there. On the %s set, the face buttons and the other pages nothing can cover it."):format(
		C_Spell.GetSpellName(fc.spell) or "A stance or form", Layout.GetButtonName(fc.set, fc.index), Layout.GetSetName(Layout.SET_BOTH)))
end

-- True when a slot holds a stance or form, directly or through a macro.
local function HoldsForm(slot)
	if not C_ActionBar.HasAction(slot) then
		return false
	end
	local kind, id, subKind = GetActionInfo(slot)
	if not id or ns.IsSealed(id) then
		return false
	end
	return (kind == "spell" or (kind == "macro" and subKind == "spell")) and IsFormSpell(id)
end

-- Out of combat. Works out, for every button that changes with the stance and every stance,
-- whether the button keeps its page slot there: it holds a shapeshift, and the stance has
-- nothing of its own on that button. The answers go to the secure header, which needs them in
-- the middle of a fight and may not look for itself. Returns true when one of them changed.
local function UpdateKept()
	local header = ns.Bindings.header
	local page = Layout.GetStancePage()
	local changed = false
	for _, button in ipairs(all) do
		local fc = button.fc
		local group = fc.group
		local holdsForm = group ~= nil and HoldsForm(Layout.GetSlot(fc.set, fc.index, page))
		for stance = 1, Layout.NUM_STANCES do
			local name = ("fc-keep-%d-%d-%d"):format(stance, fc.set, fc.index)
			local keep = holdsForm and not C_ActionBar.HasAction(Layout.GetStanceSlot(group, stance, fc.index)) or nil
			if header:GetAttribute(name) ~= keep then
				header:SetAttribute(name, keep)
				changed = true
			end
		end
	end
	return changed
end

-- Something that decides the above may have changed: what is in a slot, or which forms the
-- character has. It is looked at once, after the client has finished saying so, and never in a
-- fight: nothing can be moved on the bar in one, and the header keeps what it was last told.
-- The game announces slots for its own reasons all through a fight (a macro's icon changing is
-- one), so in a fight the first such announcement books one look for when it ends, and every
-- later one costs nothing.
local keptPending = false

local function LookAtKept()
	keptPending = false
	ns.RunOutOfCombat("kept", function()
		if ns.IsActive() and UpdateKept() then
			ns.Bindings.header:Execute([[ self:RunAttribute("fc-assign") ]])
		end
	end)
end

local function KeptMayHaveChanged()
	if keptPending or not ns.IsBuilt() then
		return
	end
	keptPending = true
	if InCombatLockdown() then
		ns.RunOutOfCombat("kept", LookAtKept)
	else
		C_Timer.After(0, function()
			ns.Try(LookAtKept)
		end)
	end
end

-- The stance bar the secure header is following right now, on the page where stances change the
-- buttons; 0 anywhere else.
local function FollowedStance()
	local header = ns.Bindings.header
	local stance = tonumber(header:GetAttribute("state-fc-stance")) or 0
	if stance < 1 or stance > Layout.NUM_STANCES or header:GetAttribute("fc-page") ~= header:GetAttribute("fc-stance-page") then
		return 0
	end
	return stance
end

-- The slot that is a button's own right now: its stance slot in a stance, else the slot it
-- shows. The two differ for a button that is keeping a shapeshift: what is dropped on it there
-- becomes the stance's own, and covers the shapeshift in that stance alone.
local function OwnSlot(button)
	local fc = button.fc
	local stance = fc.group and FollowedStance() or 0
	if stance > 0 then
		return Layout.GetStanceSlot(fc.group, stance, fc.index)
	end
	return fc.slot
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

-- The "action" attribute is the single source of truth for the slot. The secure header sets it,
-- when the page or the stance changes as much as when the settings do, and the picture follows
-- it from here.
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
		if OwnSlot(button) ~= fc.slot then
			GameTooltip:AddLine("Kept from your normal buttons: this stance or form has nothing of its own here. Drop something on the button to give it that.", 0.6, 0.6, 0.6, true)
		end
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
	if not button.fc.slot or not GetCursorInfo() then
		return
	end
	if InCombatLockdown() then
		WarnInCombat()
		return
	end
	PlaceAction(OwnSlot(button))
end

---------------------------------------------------------------------------
-- Press feedback
---------------------------------------------------------------------------
-- A held button draws its art a little smaller and darker, and springs back when it is let go.
-- Nothing is resized: the buttons are protected and may not be touched in combat. Each texture
-- is told to sample a slightly larger area instead, which draws its picture that much smaller
-- inside the same rectangle (the art has clear edges, so what lies beyond them is empty).
local PRESS_INSET = 0.045 -- at full press the art is about 8% smaller
local RELEASE_TIME = 0.12 -- seconds it takes to spring back
local pressed = {}        -- [frame] = true while its key or mouse button is down
local releasing = {}      -- [frame] = seconds since it was let go
local watchRoleKeys = false

local animator = CreateFrame("Frame")
animator:Hide()

local function ApplyPress(frame, amount)
	local fc = frame.fc
	for _, part in ipairs(fc.pressParts) do
		local crop = part.crop
		local inset = PRESS_INSET * amount * (1 - 2 * crop)
		part.texture:SetTexCoord(crop - inset, 1 - crop + inset, crop - inset, 1 - crop + inset)
	end
	fc.pressShade:SetAlpha(amount)
end

-- source is "keyDown" or "mouseDown"; the button looks held while either is.
local function Press(frame, source, down)
	local fc = frame.fc
	fc[source] = down or nil
	if fc.keyDown or fc.mouseDown then
		releasing[frame] = nil
		if not pressed[frame] then
			pressed[frame] = true
			ApplyPress(frame, 1) -- at once: the press is the moment that has to feel immediate
		end
	elseif pressed[frame] then
		pressed[frame] = nil
		releasing[frame] = 0
		animator:Show()
	end
end

-- A button that runs a game command, or is left to the player's own binding, is bound straight
-- to that command: no click passes through this addon, so the key itself is watched (Blizzard's
-- ClassActionFlyout watches its own combination the same way).
local function WatchRoleKeys()
	for index, widget in pairs(Buttons.role) do
		if widget:IsShown() then
			Press(widget, "keyDown", activeSet == 0 and IsKeyDown(ns.db.keys[index]))
		end
	end
end

animator:SetScript("OnUpdate", function(self, elapsed)
	for frame, age in pairs(releasing) do
		age = age + elapsed
		if age >= RELEASE_TIME then
			releasing[frame] = nil
			ApplyPress(frame, 0)
		else
			releasing[frame] = age
			local left = 1 - age / RELEASE_TIME
			ApplyPress(frame, left * left) -- quick at first, settling at the end
		end
	end
	if watchRoleKeys then
		WatchRoleKeys()
	elseif not next(releasing) then
		self:Hide()
	end
end)

-- A slot was just used, by key or by mouse. Nothing needs doing for the bar itself: the game's
-- events bring the cooldown. This only tells /fc trace, when it is recording, which button to watch.
local function NoteUse(button)
	if ns.Trace.active then
		ns.Try(ns.Trace.Press, ns.Trace, button)
	end
end

local function OnMouseDown(frame)
	Press(frame, "mouseDown", true)
end

local function OnMouseUp(frame)
	Press(frame, "mouseDown", false)
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

-- ownIcon: the icon is one of this addon's own, which has no border to trim.
local function AddArt(frame, round, ownIcon)
	local shape = round and "Round" or "Square"
	local fc = frame.fc
	fc.shape = shape

	fc.base = frame:CreateTexture(nil, "BACKGROUND")
	fc.base:SetAllPoints()
	fc.base:SetTexture(ART .. shape .. "-Base")

	fc.icon = frame:CreateTexture(nil, "BORDER")
	fc.icon:SetPoint("TOPLEFT", ICON_INSET, -ICON_INSET)
	fc.icon:SetPoint("BOTTOMRIGHT", -ICON_INSET, ICON_INSET)
	-- A white disc or rounded square: it clips the icon to the shape of the rim, and (below) gives
	-- the cooldown sweep the same shape, so nothing shows past the rim's rounded corners.
	fc.maskFile = ART .. shape .. "-Mask"
	local mask = frame:CreateMaskTexture()
	mask:SetTexture(fc.maskFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(fc.icon)
	fc.icon:AddMaskTexture(mask)

	-- What the button is, shown while the slot is empty.
	fc.glyph = frame:CreateTexture(nil, "BORDER", nil, 2)
	fc.glyph:SetPoint("CENTER")
	fc.glyph:SetSize(20, 20)
	fc.glyph:SetAlpha(GLYPH_ALPHA)

	-- The rim. The pushed texture is the same picture: the held look is drawn by ApplyPress, the
	-- same way for a key and for the mouse.
	frame:SetNormalTexture(ART .. shape .. "-Border")
	frame:SetPushedTexture(ART .. shape .. "-Border")
	frame:SetHighlightTexture(ART .. shape .. "-Highlight", "ADD")

	-- Darkens the inside of a held button; invisible otherwise.
	fc.pressShade = frame:CreateTexture(nil, "ARTWORK", nil, 1)
	fc.pressShade:SetAllPoints()
	fc.pressShade:SetTexture(ART .. shape .. "-Pushed")

	fc.pressParts = {
		{ texture = fc.base, crop = 0 },
		{ texture = fc.icon, crop = (round or ownIcon) and 0 or ICON_CROP },
		{ texture = fc.glyph, crop = 0 },
		{ texture = frame:GetNormalTexture(), crop = 0 },
		{ texture = frame:GetPushedTexture(), crop = 0 },
		{ texture = fc.pressShade, crop = 0 },
	}
	ApplyPress(frame, 0) -- the resting state, which is also what crops the icon
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
	button:SetCheckedTexture(ART .. fc.shape .. "-Checked")

	-- A ring for an equipped item, in the colour of its rarity (UpdateRing). Shown by alpha.
	fc.equipped = button:CreateTexture(nil, "ARTWORK", nil, 2)
	fc.equipped:SetAllPoints()
	fc.equipped:SetTexture(ART .. fc.shape .. "-Highlight")
	fc.equipped:SetAlpha(0)

	fc.pressParts[#fc.pressParts + 1] = { texture = button:GetCheckedTexture(), crop = 0 }
	fc.pressParts[#fc.pressParts + 1] = { texture = fc.equipped, crop = 0 }

	fc.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	fc.cooldown:SetAllPoints(fc.icon)
	fc.cooldown:SetDrawEdge(false)
	fc.cooldown:SetDrawBling(false)
	fc.cooldown:SetSwipeColor(0, 0, 0, 0.72)
	fc.cooldown:SetMinimumCountdownDuration(MIN_COUNTDOWN)
	fc.cooldown:SetSwipeTexture(fc.maskFile)
	if round then
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

	-- The glow of a proc (UpdateGlow), spilling past the rim. It is added to what is under it.
	fc.proc = fc.overlay:CreateTexture(nil, "BORDER")
	fc.proc:SetTexture(ART .. fc.shape .. "-Proc")
	fc.proc:SetPoint("CENTER")
	fc.proc:SetSize(PROC_SIZE, PROC_SIZE)
	fc.proc:SetBlendMode("ADD")
	fc.proc:SetAlpha(0)
	fc.procPulse = fc.proc:CreateAnimationGroup()
	fc.procPulse:SetLooping("BOUNCE")
	local fade = fc.procPulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.4)
	fade:SetDuration(0.5)
	fade:SetSmoothing("IN_OUT")

	-- Anchored to the overlay, not the button, so showing it never touches a protected frame.
	fc.badge = fc.overlay:CreateTexture(nil, "OVERLAY")
	fc.badge:SetSize(15, 15)
	fc.badge:SetPoint("CENTER", fc.overlay, "TOPRIGHT", -4, -4)
	fc.badge:Hide()

	-- HookScript keeps the flyout template's own handlers (they track hover and press for its arrow).
	button:HookScript("OnEnter", ShowTooltip)
	button:HookScript("OnLeave", HideTooltip)
	button:HookScript("OnDragStart", OnDragStart)
	button:HookScript("OnDragStart", OnMouseUp) -- a drag carries the action away: the button is no longer held
	button:HookScript("OnMouseDown", OnMouseDown)
	button:HookScript("OnMouseUp", OnMouseUp)
	button:SetScript("OnReceiveDrag", OnReceiveDrag)
	button:SetScript("PostClick", function(self)
		UpdateState(self)
		NoteUse(self)
	end)
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
	-- Like Blizzard's own controller buttons (GamepadActionBarStandardButtonMixin:OnLoad), the key
	-- always acts on the press, whatever the player's "cast on key down" setting says: a pad
	-- button that waits for the release feels late.
	proxy:SetAttribute("useOnKeyDown", true)
	proxy:RegisterForClicks("AnyDown", "AnyUp")
	proxy:SetScript("PostClick", function(_, _, down)
		Press(button, "keyDown", down)
		if down then
			NoteUse(button)
		else
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
		if command == Layout.CURSOR_COMMAND then
			GameTooltip:AddLine(("Press it to bring the mouse pointer out, and again to put it away. The right stick moves the pointer; %s."):format(ns.Mouse:DescribeClicks()), 0.8, 0.8, 0.8, true)
		end
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
	-- Its icon is a ring that reaches the edge of the picture: trimmed, the ring would be cut.
	AddArt(widget, widget.fc.round, true)
	-- A bright ring while what the button switches is on: the mouse pointer being out.
	local lit = widget:CreateTexture(nil, "ARTWORK", nil, 2)
	lit:SetAllPoints()
	lit:SetTexture(ART .. widget.fc.shape .. "-Checked")
	lit:SetAlpha(0)
	widget.fc.lit = lit
	widget.fc.pressParts[#widget.fc.pressParts + 1] = { texture = lit, crop = 0 }
	widget:SetScript("OnMouseDown", OnMouseDown)
	widget:SetScript("OnMouseUp", OnMouseUp)
	widget:SetScript("OnEnter", RoleTooltip)
	widget:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	widget:SetScript("OnClick", function(self)
		ns.Options:OpenRoleMenu(self, index)
	end)
	return widget
end

local mouseLit = false -- the controller's mouse pointer is out

local function UpdateRoleWidget(widget)
	local fc = widget.fc
	local kind, command = Layout.ParseRole(ns.db.roles[fc.index])
	if kind == "cmd" then
		local _, art = Layout.GetCommandInfo(command)
		fc.icon:SetTexture(ART .. art)
	end
	ShowIcon(fc, kind == "cmd")
	fc.lit:SetAlpha(mouseLit and kind == "cmd" and command == Layout.CURSOR_COMMAND and 1 or 0)
end

-- Called by Mouse.lua (in combat too) when the mouse pointer comes out or goes away. Alpha only.
function Buttons:SetMouseLit(out)
	mouseLit = out
	for _, widget in pairs(self.role) do
		UpdateRoleWidget(widget)
	end
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

-- Out of combat. Hands the secure header (Bindings.lua) everything it needs to point each button
-- at its slot, has it do so, and shows the right widget for each position. From then on the
-- header moves the buttons by itself whenever the page or the stance changes, fight or no fight.
function Buttons:Assign()
	Layout.Prepare()
	local header = ns.Bindings.header
	local groups = Layout.GetStanceGroups()
	local pages = Layout.GetPageCount()
	for _, set in ipairs(Layout.SETS) do
		for index = 1, 8 do
			local button, proxy = self.action[set][index], self.proxy[set][index]
			local id = set .. "-" .. index
			local isSlot = self:IsActionSlot(set, index)
			local group = isSlot and Layout.FindStanceGroup(groups, set, index) or nil
			for page = 1, Layout.NUM_PAGES do
				header:SetAttribute(("fc-slot-%d-%s"):format(page, id), isSlot and page <= pages and Layout.GetSlot(set, index, page) or nil)
			end
			header:SetAttribute("fc-store-" .. id, group and group.store or nil)
			header:SetAttribute("fc-offset-" .. id, group and group.offset + index - 1 or nil)
			button.fc.group = group
			button:SetShown(isSlot)
			proxy:SetShown(isSlot)
			if set == Layout.SET_NONE then
				local widget = self.role[index]
				widget:SetShown(not isSlot)
				UpdateRoleWidget(widget)
			end
		end
	end
	for stance = 1, Layout.NUM_STANCES do
		header:SetAttribute("fc-pad-" .. stance, Layout.GetStanceFirst("pad", stance))
		header:SetAttribute("fc-bar-" .. stance, Layout.GetStanceFirst("bar", stance))
	end
	header:SetAttribute("fc-pages", pages)
	header:SetAttribute("fc-page", Layout.GetPage())
	header:SetAttribute("fc-stance-page", Layout.GetStancePage())
	UpdateKept()
	-- The driver tells the header which stance bar is up, at once and from then on. With nothing
	-- set to change there is nothing for it to do: no button has stance slots to go to.
	if #groups > 0 then
		RegisterStateDriver(header, "fc-stance", Layout.GetStanceCondition())
	else
		UnregisterStateDriver(header, "fc-stance")
	end
	header:Execute([[ self:RunAttribute("fc-assign") ]])

	-- The pictures follow the "action" attribute as it changes; this draws each one afresh for
	-- what did not change it (another controller style, a setting), and empties the hidden ones.
	for _, button in ipairs(all) do
		SetSlot(button, button:IsShown() and tonumber(button:GetAttribute("action")) or nil)
	end
	self:UpdateGlyphs()
	watchRoleKeys = IsKeyDown ~= nil
	if watchRoleKeys then
		animator:Show()
	end
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
	end
	-- The keys now point at another set, so a release may never reach a button that was being
	-- held; do not leave it looking pressed.
	for frame in pairs(pressed) do
		Press(frame, "keyDown", false)
	end
end

-- Out of combat. Used when the bars are switched off: stops the stance driver and stops asking
-- the client for range updates. Assign puts both back.
function Buttons:Release()
	watchRoleKeys = false
	for frame in pairs(pressed) do
		frame.fc.mouseDown = nil
		Press(frame, "keyDown", false)
	end
	UnregisterStateDriver(ns.Bindings.header, "fc-stance")
	for _, button in ipairs(all) do
		SetRangeSlot(button, nil)
	end
end

function Buttons:GetSlot(set, index)
	local button = self.action[set] and self.action[set][index]
	return button and button.fc.slot
end

-- For /fc status: the names of the buttons that are glowing, or "nothing".
function Buttons:DescribeGlows()
	local names = {}
	for _, button in ipairs(all) do
		if button.fc.glowing then
			names[#names + 1] = Layout.GetButtonName(button.fc.set, button.fc.index)
		end
	end
	return #names > 0 and table.concat(names, ", ") or "nothing"
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
			NoteFormSpell(button)
		end
	end
	KeptMayHaveChanged()
end)

-- A form was learned, or the spell book changed under a slot; at login the game lists the
-- character's forms a little after the bar has been set up.
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_SHAPESHIFT_FORMS", "SPELLS_CHANGED" }) do
	ns.On(event, KeptMayHaveChanged)
end

-- The last two are raised when the spell book changes: learning a new rank can change what a slot
-- holds without the slot itself being announced.
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_SHAPESHIFT_FORM", "SPELL_UPDATE_ICON", "PLAYER_EQUIPMENT_CHANGED",
	"SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE" }) do
	ns.On(event, UpdateAll)
end

-- The game announces a cooldown that starts, ends early or is reset with one or more of these,
-- depending on whether it belongs to the action bar as a whole, to one spell or to an item.
-- Every one of them redraws every filled slot; nothing is polled.
for _, event in ipairs({ "ACTIONBAR_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN" }) do
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

-- A proc has begun or ended. The event names one spell; every button is asked again, which is
-- cheap and does not depend on the event naming the same rank of the spell as the slot holds.
for _, event in ipairs({ "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" }) do
	ns.On(event, function() ForEachWithAction(UpdateGlow) end)
end

-- The game has loaded an item it could not describe before; a ring may be waiting for it.
ns.On("GET_ITEM_INFO_RECEIVED", function(_, item)
	for _, button in ipairs(all) do
		if button.fc.ringPending == item then
			UpdateRing(button)
		end
	end
end)
