--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Paintball.Controls
-- Paintball's controls, per device (the table is fixed in PaintballClient's header; this is the code
-- that turns each device's keys into Seat.input calls). The seat reads its own keys: of the framework's,
-- only Q and gamepad B are taken, by the game's `keys`.
--   keyboard and mouse   left button fire; R reload; Shift (either) sprints while HELD; C or Left Ctrl crouches
--                while HELD; G shows the scoreboard while HELD. (WASD, the mouse look and Space are
--                the stock controls'.) A click while the scoreboard is up belongs to its buttons.
--   gamepad      R2 fire; X reload; B crouch is a TOGGLE; L3 sprint is a TOGGLE that ends on a fire
--                press, on a crouch and when the stick is let go (Tuning.padSprintOff); View shows the
--                scoreboard while HELD, and while it is held Y leaves and D-pad up changes sides.
--   touch        the right FIRE does not sink its touch: its press is read here from the touch itself
--                (inside Hud.fireRect), and the same finger's drag still turns the view; a second FIRE
--                on the left, RELOAD, CROUCH (a TOGGLE) and SCORES (a TOGGLE) are buttons. Sprint
--                starts on a FULL push of the stick (Tuning.touchSprintOn) and lasts until the stick
--                is back under touchSprintOff, a fire press or a crouch; once ended that way it wants
--                the stick eased off before it starts again.
-- "crouch", "sprint" and "scores" reach the seat as STATES (each device's hold or toggle folded into
-- one), the rest as presses. Everything connected here is disconnected by stop().
-- Interface: new(seat, hud, port, tuning?) -> Controls { step(dt), stop() }

local InputMap = require("../../Input/InputMap")
local Hud = require("./Hud")
local SeatCore = require("./SeatCore")
local SelfPort = require("./Self")
local Tuning = require("./Tuning")

export type Controls = {
	step: (self: Controls, dt: number) -> (),
	stop: (self: Controls) -> (),
}

local Controls = {}

function Controls.new(seat: SeatCore.Seat, hud: Hud.Hud, port: SelfPort.Self, tuning: typeof(Tuning.T)?): Controls
	local tune = tuning or Tuning
	local UIS = game:GetService("UserInputService")
	local conns: { RBXScriptConnection } = {}
	local fireRight: GuiObject? = hud.touch.FireRight
	local touchOn = fireRight ~= nil

	local keyShift: { [string]: boolean } = {}
	local keyCrouch: { [string]: boolean } = {}
	local padCrouch, touchCrouch = false, false
	local padSprint, touchSprint = false, false
	local touchEased = true -- the stick has been under a full push since the last sprint ended
	local padStick = 0
	local keyScores, padScores, touchScores = false, false, false
	local sprintWas, crouchWas, scoresWas = false, false, false

	local function apply()
		local crouch = keyCrouch.C == true or keyCrouch.LeftControl == true or padCrouch or touchCrouch
		if crouch then
			padSprint, touchSprint = false, false
		end
		local sprint = keyShift.LeftShift == true or keyShift.RightShift == true or padSprint or touchSprint
		local scores = keyScores or padScores or touchScores
		if crouch ~= crouchWas then
			crouchWas = crouch
			seat:input("crouch", crouch)
		end
		if sprint ~= sprintWas then
			sprintWas = sprint
			seat:input("sprint", sprint)
		end
		if scores ~= scoresWas then
			scoresWas = scores
			seat:input("scores", scores)
		end
	end

	local function fire()
		-- a fire press ends a toggled sprint (a held Shift picks the sprint up again by itself)
		if padSprint or touchSprint then
			padSprint, touchSprint = false, false
			touchEased = false
			apply()
		end
		seat:input("fire", true)
	end

	table.insert(
		conns,
		UIS.InputBegan:Connect(function(io: InputObject, processed: boolean)
			if InputMap.ignore(io, processed) then
				return
			end
			local kind = io.UserInputType
			local key = io.KeyCode.Name
			if kind == Enum.UserInputType.MouseButton1 then
				if not seat.board then
					fire()
				end
			elseif kind == Enum.UserInputType.Touch then
				if touchOn then
					local x0, y0, x1, y1 = hud:fireRect()
					local p = io.Position
					if p.X >= x0 and p.X <= x1 and p.Y >= y0 and p.Y <= y1 then
						fire()
					end
				end
			elseif key == "LeftShift" or key == "RightShift" then
				keyShift[key] = true
				apply()
			elseif key == "C" or key == "LeftControl" then
				keyCrouch[key] = true
				apply()
			elseif key == "G" then
				keyScores = true
				apply()
			elseif key == "R" or key == "ButtonX" then
				seat:input("reload", true)
			elseif key == "ButtonR2" then
				fire()
			elseif key == "ButtonB" then
				padCrouch = not padCrouch
				apply()
			elseif key == "ButtonL3" then
				padSprint = not padSprint
				if padSprint then
					padCrouch = false
				end
				apply()
			elseif key == "ButtonSelect" then
				padScores = true
				apply()
			elseif key == "ButtonY" then
				if padScores then
					seat:input("leave", true)
				end
			elseif key == "DPadUp" then
				if padScores then
					seat:input("side", true)
				end
			end
		end)
	)
	table.insert(
		conns,
		UIS.InputEnded:Connect(function(io: InputObject)
			local key = io.KeyCode.Name
			if key == "LeftShift" or key == "RightShift" then
				keyShift[key] = nil
				apply()
			elseif key == "C" or key == "LeftControl" then
				keyCrouch[key] = nil
				apply()
			elseif key == "G" then
				keyScores = false
				apply()
			elseif key == "ButtonSelect" then
				padScores = false
				apply()
			end
		end)
	)
	table.insert(
		conns,
		UIS.InputChanged:Connect(function(io: InputObject)
			if io.KeyCode == Enum.KeyCode.Thumbstick1 then
				local p = io.Position
				padStick = math.sqrt(p.X * p.X + p.Y * p.Y)
			end
		end)
	)

	-- the touch buttons that are buttons
	local function button(name: string, fn: () -> ())
		local b = hud.touch[name] :: any
		if b then
			table.insert(conns, b.MouseButton1Down:Connect(fn))
		end
	end
	button("FireLeft", fire)
	button("Reload", function()
		seat:input("reload", true)
	end)
	button("Crouch", function()
		touchCrouch = not touchCrouch
		apply()
	end)
	button("Scores", function()
		touchScores = not touchScores
		apply()
	end)

	local controls = {} :: Controls

	function controls.step(_self: Controls, _dt: number)
		-- a toggled sprint lives only while the stick is pushed
		if padSprint and padStick < tune.padSprintOff then
			padSprint = false
		end
		if touchOn then
			local push = port.push()
			if push < tune.touchSprintOn then
				touchEased = true
			end
			if touchSprint and push < tune.touchSprintOff then
				touchSprint = false
			elseif not touchSprint and touchEased and push >= tune.touchSprintOn and not touchCrouch then
				touchSprint = true
				touchEased = false
			end
		end
		apply()
	end

	function controls.stop(_self: Controls)
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
	end

	return controls
end

return Controls
