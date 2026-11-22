-- Runs in the simulator after login, just before the screenshot is taken (tools/sim/run.sh).
-- Puts the bar on the controller's slots, as it is in the game, fills some of them and holds the
-- right trigger so the picture shows a set in use and the page arrows in the middle.
-- The simulator ships no Blizzard art, so spell icons come out blank; the frames are ours.
local ns = FreeControl

-- The simulator says where the controller's slots start but cannot say which are valid: three
-- pages of 28 and five stance bars of 8 are, as in the client.
local first = C_GamepadUI.GetFirstGamepadActionStorageSlotIndex()
C_GamepadUI.IsValidGamepadActionStorageSlotIndex = function(slot)
	return slot >= first and slot < first + 124
end
ns.db.slotSource = "gamepad"
ns.Refresh()

local SPELLS = { 19740, 635, 21084, 20271, 498, 1022, 633, 853 }
local filled = { { 0, 1 }, { 0, 3 }, { 0, 4 }, { 1, 1 }, { 1, 2 }, { 1, 3 }, { 1, 4 }, { 1, 6 }, { 1, 7 }, { 1, 8 }, { 2, 2 }, { 2, 4 },
	{ 2, 5 }, { 2, 6 }, { 2, 7 }, { 2, 8 }, { 3, 1 }, { 3, 2 }, { 3, 5 }, { 3, 6 }, { 3, 8 } }
for i, button in ipairs(filled) do
	A_Admin.SetActionSlot(ns.Buttons:GetSlot(button[1], button[2]), SPELLS[(i - 1) % #SPELLS + 1])
end
A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", 0)

-- Out of combat, ordinary code may set the trigger flag and ask the header to apply it.
FreeControlHeader:SetAttribute("fc-r", 1)
FreeControlHeader:Execute([[ self:RunAttribute("fc-apply") ]])
