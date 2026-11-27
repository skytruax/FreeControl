local _, ns = ...
local CK = ns.Chat
local L = CK.L

---------------------------------------------------------------------------
-- Chat integration
--
-- The ChatEdit_* globals are only deprecated aliases (loaded with the
-- loadDeprecationFallbacks CVar): the game itself calls ChatFrameUtil.
--
-- (Easy Controller's Chat.lua: its hooks on the chat and its way of opening
-- the keyboard. Its slash command and its events are FreeControl's own here:
-- /fc keyboard and /fc phrases in Options.lua, ns.On below.)
---------------------------------------------------------------------------
function CK.ActiveChatWindow()
    local get = ChatFrameUtil and ChatFrameUtil.GetActiveWindow or ChatEdit_GetActiveWindow
    return get and get()
end

local function openChat(text)
    local open = ChatFrameUtil and ChatFrameUtil.OpenChat or ChatFrame_OpenChat
    open(text)
end

function CK:IsGamepadActive()
    if self.gamepadActive ~= nil then return self.gamepadActive end
    return C_GamePad ~= nil and C_GamePad.GetActiveDeviceID ~= nil
        and C_GamePad.GetActiveDeviceID() ~= nil
        and GetCVar("GamePadEnable") == "1"
end

function CK:WantsKeyboard(forced)
    if not self:Enabled() then return false end
    local s = self.db.settings
    if not s.modules.keyboard then return false end
    return forced or (s.autoOpen and (not s.onlyWithGamepad or self:IsGamepadActive())) or false
end

-- With the "IM" chat style the edit box stays visible and is "activated"
-- without being typed in: only open when it really has the keyboard focus.
function CK:OnChatActivated(eb)
    local forced = self.forceOpen
    C_Timer.After(0, function()
        if not eb:HasFocus() then return end
        if CK:IsOpen() and CK.editBox == eb then return end
        if not CK:WantsKeyboard(forced) then return end
        if CK:BlockedByCombat() then return end
        CK:Open(eb)
    end)
end

function CK:OnChatDeactivated(eb)
    if eb ~= self.editBox then return end
    -- A mouse click on the keyboard took the chat's focus: keep typing in it
    if self:IsClickingWheel() then
        self:EnterStandalone()
    else
        self:Close("chat deactivated")
    end
end

function CK:HookChat()
    -- Learn slash commands: remember the last text typed in each edit box
    -- (a command is already run and cleared when the text is sent)
    local lastTyped = {}
    local function onSend(eb)
        local text = lastTyped[eb]
        lastTyped[eb] = nil
        -- Sent with Enter on a physical keyboard: the keyboard's copy is sent too
        local boxText = eb.GetText and eb:GetText()
        if eb == CK.editBox and CK:IsOpen() and boxText and boxText:find("[^ \t\r\n]") then
            CK:SetText("")
        end
        if text and text:sub(1, 1) == "/" then CK.Predict:LearnCommand(text) end
    end
    -- The edit box's SendText announces itself (listening taints nothing)
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("ChatFrame.OnEditBoxPreSendText", function(_, eb) onSend(eb) end, CK)
    elseif ChatEdit_SendText then
        hooksecurefunc("ChatEdit_SendText", onSend)
    end

    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb then
            eb:HookScript("OnTextChanged", function(box, userInput)
                local text = box:GetText()
                if text and text ~= "" then lastTyped[box] = text end
                CK:OnChatTextChanged(box, userInput)
            end)
            eb:HookScript("OnEditFocusGained", function(box) CK:OnChatActivated(box) end)
            eb:HookScript("OnEditFocusLost", function(box)
                lastTyped[box] = nil
                CK:OnChatDeactivated(box)
            end)
            eb:HookScript("OnHide", function(box) CK:OnChatDeactivated(box) end)
        end
    end

    -- Learn from every message the player sends (keyboard or controller)
    local function learn(msg)
        CK.justSent = true
        CK.Predict:LearnMessage(msg)
    end
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        hooksecurefunc(C_ChatInfo, "SendChatMessage", learn)
    elseif SendChatMessage then
        hooksecurefunc("SendChatMessage", learn)
    end
end

-- The "Chat keyboard" job (a button on the bar, one under Other buttons, a
-- key binding) and /fc keyboard: open the chat with the keyboard, or close it
function CK:Toggle()
    if not self:Enabled() then return end
    if not self.db.settings.modules.keyboard then
        self:Print(L.KEYBOARD_OFF)
        return
    end
    if self:IsOpen() then
        -- With the chat it is on: nobody is left typing in a chat that has
        -- no keyboard
        self:CloseChat()
        return
    end
    -- The keyboard's keys and its send button cannot be set in a fight
    if self:BlockedByCombat() then return end
    self.forceOpen = true
    local active = CK.ActiveChatWindow()
    if active and active:HasFocus() then
        self:Open(active)
    else
        openChat("")
    end
    self.forceOpen = false
end

---------------------------------------------------------------------------
-- The two jobs' buttons: what a button of the controller given the job, or
-- a key bound to it, clicks (Bindings.lua names them, Bindings.xml lists
-- them). The press opens or closes; the release is nothing.
---------------------------------------------------------------------------
local function ToggleButton(name, onPress)
    local b = CK.NewFrame("Button", name, UIParent)
    b:SetSize(1, 1)
    b:RegisterForClicks("AnyDown")
    b:SetScript("OnClick", onPress)
    return b
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.On("ADDON_LOADED", function(_, name)
    if name == CK.ADDON then CK:InitDB() end
end)

ns.On("PLAYER_LOGIN", function()
    -- The channel is the character's; the rest is made once
    CK:LoadStickyChannel()
    if CK.started then return end
    CK.started = true
    local buttons = ns.Bindings.CHAT_BUTTONS
    ToggleButton(buttons.FREECONTROL_CHATKEYBOARD, function() CK:Toggle() end)
    ToggleButton(buttons.FREECONTROL_PHRASES, function() CK.Phrases:Toggle() end)
    CK.Predict:Load()
    CK:HookChat()
    -- The frames are built now and not at the first chat: a fight is no
    -- time to make a secure button
    if InCombatLockdown() then CK.buildPending = true else CK:BuildUI() end
end)

ns.On("PLAYER_LOGOUT", function()
    CK.Predict:Prune()
end)

if C_EventUtils and C_EventUtils.IsEventValid and C_EventUtils.IsEventValid("GAME_PAD_ACTIVE_CHANGED") then
    ns.On("GAME_PAD_ACTIVE_CHANGED", function(_, active) CK.gamepadActive = active end)
end

ns.On("PLAYER_REGEN_DISABLED", function()
    CK:OnCombatStarting()
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    if CK.buildPending then
        CK.buildPending = false
        CK:BuildUI()
    end
    CK:OnCombatEnded()
end)

-- The game refused something of ours: let go of the controller at once, so
-- that its popup can be answered
local function OnRefused(_, addon)
    if addon == CK.ADDON then CK:Close("refused") end
end
ns.On("ADDON_ACTION_BLOCKED", OnRefused)
ns.On("ADDON_ACTION_FORBIDDEN", OnRefused)
