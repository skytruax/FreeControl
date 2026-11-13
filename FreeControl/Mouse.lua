local _, ns = ...
local Layout = ns.Layout

-- Mouse mode: the game's own stick-driven mouse cursor, with a way to click.
--
-- The client can hand the mouse pointer to the right stick ("cursor control"). While it does, it
-- treats a mouse button as two separate things:
--
--   * a click on the interface (windows, bags, menus) comes from the two buttons named by the
--     console variables GamePadCursorLeftClick and GamePadCursorRightClick, which the client
--     turns into real mouse clicks. They start as RT and RB, and RT is a FreeControl trigger;
--   * a click on the world (a mob, a corpse, a ground spell) goes through key bindings, to the
--     commands the real mouse buttons are bound to.
--
-- So for two buttons of the player's choice (the stick clicks unless changed) FreeControl sets
-- the variables (CVars.lua) and, while the cursor is out, binds the same buttons to those two
-- commands (the secure header in Bindings.lua, so that it works in a fight). The rest of the
-- time the buttons keep whatever the player bound them to.
--
-- The cursor comes out when the player presses the mouse button on the bar, and the game also
-- brings it out and puts it away by itself (a window opens; the character moves or jumps). The
-- game raises no event for that, so its state is looked at once a frame and the rest follows.
local Mouse = {}
ns.Mouse = Mouse

-- What the real left and right mouse buttons are bound to.
Mouse.COMMANDS = { "CAMERAORSELECTORMOVE", "TURNORACTION" }

local CVARS = { "GamePadCursorLeftClick", "GamePadCursorRightClick" }
local SETTINGS = { "clickLeft", "clickRight" }

local watcher = CreateFrame("Frame")
watcher:Hide()
local wasOut = false

function Mouse:IsAvailable()
	return SetGamePadCursorControl ~= nil and IsGamePadCursorControlEnabled ~= nil
end

function Mouse:IsOut()
	return self:IsAvailable() and IsGamePadCursorControlEnabled() and true or false
end

-- The button FreeControl makes the left (side 1) or right (side 2) mouse button, or nil when that
-- side is left to the game. A trigger is never a click button: a held trigger has to stay one.
function Mouse:GetManagedKey(side)
	local db = ns.db
	local key = db[SETTINGS[side]]
	if key == "game" or key == db.modKeys[1] or key == db.modKeys[2] then
		return nil
	end
	return key
end

-- Name of the button that clicks for a side right now, whoever chose it, or nil if none does.
function Mouse:GetClickName(side)
	local key = GetCVar(CVARS[side])
	if not key or key == "" or key:upper() == "NONE" then
		return nil
	end
	return Layout.GetKeyName(key:upper())
end

-- "Left stick click is the left click and Right stick click is the right click"
function Mouse:DescribeClicks()
	local left, right = self:GetClickName(1), self:GetClickName(2)
	if left and right then
		return ("%s is the left click and %s is the right click"):format(left, right)
	elseif left then
		return left .. " is the left click, and no button is the right click"
	elseif right then
		return right .. " is the right click, and no button is the left click"
	end
	return "no button is set to click"
end

-- The no-trigger button on the bar that brings the cursor out, as a name, or nil.
function Mouse:GetBarButtonName()
	for index = 1, 8 do
		local kind, command = Layout.ParseRole(ns.db.roles[index])
		if kind == "cmd" and command == Layout.CURSOR_COMMAND then
			return Layout.GetButtonName(Layout.SET_NONE, index)
		end
	end
	return nil
end

-- Brings the cursor out or puts it away. Everything else follows from the watcher below.
function Mouse:Toggle()
	if not self:IsAvailable() then
		ns.Print("This client has no controller mouse cursor.")
		return
	end
	SetGamePadCursorControl(not IsGamePadCursorControlEnabled())
end

-- Keeps the world-click bindings in step with the cursor. Bindings can only be changed from here
-- outside combat; in a fight the mouse button on the bar changes them itself (it is secure), and
-- whatever is left over is put right when the fight ends.
local function SyncBindings()
	ns.RunOutOfCombat("mouse", function()
		if not (ns.IsActive() and ns.IsBuilt()) then
			return
		end
		local header = ns.Bindings.header
		local out = Mouse:IsOut()
		if (header:GetAttribute("fc-mouse") ~= nil) ~= out then
			header:SetAttribute("fc-mouse", out and 1 or nil)
			header:Execute([[ self:RunAttribute("fc-apply") ]])
		end
	end)
end

local function OnCursorChanged(out)
	ns.Buttons:SetMouseLit(out)
	SyncBindings()
	if out and not ns.db.mouseHintShown then
		ns.db.mouseHintShown = true
		ns.Print(("Mouse cursor out. The right stick moves it; %s. Move, jump or press the mouse button again to put it away."):format(Mouse:DescribeClicks()))
	end
end

watcher:SetScript("OnUpdate", function()
	local out = Mouse:IsOut()
	if out ~= wasOut then
		wasOut = out
		ns.Try(OnCursorChanged, out)
	end
end)

-- Out of combat, after the buttons and bindings have been set up.
function Mouse:Apply()
	if not self:IsAvailable() then
		return
	end
	wasOut = self:IsOut()
	ns.Buttons:SetMouseLit(wasOut)
	watcher:Show()
end

-- When FreeControl is switched off: the cursor is the game's own business again.
function Mouse:Release()
	watcher:Hide()
	wasOut = false
	ns.Buttons:SetMouseLit(false)
end

-- Used by the key binding in Bindings.xml.
function ns.ToggleCursor()
	Mouse:Toggle()
end
