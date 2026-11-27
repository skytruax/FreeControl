local ADDON, ns = ...

-- A layout of its own for each talent group
--
-- A character has two talent groups (specs) and switches between them. The game keeps what is on
-- its regular action bars apart for each, but the controller's slots, where FreeControl keeps
-- nearly everything, are the same in both: after a switch the bar showed the other spec's
-- buttons, bar the few that happen to live on a regular bar. So FreeControl does it:
--
--   the jobs    which button is a slot and which has a job, page by page: Core.lua gives each
--               talent group its own tables for these (SelectBarProfile)
--   the slots   what is in every slot FreeControl uses, written down here for the talent group
--               that is active whenever a slot changes, and put back when the group becomes
--               active again
--
-- A talent group that is active for the first time starts as a copy of what was there, and is
-- its own from then on, like another character.
--
-- Slots can only be filled outside combat and through the cursor, as a hand would. A spell, an
-- item and a macro can be picked up that way; a slot holding anything else is left as it is.
local Specs = {}
ns.Specs = Specs

local Layout = ns.Layout

local SETTLE = 1      -- seconds a change is left to settle before the slots are written down
local AFTER_SWITCH = 0.5 -- seconds the game is given to finish its own part of a switch

local generation = 0  -- goes up at every switch: a write that was waiting from before is dropped
local waiting = false -- a write is due
local restoring = false

function Specs:IsEnabled()
	return ns.db.specLayouts and ns.activeSpecGroup ~= nil and Layout.GetSlotSource() == "gamepad"
end

local function Records()
	local db = ns.db
	if type(db.specSlots) ~= "table" then
		db.specSlots = {}
	end
	return db.specSlots
end

-- What a slot holds: false for nothing, { kind, id } for something that can be put back,
-- "keep" for something that cannot, and nil when the game will not say just now.
local function Read(slot)
	local kind, id = GetActionInfo(slot)
	if kind == nil then
		return false
	elseif ns.IsSealed(kind) or ns.IsSealed(id) then
		return nil
	elseif kind == "macro" then
		-- The number the game gives for a macro is not always the macro's own: its name is.
		local name = C_ActionBar.GetActionText and C_ActionBar.GetActionText(slot)
		if type(name) == "string" and not ns.IsSealed(name) and name ~= "" then
			return { "macro", name }
		end
		return "keep"
	elseif (kind == "spell" or kind == "item") and type(id) == "number" then
		return { kind, id }
	end
	return "keep"
end

local function Same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	return a[1] == b[1] and a[2] == b[2]
end

-- Out of combat. Writes down what every slot holds, for the talent group that is active.
function Specs:Record()
	if not self:IsEnabled() or restoring or InCombatLockdown() then
		return false
	end
	local record = {}
	for _, slot in ipairs(Layout.GetSpecSlots()) do
		local held = Read(slot)
		if held == nil then
			return false -- sealed: what is written down stays as it is
		end
		record[slot] = held
	end
	Records()[ns.activeSpecGroup] = record
	return true
end

local function Pickup(held)
	local kind, id = held[1], held[2]
	if kind == "spell" then
		local pickup = C_Spell and C_Spell.PickupSpell or PickupSpell
		if pickup then pickup(id) end
	elseif kind == "item" then
		local pickup = C_Item and C_Item.PickupItem or PickupItem
		if pickup then pickup(id) end
	elseif kind == "macro" and PickupMacro then
		PickupMacro(id)
	end
	return GetCursorInfo() ~= nil
end

local function Empty(slot)
	PickupAction(slot)
	ClearCursor()
end

-- Out of combat. Makes every slot hold what was written down for the talent group that is
-- active now. Returns how many slots were changed and how many could not be filled (a spell
-- this talent group does not have, an item or a macro that is gone): those are left empty.
function Specs:Restore()
	local record = Records()[ns.activeSpecGroup]
	if type(record) ~= "table" then
		return 0, 0
	end
	local changed, missing = 0, 0
	restoring = true
	ClearCursor()
	for _, slot in ipairs(Layout.GetSpecSlots()) do
		local wanted, held = record[slot], Read(slot)
		if wanted ~= nil and wanted ~= "keep" and held ~= nil and not Same(wanted, held) then
			if wanted == false then
				Empty(slot)
			elseif Pickup(wanted) then
				PlaceAction(slot)
				ClearCursor()
			else
				ClearCursor()
				if held ~= false then Empty(slot) end
				missing = missing + 1
			end
			changed = changed + 1
		end
	end
	restoring = false
	return changed, missing
end

-- A slot changed: what the active talent group holds is written down once things are quiet.
local function RecordSoon()
	if waiting or restoring or not ns.db or not Specs:IsEnabled() then
		return
	end
	waiting = true
	local asked = generation
	C_Timer.After(SETTLE, function()
		waiting = false
		if asked == generation then
			ns.RunOutOfCombat("spec-record", function() Specs:Record() end)
		end
	end)
end

-- Called by Core.lua when another talent group has become the active one; `first` when it is
-- the first one seen this session, which is a login and no switch.
function Specs:OnGroupChanged(first)
	generation = generation + 1
	waiting = false
	if first or not self:IsEnabled() then
		return
	end
	local asked = generation
	C_Timer.After(AFTER_SWITCH, function()
		if asked ~= generation then
			return
		end
		ns.RunOutOfCombat("spec-restore", function()
			if not Specs:IsEnabled() then
				return
			end
			if type(Records()[ns.activeSpecGroup]) ~= "table" then
				-- Active for the first time: it starts as a copy of what is there.
				if Specs:Record() then
					ns.Print(("Talent group %d has its own layout from now on. It starts as a copy of the one you had: change it freely, the other talent group keeps its own."):format(ns.activeSpecGroup))
				end
				return
			end
			local changed, missing = Specs:Restore()
			Specs:Record()
			if missing > 0 then
				ns.Print(("Talent group %d: %d of its buttons could not be filled again (a spell this talent group does not have, or an item or macro that is gone) and are empty."):format(ns.activeSpecGroup, missing))
			end
			if changed > 0 then
				ns.Refresh()
			end
		end)
	end)
end

ns.On("ACTIONBAR_SLOT_CHANGED", RecordSoon)
ns.On("PLAYER_ENTERING_WORLD", RecordSoon)
ns.On("PLAYER_LOGOUT", function()
	if ns.db and not InCombatLockdown() then
		Specs:Record()
	end
end)
