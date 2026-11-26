local ADDON, ns = ...

---------------------------------------------------------------------------
-- The chat keyboard and the quick phrases
--
-- Everything in this folder is ported from Easy Controller - Forever by
-- moust4ki (https://github.com/moust4ki/EasyControllerWowForever, MIT; see
-- LICENSE-EasyController.txt beside this file): the frame of its controller
-- keyboard for the chat, its word prediction, its channel row and its quick
-- phrases. The files keep its names, its layout and its table, CK, which
-- here is FreeControl's ns.Chat.
--
-- What is different from the original:
--   * The keyboard itself is FreeControl's own (Keyboard.lua): one whole
--     keyboard with a highlight moved by the D-pad, in place of Easy
--     Controller's daisywheel and split keyboard, which are typed with the
--     sticks and the triggers. Its buttons are different too (Input.lua).
--   * Easy Controller is made for the game's Gamepad UI, FreeControl for the
--     normal interface. There is no gamepad chat footer here whose B closes
--     the chat, so B on an empty message closes it itself (Message.lua).
--   * While the keyboard or the phrases window is open, FreeControl's bar
--     lets go of its buttons (Input.lua, CK:SyncInput).
--   * Only the chat parts came over: no quest links, no drafts, no keyboard
--     for the game's other fields.
--   * The text is English only, like the rest of FreeControl (Locale.lua).
--     The dictionaries and keyboard layouts of all five languages are here.
--   * The channel last written on is kept for each character between
--     sessions (Message.lua), not until the next reload only.
---------------------------------------------------------------------------
local CK = {}
ns.Chat = CK

CK.ADDON = ADDON
CK.Dicts = {}
CK.TEX = "Interface\\AddOns\\" .. ADDON .. "\\Chat\\Textures\\"

---------------------------------------------------------------------------
-- Saved settings: the account's (FreeControlChatDB), the same for every
-- character, with the words learned and the phrases
---------------------------------------------------------------------------
local DEFAULTS = {
    autoOpen = true,         -- the keyboard opens with the chat
    onlyWithGamepad = false, -- ...only while the controller is the device in use
    learn = true,
    -- Suggestions and keyboard layout follow the client's language by default
    lang = ({ frFR = "fr", deDE = "de", esES = "es", esMX = "es", itIT = "it" })[GetLocale()] or "en",
    maxWords = 8000,
    numSuggestions = 5,
    scale = 1,
    invertY = false,
    locked = true,
    -- The keyboard itself can be turned off (the phrases stay)
    modules = { keyboard = true },
    kbLayout = ({ frFR = "azerty", deDE = "qwertz", esES = "qwerty_es", esMX = "qwerty_es",
        itIT = "qwerty_it" })[GetLocale()] or "qwerty",
    showActions = true,      -- the row of buttons for the mouse under the keys
    stickyChannel = true,    -- the keyboard reopens on the channel last written on
    -- The quick phrases' bubble at the end of the keyboard's suggestions
    -- (Phrases.lua); the phrases themselves: settings.phrases, nil = defaults
    phrasesChip = true,
    gameGlyphs = true,       -- the game's own button pictures where it has them
    debug = false,
}
CK.DEFAULTS = DEFAULTS

local function copyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            copyDefaults(v, dst[k])
        elseif dst[k] == nil or type(dst[k]) ~= type(v) then
            dst[k] = v
        end
    end
end

-- A number out of its range goes back to its default (the file can be
-- edited by hand)
local RANGES = {
    scale = { 0.4, 2 }, maxWords = { 100, 100000 }, numSuggestions = { 1, 5 },
}

function CK:InitDB()
    if type(FreeControlChatDB) ~= "table" then FreeControlChatDB = {} end
    local db = FreeControlChatDB
    if type(db.settings) ~= "table" then db.settings = {} end
    copyDefaults(DEFAULTS, db.settings)
    for key, range in pairs(RANGES) do
        local value = db.settings[key]
        if value < range[1] or value > range[2] then db.settings[key] = DEFAULTS[key] end
    end
    if db.pos ~= nil and type(db.pos) ~= "table" then db.pos = nil end
    self.db = db
    self:ApplyLanguage()
    for _, key in ipairs({ "words", "commands", "trigrams", "starts", "bigrams" }) do
        if type(db[key]) ~= "table" then db[key] = {} end
    end
end

function CK:Print(msg, ...)
    if select("#", ...) > 0 then msg = format(msg, ...) end
    ns.Print(tostring(msg))
end

-- The chat features are FreeControl's: off with it, and while the game's
-- Gamepad UI is on (FreeControl stands down then, see ns.IsActive)
function CK:Enabled()
    return self.db ~= nil and ns.db ~= nil and ns.IsActive()
end

---------------------------------------------------------------------------
-- Frames and fonts
---------------------------------------------------------------------------
-- (Easy Controller makes its frames without a parent and sets it after: the
-- Gamepad UI watches CreateFrame. Kept as it is, it costs nothing here.)
function CK.NewFrame(frameType, name, parent, template)
    local f = CreateFrame(frameType, name, nil, template)
    if parent then f:SetParent(parent) end
    return f
end

-- Friz Quadrata; the game in a language written with other letters (Korean,
-- Chinese, Russian): its own font, the Latin-only file has none of them
local NON_LATIN = { koKR = true, zhCN = true, zhTW = true, ruRU = true }

function CK:GetFontPath()
    local standard = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    if NON_LATIN[GetLocale and GetLocale() or ""] then return standard end
    return "Fonts\\FRIZQT__.TTF"
end

---------------------------------------------------------------------------
-- UTF-8 helpers (French accents)
---------------------------------------------------------------------------
local UTF8_2 = "[\195\197][\128-\191]"

-- The first n characters of a UTF-8 text (never half a letter)
function CK.Utf8Sub(text, n)
    local count, i = 0, 1
    while i <= #text do
        local b = text:byte(i)
        count = count + 1
        if count > n then return text:sub(1, i - 1) end
        i = i + (b >= 240 and 4 or b >= 224 and 3 or b >= 192 and 2 or 1)
    end
    return text
end

local LOWER = {
    ["À"] = "à", ["Â"] = "â", ["Ä"] = "ä", ["Á"] = "á", ["Ç"] = "ç", ["É"] = "é", ["È"] = "è",
    ["Ê"] = "ê", ["Ë"] = "ë", ["Î"] = "î", ["Ï"] = "ï", ["Í"] = "í", ["Ô"] = "ô", ["Ö"] = "ö",
    ["Ó"] = "ó", ["Ò"] = "ò", ["Ì"] = "ì", ["Ù"] = "ù", ["Û"] = "û", ["Ü"] = "ü", ["Ú"] = "ú", ["Ÿ"] = "ÿ", ["Ñ"] = "ñ",
    ["Œ"] = "œ", ["Æ"] = "æ",
}
local UPPER = {}
for up, low in pairs(LOWER) do UPPER[low] = up end

local STRIP = {
    ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["á"] = "a", ["ç"] = "c", ["é"] = "e", ["è"] = "e",
    ["ê"] = "e", ["ë"] = "e", ["î"] = "i", ["ï"] = "i", ["í"] = "i", ["ô"] = "o", ["ö"] = "o",
    ["ó"] = "o", ["ò"] = "o", ["ì"] = "i", ["ß"] = "ss", ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["ú"] = "u", ["ÿ"] = "y", ["ñ"] = "n",
    ["œ"] = "oe", ["æ"] = "ae",
}

-- string.lower/upper may touch UTF-8 bytes depending on the C locale: only map A-Z
local ASCII_LOWER, ASCII_UPPER = {}, {}
for b = 65, 90 do
    ASCII_LOWER[string.char(b)] = string.char(b + 32)
    ASCII_UPPER[string.char(b + 32)] = string.char(b)
end

function CK.Lower(s)
    return (s:gsub("[A-Z]", ASCII_LOWER):gsub(UTF8_2, LOWER))
end

function CK.Upper(s)
    return (s:gsub("[a-z]", ASCII_UPPER):gsub(UTF8_2, UPPER))
end

-- Lowercase and strip accents: "Été" -> "ete"
function CK.Normalize(s)
    return (CK.Lower(s):gsub(UTF8_2, STRIP))
end

function CK.FirstChar(s)
    return s:match("^[\192-\255][\128-\191]*") or s:sub(1, 1)
end

function CK.IsUpperInitial(s)
    local c = CK.FirstChar(s)
    return c ~= "" and c ~= CK.Lower(c)
end

function CK.Capitalize(s)
    local c = CK.FirstChar(s)
    return CK.Upper(c) .. s:sub(#c + 1)
end

-- Remove the last UTF-8 character of a string
function CK.DropLastChar(s)
    local i = #s
    while i > 1 do
        local b = s:byte(i)
        if b < 128 or b >= 192 then break end
        i = i - 1
    end
    return s:sub(1, i - 1)
end

-- Letters (ASCII + any UTF-8 byte) form words
CK.WORD_CHARS = "[%a\128-\255]"

---------------------------------------------------------------------------
-- Links in the message (the chat can be opened by the game with one)
---------------------------------------------------------------------------
-- A link at the very end of the text (deleted as a whole by Backspace)
function CK.TrailingLink(text)
    return text:match("(|c%x%x%x%x%x%x%x%x|H[^|]+|h[^|]*|h|r)$") or text:match("(|H[^|]+|h[^|]*|h)$")
end

-- Readable text for the preview: links shown as [Title] in gold
function CK.DisplayText(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x|H[^|]+|h([^|]*)|h|r", "|cffffd100%1|r")
        :gsub("|H[^|]+|h([^|]*)|h", "|cffffd100%1|r"))
end

---------------------------------------------------------------------------
-- Languages: dictionaries, and the accents of the 123 layer
---------------------------------------------------------------------------
CK.LANGUAGES = {
    { key = "fr", name = "Français", dicts = { "frFR" }, accents = "fr" },
    { key = "en", name = "English", dicts = { "enUS" }, accents = "en" },
    { key = "de", name = "Deutsch", dicts = { "deDE" }, accents = "de" },
    { key = "es", name = "Español", dicts = { "esES" }, accents = "es" },
    { key = "it", name = "Italiano", dicts = { "itIT" }, accents = "it" },
    { key = "fren", name = "Français + English", dicts = { "frFR", "enUS" }, accents = "fr" },
}

-- 12 characters per language: the accents first, then useful punctuation
CK.ACCENTS = {
    fr = { "é", "è", "ê", "à", "â", "ç", "ù", "û", "î", "ô", "ë", "ï" },
    en = { "é", "è", "à", "ç", "'", "?", "!", "-", "&", "$", "ë", "ï" },
    de = { "ä", "ö", "ü", "ß", "?", "!", "'", "-", "€", "&", "§", "_" },
    es = { "á", "é", "í", "ó", "ú", "ñ", "ü", "¿", "¡", "'", "-", "ç" },
    it = { "à", "è", "é", "ì", "ò", "ù", "ó", "í", "ú", "'", "?", "!" },
}

function CK:GetLanguage()
    local key = self.db and self.db.settings.lang
    for _, lang in ipairs(CK.LANGUAGES) do
        if lang.key == key then return lang end
    end
    return CK.LANGUAGES[2]
end

function CK:Accents()
    return CK.ACCENTS[self:GetLanguage().accents] or CK.ACCENTS.fr
end

-- The dictionaries in use come from the language
function CK:ApplyLanguage()
    local dicts = {}
    for _, key in ipairs(self:GetLanguage().dicts) do dicts[key] = true end
    self.db.settings.dicts = dicts
end

function CK:SetLanguage(key)
    self.db.settings.lang = key
    self:ApplyLanguage()
    CK.Predict:Load()
    if self.frame then self:UpdateMethod() end
end
