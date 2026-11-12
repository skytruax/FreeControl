-- SimInput: test-only input injection for wow-ui-sim (WoW Forever profile).
--
-- Why this exists
--   * wow-ui-sim 0.1.41 has no Lua API to press a key or gamepad button, and its key dispatcher
--     does not execute "CLICK Button:LeftButton" bindings at all.
--   * button:Click() called from test/addon code runs TAINTED: the click scripts run, but the
--     simulator refuses UseAction()/CastSpellByID() with ADDON_ACTION_FORBIDDEN, and Blizzard's
--     WrapScript wrapper errors with "Cannot call restricted closure from insecure code".
--     (That is the outcome I would expect from the real client for an addon-initiated click
--     too, but it could not be checked here.)
--   SimInput routes the click through a simulator-side proxy frame whose handler runs from a
--   clean (secure) call stack, which is what a hardware key press or mouse click looks like to
--   the secure templates.
--
-- This file is the insecure half (loaded as an ordinary addon BEFORE the addon under test so it
-- can see every RegisterForClicks call). The secure half is siminput_secure.lua, injected by
-- run-sim.sh with --exec-lua-secure.
--
-- This is an EMULATION of the client's binding dispatcher, written from how it is generally
-- described to behave (it relies on wow-ui-sim 0.1.41 internals and may break in later versions):
--   key down -> Click(button, true)   only if the button is registered for AnyDown / <Button>Down
--   key up   -> Click(button, false)  only if the button is registered for AnyUp   / <Button>Up
-- It is not evidence of what the real client does.

SimInput = {}

local registrations = setmetatable({}, { __mode = "k" })
local seq = 0

local function record(self, ...)
    registrations[self] = { ... }
end

-- Hook RegisterForClicks on every widget type that has it (they may share one method table).
local hooked = {}
for _, widgetType in ipairs({ "Button", "CheckButton" }) do
    local ok, probe = pcall(CreateFrame, widgetType)
    local mt = ok and probe and getmetatable(probe)
    local methods = mt and mt.__index
    if type(methods) == "table" and not hooked[methods] and type(methods.RegisterForClicks) == "function" then
        hooked[methods] = true
        hooksecurefunc(methods, "RegisterForClicks", record)
    end
    if ok and probe then probe:Hide() end
end

--- The click types last passed to frame:RegisterForClicks(...), or nil if never called
--- after this helper loaded (XML registerForClicks="" attributes are not seen).
function SimInput.GetClickRegistration(frame)
    return registrations[frame]
end

local function proxy()
    local p = SimInputSecureProxy
    if not p then
        error("SimInput: secure proxy missing. Run tests through run-sim.sh (it passes --exec-lua-secure --exec-lua @/simlib/siminput_secure.lua).", 3)
    end
    return p
end

--- Deliver ONE click phase to a button from a secure call stack, like a hardware click.
--- No RegisterForClicks filtering (use KeyDown/KeyUp/PressKey for that).
--- @param frame Button
--- @param mouseButton string|nil  default "LeftButton"
--- @param down boolean|nil        default false (an "up" click)
function SimInput.Click(frame, mouseButton, down)
    assert(type(frame) == "table" and frame.Click, "SimInput.Click: first argument must be a Button")
    local p = proxy()
    seq = seq + 1
    p:SetAttribute("sim-frame", frame)
    p:SetAttribute("sim-button", mouseButton or "LeftButton")
    p:SetAttribute("sim-down", down and true or false)
    p:SetAttribute("sim-click", seq)
end

local function registeredFor(frame, mouseButton, down)
    local reg = registrations[frame] or { "LeftButtonUp" } -- the widget default
    local suffix = down and "Down" or "Up"
    for _, clickType in ipairs(reg) do
        if clickType == "Any" .. suffix or clickType == mouseButton .. suffix then
            return true
        end
    end
    return false
end

local function modifierPrefix()
    local prefix = ""
    if IsAltKeyDown() then prefix = prefix .. "ALT-" end
    if IsControlKeyDown() then prefix = prefix .. "CTRL-" end
    if IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
    return prefix
end

--- What a key resolves to right now (override bindings first, held modifiers applied).
--- @return string|nil action, Button|nil frame, string|nil mouseButton
function SimInput.ResolveKey(key)
    local action = ""
    local prefix = modifierPrefix()
    if prefix ~= "" then action = GetBindingAction(prefix .. key, true) or "" end
    if action == "" then action = GetBindingAction(key, true) or "" end
    if action == "" then return nil end
    local name, mouseButton = action:match("^CLICK (.-):(.+)$")
    if not name then return action end
    return action, _G[name], mouseButton
end

local function keyPhase(key, down)
    local action, frame, mouseButton = SimInput.ResolveKey(key)
    if not action then return false, "no binding on " .. key end
    if not mouseButton then return false, "binding '" .. action .. "' is not a CLICK binding (not emulated)" end
    if not frame then return false, "binding '" .. action .. "' names a frame that does not exist" end
    if not registeredFor(frame, mouseButton, down) then
        return false, action .. " not registered for " .. (down and "down" or "up") .. " clicks (RegisterForClicks)"
    end
    SimInput.Click(frame, mouseButton, down)
    return true, action
end

--- Emulate pressing a bound key: delivers Click(button, true) if the binding is a CLICK
--- binding and the target is registered for a down click. @return boolean delivered, string detail
function SimInput.KeyDown(key) return keyPhase(key, true) end

--- Emulate releasing a bound key. @return boolean delivered, string detail
function SimInput.KeyUp(key) return keyPhase(key, false) end

--- KeyDown followed by KeyUp. @return boolean downDelivered, boolean upDelivered, string detail
function SimInput.PressKey(key)
    local d, detail = keyPhase(key, true)
    local u, detailUp = keyPhase(key, false)
    return d, u, (d or u) and (d and detail or detailUp) or detail
end

--- Run fn after n OnUpdate ticks. run-tests ticks OnUpdate (elapsed 0.016) only inside
--- async_test, so use it there: SimInput.AfterTicks(15, function() done(function() ... end) end)
function SimInput.AfterTicks(n, fn)
    local f = CreateFrame("Frame")
    local count = 0
    f:SetScript("OnUpdate", function(self)
        count = count + 1
        if count >= n then
            self:SetScript("OnUpdate", nil)
            fn()
        end
    end)
end
