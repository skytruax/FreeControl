local _, ns = ...
local Layout = ns.Layout

-- Spell ranks.
--
-- When a character learns a new rank of a spell, the game moves the copies on its action bars up
-- to that rank. It keeps two sets of bars, one for mouse and keyboard and one for the controller,
-- and going by what players see it only looks after the set that is in use. In the normal
-- interface that is the mouse and keyboard set, so the controller's slots, which are the ones
-- FreeControl shows, stayed at whatever rank they were filled with.
--
-- This does for those slots what the game does for the others. A slot is moved up when the spell
-- in it was the newest rank the last time it was looked at and no longer is: the spell book says
-- which spells are lower ranks, and which spell of the same name is the newest. A lower rank the
-- player put on a slot themselves was never the newest there, so it is left alone.
--
-- The first time a character is seen there is no "last time": every lower rank on its slots is
-- moved up once, and chat says so, because until now nothing kept them current.
--
-- Slots can only be filled outside combat and through the cursor, like dragging the spell from
-- the spell book by hand, so this waits for the fight to end and for the cursor to be empty.
local Ranks = {}
ns.Ranks = Ranks

local failed = {}   -- [slot] = spell that could not be replaced, so it is not tried again and again
local waiting = false -- the cursor was carrying something when a check was due

function Ranks:IsAvailable()
	return C_SpellBook ~= nil and C_SpellBook.IsSpellBookItemLowRank ~= nil and C_SpellBook.PickupSpellBookItem ~= nil
		and C_SpellBook.GetSpellBookItemInfo ~= nil and C_SpellBook.GetSpellBookSkillLineInfo ~= nil
		and Enum.SpellBookSpellBank ~= nil and Enum.SpellBookItemType ~= nil
end

-- Reads the spell book. Returns
--   newest[name] = { index =, spell =, base = }  the newest rank the character knows of a spell,
--                                          where it is in the book, and the number the book
--                                          files it under when something overrides it
--   older[spell] = name                    every lower rank the character knows
-- A name carried by two different spells is left out of `newest`: there is no telling which of
-- them a lower rank belongs to.
local function ReadSpellBook()
	local bank = Enum.SpellBookSpellBank.Player
	local newest, older, twice = {}, {}, {}
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info and not info.isGuild then
			for index = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
				local item = C_SpellBook.GetSpellBookItemInfo(index, bank)
				if item and item.itemType == Enum.SpellBookItemType.Spell and not item.isPassive and not item.isOffSpec and item.name ~= "" then
					local spell = item.spellID or item.actionID
					if C_SpellBook.IsSpellBookItemLowRank(index, bank) then
						older[item.actionID] = item.name
						older[spell] = item.name
					elseif newest[item.name] and newest[item.name].spell ~= spell then
						twice[item.name] = true
					else
						newest[item.name] = { index = index, spell = spell, base = item.actionID }
					end
				end
			end
		end
	end
	for name in pairs(twice) do
		newest[name] = nil
	end
	return newest, older
end

-- Puts the spell at `entry` into the slot, the way a hand would: pick it up from the spell book,
-- drop it on the slot, and let go of the lower rank that comes away on the cursor. Returns what
-- the slot then says it holds if that is the spell, and nothing if the game did not take it.
local function Replace(slot, entry)
	C_SpellBook.PickupSpellBookItem(entry.index, Enum.SpellBookSpellBank.Player)
	if GetCursorInfo() ~= "spell" then
		ClearCursor()
		return nil
	end
	PlaceAction(slot)
	ClearCursor()
	local kind, spell = GetActionInfo(slot)
	if kind == "spell" and (spell == entry.spell or spell == entry.base) then
		return spell
	end
	return nil
end

-- The record for this character: [slot] = the spell that was in it when it was last seen holding
-- the newest rank. Nothing yet for a character that has not been looked at.
local function GetRecord()
	local character = UnitGUID("player")
	return character and ns.db.ranks[character]
end

-- Adds a name to a list once.
local function List(names, name)
	for _, listed in ipairs(names) do
		if listed == name then
			return
		end
	end
	names[#names + 1] = name
end

-- Goes through the controller's slots. With `all`, every lower rank is moved up, not only the
-- ones that were the newest before. Returns the names of the spells moved up, and of those that
-- could not be (each is tried once, then left for the player).
local function Check(all)
	local moved, stuck = {}, {}
	local first, last = Layout.GetGamepadSlotRange()
	if not first then
		return moved, stuck
	end
	local newest, older = ReadSpellBook()
	if next(newest) == nil then
		return moved, stuck -- the spell book has not been loaded yet; SPELLS_CHANGED follows when it has
	end
	local character = UnitGUID("player")
	if not character then
		return moved, stuck -- too early to say whose slots these are
	end
	local record = GetRecord()
	if not record then
		record, all = {}, true
		ns.db.ranks[character] = record
	end
	for slot = first, last do
		local kind, spell = GetActionInfo(slot)
		if kind ~= "spell" or ns.IsSealed(spell) then
			record[slot] = nil
		else
			local name = older[spell]
			local entry = name and newest[name]
			if not entry then
				record[slot] = spell -- the newest rank, or a spell that has no ranks
			elseif all or record[slot] == spell then
				local placed = failed[slot] ~= spell and Replace(slot, entry)
				if placed then
					record[slot] = placed
					List(moved, name)
				elseif failed[slot] ~= spell then
					failed[slot] = spell -- tried once; the game did not take it
					List(stuck, name)
				end
			else
				record[slot] = nil -- a lower rank the player chose
			end
		end
	end
	return moved, stuck
end

-- Returns the same two lists, or nothing when no check could be made.
local function Run(all)
	if not (ns.IsActive() and Ranks:IsAvailable()) or not (all or ns.db.keepRanks) then
		return
	end
	if GetCursorInfo() then
		waiting = true -- the player is carrying something; CURSOR_CHANGED says when they no longer are
		return
	end
	waiting = false
	local first = GetRecord() == nil
	local moved, stuck = Check(all)
	if #moved > 0 then
		ns.Print(("Moved up to the newest rank on your bar: %s."):format(table.concat(moved, ", ")))
		if first then
			ns.Print("The game does not keep the controller's slots on the newest rank outside Gamepad UI mode, so FreeControl does from now on. A lower rank you put on a slot yourself is left alone.")
		end
	end
	if #stuck > 0 then
		ns.Print(("Could not be moved up to the newest rank: %s. Drag it onto the slot from the spell book."):format(table.concat(stuck, ", ")))
	end
	return moved, stuck
end

-- A check is asked for by several events at once (learning one rank raises three of them), so it
-- is made once, on the next frame, and outside combat.
local soon = CreateFrame("Frame")
soon:Hide()
soon:SetScript("OnUpdate", function(self)
	self:Hide()
	ns.RunOutOfCombat("ranks", function()
		ns.Try(Run, false)
	end)
end)

function Ranks:CheckSoon()
	soon:Show()
end

-- /fc ranks: moves every lower rank up now, whether or not it was the newest before.
function Ranks:CheckAll()
	if not self:IsAvailable() then
		ns.Print("This client's spell book does not say which spells are lower ranks.")
		return
	end
	if InCombatLockdown() then
		ns.Print("In combat; type it again when the fight is over.")
		return
	end
	if GetCursorInfo() then
		ns.Print("Put down what is on the cursor first.")
		return
	end
	if not ns.IsActive() then
		ns.Print("FreeControl is switched off or idle, so it is not looking after any slots.")
		return
	end
	wipe(failed)
	local moved, stuck = Run(true)
	if #moved == 0 and #stuck == 0 then
		ns.Print("Every spell on the controller's slots is at its newest rank.")
	end
end

-- For /fc status: how many slots hold a lower rank right now, and which spells.
function Ranks:Describe()
	if not self:IsAvailable() then
		return "Spell ranks: this client's spell book does not say which spells are lower ranks."
	end
	local first, last = Layout.GetGamepadSlotRange()
	if not first then
		return "Spell ranks: no controller slots to look after."
	end
	local newest, older = ReadSpellBook()
	local names, listed = {}, {}
	for slot = first, last do
		local kind, spell = GetActionInfo(slot)
		local name = kind == "spell" and not ns.IsSealed(spell) and older[spell]
		if name and newest[name] and not listed[name] then
			listed[name] = true
			names[#names + 1] = name
		end
	end
	return ("Spell ranks: kept at the newest rank: %s. On a lower rank right now: %s."):format(ns.db.keepRanks and "yes" or "no",
		#names > 0 and table.concat(names, ", ") or "none")
end

for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "ACTIONBAR_SLOT_CHANGED" }) do
	ns.On(event, function()
		Ranks:CheckSoon()
	end)
end

ns.On("CURSOR_CHANGED", function()
	if waiting then
		Ranks:CheckSoon()
	end
end)
