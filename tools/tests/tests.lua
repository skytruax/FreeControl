-- Scenarios for FreeControl, run against tools/tests/wowmock.lua. Each test gets a fresh Lua state.
local M = Mock
local ns

local function eq(actual, expected, what)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(what or "value", tostring(expected), tostring(actual)), 2)
	end
end

local function truthy(value, what)
	if not value then error((what or "value") .. ": expected something true, got " .. tostring(value), 2) end
end

-- The addon runs in an environment that passes everything through to the real globals but notes
-- each name it reads or writes, so `run.py --globals` can list every client API it depends on.
GLOBAL_READS, GLOBAL_WRITES = {}, {}
TRACKED = setmetatable({}, {
	__index = function(_, key)
		GLOBAL_READS[key] = true
		return _G[key]
	end,
	__newindex = function(_, key, value)
		GLOBAL_WRITES[key] = true
		_G[key] = value
	end,
})

-- Loads the addon the way the client does: every file in the .toc, in order, sharing one table.
local function Load(saved)
	FreeControlDB = saved
	ns = {}
	for line in ReadFile("FreeControl/FreeControl.toc"):gmatch("[^\r\n]+") do
		if line ~= "" and not line:match("^#") then
			local chunk = assert(loadstring(ReadFile("FreeControl/" .. line), "@FreeControl/" .. line))
			setfenv(chunk, TRACKED)
			chunk("FreeControl", ns)
		end
	end
	M.Fire("ADDON_LOADED", "FreeControl")
	M.Fire("PLAYER_LOGIN")
	M.Fire("PLAYER_ENTERING_WORLD")
	return ns
end

local function Binding(key)
	local binding = M.bindings[key]
	return binding and (binding.kind .. ":" .. binding.target) or nil
end

local function Used()
	local slots = {}
	for i, use in ipairs(M.used) do slots[i] = use.slot end
	return table.concat(slots, ",")
end

local function Printed(pattern)
	for _, line in ipairs(M.printed) do
		if line:find(pattern) then return true end
	end
	return false
end

local function Slots(set)
	local out = {}
	for index = 1, 8 do out[index] = tostring(ns.Buttons:GetSlot(set, index) or "-") end
	return table.concat(out, " ")
end

TESTS = {}
local function test(name, fn) TESTS[#TESTS + 1] = { name = name, fn = fn } end

---------------------------------------------------------------------------
test("loads, builds 32 slots and shows the bar", function()
	Load()
	truthy(ns.IsBuilt(), "built")
	truthy(M.frames.FreeControlBar:IsShown(), "bar shown")
	for set = 0, 3 do
		for index = 1, 8 do
			truthy(M.frames[("FreeControlButton%d_%d"):format(set, index)], "visible button")
			truthy(M.frames[("FreeControlKey%d_%d"):format(set, index)], "key button")
		end
	end
	eq(ns.Buttons:IsSecureClickMissing(), false, "secure click check")
	eq(M.frames.FreeControlButton1_1:GetScript("OnClick"), SecureActionButton_OnClick, "visible OnClick is the secure one")
	eq(M.frames.FreeControlKey1_1:GetScript("OnClick"), SecureActionButton_OnClick, "key OnClick is the secure one")
	eq(M.category ~= nil, true, "settings page registered")
end)

test("slots match Blizzard's controller-bar layout", function()
	Load()
	eq(Slots(1), "185 186 187 188 189 190 191 192", "LT set")
	eq(Slots(2), "193 194 195 196 197 198 199 200", "RT set")
	eq(Slots(3), "201 202 203 204 205 206 207 208", "LT+RT set")
	eq(Slots(0), "181 182 183 184 - - - -", "no-trigger set (face buttons are commands by default)")
end)

test("default bindings: D-pad slots, Interact / Cancel / Jump, Y left alone", function()
	Load()
	eq(Binding("PADLTRIGGER"), "click:FreeControlTrigger1", "left trigger")
	eq(Binding("PADRTRIGGER"), "click:FreeControlTrigger2", "right trigger")
	eq(Binding("PADDLEFT"), "click:FreeControlKey0_1", "d-pad left")
	eq(Binding("PADDUP"), "click:FreeControlKey0_2", "d-pad up")
	eq(Binding("PADDRIGHT"), "click:FreeControlKey0_3", "d-pad right")
	eq(Binding("PADDDOWN"), "click:FreeControlKey0_4", "d-pad down")
	eq(Binding("PAD3"), "cmd:INTERACTTARGET", "X = interact")
	eq(Binding("PAD4"), nil, "Y is left to the player's own binding")
	eq(Binding("PAD2"), "cmd:TOGGLEGAMEMENU", "B = cancel")
	eq(Binding("PAD1"), "cmd:JUMP", "A = jump")
end)

test("a key casts once, on press, and shows the button pushed while held", function()
	Load()
	M.actions[182] = { texture = "icon" }
	M.KeyDown("PADDUP")
	eq(Used(), "182", "cast on press")
	eq(M.frames.FreeControlButton0_2:GetButtonState(), "PUSHED", "pushed while held")
	M.KeyUp("PADDUP")
	eq(Used(), "182", "no second cast on release")
	eq(M.frames.FreeControlButton0_2:GetButtonState(), "NORMAL", "released")
end)

test("a key casts on release when the player turned 'cast on key down' off", function()
	M.cvars.ActionButtonUseKeyDown = "0"
	Load()
	M.KeyDown("PADDUP")
	eq(Used(), "", "nothing on press")
	M.KeyUp("PADDUP")
	eq(Used(), "182", "cast on release")
end)

test("triggers switch sets in combat without a protected-call error", function()
	Load()
	M.EnterCombat()
	M.KeyDown("PADLTRIGGER")
	eq(ns.Bindings:GetActiveSet(), 1, "left set held")
	eq(Binding("PADDUP"), "click:FreeControlKey1_2", "d-pad up now on the left set")
	eq(Binding("PAD1"), "click:FreeControlKey1_8", "A now on the left set")
	eq(Binding("PAD4"), "click:FreeControlKey1_6", "Y now on the left set")
	M.Tap("PAD1")
	eq(Used(), "192", "LT + A")

	M.KeyDown("PADRTRIGGER")
	eq(ns.Bindings:GetActiveSet(), 3, "both held")
	M.Tap("PAD3")
	eq(Used(), "192,205", "LT + RT + X")

	M.KeyUp("PADLTRIGGER")
	eq(ns.Bindings:GetActiveSet(), 2, "right set after letting go of the left trigger")
	M.Tap("PADDLEFT")
	eq(Used(), "192,205,193", "RT + d-pad left")

	M.KeyUp("PADRTRIGGER")
	eq(ns.Bindings:GetActiveSet(), 0, "back to no trigger")
	eq(Binding("PAD1"), "cmd:JUMP", "A is jump again")
	eq(Binding("PAD4"), nil, "Y handed back")
	M.Tap("PAD1")
	eq(M.commands[1][1] .. "/" .. M.commands[1][2], "JUMP/down", "jump pressed")
	eq(M.commands[2][1] .. "/" .. M.commands[2][2], "JUMP/up", "jump released")
	M.LeaveCombat()
end)

test("the held set grows and the others fade, in combat too", function()
	Load()
	M.EnterCombat()
	M.KeyDown("PADRTRIGGER")
	eq(M.frames.FreeControlSet2:GetScale(), 1.2, "held set scale")
	eq(M.frames.FreeControlSet2:GetAlpha(), 1, "held set alpha")
	eq(M.frames.FreeControlSet0:GetScale(), 1, "other set scale")
	eq(M.frames.FreeControlSet0:GetAlpha(), 0.8, "other set alpha")
	truthy(ns.Bars.deco[2].glow:IsShown(), "glow on the held set")
	eq(ns.Bars.deco[0].glow:IsShown(), false, "no glow elsewhere")
	M.KeyUp("PADRTRIGGER")
	eq(M.frames.FreeControlSet0:GetScale(), 1.2, "no-trigger set grows back")
	M.LeaveCombat()
end)

test("a key released after its trigger still ends on the button it started on", function()
	Load()
	M.KeyDown("PADLTRIGGER")
	M.KeyDown("PAD1")
	M.KeyUp("PADLTRIGGER")
	M.KeyUp("PAD1")
	eq(Used(), "192", "one cast")
	eq(M.frames.FreeControlButton1_8:GetButtonState(), "NORMAL", "not left looking pushed")
	eq(#M.commands, 0, "no stray jump")
end)

test("the mouse acts on release, so a drag can pick the action up first", function()
	Load()
	M.actions[185] = { texture = "icon" }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 185)
	local button = M.frames.FreeControlButton1_1
	eq(M.Click(button, "LeftButton", true), false, "press is not delivered")
	eq(M.Click(button, "LeftButton", false), true, "release is")
	eq(Used(), "185", "cast once, on release")
end)

test("drag and drop follows the action bar lock and never runs in combat", function()
	Load()
	M.actions[185] = { texture = "icon" }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 185)
	local button = M.frames.FreeControlButton1_1
	button:GetScript("OnDragStart")(button)
	eq(#M.picked, 0, "locked bars need the modifier")
	M.pickupModifier = true
	button:GetScript("OnDragStart")(button)
	eq(M.picked[1], 185, "picked up with the modifier")

	local target = M.frames.FreeControlButton2_3
	target:GetScript("OnReceiveDrag")(target)
	eq(M.placed[1], 195, "dropped on another slot")

	M.EnterCombat()
	button:GetScript("OnDragStart")(button)
	M.cursor = "spell"
	target:GetScript("OnReceiveDrag")(target)
	eq(#M.picked, 1, "no pick-up in combat")
	eq(#M.placed, 1, "no drop in combat")
	eq(#M.errors, 2, "the player is told why")
	M.LeaveCombat()
end)

test("buttons draw what is in their slot and follow changes", function()
	Load()
	local button = M.frames.FreeControlButton2_5
	eq(button.fc.icon:GetAlpha(), 0, "empty: no icon")
	eq(button.fc.glyph:GetAlpha(), 0.5, "empty: glyph")

	M.actions[197] = { texture = "fireball", count = "3", cooldown = { 10, 5 }, text = "aa", current = true }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 197)
	eq(button.fc.icon:GetTexture(), "fireball", "icon")
	eq(button.fc.icon:GetAlpha(), 1, "icon visible")
	eq(button.fc.glyph:GetAlpha(), 0, "glyph out of the way")
	eq(button.fc.count:GetText(), "3", "count")
	eq(button.fc.name:GetText(), "aa", "macro name")
	eq(button.fc.cooldown.__cooldown[2], 5, "cooldown running")
	eq(button:GetChecked(), true, "checked while current")

	M.actions[197].usable, M.actions[197].noMana = false, true
	M.Fire("ACTION_USABLE_CHANGED", { { slot = 197, usable = false, noMana = true } })
	eq(button.fc.icon.calls.SetVertexColor[3], 1, "blue tint when out of mana")
	M.Fire("ACTION_RANGE_CHECK_UPDATE", 197, false, true)
	eq(button.fc.icon.calls.SetVertexColor[1], 0.9, "red tint when out of range")

	M.actions[197] = nil
	M.Fire("ACTIONBAR_SLOT_CHANGED", 197)
	eq(button.fc.icon:GetAlpha(), 0, "emptied")
	eq(button.fc.cooldown.__cooldown, nil, "cooldown cleared")
end)

test("the face badge shows only on the held set", function()
	Load()
	M.actions[197] = { texture = "icon" }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 197)
	local badge = M.frames.FreeControlButton2_5.fc.badge
	eq(badge:IsShown(), false, "not held")
	M.KeyDown("PADRTRIGGER")
	eq(badge:IsShown(), true, "held")
	M.KeyUp("PADRTRIGGER")
	eq(badge:IsShown(), false, "released")
end)

test("a no-trigger button can be turned into an action slot", function()
	Load()
	ns.db.roles[5] = "action"
	ns.RequestRefresh()
	eq(Slots(0), "181 182 183 184 261 - - -", "borrows a slot from page 3")
	eq(Binding("PAD3"), "click:FreeControlKey0_5", "X now presses that slot")
	truthy(M.frames.FreeControlButton0_5:IsShown(), "action button shown")
	eq(ns.Buttons.role[5]:IsShown(), false, "stand-in hidden")
	M.Tap("PAD3")
	eq(Used(), "261", "casts")

	ns.db.page = 3
	ns.RequestRefresh()
	eq(Slots(0), "237 238 239 240 233 - - -", "on page 3 it borrows from page 2 instead")
	eq(Slots(3), "257 258 259 260 261 262 263 264", "page 3 LT+RT set keeps its own slots")
end)

test("stance set swaps slots with the stance, in combat", function()
	Load({ stanceSet = "lt" })
	-- before the client has evaluated the drivers the buttons already point at the plain slots
	eq(M.frames.FreeControlKey1_1:GetAttribute("action"), 185, "key button has a slot straight away")
	eq(Slots(1), "185 186 187 188 189 190 191 192", "and so does the picture")
	M.RunDrivers()
	eq(Slots(1), "185 186 187 188 189 190 191 192", "no stance")
	M.EnterCombat()
	M.bonusbar = 2
	M.RunDrivers()
	eq(Slots(1), "273 274 275 276 277 278 279 280", "stance 2")
	eq(M.frames.FreeControlKey1_1:GetAttribute("action"), "273", "the key button follows")
	M.KeyDown("PADLTRIGGER")
	M.Tap("PADDLEFT")
	eq(Used(), "273", "casts the stance slot")
	M.KeyUp("PADLTRIGGER")
	M.bonusbar = 0
	M.RunDrivers()
	eq(Slots(1), "185 186 187 188 189 190 191 192", "back out of stance")
	eq(Slots(2), "193 194 195 196 197 198 199 200", "other sets untouched")
	M.LeaveCombat()
end)

test("stance set 'auto' follows the Gamepad options choice", function()
	M.cvars.GamepadStanceBarOverride = "3" -- page 1, right bar
	Load()
	M.bonusbar = 1
	M.RunDrivers()
	eq(Slots(2), "265 266 267 268 269 270 271 272", "right set swaps")
	eq(Slots(1), "185 186 187 188 189 190 191 192", "left set does not")
end)

test("settings changed in combat wait for the fight to end", function()
	Load()
	M.EnterCombat()
	ns.db.roles[6] = "cmd:TARGETNEARESTENEMY"
	eq(ns.RequestRefresh(), false, "queued")
	eq(Binding("PAD4"), nil, "not applied yet")
	M.LeaveCombat()
	eq(Binding("PAD4"), "cmd:TARGETNEARESTENEMY", "applied after combat")
end)

test("switching off hands everything back, switching on restores it", function()
	M.cvars.GamePadEnable = "0" -- a player who had controller input switched off
	Load()
	eq(M.cvars.GamePadEnable, "1", "controller input on")
	eq(M.cvars.SoftTargetInteract, "3", "interact key on")
	eq(M.cvars.SoftTargetInteractRange, "20.000000", "gamepad reach")
	eq(M.cvars.GamePadEmulateShift, "none", "left trigger no longer stands in for Shift")
	SlashCmdList.FREECONTROL("off")
	eq(next(M.bindings), nil, "no bindings left")
	eq(M.frames.FreeControlBar:IsShown(), false, "bar hidden")
	eq(M.cvars.GamePadEnable, "0", "controller input back to the player's value")
	eq(M.cvars.SoftTargetInteract, "1", "interact key back")
	eq(M.cvars.SoftTargetInteractRange, "10.000000", "reach back")
	eq(M.cvars.GamePadEmulateShift, "PADLTRIGGER", "Shift stand-in back")
	for slot, refs in pairs(M.rangeRefs) do eq(refs, 0, "range checks released for slot " .. slot) end
	eq(#M.drivers, 0, "no drivers left")

	SlashCmdList.FREECONTROL("on")
	eq(Binding("PAD1"), "cmd:JUMP", "bound again")
	truthy(M.frames.FreeControlBar:IsShown(), "bar back")
	eq(M.cvars.GamePadEnable, "1", "controller input on again")
	eq(M.rangeRefs[185], 1, "range checks asked for again, once")
end)

test("logging out restores the player's console variables, but not ones they changed since", function()
	M.cvars.GamePadEnable = "0"
	Load()
	M.cvars.SoftTargetInteractArc = "2" -- the player changed it mid-session
	M.Fire("PLAYER_LOGOUT")
	eq(M.cvars.GamePadEnable, "0", "restored")
	eq(M.cvars.SoftTargetInteract, "1", "restored")
	eq(M.cvars.SoftTargetInteractRange, "10.000000", "restored, though the client reformats the number")
	eq(M.cvars.GamePadEmulateShift, "PADLTRIGGER", "restored")
	eq(M.cvars.SoftTargetInteractArc, "2", "the player's newer choice stands")
	eq(next(ns.db.cvarBackup), nil, "nothing left to restore")
end)

test("a console variable the player already had on is left alone", function()
	M.cvars.GamePadEnable = "1"
	Load()
	M.Fire("PLAYER_LOGOUT")
	eq(M.cvars.GamePadEnable, "1", "still on")
end)

test("stays idle while Blizzard's Gamepad UI mode is on", function()
	M.gamepadUI = true
	Load()
	eq(ns.IsBuilt(), false, "nothing built")
	eq(next(M.bindings), nil, "nothing bound")
	eq(M.cvars.GamePadEmulateShift, "PADLTRIGGER", "console variables untouched")
	eq(M.cvars.SoftTargetInteract, "1", "console variables untouched")
	truthy(Printed("Gamepad UI mode is on"), "says why")
end)

test("falls back to the regular action bars when there are no controller slots", function()
	C_GamepadUI = nil
	Load()
	eq(ns.Layout.GetSlotSource(), "bars", "source")
	eq(Slots(1), "61 62 63 64 65 66 67 68", "LT set on the Bottom Left bar")
	eq(Slots(2), "49 50 51 52 53 54 55 56", "RT set on the Bottom Right bar")
	eq(Slots(3), "25 26 27 28 29 30 31 32", "LT+RT set on the Right bar")
	eq(Slots(0), "37 38 39 40 - - - -", "no-trigger set on the Left bar")
end)

test("stance swapping is skipped when the client rejects the stance slots", function()
	M.lastGamepadSlot = 264
	Load({ stanceSet = "lt" })
	eq(ns.Layout.HasGamepadSlots(), true, "pages usable")
	eq(ns.Layout.GetStanceSet(), nil, "no stance set")
	eq(#M.drivers, 0, "no drivers")
	eq(Slots(1), "185 186 187 188 189 190 191 192", "plain slots")
end)

test("dragging the handle moves the bar, and its centre stays put when the scale changes", function()
	Load()
	local mover, bar = nil, M.frames.FreeControlBar
	SlashCmdList.FREECONTROL("unlock")
	mover = ns.Bars.mover
	truthy(mover:IsShown(), "handle shown")
	eq(mover.__calls.SetSize[1], 760, "handle covers the bar")
	mover:GetScript("OnDragStart")(mover)
	truthy(mover.__moving, "the handle is what moves")
	mover.__center = { 900, 400 }
	mover:GetScript("OnUpdate")(mover)
	eq(bar.__calls.SetPoint[4], 100, "the bar follows during the drag (screen is 1600 wide)")
	mover:GetScript("OnDragStop")(mover)
	eq(mover.__moving, false, "dropped")
	eq(ns.db.point[1], 100, "x from the bottom-centre")
	eq(ns.db.point[2], 400, "y")
	SlashCmdList.FREECONTROL("scale 2")
	eq(bar.__calls.SetPoint[4], 50, "offset divided by the scale")
	eq(bar.__calls.SetPoint[5], 200, "offset divided by the scale")
	eq(mover.__calls.SetSize[1], 1520, "handle grows with the bar")
	eq(mover.__calls.SetPoint[4], 100, "handle stays in screen units")
	SlashCmdList.FREECONTROL("lock")
	eq(mover:IsShown(), false, "handle hidden")
end)

test("a drag is ended when combat starts", function()
	Load()
	SlashCmdList.FREECONTROL("unlock")
	local mover = ns.Bars.mover
	mover:GetScript("OnDragStart")(mover)
	mover.__center = { 700, 350 }
	M.EnterCombat()
	eq(mover.__moving, false, "stopped")
	eq(mover:IsShown(), false, "handle hidden in combat")
	eq(ns.db.point[1], -100, "where it was dropped is kept")
	M.LeaveCombat()
	truthy(mover:IsShown(), "handle back after combat")
end)

test("if the client is already locked down when combat is announced, the bar catches up afterwards", function()
	Load()
	SlashCmdList.FREECONTROL("unlock")
	local mover, bar = ns.Bars.mover, M.frames.FreeControlBar
	mover:GetScript("OnDragStart")(mover)
	mover.__center = { 700, 350 }
	M.combat = true -- lockdown first, then the event: nothing protected may be touched now
	M.Fire("PLAYER_REGEN_DISABLED")
	eq(mover:IsShown(), false, "handle hidden")
	eq(bar.__calls.SetPoint[4], 0, "bar not moved during the fight")
	M.LeaveCombat()
	eq(bar.__calls.SetPoint[4], -100, "bar moved once it ended")
end)

test("slash commands", function()
	Load()
	SlashCmdList.FREECONTROL("page 2")
	eq(Slots(1), "213 214 215 216 217 218 219 220", "page 2")
	SlashCmdList.FREECONTROL("slots bars")
	eq(Slots(1), "61 62 63 64 65 66 67 68", "bars")
	SlashCmdList.FREECONTROL("key lt PADLSHOULDER")
	eq(Binding("PADLSHOULDER"), "click:FreeControlTrigger1", "left trigger moved")
	eq(Binding("PADLTRIGGER"), nil, "old key released")
	SlashCmdList.FREECONTROL("key 8 SPACE")
	eq(Binding("SPACE"), "cmd:JUMP", "slot key moved")
	SlashCmdList.FREECONTROL("")
	eq(M.opened[1], "FreeControl", "opens the settings page")
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("State: active"), "status prints")
	SlashCmdList.FREECONTROL("nonsense")
	truthy(Printed("/fc status"), "help prints")
end)

test("the settings page builds and reflects the saved settings", function()
	Load()
	local panel = ns.Options.panel
	panel:GetScript("OnShow")(panel)
	truthy(panel.built, "built on first show")
	ns.db.scale = 1.5
	ns.Options:Sync()
end)

local function Problem(pattern)
	for _, problem in ipairs(ns.Bindings:FindProblems()) do
		if problem:find(pattern) then return true end
	end
	return false
end

test("status points out a key used twice", function()
	Load({ modKeys = { "PAD1", "PADRTRIGGER" } })
	truthy(Problem("PAD1 is set for both"), "names the key")
end)

test("status mentions that the right trigger clicks while the stick cursor is out", function()
	Load()
	truthy(Problem("PADRTRIGGER is also the controller's mouse%-click button"), "client default")
	M.cvars.GamePadCursorLeftClick = "PADLSTICK"
	eq(Problem("mouse%-click button"), false, "gone once the click button is moved")
end)

test("saved settings that make no sense are replaced by defaults", function()
	Load({ page = 9, scale = "big", roles = { "action", "action", "action", "action", "explode" }, keys = { 5 } })
	eq(ns.db.page, 1, "page")
	eq(ns.db.scale, 1, "scale")
	eq(ns.db.roles[5], "cmd:INTERACTTARGET", "role")
	eq(ns.db.keys[1], "PADDLEFT", "key")
end)

test("the mouse-cursor command toggles the client's stick cursor", function()
	Load()
	ns.ToggleCursor()
	eq(M.cursorControl, true, "on")
	ns.ToggleCursor()
	eq(M.cursorControl, false, "off")
end)

test("tooltips name the button and what it does", function()
	Load()
	local empty = M.frames.FreeControlButton1_5
	empty:GetScript("OnEnter")(empty)
	eq(GameTooltip.lines[1], "LT + X", "empty slot is named")
	M.actions[189] = { texture = "icon" }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 189)
	eq(GameTooltip.lines[1], "action 189", "refreshes to the action")
	eq(GameTooltip.lines[2], "LT + X", "with the button name under it")
	empty:GetScript("OnLeave")(empty)

	local role = ns.Buttons.role[8]
	role:GetScript("OnEnter")(role)
	eq(GameTooltip.lines[1], "A", "role button is named")
	eq(GameTooltip.lines[2], "Jump", "and says what it does")
end)

test("labels follow the controller: PlayStation shapes and L2 / R2", function()
	M.labelStyle = "Shapes"
	Load()
	truthy(M.frames.FreeControlButton1_5.fc.glyph:GetTexture():find("Glyph%-Square$"), "square on the left face button")
	truthy(ns.Bars.deco[1].labels[1].texture:GetTexture():find("Badge%-L2$"), "L2 badge")
	eq(ns.Layout.GetButtonName(3, 8), "L2 + R2 + Cross", "button name")
end)

test("settings page buttons step through choices when there is no menu system", function()
	Load()
	local panel = ns.Options.panel
	panel:GetScript("OnShow")(panel)
	eq(ns.db.labelStyle, "auto", "starts on auto")
	ns.Options:OpenRoleMenu(ns.Buttons.role[6], 6)
	eq(ns.db.roles[6], "cmd:INTERACTTARGET", "'pass' steps to the first command")
	eq(Binding("PAD4"), "cmd:INTERACTTARGET", "and it is bound")
end)

test("settings page buttons open a menu when the client has one", function()
	local picked
	MenuUtil = {
		CreateContextMenu = function(owner, generator)
			local root = { items = {} }
			function root:CreateRadio(text, isSelected, onSelect, data)
				self.items[#self.items + 1] = { text = text, isSelected = isSelected, onSelect = onSelect }
			end
			generator(owner, root)
			picked = root
		end,
	}
	Load()
	ns.Options:OpenRoleMenu(ns.Buttons.role[6], 6)
	eq(picked.items[1].text, "Action slot", "first choice")
	eq(picked.items[2].isSelected(), true, "'My own key binding' is the current one")
	picked.items[4].onSelect()
	eq(ns.db.roles[6], "cmd:JUMP", "picking sets the role")
	eq(picked.items[4].isSelected(), true, "and the menu shows it selected")
	eq(picked.items[2].isSelected(), false, "and no longer the old one")
end)

test("a button left to the player's own binding says what that binding is", function()
	M.userBindings = { PAD4 = "TARGETNEARESTENEMY" }
	Load()
	local role = ns.Buttons.role[6]
	role:GetScript("OnEnter")(role)
	eq(GameTooltip.lines[2], "Your own key binding: <TARGETNEARESTENEMY>", "names the binding")
	M.userBindings = nil
	role:GetScript("OnEnter")(role)
	truthy(GameTooltip.lines[2]:find("nothing is bound"), "says when nothing is bound")
end)

test("status reports the stance slots and agrees with the client", function()
	Load({ stanceSet = "rt" })
	M.bonusbar = 3
	M.RunDrivers()
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Stance 3 slots start at 281 %(the game says 281%)"), "stance line")
	eq(Printed("these differ"), false, "no mismatch")
	truthy(Printed("stance set: RT"), "names the stance set")
end)

test("reset puts the bar back", function()
	Load({ point = { 300, 500 }, scale = 1.5 })
	SlashCmdList.FREECONTROL("reset")
	eq(ns.db.point[1], 0, "x")
	eq(ns.db.point[2], 270, "y")
	eq(ns.db.scale, 1, "scale")
	ns.db.point[1] = 99
	eq(ns.DEFAULTS.point[1], 0, "the defaults table is not shared with the saved one")
end)

test("a command typed by hand still gets a name and an icon", function()
	Load({ roles = { "action", "action", "action", "action", "cmd:TOGGLESHEATH" } })
	eq(Binding("PAD3"), "cmd:TOGGLESHEATH", "bound")
	local role = ns.Buttons.role[5]
	truthy(role.fc.icon:GetTexture():find("Role%-Generic$"), "generic icon")
	role:GetScript("OnEnter")(role)
	eq(GameTooltip.lines[2], "<TOGGLESHEATH>", "named by the game")
end)

test("drag and drop is free when the action bars are unlocked", function()
	M.lockActionBars = false
	Load()
	M.actions[185] = { texture = "icon" }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 185)
	local button = M.frames.FreeControlButton1_1
	button:GetScript("OnDragStart")(button)
	eq(M.picked[1], 185, "picked up without a modifier")
	-- clicking a slot while holding something drops it there (UseAction places what is on the cursor)
	M.Click(M.frames.FreeControlButton1_2, "LeftButton", false)
	eq(M.placed[1], 186, "dropped by clicking")
	eq(Used(), "", "and nothing was cast")
end)

test("a trigger that stands in for Shift is made a plain button, other buttons are left alone", function()
	Load()
	eq(M.cvars.GamePadEmulateShift, "none", "left trigger: stand-in off")
	eq(M.cvars.GamePadEmulateCtrl, "PADLSHOULDER", "left bumper still Ctrl: not one of our buttons")
	eq(Problem("act as a modifier"), false, "nothing to warn about")
	M.KeyDown("PADLTRIGGER")
	eq(ns.Bindings:GetActiveSet(), 1, "holding it selects the left set")
	M.KeyUp("PADLTRIGGER")

	-- move the left trigger onto the bumper: the two stand-ins swap
	SlashCmdList.FREECONTROL("key lt PADLSHOULDER")
	eq(M.cvars.GamePadEmulateShift, "PADLTRIGGER", "old trigger gets its stand-in back")
	eq(M.cvars.GamePadEmulateCtrl, "none", "new trigger loses its own")
	M.KeyDown("PADLSHOULDER")
	eq(ns.Bindings:GetActiveSet(), 1, "the bumper now selects the left set")
	M.KeyUp("PADLSHOULDER")

	-- and if something sets it again behind our back, status says so
	M.cvars.GamePadEmulateCtrl = "PADLSHOULDER"
	truthy(Problem("GamePadEmulateCtrl"), "warns")
	eq(M.KeyDown("PADLSHOULDER"), "modifier", "because the press no longer arrives")
end)

test("the first login explains itself once", function()
	Load()
	truthy(Printed("Hold a trigger"), "hint shown")
	local saved = FreeControlDB
	M.printed = {}
	M.Fire("PLAYER_LOGIN")
	eq(Printed("Hold a trigger"), false, "not repeated")
	eq(saved.introShown, true, "remembered")
end)
