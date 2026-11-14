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
	truthy(Printed("Changes with your stance or form: RT set and LT set%."), "two sets, in words")
	M.bonusbar = 2
	M.RunDrivers()
	eq(Slots(2), "273 274 275 276 277 278 279 280", "right set")
	eq(Slots(1), "85 86 87 88 89 90 91 92", "left set")
	eq(Slots(0), CASTER[0], "D-pad stays")
	SlashCmdList.FREECONTROL("stance all")
	truthy(Printed("Changes with your stance or form: RT set, LT set and the D%-pad%."), "the command says what changes now")
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
	truthy(Printed("Druid: RT set, LT set and the D%-pad change with your form"), "said at the first login on a Druid")
	truthy(Printed("The LT %+ RT set and the face buttons stay the same in every form"), "with where to put the shapeshifts")
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
	panel:GetScript("OnShow")(panel)
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

test("stances do not change the bar while the regular action bars are used", function()
	Load({ slotSource = "bars", stanceSet = "all" })
	eq(#ns.Layout.GetStanceGroups(), 0, "nothing changes with the stance")
	eq(#M.drivers, 0, "no drivers")
	M.bonusbar = 1
	M.RunDrivers()
	eq(Slots(1), "61 62 63 64 65 66 67 68", "the left set stays on the Bottom Left bar")
	eq(Slots(0), "37 38 39 40 - - - -", "and the D-pad on the Left bar")
end)

test("stance swapping is skipped when the client rejects the stance slots", function()
	M.lastGamepadSlot = 264
	Load({ stanceSet = "lt" })
	eq(ns.Layout.HasGamepadSlots(), true, "pages usable")
	eq(#ns.Layout.GetStanceGroups(), 0, "nothing changes with the stance")
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

test("nothing is added to the Key Bindings screen", function()
	Load()
	eq(BINDING_NAME_FREECONTROL_TOGGLECURSOR, nil, "no binding of our own for the player to set up")
	eq(ns.ToggleCursor, nil, "and no function for one to call")
	for line in ReadFile("FreeControl/FreeControl.toc"):gmatch("[^\r\n]+") do
		eq(line:lower():find("bindings.xml", 1, true), nil, "no bindings file is loaded")
	end
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
	panel:GetScript("OnShow")(panel)
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
	panel:GetScript("OnShow")(panel)
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
	truthy(Printed("No stance or form bar is active right now"), "outside any stance")
	M.bonusbar = 3
	M.RunDrivers()
	SlashCmdList.FREECONTROL("status")
	truthy(Printed("Stance 3: its controller slots start at 281 %(the game says 281%)"), "the controller's stance slots")
	truthy(Printed("Stance 3: its regular action bar slots start at 97 %(the game says 97%)"), "and the regular bar's")
	eq(Printed("these differ"), false, "no mismatch")
	truthy(Printed("Class: ROGUE%. Changes with your stance or form %(setting: rt%): RT set"), "names what changes")
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
