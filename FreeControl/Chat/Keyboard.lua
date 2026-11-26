local _, ns = ...
local CK = ns.Chat
local L = CK.L

---------------------------------------------------------------------------
-- The keyboard: one whole keyboard, and a highlight that is moved over it
-- with the D-pad or the left stick. A presses the highlighted key. Moving
-- up from the top row goes to the suggestions above it (Message.lua).
--
-- This is FreeControl's own. Easy Controller has two keyboards, a daisywheel
-- and a keyboard cut in two halves with a cursor for each stick, and both
-- were ported first and dropped: typing with the sticks and the triggers
-- did not suit a bar whose triggers are its layers. What is kept of its
-- split keyboard (StickKeyboard.lua) is the keys: the layouts below, the
-- 123 layer whose accents follow the language, and the look of a key.
---------------------------------------------------------------------------
local M = { key = "keys", width = 600, areaWidth = 580, height = 220 }
CK.Keyboard = M

function M:Help()
    return {
        { "DPAD", L.HELP_MOVE }, { "A", L.HELP_TYPE }, { "X", L.BACKSPACE }, { "Y", L.SEND },
        { "LB", L.HELP_CHANNEL }, { "RB", L.HELP_CHANNEL }, { "B", L.HELP_CLOSE },
    }
end

-- Keys: a character, or { k = special key }
local function special(k) return { k = k } end
local SHIFT, BACK, LAYER, SPACE = special("SHIFT"), special("BACK"), special("LAYER"), special("SPACE")
-- A key of the 123 layer showing the language's n-th accent (CK:Accents())
local function accent(n) return { acc = n } end

local LAYOUTS = {
    azerty = {
        { "a", "z", "e", "r", "t", "y", "u", "i", "o", "p" },
        { "q", "s", "d", "f", "g", "h", "j", "k", "l", "m" },
        { SHIFT, "w", "x", "c", "v", "b", "n", "'", BACK },
        { LAYER, ",", "-", SPACE, ".", "?", "!" },
    },
    qwerty = {
        { "q", "w", "e", "r", "t", "y", "u", "i", "o", "p" },
        { "a", "s", "d", "f", "g", "h", "j", "k", "l", "'" },
        { SHIFT, "z", "x", "c", "v", "b", "n", "m", BACK },
        { LAYER, ",", "-", SPACE, ".", "?", "!" },
    },
    qwertz = {
        { "q", "w", "e", "r", "t", "z", "u", "i", "o", "p" },
        { "a", "s", "d", "f", "g", "h", "j", "k", "l", "ö" },
        { SHIFT, "y", "x", "c", "v", "b", "n", "m", BACK },
        { LAYER, "ä", "ü", SPACE, "ß", ".", "," },
    },
    qwerty_es = {
        { "q", "w", "e", "r", "t", "y", "u", "i", "o", "p" },
        { "a", "s", "d", "f", "g", "h", "j", "k", "l", "ñ" },
        { SHIFT, "z", "x", "c", "v", "b", "n", "m", BACK },
        { LAYER, ",", "-", SPACE, ".", "?", "!" },
    },
    qwerty_it = {
        { "q", "w", "e", "r", "t", "y", "u", "i", "o", "p" },
        { "a", "s", "d", "f", "g", "h", "j", "k", "l", "'" },
        { SHIFT, "z", "x", "c", "v", "b", "n", "m", BACK },
        { LAYER, ",", "è", SPACE, ".", "?", "!" },
    },
    symbols = {
        { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" },
        { accent(1), accent(2), accent(3), accent(4), accent(5), accent(6), accent(7), accent(8), accent(9), accent(10) },
        { SHIFT, accent(11), accent(12), "œ", "@", "/", ":", ";", BACK },
        { LAYER, "(", ")", SPACE, "\"", "%", "+" },
    },
}
M.LAYOUTS = LAYOUTS

-- Ten columns of 54 on a pitch of 58, four rows of 50 on a pitch of 54. A
-- key's place in each row: the column it starts in and how many it spans
-- (Delete two, Space four). Every layout has the same keys in the same
-- places, so the highlight keeps its place when the 123 layer comes up.
local KEY_W, KEY_H, PITCH_X = 54, 50, 58
local ROW_Y = { 4, 58, 112, 166 }
local ROW_COLS = {
    { { 1, 1 }, { 2, 1 }, { 3, 1 }, { 4, 1 }, { 5, 1 }, { 6, 1 }, { 7, 1 }, { 8, 1 }, { 9, 1 }, { 10, 1 } },
    { { 1, 1 }, { 2, 1 }, { 3, 1 }, { 4, 1 }, { 5, 1 }, { 6, 1 }, { 7, 1 }, { 8, 1 }, { 9, 1 }, { 10, 1 } },
    { { 1, 1 }, { 2, 1 }, { 3, 1 }, { 4, 1 }, { 5, 1 }, { 6, 1 }, { 7, 1 }, { 8, 1 }, { 9, 2 } },
    { { 1, 1 }, { 2, 1 }, { 3, 1 }, { 4, 4 }, { 8, 1 }, { 9, 1 }, { 10, 1 } },
}
local AREA_PAD = 2
-- Where the highlight starts: the middle of the second row
local START_ROW, START_KEY = 2, 5

-- Text colours by state
local COLOR = {
    char = { 1, 0.82, 0 }, special = { 0.85, 0.79, 0.63 }, lit = { 1, 0.94, 0.78 },
    hover = { 1, 0.96, 0.85 }, pressed = { 0, 0, 0 },
}
local PRESSED_TIME = 0.12

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
local function buildKey(parent, def, row, index)
    local K = CK.UIKit
    local col, span = ROW_COLS[row][index][1], ROW_COLS[row][index][2]
    local x, y = AREA_PAD + (col - 1) * PITCH_X, ROW_Y[row]
    local w = span * PITCH_X - (PITCH_X - KEY_W)
    local b = CK.NewFrame("Button", nil, parent)
    K.place(b, parent, x, y, w, KEY_H)
    b.base = K.nineSlice(b, "ck_sk_key_normal", 128, 64, 12, 12, "BORDER")
    b.file = "ck_sk_key_normal"
    local isChar = type(def) == "string"
    b.accent = type(def) == "table" and def.acc or nil
    b.label = K.text(b, (isChar or b.accent) and 20 or 13)
    b.label:SetPoint("CENTER", 0, 1)
    b.label:SetShadowOffset(1, -1)
    b.char = isChar and def or nil
    b.special = type(def) == "table" and def.k or nil
    -- Where it is, for moving the highlight up and down
    b.row, b.index = row, index
    b.left, b.right, b.cx = x, x + w, x + w / 2
    b:SetScript("OnClick", function() M:Press(b) end)
    b:SetScript("OnEnter", function() M.hover = b; M:Update() end)
    b:SetScript("OnLeave", function() M.hover = nil; M:Update() end)
    return b
end

function M:Build(area)
    self.area = area
    self.sets = {}
    for name, rows in pairs(LAYOUTS) do
        local set = CK.NewFrame("Frame", nil, area)
        set:SetAllPoints()
        set.rows = {}
        set.keys = {}
        for r, row in ipairs(rows) do
            set.rows[r] = {}
            for n, def in ipairs(row) do
                local key = buildKey(set, def, r, n)
                set.rows[r][n] = key
                set.keys[#set.keys + 1] = key
            end
        end
        set:Hide()
        self.sets[name] = set
    end
    self:Reset()
end

function M:ActiveSet()
    if CK.state.layer == "symbols" then return self.sets.symbols end
    return self.sets[CK.db.settings.kbLayout] or self.sets.qwerty
end

---------------------------------------------------------------------------
-- The highlight: a row and a key in it, the same on every layer
---------------------------------------------------------------------------
function M:Reset()
    self.row, self.index, self.navX = START_ROW, START_KEY, nil
end

-- The key that is highlighted
function M:Focused()
    local set = self.sets and self:ActiveSet()
    local row = set and set.rows[self.row]
    return row and row[self.index]
end

-- How far a place across the keyboard is from a key (0 inside it)
local function gap(key, x)
    if x < key.left then return key.left - x end
    if x > key.right then return x - key.right end
    return 0
end

-- Moves the highlight one key: dx across (past the end of a row it comes
-- round to the other end), dy down. Going up and down it keeps to the place
-- across that it started from, so that down through Space and up again is
-- the key it left. False when there is no row that way.
function M:Move(dx, dy)
    local set = self:ActiveSet()
    if dx ~= 0 then
        local row = set.rows[self.row]
        self.index = (self.index - 1 + dx) % #row + 1
        self.navX = nil
    else
        local row = set.rows[self.row + dy]
        if not row then return false end
        local x = self.navX or self:Focused().cx
        local best, bestGap, bestOff
        for n, key in ipairs(row) do
            local g, off = gap(key, x), math.abs(key.cx - x)
            if not best or g < bestGap or (g == bestGap and off < bestOff) then
                best, bestGap, bestOff = n, g, off
            end
        end
        self.row, self.index, self.navX = self.row + dy, best, x
    end
    self:Update()
    return true
end

---------------------------------------------------------------------------
-- Typing
---------------------------------------------------------------------------
function M:Flash(key)
    local untilTime = GetTime() + PRESSED_TIME
    key.pressedUntil = untilTime
    C_Timer.After(PRESSED_TIME, function()
        if key.pressedUntil == untilTime then key.pressedUntil = nil end
        if M.sets then M:Update() end
    end)
end

function M:Press(key)
    if not key then return end
    self:Flash(key)
    if key.char then
        CK:TypeChar(key.char)
    elseif key.special == "SHIFT" then
        CK:ToggleShift()
    elseif key.special == "BACK" then
        CK:Backspace()
    elseif key.special == "LAYER" then
        CK:ToggleSymbols()
    elseif key.special == "SPACE" then
        CK:Space()
    end
    self:Update()
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------
local SPECIAL_LABEL = { SHIFT = "SHIFT", BACK = "BACKSPACE", SPACE = "SPACE" }

function M:Update()
    if not self.sets then return end
    local state = CK.state
    local set = self:ActiveSet()
    for _, s in pairs(self.sets) do s:SetShown(s == set) end

    -- The highlight is on the keys unless it has gone up to the suggestions
    local focused = state.activeRow ~= "suggestions" and self:Focused() or nil
    local shiftOn = state.shift or state.caps
    local accents = CK:Accents()

    local now = GetTime()
    for _, key in ipairs(set.keys) do
        local active = (key.special == "SHIFT" and shiftOn) or (key.special == "LAYER" and state.layer == "symbols")
        local pressed = key.pressedUntil and now < key.pressedUntil
        local file = pressed and "ck_sk_key_pressed"
            or (key == focused and "ck_sk_key_target_l")
            or (active and "ck_sk_key_active")
            or (key == self.hover and "ck_sk_key_hover")
            or "ck_sk_key_normal"
        if file ~= key.file then
            key.base:SetFile(file)
            key.file = file
        end

        if key.accent then key.char = accents[key.accent] end
        if key.char then
            key.label:SetText(CK:DisplayChar(key.char))
        elseif key.special == "LAYER" then
            key.label:SetText(state.layer == "symbols" and L.LETTERS or L.SYMBOLS)
        else
            key.label:SetText(L[SPECIAL_LABEL[key.special]])
        end
        local color = pressed and COLOR.pressed or ((key == focused or active) and COLOR.lit)
            or (key == self.hover and COLOR.hover) or ((key.char or key.accent) and COLOR.char) or COLOR.special
        key.label:SetTextColor(unpack(color))
        key.label:SetShadowColor(0, 0, 0, pressed and 0 or 1)
    end
end

---------------------------------------------------------------------------
-- The pad: the D-pad and the left stick move, A presses (Input.lua)
---------------------------------------------------------------------------
-- How many places the suggestions row has to go to: its words, and the
-- quick phrases' bubble after them
local function suggestionStops()
    return #CK.state.suggestions + (CK:PhrasesChipShown() and 1 or 0)
end

function CK:MoveHighlight(dx, dy)
    local state = self.state
    if state.activeRow == "suggestions" then
        if dx ~= 0 then
            self:SelectSuggestion(dx)
        elseif dy > 0 then
            self:SetActiveRow("keys")
        end
        return
    end
    -- Up from the top row: the suggestions, when there is one to go to
    if not M:Move(dx, dy) and dy < 0 and suggestionStops() > 0 then
        self:SetActiveRow("suggestions")
    end
end

function CK:MoveUp() self:MoveHighlight(0, -1) end
function CK:MoveDown() self:MoveHighlight(0, 1) end
function CK:MoveLeft() self:MoveHighlight(-1, 0) end
function CK:MoveRight() self:MoveHighlight(1, 0) end

-- A: the highlighted key is typed, the highlighted suggestion taken
function CK:PressFocus()
    if self.state.activeRow == "suggestions" then
        self:AcceptSuggestion()
    else
        M:Press(M:Focused())
    end
end

-- The suggestions change with every letter: with none left to be on, the
-- highlight is back on the keys
function CK:KeepHighlight()
    if self.state.activeRow == "suggestions" and suggestionStops() == 0 then
        self.state.activeRow = "keys"
    end
end
