local _, ns = ...
local Layout = ns.Layout

-- The frames the buttons live in: one bar, four sets, plus the decoration around each set
-- (a faint shade, trigger labels) and the handle for dragging the bar.
--
-- The sets are protected frames, because they hold protected buttons. In combat only the secure
-- code in Bindings.lua may resize them; everything in here that runs in combat touches the
-- unprotected decoration frames only.
local Bars = {}
ns.Bars = Bars

Bars.sets = {} -- [set] = protected frame holding that set's buttons
Bars.deco = {} -- [set] = unprotected frame behind it: shade and trigger label
Bars.pageButtons = {} -- [1] = next page, [-1] = previous page: secure buttons, see Bindings.lua

local ART = ns.ART
local LABEL_SIZE = { 34, 17 }
local activeSet = 0

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function CreateLabel(deco, x)
	local label = deco:CreateTexture(nil, "ARTWORK")
	label:SetSize(unpack(LABEL_SIZE))
	label:SetPoint("CENTER", deco, "CENTER", Layout.LABEL_OFFSET[1] + x, Layout.LABEL_OFFSET[2])
	return label
end

local function CreateDecoration(root, anchor, set)
	local deco = CreateFrame("Frame", nil, root)
	deco:SetSize(unpack(Layout.SET_SIZE))
	deco:SetPoint("CENTER", anchor, "CENTER")
	deco:SetFrameLevel(root:GetFrameLevel() + 1)

	-- A dark, almost transparent patch behind the held set: enough to lift it off a busy
	-- background, not enough to draw the eye.
	deco.shade = deco:CreateTexture(nil, "BACKGROUND")
	deco.shade:SetTexture(ART .. "Set-Shade")
	deco.shade:SetPoint("TOPLEFT", -44, 34)
	deco.shade:SetPoint("BOTTOMRIGHT", 44, -34)
	deco.shade:Hide()

	deco.labels = {}
	if set == Layout.SET_LT then
		deco.labels[1] = { texture = CreateLabel(deco, 0), side = 1 }
	elseif set == Layout.SET_RT then
		deco.labels[1] = { texture = CreateLabel(deco, 0), side = 2 }
	elseif set == Layout.SET_BOTH then
		deco.labels[1] = { texture = CreateLabel(deco, -23), side = 1 }
		deco.labels[2] = { texture = CreateLabel(deco, 23), side = 2 }
		deco.plus = deco:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		deco.plus:SetPoint("CENTER", deco, "CENTER", Layout.LABEL_OFFSET[1], Layout.LABEL_OFFSET[2])
		deco.plus:SetText("+")
	end
	return deco
end

-- The handle for dragging the bar. It is a frame of its own, placed over the bar but not attached
-- to it: the bar is protected, and anything anchored to a protected frame is best left alone in
-- combat. The handle is what moves; the bar is put where the handle is.
local function CreateMover(bars)
	local mover = CreateFrame("Frame", nil, UIParent)
	mover:SetFrameStrata("HIGH")
	mover:SetMovable(true)
	mover:SetClampedToScreen(true)
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	mover:Hide()

	local fill = mover:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(0.1, 0.45, 0.9, 0.3)

	local text = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetPoint("TOP", 0, -6)
	text:SetText("FreeControl: drag to move, then /fc lock")

	mover:SetScript("OnDragStart", function(self)
		bars.moving = true
		self:StartMoving()
	end)
	mover:SetScript("OnDragStop", function()
		bars:StopMoving()
	end)
	-- The bar follows the handle while it is dragged.
	mover:SetScript("OnUpdate", function()
		if bars.moving then
			bars:FollowMover()
		end
	end)
	return mover
end

---------------------------------------------------------------------------
-- The pager
---------------------------------------------------------------------------
-- In the gap in the middle of the bar: an arrow down, the number of the page being shown, an
-- arrow up. The arrows are secure buttons, so that a click (the mouse, the stick pointer, or a
-- button bound to one of them) can change the page in a fight; what a click does is set up in
-- Bindings.lua. The number sits on a frame of its own that nothing protected hangs on, because
-- it changes in a fight too.
local PAGER_SIZE, PAGER_STEP = Layout.PAGER_SIZE, Layout.PAGER_STEP

local function PageTooltip(button)
	local step = button.fc.step
	GameTooltip_SetDefaultAnchor(GameTooltip, button)
	GameTooltip:SetText(step > 0 and "Next page" or "Previous page", 0.37, 0.84, 1)
	GameTooltip:AddLine(("Page %d of %d is showing. Each page has its own buttons."):format(Layout.GetPage(), Layout.GetPageCount()), 1, 1, 1, true)
	local key = GetBindingKey(ns.Bindings.PAGE_COMMANDS[step > 0 and "next" or "prev"])
	if key then
		GameTooltip:AddLine(("%s does this."):format(Layout.GetKeyName(key)), 0.6, 0.6, 0.6, true)
	else
		GameTooltip:AddLine("No button does this yet: give it one under Other buttons in the settings (/fc).", 0.6, 0.6, 0.6, true)
	end
	GameTooltip:Show()
end

local function CreatePageButton(root, step)
	local name = step > 0 and "Next" or "Prev"
	local button = CreateFrame("Button", "FreeControlPage" .. name, root, "SecureHandlerClickTemplate")
	button:SetSize(PAGER_SIZE, PAGER_SIZE)
	button:SetPoint("CENTER", root, "CENTER", step * PAGER_STEP, 0)
	button:SetFrameLevel(root:GetFrameLevel() + 3)
	button:SetNormalTexture(ART .. "Page-" .. name)
	button:SetPushedTexture(ART .. "Page-" .. name .. "-Pushed")
	button:SetHighlightTexture(ART .. "Round-Highlight", "ADD")
	button.fc = { step = step }
	button:SetScript("OnEnter", PageTooltip)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return button
end

local function CreatePager(root)
	local pager = CreateFrame("Frame", nil, root)
	pager:SetSize(PAGER_SIZE, PAGER_SIZE)
	pager:SetPoint("CENTER", root, "CENTER")
	pager:SetFrameLevel(root:GetFrameLevel() + 3)
	pager.number = pager:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	pager.number:SetPoint("CENTER")
	return pager
end

-- Called (in combat too) when another page is shown. Text only.
function Bars:OnPageChanged(page)
	self.pager.number:SetText(tostring(page))
end

-- Out of combat.
function Bars:Create()
	local root = CreateFrame("Frame", "FreeControlBar", UIParent, "SecureFrameTemplate")
	root:SetSize(unpack(Layout.ROOT_SIZE))
	root:Hide()
	self.root = root

	for _, set in ipairs(Layout.SETS) do
		-- A 1x1 anchor at the centre of the set. The set is pinned to it with no offset, so secure
		-- code can change the set's scale without it sliding (anchor offsets scale with a frame).
		local anchor = CreateFrame("Frame", nil, root)
		anchor:SetSize(1, 1)
		anchor:SetPoint("CENTER", root, "CENTER", unpack(Layout.SET_OFFSET[set]))

		self.deco[set] = CreateDecoration(root, anchor, set)

		local frame = CreateFrame("Frame", "FreeControlSet" .. set, root, "SecureFrameTemplate")
		frame:SetSize(unpack(Layout.SET_SIZE))
		frame:SetPoint("CENTER", anchor, "CENTER")
		frame:SetFrameLevel(root:GetFrameLevel() + 2)
		self.sets[set] = frame
	end

	self.pager = CreatePager(root)
	self.pageButtons[1] = CreatePageButton(root, 1)
	self.pageButtons[-1] = CreatePageButton(root, -1)

	self.mover = CreateMover(self)
end

---------------------------------------------------------------------------
-- Position
---------------------------------------------------------------------------
-- The saved position is the bar's centre in screen units, so changing the scale grows the bar
-- around that point instead of sliding it. Anchor offsets are in the frame's own (scaled) units,
-- hence the division.
local function Place(root)
	local db = ns.db
	root:SetScale(db.scale)
	root:ClearAllPoints()
	root:SetPoint("CENTER", UIParent, "BOTTOM", db.point[1] / db.scale, db.point[2] / db.scale)
end

-- The handle is unscaled, so its size and offsets are plain screen units.
local function PlaceMover(mover)
	local db = ns.db
	mover:SetSize(Layout.ROOT_SIZE[1] * db.scale, Layout.ROOT_SIZE[2] * db.scale)
	mover:ClearAllPoints()
	mover:SetPoint("CENTER", UIParent, "BOTTOM", db.point[1], db.point[2])
end

-- Saves where the handle is and, out of combat, puts the bar there. In combat the bar catches up
-- when the fight ends.
function Bars:FollowMover()
	local x, y = self.mover:GetCenter() -- measured from the bottom-left of the screen
	ns.db.point[1] = x - UIParent:GetWidth() / 2
	ns.db.point[2] = y
	ns.RunOutOfCombat("place", function()
		Place(self.root)
	end)
end

function Bars:StopMoving()
	if not self.moving then
		return
	end
	self.moving = false
	self.mover:StopMovingOrSizing()
	self:FollowMover()
	PlaceMover(self.mover)
end

function Bars:UpdateMover()
	local show = not ns.db.locked and ns.IsActive() and not InCombatLockdown()
	if show then
		PlaceMover(self.mover)
	end
	self.mover:SetShown(show)
end

---------------------------------------------------------------------------
-- Appearance
---------------------------------------------------------------------------
-- Runs in combat too (called from the secure code when the held triggers change), so it only
-- touches the decoration frames and textures.
function Bars:OnSetChanged(set)
	activeSet = set
	local db = ns.db
	for _, id in ipairs(Layout.SETS) do
		local deco = self.deco[id]
		local active = id == set
		deco:SetScale(active and db.activeScale or 1)
		deco:SetAlpha(active and 1 or db.inactiveAlpha)
		deco.shade:SetShown(active)
	end
	ns.Buttons:OnSetChanged(set)
end

-- Trigger labels follow the controller style (LT / L2 / ZL ...).
function Bars:UpdateLabels()
	for _, id in ipairs(Layout.SETS) do
		for _, label in ipairs(self.deco[id].labels) do
			label.texture:SetTexture(ART .. Layout.GetTriggerBadge(label.side))
		end
	end
end

---------------------------------------------------------------------------
-- Module interface
---------------------------------------------------------------------------
-- Out of combat.
function Bars:Apply()
	Place(self.root)
	self.root:Show()
	self:UpdateLabels()
	self:OnSetChanged(activeSet)
	self:UpdateMover()
	-- Nothing to turn with the regular action bars as the slots: they have one page.
	local paged = Layout.GetPageCount() > 1
	self.pager:SetShown(paged)
	for _, button in pairs(self.pageButtons) do
		button:SetShown(paged)
	end
end

-- Out of combat.
function Bars:Hide()
	self:StopMoving()
	self.root:Hide()
	self.mover:Hide()
end

-- A drag cannot continue into combat: the bar is protected and could not follow the handle.
ns.On("PLAYER_REGEN_DISABLED", function()
	if ns.IsBuilt() then
		Bars:StopMoving()
		Bars.mover:Hide()
	end
end)

ns.On("PLAYER_REGEN_ENABLED", function()
	if ns.IsBuilt() then
		Bars:UpdateMover()
	end
end)
