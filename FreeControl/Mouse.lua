local _, ns = ...
local Layout = ns.Layout

-- Mouse mode: the game's own stick-driven mouse pointer, with a way to click.
--
-- The game keeps two things apart that a player thinks of as one:
--
--   * "cursor control": the right stick steers the mouse pointer instead of the camera;
--   * "free look": the controller is steering the camera, and the pointer is hidden. The game
--     goes into it by itself as soon as a stick is used.
--
-- Asking for cursor control while free look is still on leaves the pointer hidden. Version 1.2.0
-- did only that, so pressing the button while playing with the controller showed nothing. The
-- pointer is brought out here by ending free look first and asking for cursor control second,
-- and put away in the reverse order.
--
-- While the pointer is out the client treats a mouse button as two separate things:
--
--   * a click on the interface (windows, bags, menus) comes from the two buttons named by the
--     console variables GamePadCursorLeftClick and GamePadCursorRightClick, which the client
--     turns into real mouse clicks. They start as RT and RB, and RT is a FreeControl trigger;
--   * a click on the world (a mob, a corpse, a ground spell) goes through key bindings, to the
--     commands the real mouse buttons are bound to.
--
-- So for two buttons of the player's choice (the stick clicks unless changed) FreeControl sets
-- the variables (CVars.lua) and, while the pointer is out, binds the same buttons to those two
-- commands (the secure header in Bindings.lua, so that it works in a fight). The rest of the
-- time the buttons keep whatever the player bound them to.
--
-- The pointer comes out when the player presses the mouse button on the bar (Y unless changed;
-- FreeControl binds it, there is nothing to set up in the Key Bindings screen). The game also
-- brings it out and puts it away by itself (a window opens; the character jumps). It raises no
-- event for that, so its state is looked at once a frame and the rest follows.
local Mouse = {}
ns.Mouse = Mouse

-- What the real left and right mouse buttons are bound to.
Mouse.COMMANDS = { "CAMERAORSELECTORMOVE", "TURNORACTION" }

local CVARS = { "GamePadCursorLeftClick", "GamePadCursorRightClick" }
local SETTINGS = { "clickLeft", "clickRight" }

-- How long the game is given to do what it was asked before that is called a failure.
local FOLLOW_TIME = 0.4

local watcher = CreateFrame("Frame")
watcher:Hide()
local wasOut = false

-- What has happened since login, for /fc status: a report of "it does not work" is only useful
-- with what the game itself said at the time.
local history = {
	presses = 0,     -- times the mouse button on the bar was pressed
	asked = 0,       -- times the pointer was asked for
	came = 0,        -- times the game then said it was out
	retried = 0,     -- times it took a second request
	refused = 0,     -- times the game never said so
	last = nil,      -- what the last request came to, in words
}
local request        -- the request the game has not answered yet: { time =, tries = }
local refusalSaid = false

function Mouse:IsAvailable()
	return SetGamePadCursorControl ~= nil and IsGamePadCursorControlEnabled ~= nil
end

function Mouse:IsOut()
	return self:IsAvailable() and IsGamePadCursorControlEnabled() and true or false
end

-- What one of the game's yes-or-no functions answers, or nil when this client does not have it.
local function Ask(fn)
	if fn == nil then
		return nil
	end
	return fn() and true or false
end

local function AskForPointer()
	if SetGamePadFreeLook then
		SetGamePadFreeLook(false)
	end
	SetGamePadCursorControl(true)
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

-- The no-trigger button on the bar that brings the pointer out, as a name, or nil.
function Mouse:GetBarButtonName()
	for index = 1, 8 do
		if Layout.IsCursorRole(ns.db.roles[index]) then
			return Layout.GetButtonName(Layout.SET_NONE, index)
		end
	end
	return nil
end

-- Brings the pointer out. Returns false when this client has none.
function Mouse:BringOut()
	if not self:IsAvailable() then
		ns.Print("This client has no controller mouse pointer.")
		return false
	end
	history.asked = history.asked + 1
	request = { time = GetTime(), tries = 1 }
	AskForPointer()
	return true
end

-- Puts the pointer away. toCamera hands the right stick straight back to the camera, which is
-- right after a controller press and wrong for someone typing the command with a real mouse.
function Mouse:PutAway(toCamera)
	if not self:IsAvailable() then
		return false
	end
	request = nil
	SetGamePadCursorControl(false)
	if toCamera and SetGamePadFreeLook then
		SetGamePadFreeLook(true)
	end
	history.last = "put away"
	return true
end

function Mouse:Toggle(fromController)
	if self:IsOut() then
		return self:PutAway(fromController)
	end
	return self:BringOut()
end

-- The mouse button on the bar was pressed (Bindings.lua).
function Mouse:OnButtonPressed()
	history.presses = history.presses + 1
	self:Toggle(true)
end

-- Keeps the world-click bindings in step with the pointer. Bindings can only be changed from here
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
		ns.Print(("Mouse pointer out. The right stick moves it; %s. Press %s again to put it away; jumping puts it away too."):format(
			Mouse:DescribeClicks(), Mouse:GetBarButtonName() or "the mouse button"))
	end
end

-- Looks at whether the game did what the last request asked. A request that is not followed is
-- made once more, and after that it is said in chat (once) and kept for /fc status.
local function FollowRequest(out)
	if out then
		history.came = history.came + 1
		history.last = request.tries > 1 and "came out on the second request" or "came out"
		request = nil
	elseif GetTime() - request.time >= FOLLOW_TIME then
		if request.tries == 1 then
			request.tries, request.time = 2, GetTime()
			history.retried = history.retried + 1
			AskForPointer()
		else
			request = nil
			history.refused = history.refused + 1
			history.last = "the game did not bring it out"
			SyncBindings() -- the press bound the click buttons for a pointer that never came
			if not refusalSaid then
				refusalSaid = true
				ns.Print("The game did not bring the mouse pointer out. Type /fc status and send what it prints, so this can be fixed.")
			end
		end
	end
end

watcher:SetScript("OnUpdate", function()
	local out = Mouse:IsOut()
	if request then
		ns.Try(FollowRequest, out)
	end
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

-- When FreeControl is switched off: the pointer is the game's own business again.
function Mouse:Release()
	watcher:Hide()
	wasOut = false
	request = nil
	ns.Buttons:SetMouseLit(false)
end

local function YesNo(value)
	if value == nil then
		return "this client does not say"
	end
	return value and "yes" or "no"
end

-- For /fc status: what the game says about its pointer right now, and what happened to the
-- requests made since login.
function Mouse:Describe()
	local lines = {}
	if not self:IsAvailable() then
		lines[1] = "This client has no controller mouse pointer."
		return lines
	end
	lines[#lines + 1] = ("The game says: stick steers the pointer: %s. Controller steers the camera: %s. Using the controller: %s. Using the mouse: %s."):format(
		YesNo(self:IsOut()), YesNo(Ask(IsGamePadFreelookEnabled)), YesNo(Ask(IsUsingGamepad)), YesNo(Ask(IsUsingMouse)))
	lines[#lines + 1] = ("Since login: mouse button pressed %d times, pointer asked for %d times, came out %d, needed a second request %d, never came %d. Last: %s."):format(
		history.presses, history.asked, history.came, history.retried, history.refused, history.last or "nothing yet")
	local settings = {}
	for _, name in ipairs({ "GamePadCursorAutoEnable", "GamePadCursorAutoDisableSticks", "GamePadCursorAutoDisableJump", "GamePadCursorCentering", "GamePadCursorCenteredEmulation" }) do
		settings[#settings + 1] = ("%s = %s"):format(name, tostring(GetCVar(name)))
	end
	lines[#lines + 1] = "The game's own pointer settings: " .. table.concat(settings, ", ")
	return lines
end

-- For the tests.
function Mouse:GetHistory()
	return history
end
