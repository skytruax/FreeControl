-- Runs in the simulator after login, just before the screenshot is taken (tools/sim/run.sh).
-- Fills some slots and holds the right trigger so the picture shows a set in use.
-- The simulator ships no Blizzard art, so spell icons come out blank; the frames are ours.
local SPELLS = { 19740, 635, 21084, 20271, 498, 1022, 633, 853 }
local slots = { 37, 39, 40, 61, 62, 63, 64, 66, 67, 68, 50, 52, 53, 54, 55, 56, 25, 26, 29, 30, 32 }
for i, slot in ipairs(slots) do
	A_Admin.SetActionSlot(slot, SPELLS[(i - 1) % #SPELLS + 1])
end
A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", 0)

-- Out of combat, ordinary code may set the trigger flag and ask the header to apply it.
FreeControlHeader:SetAttribute("fc-r", 1)
FreeControlHeader:Execute([[ self:RunAttribute("fc-apply") ]])
