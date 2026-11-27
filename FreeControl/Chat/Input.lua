local _, ns = ...
local CK = ns.Chat

-- Pad buttons while the keyboard is open. Only the four face buttons do
-- something of their own; the D-pad (and the left stick) moves the highlight
-- and the bumpers go through the channels, as they do in the quick phrases:
--
--   D-pad, left stick   move the highlight: over the keys, and up from the
--                       top row to the suggestions
--   A                   press what is highlighted: type the key, take the
--                       suggestion
--   X                   delete (held: goes on deleting)
--   Y                   send (the secure macro button); in a prompt, confirm
--   B                   empty the message; on an empty one, close the chat
--   LB / RB             the channel before / after
--
-- Space, Shift and 123 are keys of the keyboard, not buttons. Nothing else
-- of the controller is the keyboard's.
--
-- (Not Easy Controller's buttons: its two keyboards type with the sticks and
-- the triggers, and A sends. This keyboard is FreeControl's own, see
-- Keyboard.lua.)
--
-- The buttons are named as the game names them (PAD1 is the bottom face
-- button, A), not by FreeControl's own key settings: the keyboard is laid
-- out for the controller as it is held.
local ACTIONS = {
    PADDUP = "MoveUp",
    PADDDOWN = "MoveDown",
    PADDLEFT = "MoveLeft",
    PADDRIGHT = "MoveRight",
    PAD1 = "PressFocus",
    PAD3 = "Backspace",
    PADLSHOULDER = "PrevChannel",
    PADRSHOULDER = "NextChannel",
}

-- Actions repeated while the button (or stick) is held
local REPEATABLE = { Backspace = true, MoveUp = true, MoveDown = true, MoveLeft = true, MoveRight = true }
local REPEAT_DELAY, REPEAT_RATE = 0.45, 0.08

-- The left stick moves the highlight like the D-pad: pushed past STICK_IN it
-- is a press of that direction, held there it repeats, and it has to come
-- back under STICK_OUT before it counts again
local STICK_IN, STICK_OUT = 0.6, 0.35
local STICK_MOVES = { "MoveUp", "MoveRight", "MoveDown", "MoveLeft" }

-- The direction a stick is pushed in (1 up, 2 right, 3 down, 4 left), or nil
-- while it is near its centre. `held`: the direction it was in before, which
-- it keeps until it is let go.
function CK.StickDirection(x, y, held)
    local len = math.sqrt(x * x + y * y)
    if len < (held and STICK_OUT or STICK_IN) then return nil end
    if held then return held end
    if math.abs(x) > math.abs(y) then return x > 0 and 2 or 4 end
    return y > 0 and 1 or 3
end

function CK:SetLeftStick(x, y)
    if self.db.settings.invertY then y = -y end
    local direction = CK.StickDirection(x, y, self.stickHeld)
    if direction == self.stickHeld then return end
    self.stickHeld = direction
    if self.repeatButton == "LEFTSTICK" then self.repeatFn = nil end
    if direction then self:RunAction(STICK_MOVES[direction], "LEFTSTICK") end
end

-- The right stick has no job here; it is taken all the same, so that the
-- camera stays still while the keyboard is up
function CK:SetRightStick() end

function CK:RunAction(action, button)
    self[action](self)
    if REPEATABLE[action] then
        self.repeatFn = action
        self.repeatButton = button
        self.repeatAt = GetTime() + REPEAT_DELAY
    end
end

-- B: without the chat (a mouse click on the keyboard took its focus, a
-- phrase being written) it closes the keyboard; on the chat, see
-- CK:CancelMessage
function CK:ButtonAction(button)
    if button == "PAD2" then
        return self.standalone and "Close" or "CancelMessage"
    end
    return ACTIONS[button]
end

function CK:OnPadButton(button)
    if self.db.settings.debug then
        self:Print("button %s", tostring(button))
    end
    self.padDown = self.padDown or {}
    self.padDown[button] = true
    local action = self:ButtonAction(button)
    if action then
        self:RunAction(action, button)
    end
end

function CK:OnPadButtonUp(button)
    if self.padDown then self.padDown[button] = nil end
    if button == self.repeatButton then
        self.repeatFn = nil
    end
    -- B let go on an empty message: the chat closes, and the keyboard with it
    if button == "PAD2" and self.closeOnRelease then
        self.closeOnRelease = nil
        self:CloseChat()
    end
end

function CK:OnUpdate()
    local now = GetTime()

    -- Safety net: the chat lost the focus without any event we hooked
    if not self.standalone and not (self.editBox and self.editBox:HasFocus()) then
        if self:IsClickingWheel() then
            self:EnterStandalone()
        else
            self:Close("focus lost (OnUpdate)")
            return
        end
    end

    -- Fallback when OnGamePadStick never fires: poll the device state
    if not self.stickEvents and C_GamePad and C_GamePad.GetDeviceMappedState then
        local id = C_GamePad.GetActiveDeviceID and C_GamePad.GetActiveDeviceID()
        local st = id and C_GamePad.GetDeviceMappedState(id)
        local sticks = st and st.sticks
        if sticks and sticks[1] then self:SetLeftStick(sticks[1].x or 0, sticks[1].y or 0) end
    end

    self:CheckBindings(now)

    if self.repeatFn and now >= self.repeatAt then
        self[self.repeatFn](self)
        self.repeatAt = now + REPEAT_RATE
    end
end

-- The keyboard's keys kept while it is open. FreeControl's bar lets go of
-- its own for that time (CK:SyncInput), so nothing of the addon's competes;
-- this is for whatever else binds a key over the keyboard's. Looked at five
-- times a second; ours set again when another took one, never more than a
-- few times in a row (no endless back and forth with whoever wants the key).
local CHECK_EVERY, RESTORE_WINDOW, MAX_RESTORES = 0.2, 3, 5

function CK:CheckBindings(now)
    if not (self.bindingsActive and self.keyboardBinds) or InCombatLockdown() or not GetBindingAction then return end
    if now < (self.nextBindCheck or 0) then return end
    self.nextBindCheck = now + CHECK_EVERY
    for key, action in pairs(self.keyboardBinds) do
        local current = GetBindingAction(key, true)
        if current ~= action then
            local restores = self.bindRestores or {}
            while restores[1] and restores[1] < now - RESTORE_WINDOW do table.remove(restores, 1) end
            self.bindRestores = restores
            self.lastTaken = { key = key, by = current, time = now }
            if #restores >= MAX_RESTORES then return end
            restores[#restores + 1] = now
            if self.db.settings.debug then
                self:Print("%s taken by %s: the keyboard's set again", key, tostring(current))
            end
            self:EnableButtons()
            return
        end
    end
end

---------------------------------------------------------------------------
-- Buttons
--
-- While the keyboard is open, each pad button is bound (override binding)
-- to "click" a hidden button. Pad buttons keep working while the chat edit
-- box has the focus, and Y clicks a secure macro button that sends the text
-- with "/s ...", "/p ..." etc.: the game itself sends the message.
-- In combat bindings and attributes are locked: the keyboard is closed as a
-- fight starts.
---------------------------------------------------------------------------
local function bindingButtonName(key)
    return "FreeControlChatPad" .. key
end

-- A button held may add a modifier to the keys (a controller button can
-- stand in for Shift, Ctrl or Alt): pressed with one held, a key is still
-- the keyboard's
local PREFIXES = { "", "SHIFT-", "CTRL-", "ALT-", "CTRL-SHIFT-", "ALT-SHIFT-", "ALT-CTRL-", "ALT-CTRL-SHIFT-" }
local function bind(f, key, button)
    for _, prefix in ipairs(PREFIXES) do SetOverrideBindingClick(f, true, prefix .. key, button) end
    -- What the key must run while the keyboard is open (see CK:CheckBindings)
    if CK.keyboardBinds then CK.keyboardBinds[key] = "CLICK " .. button .. ":LeftButton" end
end

local SEND_KEY = "PAD4"
local SEND_BUTTON = "FreeControlChatSend"
-- Y in a prompt (a phrase being written): confirms, nothing is sent
local PROMPT_BUTTON = "FreeControlChatPrompt"

function CK:CreateButtons()
    -- One hidden button per pad button the keyboard uses, plus B
    local keys = { "PAD2" }
    for key in pairs(ACTIONS) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do
        local b = CK.NewFrame("Button", bindingButtonName(key))
        b:SetSize(1, 1)
        b:RegisterForClicks("AnyDown", "AnyUp")
        b:SetScript("OnClick", function(_, _, down)
            if down == false then
                CK:OnPadButtonUp(key)
            else
                CK:OnPadButton(key)
            end
        end)
    end

    local ok = CK.NewFrame("Button", PROMPT_BUTTON)
    ok:SetSize(1, 1)
    ok:RegisterForClicks("AnyDown")
    ok:SetScript("OnClick", function() CK:FinishPrompt(true) end)

    -- Secure macro button: Y clicks it, and it lies over the "Send" button
    -- for the mouse
    local s = CK.NewFrame("Button", SEND_BUTTON, nil, "SecureActionButtonTemplate")
    s:SetAttribute("type", "macro")
    s:SetAttribute("macrotext", "")
    s:RegisterForClicks("AnyDown", "AnyUp")
    s:SetFrameStrata("FULLSCREEN_DIALOG")
    -- The overlay takes the mouse: light up the visible "Send" button below
    local function hover(on)
        local send = CK.frame and CK.frame.actions.Send
        if send then
            send.hover = on
            send:Render()
        end
    end
    s:SetScript("OnEnter", function() hover(true) end)
    s:SetScript("OnLeave", function() hover(false) end)
    s:SetScript("PreClick", function(_, _, down) CK:PrepareSend(down) end)
    s:SetScript("PostClick", function(_, _, down) CK:FinishSend(down) end)
    s:Hide()
    self.sendButton = s
end

-- Runs before the secure click: put the current message in the macro
function CK:PrepareSend(down)
    self.justSent = false
    if InCombatLockdown() then return end
    self.sendButton:SetAttribute("macrotext", self:BuildMacroText() or "")
    self:SendWhisper()
end

-- Whispers go straight through SendChatMessage with the full name: a macro
-- "/w Fraicheur Hunt hi" would whisper "Fraicheur". Whispers need no hardware
-- event and the game's chat box is not touched.
function CK:SendWhisper()
    local target = self:GetChatAttr("tellTarget")
    local chatType = self:GetChatAttr("chatType")
    if (chatType ~= "WHISPER" and chatType ~= "BN_WHISPER") or self:GetChatAttr("reply")
        or not target or target == "" then
        return
    end
    local text = self:GetText():gsub("[\r\n]", " ")
    if text:match("^[ \t\r\n]*$") then return end
    -- A command (/g, /dance...): the macro runs it, nothing is whispered
    if text:sub(1, 1) == "/" then return end
    -- PreClick runs on both press and release: send once
    local now = GetTime()
    if self.lastWhisper == text and now - (self.lastWhisperTime or 0) < 0.5 then return end
    self.lastWhisper, self.lastWhisperTime = text, now
    if chatType == "BN_WHISPER" then
        -- A Battle.net friend, as the game's chat box sends it
        local account = BNet_GetBNetIDAccount and BNet_GetBNetIDAccount(target)
        local send = C_BattleNet and C_BattleNet.SendWhisper or BNSendWhisper
        if not (account and send) then return end
        send(account, text)
        self.justSent = true
        CK.Predict:LearnMessage(text)
        return
    end
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    send(text, "WHISPER", nil, target)
end

-- Runs after the secure click: once the game sent the message, clear it
-- (the chat stays open for the next message; B closes it)
function CK:FinishSend(down)
    local text = self:GetText()
    -- /w without a recipient yet: Y confirms the typed name (a command typed
    -- there is run, not taken for a name)
    if self:WhisperNameMode() and text:sub(1, 1) ~= "/" and not text:find("|H", 1, true) then
        if down ~= true then self:ConfirmWhisperTarget(text) end
        return
    end
    local slashCommand = text:sub(1, 1) == "/" and down ~= true
    if self.justSent or slashCommand then
        -- A message, not a command: its channel is the one to come back to
        if self.justSent and text:sub(1, 1) ~= "/" then self:RememberChannel() end
        self.justSent = false
        if not InCombatLockdown() then
            self.sendButton:SetAttribute("macrotext", "")
        end
        if slashCommand then CK.Predict:LearnCommand(text) end
        local box = self.editBox and self.editBox:GetText()
        self.sentBoxText = (box and box ~= "") and box or nil
        self:SetText("")
        if self.standalone then self:Close("sent") end
    end
end

-- The secure "Send" button is placed over the visible one with screen
-- coordinates, never anchored to it: a frame a protected frame is anchored to
-- becomes protected too, and the keyboard could no longer be shown in combat.
function CK:PositionSendButton()
    local s, send = self.sendButton, self.frame and self.frame.actions.Send
    if not (s and send) or InCombatLockdown() or not send:GetLeft() then return end
    s:SetScale(send:GetEffectiveScale())
    s:ClearAllPoints()
    s:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", send:GetLeft(), send:GetBottom())
    s:SetSize(send:GetWidth(), send:GetHeight())
    s:EnableMouse(self.db.settings.showActions and true or false)
end

-- Override bindings can't change in combat: the keyboard (and its bindings)
-- is closed just before combat starts, when PLAYER_REGEN_DISABLED still allows it.
function CK:EnableButtons()
    local f = self.frame
    if InCombatLockdown() then return end
    ClearOverrideBindings(f)
    self.keyboardBinds = {}
    for key in pairs(ACTIONS) do bind(f, key, bindingButtonName(key)) end
    -- B: empties the message, then closes (the chat, or the keyboard alone)
    bind(f, "PAD2", bindingButtonName("PAD2"))
    self.bindingsActive = true
    if self.prompt then
        -- A prompt: Y confirms, nothing goes to the chat
        bind(f, SEND_KEY, PROMPT_BUTTON)
        self.sendButton:Hide()
    else
        -- Y sends the keyboard's buffer (the chat edit box stays empty)
        bind(f, SEND_KEY, SEND_BUTTON)
        self:PositionSendButton()
        self.sendButton:Show()
    end
    self:SyncInput()
end

function CK:DisableButtons()
    self.padDown = nil
    self.keyboardBinds = nil
    self.stickHeld = nil
    if not self.bindingsActive or InCombatLockdown() then return end
    ClearOverrideBindings(self.frame)
    self.sendButton:Hide()
    self.sendButton:SetAttribute("macrotext", "")
    self.bindingsActive = false
    self:SyncInput()
end

---------------------------------------------------------------------------
-- The controller is the window's while one is open
---------------------------------------------------------------------------
-- A button the keyboard or the phrases window is using right now. While one
-- is, the game must not hold it as Shift, Ctrl or Alt: a button used that
-- way only reports a press when tapped, so LB would change the channel late
-- or not at all. FreeControl looks after those settings (CVars.lua), and
-- asks here.
function CK:HoldsKey(button)
    if self.bindingsActive and self.keyboardBinds and self.keyboardBinds[button] then return true end
    return CK.Phrases ~= nil and CK.Phrases:HoldsKey(button)
end

-- True while the keyboard or the phrases window has its keys bound.
function CK:HasController()
    return (self.bindingsActive or (CK.Phrases ~= nil and CK.Phrases.bound)) and true or false
end

-- Called whenever the keyboard or the phrases window takes its keys or
-- gives them up. While either has them, FreeControl's bar lets go of every
-- button of its own (Bindings:Suspend), and takes them back after.
--
-- Leaving the bar's bindings under the window's did not work: the bar binds
-- its D-pad and face buttons again whenever a trigger is pressed or let go
-- (its secure header does, Bindings.lua), and the binding made last is the
-- one in force. A window opened from a button on a trigger's layer lost its
-- D-pad, A and B the moment the trigger was released, and kept only the
-- bumpers, which the bar does not bind.
function CK:SyncInput()
    if not ns.db or InCombatLockdown() then return end
    if self:HasController() then
        ns.Bindings:Suspend()
    else
        ns.Bindings:Resume()
    end
    if ns.IsActive() then ns.CVars:Apply() end
end

-- The windows are worked with the D-pad and the left stick. While
-- FreeControl's mouse pointer is out (Mouse.lua) the two click buttons are
-- mouse buttons and the game may take the sticks: the pointer is put away
-- as a window opens. A real mouse is not touched by this.
function CK:TakeSticks()
    if ns.Mouse and ns.Mouse:IsOut() then ns.Mouse:PutAway(false) end
end

function CK:OnCombatStarting()
    self.reopenAfterCombat = self:IsOpen() and self.editBox or nil
    self:Close("combat")
    self:DisableButtons()
end

-- Back after combat if the chat is still being typed in
function CK:OnCombatEnded()
    -- Closed in the middle of a fight (the game refused something): its keys
    -- could not be given up then
    if self.bindingsActive and not self:IsOpen() then self:DisableButtons() end
    local eb = self.reopenAfterCombat
    self.reopenAfterCombat = nil
    if not eb and self:WantsKeyboard() then
        local active = CK.ActiveChatWindow()
        if active and active:HasFocus() then eb = active end
    end
    if eb and eb:HasFocus() and not self:IsOpen() then
        self:Open(eb)
    end
end

---------------------------------------------------------------------------
-- Sticks
---------------------------------------------------------------------------
local LEFT_STICKS = { Left = true, Movement = true }
local RIGHT_STICKS = { Right = true, Camera = true }
CK.LEFT_STICKS = LEFT_STICKS

function CK:SetupInput(f)
    self:CreateButtons()
    if f.EnableGamePadStick then
        f:EnableGamePadStick(true)
        f:SetScript("OnGamePadStick", function(_, stick, x, y)
            if CK.db.settings.debug then
                CK.seenSticks = CK.seenSticks or {}
                if not CK.seenSticks[stick] then
                    CK.seenSticks[stick] = true
                    CK:Print("stick %s", tostring(stick))
                end
            end
            if LEFT_STICKS[stick] then
                CK.stickEvents = true
                CK:SetLeftStick(x or 0, y or 0)
            elseif RIGHT_STICKS[stick] then
                CK.stickEvents = true
                CK:SetRightStick(x or 0, y or 0)
            end
        end)
    end
    f:SetScript("OnUpdate", function() CK:OnUpdate() end)
end
