-- Secure half of SimInput. Executed by wow-sim with --exec-lua-secure, after login events and
-- before the test files load. Creates a forbidden (not protected) proxy frame: the simulator
-- dispatches OnAttributeChanged on protected/forbidden frames with the caller's taint cleared,
-- and a frame that is forbidden-but-not-protected is still writable during combat lockdown.
local proxy = CreateFrame("Frame", "SimInputSecureProxy")
proxy:SetForbidden(true)
proxy:SetScript("OnAttributeChanged", function(self, name, value)
    if name ~= "sim-click" or value == nil then
        return
    end
    local frame = self:GetAttribute("sim-frame")
    if frame then
        frame:Click(self:GetAttribute("sim-button") or "LeftButton", self:GetAttribute("sim-down") and true or false)
    end
end)

-- Stances and forms. The simulator has none: no class changes form in it, no stance bar ever
-- comes up, and its macro conditions say so. Blizzard's state driver asks SecureCmdOptionParse
-- which stance bar is up ("[bonusbar:N]"), so that is the one place a test can put a stance in.
-- The answer comes from an attribute on the proxy above (SimInput.SetStanceBar sets it), read
-- here in secure code: a function installed by a test would taint the driver, and the simulator
-- then refuses its work in combat, as the client would.
--
-- Only condition lists that ask about the bonus bar are answered here, and only that condition
-- is understood in them; everything else goes to the simulator's own parser.
--
-- The function is put among the real globals with getfenv(0): this script's own globals, _G
-- included, are kept apart from everyone else's (an assignment to either is seen by nobody), and
-- Blizzard's driver looks the parser up among the real ones each time it runs.
local simParse = SecureCmdOptionParse
getfenv(0).SecureCmdOptionParse = function(options)
    if type(options) ~= "string" or not options:find("bonusbar", 1, true) then
        return simParse(options)
    end
    local bar = tonumber(proxy:GetAttribute("sim-bonusbar")) or 0
    for clause in (options .. ";"):gmatch("%s*([^;]*);") do
        local condition, value = clause:match("^%[(.-)%]%s*(.-)%s*$")
        if not condition then
            return (clause:match("^%s*(.-)%s*$"))
        end
        local wanted = condition:match("^bonusbar:(%d+)$")
        if not wanted then
            error("SimInput: in a list that asks about the bonus bar, only [bonusbar:N] is modelled; got [" .. condition .. "]")
        end
        if tonumber(wanted) == bar then
            return value
        end
    end
    return nil
end
