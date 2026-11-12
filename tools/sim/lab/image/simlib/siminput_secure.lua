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
