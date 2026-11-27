-- Pages, stances and the Other buttons page against Blizzard's real Forever interface code.
-- Runs after 01_freecontrol.lua, in the same simulator session.
--
-- What is Blizzard's own here: the secure handler templates and the restricted environment the
-- page and stance snippets run in, the state driver that tells the bar which stance bar is up,
-- the settings panel and its menus, and the key binding functions. What is a model:
--
--   * the stance itself. The simulator has no stances or forms, so SimInput.SetStanceBar says
--     which stance bar is up, to macro conditions and to the action bar API alike (see
--     lab/image/simlib). Which bar each form of each class really brings up is the game's data,
--     and is not in the simulator: tools/tests covers the classes by the classic rules.
--   * the controller's slots. The simulator says where they start but cannot say which are
--     valid, so three pages of 28 and five stance bars of 8 are declared valid here.
local ns = FreeControl
local first = C_GamepadUI.GetFirstGamepadActionStorageSlotIndex()
local SPELL = 19740

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
	if InCombatLockdown() then
		A_Admin.SetInCombat(false)
	end
	wipe(refused)
	wipe(used)
end

local function Clean()
	assertEquals("", table.concat(refused, " | "))
	assertEquals(0, #ns.GetProblems())
end

-- Slots a set shows, and the slots its key buttons would cast: they have to be the same.
local function Slots(set)
	local out = {}
	for index = 1, 8 do
		local button, key = _G[("FreeControlButton%d_%d"):format(set, index)], _G[("FreeControlKey%d_%d"):format(set, index)]
		if button:IsShown() then
			assertEquals(tonumber(button:GetAttribute("action")), tonumber(key:GetAttribute("action")))
			assertEquals(tonumber(button:GetAttribute("action")), ns.Buttons:GetSlot(set, index))
			out[#out + 1] = tonumber(button:GetAttribute("action")) - first
		end
	end
	return table.concat(out, " ")
end

-- The same, for slots of the regular action bars (not counted from the controller's first slot).
local function BarSlots(set)
	local out = {}
	for index = 1, 8 do
		local button = _G[("FreeControlButton%d_%d"):format(set, index)]
		if button:IsShown() then
			out[#out + 1] = tonumber(button:GetAttribute("action"))
		end
	end
	return table.concat(out, " ")
end

local PAGE = {
	{ [0] = "0 1 2 3", "4 5 6 7 8 9 10 11", "12 13 14 15 16 17 18 19", "20 21 22 23 24 25 26 27" },
	{ [0] = "28 29 30 31", "32 33 34 35 36 37 38 39", "40 41 42 43 44 45 46 47", "48 49 50 51 52 53 54 55" },
	{ [0] = "56 57 58 59", "60 61 62 63 64 65 66 67", "68 69 70 71 72 73 74 75", "76 77 78 79 80 81 82 83" },
}

local function ShowsPage(page)
	for set = 0, 3 do
		assertEquals(PAGE[page][set], Slots(set))
	end
	assertEquals(page, tonumber(ns.Bars.pager.number:GetText()))
	assertEquals(page, ns.db.page)
end

-- A click on a page arrow from a secure call stack, as the mouse or a bound button makes it.
local function Turn(button)
	SimInput.Click(button, "LeftButton", true)
	SimInput.Click(button, "LeftButton", false)
end

-- The simulator's test runner runs a file's plain tests first and its async tests after them,
-- so each group puts the bar on the controller's slots itself and takes it off again.
local hadValid = C_GamepadUI.IsValidGamepadActionStorageSlotIndex

local function UseControllerSlots(stanceSet)
	C_GamepadUI.IsValidGamepadActionStorageSlotIndex = function(slot)
		return slot >= first and slot < first + 124
	end
	ns.db.slotSource, ns.db.stanceSet, ns.db.page = "gamepad", stanceSet, 1
	assertTrue(ns.RequestRefresh())
end

local function UseRegularBars()
	ns.db.slotSource, ns.db.stanceSet = "bars", "auto"
	assertTrue(ns.RequestRefresh())
	C_GamepadUI.IsValidGamepadActionStorageSlotIndex = hadValid
end

test("on the controller's slots the bar has three pages and two secure arrows", function()
	Reset()
	UseControllerSlots("none")
	assertEquals("gamepad", ns.Layout.GetSlotSource())
	assertEquals(3, ns.Layout.GetPageCount())
	for _, button in ipairs({ FreeControlPageNext, FreeControlPagePrev }) do
		local protected, explicit = button:IsProtected()
		assertTrue(protected)
		assertTrue(explicit) -- or its click could not move the buttons in a fight
		assertTrue(button:IsVisible())
	end
	ShowsPage(1)
	Clean()
end)

test("the arrows turn the page, round and round, out of a fight", function()
	Reset()
	Turn(FreeControlPageNext)
	ShowsPage(2)
	Turn(FreeControlPageNext)
	ShowsPage(3)
	Turn(FreeControlPageNext)
	ShowsPage(1)
	Turn(FreeControlPagePrev)
	ShowsPage(3)
	Turn(FreeControlPagePrev)
	Turn(FreeControlPagePrev)
	ShowsPage(1)
	Clean()
end)

test("in a fight the arrows still turn the page, and a key casts from the page on show", function()
	Reset()
	A_Admin.SetActionSlot(first + 32, SPELL) -- page 2, left set, first button
	A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", first + 32)
	A_Admin.SetInCombat(true)
	Turn(FreeControlPageNext)
	ShowsPage(2)
	SimInput.KeyDown("PADLTRIGGER")
	SimInput.PressKey("PADDLEFT")
	SimInput.KeyUp("PADLTRIGGER")
	assertTableEquals({ first + 32 }, used)
	assertNotNil(FreeControlButton1_1.fc.icon:GetTexture()) -- drawn at once, in the fight
	Turn(FreeControlPageNext)
	ShowsPage(3)
	Turn(FreeControlPageNext)
	ShowsPage(1)
	A_Admin.SetInCombat(false)
	A_Admin.ClearActionSlot(first + 32)
	Clean()
end)

test("a button the player bound to an arrow turns the page in a fight", function()
	Reset()
	assertTrue(SetBinding("PADRSHOULDER", ns.Bindings.PAGE_COMMANDS.next) and true)
	assertEquals("PADRSHOULDER", (GetBindingKey(ns.Bindings.PAGE_COMMANDS.next)))
	assertEquals("FreeControl: next page", GetBindingName(ns.Bindings.PAGE_COMMANDS.next))
	A_Admin.SetInCombat(true)
	local down = SimInput.PressKey("PADRSHOULDER")
	assertTrue(down)
	ShowsPage(2)
	SimInput.PressKey("PADRSHOULDER")
	SimInput.PressKey("PADRSHOULDER")
	ShowsPage(1)
	A_Admin.SetInCombat(false)
	SetBinding("PADRSHOULDER", nil)
	Clean()
end)

test("turned from the settings in a fight, the page waits for the fight to end", function()
	Reset()
	A_Admin.SetInCombat(true)
	SlashCmdList.FREECONTROL("page 3")
	assertEquals(PAGE[1][1], Slots(1)) -- ordinary code may not move the buttons now
	A_Admin.SetInCombat(false)
	ShowsPage(3)
	SlashCmdList.FREECONTROL("page 1")
	ShowsPage(1)
	Clean()
end)

async_test("a stance bar coming up in a fight moves the changing groups, on the stance page only, and the keys follow", function(done)
	Reset()
	UseControllerSlots("all") -- the right set, the left set and the D-pad
	local seen = {}
	A_Admin.SetInCombat(true)
	SimInput.SetStanceBar(2)
	SimInput.AfterTicks(20, function() -- Blizzard's driver looks on a timer
		seen.right, seen.left, seen.dpad, seen.both = Slots(2), BarSlots(1), BarSlots(0), Slots(3)
		SimInput.KeyDown("PADRTRIGGER")
		SimInput.PressKey("PADDLEFT")
		SimInput.KeyUp("PADRTRIGGER")
		SimInput.KeyDown("PADLTRIGGER")
		SimInput.PressKey("PAD1")
		SimInput.KeyUp("PADLTRIGGER")
		SimInput.PressKey("F8") -- the release binding installed by 01_freecontrol.lua
		SimInput.PressKey("PADDUP")
		seen.used = table.concat(used, " ")
		Turn(FreeControlPageNext)
		seen.page2 = { [0] = Slots(0), Slots(1), Slots(2), Slots(3) }
		Turn(FreeControlPagePrev)
		seen.backRight, seen.backLeft = Slots(2), BarSlots(1)
		SimInput.SetStanceBar(5)
		SimInput.AfterTicks(20, function()
			seen.fifthRight, seen.fifthLeft, seen.fifthDpad = Slots(2), BarSlots(1), BarSlots(0)
			SimInput.SetStanceBar(0)
			SimInput.AfterTicks(20, function()
				seen.out = { [0] = Slots(0), Slots(1), Slots(2), Slots(3) }
				seen.refused = table.concat(refused, " | ")
				A_Admin.SetInCombat(false)
				UseRegularBars()
				done(function()
					assertEquals("92 93 94 95 96 97 98 99", seen.right)  -- the controller's second stance bar
					assertEquals("85 86 87 88 89 90 91 92", seen.left)   -- the regular action bar's slots in that stance
					assertEquals("93 94 95 96", seen.dpad)               -- and the last four of them
					assertEquals(PAGE[1][3], seen.both)                  -- the both-triggers set never changes
					assertEquals(("%d 92 94"):format(first + 92), seen.used) -- right set, left set, D-pad: each casts what it shows
					for set = 0, 3 do
						assertEquals(PAGE[2][set], seen.page2[set])      -- page 2 is page 2 in every stance
					end
					assertEquals("92 93 94 95 96 97 98 99", seen.backRight) -- and the stance is still there on page 1
					assertEquals("85 86 87 88 89 90 91 92", seen.backLeft)
					assertEquals("116 117 118 119 120 121 122 123", seen.fifthRight) -- the fifth stance bar
					assertEquals("121 122 123 124 125 126 127 128", seen.fifthLeft)
					assertEquals("129 130 131 132", seen.fifthDpad)
					for set = 0, 3 do
						assertEquals(PAGE[1][set], seen.out[set])        -- out of every stance: the plain page
					end
					assertEquals("", seen.refused)                       -- all of it in a fight, nothing refused
					Clean()
				end)
			end)
		end)
	end)
end)

async_test("a Druid on automatic: three groups change with the form, and status agrees with the game", function(done)
	Reset()
	A_Admin.SetPlayerClass(11)
	local _, class = UnitClass("player")
	UseControllerSlots("auto")
	local described = ns.Layout.DescribeStance()
	SimInput.SetStanceBar(1) -- Cat, by the classic rules
	SimInput.AfterTicks(20, function()
		local right, left, dpad = Slots(2), BarSlots(1), BarSlots(0)
		local following = FreeControlHeader:GetAttribute("state-fc-stance")
		-- The simulator's action bar API knows no stance; for the length of the report it says
		-- what the macro condition says, as the client's would.
		local hadOffset, hadIndex = C_ActionBar.GetBonusBarOffset, C_ActionBar.GetBonusBarIndex
		C_ActionBar.GetBonusBarOffset = function() return 1 end
		C_ActionBar.GetBonusBarIndex = function() return 7 end
		SlashCmdList.FREECONTROL("status")
		C_ActionBar.GetBonusBarOffset, C_ActionBar.GetBonusBarIndex = hadOffset, hadIndex
		SimInput.SetStanceBar(0)
		SimInput.AfterTicks(20, function()
			local out = Slots(2)
			A_Admin.SetPlayerClass(2)
			UseRegularBars()
			done(function()
				assertEquals("DRUID", class)
				assertEquals("RT set, LT set and the D-pad, on page 1", described)
				assertEquals("84 85 86 87 88 89 90 91", right)
				assertEquals("73 74 75 76 77 78 79 80", left)
				assertEquals("81 82 83 84", dpad)
				assertEquals(1, tonumber(following))
				assertEquals(PAGE[1][2], out)
				Clean()
			end)
		end)
	end)
end)

async_test("a shapeshift on a button that changes with the stance stays there when the stance bar comes up", function(done)
	Reset()
	UseControllerSlots("rt")
	-- What the simulator lists as this character's first stance or form, whatever it is.
	local _, _, _, form = GetShapeshiftFormInfo(1)
	A_Admin.SetActionSlot(first + 12, form)  -- right set, first button
	A_Admin.SetActionSlot(first + 13, SPELL) -- an ordinary spell next to it
	A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", first + 12)
	A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", first + 13)
	SimInput.AfterTicks(3, function() -- what is kept is worked out a moment after the slot changed
		local kept = FreeControlHeader:GetAttribute("fc-keep-2-2-1")
		local other = FreeControlHeader:GetAttribute("fc-keep-2-2-2")
		A_Admin.SetInCombat(true)
		SimInput.SetStanceBar(2)
		SimInput.AfterTicks(20, function()
			local right = Slots(2)
			SimInput.KeyDown("PADRTRIGGER")
			SimInput.PressKey("PADDLEFT")
			SimInput.KeyUp("PADRTRIGGER")
			local pressed = table.concat(used, " ")
			local wasRefused = table.concat(refused, " | ")
			A_Admin.SetInCombat(false)
			SimInput.SetStanceBar(0)
			A_Admin.ClearActionSlot(first + 12)
			A_Admin.ClearActionSlot(first + 13)
			A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", first + 12)
			A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", first + 13)
			SimInput.AfterTicks(20, function()
				local after = FreeControlHeader:GetAttribute("fc-keep-2-2-1")
				UseRegularBars()
				done(function()
					assertNotNil(form)
					assertEquals(first + 12, kept) -- in a stance with nothing of its own there, the button shows the slot that holds the stance
					assertNil(other)               -- the ordinary spell next to it is not kept
					assertEquals("12 93 94 95 96 97 98 99", right) -- its button keeps the page slot, the rest are the stance's
					assertEquals(tostring(first + 12), pressed)    -- and the key casts it, in the fight
					assertEquals("", wasRefused)
					assertNil(after)   -- taken off the bar, it is no longer kept
					Clean()
				end)
			end)
		end)
	end)
end)

test("the Other buttons page builds in Blizzard's settings panel, and a job picked there is a real key binding", function()
	Reset()
	ns.Options:OpenButtons()
	local panel = ns.Options.buttonsPanel
	assertTrue(panel.built)
	assertTrue(panel:IsVisible())
	assertNotNil(ns.Options.catcher)
	assertEquals("", GetBindingAction("PADPADDLE1"))
	assertTrue(ns.Options.Bind("PADPADDLE1", ns.Bindings.PAGE_COMMANDS.prev))
	assertEquals(ns.Bindings.PAGE_COMMANDS.prev, GetBindingAction("PADPADDLE1"))
	SimInput.PressKey("PADPADDLE1")
	ShowsPage(3)
	assertTrue(ns.Options.Bind("PADPADDLE1", ""))
	assertEquals("", GetBindingAction("PADPADDLE1"))
	Turn(FreeControlPageNext)
	ShowsPage(1)
	-- The left bumper is the game's Ctrl key until it has a job.
	assertEquals("PADLSHOULDER", GetCVar("GamePadEmulateCtrl"))
	assertTrue(ns.Options.Bind("PADLSHOULDER", "TOGGLEWORLDMAP"))
	assertEquals("none", GetCVar("GamePadEmulateCtrl"))
	assertTrue(ns.Options.Bind("PADLSHOULDER", ""))
	assertEquals("PADLSHOULDER", GetCVar("GamePadEmulateCtrl"))
	-- The menu of jobs opens through Blizzard's menu system, and the Key Bindings screen is there.
	for _, frame in ipairs({ panel:GetChildren() }) do
		if frame.Sync and frame:IsShown() and frame.GetText and frame:GetText() == "Nothing" then
			frame:GetScript("OnClick")(frame)
			break
		end
	end
	assertEquals("number", type(Settings.KEYBINDINGS_CATEGORY_ID))
	ns.Options:OpenKeyBindings()
	HideUIPanel(SettingsPanel)
	Clean()
end)

async_test("a stance put on a button in one stance is there in the next, as for a Warrior who is always in one", function(done)
	Reset()
	UseControllerSlots("rt")
	local _, _, _, form = GetShapeshiftFormInfo(1)
	local seen = {}
	SimInput.SetStanceBar(1)
	SimInput.AfterTicks(20, function()
		seen.inFirst = Slots(2)
		A_Admin.SetActionSlot(first + 84, form) -- the first stance's own slot for the right set's first button
		A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", first + 84)
		SimInput.AfterTicks(3, function()
			seen.keptInSecond = FreeControlHeader:GetAttribute("fc-keep-2-2-1")
			seen.keptInNone = FreeControlHeader:GetAttribute("fc-keep-0-2-1")
			seen.keptInFirst = FreeControlHeader:GetAttribute("fc-keep-1-2-1")
			A_Admin.SetInCombat(true)
			SimInput.SetStanceBar(2)
			SimInput.AfterTicks(20, function()
				seen.inSecond = Slots(2)
				SimInput.KeyDown("PADRTRIGGER")
				SimInput.PressKey("PADDLEFT")
				SimInput.KeyUp("PADRTRIGGER")
				seen.pressed = table.concat(used, " ")
				seen.refused = table.concat(refused, " | ")
				A_Admin.SetInCombat(false)
				SimInput.SetStanceBar(0)
				A_Admin.ClearActionSlot(first + 84)
				A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", first + 84)
				SimInput.AfterTicks(20, function()
					UseRegularBars()
					done(function()
						assertEquals("84 85 86 87 88 89 90 91", seen.inFirst)  -- the first stance's own slots
						assertEquals(first + 84, seen.keptInSecond)            -- the second stance borrows the one that holds the stance
						assertEquals(first + 84, seen.keptInNone)              -- and so does no stance at all
						assertNil(seen.keptInFirst)                            -- the first has it as its own
						assertEquals("84 93 94 95 96 97 98 99", seen.inSecond) -- in the second stance: that button, and the second's own for the rest
						assertEquals(tostring(first + 84), seen.pressed)       -- the key casts it, in the fight
						assertEquals("", seen.refused)
						Clean()
					end)
				end)
			end)
		end)
	end)
end)

test("a no-trigger button given a stance runs the game's own command for it and wears its icon", function()
	Reset()
	local was = ns.db.roles[1]
	local texture = GetShapeshiftFormInfo(1)
	ns.db.roles[1] = "cmd:" .. ns.Layout.GetFormCommand(1)
	assertTrue(ns.RequestRefresh())
	assertEquals("SHAPESHIFTBUTTON1", GetBindingAction("PADDLEFT", true))
	local widget = ns.Buttons.role[1]
	assertTrue(widget:IsShown())
	assertNotNil(texture)
	assertNotNil(widget.fc.icon:GetTexture())
	assertEquals(1, ns.Layout.GetCommandForm("SHAPESHIFTBUTTON1"))
	assertEquals("string", type((ns.Layout.GetCommandInfo("SHAPESHIFTBUTTON1"))))
	widget:GetScript("OnEnter")(widget)
	assertTrue(GameTooltip:IsShown())
	widget:GetScript("OnLeave")(widget)
	A_Admin.FireEvent("UPDATE_SHAPESHIFT_FORM")
	A_Admin.FireEvent("UPDATE_SHAPESHIFT_USABLE")
	ns.db.roles[1] = was
	assertTrue(ns.RequestRefresh())
	assertEquals("CLICK FreeControlKey0_1:LeftButton", GetBindingAction("PADDLEFT", true))
	Clean()
end)

test("the pager is a plate under the both-triggers set, with an arrow at each end", function()
	Reset()
	UseControllerSlots("none")
	local _, _, _, x, y = ns.Bars.pager:GetPoint(1)
	assertEquals(0, x)
	assertTrue(y < -100) -- below the bottom set (54 below the middle) and its labels at their held size
	local _, _, _, nextX, nextY = FreeControlPageNext:GetPoint(1)
	local _, _, _, prevX, prevY = FreeControlPagePrev:GetPoint(1)
	assertTrue(nextX > 0 and prevX < 0)
	assertAlmostEquals(y, nextY, 0.001)
	assertAlmostEquals(y, prevY, 0.001)
	assertTrue(ns.Bars.pager:IsVisible())
	assertNotNil(ns.Bars.pager.plate:GetTexture())
	assertNotNil(FreeControlPageNext.fc.arrow:GetTexture())
	FreeControlPageNext:GetScript("OnMouseDown")(FreeControlPageNext)
	FreeControlPageNext:GetScript("OnMouseUp")(FreeControlPageNext)
	UseRegularBars()
	Clean()
end)

test("the page selector can be hidden while a bound button still turns the page, and pages can be switched off", function()
	Reset()
	UseControllerSlots("none")
	ns.db.showPager = false
	assertTrue(ns.RequestRefresh())
	assertFalse(ns.Bars.pager:IsShown())
	for _, arrow in ipairs({ FreeControlPageNext, FreeControlPagePrev }) do
		assertTrue(arrow:IsShown())          -- still there for a bound button
		assertEquals(0, arrow:GetAlpha())    -- with nothing to see
		assertFalse(arrow:IsMouseEnabled())  -- and nothing to click
	end
	SetBinding("PADRSHOULDER", ns.Bindings.PAGE_COMMANDS.next)
	A_Admin.SetInCombat(true)
	SimInput.PressKey("PADRSHOULDER")
	A_Admin.SetInCombat(false)
	assertEquals(PAGE[2][1], Slots(1))
	assertEquals(2, ns.db.page)

	ns.db.pages = false
	assertTrue(ns.RequestRefresh())
	assertEquals(1, ns.Layout.GetPageCount())
	assertFalse(FreeControlPageNext:IsShown())
	assertEquals(PAGE[2][1], Slots(1))   -- the bar stays on the page it was on
	SimInput.PressKey("PADRSHOULDER")
	assertEquals(PAGE[2][1], Slots(1))   -- and the bound button turns nothing
	assertEquals(2, ns.db.page)

	SetBinding("PADRSHOULDER", nil)
	ns.db.pages, ns.db.showPager, ns.db.page = true, true, 1
	assertTrue(ns.RequestRefresh())
	assertTrue(ns.Bars.pager:IsVisible())
	assertEquals(1, FreeControlPageNext:GetAlpha())
	assertTrue(FreeControlPageNext:IsMouseEnabled())
	UseRegularBars()
	Clean()
end)

test("with mouse mode switched off its button is a slot with its own action on each page, and on again it is the mouse button", function()
	Reset()
	UseControllerSlots("none")
	assertEquals("CLICK FreeControlMouse:LeftButton", GetBindingAction("PAD4", true))
	ns.SetMouseMode(false)
	assertEquals("action", ns.db.roles[6])
	assertEquals("CLICK FreeControlKey0_6:LeftButton", GetBindingAction("PAD4", true))
	assertTrue(FreeControlButton0_6:IsShown())
	assertFalse(ns.Buttons.role[6]:IsShown())
	assertNil(FreeControlHeader:GetAttribute("fc-mouse-on"))
	local seen = {}
	for page = 1, 3 do
		local slot = ns.Buttons:GetSlot(0, 6)
		assertNil(seen[slot])
		seen[slot] = page
		wipe(used)
		SimInput.PressKey("PAD4")
		assertTableEquals({ slot }, used)
		Turn(FreeControlPageNext)
	end
	assertEquals(1, seen[first + 56 + 25]) -- page 1 keeps it in page 3's LT + RT slot of that button
	assertEquals(2, seen[first + 25])      -- page 2 in page 1's
	assertEquals(3, seen[first + 28 + 25]) -- page 3 in page 2's

	ns.SetMouseMode(true)
	assertEquals("cmd:FREECONTROL_TOGGLECURSOR", ns.db.roles[6])
	assertEquals("CLICK FreeControlMouse:LeftButton", GetBindingAction("PAD4", true))
	assertTrue(ns.Buttons.role[6]:IsShown())
	assertTrue(FreeControlHeader:GetAttribute("fc-mouse-on"))
	UseRegularBars()
	Clean()
end)

test("mouse mode switched off in a fight: both halves of its button go on working until the fight ends", function()
	Reset()
	UseControllerSlots("none")
	local leftBefore = GetBindingAction("PADLSTICK", true)
	A_Admin.SetInCombat(true)
	assertFalse(ns.SetMouseMode(false)) -- waits for the fight to end
	assertEquals("CLICK FreeControlMouse:LeftButton", GetBindingAction("PAD4", true)) -- nothing is rebound in a fight
	-- The secure half of the press (Blizzard's restricted code) still binds the click buttons,
	-- so the ordinary half has to bring the pointer out with it: one without the other would
	-- leave the stick clicks clicking at a pointer that is not there.
	SimInput.PressKey("PAD4")
	assertEquals("CAMERAORSELECTORMOVE", GetBindingAction("PADLSTICK", true))
	assertTrue(IsGamePadCursorControlEnabled())
	SimInput.PressKey("PAD4")
	assertEquals(leftBefore, GetBindingAction("PADLSTICK", true))
	assertFalse(IsGamePadCursorControlEnabled())
	A_Admin.SetInCombat(false)
	assertEquals("CLICK FreeControlKey0_6:LeftButton", GetBindingAction("PAD4", true))
	assertNil(FreeControlHeader:GetAttribute("fc-mouse-on"))
	wipe(used)
	SimInput.PressKey("PAD4")
	assertFalse(IsGamePadCursorControlEnabled())
	assertEquals(leftBefore, GetBindingAction("PADLSTICK", true))
	assertTableEquals({ ns.Buttons:GetSlot(0, 6) }, used)
	assertTrue(ns.SetMouseMode(true))
	UseRegularBars()
	Clean()
end)

test("a button chosen to be held is the game's own setting while FreeControl is active, and a combination's job is a real key binding", function()
	Reset()
	UseControllerSlots("none")
	local own = GetCVar("GamePadEmulateAlt")
	assertNotNil(own) -- the simulator has the setting
	ns.Options:OpenCombos()
	assertTrue(ns.Options.combosPanel.built)
	assertTrue(ns.Options.combosPanel:IsVisible())
	assertTrue(ns.Options.SetHold("Alt", "PADRSHOULDER"))
	assertEquals("PADRSHOULDER", GetCVar("GamePadEmulateAlt"))
	assertEquals("PADRSHOULDER", ns.CVars:GetCombinationButton("Alt"))
	SlashCmdList.FREECONTROL("off")
	assertEquals(own, GetCVar("GamePadEmulateAlt")) -- the game's own value is back
	SlashCmdList.FREECONTROL("on")
	assertEquals("PADRSHOULDER", GetCVar("GamePadEmulateAlt"))

	-- Blizzard's SetBinding takes the combination by the name the game spells it with, and the
	-- binding clicks the secure page arrow in a fight. That the client looks for this binding
	-- before the D-pad's own when the two buttons are held is the client's doing, and cannot be
	-- seen here: the simulator has no keys to hold.
	local chord = "ALT-CTRL-PADDRIGHT"
	assertTrue(ns.Options.Bind(chord, ns.Bindings.PAGE_COMMANDS.next))
	assertEquals(ns.Bindings.PAGE_COMMANDS.next, GetBindingAction(chord))
	assertEquals(chord, (GetBindingKey(ns.Bindings.PAGE_COMMANDS.next)))
	local listed = false
	for _, region in ipairs({ ns.Options.combosPanel:GetRegions() }) do
		listed = listed or (region.GetText and region:GetText() == "LB + RB + D-pad Right")
	end
	assertTrue(listed) -- the page lists it, named by its buttons
	A_Admin.SetInCombat(true)
	SimInput.PressKey(chord)
	ShowsPage(2)
	wipe(used)
	SimInput.PressKey("PADDRIGHT")
	assertTableEquals({ first + 30 }, used) -- the D-pad alone still casts its slot, on the page now showing
	A_Admin.SetInCombat(false)

	assertTrue(ns.Options.Bind(chord, ""))
	assertEquals("", GetBindingAction(chord))
	assertTrue(ns.Options.SetHold("Alt", "none"))
	ns.db.standIns.Alt = nil
	assertTrue(ns.RequestRefresh())
	assertEquals(own, GetCVar("GamePadEmulateAlt"))
	SlashCmdList.FREECONTROL("page 1")
	UseRegularBars()
	Clean()
end)

test("the game's own pointer and its pick of enemies are console variables set while FreeControl is active, and put back", function()
	Reset()
	local auto, aim, arc = GetCVar("GamePadCursorAutoEnable"), GetCVar("GamePadCursorForTargeting"), GetCVar("SoftTargetEnemyArc")
	assertNotNil(auto)
	assertNotNil(aim)
	assertNotNil(arc)
	SlashCmdList.FREECONTROL("gamepointer off")
	assertEquals("0", GetCVar("GamePadCursorAutoEnable"))
	assertEquals("0", GetCVar("GamePadCursorForTargeting"))
	SlashCmdList.FREECONTROL("front on")
	assertEquals("1", GetCVar("SoftTargetEnemyArc"))
	SlashCmdList.FREECONTROL("gamepointer on")
	SlashCmdList.FREECONTROL("front off")
	assertEquals(auto, GetCVar("GamePadCursorAutoEnable"))
	assertEquals(aim, GetCVar("GamePadCursorForTargeting"))
	assertEquals(arc, GetCVar("SoftTargetEnemyArc"))
	Clean()
end)

test("every control on the four settings pages shows a tooltip when the mouse is over it", function()
	Reset()
	-- With Blizzard's own tooltip code. The error version 1.5.0 raised here (a tooltip handed a
	-- function for its title, because the game has no text to give back for an empty label) does
	-- not show in the simulator, which answers differently for an empty label; tools/tests is
	-- where that one is caught.
	local empty = UIParent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	empty:SetText("")
	local emptyText = empty:GetText()
	local hovered = 0
	for open, panel in pairs({ Open = ns.Options.panel, OpenMouse = ns.Options.mousePanel, OpenButtons = ns.Options.buttonsPanel, OpenCombos = ns.Options.combosPanel }) do
		ns.Options[open](ns.Options)
		assertTrue(panel.built)
		assertTrue(panel:IsVisible())
		for _, control in ipairs({ panel:GetChildren() }) do
			local onEnter = control:IsShown() and control:GetScript("OnEnter")
			if onEnter then
				onEnter(control)
				assertTrue(GameTooltip:IsShown())
				assertEquals("string", type(GameTooltipTextLeft1:GetText()))
				control:GetScript("OnLeave")(control)
				hovered = hovered + 1
			end
		end
	end
	HideUIPanel(SettingsPanel)
	assertTrue(hovered > 40)
	assertTrue(emptyText == nil or emptyText == "")
	Clean()
end)

test("back on the regular action bars there is one page, and the arrows are gone", function()
	Reset()
	UseRegularBars()
	assertEquals(1, ns.Layout.GetPageCount())
	assertFalse(FreeControlPageNext:IsShown())
	assertFalse(FreeControlPagePrev:IsShown())
	assertEquals(61, FreeControlKey1_1:GetAttribute("action"))
	Turn(FreeControlPageNext)
	assertEquals(61, FreeControlKey1_1:GetAttribute("action"))
	for _, command in ipairs({ "status", "buttons", "page 2", "page 1" }) do
		SlashCmdList.FREECONTROL(command)
	end
	HideUIPanel(SettingsPanel)
	Clean()
end)
