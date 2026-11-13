-- FreeControl against Blizzard's real Forever interface code, in the wow-ui-sim simulator.
-- Run with tools/sim/run.sh (it copies this folder into a scratch copy of the addon).
--
-- Unlike tools/tests, nothing here is a model written by us: the secure templates, the restricted
-- environment, the state drivers and the settings panel are Blizzard's own Lua. What IS emulated
-- is input: the simulator cannot press keys, so SimInput looks the key up in the override
-- bindings and clicks the bound button from a secure call stack (press, then release).
--
-- The simulator has no IsValidGamepadActionStorageSlotIndex, so FreeControl falls back to the
-- regular action bar slots here: no-trigger 37-44, LT 61-68, RT 49-56, LT+RT 25-32.
local ns = FreeControl
local SPELL = 19740 -- Blessing of Might: the simulator's character is a Paladin

-- Every protected call the client refused while a test ran.
local refused = {}
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_ACTION_BLOCKED")
watcher:RegisterEvent("ADDON_ACTION_FORBIDDEN")
watcher:SetScript("OnEvent", function(_, event, addon, what)
	refused[#refused + 1] = event .. ": " .. tostring(addon) .. " " .. tostring(what)
end)

local used = {}
hooksecurefunc("UseAction", function(slot) used[#used + 1] = tonumber(slot) end)

local function Reset()
	if InCombatLockdown() then -- a failed test must not leave the next one in combat
		A_Admin.SetInCombat(false)
	end
	wipe(refused)
	wipe(used)
end

local function NothingRefused()
	assertEquals("", table.concat(refused, " | "))
end

local function Bound(key)
	return GetBindingAction(key, true)
end

local function Near(expected, actual)
	assertAlmostEquals(expected, actual, 0.001)
end

test("the bar is built on Blizzard's templates and the secure click handler survived", function()
	assertTrue(ns.IsActive())
	assertTrue(ns.IsBuilt())
	assertTrue(FreeControlBar:IsShown())
	assertFalse(ns.Buttons:IsSecureClickMissing())
	for _, name in ipairs({ "FreeControlButton0_1", "FreeControlButton1_5", "FreeControlKey2_3", "FreeControlKey3_8" }) do
		local frame = _G[name]
		assertNotNil(frame)
		assertEquals(SecureActionButton_OnClick, frame:GetScript("OnClick"))
		local protected, explicit = frame:IsProtected()
		assertTrue(protected)
		assertTrue(explicit)
		assertEquals("action", frame:GetAttribute("type"))
	end
	for set = 0, 3 do
		local _, explicit = _G["FreeControlSet" .. set]:IsProtected()
		assertTrue(explicit) -- or the secure code could not resize it in combat
	end
	assertEquals("bars", ns.Layout.GetSlotSource())
	assertEquals(61, FreeControlButton1_1:GetAttribute("action"))
	assertEquals(68, FreeControlKey1_8:GetAttribute("action"))
end)

test("login bound the triggers, the D-pad slots and the three commands", function()
	assertEquals("CLICK FreeControlTrigger1:LeftButton", Bound("PADLTRIGGER"))
	assertEquals("CLICK FreeControlTrigger2:LeftButton", Bound("PADRTRIGGER"))
	assertEquals("CLICK FreeControlKey0_1:LeftButton", Bound("PADDLEFT"))
	assertEquals("CLICK FreeControlKey0_2:LeftButton", Bound("PADDUP"))
	assertEquals("CLICK FreeControlKey0_3:LeftButton", Bound("PADDRIGHT"))
	assertEquals("CLICK FreeControlKey0_4:LeftButton", Bound("PADDDOWN"))
	assertEquals("INTERACTTARGET", Bound("PAD3"))
	assertEquals("TOGGLEGAMEMENU", Bound("PAD2"))
	assertEquals("JUMP", Bound("PAD1"))
	assertEquals("", Bound("PAD4"))
	assertEquals(0, ns.Bindings:GetActiveSet())
	Near(1.2, FreeControlSet0:GetScale())
	Near(1, FreeControlSet1:GetScale())
end)

test("a key press casts the slot once, on the way down", function()
	Reset()
	A_Admin.SetActionSlot(38, SPELL)
	A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", 38)
	SetCVar("ActionButtonUseKeyDown", "1")
	local down, up = SimInput.PressKey("PADDUP")
	assertTrue(down)
	assertTrue(up)
	assertTableEquals({ 38 }, used)
	NothingRefused()
	assertEquals("NORMAL", FreeControlButton0_2:GetButtonState())
end)

test("holding a trigger moves the keys to its set and grows it; letting go puts them back", function()
	Reset()
	assertTrue((SimInput.KeyDown("PADLTRIGGER")))
	assertEquals(1, ns.Bindings:GetActiveSet())
	assertEquals("CLICK FreeControlKey1_2:LeftButton", Bound("PADDUP"))
	assertEquals("CLICK FreeControlKey1_8:LeftButton", Bound("PAD1"))
	assertEquals("CLICK FreeControlKey1_6:LeftButton", Bound("PAD4"))
	Near(1.2, FreeControlSet1:GetScale())
	Near(1, FreeControlSet0:GetScale())
	Near(ns.db.inactiveAlpha, FreeControlSet0:GetAlpha())
	assertTrue(ns.Bars.deco[1].shade:IsShown())

	SimInput.PressKey("PAD1")
	assertTableEquals({ 68 }, used)

	assertTrue((SimInput.KeyUp("PADLTRIGGER")))
	assertEquals(0, ns.Bindings:GetActiveSet())
	assertEquals("JUMP", Bound("PAD1"))
	assertEquals("", Bound("PAD4"))
	Near(1, FreeControlSet1:GetScale())
	NothingRefused()
end)

test("both triggers select the fourth set, in either release order", function()
	Reset()
	SimInput.KeyDown("PADLTRIGGER")
	SimInput.KeyDown("PADRTRIGGER")
	assertEquals(3, ns.Bindings:GetActiveSet())
	SimInput.PressKey("PAD3")
	assertTableEquals({ 29 }, used)
	SimInput.KeyUp("PADLTRIGGER")
	assertEquals(2, ns.Bindings:GetActiveSet())
	SimInput.PressKey("PADDLEFT")
	assertTableEquals({ 29, 49 }, used)
	SimInput.KeyUp("PADRTRIGGER")
	assertEquals(0, ns.Bindings:GetActiveSet())
	NothingRefused()
end)

test("in combat: sets still switch, keys still cast, and nothing of ours is refused", function()
	Reset()
	A_Admin.SetInCombat(true)
	assertTrue(InCombatLockdown())

	SimInput.KeyDown("PADRTRIGGER")
	assertEquals(2, ns.Bindings:GetActiveSet())
	assertEquals("CLICK FreeControlKey2_4:LeftButton", Bound("PADDDOWN"))
	Near(1.2, FreeControlSet2:GetScale())
	SimInput.PressKey("PADDDOWN")
	assertTableEquals({ 52 }, used)
	SimInput.KeyUp("PADRTRIGGER")
	assertEquals(0, ns.Bindings:GetActiveSet())
	assertEquals("CLICK FreeControlKey0_4:LeftButton", Bound("PADDDOWN"))
	Near(1.2, FreeControlSet0:GetScale())

	-- a setting changed mid-fight is held back, not applied half-way
	ns.db.roles[6] = "cmd:TARGETNEARESTENEMY"
	assertFalse(ns.RequestRefresh())
	assertEquals("", Bound("PAD4"))

	A_Admin.SetInCombat(false)
	assertEquals("TARGETNEARESTENEMY", Bound("PAD4"))
	ns.db.roles[6] = "pass"
	ns.RequestRefresh()
	NothingRefused()
end)

test("a key casts on the press even when the game's 'cast on key down' is off", function()
	Reset()
	A_Admin.SetActionSlot(38, SPELL)
	A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", 38)
	SetCVar("ActionButtonUseKeyDown", "0")
	assertTrue((SimInput.KeyDown("PADDUP")))
	assertTableEquals({ 38 }, used) -- Blizzard's own click handler ran it on the way down
	SimInput.KeyUp("PADDUP")
	assertTableEquals({ 38 }, used)
	SetCVar("ActionButtonUseKeyDown", "1")
	NothingRefused()
end)

async_test("in combat a held key makes its button look pressed, then it springs back; nothing of ours is refused", function(done)
	Reset()
	A_Admin.SetActionSlot(38, SPELL)
	A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", 38)
	local fc = FreeControlButton0_2.fc
	A_Admin.SetInCombat(true)
	SimInput.KeyDown("PADDUP")
	local held = fc.pressShade:GetAlpha()
	local heldLeft = fc.base:GetTexCoord()
	SimInput.KeyUp("PADDUP")
	SimInput.AfterTicks(15, function() -- about a quarter of a second: twice the time it takes to spring back
		local rest = fc.pressShade:GetAlpha()
		local restLeft = fc.base:GetTexCoord()
		A_Admin.SetInCombat(false)
		done(function()
			Near(1, held)
			assertTrue(heldLeft < 0) -- sampled wider while held, so the art draws smaller
			Near(0, rest)
			Near(0, restLeft)
			NothingRefused()
		end)
	end)
end)

test("the buttons are handed to the client for instant cooldowns, and the numbers option works", function()
	Reset()
	-- "yes" where the client offers the call; on a client without it the bar says so instead of failing.
	local status = ns.Buttons:GetNativeStatus()
	assertTrue(status == "yes" or status == "not offered by this client", status)
	assertTrue(ns.db.cooldownNumbers)
	SlashCmdList.FREECONTROL("numbers off")
	assertFalse(ns.db.cooldownNumbers)
	SlashCmdList.FREECONTROL("numbers on")
	assertTrue(ns.db.cooldownNumbers)
	NothingRefused()
end)

test("the mouse clicks a slot on release", function()
	Reset()
	SimInput.Click(FreeControlButton1_1, "LeftButton", false)
	assertTableEquals({ 61 }, used)
	NothingRefused()
end)

test("a spell dropped on a slot lands in it and the button draws it", function()
	Reset()
	local button = FreeControlButton2_3 -- slot 51
	assertFalse(button.fc.hasAction)
	PickupSpell(SPELL)
	assertEquals("spell", (GetCursorInfo()))
	button:GetScript("OnReceiveDrag")(button)
	assertNil((GetCursorInfo()))
	assertTrue(C_ActionBar.HasAction(51))
	A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", 51)
	assertTrue(button.fc.hasAction)
	Near(1, button.fc.icon:GetAlpha())
	Near(0, button.fc.glyph:GetAlpha())
	NothingRefused()
end)

test("a slot that changes during a fight is redrawn, and nothing is refused", function()
	Reset()
	local button = FreeControlButton1_2 -- slot 62
	A_Admin.ClearActionSlot(62)
	A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", 62)
	assertFalse(button.fc.hasAction)
	A_Admin.SetInCombat(true)
	A_Admin.SetActionSlot(62, SPELL)
	A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", 62)
	assertTrue(button.fc.hasAction)
	Near(1, button.fc.icon:GetAlpha())
	A_Admin.ClearActionSlot(62)
	A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", 62)
	assertFalse(button.fc.hasAction)
	Near(0, button.fc.icon:GetAlpha())
	-- the badge of a held set appears and disappears in combat too
	A_Admin.SetActionSlot(66, SPELL)
	A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", 66)
	SimInput.KeyDown("PADLTRIGGER")
	assertTrue(FreeControlButton1_6.fc.badge:IsShown())
	SimInput.KeyUp("PADLTRIGGER")
	assertFalse(FreeControlButton1_6.fc.badge:IsShown())
	A_Admin.SetInCombat(false)
	NothingRefused()
end)

test("usable, range and cooldown events redraw the button without errors", function()
	Reset()
	local button = FreeControlButton2_3
	A_Admin.FireEvent("ACTION_USABLE_CHANGED", { { slot = 51, usable = false, noMana = true } })
	A_Admin.FireEvent("ACTION_RANGE_CHECK_UPDATE", 51, false, true)
	assertTrue(button.fc.outOfRange)
	A_Admin.FireEvent("ACTION_RANGE_CHECK_UPDATE", 51, true, true)
	assertFalse(button.fc.outOfRange)
	A_Admin.SetSpellCooldown(SPELL, 30)
	A_Admin.FireEvent("ACTIONBAR_UPDATE_COOLDOWN")
	A_Admin.FireEvent("ACTIONBAR_UPDATE_STATE")
	A_Admin.FireEvent("SPELL_UPDATE_CHARGES")
	A_Admin.FireEvent("UPDATE_SHAPESHIFT_FORM")
	A_Admin.SetSpellCooldown(SPELL, 0)
	NothingRefused()
end)

-- The simulator does not copy GameTooltip:SetText into the first line's font string, so these
-- check the lines added after the title (AddLine), which it does model.
test("tooltips work on slots and on command buttons", function()
	local button = FreeControlButton2_3 -- holds the spell dropped on it above
	button:GetScript("OnEnter")(button)
	assertEquals(button, GameTooltip:GetOwner())
	assertEquals("Blessing of Might", GameTooltipTextLeft1:GetText())
	assertEquals("RT + D-pad Right", _G["GameTooltipTextLeft" .. GameTooltip:NumLines()]:GetText())
	button:GetScript("OnLeave")(button)
	assertNil(GameTooltip:GetOwner())

	local empty = FreeControlButton3_7
	assertFalse(empty.fc.hasAction)
	empty:GetScript("OnEnter")(empty)
	assertEquals(empty, GameTooltip:GetOwner())
	assertEquals(2, GameTooltip:NumLines())
	assertEquals("Empty. Drop a spell, item or macro here.", GameTooltipTextLeft2:GetText())
	empty:GetScript("OnLeave")(empty)

	local role = ns.Buttons.role[8]
	role:GetScript("OnEnter")(role)
	assertEquals("Jump", GameTooltipTextLeft2:GetText())
	assertEquals("Click to change what this button does.", GameTooltipTextLeft3:GetText())
	role:GetScript("OnLeave")(role)
end)

test("a no-trigger button turned into an action slot is bound and castable", function()
	Reset()
	ns.db.roles[5] = "action"
	assertTrue(ns.RequestRefresh())
	assertEquals("CLICK FreeControlKey0_5:LeftButton", Bound("PAD3"))
	assertTrue(FreeControlButton0_5:IsShown())
	assertFalse(ns.Buttons.role[5]:IsShown())
	SimInput.PressKey("PAD3")
	assertTableEquals({ 41 }, used)
	ns.db.roles[5] = "cmd:INTERACTTARGET"
	ns.RequestRefresh()
	assertEquals("INTERACTTARGET", Bound("PAD3"))
	assertFalse(FreeControlButton0_5:IsShown())
	NothingRefused()
end)

test("with controller slots available the bar moves onto them and still casts", function()
	Reset()
	-- The simulator lacks the validity check, so stand in for it: three pages of 28 and five
	-- stance bars of 8, starting wherever the simulator says its controller slots start.
	local first = C_GamepadUI.GetFirstGamepadActionStorageSlotIndex()
	local had = C_GamepadUI.IsValidGamepadActionStorageSlotIndex
	C_GamepadUI.IsValidGamepadActionStorageSlotIndex = function(slot)
		return slot >= first and slot < first + 124
	end
	ns.db.stanceSet = "none"
	ns.db.slotSource = "gamepad"
	assertTrue(ns.RequestRefresh())
	assertEquals("gamepad", ns.Layout.GetSlotSource())
	assertEquals(first, FreeControlButton0_1:GetAttribute("action"))     -- top D-pad
	assertEquals(first + 4, FreeControlKey1_1:GetAttribute("action"))    -- left bar
	assertEquals(first + 12, FreeControlKey2_1:GetAttribute("action"))   -- right bar
	assertEquals(first + 27, FreeControlKey3_8:GetAttribute("action"))   -- bottom bar
	SimInput.KeyDown("PADLTRIGGER")
	SimInput.PressKey("PADDLEFT")
	SimInput.KeyUp("PADLTRIGGER")
	assertTableEquals({ first + 4 }, used)

	ns.db.slotSource = "bars"
	ns.db.stanceSet = "auto"
	ns.RequestRefresh()
	C_GamepadUI.IsValidGamepadActionStorageSlotIndex = had
	assertEquals(61, FreeControlKey1_1:GetAttribute("action"))
	NothingRefused()
end)

test("switching off clears every binding, hides the bar and puts console variables back", function()
	Reset()
	-- The simulator starts with the client's defaults: the left trigger stands in for Shift, the
	-- left bumper for Ctrl, and Interact only picks targets for gamepad input.
	assertEquals("none", GetCVar("GamePadEmulateShift"))
	assertEquals("PADLSHOULDER", GetCVar("GamePadEmulateCtrl"))
	assertEquals("3", GetCVar("SoftTargetInteract"))
	assertEquals(20, tonumber(GetCVar("SoftTargetInteractRange")))

	SlashCmdList.FREECONTROL("off")
	assertFalse(FreeControlBar:IsShown())
	for _, key in ipairs({ "PADLTRIGGER", "PADRTRIGGER", "PADDUP", "PAD1", "PAD3" }) do
		assertEquals("", Bound(key))
	end
	assertEquals("PADLTRIGGER", GetCVar("GamePadEmulateShift"))
	assertEquals("1", GetCVar("SoftTargetInteract"))
	assertEquals(10, tonumber(GetCVar("SoftTargetInteractRange")))
	assertNil(next(ns.db.cvarBackup))

	SlashCmdList.FREECONTROL("on")
	assertTrue(FreeControlBar:IsShown())
	assertEquals("CLICK FreeControlKey0_2:LeftButton", Bound("PADDUP"))
	assertEquals("JUMP", Bound("PAD1"))
	assertEquals("none", GetCVar("GamePadEmulateShift"))
	NothingRefused()
end)

test("the settings page opens in Blizzard's settings panel and its controls work", function()
	Reset()
	ns.Options:Open()
	local panel = ns.Options.panel
	assertTrue(panel.built)
	assertTrue(panel:IsShown())
	ns.db.scale = 1.25
	ns.Options:Sync()
	ns.db.scale = 1
	ns.RequestRefresh()
	ns.Options:OpenRoleMenu(ns.Buttons.role[6], 6)
	HideUIPanel(SettingsPanel)
	NothingRefused()
end)

test("slash commands and the status report run clean", function()
	Reset()
	for _, command in ipairs({ "status", "unlock", "lock", "scale 1.1", "reset", "page 2", "page 1", "help" }) do
		SlashCmdList.FREECONTROL(command)
	end
	Near(1, FreeControlBar:GetScale())
	NothingRefused()
end)

test("the bar can be dragged while unlocked, and the handle hides in combat", function()
	Reset()
	SlashCmdList.FREECONTROL("unlock")
	local mover = ns.Bars.mover
	assertTrue(mover:IsShown())
	mover:GetScript("OnDragStart")(mover)
	mover:GetScript("OnUpdate")(mover, 0.016)
	mover:GetScript("OnDragStop")(mover)
	assertEquals("number", type(ns.db.point[1]))
	assertEquals("number", type(ns.db.point[2]))
	-- combat starting mid-drag ends the drag and hides the handle
	mover:GetScript("OnDragStart")(mover)
	A_Admin.SetInCombat(true)
	assertFalse(mover:IsShown())
	assertFalse(ns.Bars.moving)
	A_Admin.SetInCombat(false)
	assertTrue(mover:IsShown())
	SlashCmdList.FREECONTROL("lock")
	assertFalse(mover:IsShown())
	SlashCmdList.FREECONTROL("reset")
	NothingRefused()
end)

async_test("the stance driver is accepted by Blizzard's state driver and keeps the plain slot out of stance", function(done)
	Reset()
	ns.db.stanceSet = "lt"
	ns.db.slotSource = "gamepad"
	local first = C_GamepadUI.GetFirstGamepadActionStorageSlotIndex()
	local had = C_GamepadUI.IsValidGamepadActionStorageSlotIndex
	C_GamepadUI.IsValidGamepadActionStorageSlotIndex = function(slot)
		return slot >= first and slot < first + 124
	end
	ns.RequestRefresh()
	SimInput.AfterTicks(20, function() -- the driver manager evaluates on a timer
		local visible, key = FreeControlButton1_3:GetAttribute("action"), FreeControlKey1_3:GetAttribute("action")
		local shown = ns.Buttons:GetSlot(1, 3)
		ns.db.stanceSet = "auto"
		ns.db.slotSource = "bars"
		ns.RequestRefresh()
		C_GamepadUI.IsValidGamepadActionStorageSlotIndex = had
		done(function()
			assertEquals(first + 6, tonumber(visible))
			assertEquals(first + 6, tonumber(key))
			assertEquals(first + 6, shown)
			assertEquals(63, FreeControlKey1_3:GetAttribute("action"))
			NothingRefused()
		end)
	end)
end)
