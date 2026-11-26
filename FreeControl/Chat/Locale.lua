local _, ns = ...
local CK = ns.Chat

-- The text of the keyboard and of the quick phrases: Easy Controller's
-- English (its Locales/enUS.lua), only what is used here. FreeControl is in
-- English only; a name that has no text shows as itself.
CK.L = setmetatable({
    SHIFT = "Shift",
    SYMBOLS = "123",
    LETTERS = "abc",
    SPACE = "Space",
    BACKSPACE = "Delete",
    SEND = "Send",
    SEND_COMBAT = "Press Y on the gamepad to send.",
    DRAG_HINT = "Drag to move the keyboard (/fc keyboard lock to lock)",
    COMBAT_UNAVAILABLE = "Not possible in combat",
    HELP_MOVE = "Move",
    HELP_TYPE = "Type",
    HELP_CHANNEL = "Channel",
    HELP_CLOSE = "Close",
    REPLY_TO = "Reply to %s: ",
    WHISPER_NAME = "Whisper to (name, then Y): ",
    CHANNEL_NAMES = { "Say", "Yell", "Party", "Raid", "Guild", "General (/1)", "Whisper", "Reply" },
    CHANNEL_UNAVAILABLE = "unavailable",
    BADGE_SHIFT = "SHIFT",
    BADGE_CAPS = "CAPS",
    TOAST_CLOSE_CHAT = "Close the chat first",
    V_OK = "OK",
    NO_DICT = "Dictionary not available: %s",
    KEYBOARD_OFF = "The chat keyboard is switched off. /fc keyboard on switches it on again.",

    PHRASES_NAME = "Quick phrases",
    PHRASES_TIP = "Quick phrases: ready-made phrases sent in one press",
    PH_ADD = "+ Add",
    PH_ADD_ROW = "+ Add a row",
    PH_COMMAND = "command",
    PH_V_SEND = "Send",
    PH_V_EDIT = "Edit",
    PH_V_TYPE = "Type a message",
    PH_V_CHANNEL = "Channel",
    PH_V_CLOSE = "Close",
    PH_V_ADD = "Add",
    PH_V_RENAME = "Rename",
    PH_V_ADD_ROW = "Add a row",
    PH_V_DELETE = "Delete",
    PH_V_CANCEL = "Cancel",
    PH_EDIT_TITLE = "Phrase",
    PH_ROW_TITLE = "Row name (empty: delete it)",
    PH_NEW_ROW_TITLE = "New row",
    PH_ASK_DELETE = "Delete the row \"%s\" and its %d phrase(s)?",
    -- The default phrases: { row name, { up to five phrases } }. One that
    -- starts with @ is an emote or command of the game's (Phrases.lua).
    PHRASE_ROWS = {
        { "Social", { "gg", "Nice one", "Thanks", "My bad, sorry", "lol" } },
        { "Status", { "Hi", "brb", "afk a sec", "Ready to go", "One more run?" } },
        { "Combat", { "Incoming", "Need heals", "Need mana", "CC that", "Don't pull yet" } },
        { "Moving", { "Let's go", "Follow me", "Wait here", "On my way", "Back off, let me pull" } },
        { "Emotes", { "@WAVE", "@THANK", "@CHEER", "@DANCE", "@ROLL" } },
        { "Your own", {  } },
    },
}, { __index = function(_, key) return key end })
