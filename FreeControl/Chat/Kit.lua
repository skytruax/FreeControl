local _, ns = ...
local CK = ns.Chat

-- The parts the keyboard and the quick phrases window are drawn with: their
-- colours and type, rounded boxes, the window look, gamepad glyphs.
--
-- (The part of Easy Controller's ConfigKit.lua that those two use; the rest
-- of that file is its configuration panel's.)
local K = {}
CK.ConfigKit = K

local TEX = CK.TEX
K.TEX = TEX

local function hex(h)
    return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 }
end

K.C = {
    title = hex("F2C43C"), focus = hex("FFD24A"), focusText = hex("FFF3D0"),
    cream = hex("EFE4C8"), grey = hex("9D917A"),
    bronze = hex("7A5D36"), line1 = hex("5A4630"), line2 = hex("4A3A26"),
    bg = hex("16110C"), boxBg = hex("0B0805"), pressed = hex("2A1F12"),
    danger = hex("FF7A5C"), dangerBg = hex("4A140E"), dangerText = hex("FFE0D6"),
    inner = hex("2A1F14"), white = { 1, 1, 1 },
}
local C = K.C

---------------------------------------------------------------------------
-- Type: Friz Quadrata for titles and labels, the chat's font for what is
-- sent to the chat
---------------------------------------------------------------------------
function K.Text(parent, size, color, layer)
    local fs = CK.UIKit.text(parent, size, layer)
    fs:SetWordWrap(false)
    fs:SetJustifyH("LEFT")
    if color then fs:SetTextColor(unpack(color)) end
    return fs
end

local function chatFont()
    return (ChatFontNormal and ChatFontNormal:GetFont()) or STANDARD_TEXT_FONT or "Fonts\\ARIALN.TTF"
end

function K.ChatText(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(chatFont(), size, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetJustifyH("LEFT")
    if color then fs:SetTextColor(unpack(color)) end
    return fs
end

-- A solid colour texture
function K.Solid(parent, color, alpha, layer, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    t:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    return t
end

---------------------------------------------------------------------------
-- Rounded boxes: nine-slices of the ck_box textures (32 texels for 16 px,
-- corners of 4 px), tinted
---------------------------------------------------------------------------
function K.Slice(parent, file, layer, sub)
    local s = { parts = {} }
    local u = 8 / 32
    local cuts = { { 0, u }, { u, 1 - u }, { 1 - u, 1 } }
    for r = 1, 3 do
        for c = 1, 3 do
            local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
            t:SetTexture(TEX .. file)
            t:SetTexCoord(cuts[c][1], cuts[c][2], cuts[r][1], cuts[r][2])
            s.parts[#s.parts + 1] = t
        end
    end
    local tl, t, tr, l, m, rt, bl, b, br = unpack(s.parts)
    function s:SetPoints(region, inset)
        inset = inset or 0
        for _, p in ipairs(self.parts) do p:ClearAllPoints() end
        tl:SetPoint("TOPLEFT", region, "TOPLEFT", inset, -inset)
        tr:SetPoint("TOPRIGHT", region, "TOPRIGHT", -inset, -inset)
        bl:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", inset, inset)
        br:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", -inset, inset)
        for _, corner in ipairs({ tl, tr, bl, br }) do corner:SetSize(4, 4) end
        t:SetPoint("TOPLEFT", tl, "TOPRIGHT"); t:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
        b:SetPoint("TOPLEFT", bl, "TOPRIGHT"); b:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
        l:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); l:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
        rt:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); rt:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
        m:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT"); m:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
    end
    function s:SetColor(color, alpha)
        for _, p in ipairs(self.parts) do p:SetVertexColor(color[1], color[2], color[3], alpha or 1) end
    end
    function s:SetShown(shown)
        for _, p in ipairs(self.parts) do p:SetShown(shown) end
    end
    s:SetPoints(parent)
    return s
end

-- A filled box with an edge: radius 3 (edge 2) or 4 (edge 1 or 2)
function K.Box(parent, radius, edge, layer, sub)
    local box = { fill = K.Slice(parent, format("ck_box%d", radius), layer, sub) }
    if edge then box.line = K.Slice(parent, format("ck_box%d_line%d", radius, edge), layer, (sub or 0) + 1) end
    function box:SetPoints(region, inset)
        self.fill:SetPoints(region, inset)
        if self.line then self.line:SetPoints(region, inset) end
    end
    -- No colour: that part stays hidden (an edge alone, a fill alone)
    function box:SetColors(fill, fillAlpha, line, lineAlpha)
        self.noFill, self.noLine = fill == nil, line == nil
        self.fill:SetShown(fill ~= nil and not self.hidden)
        if fill then self.fill:SetColor(fill, fillAlpha) end
        if self.line then
            self.line:SetShown(line ~= nil and not self.hidden)
            if line then self.line:SetColor(line, lineAlpha) end
        end
    end
    function box:SetShown(shown)
        self.hidden = not shown
        self.fill:SetShown(shown and not self.noFill)
        if self.line then self.line:SetShown(shown and not self.noLine) end
    end
    return box
end

-- The window look: the stone tile, a 2 px bronze edge, a 1 px dark line
-- inside it
function K.Panel(f)
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetTexture(TEX .. "ck_panel_bg", "REPEAT", "REPEAT")
    bg:SetHorizTile(true)
    bg:SetVertTile(true)
    bg:SetAllPoints()
    local under = K.Solid(f, C.bg, 1, "BACKGROUND", -8)
    under:SetAllPoints()
    under:SetDrawLayer("BACKGROUND", -8)
    bg:SetDrawLayer("BACKGROUND", -7)
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
        { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
        local t = K.Solid(f, C.bronze, 1, "BORDER")
        t:SetPoint(e[1]); t:SetPoint(e[2])
        if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
    end
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, -2, nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 2, nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 2, 0, 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", -2, 0, 1, nil } }) do
        local t = K.Solid(f, C.inner, 1, "BORDER", 1)
        t:SetPoint(e[1], e[3], e[4]); t:SetPoint(e[2], e[3], e[4])
        if e[5] then t:SetWidth(e[5]) else t:SetHeight(e[6]) end
    end
end

---------------------------------------------------------------------------
-- Glyphs: the gamepad's buttons (Glyphs.lua: the game's atlases or ours),
-- a grey pill with its name for any other
---------------------------------------------------------------------------
local IMAGE = {
    A = true, B = true, X = true, Y = true, LB = true, RB = true, LT = true, RT = true, LS = true, RS = true,
    DPAD = true, DPAD_LR = true, DPAD_UP = true, DPAD_LEFT = true, DPAD_RIGHT = true, DPAD_DOWN = true,
}
K.IMAGE = IMAGE

function K.Glyph(parent, size)
    local g = CK.NewFrame("Frame", nil, parent)
    g:SetSize(size, size)
    g.size = size
    g.tex = g:CreateTexture(nil, "ARTWORK")
    g.tex:SetAllPoints()
    -- The pill: three pieces of ck_chip (rounded ends, a middle that stretches)
    local h = math.floor(size * 0.72 + 0.5)
    g.chip = {}
    for i, cut in ipairs({ { 0, 22 / 64 }, { 22 / 64, 42 / 64 }, { 42 / 64, 1 } }) do
        local t = g:CreateTexture(nil, "ARTWORK")
        t:SetTexture(TEX .. "ck_chip")
        t:SetTexCoord(cut[1], cut[2], 10 / 64, 54 / 64)
        t:SetHeight(h)
        g.chip[i] = t
    end
    g.chip[1]:SetPoint("LEFT")
    g.chip[1]:SetWidth(h / 2)
    g.chip[3]:SetPoint("RIGHT")
    g.chip[3]:SetWidth(h / 2)
    g.chip[2]:SetPoint("LEFT", g.chip[1], "RIGHT")
    g.chip[2]:SetPoint("RIGHT", g.chip[3], "LEFT")
    g.label = K.ChatText(g, math.max(9, math.floor(size * 0.38)), C.white)
    g.label:SetPoint("CENTER", 0, 0)
    g.label:SetJustifyH("CENTER")
    function g:Set(key)
        local image = IMAGE[key]
        self.tex:SetShown(image)
        for _, t in ipairs(self.chip) do t:SetShown(not image) end
        self.label:SetShown(not image)
        if image then
            CK:SetGlyph(self.tex, key)
            self:SetWidth(self.size)
        else
            self.label:SetText(key)
            self:SetWidth(math.max(self.size * 0.75, self.label:GetStringWidth() + h * 0.6))
        end
        self:Show()
    end
    return g
end

-- A row of glyphs ("LB RB"): keys, "+" for a plus sign; returns its width
function K.GlyphRow(parent, size)
    local row = CK.NewFrame("Frame", nil, parent)
    row:SetSize(1, size)
    row.items = {}
    function row:Set(keys)
        local x = 0
        for i, key in ipairs(keys or {}) do
            local item = self.items[i]
            if not item then
                item = { glyph = K.Glyph(self, size), plus = K.Text(self, 16, C.cream) }
                item.plus:SetText("+")
                self.items[i] = item
            end
            item.glyph:ClearAllPoints()
            item.plus:ClearAllPoints()
            if key == "+" then
                item.glyph:Hide()
                item.plus:Show()
                item.plus:SetPoint("LEFT", x + 2, 0)
                x = x + item.plus:GetStringWidth() + 4
            else
                item.plus:Hide()
                item.glyph:Set(key)
                item.glyph:SetPoint("LEFT", x, 0)
                x = x + item.glyph:GetWidth() + 1
            end
        end
        for i = #(keys or {}) + 1, #self.items do
            self.items[i].glyph:Hide()
            self.items[i].plus:Hide()
        end
        self:SetWidth(math.max(1, x))
        return x
    end
    return row
end
