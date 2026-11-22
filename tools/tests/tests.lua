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

-- Opens a settings page the way the settings window does: by showing it.
local function Open(panel)
	panel:Hide()
	panel:Show()
end

TESTS = {}
-- A scenario also fails if the addon reported an error to the game along the way (the addon
-- catches errors in its event handlers so that one bad handler cannot stop the rest), unless
-- the scenario is about exactly that and says so with M.expectErrors.
local function test(name, fn)
	TESTS[#TESTS + 1] = { name = name, fn = function()
		local ok, problem = xpcall(fn, function(e) return debug.traceback(tostring(e), 2) end)
		if not M.expectErrors and #M.luaErrors > 0 then
			error("the addon raised an error: " .. M.luaErrors[1] .. (ok and "" or "\nand then: " .. tostring(problem)), 0)
		end
		if not ok then error(problem, 0) end
	end }
end

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

test("default bindings: D-pad slots, Interact / mouse cursor / Cancel / Jump", function()
	Load()
	eq(Binding("PADLTRIGGER"), "click:FreeControlTrigger1", "left trigger")
	eq(Binding("PADRTRIGGER"), "click:FreeControlTrigger2", "right trigger")
	eq(Binding("PADDLEFT"), "click:FreeControlKey0_1", "d-pad left")
	eq(Binding("PADDUP"), "click:FreeControlKey0_2", "d-pad up")
	eq(Binding("PADDRIGHT"), "click:FreeControlKey0_3", "d-pad right")
	eq(Binding("PADDDOWN"), "click:FreeControlKey0_4", "d-pad down")
	eq(Binding("PAD3"), "cmd:INTERACTTARGET", "X = interact")
	eq(Binding("PAD4"), "click:FreeControlMouse", "Y = mouse cursor on / off, through the secure mouse button")
	eq(Binding("PAD2"), "cmd:TOGGLEGAMEMENU", "B = cancel")
	eq(Binding("PAD1"), "cmd:JUMP", "A = jump")
end)

test("a key casts once, on press; the button looks held meanwhile and springs back, in combat too", function()
	Load()
	M.actions[182] = { texture = "icon" }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 182)
	local fc = M.frames.FreeControlButton0_2.fc
	eq(fc.pressShade:GetAlpha(), 0, "not held to begin with")
	eq(fc.icon.calls.SetTexCoord[1], 0.07, "a square icon is cropped at rest")
	M.EnterCombat()
	M.KeyDown("PADDUP")
	eq(Used(), "182", "cast on press")
	eq(fc.pressShade:GetAlpha(), 1, "held look, at once")
	truthy(fc.base.calls.SetTexCoord[1] < 0, "art drawn smaller while held")
	truthy(fc.icon.calls.SetTexCoord[1] < 0.07, "icon drawn smaller while held")
	M.KeyUp("PADDUP")
	eq(Used(), "182", "no second cast on release")
	M.Advance(0.05)
	truthy(fc.pressShade:GetAlpha() > 0 and fc.pressShade:GetAlpha() < 1, "springing back")
	M.Advance(0.2)
	eq(fc.pressShade:GetAlpha(), 0, "back to rest")
	eq(fc.base.calls.SetTexCoord[1], 0, "art back to full size")
	eq(fc.icon.calls.SetTexCoord[1], 0.07, "icon back to its crop")
	M.LeaveCombat()
end)

test("a key casts on press even with the game's 'cast on key down' switched off", function()
	M.cvars.ActionButtonUseKeyDown = "0"
	Load()
	M.KeyDown("PADDUP")
	eq(Used(), "182", "cast on press, like Blizzard's own controller buttons")
	M.KeyUp("PADDUP")
	eq(Used(), "182", "nothing more on release")
end)

test("in combat the game seals a cooldown's numbers, and the sweep of what was just used still shows at once", function()
	Load()
	local cooldown = M.frames.FreeControlButton0_2.fc.cooldown
	M.actions[182] = { texture = "kick", spell = 1766, cooldownOnUse = 10 }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 182)
	eq(cooldown.__cooldown, nil, "no cooldown yet")
	M.EnterCombat()
	truthy(issecretvalue(C_ActionBar.GetActionCooldown(182).duration), "this model seals the numbers in combat")
	M.KeyDown("PADDUP")
	-- No time has passed, and (checked after every test) nothing was refused or raised an error.
	truthy(cooldown.__cooldown, "cooldown showing at once")
	eq(cooldown.__cooldown[2], 10, "its duration")
	M.KeyUp("PADDUP")
	M.LeaveCombat()
end)

test("a cooldown shows the same way on a client that seals nothing", function()
	M.secretRestrictions = false
	Load()
	local cooldown = M.frames.FreeControlButton0_2.fc.cooldown
	M.actions[182] = { texture = "kick", cooldownOnUse = 10 }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 182)
	M.EnterCombat()
	M.Tap("PADDUP")
	eq(cooldown.__cooldown and cooldown.__cooldown[2], 10, "cooldown showing")
	M.LeaveCombat()
end)

for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN" }) do
	test("a cooldown shows when " .. event .. " is the only event the game raises for it", function()
		M.cooldownEvents = { event }
		Load()
		local cooldown = M.frames.FreeControlButton0_2.fc.cooldown
		M.actions[182] = { texture = "gouge", cooldownOnUse = 10 }
		M.Fire("ACTIONBAR_SLOT_CHANGED", 182)
		M.EnterCombat()
		M.Tap("PADDUP")
		eq(cooldown.__cooldown and cooldown.__cooldown[2], 10, "cooldown showing")
		M.LeaveCombat()
	end)
end

test("an item's cooldown is picked up from the bag event", function()
	Load()
	local cooldown = M.frames.FreeControlButton0_2.fc.cooldown
	M.actions[182] = { texture = "potion" }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 182)
	M.EnterCombat()
	M.actions[182].cooldown = { M.now, 120 }
	M.Fire("BAG_UPDATE_COOLDOWN")
	eq(cooldown.__cooldown and cooldown.__cooldown[2], 120, "potion cooldown showing")
	M.LeaveCombat()
end)

test("a cooldown that is reset early comes off the button with the next event, in combat too", function()
	Load()
	local cooldown = M.frames.FreeControlButton0_2.fc.cooldown
	M.actions[182] = { texture = "gouge", cooldownOnUse = 10 }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 182)
	M.EnterCombat()
	M.Tap("PADDUP")
	truthy(cooldown.__cooldown, "running")
	M.actions[182].cooldown = nil
	M.Fire("SPELL_UPDATE_COOLDOWN", 182)
	eq(cooldown.__cooldown, nil, "cleared")
	M.LeaveCombat()
end)

test("the bar does not poll: no cooldown is read unless the game raises an event", function()
	Load()
	M.actions[182] = { texture = "kick" }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 182)
	local readings = 0
	local read = C_ActionBar.GetActionCooldown
	C_ActionBar.GetActionCooldown = function(slot)
		readings = readings + 1
		return read(slot)
	end
	M.Tap("PADDUP")
	for _ = 1, 60 do M.Advance(0.05) end -- three seconds
	eq(readings, 0, "readings with no event")
	M.Fire("SPELL_UPDATE_COOLDOWN", 182)
	C_ActionBar.GetActionCooldown = read
	eq(readings, 1, "one reading per filled slot per event")
end)

test("a charge count is passed on while it is sealed, never read", function()
	Load()
	M.actions[182] = { texture = "bandage", count = "5" }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 182)
	local count = M.frames.FreeControlButton0_2.fc.count
	eq(count:GetText(), "5", "plain out of combat")
	M.EnterCombat()
	M.actions[182].count = "4"
	M.Fire("BAG_UPDATE")
	truthy(M.IsSealed(count:GetText()), "handed to the font string still sealed")
	eq(M.Unseal(count:GetText()), "4", "and it is the new count")
	M.LeaveCombat()
end)

test("a button that cannot be drawn is reported, not hidden, and the buttons after it still update", function()
	Load()
	M.actions[182] = { texture = "kick" }
	M.actions[183] = { texture = "gouge" }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 0)
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Errors since login: none"), "status says so while there are none")
	local read = C_ActionBar.GetActionCooldown
	C_ActionBar.GetActionCooldown = function(slot)
		if slot == 182 then error("the game changed its mind about slot 182") end
		return read(slot)
	end
	M.actions[183].cooldown = { M.now, 10 }
	M.expectErrors = true
	M.Fire("SPELL_UPDATE_COOLDOWN", 183)
	M.Fire("SPELL_UPDATE_COOLDOWN", 183)
	C_ActionBar.GetActionCooldown = read
	eq(M.frames.FreeControlButton0_3.fc.cooldown.__cooldown[2], 10, "the button after the failing one")
	eq(#M.luaErrors, 2, "every error reached the game's error handler")
	truthy(M.luaErrors[1]:find("changed its mind"), "with its text")
	local said = 0
	for _, line in ipairs(M.printed) do
		if line:find("Something went wrong inside FreeControl") then said = said + 1 end
	end
	eq(said, 1, "said in chat, once")
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("2 time%(s%): .*changed its mind"), "status lists it with how often it happened")
end)

test("an error in one event handler does not stop the other handlers of that event", function()
	Load()
	local ran = false
	ns.On("PLAYER_TARGET_CHANGED", function() error("first handler fails") end)
	ns.On("PLAYER_TARGET_CHANGED", function() ran = true end)
	M.expectErrors = true
	M.Fire("PLAYER_TARGET_CHANGED")
	truthy(ran, "second handler ran")
	truthy(M.luaErrors[1]:find("first handler fails"), "and the error was reported")
end)

test("/fc trace records what the game says about a used ability, and never touches a sealed value", function()
	Load()
	M.actions[182] = { texture = "kick", spell = 1766, cooldownOnUse = 10 }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 182)
	SlashCmdList.FREECONTROL("trace")
	truthy(Printed("Recording for 20 seconds"), "says that it started")
	M.EnterCombat()
	M.Advance(0.5)
	M.KeyDown("PADDUP")
	M.KeyUp("PADDUP")
	M.Advance(0.3)
	M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 1766)
	M.Fire("UNIT_SPELLCAST_SUCCEEDED", "target", M.Seal("Cast-2"), M.Seal(99)) -- someone else's: not asked for
	M.Fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-3", 424242)
	M.Fire("BAG_UPDATE_COOLDOWN")
	M.Fire("SPELL_UPDATE_COOLDOWN", M.Seal(1766)) -- an event may carry a sealed value too
	M.LeaveCombat()
	SlashCmdList.FREECONTROL("trace")
	local window = M.frames.FreeControlTrace
	truthy(window and window:IsShown(), "the box is up")
	local text = window.edit:GetText()
	local function Has(pattern, what)
		truthy(text:find(pattern), what .. " in:\n" .. text)
	end
	Has("FreeControl test, game interface 16001, out of combat", "the header")
	Has("seals combat values from addons: yes, but cooldowns are not sealed right now", "what the client says about sealing")
	Has("PLAYER_REGEN_DISABLED", "combat starting")
	Has("SPELL_UPDATE_COOLDOWN 1766", "the cooldown event and its spell")
	Has("ACTIONBAR_UPDATE_COOLDOWN", "the action bar event")
	Has("USED [^\n]*slot 182, spell 1766, in combat", "the press")
	Has("slot: running, sealed | spell: running, sealed | sweep: showing, sealed", "what the game and the button said, sealed")
	Has("UNIT_SPELLCAST_SUCCEEDED 1766", "the player's cast")
	Has("BAG_UPDATE_COOLDOWN\n[^\n]*SPELL_UPDATE_COOLDOWN sealed", "a sealed event value is written as such")
	Has("PLAYER_REGEN_ENABLED\n[^\n]*right after: slot: running, 10.0s", "the numbers once the fight is over")
	eq(text:find("<sealed>", 1, true), nil, "no sealed value was turned into text")
	eq(select(2, text:gsub("UNIT_SPELLCAST_SUCCEEDED", "")), 1, "nobody else's casts, sealed or not")
	eq(ns.Trace.active, false, "stopped")
	eq(#M.events.UNIT_SPELLCAST_SUCCEEDED, 0, "and no longer listening")
end)

test("/fc trace stops by itself, and does nothing at all while it is off", function()
	Load()
	M.actions[182] = { texture = "kick", cooldownOnUse = 10 }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 182)
	M.Tap("PADDUP")
	eq(M.frames.FreeControlTrace, nil, "no box before it is ever used")
	eq(M.events.UNIT_SPELLCAST_SENT, nil, "not listening while off")
	SlashCmdList.FREECONTROL("trace")
	eq(ns.Trace.active, true, "recording")
	M.Tap("PADDUP")
	M.Advance(10)
	eq(ns.Trace.active, true, "still recording after ten seconds")
	M.Advance(11)
	eq(ns.Trace.active, false, "stopped after twenty")
	truthy(Printed("Trace ready"), "and said so")
	truthy(M.frames.FreeControlTrace.edit:GetText():find("USED"), "with what it saw")
end)

test("cooldown numbers are on by default, skip the global cooldown, and can be switched off", function()
	Load()
	M.actions[182] = { texture = "icon" }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 182)
	local cooldown = M.frames.FreeControlButton0_2.fc.cooldown
	eq(cooldown.__calls.SetHideCountdownNumbers[1], false, "numbers shown")
	truthy(cooldown.__calls.SetMinimumCountdownDuration[1] > 1500, "not for a 1.5 second global cooldown")
	SlashCmdList.FREECONTROL("numbers off")
	eq(ns.db.cooldownNumbers, false, "saved")
	eq(cooldown.__calls.SetHideCountdownNumbers[1], true, "numbers hidden")
	SlashCmdList.FREECONTROL("numbers on")
	eq(cooldown.__calls.SetHideCountdownNumbers[1], false, "and back")
end)

test("a held button does not stay looking pressed when its key moves to another set", function()
	Load()
	M.actions[182] = { texture = "icon" }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 182)
	local fc = M.frames.FreeControlButton0_2.fc
	M.KeyDown("PADDUP")
	eq(fc.pressShade:GetAlpha(), 1, "held")
	M.KeyDown("PADLTRIGGER") -- the D-pad now belongs to the left set
	M.Advance(0.3)
	eq(fc.pressShade:GetAlpha(), 0, "let go")
	M.KeyUp("PADDUP")
	M.KeyUp("PADLTRIGGER")
end)

test("command buttons look held while their key is down, but only with no trigger held", function()
	Load()
	local jump = ns.Buttons.role[8].fc
	M.KeyDown("PAD1")
	M.Advance(0.016)
	eq(jump.pressShade:GetAlpha(), 1, "held")
	M.KeyUp("PAD1")
	M.Advance(0.016)
	M.Advance(0.3)
	eq(jump.pressShade:GetAlpha(), 0, "released")
	M.KeyDown("PADRTRIGGER")
	M.KeyDown("PAD1") -- A now belongs to the right set
	M.Advance(0.016)
	eq(jump.pressShade:GetAlpha(), 0, "the Jump button is not what was pressed")
	eq(M.frames.FreeControlButton2_8.fc.pressShade:GetAlpha(), 1, "the right set's button is")
	M.KeyUp("PAD1")
	M.KeyUp("PADRTRIGGER")
end)

-- The colour a texture was last given, as text.
local function Colour(region)
	local c = region.calls.SetVertexColor
	return c and ("%.2f %.2f %.2f"):format(c[1], c[2], c[3]) or "none"
end
local GREEN, BLUE, PURPLE = "0.25 1.00 0.30", "0.00 0.44 0.87", "0.64 0.21 0.93"

test("the ring around an equipped item has the colour of the item's rarity", function()
	Load()
	M.itemQuality[900] = 3 -- a rare item
	M.actions[182] = { texture = "icon", equipped = true, item = 900 }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 182)
	local ring = M.frames.FreeControlButton0_2.fc.equipped
	eq(ring:GetAlpha(), 1, "ring shown")
	eq(Colour(ring), BLUE, "blue for a rare item, where 1.2.0 drew every ring green")
	M.itemQuality[900] = 4
	M.Fire("ACTIONBAR_SLOT_CHANGED", 182)
	eq(Colour(ring), PURPLE, "purple for an epic one")
	M.actions[182].equipped = false
	M.Fire("ACTIONBAR_SLOT_CHANGED", 182)
	eq(ring:GetAlpha(), 0, "no ring once it is no longer equipped")
	M.actions[182] = nil
	M.Fire("ACTIONBAR_SLOT_CHANGED", 182)
	eq(ring:GetAlpha(), 0, "nor on an empty slot")
end)

test("an item the game has not loaded yet is ringed green until it has", function()
	Load()
	M.actions[182] = { texture = "icon", equipped = true, item = 901 }
	M.actions[183] = { texture = "icon", equipped = true, item = 902 }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 0)
	local ring, other = M.frames.FreeControlButton0_2.fc.equipped, M.frames.FreeControlButton0_3.fc.equipped
	eq(ring:GetAlpha(), 1, "ring shown")
	eq(Colour(ring), GREEN, "the green of the regular action bars meanwhile")
	M.itemQuality[901], M.itemQuality[902] = 3, 4
	M.Fire("GET_ITEM_INFO_RECEIVED", 902, true)
	eq(Colour(ring), GREEN, "another item's arrival does not touch it")
	eq(Colour(other), PURPLE, "only the ring that was waiting for that item")
	M.Fire("GET_ITEM_INFO_RECEIVED", 901, true)
	eq(Colour(ring), BLUE, "its own arrival colours it")
	M.itemQuality[901] = 4
	M.Fire("GET_ITEM_INFO_RECEIVED", 901, true)
	eq(Colour(ring), BLUE, "and after that the event is no longer of interest")
end)

test("an equipped item used through a macro keeps the green ring", function()
	Load()
	M.itemQuality[7] = 4 -- an item that happens to have the macro's number
	M.actions[182] = { texture = "icon", equipped = true, macro = 7 }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 182)
	local ring = M.frames.FreeControlButton0_2.fc.equipped
	eq(ring:GetAlpha(), 1, "ring shown")
	eq(Colour(ring), GREEN, "green: a macro's number is not an item")
end)

test("on a client that seals what is in a slot, the ring stays green and nothing fails", function()
	M.sealActionInfo = true
	Load()
	M.itemQuality[900] = 3
	M.actions[182] = { texture = "icon", equipped = true, item = 900, current = true }
	M.EnterCombat()
	M.Fire("ACTIONBAR_SLOT_CHANGED", 182)
	local button = M.frames.FreeControlButton0_2
	eq(button.fc.equipped:GetAlpha(), 1, "ring shown")
	eq(Colour(button.fc.equipped), GREEN, "green, without reading the sealed item")
	eq(button:GetChecked(), true, "and the rest of the button was still drawn")
	M.LeaveCombat()
	M.Fire("ACTIONBAR_SLOT_CHANGED", 182)
	eq(Colour(button.fc.equipped), BLUE, "the rarity colour once the item can be read")
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
	eq(Binding("PAD4"), "click:FreeControlMouse", "Y is the mouse button again")
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
	truthy(ns.Bars.deco[2].shade:IsShown(), "faint shade behind the held set")
	eq(ns.Bars.deco[0].shade:IsShown(), false, "none elsewhere")
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
	eq(M.frames.FreeControlKey1_1:GetAttribute("action"), 273, "the key button follows")
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
	eq(Slots(0), "181 182 183 184 - - - -", "nor does the D-pad: a Rogue needs one changing set")
	eq(Printed("Druid"), false, "and is told nothing about forms")
end)

-- What a Druid's bar shows in each form, with everything on automatic.
local CASTER = { [0] = "181 182 183 184 - - - -", "185 186 187 188 189 190 191 192", "193 194 195 196 197 198 199 200", "201 202 203 204 205 206 207 208" }

test("a Druid's right set, left set and D-pad all change with the form, and the rest stays", function()
	M.class = "DRUID"
	Load()
	M.RunDrivers()
	for set = 0, 3 do eq(Slots(set), CASTER[set], "caster form, set " .. set) end
	M.bonusbar = 1 -- Cat
	M.RunDrivers()
	eq(Slots(2), "265 266 267 268 269 270 271 272", "right set: the controller's own Cat slots, as before")
	eq(Slots(1), "73 74 75 76 77 78 79 80", "left set: the first eight slots of the game's own Cat bar")
	eq(Slots(0), "81 82 83 84 - - - -", "D-pad: the last four of them")
	eq(Slots(3), CASTER[3], "the both-triggers set is the same in every form")
	M.bonusbar = 3 -- Bear
	M.RunDrivers()
	eq(Slots(2), "281 282 283 284 285 286 287 288", "right set in Bear")
	eq(Slots(1), "97 98 99 100 101 102 103 104", "left set in Bear")
	eq(Slots(0), "105 106 107 108 - - - -", "D-pad in Bear")
	M.bonusbar = 5
	M.RunDrivers()
	eq(Slots(1), "121 122 123 124 125 126 127 128", "the fifth stance bar has slots too")
	eq(Slots(0), "129 130 131 132 - - - -", "for both groups")
	M.bonusbar = 0
	M.RunDrivers()
	for set = 0, 3 do eq(Slots(set), CASTER[set], "back in caster form, set " .. set) end
end)

test("a Druid changes form in a fight and every changing button casts the form's slot", function()
	M.class = "DRUID"
	Load()
	M.EnterCombat()
	M.bonusbar = 1
	M.RunDrivers()
	M.Tap("PADDLEFT")
	M.KeyDown("PADLTRIGGER")
	M.Tap("PADDLEFT")
	M.KeyUp("PADLTRIGGER")
	M.KeyDown("PADRTRIGGER")
	M.Tap("PAD1")
	M.KeyUp("PADRTRIGGER")
	M.KeyDown("PADLTRIGGER")
	M.KeyDown("PADRTRIGGER")
	M.Tap("PADDLEFT")
	M.KeyUp("PADRTRIGGER")
	M.KeyUp("PADLTRIGGER")
	eq(Used(), "81,73,272,201", "D-pad, left set and right set use the Cat slots; the both-triggers set its own")
	M.LeaveCombat()
end)

test("a Druid's first changing set is the one the Gamepad options name, when that is a trigger set", function()
	M.class = "DRUID"
	M.cvars.GamepadStanceBarOverride = "2" -- page 1, left bar
	Load()
	M.bonusbar = 1
	M.RunDrivers()
	eq(Slots(1), "265 266 267 268 269 270 271 272", "left set gets the controller's Cat slots")
	eq(Slots(2), "73 74 75 76 77 78 79 80", "and the right set the game's own Cat bar")
end)

test("a Druid whose Gamepad options name no usable set still gets all three", function()
	M.class = "DRUID"
	M.cvars.GamepadStanceBarOverride = "4" -- page 1, bottom bar: the both-triggers set
	Load()
	M.bonusbar = 1
	M.RunDrivers()
	eq(Slots(2), "265 266 267 268 269 270 271 272", "right set")
	eq(Slots(1), "73 74 75 76 77 78 79 80", "left set")
	eq(Slots(0), "81 82 83 84 - - - -", "D-pad")
	eq(Slots(3), CASTER[3], "the both-triggers set is left alone: something has to stay")
	M.cvars.GamepadStanceBarOverride = "1" -- none
	ns.RequestRefresh()
	M.RunDrivers()
	eq(Slots(2), "265 266 267 268 269 270 271 272", "the same with the Gamepad option set to none")
	eq(Slots(1), "73 74 75 76 77 78 79 80", "both sets")
end)

test("any class can ask for two changing sets, or two and the D-pad", function()
	Load({ stanceSet = "ltrt" })
	SlashCmdList.FREECONTROL("stance ltrt")
	truthy(Printed("Changes with your stance or form: RT set and LT set, on page 1%."), "two sets, in words, and the page they change on")
	M.bonusbar = 2
	M.RunDrivers()
	eq(Slots(2), "273 274 275 276 277 278 279 280", "right set")
	eq(Slots(1), "85 86 87 88 89 90 91 92", "left set")
	eq(Slots(0), CASTER[0], "D-pad stays")
	SlashCmdList.FREECONTROL("stance all")
	truthy(Printed("Changes with your stance or form: RT set, LT set and the D%-pad, on page 1%."), "the command says what changes now")
	M.RunDrivers()
	eq(Slots(0), "93 94 95 96 - - - -", "D-pad joins in")
	SlashCmdList.FREECONTROL("stance none")
	truthy(Printed("Changes with your stance or form: nothing%."), "and when nothing does")
	eq(#M.drivers, 0, "no driver is left behind")
	for set = 0, 3 do eq(Slots(set), CASTER[set], "everything back on its plain slot, set " .. set) end
	M.printed = {}
	SlashCmdList.FREECONTROL("stance sideways")
	eq(ns.db.stanceSet, "none", "a choice that does not exist changes nothing")
	truthy(Printed("/fc stance auto"), "and brings up the help")
end)

test("only D-pad buttons that are action slots change with the stance", function()
	local roles = { "cmd:TARGETNEARESTENEMY", "action", "action", "action", "action", "cmd:FREECONTROL_TOGGLECURSOR", "cmd:TOGGLEGAMEMENU", "cmd:JUMP" }
	Load({ stanceSet = "all", roles = roles })
	M.bonusbar = 1
	M.RunDrivers()
	eq(Slots(0), "- 82 83 84 261 - - -", "D-pad Left runs a command and X is a plain slot; neither changes")
	eq(Binding("PADDLEFT"), "cmd:TARGETNEARESTENEMY", "the command button still runs its command")
end)

test("a Druid is told once which buttons change with the form", function()
	M.class = "DRUID"
	Load()
	truthy(Printed("Druid: RT set, LT set and the D%-pad change with your form on page 1"), "said at the first login on a Druid")
	truthy(Printed("The LT %+ RT set, the face buttons and the other pages stay the same in every form"), "with where to put the shapeshifts")
	M.printed = {}
	M.Fire("PLAYER_LOGIN")
	eq(Printed("Druid"), false, "only once")
end)

test("a Druid who chose the changing sets by hand is not told what automatic does", function()
	M.class = "DRUID"
	Load({ stanceSet = "all" })
	eq(Printed("Druid"), false, "nothing said")
	eq(ns.db.stanceNoteShown, false, "and it is kept for when they go back to automatic")
	SlashCmdList.FREECONTROL("stance rt")
	M.bonusbar = 1
	M.RunDrivers()
	eq(Slots(2), "265 266 267 268 269 270 271 272", "the one set they chose changes")
	eq(Slots(1), CASTER[1], "and the left set does not, Druid or not")
	eq(Slots(0), CASTER[0], "nor the D-pad")
end)

test("the settings page offers every stance choice", function()
	Load()
	local panel = ns.Options.panel
	Open(panel)
	local button
	for _, frame in ipairs(M.all) do
		if frame:GetText() == "Automatic" then button = frame end
	end
	truthy(button, "the button showing the current choice")
	local seen, labels = {}, {}
	for _ = 1, #ns.Layout.STANCE_CHOICES do
		button:GetScript("OnClick")(button)
		seen[#seen + 1] = ns.db.stanceSet
		labels[#labels + 1] = button:GetText()
	end
	eq(table.concat(seen, " "), "none lt rt both ltrt all auto", "stepping through them reaches every choice the addon accepts")
	eq(table.concat(labels, " | "), "Nothing | Left trigger set | Right trigger set | Both triggers set | Left and right sets | Left, right and D-pad | Automatic", "each with a name")
end)

test("settings changed in combat wait for the fight to end", function()
	Load()
	M.EnterCombat()
	ns.db.roles[6] = "cmd:TARGETNEARESTENEMY"
	eq(ns.RequestRefresh(), false, "queued")
	eq(Binding("PAD4"), "click:FreeControlMouse", "not applied yet")
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

test("with the regular action bars as the slots, automatic leaves every stance alone", function()
	M.class = "DRUID"
	Load({ slotSource = "bars" })
	eq(#ns.Layout.GetStanceGroups(), 0, "nothing changes with the stance")
	eq(#M.drivers, 0, "no drivers")
	M.ShapeshiftTo("Cat Form")
	eq(Slots(1), "61 62 63 64 65 66 67 68", "the left set stays on the Bottom Left bar")
	eq(Slots(0), "37 38 39 40 - - - -", "and the D-pad on the Left bar")
	eq(Printed("Druid:"), false, "and a Druid is not told otherwise")
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Changes with your stance or form %(setting: auto%): nothing"), "status says so")
end)

test("with the regular action bars as the slots, a set asked for by hand changes, and the D-pad can join it", function()
	Load({ slotSource = "bars", stanceSet = "rt" })
	M.EnterCombat()
	M.ShapeshiftTo("Stealth")
	eq(Slots(2), "73 74 75 76 77 78 79 80", "the right set shows the first eight slots the game's own bar has in the stance")
	eq(Slots(1), "61 62 63 64 65 66 67 68", "the left set stays")
	M.KeyDown("PADRTRIGGER")
	M.Tap("PAD1")
	M.KeyUp("PADRTRIGGER")
	eq(Used(), "80", "and the key casts from there")
	M.ShapeshiftTo(nil)
	eq(Slots(2), "49 50 51 52 53 54 55 56", "back on the Bottom Right bar outside the stance")
	M.LeaveCombat()
	SlashCmdList.FREECONTROL("stance all")
	truthy(Printed("Changes with your stance or form: RT set and the D%-pad%."), "one set and the D-pad: there is nowhere to keep a second set, and no page to name")
	M.ShapeshiftTo("Stealth")
	eq(Slots(2), "73 74 75 76 77 78 79 80", "the set")
	eq(Slots(0), "81 82 83 84 - - - -", "and the D-pad: the last four of the twelve")
	eq(Slots(1), "61 62 63 64 65 66 67 68", "the other trigger set has nowhere to keep a stance's actions, and stays")
end)

test("a client without the controller's stance bars still changes one set, kept in the game's own stance slots", function()
	M.lastGamepadSlot = 264
	Load({ stanceSet = "lt" })
	eq(ns.Layout.HasGamepadSlots(), true, "pages usable")
	eq(ns.Layout.HasStanceSlots(), false, "stance bars not")
	M.ShapeshiftTo("Stealth")
	eq(Slots(1), "73 74 75 76 77 78 79 80", "the set changes, in the regular action bar's slots for the stance")
	eq(Slots(2), "193 194 195 196 197 198 199 200", "the other set does not")
	SlashCmdList.FREECONTROL("stance all")
	eq(Slots(2), "73 74 75 76 77 78 79 80", "asked for everything: the first set takes those slots")
	eq(Slots(0), "81 82 83 84 - - - -", "the D-pad the last four")
	eq(Slots(1), "185 186 187 188 189 190 191 192", "and the second set, with nowhere to go, stays")
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
	Open(panel)
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

test("status says so when a trigger is still the game's mouse-click button", function()
	Load()
	eq(Problem("mouse%-click button"), false, "not by default: FreeControl moves the clicks to the stick clicks")
	SlashCmdList.FREECONTROL("click left game")
	eq(M.cvars.GamePadCursorLeftClick, "PADRTRIGGER", "left to the game, the client's own RT is back")
	truthy(Problem("PADRTRIGGER is also the controller's mouse%-click button"), "and status points it out")
end)

test("saved settings that make no sense are replaced by defaults", function()
	Load({ page = 9, scale = "big", roles = { "action", "action", "action", "action", "explode" }, keys = { 5 }, stanceSet = "every" })
	eq(ns.db.stanceSet, "auto", "stance sets")
	eq(ns.db.page, 1, "page")
	eq(ns.db.scale, 1, "scale")
	eq(ns.db.roles[5], "cmd:INTERACTTARGET", "role")
	eq(ns.db.keys[1], "PADDLEFT", "key")
end)

test("pressing Y while playing with the controller brings out a pointer that can be seen", function()
	Load()
	M.Tap("PADDUP") -- the player has been using the controller: the client is in camera mode
	eq(M.freeLook, true, "camera mode, in which the pointer is hidden")
	M.Tap("PAD4")
	eq(M.cursorControl, true, "the stick steers the pointer")
	eq(M.freeLook, false, "and camera mode was ended, which 1.2.0 did not do")
	eq(table.concat(M.pointerCalls, ", "), "camera false, pointer true", "in that order")
	eq(M.PointerVisible(), true, "so the pointer is there to see")
	M.pointerCalls = {}
	M.Tap("PAD4")
	eq(M.cursorControl, false, "pressed again: the pointer is away")
	eq(M.freeLook, true, "and the right stick is the camera's again at once")
	eq(table.concat(M.pointerCalls, ", "), "pointer false, camera true", "in the reverse order")
end)

test("switching FreeControl off forgets a request the game had not answered", function()
	Load()
	M.refuseCursor = 1
	M.Tap("PAD4")
	SlashCmdList.FREECONTROL("off")
	M.Advance(1)
	SlashCmdList.FREECONTROL("on")
	M.Advance(1)
	eq(M.cursorControl, false, "no pointer pops out later")
	eq(ns.Mouse:GetHistory().retried, 0, "because nothing was asked a second time")
end)

test("the mouse button acts once for a press, however long it is held", function()
	Load()
	local button = M.frames.FreeControlMouse
	eq(button.__clicks.down and button.__clicks.up, true, "it hears the press and the release, as the triggers do")
	M.KeyDown("PAD4")
	eq(M.PointerVisible(), true, "out on the press")
	M.Advance(0.5)
	M.KeyUp("PAD4")
	eq(M.PointerVisible(), true, "and the release does not put it away again")
	eq(Binding("PADLSTICK"), "cmd:CAMERAORSELECTORMOVE", "nor undo the click buttons")
	eq(ns.Mouse:GetHistory().presses, 1, "one press counted")
end)

test("the Key Bindings screen gets the two page buttons and nothing else", function()
	Load()
	eq(BINDING_NAME_FREECONTROL_TOGGLECURSOR, nil, "no binding for the mouse button: the addon binds that itself")
	eq(ns.ToggleCursor, nil, "and no function for one to call")
	local names = {}
	for name in ReadFile("FreeControl/Bindings.xml"):gmatch('<Binding name="([^"]+)"') do
		names[#names + 1] = name
		truthy(M.frames[name:match("^CLICK (%w+):LeftButton$")], "a click on a button that exists: " .. name)
		truthy(_G["BINDING_NAME_" .. name], "with a name to show: " .. name)
	end
	table.sort(names)
	eq(table.concat(names, " | "), "CLICK FreeControlPageNext:LeftButton | CLICK FreeControlPagePrev:LeftButton", "exactly the two page buttons")
	eq(GetBindingName(ns.Bindings.PAGE_COMMANDS.next), "FreeControl: next page", "named")
	eq(GetBindingName(ns.Bindings.PAGE_COMMANDS.prev), "FreeControl: previous page", "both of them")
end)

test("/fc mouse typed with a real mouse in hand does not throw the game into camera mode", function()
	Load()
	SlashCmdList.FREECONTROL("mouse")
	eq(M.PointerVisible(), true, "out")
	M.Advance(0.02)
	eq(Binding("PADLSTICK"), "cmd:CAMERAORSELECTORMOVE", "the clicks follow")
	SlashCmdList.FREECONTROL("mouse")
	eq(M.cursorControl, false, "away")
	eq(M.freeLook, false, "without handing the camera to a controller nobody is holding")
	M.Advance(0.02)
	eq(Binding("PADLSTICK"), nil, "and the clicks are handed back")
end)

test("a request the game ignores is made once more", function()
	Load()
	M.refuseCursor = 1
	M.Tap("PAD4")
	eq(M.cursorControl, false, "ignored the first time")
	M.Advance(0.2)
	eq(M.cursorControl, false, "given a moment")
	M.Advance(0.3)
	eq(M.PointerVisible(), true, "asked again, and this time it came")
	M.Advance(0.02)
	local history = ns.Mouse:GetHistory()
	eq(history.retried, 1, "noted")
	eq(history.came, 1, "as having come out")
	eq(history.last, "came out on the second request", "in words")
	eq(Printed("did not bring"), false, "and nothing to complain about")
	M.Advance(2)
	eq(history.asked, 1, "nothing is asked for again once it is out")
end)

test("if the game never brings the pointer out, that is said once and the click buttons are handed back", function()
	Load()
	M.refuseCursor = 99
	M.Tap("PAD4")
	eq(Binding("PADLSTICK"), "cmd:CAMERAORSELECTORMOVE", "the press bound the click buttons")
	M.Advance(0.5)
	M.Advance(0.5)
	eq(M.cursorControl, false, "still no pointer")
	truthy(Printed("The game did not bring the mouse pointer out%. Type /fc status"), "said, with what to do")
	eq(Binding("PADLSTICK"), nil, "and the stick clicks are the player's own again")
	eq(ns.Mouse:GetHistory().refused, 1, "counted")
	local lines = #M.printed
	M.Tap("PAD4")
	M.Advance(0.5)
	M.Advance(0.5)
	eq(#M.printed, lines, "not said a second time")
	eq(ns.Mouse:GetHistory().refused, 2, "though it is counted")
	M.Advance(5)
	eq(ns.Mouse:GetHistory().asked, 2, "and it does not keep asking")
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("mouse button pressed 2 times, pointer asked for 2 times, came out 0, needed a second request 2, never came 2%. Last: the game did not bring it out"), "status has the whole story")
end)

test("a pointer the player puts away before the game answered is not asked for again", function()
	Load()
	M.refuseCursor = 1
	M.Tap("PAD4")
	SlashCmdList.FREECONTROL("mouse") -- the pointer is not out, so this asks for it too
	eq(M.cursorControl, true, "out")
	SlashCmdList.FREECONTROL("mouse")
	eq(M.cursorControl, false, "away")
	M.Advance(1)
	eq(M.cursorControl, false, "and it stays away")
	eq(ns.Mouse:GetHistory().retried, 0, "no second request for something that was taken back")
end)

test("a client that cannot say whether it is in camera mode still gets its pointer", function()
	SetGamePadFreeLook, IsGamePadFreelookEnabled, IsUsingGamepad, IsUsingMouse = nil, nil, nil, nil
	Load()
	M.Tap("PAD4")
	eq(M.cursorControl, true, "out")
	M.Advance(0.02)
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Controller steers the camera: this client does not say%. Using the controller: this client does not say"), "and status says what it cannot know")
	M.Tap("PAD4")
	eq(M.cursorControl, false, "away")
end)

local function Clicks()
	local out = {}
	for i, click in ipairs(M.clicks) do out[i] = click[1] .. "/" .. click[2] end
	return table.concat(out, ",")
end

local function Commands()
	local out = {}
	for i, command in ipairs(M.commands) do out[i] = command[1] .. "/" .. command[2] end
	return table.concat(out, ",")
end

local OLD_ROLES = { "action", "action", "action", "action", "cmd:INTERACTTARGET", "pass", "cmd:TOGGLEGAMEMENU", "cmd:JUMP" }

-- A setup saved by a version before 1.3, in which Y was left to the player's own key binding.
local function OldSetup(more)
	local saved = { introShown = true, roles = { unpack(OLD_ROLES) } }
	for key, value in pairs(more or {}) do saved[key] = value end
	return saved
end

-- A setup in which the player has taken the mouse button off the bar again, after being given it.
local function NoMouseButton(more)
	local saved = OldSetup(more)
	saved.mouseStep = 2
	return saved
end

test("a new setup has the mouse pointer on Y", function()
	Load()
	eq(ns.db.roles[6], "cmd:FREECONTROL_TOGGLECURSOR", "new setup")
	eq(ns.Mouse:GetBarButtonName(), "Y", "found by name")
	eq(Printed("New:"), false, "and it is not told what is new")
end)

test("a setup from before 1.3 gets the mouse button on Y, bound by the addon, and is told once", function()
	M.userBindings = { PAD4 = "FREECONTROL_TOGGLECURSOR" } -- what 1.2 asked the player to set up
	Load(OldSetup({ mouseTipShown = true }))
	eq(ns.db.mouseTipShown, nil, "a leftover of 1.2 is cleared out of the saved settings")
	eq(ns.db.roles[6], "cmd:FREECONTROL_TOGGLECURSOR", "Y is the mouse button now")
	eq(Binding("PAD4"), "click:FreeControlMouse", "and FreeControl binds it, over whatever was there")
	truthy(Printed("New: Y is now the mouse button%. Press it and the right stick steers a mouse pointer; Left stick click is the left click and Right stick click is the right click"), "told what it does")
	truthy(Printed("To give Y another job, click it on the bar"), "and how to undo it")
	M.Tap("PAD4")
	eq(M.PointerVisible(), true, "it works straight away")
	M.Tap("PAD4")
	local saved = FreeControlDB
	M.printed = {}
	saved.roles[6] = "pass" -- the player takes it off again
	M.Fire("ADDON_LOADED", "FreeControl")
	M.Fire("PLAYER_LOGIN")
	eq(saved.roles[6], "pass", "which is respected from then on")
	eq(Printed("New:"), false, "and nothing is said again")
end)

test("a Y that had another job becomes the mouse button too, once, and chat says what it was", function()
	local roles = { unpack(OLD_ROLES) }
	roles[6] = "cmd:TARGETNEARESTENEMY"
	Load(OldSetup({ roles = roles }))
	eq(ns.db.roles[6], "cmd:FREECONTROL_TOGGLECURSOR", "Y is the mouse button")
	eq(Binding("PAD4"), "click:FreeControlMouse", "and is bound as one")
	truthy(Printed("New: Y is now the mouse button%. Press it and the right stick steers a mouse pointer"), "told")
	truthy(Printed("It was \"Target nearest enemy\" before: to put that back, click Y on the bar%."), "with what it was and how to get it back")
	local saved = FreeControlDB
	M.printed = {}
	saved.roles[6] = "cmd:TARGETNEARESTENEMY" -- the player puts it back
	M.Fire("ADDON_LOADED", "FreeControl")
	M.Fire("PLAYER_LOGIN")
	eq(saved.roles[6], "cmd:TARGETNEARESTENEMY", "and from then on their choice stands")
	eq(Printed("New:"), false, "with nothing more said")
end)

test("a Y that was an action slot becomes the mouse button, and what was in the slot is kept", function()
	local roles = { unpack(OLD_ROLES) }
	roles[6] = "action"
	M.actions[262] = { texture = "icon" } -- the slot Y borrows on page 1
	Load(OldSetup({ roles = roles }))
	eq(ns.db.roles[6], "cmd:FREECONTROL_TOGGLECURSOR", "Y is the mouse button")
	truthy(Printed("It was an action slot before, and what was in it is still there: to put that back, click Y on the bar%."), "told")
	eq(#M.picked + #M.placed, 0, "nothing was moved out of the slot")
	ns.db.roles[6] = "action"
	ns.RequestRefresh()
	eq(ns.Buttons:GetSlot(0, 6), 262, "switched back, it shows the same slot")
	eq(M.frames.FreeControlButton0_6.fc.hasAction, true, "with its action")
end)

test("a setup that 1.3.0 left without a mouse button, because Y had a job, gets one now", function()
	local roles = { unpack(OLD_ROLES) }
	roles[6] = "cmd:OPENALLBAGS"
	Load(OldSetup({ roles = roles, mouseButtonSet = true, mouseNews = "taken" })) -- as 1.3.0 saved it
	eq(ns.db.roles[6], "cmd:FREECONTROL_TOGGLECURSOR", "Y is the mouse button")
	truthy(Printed("It was \"Bags\" before"), "and chat says what it was")
	eq(ns.db.mouseButtonSet, nil, "1.3.0's own note is cleared out of the saved settings")
end)

test("news that 1.3.0 had not said yet is still said", function()
	M.gamepadUI = true
	Load({ introShown = true, mouseButtonSet = true, mouseNews = "given" }) -- 1.3.0 gave Y the job with the Gamepad UI on
	eq(Printed("New:"), false, "not while FreeControl is idle")
	M.gamepadUI = false
	M.Fire("ADDON_LOADED", "FreeControl")
	M.Fire("PLAYER_LOGIN")
	truthy(Printed("New: Y is now the mouse button.*To give Y another job, click it on the bar%."), "said once FreeControl is in use")
end)

test("a setup from before 1.3 that has the mouse button on another button is left alone", function()
	local roles = { unpack(OLD_ROLES) }
	roles[5] = "cmd:FREECONTROL_TOGGLECURSOR"
	Load(OldSetup({ roles = roles }))
	eq(ns.db.roles[6], "pass", "Y untouched")
	eq(ns.Mouse:GetBarButtonName(), "X", "the player's own choice stands")
	eq(Printed("New:"), false, "nothing to say")
end)

test("a setup from before 1.3 on a client with no stick pointer is told nothing about mouse mode", function()
	SetGamePadCursorControl, IsGamePadCursorControlEnabled = nil, nil
	Load(OldSetup())
	eq(Printed("New:"), false, "there is no mouse mode to announce")
	eq(Binding("PAD4"), nil, "and Y is still the player's own")
end)

test("a player who took the mouse button off the bar is left without one, and status says so", function()
	Load(NoMouseButton())
	eq(ns.db.roles[6], "pass", "untouched")
	eq(Binding("PAD4"), nil, "Y unbound by us")
	eq(ns.Mouse:GetBarButtonName(), nil, "so no button brings the pointer out")
	truthy(Problem("No button brings the mouse pointer out"), "which status points out")
end)

test("the stick clicks become the game's mouse-click buttons, and the player's own are put back", function()
	Load()
	eq(M.cvars.GamePadCursorLeftClick, "PADLSTICK", "left click")
	eq(M.cvars.GamePadCursorRightClick, "PADRSTICK", "right click")
	SlashCmdList.FREECONTROL("off")
	eq(M.cvars.GamePadCursorLeftClick, "PADRTRIGGER", "the client's own left click is back")
	eq(M.cvars.GamePadCursorRightClick, "PADRSHOULDER", "and its right click")
	SlashCmdList.FREECONTROL("on")
	eq(M.cvars.GamePadCursorLeftClick, "PADLSTICK", "ours again")
	M.Fire("PLAYER_LOGOUT")
	eq(M.cvars.GamePadCursorLeftClick, "PADRTRIGGER", "and restored at logout")
	eq(M.cvars.GamePadCursorRightClick, "PADRSHOULDER", "both")
end)

test("Y brings the mouse pointer out, the stick clicks click windows and the world, Y puts it away", function()
	Load()
	eq(Binding("PADLSTICK"), nil, "the left stick click is the player's own while the pointer is away")
	eq(M.Tap("PADLSTICK"), "unbound", "so a press goes to their binding, not to us")
	M.Tap("PAD4")
	eq(M.PointerVisible(), true, "pointer out")
	eq(Binding("PADLSTICK"), "cmd:CAMERAORSELECTORMOVE", "left stick click runs the left mouse button's command")
	eq(Binding("PADRSTICK"), "cmd:TURNORACTION", "right stick click runs the right mouse button's")
	M.Tap("PADLSTICK") -- the pointer is over a window
	M.Tap("PADRSTICK")
	eq(Clicks(), "LeftButton/down,LeftButton/up,RightButton/down,RightButton/up", "real clicks on a window")
	eq(Commands(), "", "and nothing else ran")
	M.cursorOver = "world"
	M.Tap("PADLSTICK")
	M.Tap("PADRSTICK")
	eq(Commands(), "CAMERAORSELECTORMOVE/down,CAMERAORSELECTORMOVE/up,TURNORACTION/down,TURNORACTION/up", "the mouse commands on the world")
	M.Tap("PAD4")
	eq(M.cursorControl, false, "pointer away")
	eq(Binding("PADLSTICK"), nil, "stick clicks handed back")
	eq(Binding("PADRSTICK"), nil, "both of them")
	M.clicks = {}
	eq(M.Tap("PADLSTICK"), "unbound", "and a press is the player's own again")
	eq(Clicks(), "", "not a click")
end)

test("in a fight the mouse button still brings the pointer out and rebinds the clicks", function()
	Load()
	M.EnterCombat()
	M.Tap("PADDUP")
	M.Tap("PAD4")
	eq(M.PointerVisible(), true, "pointer out")
	eq(Binding("PADLSTICK"), "cmd:CAMERAORSELECTORMOVE", "left click bound by the secure button")
	M.Advance(0.1)
	M.KeyDown("PADRTRIGGER")
	eq(ns.Bindings:GetActiveSet(), 2, "RT still selects its set while the cursor is out")
	eq(Binding("PADLSTICK"), "cmd:CAMERAORSELECTORMOVE", "and the clicks survive a set change")
	M.KeyUp("PADRTRIGGER")
	eq(M.PointerVisible(), true, "a trigger does not send the pointer away")
	M.Tap("PAD4")
	eq(M.cursorControl, false, "pointer away")
	eq(Binding("PADLSTICK"), nil, "clicks handed back")
	M.LeaveCombat()
end)

test("when the game brings the pointer out or puts it away by itself, the clicks follow", function()
	Load()
	M.GameShowsPointer() -- a window opened
	M.Advance(0.02)
	eq(Binding("PADRSTICK"), "cmd:TURNORACTION", "bound once the pointer is seen to be out")
	M.GameHidesPointer() -- the character jumped
	M.Advance(0.02)
	eq(Binding("PADRSTICK"), nil, "and handed back when it is gone")
	eq(ns.Mouse:GetHistory().asked, 0, "none of which FreeControl asked for")
end)

test("a pointer the game brings out in a fight gets its world clicks when the fight ends", function()
	Load()
	M.EnterCombat()
	M.GameShowsPointer()
	M.Advance(0.02)
	eq(Binding("PADLSTICK"), nil, "bindings cannot be changed from ordinary code in a fight")
	M.Tap("PADLSTICK")
	eq(Clicks(), "LeftButton/down,LeftButton/up", "windows can be clicked all the same: that part is the game's own doing")
	M.LeaveCombat()
	eq(Binding("PADLSTICK"), "cmd:CAMERAORSELECTORMOVE", "caught up")
end)

test("if the game puts the pointer away mid-fight, one press of the mouse button still brings it back", function()
	Load()
	M.EnterCombat()
	M.Tap("PAD4")
	M.Advance(0.02)
	M.GameHidesPointer() -- the character jumped
	M.Advance(0.02)
	M.Tap("PADDUP")
	M.Tap("PAD4")
	eq(M.PointerVisible(), true, "out again on the first press")
	M.Advance(0.02)
	M.LeaveCombat()
	eq(Binding("PADLSTICK"), "cmd:CAMERAORSELECTORMOVE", "and the world clicks are right once the fight is over")
	M.Tap("PAD4")
	eq(M.cursorControl, false, "away")
	eq(Binding("PADLSTICK"), nil, "everything handed back")
end)

test("the mouse button on the bar is lit while the pointer is out, whoever brought it out", function()
	Load()
	local lit = ns.Buttons.role[6].fc.lit
	eq(lit:GetAlpha(), 0, "dark while the pointer is away")
	M.Tap("PAD4")
	M.Advance(0.02)
	eq(lit:GetAlpha(), 1, "lit")
	M.GameHidesPointer()
	M.Advance(0.02)
	eq(lit:GetAlpha(), 0, "dark again")
	M.GameShowsPointer()
	M.Advance(0.02)
	eq(lit:GetAlpha(), 1, "lit when the game brings it out")
	ns.db.roles[6] = "cmd:JUMP"
	ns.RequestRefresh()
	eq(lit:GetAlpha(), 0, "a button that is no longer the mouse button is not lit")
end)

test("the first time the pointer comes out chat explains the clicks, and only that once", function()
	Load()
	M.Tap("PAD4")
	M.Advance(0.02)
	truthy(Printed("Mouse pointer out%. The right stick moves it; Left stick click is the left click and Right stick click is the right click%. Press Y again to put it away; jumping puts it away too"), "explained")
	local lines = #M.printed
	M.Tap("PAD4")
	M.Advance(0.02)
	M.Tap("PAD4")
	M.Advance(0.02)
	eq(#M.printed, lines, "not again")
	eq(ns.db.mouseHintShown, true, "and that is remembered between sessions")
end)

test("the click buttons can be changed and swapped, and a trigger is refused", function()
	Load()
	SlashCmdList.FREECONTROL("click left padlshoulder")
	eq(M.cvars.GamePadCursorLeftClick, "PADLSHOULDER", "left click on the left bumper")
	eq(M.cvars.GamePadEmulateCtrl, "none", "which therefore stops standing in for Ctrl")
	truthy(Printed("Mouse clicks: LB is the left click and Right stick click is the right click"), "confirmed in words")
	SlashCmdList.FREECONTROL("click right padlshoulder")
	eq(ns.db.clickRight, "PADLSHOULDER", "choosing the other click's button")
	eq(ns.db.clickLeft, "PADRSTICK", "swaps the two")
	SlashCmdList.FREECONTROL("click left padrtrigger")
	eq(ns.db.clickLeft, "PADRSTICK", "a trigger is refused")
	truthy(Printed("RT is a trigger, so it cannot also be a mouse click"), "with the reason")
	SlashCmdList.FREECONTROL("click left game")
	eq(M.cvars.GamePadCursorLeftClick, "PADRTRIGGER", "'game' gives that click back to the game")
	SlashCmdList.FREECONTROL("off")
	eq(M.cvars.GamePadEmulateCtrl, "PADLSHOULDER", "and switching off puts the Ctrl stand-in back")
end)

test("Y can be the left click instead: it clicks while the pointer is out and is a slot key otherwise", function()
	Load(NoMouseButton({ clickLeft = "PAD4" }))
	eq(M.cvars.GamePadCursorLeftClick, "PAD4", "the game is told")
	SlashCmdList.FREECONTROL("mouse")
	M.Advance(0.02)
	eq(Binding("PAD4"), "cmd:CAMERAORSELECTORMOVE", "Y is the left mouse button while the pointer is out")
	M.KeyDown("PADLTRIGGER")
	eq(Binding("PAD4"), "cmd:CAMERAORSELECTORMOVE", "with a trigger held too")
	M.KeyUp("PADLTRIGGER")
	SlashCmdList.FREECONTROL("mouse")
	M.Advance(0.02)
	eq(Binding("PAD4"), nil, "back to the player's own binding")
	M.KeyDown("PADLTRIGGER")
	eq(Binding("PAD4"), "click:FreeControlKey1_6", "and to its slot with a trigger held")
	M.KeyUp("PADLTRIGGER")
end)

test("click settings that make no sense fall back", function()
	Load({ clickLeft = 7, clickRight = "PADRTRIGGER" })
	eq(ns.db.clickLeft, "PADLSTICK", "nonsense becomes the default")
	eq(ns.db.clickRight, "game", "a trigger is left to the game")
	eq(M.cvars.GamePadCursorRightClick, "PADRSHOULDER", "whose own setting stands")
end)

test("a button made a trigger later stops being a click button, and status says so", function()
	Load()
	SlashCmdList.FREECONTROL("key lt padlstick")
	eq(Binding("PADLSTICK"), "click:FreeControlTrigger1", "the left stick click is the left trigger now")
	eq(M.cvars.GamePadCursorLeftClick, "PADRTRIGGER", "so the left click goes back to the game")
	truthy(Problem("PADLSTICK is a trigger, so it cannot also be the left mouse click"), "and status explains")
	M.Tap("PAD4")
	eq(Binding("PADLSTICK"), "click:FreeControlTrigger1", "still the trigger with the pointer out")
	eq(Binding("PADRSTICK"), "cmd:TURNORACTION", "while the right click works as before")
end)

test("two clicks saved on one button: the left keeps it", function()
	Load({ clickLeft = "PADRSTICK", clickRight = "PADRSTICK" })
	eq(ns.db.clickLeft, "PADRSTICK", "left click")
	eq(ns.db.clickRight, "game", "the right is left to the game")
end)

test("switching FreeControl off and on goes by where the pointer is at that moment", function()
	Load()
	local lit = ns.Buttons.role[6].fc.lit
	M.Tap("PAD4")
	M.Advance(0.02)
	SlashCmdList.FREECONTROL("off")
	eq(next(M.bindings), nil, "no bindings left while off")
	eq(lit:GetAlpha(), 0, "nothing lit")
	M.GameHidesPointer() -- the game puts the pointer away while FreeControl is off
	M.Advance(0.02)
	SlashCmdList.FREECONTROL("on")
	eq(Binding("PADLSTICK"), nil, "switched on with the pointer away: the stick clicks stay the player's own")
	SlashCmdList.FREECONTROL("off")
	M.GameShowsPointer() -- and brings it out again
	M.Advance(0.02)
	eq(next(M.bindings), nil, "the pointer is the game's own business while FreeControl is off")
	eq(lit:GetAlpha(), 0, "FreeControl does not even watch it then")
	SlashCmdList.FREECONTROL("on")
	eq(Binding("PADLSTICK"), "cmd:CAMERAORSELECTORMOVE", "switched on with the pointer out: the clicks are bound at once")
	eq(lit:GetAlpha(), 1, "and the button is lit")
end)

test("pointer speed scales the game's three cursor speed settings together, from the player's own values", function()
	M.cvars.GamePadCursorSpeedMax = "2" -- a player who had already made the cursor faster
	Load()
	eq(M.cvars.GamePadCursorSpeedStart, "0.1", "left alone at 100%")
	eq(M.cvars.GamePadCursorSpeedMax, "2", "including the player's own change")
	SlashCmdList.FREECONTROL("pointer 150")
	eq(ns.db.cursorSpeed, 1.5, "saved")
	eq(tonumber(M.cvars.GamePadCursorSpeedStart), 0.15, "start speed")
	eq(tonumber(M.cvars.GamePadCursorSpeedAccel), 3, "acceleration")
	eq(tonumber(M.cvars.GamePadCursorSpeedMax), 3, "top speed, from the player's 2")
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Pointer speed: 150%%"), "status shows it")
	SlashCmdList.FREECONTROL("pointer 50")
	eq(tonumber(M.cvars.GamePadCursorSpeedMax), 1, "worked out from the player's own value again, not from ours")
	SlashCmdList.FREECONTROL("pointer 1000")
	eq(ns.db.cursorSpeed, 3, "kept within range")
	SlashCmdList.FREECONTROL("pointer 100")
	eq(M.cvars.GamePadCursorSpeedMax, "2", "100% hands the settings back")
	eq(M.cvars.GamePadCursorSpeedStart, "0.1", "all of them")
	SlashCmdList.FREECONTROL("pointer 200")
	eq(tonumber(M.cvars.GamePadCursorSpeedAccel), 4, "doubled")
	M.Fire("PLAYER_LOGOUT")
	eq(M.cvars.GamePadCursorSpeedAccel, "2", "and logging out puts the player's own back")
end)

test("a saved pointer speed that makes no sense goes back to 100%", function()
	Load({ cursorSpeed = "fast" })
	eq(ns.db.cursorSpeed, 1, "reset")
	eq(M.cvars.GamePadCursorSpeedMax, "1", "and nothing is changed")
end)

test("a client without the stick pointer is left alone", function()
	SetGamePadCursorControl, IsGamePadCursorControlEnabled = nil, nil
	Load()
	eq(Binding("PAD4"), nil, "the mouse button is not bound to something that cannot work")
	eq(M.cvars.GamePadCursorCentering, "0", "and nothing about the pointer is changed")
	eq(ns.db.cvarApplied.GamePadCursorCentering, nil, "or even claimed")
	SlashCmdList.FREECONTROL("mouse")
	truthy(Printed("This client has no controller mouse pointer"), "the command says so")
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Mouse pointer: this client has no controller mouse pointer"), "and so does status")
	ns.db.roles[6] = "pass"
	ns.RequestRefresh()
	eq(Problem("No button brings"), false, "without complaining that no button brings it out")
	M.Advance(1)
	eq(Binding("PADLSTICK"), nil, "no click bindings")
end)

test("the game's setting that pins the pointer to the middle of the screen is switched off while active", function()
	M.cvars.GamePadCursorCentering = "1" -- left on by something else
	Load()
	eq(M.cvars.GamePadCursorCentering, "0", "off, so the stick can move the pointer")
	eq(Problem("GamePadCursorCentering"), false, "nothing to warn about")
	M.cvars.GamePadCursorCentering = "1" -- and if it is turned back on behind our back
	truthy(Problem("GamePadCursorCentering is on, which pins the mouse pointer"), "status says so")
	M.cvars.GamePadCursorCentering = "0"
	M.Fire("PLAYER_LOGOUT")
	eq(M.cvars.GamePadCursorCentering, "1", "and the player's own value is put back at logout")
end)

test("status and the mouse button's tooltip say which buttons click", function()
	Load()
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Mouse pointer: away%. Mouse button: Y %(PAD4%), bound right now to: CLICK FreeControlMouse:LeftButton%. Pointer speed: 100%%"), "state, button and what the button is bound to")
	truthy(Printed("Left click: PADLSTICK %(setting: PADLSTICK%), bound right now to: nothing"), "left click while away")
	truthy(Printed("The game says: stick steers the pointer: no%. Controller steers the camera: no%. Using the controller: no%. Using the mouse: no"), "what the game itself reports")
	truthy(Printed("Since login: mouse button pressed 0 times, pointer asked for 0 times, came out 0, needed a second request 0, never came 0%. Last: nothing yet"), "and what has happened so far")
	truthy(Printed("The game's own pointer settings: GamePadCursorAutoEnable = 1, GamePadCursorAutoDisableSticks = 2, GamePadCursorAutoDisableJump = 1, GamePadCursorCentering = 0, GamePadCursorCenteredEmulation = 1"), "with the settings that decide when the game hides it")
	M.printed = {}
	M.Tap("PAD4")
	M.Advance(0.02)
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Mouse pointer: out"), "out")
	truthy(Printed("Right click: PADRSTICK %(setting: PADRSTICK%), bound right now to: TURNORACTION"), "right click while out")
	truthy(Printed("The game says: stick steers the pointer: yes%. Controller steers the camera: no%. Using the controller: yes"), "the game's side of it")
	truthy(Printed("mouse button pressed 1 times, pointer asked for 1 times, came out 1, needed a second request 0, never came 0%. Last: came out"), "and the count")
	M.Tap("PAD4")
	M.printed = {}
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Last: put away"), "putting it away is the last thing that happened")
	local role = ns.Buttons.role[6]
	role:GetScript("OnEnter")(role)
	eq(GameTooltip.lines[2], "Mouse pointer on / off", "what the button does")
	truthy(GameTooltip.lines[3]:find("Press it to bring the mouse pointer out, and again to put it away%. The right stick moves the pointer; Left stick click is the left click and Right stick click is the right click"), "and which buttons click")
end)

test("status names the mouse button's own binding when FreeControl has none", function()
	Load(NoMouseButton())
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Mouse pointer: away%. Mouse button: none %(%-%), bound right now to: nothing"), "no button")
end)

test("status warns when the mouse button is also a click button", function()
	Load({ clickLeft = "PAD4" })
	truthy(Problem("Y is both the mouse button and a click button"), "warned")
end)

test("the settings page explains mouse mode and names the button that brings the pointer out", function()
	Load()
	local panel = ns.Options.panel
	Open(panel)
	local function PageSays(pattern)
		for _, text in ipairs(panel.__texts) do
			if (text:GetText() or ""):find(pattern) then return true end
		end
		return false
	end
	truthy(PageSays("^Mouse mode$"), "a heading")
	truthy(PageSays("^Left click$") and PageSays("^Right click$") and PageSays("^Pointer speed$"), "the two click buttons and the pointer speed")
	truthy(PageSays("Y brings the mouse pointer out and puts it away%. FreeControl binds it; there is nothing to set up%. While it is out, the right stick moves it and these two buttons click"), "the explanation")
	truthy(PageSays("^Stance sets$"), "and the stance choice is on the page under its new name")
	ns.db.roles[6] = "pass"
	ns.RequestRefresh()
	truthy(PageSays("No button brings the mouse pointer out%. Give one \"Mouse pointer on / off\" in the list on the right"), "and it says so when no button does")
	eq(PageSays("Key Bindings"), false, "without sending anyone to the Key Bindings screen")
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
	Open(panel)
	eq(ns.db.labelStyle, "auto", "starts on auto")
	ns.db.roles[6] = "pass"
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
	Load({ mouseStep = 2, roles = { [6] = "pass" } })
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
	Load({ mouseStep = 2, roles = { [6] = "pass" } })
	local role = ns.Buttons.role[6]
	role:GetScript("OnEnter")(role)
	eq(GameTooltip.lines[2], "Your own key binding: <TARGETNEARESTENEMY>", "names the binding")
	M.userBindings = nil
	role:GetScript("OnEnter")(role)
	truthy(GameTooltip.lines[2]:find("nothing is bound"), "says when nothing is bound")
end)

test("status reports the stance slots and agrees with the client", function()
	Load({ stanceSet = "rt" })
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("No stance or form bar is up right now"), "outside any stance")
	truthy(Printed("Stances or forms the game lists: Stealth%."), "the forms the game lists for the class")
	M.bonusbar = 3
	M.RunDrivers()
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Stance bar 3 is up%. The bar is following stance bar 3$"), "what the game says and what the secure code went by")
	truthy(Printed("Stance 3: its controller slots start at 281 %(the game says 281%)"), "the controller's stance slots")
	truthy(Printed("Stance 3: its regular action bar slots start at 97 %(the game says 97%)"), "and the regular bar's")
	eq(Printed("these differ"), false, "no mismatch")
	truthy(Printed("Page 1 of 3%. Class: ROGUE%. Changes with your stance or form %(setting: rt%): RT set, on page 1"), "names what changes, and where")
end)

test("status says which form the character is in, and flags a bar the secure code did not follow", function()
	M.class = "DRUID"
	Load()
	M.ShapeshiftTo("Cat Form")
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Stances or forms the game lists: Bear Form, Aquatic Form, Cat Form %(in it now%), Travel Form, Moonkin Form%."), "the list, with the one in use")
	truthy(Printed("Stance bar 1 is up%. The bar is following stance bar 1$"), "both agree")
	M.printed = {}
	M.bonusbar = 3 -- the game says another bar is up, but the macro condition was never looked at again
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Stance bar 3 is up%. The bar is following stance bar 1.*these differ, please report it"), "a stance the bar did not follow is flagged")
	M.printed = {}
	M.bonusbar = 6
	M.RunDrivers()
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("FreeControl has slots for stance bars 1 to 5 only, please report this one"), "and so is a stance bar there are no slots for")
	eq(Slots(2), "193 194 195 196 197 198 199 200", "for which the buttons keep their plain slots")
end)

test("a form with no bar of its own is listed, and changes nothing", function()
	M.class = "DRUID"
	Load()
	M.ShapeshiftTo("Travel Form")
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Travel Form %(in it now%)"), "status knows the form")
	truthy(Printed("No stance or form bar is up right now"), "and that it brings no bar")
	eq(Slots(1), "185 186 187 188 189 190 191 192", "the buttons stay as they are")
end)

test("status says so when the game keeps a stance's slots somewhere else", function()
	Load()
	M.bonusbar = 2
	C_ActionBar.GetBonusBarIndex = function() return 9 end -- a client that pages differently
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Stance 2: its regular action bar slots start at 85 %(the game says 97%).*these differ, please report it"), "flagged")
	eq(Printed("controller slots start at 273 %(the game says 273%).*these differ"), false, "the line that agrees is not")
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
	truthy(Printed("Y brings out a mouse pointer that the right stick steers; Left stick click is the left click"), "with the mouse button")
	eq(Printed("New:"), false, "and not the note meant for older setups")
	local saved = FreeControlDB
	M.printed = {}
	ns.db.roles[6] = "pass" -- a player who took the mouse button off the bar knows it is there
	M.Fire("ADDON_LOADED", "FreeControl")
	M.Fire("PLAYER_LOGIN")
	eq(Printed("Hold a trigger"), false, "not repeated")
	eq(Printed("mouse pointer"), false, "none of it")
	eq(Printed("New:"), false, "and no note meant for setups from before 1.3")
	eq(saved.roles[6], "pass", "and the button they took off the bar stays off")
	eq(saved.introShown, true, "remembered")
end)

test("what is new is not announced while the Gamepad UI is on, and is kept for the login after it", function()
	M.gamepadUI = true
	M.class = "DRUID"
	Load(OldSetup())
	eq(Printed("New:"), false, "the Gamepad UI line is all there is")
	eq(Printed("Druid"), false, "nothing about forms either")
	eq(ns.db.roles[6], "cmd:FREECONTROL_TOGGLECURSOR", "the button is ready for when FreeControl is used again")
	M.gamepadUI = false
	M.printed = {}
	M.Fire("ADDON_LOADED", "FreeControl")
	M.Fire("PLAYER_LOGIN")
	truthy(Printed("New: Y is now the mouse button"), "said at the first login with FreeControl in use")
	truthy(Printed("Druid: RT set, LT set and the D%-pad"), "with the Druid note")
	M.printed = {}
	M.Fire("ADDON_LOADED", "FreeControl")
	M.Fire("PLAYER_LOGIN")
	eq(#M.printed, 0, "and not after that")
end)

test("what is new is not announced while FreeControl is switched off", function()
	M.class = "DRUID"
	Load(OldSetup({ enabled = false }))
	eq(#M.printed, 0, "nothing at all is said")
	eq(ns.db.stanceNoteShown, false, "and the Druid note is kept for when it is switched on")
	eq(ns.db.mouseNews, "pass", "as is the news about the mouse button: what Y was before")
end)

test("a saved note that makes no sense is dropped", function()
	Load({ introShown = true, mouseStep = 2, mouseNews = "everything" })
	eq(ns.db.mouseNews, nil, "dropped")
	eq(Printed("New:"), false, "and nothing is said")
end)

test("a saved step that makes no sense is taken as not done", function()
	Load(OldSetup({ mouseStep = "done" }))
	eq(ns.db.mouseStep, 2, "worked out afresh")
	eq(ns.db.roles[6], "cmd:FREECONTROL_TOGGLECURSOR", "and Y is given the job")
end)

test("a command button on the D-pad shows the whole of its icon, ring and all", function()
	local roles = { "cmd:TARGETNEARESTENEMY", "action", "action", "action", "cmd:INTERACTTARGET", "cmd:FREECONTROL_TOGGLECURSOR", "cmd:TOGGLEGAMEMENU", "cmd:JUMP" }
	Load({ roles = roles })
	local function Shown(frame)
		local c = frame.fc.icon.calls.SetTexCoord
		return ("%.2f %.2f %.2f %.2f"):format(c[1], c[2], c[3], c[4])
	end
	eq(Shown(ns.Buttons.role[1]), "0.00 1.00 0.00 1.00", "a square command button: nothing trimmed, or its ring would be cut")
	eq(Shown(ns.Buttons.role[5]), "0.00 1.00 0.00 1.00", "a round one never was")
	eq(Shown(M.frames.FreeControlButton0_2), "0.07 0.93 0.07 0.93", "a square action slot still trims the border spell icons come with")
end)

test("a setup that was never logged into gets the mouse button without the note for older setups", function()
	Load({ roles = { unpack(OLD_ROLES) } }) -- saved by 1.1 while the Gamepad UI was on: never introduced
	eq(ns.db.roles[6], "cmd:FREECONTROL_TOGGLECURSOR", "Y is the mouse button")
	truthy(Printed("Hold a trigger"), "the first-login lines")
	truthy(Printed("Y brings out a mouse pointer"), "which cover the mouse button")
	eq(Printed("New:"), false, "so the note is not needed")
	M.printed = {}
	M.Fire("ADDON_LOADED", "FreeControl")
	M.Fire("PLAYER_LOGIN")
	eq(Printed("New:"), false, "at the next login either")
end)

test("the game refusing a call is kept for status, with which call it was", function()
	Load()
	M.Fire("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "CastSpellByName()")
	eq(#ns.GetProblems(), 0, "another addon's trouble is not ours")
	M.Fire("ADDON_ACTION_BLOCKED", "FreeControl", "SetGamePadCursorControl()")
	M.Fire("ADDON_ACTION_FORBIDDEN", "FreeControl", "SetGamePadCursorControl()")
	eq(#ns.GetProblems(), 1, "ours is kept")
	eq(ns.GetProblems()[1].count, 2, "and counted")
	truthy(Printed("Something went wrong inside FreeControl"), "said in chat the first time")
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("2 time%(s%): The game refused to let FreeControl call SetGamePadCursorControl%(%)"), "and status names the call")
	eq(#M.luaErrors, 0, "it is not a Lua error, so nothing goes to the error handler")
end)

---------------------------------------------------------------------------
-- The glow of a proc
---------------------------------------------------------------------------
local function Glowing(button)
	local fc = button.fc
	eq(fc.procPulse:IsPlaying(), fc.proc:GetAlpha() == 1, "the glow pulses exactly while it shows")
	return fc.proc:GetAlpha() == 1
end

-- Puts something in a slot the way the game reports it.
local function Fill(slot, action)
	M.actions[slot] = action
	M.Fire("ACTIONBAR_SLOT_CHANGED", slot)
end

test("a button glows while the game says its spell has procced, in a fight too", function()
	Load()
	Fill(185, { texture = "icon", spell = 5001 })
	Fill(186, { texture = "icon", spell = 5002 })
	local button, other = M.frames.FreeControlButton1_1, M.frames.FreeControlButton1_2
	eq(Glowing(button), false, "dark to begin with")
	truthy(button.fc.proc:GetTexture():find("Square%-Proc$"), "the glow of a square button")
	truthy(M.frames.FreeControlButton1_5.fc.proc:GetTexture():find("Round%-Proc$"), "and of a round one")
	M.EnterCombat()
	M.Proc(5001, true)
	eq(Glowing(button), true, "glows when the game says so")
	eq(Glowing(other), false, "and only the button with that spell")
	M.Proc(5002, true)
	eq(Glowing(other), true, "a second proc glows as well")
	M.Proc(5001, false)
	eq(Glowing(button), false, "and stops when the game says it is over")
	eq(Glowing(other), true, "leaving the other alone")
	M.LeaveCombat()
end)

test("a procced spell dropped on a slot glows at once, and taking it away ends the glow", function()
	Load()
	M.overlayed[5001] = true
	local button = M.frames.FreeControlButton1_1
	Fill(185, { texture = "icon", spell = 5001 })
	eq(Glowing(button), true, "glows as soon as it is there")
	Fill(185, { texture = "icon", spell = 5002 })
	eq(Glowing(button), false, "another spell in the slot does not")
	Fill(185, { texture = "icon", spell = 5001 })
	eq(Glowing(button), true, "back again")
	Fill(185, nil)
	eq(Glowing(button), false, "an empty slot is dark")
end)

test("a macro that casts the spell glows, and an item never does", function()
	Load()
	Fill(185, { texture = "icon", macro = 4, macroSpell = 5001 })
	Fill(186, { texture = "icon", item = 5001 })
	Fill(187, { texture = "icon", macro = 5001 })
	M.Proc(5001, true)
	eq(Glowing(M.frames.FreeControlButton1_1), true, "the macro's spell")
	eq(Glowing(M.frames.FreeControlButton1_2), false, "an item that happens to have the spell's number")
	eq(Glowing(M.frames.FreeControlButton1_3), false, "nor a macro that happens to")
end)

test("the glow can be switched off, and status says what is glowing", function()
	Load()
	Fill(185, { texture = "icon", spell = 5001 })
	M.Proc(5001, true)
	local button = M.frames.FreeControlButton1_1
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Proc glow: yes %(the game's proc signal is there: yes%)%. Glowing right now: LT %+ D%-pad Left"), "status names the button")
	SlashCmdList.FREECONTROL("glow off")
	eq(ns.db.procGlow, false, "saved")
	eq(Glowing(button), false, "dark")
	M.Proc(5001, false)
	M.Proc(5001, true)
	eq(Glowing(button), false, "and it stays dark")
	M.printed = {}
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Proc glow: no .*Glowing right now: nothing"), "status says so")
	SlashCmdList.FREECONTROL("glow on")
	eq(Glowing(button), true, "switched on again, it picks up the proc that is still running")
end)

test("on a client that seals what is in a slot, nothing glows in a fight and nothing fails", function()
	M.sealActionInfo = true
	Load()
	Fill(185, { texture = "icon", spell = 5001 })
	local button = M.frames.FreeControlButton1_1
	M.EnterCombat()
	M.Fire("ACTIONBAR_SLOT_CHANGED", 185)
	M.Proc(5001, true)
	eq(Glowing(button), false, "the spell cannot be read, so it is not asked about")
	M.LeaveCombat()
	M.Fire("ACTIONBAR_SLOT_CHANGED", 185)
	eq(Glowing(button), true, "once it can be read the glow is there")
end)

test("a client without the proc signal gets no glow from it, and no errors", function()
	C_SpellActivationOverlay = nil
	Load()
	Fill(185, { texture = "icon", spell = 5001 })
	M.Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 5001)
	eq(Glowing(M.frames.FreeControlButton1_1), false, "nothing to ask")
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("the game's proc signal is there: no"), "and status says why")
end)

-- An ability that cannot be used until something has happened.
local function Reactive(slot, name, spell)
	M.spellNames[spell] = name
	Fill(slot, { texture = "icon", spell = spell, usable = false })
end

local function ComeFree(slot)
	M.actions[slot].usable, M.actions[slot].noMana = true, nil
	M.Fire("ACTIONBAR_UPDATE_USABLE")
end

local function TakenBack(slot)
	M.actions[slot].usable, M.actions[slot].noMana = false, nil
	M.Fire("ACTIONBAR_UPDATE_USABLE")
end

test("an ability that comes free for a moment glows until the game takes it back", function()
	Load()
	Reactive(185, "Overpower", 7384)
	Reactive(186, "Eviscerate", 2098) -- unusable without combo points, but not one of these
	local button, finisher = M.frames.FreeControlButton1_1, M.frames.FreeControlButton1_2
	eq(Glowing(button), false, "dark while it cannot be used")
	M.EnterCombat()
	ComeFree(185)
	eq(Glowing(button), true, "glows when the target dodges and it comes free")
	ComeFree(186)
	eq(Glowing(finisher), false, "an ordinary ability becoming usable does not")
	TakenBack(185)
	eq(Glowing(button), false, "and stops when the moment has passed")
	ComeFree(185)
	eq(Glowing(button), true, "the next time, again")
	M.LeaveCombat()
end)

test("an ability that was usable when first seen does not glow: nothing has just happened", function()
	Load()
	M.spellNames[7384] = "Overpower"
	Fill(185, { texture = "icon", spell = 7384 })
	local button = M.frames.FreeControlButton1_1
	eq(Glowing(button), false, "no glow at login")
	M.Fire("ACTIONBAR_UPDATE_USABLE")
	eq(Glowing(button), false, "nor at the next look")
end)

test("an ability that comes free while there is no rage for it glows once there is", function()
	Load()
	Reactive(185, "Overpower", 7384)
	local button = M.frames.FreeControlButton1_1
	M.actions[185].noMana = true -- free, but not enough rage: the game reports that instead
	M.Fire("ACTIONBAR_UPDATE_USABLE")
	eq(Glowing(button), false, "not while it still cannot be pressed")
	ComeFree(185)
	eq(Glowing(button), true, "as soon as it can")
	M.Advance(15)
	M.actions[185].usable, M.actions[185].noMana = false, true
	M.Fire("ACTIONBAR_UPDATE_USABLE")
	eq(Glowing(button), false, "dark again when the rage is spent")
	ComeFree(185)
	eq(Glowing(button), true, "and back while the moment lasts")
	M.Advance(5.5)
	eq(Glowing(button), false, "which is counted from when it came free, not from when the rage came back")
end)

test("the glow of an ability that came free ends by itself after twenty seconds", function()
	Load()
	Reactive(185, "Victory Rush", 34428)
	local button = M.frames.FreeControlButton1_1
	ComeFree(185)
	eq(Glowing(button), true, "glowing")
	M.Advance(19)
	eq(Glowing(button), true, "still, a second before")
	M.Advance(1.1)
	eq(Glowing(button), false, "and over, though the game never said so")
	M.Fire("ACTIONBAR_UPDATE_USABLE")
	eq(Glowing(button), false, "and it stays over while the ability stays usable")
	TakenBack(185)
	ComeFree(185)
	eq(Glowing(button), true, "until it comes free afresh")
end)

test("a redraw in the middle of the moment does not end the glow, another spell in the slot does", function()
	Load()
	Reactive(185, "Riposte", 14251)
	local button = M.frames.FreeControlButton1_1
	ComeFree(185)
	M.Fire("SPELL_UPDATE_ICON")
	M.Fire("ACTIONBAR_SLOT_CHANGED", 0)
	eq(Glowing(button), true, "still glowing after everything was redrawn")
	Fill(185, { texture = "icon", spell = 5002 })
	eq(Glowing(button), false, "a different spell starts from nothing")
	M.spellNames[14251] = "Riposte"
	Fill(185, { texture = "icon", spell = 14251 })
	eq(Glowing(button), false, "and so does the same one, put back while usable")
end)

test("an ability that is always usable from stealth glows only when it comes free outside it", function()
	Load()
	Reactive(185, "Ambush", 8676)
	local button = M.frames.FreeControlButton1_1
	M.stealthed = true
	ComeFree(185)
	eq(Glowing(button), false, "usable because of stealth: nothing to point out")
	M.stealthed = false
	TakenBack(185)
	ComeFree(185)
	eq(Glowing(button), true, "usable in the open: that is the proc")
end)

test("abilities that come free do not glow with the glow switched off", function()
	Load({ procGlow = false })
	Reactive(185, "Overpower", 7384)
	ComeFree(185)
	eq(Glowing(M.frames.FreeControlButton1_1), false, "dark")
end)

---------------------------------------------------------------------------
-- Spell ranks
---------------------------------------------------------------------------
local function SpellIn(slot)
	return M.actions[slot] and M.actions[slot].spell
end

-- A character that knows Fireball rank 1 and Frost Nova, with both on the left set.
local function Mage(saved)
	M.book = { { spell = 101, name = "Fireball" }, { spell = 201, name = "Frost Nova" } }
	M.actions[185] = { texture = "icon", spell = 101 }
	M.actions[186] = { texture = "icon", spell = 201 }
	Load(saved)
	M.Advance(0.02) -- the first look at the slots
end

test("a spell on the bar moves up when a new rank of it is learned", function()
	Mage()
	eq(#M.printed, 2, "nothing to say about ranks at login: only the first-login lines")
	M.Learn(102, "Fireball")
	eq(SpellIn(185), 101, "not on the spot: on the next frame")
	M.Advance(0.02)
	eq(SpellIn(185), 102, "the slot holds the new rank")
	eq(SpellIn(186), 201, "another spell is not touched")
	eq(M.cursor, nil, "and the old rank is not left on the cursor")
	truthy(Printed("Moved up to the newest rank on your bar: Fireball%."), "chat says so")
	eq(Printed("The game does not keep"), false, "without the explanation meant for the first time")
	eq(ns.Buttons:GetSlot(1, 1), 185, "the button still shows its slot")
	eq(M.frames.FreeControlButton1_1.fc.spell, 102, "and has drawn what is in it now")
	M.Learn(103, "Fireball")
	M.Advance(0.02)
	eq(SpellIn(185), 103, "and again for the rank after that")
end)

test("a slot whose spell the game changed without announcing the slot is redrawn when the spell book changes", function()
	Mage()
	local button = M.frames.FreeControlButton1_1
	eq(button.fc.spell, 101, "drawn as rank 1")
	M.actions[185] = { texture = "icon two", spell = 102 } -- the game moved it up itself, and said nothing about the slot
	M.book = { { spell = 101, name = "Fireball", low = true }, { spell = 102, name = "Fireball" }, { spell = 201, name = "Frost Nova" } }
	M.Fire("SPELLS_CHANGED")
	eq(button.fc.spell, 102, "the button knows what it holds now")
	eq(button.fc.icon:GetTexture(), "icon two", "and shows it")
	M.actions[185] = { texture = "icon three", spell = 103 }
	M.Fire("LEARNED_SPELL_IN_SKILL_LINE", 103, 1, false)
	eq(button.fc.icon:GetTexture(), "icon three", "the other event for a learned spell does the same")
end)

test("a spell that the book files under another number while something overrides it still counts as moved", function()
	Mage()
	local real = C_SpellBook.GetSpellBookItemInfo
	C_SpellBook.GetSpellBookItemInfo = function(index, bank) -- the book's rank 2 is shown as an overriding spell
		local item = real(index, bank)
		if item and item.actionID == 102 then item.spellID = 9102 end
		return item
	end
	M.Learn(102, "Fireball")
	M.Advance(0.02)
	eq(SpellIn(185), 102, "the slot holds what the book handed over")
	truthy(Printed("Moved up to the newest rank on your bar: Fireball"), "and that counts as moved")
	eq(Printed("Could not be moved up"), false, "not as refused")
	eq(ns.db.ranks[M.guid][185], 102, "remembered under the number the slot gives")
end)

test("before the game can say whose slots these are, nothing is decided", function()
	M.book = { { spell = 101, name = "Fireball", low = true }, { spell = 102, name = "Fireball" } }
	M.actions[185] = { texture = "icon", spell = 101 }
	M.guid = nil
	Load()
	M.Advance(0.02)
	eq(SpellIn(185), 101, "nothing moved")
	eq(next(ns.db.ranks), nil, "and nothing recorded")
	M.guid = "Player-1-00000001"
	M.Fire("SPELLS_CHANGED")
	M.Advance(0.02)
	eq(SpellIn(185), 102, "moved up once the character is known")
end)

test("a lower rank the player put on a slot is left alone", function()
	Mage()
	M.Learn(102, "Fireball")
	M.Advance(0.02)
	Fill(187, { texture = "icon", spell = 101 }) -- rank 1 on purpose, next to rank 2
	M.Advance(0.02)
	eq(SpellIn(187), 101, "left as it was dropped")
	M.Learn(103, "Fireball")
	M.Advance(0.02)
	eq(SpellIn(185), 103, "the slot that was on the newest rank moves up")
	eq(SpellIn(187), 101, "the one chosen on purpose still does not")
	Fill(187, { texture = "icon", spell = 103 })
	M.Advance(0.02)
	M.Learn(104, "Fireball")
	M.Advance(0.02)
	eq(SpellIn(187), 104, "once the player puts the newest rank there, it is looked after like the rest")
end)

test("the first time a character is seen, every lower rank on the bar is moved up, and chat says why", function()
	M.book = { { spell = 101, name = "Fireball", low = true }, { spell = 102, name = "Fireball" }, { spell = 201, name = "Frost Nova" } }
	M.actions[185] = { texture = "icon", spell = 101 }
	M.actions[190] = { texture = "icon", spell = 101 }
	M.actions[186] = { texture = "icon", spell = 201 }
	Load()
	M.Advance(0.02)
	eq(SpellIn(185), 102, "moved up")
	eq(SpellIn(190), 102, "both of them")
	eq(SpellIn(186), 201, "a spell with one rank is left")
	truthy(Printed("Moved up to the newest rank on your bar: Fireball%."), "named once, though it was in two slots")
	truthy(Printed("The game does not keep the controller's slots on the newest rank outside Gamepad UI mode"), "with the reason, this once")
	M.printed = {}
	Fill(187, { texture = "icon", spell = 101 })
	M.Advance(0.02)
	eq(SpellIn(187), 101, "from then on a lower rank is the player's choice")
	eq(#M.printed, 0, "and nothing is said")
end)

test("what one character's slots held says nothing about another character's", function()
	M.book = { { spell = 101, name = "Fireball", low = true }, { spell = 102, name = "Fireball" } }
	M.actions[185] = { texture = "icon", spell = 101 }
	Load({ ranks = { ["Player-1-0000BEEF"] = { [185] = 55 } } })
	M.Advance(0.02)
	eq(SpellIn(185), 102, "a character seen for the first time gets its lower ranks moved up")
	eq(ns.db.ranks["Player-1-0000BEEF"][185], 55, "and the other character's record is untouched")
	eq(ns.db.ranks[M.guid][185], 102, "next to its own")
end)

test("in a fight a new rank waits for the fight to end", function()
	Mage()
	M.EnterCombat()
	M.Learn(102, "Fireball")
	M.Advance(0.02)
	eq(SpellIn(185), 101, "slots cannot be filled in combat")
	M.LeaveCombat()
	eq(SpellIn(185), 102, "moved up when it is over")
end)

test("while the player is carrying something, a new rank waits for the cursor to be empty", function()
	Mage()
	M.SetCursor("action")
	M.Learn(102, "Fireball")
	M.Advance(0.02)
	eq(SpellIn(185), 101, "not while something is on the cursor")
	eq(M.cursor, "action", "which is still there")
	M.SetCursor(nil)
	M.Advance(0.02)
	eq(SpellIn(185), 102, "moved up once it is put down")
end)

test("a slot the game will not fill is reported once and not tried over and over", function()
	Mage()
	M.refusePlace = true
	M.Learn(102, "Fireball")
	M.Advance(0.02)
	eq(SpellIn(185), 101, "the game did not take it")
	eq(M.cursor, nil, "and nothing is left on the cursor")
	truthy(Printed("Could not be moved up to the newest rank: Fireball%. Drag it onto the slot from the spell book%."), "said, with what to do")
	local lines, drops = #M.printed, #M.placed
	M.Fire("SPELLS_CHANGED")
	M.Advance(0.02)
	M.Fire("ACTIONBAR_SLOT_CHANGED", 185)
	M.Advance(0.02)
	eq(#M.printed, lines, "not said again")
	eq(#M.placed, drops, "and not tried again")
	M.refusePlace = false
	M.printed = {}
	SlashCmdList.FREECONTROL("ranks")
	eq(SpellIn(185), 102, "asking for it by hand tries afresh")
	truthy(Printed("Moved up to the newest rank on your bar: Fireball"), "and says so")
end)

test("if the spell book will not hand the spell over, nothing is dropped on the slot", function()
	Mage()
	M.refusePickup = true
	M.Learn(102, "Fireball")
	M.Advance(0.02)
	eq(SpellIn(185), 101, "unchanged")
	eq(#M.placed, 0, "and nothing was dropped with an empty hand")
	truthy(Printed("Could not be moved up to the newest rank: Fireball"), "said")
end)

test("a slot that held something else in between starts afresh", function()
	Mage()
	M.Learn(102, "Fireball")
	M.Advance(0.02) -- slot 185 is on rank 2, and known to be
	Fill(185, { texture = "icon", item = 900 })
	M.Advance(0.02)
	M.Learn(103, "Fireball")
	M.Advance(0.02)
	Fill(185, { texture = "icon", spell = 102 }) -- rank 2 again, now on purpose
	M.Advance(0.02)
	eq(SpellIn(185), 102, "what it held before the item no longer counts")
end)

test("a slot that held a chosen lower rank in between starts afresh too", function()
	Mage()
	M.Learn(102, "Fireball")
	M.Advance(0.02) -- slot 185 is on rank 2, and known to be
	Fill(185, { texture = "icon", spell = 101 }) -- rank 1 on purpose
	M.Advance(0.02)
	M.Learn(103, "Fireball")
	M.Advance(0.02)
	Fill(185, { texture = "icon", spell = 102 }) -- rank 2, now a lower rank, on purpose
	M.Advance(0.02)
	eq(SpellIn(185), 102, "that it once held rank 2 as the newest no longer counts")
end)

test("every page and the stance bars are looked after; the regular action bars are the game's own", function()
	M.book = { { spell = 101, name = "Fireball" } }
	for _, slot in ipairs({ 5, 185, 213, 241, 265, 304 }) do M.actions[slot] = { texture = "icon", spell = 101 } end
	Load()
	M.Advance(0.02)
	M.Learn(102, "Fireball")
	M.Advance(0.02)
	eq(SpellIn(185), 102, "the page that is showing")
	eq(SpellIn(213), 102, "page 2")
	eq(SpellIn(241), 102, "page 3")
	eq(SpellIn(265), 102, "the first stance bar")
	eq(SpellIn(304), 102, "the last slot of the last stance bar")
	eq(SpellIn(5), 101, "a regular action bar slot is not FreeControl's to change")
end)

test("only spells are looked at: items, macros and empty slots are left as they are", function()
	M.book = { { spell = 101, name = "Fireball", low = true }, { spell = 102, name = "Fireball" } }
	M.actions[185] = { texture = "icon", item = 101 }
	M.actions[186] = { texture = "icon", macro = 101 }
	M.actions[187] = { texture = "icon", macro = 4, macroSpell = 101 }
	Load()
	M.Advance(0.02)
	eq(M.actions[185].item, 101, "an item with the number of a lower rank")
	eq(M.actions[186].macro, 101, "a macro with that number")
	eq(M.actions[187].macroSpell, 101, "a macro that casts the lower rank: a macro names its spell itself")
	eq(#M.placed, 0, "nothing was dropped anywhere")
	eq(Printed("Moved up"), false, "and nothing is said")
end)

test("two different spells of one name: a lower rank is not moved to either", function()
	M.book = { { spell = 101, name = "Blessing", low = true }, { spell = 102, name = "Blessing" }, { spell = 150, name = "Blessing" } }
	M.actions[185] = { texture = "icon", spell = 101 }
	Load()
	M.Advance(0.02)
	eq(SpellIn(185), 101, "there is no telling which of the two it belongs to")
	eq(#M.placed, 0, "so nothing is tried")
end)

test("passive spells, another specialisation's spells and spells not yet learned are not ranks to move to", function()
	M.book = {
		{ spell = 101, name = "Fireball", low = true },
		{ spell = 102, name = "Fireball", passive = true },
		{ spell = 103, name = "Fireball", offSpec = true },
		{ spell = 104, name = "Fireball", passive = "future" },
	}
	M.actions[185] = { texture = "icon", spell = 101 }
	Load()
	M.Advance(0.02)
	eq(SpellIn(185), 101, "none of them replaces it")
	eq(#M.placed, 0, "nothing was tried")
end)

test("before the spell book is loaded nothing is decided; once it is, the lower ranks move up", function()
	M.actions[185] = { texture = "icon", spell = 101 }
	Load()
	M.Advance(0.02)
	eq(ns.db.ranks[M.guid], nil, "an empty spell book is not a first look at the character")
	M.book = { { spell = 101, name = "Fireball", low = true }, { spell = 102, name = "Fireball" } }
	M.Fire("SPELLS_CHANGED")
	M.Advance(0.02)
	eq(SpellIn(185), 102, "moved up when the book arrives")
end)

test("looking after ranks can be switched off, and asked for by hand", function()
	Mage()
	SlashCmdList.FREECONTROL("ranks off")
	eq(ns.db.keepRanks, false, "saved")
	M.Learn(102, "Fireball")
	M.Advance(0.02)
	eq(SpellIn(185), 101, "left alone")
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Spell ranks: kept at the newest rank: no%. On a lower rank right now: Fireball%."), "status lists what is behind")
	M.EnterCombat()
	SlashCmdList.FREECONTROL("ranks")
	truthy(Printed("In combat; type it again when the fight is over"), "not in a fight")
	M.LeaveCombat()
	M.SetCursor("action")
	SlashCmdList.FREECONTROL("ranks")
	truthy(Printed("Put down what is on the cursor first"), "nor with something on the cursor")
	M.SetCursor(nil)
	eq(SpellIn(185), 101, "nothing moved by either")
	SlashCmdList.FREECONTROL("ranks")
	eq(SpellIn(185), 102, "by hand it moves up")
	M.printed = {}
	SlashCmdList.FREECONTROL("ranks")
	truthy(Printed("Every spell on the controller's slots is at its newest rank"), "and a second time there is nothing to do")
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("On a lower rank right now: none"), "as status agrees")
	SlashCmdList.FREECONTROL("ranks on")
	eq(ns.db.keepRanks, true, "switched on again")
	M.Learn(103, "Fireball")
	M.Advance(0.02)
	eq(SpellIn(185), 103, "it follows the next rank by itself")
end)

test("asking for every rank by hand also moves a lower rank the player had chosen", function()
	Mage()
	M.Learn(102, "Fireball")
	M.Advance(0.02)
	Fill(187, { texture = "icon", spell = 101 })
	M.Advance(0.02)
	SlashCmdList.FREECONTROL("ranks")
	eq(SpellIn(187), 102, "that is what was asked for")
end)

test("with FreeControl switched off no slot is touched", function()
	Mage()
	SlashCmdList.FREECONTROL("off")
	M.Learn(102, "Fireball")
	M.Advance(0.02)
	eq(SpellIn(185), 101, "off: left alone")
	M.printed = {}
	SlashCmdList.FREECONTROL("ranks")
	truthy(Printed("FreeControl is switched off or idle"), "and the command says why")
	eq(SpellIn(185), 101, "without doing anything")
	SlashCmdList.FREECONTROL("on")
	M.Advance(0.02)
	eq(SpellIn(185), 102, "switched on again, it catches up")
end)

test("a client whose spell book does not tell lower ranks apart is left alone, and status says so", function()
	C_SpellBook.IsSpellBookItemLowRank = nil
	M.book = { { spell = 101, name = "Fireball", low = true }, { spell = 102, name = "Fireball" } }
	M.actions[185] = { texture = "icon", spell = 101 }
	Load()
	M.Advance(0.02)
	eq(SpellIn(185), 101, "nothing is moved")
	SlashCmdList.FREECONTROL("ranks")
	truthy(Printed("This client's spell book does not say which spells are lower ranks"), "the command says why")
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Spell ranks: this client's spell book does not say which spells are lower ranks"), "and so does status")
end)

test("with the regular action bars as the slots there is nothing of the controller's to look after", function()
	C_GamepadUI = nil
	M.book = { { spell = 101, name = "Fireball", low = true }, { spell = 102, name = "Fireball" } }
	M.actions[61] = { texture = "icon", spell = 101 }
	Load()
	M.Advance(0.02)
	eq(SpellIn(61), 101, "the game looks after those itself")
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Spell ranks: no controller slots to look after"), "status says so")
end)

test("a saved record of ranks that makes no sense is dropped", function()
	Load({ ranks = { broken = 5, ["Player-1-0000BEEF"] = { [185] = 101 } } })
	eq(ns.db.ranks.broken, nil, "dropped")
	eq(ns.db.ranks["Player-1-0000BEEF"][185], 101, "a real one is kept")
end)

test("the settings page has the two spell options", function()
	Load()
	local panel = ns.Options.panel
	Open(panel)
	local found = {}
	for _, frame in ipairs(M.all) do
		if frame.Text and frame.Text:GetText() then found[frame.Text:GetText()] = frame end
	end
	truthy(found["Glow when a spell procs"], "the glow")
	truthy(found["Keep spells at their newest rank"], "and the ranks")
	eq(found["Glow when a spell procs"]:GetChecked(), true, "both ticked to begin with")
	found["Keep spells at their newest rank"]:SetChecked(false)
	found["Keep spells at their newest rank"]:GetScript("OnClick")(found["Keep spells at their newest rank"])
	eq(ns.db.keepRanks, false, "unticking saves it")
end)


---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
-- What each page shows with nothing changed: the layout of Blizzard's controller bars.
local PAGE = {
	{ [0] = "181 182 183 184 - - - -", "185 186 187 188 189 190 191 192", "193 194 195 196 197 198 199 200", "201 202 203 204 205 206 207 208" },
	{ [0] = "209 210 211 212 - - - -", "213 214 215 216 217 218 219 220", "221 222 223 224 225 226 227 228", "229 230 231 232 233 234 235 236" },
	{ [0] = "237 238 239 240 - - - -", "241 242 243 244 245 246 247 248", "249 250 251 252 253 254 255 256", "257 258 259 260 261 262 263 264" },
}

local function ShowsPage(page, what)
	for set = 0, 3 do eq(Slots(set), PAGE[page][set], ("%s: page %d, set %d"):format(what, page, set)) end
end

-- The slot each key button would cast, which has to be the slot its picture shows.
local function KeySlots(set)
	local out = {}
	for index = 1, 8 do
		local key = M.frames[("FreeControlKey%d_%d"):format(set, index)]
		out[index] = key:IsShown() and tostring(key:GetAttribute("action")) or "-"
	end
	return table.concat(out, " ")
end

local function PageNumber()
	return tonumber(ns.Bars.pager.number:GetText())
end

test("the arrows in the middle of the bar turn the page, round and round", function()
	Load()
	local next, prev = M.frames.FreeControlPageNext, M.frames.FreeControlPagePrev
	truthy(next:IsVisible() and prev:IsVisible(), "both arrows are on the bar")
	truthy(ns.Bars.pager:IsVisible(), "and the number between them")
	eq(PageNumber(), 1, "which is the page being shown")
	ShowsPage(1, "to begin with")
	M.MouseClick(next)
	ShowsPage(2, "one click on")
	eq(ns.Bars.pager.number:GetText(), "2", "the number follows, as text for the font string")
	eq(ns.db.page, 2, "and the page is remembered")
	for set = 0, 3 do eq(KeySlots(set), PAGE[2][set], "the keys cast what the pictures show, set " .. set) end
	M.MouseClick(next)
	ShowsPage(3, "two clicks on")
	M.MouseClick(next)
	ShowsPage(1, "after the last page comes the first")
	M.MouseClick(prev)
	ShowsPage(3, "and before the first the last")
	M.MouseClick(prev)
	ShowsPage(2, "back one more")
	eq(ns.db.page, 2, "remembered again")
	eq(#M.luaErrors, 0, "nothing went wrong on the way")
end)

test("a click turns one page, on the way down", function()
	Load()
	local next = M.frames.FreeControlPageNext
	M.Click(next, "LeftButton", true)
	eq(ns.db.page, 2, "at once, on the press")
	M.Click(next, "LeftButton", false)
	eq(ns.db.page, 2, "the release does nothing more")
end)

test("a button bound to a page arrow turns the page in the middle of a fight", function()
	M.userBindings = { PADRSHOULDER = "CLICK FreeControlPageNext:LeftButton", PADLSHOULDER = "CLICK FreeControlPagePrev:LeftButton" }
	Load()
	M.actions[214] = { texture = "page two" }
	M.EnterCombat()
	M.Tap("PADRSHOULDER")
	ShowsPage(2, "in combat")
	eq(PageNumber(), 2, "the number too")
	eq(M.frames.FreeControlButton1_2.fc.icon:GetTexture(), "page two", "the buttons draw the new page's actions at once")
	M.KeyDown("PADLTRIGGER")
	M.Tap("PADDUP")
	M.KeyUp("PADLTRIGGER")
	eq(Used(), "214", "and a key casts from the page being shown")
	M.Tap("PADLSHOULDER")
	M.Tap("PADLSHOULDER")
	ShowsPage(3, "back past the first page to the last")
	eq(ns.db.page, 3, "remembered, though it was a fight")
	M.LeaveCombat()
	eq(#M.luaErrors, 0, "no protected call was refused")
end)

test("the page shown at logout is the page shown at the next login", function()
	Load({ page = 3 })
	ShowsPage(3, "saved page")
	eq(PageNumber(), 3, "the number")
	eq(M.frames.FreeControlHeader:GetAttribute("fc-page"), 3, "the secure header starts from it")
end)

test("the settings page and /fc page turn the page as well, and follow the arrows", function()
	Load()
	Open(ns.Options.panel)
	local button
	for _, frame in ipairs(M.all) do
		if frame:GetText() == "Page 1" then button = frame end
	end
	truthy(button, "the page choice on the settings page")
	SlashCmdList.FREECONTROL("page 3")
	ShowsPage(3, "/fc page 3")
	eq(button:GetText(), "Page 3", "the settings page shows it")
	M.MouseClick(M.frames.FreeControlPageNext)
	eq(button:GetText(), "Page 1", "and follows the arrows while it is open")
	button:GetScript("OnClick")(button)
	ShowsPage(2, "its own button steps on")
	SlashCmdList.FREECONTROL("page 4")
	eq(ns.db.page, 2, "there is no page 4")
end)

test("turned in a fight from the settings, the page waits; the arrows do not have to", function()
	Load()
	M.EnterCombat()
	M.printed = {}
	SlashCmdList.FREECONTROL("page 2")
	truthy(Printed("In combat"), "ordinary code may not touch the buttons in a fight, and says so")
	ShowsPage(1, "still page 1")
	M.MouseClick(M.frames.FreeControlPageNext)
	M.MouseClick(M.frames.FreeControlPageNext)
	ShowsPage(3, "the arrows are secure code")
	M.LeaveCombat()
	ShowsPage(3, "and what they chose stands when the fight ends: the page asked for earlier is not forced on top")
end)

test("with the regular action bars as the slots there is one page, and no arrows", function()
	Load({ slotSource = "bars", page = 2 })
	eq(ns.Layout.GetPageCount(), 1, "one page")
	eq(M.frames.FreeControlPageNext:IsShown(), false, "no arrow up")
	eq(M.frames.FreeControlPagePrev:IsShown(), false, "no arrow down")
	eq(ns.Bars.pager:IsShown(), false, "no number")
	eq(Slots(1), "61 62 63 64 65 66 67 68", "the bars' own slots")
	M.userBindings = { PADRSHOULDER = "CLICK FreeControlPageNext:LeftButton" }
	M.Tap("PADRSHOULDER")
	eq(Slots(1), "61 62 63 64 65 66 67 68", "a button bound to an arrow does nothing")
	eq(ns.db.page, 2, "and the page saved for the controller's slots is kept")
	SlashCmdList.FREECONTROL("slots gamepad")
	ShowsPage(2, "it is back when they are")
	truthy(M.frames.FreeControlPageNext:IsShown(), "with the arrows")
end)

test("switched off, a button bound to a page arrow does nothing", function()
	M.userBindings = { PADRSHOULDER = "CLICK FreeControlPageNext:LeftButton" }
	Load()
	SlashCmdList.FREECONTROL("off")
	M.Tap("PADRSHOULDER")
	eq(ns.db.page, 1, "the page is not turned behind the player's back")
	SlashCmdList.FREECONTROL("on")
	M.Tap("PADRSHOULDER")
	ShowsPage(2, "on again, it works again")
end)

test("a face button made a slot borrows from another page on every page, and no page shows a slot twice", function()
	Load({ roles = { "action", "action", "action", "action", "action", "cmd:FREECONTROL_TOGGLECURSOR", "action", "cmd:JUMP" }, mouseStep = 2 })
	local borrowed = { "261 - 263 -", "261 - 263 -", "233 - 235 -" }
	for page = 1, 3 do
		eq(Slots(0), PAGE[page][0]:sub(1, 15) .. " " .. borrowed[page], "page " .. page .. ": the D-pad is the page's own, the face slots are borrowed")
		local seen = {}
		for set = 0, 3 do
			for index = 1, 8 do
				local slot = ns.Buttons:GetSlot(set, index)
				if slot then
					eq(seen[slot], nil, ("page %d shows slot %d once"):format(page, slot))
					seen[slot] = true
				end
			end
		end
		M.MouseClick(M.frames.FreeControlPageNext)
	end
end)

test("turning the page keeps the range checks in step: one for each slot on show, none left behind", function()
	Load()
	local function Check(what)
		local shown = {}
		for set = 0, 3 do
			for index = 1, 8 do
				local slot = ns.Buttons:GetSlot(set, index)
				if slot then shown[slot] = (shown[slot] or 0) + 1 end
			end
		end
		for slot, count in pairs(M.rangeRefs) do
			eq(count, shown[slot] or 0, ("%s: range checks asked for slot %d"):format(what, slot))
		end
		for slot, count in pairs(shown) do
			eq(M.rangeRefs[slot], count, ("%s: slot %d is on show and watched"):format(what, slot))
		end
	end
	Check("at login")
	for turn = 1, 7 do
		M.MouseClick(turn % 3 == 0 and M.frames.FreeControlPagePrev or M.frames.FreeControlPageNext)
		Check("after turn " .. turn)
	end
	SlashCmdList.FREECONTROL("off")
	for slot, count in pairs(M.rangeRefs) do eq(count, 0, "switched off, nothing is watched: slot " .. slot) end
end)

test("a cooldown and a proc on another page show the moment that page is turned to", function()
	Load()
	M.actions[213] = { texture = "frost", spell = 116, cooldown = { M.now, 8 } }
	M.spellNames[116] = "Frostbolt"
	M.overlayed[116] = true
	local button = M.frames.FreeControlButton1_1
	eq(button.fc.cooldown.__cooldown, nil, "nothing on page 1")
	M.EnterCombat()
	M.MouseClick(M.frames.FreeControlPageNext)
	truthy(button.fc.cooldown.__cooldown, "the sweep is there on page 2")
	eq(button.fc.proc:GetAlpha(), 1, "and the glow")
	M.MouseClick(M.frames.FreeControlPagePrev)
	eq(button.fc.cooldown.__cooldown, nil, "gone again on page 1")
	eq(button.fc.proc:GetAlpha(), 0, "with the glow")
	M.LeaveCombat()
end)

test("a button held while the page turns is let go by the button it was pressed on", function()
	M.userBindings = { PADRSHOULDER = "CLICK FreeControlPageNext:LeftButton" }
	Load()
	M.actions[182] = { texture = "one" }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 182)
	local fc = M.frames.FreeControlButton0_2.fc
	M.KeyDown("PADDUP")
	eq(fc.pressShade:GetAlpha(), 1, "held")
	M.Tap("PADRSHOULDER")
	M.KeyUp("PADDUP")
	M.Advance(0.3)
	eq(fc.pressShade:GetAlpha(), 0, "not left looking held")
	eq(Used(), "182", "and it cast once, from the page it was pressed on")
end)

test("the arrows say what they do and which button does it", function()
	Load()
	local next = M.frames.FreeControlPageNext
	next:GetScript("OnEnter")(next)
	eq(GameTooltip.lines[1], "Next page", "title")
	truthy(GameTooltip.lines[2]:find("Page 1 of 3"), "where the bar is")
	truthy(GameTooltip.lines[3]:find("No button does this yet.*Other buttons"), "and where to give it a button")
	M.userBindings = { PADRSHOULDER = "CLICK FreeControlPageNext:LeftButton" }
	next:GetScript("OnEnter")(next)
	truthy(GameTooltip.lines[3]:find("^RB does this"), "or the button that has the job, by the name printed on it")
	local prev = M.frames.FreeControlPagePrev
	prev:GetScript("OnEnter")(prev)
	eq(GameTooltip.lines[1], "Previous page", "the other arrow")
	prev:GetScript("OnLeave")(prev)
	eq(GameTooltip.owner, nil, "tooltip put away")
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Page buttons: next page is on PADRSHOULDER, previous page on no button"), "status lists them too")
end)

---------------------------------------------------------------------------
-- Stances and forms, with pages
---------------------------------------------------------------------------
test("a stance changes the buttons on its own page only; the other pages are the same in every stance", function()
	Load()
	M.EnterCombat()
	M.ShapeshiftTo("Stealth")
	eq(Slots(2), "265 266 267 268 269 270 271 272", "page 1, in stealth: the right set changes")
	M.MouseClick(M.frames.FreeControlPageNext)
	ShowsPage(2, "page 2 in stealth is page 2")
	M.MouseClick(M.frames.FreeControlPageNext)
	ShowsPage(3, "page 3 in stealth is page 3")
	M.ShapeshiftTo(nil)
	ShowsPage(3, "and out of it")
	M.ShapeshiftTo("Stealth")
	M.MouseClick(M.frames.FreeControlPageNext)
	eq(Slots(2), "265 266 267 268 269 270 271 272", "back on page 1, the stance set is there again")
	eq(KeySlots(2), "265 266 267 268 269 270 271 272", "for the keys as well")
	M.LeaveCombat()
end)

test("the stance page is the one the Gamepad options put the stance bar on", function()
	M.cvars.GamepadStanceBarOverride = "6" -- page 2, left bar
	Load()
	eq(ns.Layout.GetStancePage(), 2, "page 2")
	M.ShapeshiftTo("Stealth")
	ShowsPage(1, "page 1 is left alone")
	M.MouseClick(M.frames.FreeControlPageNext)
	eq(Slots(1), "265 266 267 268 269 270 271 272", "on page 2 the left set changes")
	eq(Slots(2), PAGE[2][2], "and the right set does not")
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Changes with your stance or form %(setting: auto%): LT set, on page 2"), "status says where")
	M.cvars.GamepadStanceBarOverride = "9" -- page 3, top bar: no set there can change
	ns.RequestRefresh()
	eq(Slots(1), PAGE[2][1], "a stance bar on the top bar means nothing changes")
	SlashCmdList.FREECONTROL("stance rt")
	eq(ns.Layout.GetStancePage(), 3, "a set picked by hand changes on the page the option names")
	M.MouseClick(M.frames.FreeControlPageNext)
	eq(Slots(2), "265 266 267 268 269 270 271 272", "there it is")
end)

test("a Druid's pages: the first follows the form, the other two never do", function()
	M.class = "DRUID"
	Load()
	M.EnterCombat()
	M.ShapeshiftTo("Cat Form")
	eq(Slots(2), "265 266 267 268 269 270 271 272", "page 1 in Cat: right set")
	eq(Slots(1), "73 74 75 76 77 78 79 80", "left set")
	eq(Slots(0), "81 82 83 84 - - - -", "D-pad")
	eq(Slots(3), PAGE[1][3], "the both-triggers set stays")
	M.MouseClick(M.frames.FreeControlPageNext)
	ShowsPage(2, "page 2 in Cat")
	M.ShapeshiftTo("Bear Form")
	ShowsPage(2, "page 2 in Bear")
	M.MouseClick(M.frames.FreeControlPagePrev)
	eq(Slots(2), "281 282 283 284 285 286 287 288", "page 1 in Bear: right set")
	eq(Slots(1), "97 98 99 100 101 102 103 104", "left set")
	eq(Slots(0), "105 106 107 108 - - - -", "D-pad")
	M.ShapeshiftTo("Travel Form")
	ShowsPage(1, "Travel form has no bar of its own: the caster's buttons")
	M.ShapeshiftTo("Moonkin Form")
	eq(Slots(1), "109 110 111 112 113 114 115 116", "Moonkin has")
	M.ShapeshiftTo(nil)
	ShowsPage(1, "caster again")
	M.LeaveCombat()
	eq(#M.luaErrors, 0, "all of it in a fight, with nothing refused")
end)

test("a Druid who logs in in a form sees that form's buttons from the start", function()
	M.class = "DRUID"
	M.form, M.bonusbar = 3, 1 -- Cat
	Load()
	eq(Slots(2), "265 266 267 268 269 270 271 272", "right set")
	eq(Slots(1), "73 74 75 76 77 78 79 80", "left set")
	eq(KeySlots(1), "73 74 75 76 77 78 79 80", "and the keys with them, before anything else has happened")
	M.Tap("PADDLEFT")
	eq(Used(), "81", "the D-pad casts the form's slot")
end)

test("what is dropped on a button in a form stays in that form", function()
	M.class = "DRUID"
	M.lockActionBars = false
	Load()
	M.ShapeshiftTo("Cat Form")
	local button = M.frames.FreeControlButton1_1
	M.SetCursor({ kind = "spell", spell = 1082 })
	button:GetScript("OnReceiveDrag")(button)
	eq(M.placed[#M.placed], 73, "dropped into the Cat slot the button shows")
	eq(button.fc.icon:GetTexture(), "spell 1082", "and drawn there")
	M.ShapeshiftTo("Bear Form")
	eq(button.fc.hasAction, false, "not there in Bear")
	M.ShapeshiftTo(nil)
	eq(button.fc.hasAction, false, "nor as a caster")
	M.ShapeshiftTo("Cat Form")
	eq(button.fc.icon:GetTexture(), "spell 1082", "there again in Cat")
end)

test("a shapeshift dropped on a button that changes with the form is pointed out, once for the character", function()
	M.class = "DRUID"
	Load()
	M.printed = {}
	M.actions[193] = { texture = "cat", spell = 768 } -- Cat Form on RT + D-pad Left, as a caster
	M.Fire("ACTIONBAR_SLOT_CHANGED", 193)
	truthy(Printed("Cat Form is on RT %+ D%-pad Left, a button that changes with your stance or form"), "said when it happens")
	truthy(Printed("It stays there in every one of them, until you put something else on that button while you are in one"), "with how that works")
	truthy(Printed("On the LT %+ RT set, the face buttons and the other pages nothing can cover it"), "and where nothing can go wrong")
	M.printed = {}
	M.actions[194] = { texture = "bear", spell = 5487 }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 194)
	eq(#M.printed, 0, "and not again for that character")
	M.guid = "Player-1-00000002"
	M.Fire("ACTIONBAR_SLOT_CHANGED", 194)
	truthy(Printed("Bear Form is on RT %+ D%-pad Up"), "another character is told in turn")
end)

test("a shapeshift where it is safe, or an ordinary spell where it is not, is not pointed out", function()
	M.class = "DRUID"
	Load()
	M.printed = {}
	M.actions[201] = { texture = "cat", spell = 768 } -- on the both-triggers set
	M.Fire("ACTIONBAR_SLOT_CHANGED", 201)
	M.actions[193] = { texture = "wrath", spell = 5176 } -- not a form, on a button that changes
	M.Fire("ACTIONBAR_SLOT_CHANGED", 193)
	M.MouseClick(M.frames.FreeControlPageNext)
	M.actions[221] = { texture = "cat", spell = 768 } -- on page 2, which no form changes
	M.Fire("ACTIONBAR_SLOT_CHANGED", 221)
	eq(#M.printed, 0, "nothing said")
	eq(next(ns.db.formNotes), nil, "and nothing used up")
end)

test("a class with no stances is told nothing about shapeshifts, and a broken record of it is dropped", function()
	M.class = "MAGE"
	Load({ stanceSet = "all", formNotes = { ["Player-1-00000009"] = "yes", ["Player-1-00000008"] = true } })
	eq(ns.db.formNotes["Player-1-00000009"], nil, "a saved value that makes no sense is dropped")
	eq(ns.db.formNotes["Player-1-00000008"], true, "a good one is kept")
	M.printed = {}
	M.actions[193] = { texture = "frost", spell = 116 }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 193)
	eq(#M.printed, 0, "nothing said")
end)

-- Every class the classic rules give a stance or form, and clients that might number them
-- differently: nobody here has seen which Forever is.
local VARIANTS = {
	{ name = "Druid", class = "DRUID" },
	{ name = "Druid whose Prowl has a bar of its own", class = "DRUID", forms = {
		{ "Bear Form", 5487, 3 }, { "Aquatic Form", 1066, 0 }, { "Cat Form", 768, 1 }, { "Prowl", 5215, 2 }, { "Travel Form", 783, 0 }, { "Moonkin Form", 24858, 4 } } },
	{ name = "Druid whose every form has a bar, the fifth among them", class = "DRUID", forms = {
		{ "Bear Form", 5487, 3 }, { "Aquatic Form", 1066, 5 }, { "Cat Form", 768, 1 }, { "Travel Form", 783, 2 }, { "Moonkin Form", 24858, 4 } } },
	{ name = "Warrior", class = "WARRIOR" },
	{ name = "Rogue", class = "ROGUE" },
	{ name = "Priest", class = "PRIEST" },
	{ name = "Mage", class = "MAGE" },
}

-- What a button should show, from the rules as the settings page states them. This is written
-- out again on purpose, without the addon's own layout code, so that the two can disagree.
local function Expected(class, choice, option, page, bar)
	local optionPage, optionSet = 1, nil
	if option >= 2 and option <= 4 then
		optionSet = option - 1
	elseif option >= 5 then
		optionPage = math.floor((option - 5) / 4) + 2
		optionSet = (option - 5) % 4
		if optionSet == 0 then optionSet = nil end
	end
	local first, pair, dpad
	if choice == "auto" then
		first, pair, dpad = optionSet, class == "DRUID", class == "DRUID"
	elseif choice == "ltrt" or choice == "all" then
		first, pair, dpad = optionSet, true, choice == "all"
	elseif choice ~= "none" then
		first = ({ lt = 1, rt = 2, both = 3 })[choice]
	end
	if pair and first ~= 1 and first ~= 2 then first = 2 end
	local second = pair and (first == 2 and 1 or 2) or nil
	local changing = bar >= 1 and bar <= 5 and page == optionPage
	local slots = {}
	for set = 0, 3 do
		slots[set] = {}
		for index = 1, 8 do
			local unit = set * 8 + index
			local slot
			if set == 0 and index > 4 then
				slot = nil -- commands, by default
			elseif changing and set == first then
				slot = 181 + 84 + (bar - 1) * 8 + index - 1
			elseif changing and set == second then
				slot = 73 + (bar - 1) * 12 + index - 1
			elseif changing and dpad and set == 0 then
				slot = 73 + (bar - 1) * 12 + 8 + index - 1
			else
				slot = 181 + 28 * (page - 1) + (unit > 8 and unit - 5 or unit - 1)
			end
			slots[set][index] = slot
		end
	end
	return slots
end

test("every class, every stance setting, every page, every form: each button shows and casts the slot the rules give it", function()
	Load()
	local states = 0
	local function CheckState(variant, choice, option, what)
		local page = ns.db.page
		local expected = Expected(variant.class, choice, option, page, M.bonusbar)
		local seen = {}
		for set = 0, 3 do
			for index = 1, 8 do
				local button = M.frames[("FreeControlButton%d_%d"):format(set, index)]
				local key = M.frames[("FreeControlKey%d_%d"):format(set, index)]
				local slot = expected[set][index]
				local where = ("%s, button %d/%d"):format(what, set, index)
				eq(ns.Buttons:GetSlot(set, index), slot, where .. ": the picture")
				if slot then
					eq(key:GetAttribute("action"), slot, where .. ": the key")
					eq(button:GetAttribute("action"), slot, where .. ": the button under the mouse")
					eq(seen[slot], nil, where .. ": a slot on show twice")
					seen[slot] = true
					eq(M.rangeRefs[slot], 1, where .. ": its range is watched once")
				end
			end
		end
		for slot, count in pairs(M.rangeRefs) do
			eq(count, seen[slot] and 1 or 0, what .. ": range checks for slot " .. slot)
		end
		states = states + 1
	end
	for _, variant in ipairs(VARIANTS) do
		M.class, M.forms = variant.class, variant.forms
		local forms = M.GetForms()
		for _, choice in ipairs(ns.Layout.STANCE_CHOICES) do
			for _, option in ipairs({ 1, 2, 3, 4, 5, 6, 11, 12 }) do
				M.Shapeshift(0)
				M.cvars.GamepadStanceBarOverride = tostring(option)
				ns.db.stanceSet = choice
				ns.db.page = 1
				ns.Refresh()
				local label = ("%s, stance sets %s, Gamepad option %d"):format(variant.name, choice, option)
				-- Out of a fight and in one; every form on every page, and back out again.
				for round = 1, 2 do
					if round == 2 then M.EnterCombat() end
					for page = 1, 3 do
						for form = 0, #forms do
							M.Shapeshift(form)
							CheckState(variant, choice, option, ("%s, page %d, form %d%s"):format(label, page, form, round == 2 and ", in combat" or ""))
						end
						M.Shapeshift(0)
						CheckState(variant, choice, option, label .. ", out of every form again")
						M.MouseClick(M.frames.FreeControlPageNext)
					end
					if round == 2 then M.LeaveCombat() end
				end
			end
		end
	end
	truthy(states > 5000, "looked at a few thousand states: " .. states)
	eq(#M.luaErrors, 0, "and nothing was refused or went wrong in any of them")
end)

test("in every form a key casts exactly what its button shows, whichever trigger is held", function()
	Load()
	for _, variant in ipairs(VARIANTS) do
		M.class, M.forms = variant.class, variant.forms
		ns.db.stanceSet = "auto"
		ns.Refresh()
		M.EnterCombat()
		for form = 0, #M.GetForms() do
			M.Shapeshift(form)
			for set = 0, 3 do
				if set == 1 or set == 3 then M.KeyDown("PADLTRIGGER") end
				if set == 2 or set == 3 then M.KeyDown("PADRTRIGGER") end
				for index = 1, 8 do
					local slot = ns.Buttons:GetSlot(set, index)
					if slot then
						M.used = {}
						M.Tap(ns.db.keys[index])
						eq(Used(), tostring(slot), ("%s, form %d, set %d, button %d"):format(variant.name, form, set, index))
					end
				end
				M.KeyUp("PADRTRIGGER")
				M.KeyUp("PADLTRIGGER")
			end
		end
		M.Shapeshift(0)
		M.LeaveCombat()
	end
end)

test("no two forms share a button's slot, and what a form without a bar shows is what no form shows", function()
	M.class = "DRUID"
	Load()
	local function Snapshot()
		local out = {}
		for set = 0, 3 do
			for index = 1, 8 do out[#out + 1] = ns.Buttons:GetSlot(set, index) or 0 end
		end
		return out
	end
	local caster = Snapshot()
	local byBar = {}
	for index, form in ipairs(M.GetForms()) do
		M.Shapeshift(index)
		local now = Snapshot()
		if form[3] == 0 then
			for i = 1, #now do eq(now[i], caster[i], form[1] .. " has no bar: button " .. i) end
		else
			byBar[form[1]] = now
		end
	end
	for name, slots in pairs(byBar) do
		for other, otherSlots in pairs(byBar) do
			if name ~= other then
				for i = 1, #slots do
					if slots[i] ~= caster[i] then
						truthy(slots[i] ~= otherSlots[i], ("%s and %s keep button %d apart"):format(name, other, i))
					end
				end
			end
		end
		local changed = 0
		for i = 1, #slots do
			if slots[i] ~= caster[i] then changed = changed + 1 end
		end
		eq(changed, 20, name .. ": two sets of eight and the D-pad change, the other twelve do not")
	end
end)

test("switched off in a form and on again, the bar comes back in that form", function()
	M.class = "DRUID"
	Load()
	M.ShapeshiftTo("Bear Form")
	SlashCmdList.FREECONTROL("off")
	eq(#M.drivers, 0, "no driver is left running while it is off")
	M.ShapeshiftTo("Cat Form")
	SlashCmdList.FREECONTROL("on")
	eq(Slots(1), "73 74 75 76 77 78 79 80", "the form the character is in now")
	eq(KeySlots(1), "73 74 75 76 77 78 79 80", "keys too")
end)

test("one driver follows the stance for the whole bar, and none is left when nothing changes", function()
	M.class = "DRUID"
	Load()
	eq(#M.drivers, 1, "one driver, on the secure header")
	eq(M.drivers[1].frame, M.frames.FreeControlHeader, "that frame")
	eq(M.drivers[1].values, "[bonusbar:1] 1; [bonusbar:2] 2; [bonusbar:3] 3; [bonusbar:4] 4; [bonusbar:5] 5; 0", "asking which stance bar is up")
	M.ShapeshiftTo("Cat Form")
	SlashCmdList.FREECONTROL("stance none")
	eq(#M.drivers, 0, "none with nothing to change")
	ShowsPage(1, "and the buttons are back on their plain slots, form or no form")
	M.ShapeshiftTo("Bear Form")
	ShowsPage(1, "and stay there")
end)

test("the stance sets choice says what it comes to on this character", function()
	M.class = "DRUID"
	Load()
	Open(ns.Options.panel)
	local button
	for _, frame in ipairs(M.all) do
		if frame:GetText() == "Automatic" then button = frame end
	end
	button:GetScript("OnEnter")(button)
	eq(GameTooltip.lines[1], "Stance sets", "title")
	truthy(GameTooltip.lines[2]:find("On this character: RT set, LT set and the D%-pad, on page 1%.$"), "a Druid on automatic")
	truthy(GameTooltip.lines[2]:find("They change on one page only"), "with the rule about pages")
	eq(GameTooltip.lines[2]:find("regular action bars as the slots"), nil, "and not a word about a setup the player is not using")
	SlashCmdList.FREECONTROL("slots bars")
	button:GetScript("OnEnter")(button)
	truthy(GameTooltip.lines[2]:find("With the regular action bars as the slots, Automatic changes nothing"), "and why nothing does with the regular bars")
	truthy(GameTooltip.lines[2]:find("On this character: nothing%.$"), "said plainly")
end)

---------------------------------------------------------------------------
-- The Other buttons page
---------------------------------------------------------------------------
-- The client's menu system, as far as the settings pages use it: the last menu opened is kept,
-- with its entries in order. An entry is picked with Pick(menu, "its label").
local function UseMenus()
	local menus = {}
	MenuUtil = {
		CreateContextMenu = function(owner, generator)
			local root = { items = {}, owner = owner }
			function root:CreateRadio(text, isSelected, onSelect)
				self.items[#self.items + 1] = { text = text, isSelected = isSelected, onSelect = onSelect }
			end
			function root:CreateButton(text, onClick)
				self.items[#self.items + 1] = { text = text, onSelect = onClick, plain = true }
			end
			generator(owner, root)
			menus.last = root
		end,
	}
	return menus
end

local function Pick(menu, label)
	for _, item in ipairs(menu.items) do
		if item.text == label then
			item.onSelect()
			return
		end
	end
	error("the menu has no entry called " .. label, 2)
end

local function Selected(menu)
	for _, item in ipairs(menu.items) do
		if item.isSelected and item.isSelected() then return item.text end
	end
	return nil
end

-- The rows of the Other buttons page: [name printed on the row] = the button showing its job.
local function ButtonRows()
	local panel = ns.Options.buttonsPanel
	Open(panel)
	local rows, order = {}, {}
	local labels = {}
	for _, text in ipairs(panel.__texts) do labels[#labels + 1] = text end
	-- Every row made a label and then a button; the buttons are the panel's children in that order.
	local buttons = {}
	for _, frame in ipairs(M.all) do
		if frame:GetParent() == panel and frame.Sync then buttons[#buttons + 1] = frame end
	end
	-- The row labels are the panel's texts that sit where a row's label sits: four in from the
	-- left column, six down from the row's top.
	local index = 0
	for _, text in ipairs(labels) do
		local point = text.calls.SetPoint
		if point and point[1] == "TOPLEFT" and point[2] == 20 and text.kind == "FontString" and text ~= panel.__texts[1] and buttons[index + 1]
			and buttons[index + 1].__calls.SetPoint[3] == point[3] + 4 then
			index = index + 1
			local name = text:GetText() or ""
			rows[name] = buttons[index]
			order[#order + 1] = name
		end
	end
	return rows, order
end

test("the Other buttons page lists the controller's ordinary buttons with what each one does", function()
	M.userBindings = { PADRSHOULDER = "TARGETNEARESTENEMY", PADFORWARD = "TOGGLEGAMEMENU", PADBACK = "SOMETHINGELSE" }
	Load()
	eq(M.subcategories[1].GetID(), "Other buttons", "a page of its own under FreeControl")
	eq(M.subcategories[1].parent, M.category, "in the game's list of addon settings")
	local rows, order = ButtonRows()
	eq(table.concat(order, ", "), "LB, RB, Left stick click, Right stick click, Back, Start, Paddle 1, Paddle 2, Paddle 3, Paddle 4, ", "ten buttons by the names printed on them, and the row for any other")
	eq(rows.RB:GetText(), "Target nearest enemy", "a button with a job shows it")
	eq(rows.Start:GetText(), "Cancel / game menu", "another")
	eq(rows.Back:GetText(), "<SOMETHINGELSE>", "a job that is not in the list shows by the name the game gives it")
	eq(rows["Paddle 1"]:GetText(), "Nothing", "a button with no job says so")
	eq(rows.LB:GetText(), "Stand in for the Ctrl key", "the left bumper is the game's Ctrl key unless told otherwise, and the page says so")
	eq(rows[""]:IsShown(), false, "the row for another button is empty until one is pressed")
end)

test("picking a job gives the button a key binding of the player's own, and saves it", function()
	local menus = UseMenus()
	Load()
	local rows = ButtonRows()
	local row = rows.RB
	row:GetScript("OnClick")(row)
	eq(Selected(menus.last), "Nothing", "the menu marks what the button does now")
	M.printed = {}
	Pick(menus.last, "FreeControl: next page")
	eq(M.userBindings.PADRSHOULDER, "CLICK FreeControlPageNext:LeftButton", "bound")
	eq(M.savedBindings[#M.savedBindings], 1, "and saved in the binding set in use, as the Key Bindings screen does")
	truthy(Printed("RB now does this: FreeControl: next page%."), "chat says what happened")
	eq(row:GetText(), "FreeControl: next page", "the row shows it")
	eq(Selected(menus.last), "FreeControl: next page", "and so does the menu")
	M.EnterCombat()
	M.Tap("PADRSHOULDER")
	eq(ns.db.page, 2, "the button turns the page, in a fight")
	M.LeaveCombat()
	row:GetScript("OnClick")(row)
	M.printed = {}
	Pick(menus.last, "Nothing")
	eq(M.userBindings.PADRSHOULDER, nil, "Nothing takes the binding away")
	truthy(Printed("RB now does nothing%."), "and says so")
	eq(#M.savedBindings, 2, "saved again")
end)

test("the list of jobs: the pages, the mouse pointer, the game's common commands, and the way to everything else", function()
	local menus = UseMenus()
	Load()
	local rows = ButtonRows()
	rows["Paddle 2"]:GetScript("OnClick")(rows["Paddle 2"])
	local labels = {}
	for index, item in ipairs(menus.last.items) do labels[index] = item.text end
	eq(table.concat(labels, " | "), "Nothing | FreeControl: next page | FreeControl: previous page | Interact (loot, talk, use) | Jump | Cancel / game menu | Target nearest enemy | Target previous enemy | Target nearest friend | Target yourself | Start attacking | Auto-run | Mouse pointer on / off | World map | Bags | Target your target's target | Character | Spellbook | Talents | Quest log | Friends and guild | Dismount | Sit or stand | Something else...", "in this order")
	eq(menus.last.items[#menus.last.items].plain, true, "the last is something to do, not a job to have")
	Pick(menus.last, "Mouse pointer on / off")
	eq(M.userBindings.PADPADDLE2, "CLICK FreeControlMouse:LeftButton", "the mouse button can go on any button")
	M.Tap("PADPADDLE2")
	eq(M.PointerVisible(), true, "and brings the pointer out from there")
	rows["Paddle 2"]:GetScript("OnClick")(rows["Paddle 2"])
	Pick(menus.last, "Something else...")
	eq(M.opened[#M.opened], "Keybindings", "Something else opens the game's Key Bindings screen")
	eq(M.userBindings.PADPADDLE2, "CLICK FreeControlMouse:LeftButton", "and leaves the button as it was")
end)

test("a client with no stick pointer is not offered the mouse pointer as a job", function()
	local menus = UseMenus()
	SetGamePadCursorControl = nil
	Load()
	local rows = ButtonRows()
	rows.RB:GetScript("OnClick")(rows.RB)
	for _, item in ipairs(menus.last.items) do
		truthy(item.text ~= "Mouse pointer on / off", "not in the list")
	end
end)

test("the left bumper stops being the Ctrl key when it is given a job, and is Ctrl again when the job is taken away", function()
	local menus = UseMenus()
	Load()
	eq(M.cvars.GamePadEmulateCtrl, "PADLSHOULDER", "the game's own setting, left alone so far")
	eq(M.KeyDown("PADLSHOULDER"), "modifier", "so a press of the bumper is not a button press at all")
	M.KeyUp("PADLSHOULDER")
	local rows = ButtonRows()
	local row = rows.LB
	row:GetScript("OnEnter")(row)
	eq(GameTooltip.lines[1], "LB", "the tooltip is headed by the button's name")
	truthy(GameTooltip.lines[2]:find("stand%-in for the Ctrl key %(its GamePadEmulateCtrl setting%)"), "and says what the game is doing with it")
	row:GetScript("OnClick")(row)
	eq(Selected(menus.last), "Stand in for the Ctrl key", "that is what it does now")
	M.printed = {}
	Pick(menus.last, "FreeControl: previous page")
	eq(M.cvars.GamePadEmulateCtrl, "none", "with a job it is a plain button")
	eq(ns.db.cvarBackup.GamePadEmulateCtrl, "PADLSHOULDER", "and the player's own setting is kept for later")
	truthy(Printed("LB now does this: FreeControl: previous page%. It no longer stands in for the Ctrl key while FreeControl is active%."), "chat says both")
	eq(row:GetText(), "FreeControl: previous page", "the row shows the job")
	M.Tap("PADLSHOULDER")
	eq(ns.db.page, 3, "and the bumper turns the page")
	row:GetScript("OnEnter")(row)
	eq(GameTooltip.lines[2]:find("stand%-in"), nil, "nothing more about Ctrl in the tooltip")
	SlashCmdList.FREECONTROL("off")
	eq(M.cvars.GamePadEmulateCtrl, "PADLSHOULDER", "switched off, the game has its setting back")
	SlashCmdList.FREECONTROL("on")
	eq(M.cvars.GamePadEmulateCtrl, "none", "and on again it is a plain button again")
	row:GetScript("OnClick")(row)
	eq(menus.last.items[1].text, "Nothing", "the first choice has its plain name while the bumper is a plain button")
	M.printed = {}
	Pick(menus.last, "Nothing")
	eq(M.cvars.GamePadEmulateCtrl, "PADLSHOULDER", "without a job it stands in for Ctrl again")
	truthy(Printed("LB has no job of its own now, and stands in for the Ctrl key again"), "which chat says")
	eq(row:GetText(), "Stand in for the Ctrl key", "and the row")
	eq(next(ns.db.plainKeys), nil, "nothing is left over")
end)

test("a page arrow bound in the game's Key Bindings screen works on the left bumper too", function()
	Load()
	SetBinding("PADLSHOULDER", "CLICK FreeControlPagePrev:LeftButton") -- what the Key Bindings screen does
	eq(M.cvars.GamePadEmulateCtrl, "PADLSHOULDER", "nothing yet: the client is still in the middle of the change")
	M.Advance(0.01)
	eq(M.cvars.GamePadEmulateCtrl, "none", "a moment later the bumper is a plain button")
	M.Tap("PADLSHOULDER")
	eq(ns.db.page, 3, "and turns the page")
	SetBinding("PADLSHOULDER", "TOGGLEWORLDMAP")
	M.Advance(0.01)
	eq(M.cvars.GamePadEmulateCtrl, "PADLSHOULDER", "bound to something of the game's own there, it is the player's business again")
	SetBinding("PADLSHOULDER", nil)
	M.Advance(0.01)
	eq(M.cvars.GamePadEmulateCtrl, "PADLSHOULDER", "and unbound")
end)

test("bindings that change in a fight, or while FreeControl is off, do not touch the game's settings", function()
	Load()
	SlashCmdList.FREECONTROL("off")
	M.userBindings.PADLSHOULDER = "CLICK FreeControlPagePrev:LeftButton"
	M.Fire("UPDATE_BINDINGS")
	M.Advance(0.01)
	eq(M.cvars.GamePadEmulateCtrl, "PADLSHOULDER", "off: left alone")
	SlashCmdList.FREECONTROL("on")
	eq(M.cvars.GamePadEmulateCtrl, "none", "on: the bumper has one of FreeControl's jobs, so it is a plain button")
	M.EnterCombat()
	for _ = 1, 5 do M.Fire("UPDATE_BINDINGS") end -- the client says this for its own reasons too
	M.Advance(0.01)
	M.LeaveCombat()
	eq(#M.luaErrors, 0, "nothing is attempted in a fight")
end)

test("a job cannot be given in a fight", function()
	local menus = UseMenus()
	Load()
	local rows = ButtonRows()
	rows.RB:GetScript("OnClick")(rows.RB)
	M.EnterCombat()
	M.printed = {}
	Pick(menus.last, "Jump")
	truthy(Printed("Key bindings cannot be changed in combat"), "said")
	eq(M.userBindings.PADRSHOULDER, nil, "and nothing is bound")
	eq(#M.savedBindings, 0, "or saved")
	M.LeaveCombat()
	eq(#M.luaErrors, 0, "no protected call was tried")
end)

test("a client that will not make the binding is reported, and the row stays as it was", function()
	local menus = UseMenus()
	Load()
	M.refuseBinding = true
	local rows = ButtonRows()
	rows.RB:GetScript("OnClick")(rows.RB)
	M.printed = {}
	Pick(menus.last, "Jump")
	truthy(Printed("The game would not bind RB to that"), "said")
	eq(#M.savedBindings, 0, "nothing saved")
	eq(rows.RB:GetText(), "Nothing", "the row is unchanged")
	eq(ns.db.plainKeys.PADRSHOULDER, nil, "and the button is not taken for one with a job")
end)

test("a button FreeControl uses itself says so instead of offering jobs", function()
	local menus = UseMenus()
	Load({ modKeys = { "PADLSHOULDER", "PADRTRIGGER" } })
	local rows = ButtonRows()
	eq(rows.LB:GetText(), "FreeControl's left trigger", "the left bumper is the left trigger here")
	M.printed = {}
	rows.LB:GetScript("OnClick")(rows.LB)
	eq(menus.last, nil, "no menu")
	truthy(Printed("LB is FreeControl's left trigger, so a key binding on it would never be reached"), "but the reason")
end)

test("any other button or key can be pressed to give it a job", function()
	local menus = UseMenus()
	Load()
	local rows = ButtonRows()
	local find
	for _, frame in ipairs(M.all) do
		if frame:GetText() == "Press it..." then find = frame end
	end
	truthy(find, "the button that starts listening")
	local catcher = ns.Options.catcher
	eq(catcher:IsShown(), false, "not listening to begin with")
	find:GetScript("OnClick")(find)
	truthy(catcher:IsVisible(), "listening")
	eq(M.KeyDown("LSHIFT"), "caught", "a modifier key on its own")
	M.KeyUp("LSHIFT")
	truthy(catcher:IsVisible(), "is waited through")
	eq(M.KeyDown("PADSOCIAL"), "caught", "a controller button goes to the page, not to its binding")
	M.KeyUp("PADSOCIAL")
	eq(catcher:IsShown(), false, "one press ends the listening")
	local row = rows[""]
	truthy(row:IsShown(), "the button has a row now")
	eq(row:GetText(), "Nothing", "showing its job")
	row:GetScript("OnClick")(row)
	Pick(menus.last, "World map")
	eq(M.userBindings.PADSOCIAL, "TOGGLEWORLDMAP", "which can be changed like any other")
	eq(row:GetText(), "World map", "and shows")

	find:GetScript("OnClick")(find)
	M.Tap("ESCAPE")
	eq(catcher:IsShown(), false, "Escape ends the listening")
	eq(ns.Options.caughtKey, "PADSOCIAL", "and changes nothing")
	find:GetScript("OnClick")(find)
	catcher:GetScript("OnMouseDown")(catcher, "LeftButton")
	eq(catcher:IsShown(), false, "so does a click")
	find:GetScript("OnClick")(find)
	M.Tap("F")
	eq(ns.Options.caughtKey, "F", "a key on the keyboard works the same way")
	find:GetScript("OnClick")(find)
	M.Tap("PAD1")
	eq(row:GetText(), "FreeControl's A", "one of FreeControl's own buttons is named as that")

	M.EnterCombat()
	M.printed = {}
	find:GetScript("OnClick")(find)
	eq(catcher:IsShown(), false, "no listening in a fight")
	truthy(Printed("Key bindings cannot be changed in combat"), "with the reason")
	M.LeaveCombat()
end)

test("a click button's row says it is a mouse button while the pointer is out", function()
	Load()
	local rows = ButtonRows()
	local row = rows["Left stick click"]
	row:GetScript("OnEnter")(row)
	truthy(GameTooltip.lines[2]:find("While the mouse pointer is out it is the left mouse button instead"), "left click")
	row = rows["Right stick click"]
	row:GetScript("OnEnter")(row)
	truthy(GameTooltip.lines[2]:find("it is the right mouse button instead"), "right click")
	row = rows.Start
	row:GetScript("OnEnter")(row)
	eq(GameTooltip.lines[2]:find("mouse button"), nil, "not said of a button that is not one")
end)

test("the rows follow bindings made somewhere else while the page is open, and only then", function()
	Load()
	local rows = ButtonRows()
	SetBinding("PADRSHOULDER", "JUMP")
	eq(rows.RB:GetText(), "Jump", "open: the row follows")
	ns.Options.buttonsPanel:Hide()
	SetBinding("PADRSHOULDER", "TOGGLEAUTORUN")
	eq(rows.RB:GetText(), "Jump", "closed: nothing is redrawn")
	Open(ns.Options.buttonsPanel)
	eq(rows.RB:GetText(), "Auto-run", "and it is brought up to date when opened")
end)

test("the main page and /fc buttons lead to the Other buttons page, and the Key Bindings screen is one click from it", function()
	Load()
	Open(ns.Options.panel)
	local toButtons
	for _, frame in ipairs(M.all) do
		if frame:GetText() == "Other buttons..." then toButtons = frame end
	end
	truthy(toButtons, "a button on the main page")
	toButtons:GetScript("OnClick")(toButtons)
	eq(M.opened[#M.opened], "Other buttons", "opens the page")
	M.opened = {}
	SlashCmdList.FREECONTROL("buttons")
	eq(M.opened[1], "Other buttons", "/fc buttons does the same")
	Open(ns.Options.buttonsPanel)
	local toBindings
	for _, frame in ipairs(M.all) do
		if frame:GetText() == "Open Key Bindings" then toBindings = frame end
	end
	toBindings:GetScript("OnClick")(toBindings)
	eq(M.opened[#M.opened], "Keybindings", "the game's own screen")
	local found = false
	for _, text in ipairs(ns.Options.panel.__texts) do
		found = found or (text:GetText() or ""):find("bumpers, stick clicks, Start, Back and paddles stay ordinary buttons") ~= nil
	end
	truthy(found, "and the main page says in so many words that those buttons are the player's own")
end)

test("without the menu system a row steps through the jobs, and never onto the way out", function()
	Load()
	local rows = ButtonRows()
	local row = rows.RB
	local seen = {}
	for _ = 1, 30 do
		row:GetScript("OnClick")(row)
		seen[#seen + 1] = M.userBindings.PADRSHOULDER or "-"
	end
	eq(seen[1], "CLICK FreeControlPageNext:LeftButton", "first the next job in the list")
	eq(#M.opened, 0, "the Key Bindings screen is never opened by stepping")
	local back = false
	for _, value in ipairs(seen) do back = back or value == "-" end
	truthy(back, "and it comes round to nothing again")
end)

test("saved notes about plain buttons that make no sense are dropped", function()
	Load({ plainKeys = { PADRSHOULDER = true, padlshoulder = true, PADBACK = "yes", [5] = true } })
	eq(ns.db.plainKeys.PADRSHOULDER, true, "a good one is kept")
	eq(ns.db.plainKeys.padlshoulder, nil, "a name in the wrong case is not a button")
	eq(ns.db.plainKeys.PADBACK, nil, "nor is a value that is not yes")
	eq(ns.db.plainKeys[5], nil, "nor a number")
end)

---------------------------------------------------------------------------
-- A shapeshift on a button that changes with the form
---------------------------------------------------------------------------
test("a shapeshift on a button that changes with the form stays there in every form with nothing of its own on it", function()
	M.class = "DRUID"
	Load()
	M.actions[193] = { texture = "cat", spell = 768 }  -- Cat Form on RT + D-pad Left, as a caster
	M.actions[194] = { texture = "wrath", spell = 5176 } -- an ordinary spell next to it
	M.Fire("ACTIONBAR_SLOT_CHANGED", 193)
	M.Fire("ACTIONBAR_SLOT_CHANGED", 194)
	M.Advance(0.01)
	M.EnterCombat()
	M.ShapeshiftTo("Cat Form")
	eq(Slots(2), "193 266 267 268 269 270 271 272", "in Cat the shapeshift is still on its button; the rest of the set is Cat's own")
	eq(KeySlots(2), "193 266 267 268 269 270 271 272", "for the key as well")
	M.KeyDown("PADRTRIGGER")
	M.Tap("PADDLEFT")
	M.KeyUp("PADRTRIGGER")
	eq(Used(), "193", "and the key casts it: the way out of the form is where it was put")
	M.ShapeshiftTo("Bear Form")
	eq(Slots(2), "193 282 283 284 285 286 287 288", "the same in Bear")
	M.ShapeshiftTo(nil)
	eq(Slots(2), "193 194 195 196 197 198 199 200", "and as a caster nothing has changed")
	M.LeaveCombat()
	eq(#M.luaErrors, 0, "all in a fight, nothing refused")
end)

test("what is dropped on a kept shapeshift in a form becomes the form's own, and covers it in that form only", function()
	M.class = "DRUID"
	M.lockActionBars = false
	Load()
	M.actions[193] = { texture = "cat", spell = 768 }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 193)
	M.Advance(0.01)
	M.ShapeshiftTo("Cat Form")
	local button = M.frames.FreeControlButton2_1
	eq(button.fc.slot, 193, "kept")
	button:GetScript("OnEnter")(button)
	truthy(GameTooltip.lines[#GameTooltip.lines]:find("Kept from your normal buttons"), "the tooltip says why it is there")
	M.SetCursor({ kind = "spell", spell = 1082 }) -- Claw
	button:GetScript("OnReceiveDrag")(button)
	eq(M.placed[#M.placed], 265, "dropped into Cat's own slot for the button, not onto the shapeshift")
	eq(M.actions[193].spell, 768, "which is untouched")
	M.Advance(0.01)
	eq(button.fc.slot, 265, "Cat now has its own action there")
	eq(button.fc.icon:GetTexture(), "spell 1082", "and shows it")
	button:GetScript("OnEnter")(button)
	eq(GameTooltip.lines[#GameTooltip.lines]:find("Kept from"), nil, "no note on a button that is the form's own")
	M.ShapeshiftTo("Bear Form")
	eq(button.fc.slot, 193, "Bear has nothing there: the shapeshift is still on show")
	M.ShapeshiftTo("Cat Form")
	M.actions[265] = nil -- taken off again
	M.Fire("ACTIONBAR_SLOT_CHANGED", 265)
	M.Advance(0.01)
	eq(button.fc.slot, 193, "with Cat's own gone the shapeshift is back")
end)

test("only a shapeshift is kept: an ordinary spell gives way, and an empty stance button stays empty", function()
	Load({ stanceSet = "rt" })
	M.actions[193] = { texture = "stealth", spell = 1784 }  -- Stealth
	M.actions[194] = { texture = "strike", spell = 1752 }   -- not a stance
	M.Fire("ACTIONBAR_SLOT_CHANGED", 193)
	M.Fire("ACTIONBAR_SLOT_CHANGED", 194)
	M.Advance(0.01)
	M.ShapeshiftTo("Stealth")
	eq(Slots(2), "193 266 267 268 269 270 271 272", "a Rogue's Stealth stays in stealth; the strike next to it gives way")
	eq(M.frames.FreeControlButton2_2.fc.hasAction, false, "to an empty button, as before")
	M.ShapeshiftTo(nil)
	M.actions[193] = { texture = "macro", macro = 7, macroSpell = 1784 }
	M.Fire("ACTIONBAR_SLOT_CHANGED", 193)
	M.Advance(0.01)
	M.ShapeshiftTo("Stealth")
	eq(ns.Buttons:GetSlot(2, 1), 193, "a macro that casts the shapeshift counts as one")
end)

test("what is kept is worked out outside a fight and stands through one", function()
	M.class = "DRUID"
	Load()
	M.EnterCombat()
	M.actions[193] = { texture = "cat", spell = 768 } -- the game changes a slot in mid-fight
	M.Fire("ACTIONBAR_SLOT_CHANGED", 193)
	M.Advance(0.01)
	M.ShapeshiftTo("Cat Form")
	eq(ns.Buttons:GetSlot(2, 1), 265, "nothing is looked at or handed over in a fight")
	M.LeaveCombat()
	eq(ns.Buttons:GetSlot(2, 1), 193, "it catches up when the fight ends")
	eq(#M.luaErrors, 0, "and nothing was refused")
end)

test("learning a form makes its button a kept one", function()
	M.class = "DRUID"
	M.forms = { { "Bear Form", 5487, 3 } }
	Load()
	M.actions[193] = { texture = "cat", spell = 768 } -- on the bar before it is a form the game lists
	M.Fire("ACTIONBAR_SLOT_CHANGED", 193)
	M.Advance(0.01)
	M.ShapeshiftTo("Bear Form")
	eq(ns.Buttons:GetSlot(2, 1), 281, "not a form of this character's: it gives way")
	M.forms = { { "Bear Form", 5487, 3 }, { "Cat Form", 768, 1 } }
	M.Fire("UPDATE_SHAPESHIFT_FORMS")
	M.Advance(0.01)
	eq(ns.Buttons:GetSlot(2, 1), 193, "learned: it stays")
end)

test("with nothing changing by stance nothing is kept, and switching the stance sets brings it back", function()
	M.class = "DRUID"
	Load()
	M.actions[185] = { texture = "bear", spell = 5487 } -- on the left set
	M.Fire("ACTIONBAR_SLOT_CHANGED", 185)
	M.Advance(0.01)
	local header = M.frames.FreeControlHeader
	eq(header:GetAttribute("fc-keep-1-1-1"), true, "kept in Cat")
	eq(header:GetAttribute("fc-keep-3-1-1"), true, "and in Bear")
	SlashCmdList.FREECONTROL("stance rt")
	eq(header:GetAttribute("fc-keep-1-1-1"), nil, "the left set no longer changes: nothing to keep")
	SlashCmdList.FREECONTROL("stance auto")
	eq(header:GetAttribute("fc-keep-1-1-1"), true, "back on automatic")
	M.actions[73] = { texture = "claw", spell = 1082 } -- the game's own Cat bar has something on that button
	M.Fire("ACTIONBAR_SLOT_CHANGED", 73)
	M.Advance(0.01)
	eq(header:GetAttribute("fc-keep-1-1-1"), nil, "Cat has its own: not kept there")
	eq(header:GetAttribute("fc-keep-3-1-1"), true, "still kept in Bear")
	M.ShapeshiftTo("Cat Form")
	eq(ns.Buttons:GetSlot(1, 1), 73, "Cat shows its own")
	M.ShapeshiftTo("Bear Form")
	eq(ns.Buttons:GetSlot(1, 1), 185, "Bear the shapeshift")
end)

test("in a form, a drop on a page that no form changes goes to that page's own slot", function()
	M.class = "DRUID"
	M.lockActionBars = false
	Load()
	M.ShapeshiftTo("Cat Form")
	M.MouseClick(M.frames.FreeControlPageNext)
	local button = M.frames.FreeControlButton1_1
	eq(button.fc.slot, 213, "page 2, left set: the page's slot, Cat or not")
	M.SetCursor({ kind = "spell", spell = 1082 })
	button:GetScript("OnReceiveDrag")(button)
	eq(M.placed[#M.placed], 213, "which is where the drop goes, not into Cat's slots on page 1")
	eq(M.actions[73], nil, "those are untouched")
end)

test("with nothing set to change, status says so and does not call a stance bar unfollowed", function()
	M.class = "DRUID"
	Load({ stanceSet = "none" })
	M.ShapeshiftTo("Cat Form")
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Stance bar 1 is up%. Nothing on the bar is set to change with it%."), "said plainly")
	eq(Printed("these differ"), false, "and nothing is flagged")
	M.printed = {}
	SlashCmdList.FREECONTROL("stance auto")
	SlashCmdList.FREECONTROL("stance none")
	M.ShapeshiftTo("Bear Form")
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Stance bar 3 is up%. Nothing on the bar is set to change with it%."), "the same after the sets were on for a while")
	eq(Printed("these differ"), false, "still nothing flagged")
	ShowsPage(1, "and the buttons are the plain ones")
end)

test("status does not ask for a mouse button when another button has that job", function()
	local roles = { "action", "action", "action", "action", "cmd:INTERACTTARGET", "pass", "cmd:TOGGLEGAMEMENU", "cmd:JUMP" }
	Load({ mouseStep = 2, roles = roles })
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("No button brings the mouse pointer out.*Other buttons"), "none on the bar: status says so, and where else one can be given")
	M.printed = {}
	SetBinding("PADPADDLE1", ns.Bindings.MOUSE_COMMAND)
	SlashCmdList.FREECONTROL("status")
	eq(Printed("No button brings the mouse pointer out"), false, "a paddle has the job: nothing to say")
	eq(GetBindingName(ns.Bindings.MOUSE_COMMAND), "FreeControl: mouse pointer on / off", "and the binding has a name to show")
end)

test("a job given while FreeControl is switched off is bound, and the game's settings wait until it is on", function()
	local menus = UseMenus()
	Load()
	SlashCmdList.FREECONTROL("off")
	local rows = ButtonRows()
	rows.LB:GetScript("OnClick")(rows.LB)
	Pick(menus.last, "World map")
	eq(M.userBindings.PADLSHOULDER, "TOGGLEWORLDMAP", "the binding is the player's own, whatever FreeControl is doing")
	eq(M.cvars.GamePadEmulateCtrl, "PADLSHOULDER", "but FreeControl touches no setting of the game's while it is off")
	eq(rows.LB:GetText(), "World map", "the row shows the job")
	SlashCmdList.FREECONTROL("on")
	eq(M.cvars.GamePadEmulateCtrl, "none", "switched on, the bumper is a plain button")
end)

test("a shapeshift already on the bar at login is kept once the game has listed the character's forms", function()
	M.class = "DRUID"
	M.forms = {} -- at login the game has not listed them yet
	M.actions[193] = { texture = "cat", spell = 768 }
	Load()
	M.Advance(0.01)
	local header = M.frames.FreeControlHeader
	eq(header:GetAttribute("fc-keep-1-2-1"), nil, "not known to be a form yet")
	M.forms = nil -- now it has
	M.Fire("PLAYER_ENTERING_WORLD")
	M.Advance(0.01)
	eq(header:GetAttribute("fc-keep-1-2-1"), true, "kept from then on")
	M.ShapeshiftTo("Cat Form")
	eq(ns.Buttons:GetSlot(2, 1), 193, "and there in the form")
end)

test("slots announced all through a fight book one look for when it ends, and start no timers", function()
	M.class = "DRUID"
	Load()
	M.Advance(0.01)
	M.EnterCombat()
	local before = #M.timers
	M.actions[193] = { texture = "cat", spell = 768 }
	for _ = 1, 50 do M.Fire("ACTIONBAR_SLOT_CHANGED", 193) end -- a macro's icon flickering, say
	eq(#M.timers, before, "nothing is scheduled in the fight")
	eq(M.frames.FreeControlHeader:GetAttribute("fc-keep-1-2-1"), nil, "and nothing handed over")
	M.LeaveCombat()
	eq(M.frames.FreeControlHeader:GetAttribute("fc-keep-1-2-1"), true, "one look when it ends")
	M.actions[193] = nil
	M.Fire("ACTIONBAR_SLOT_CHANGED", 193)
	M.Advance(0.01)
	eq(M.frames.FreeControlHeader:GetAttribute("fc-keep-1-2-1"), nil, "and the usual look after that")
end)
