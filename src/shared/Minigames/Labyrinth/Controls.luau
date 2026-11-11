--!strict
-- ReplicatedStorage.Shared.Minigames.Labyrinth.Controls
-- The tilt labyrinth's controls. The owner fixed them and they must not change (brief v2 §13a, verbatim):
-- "W/S tilt forward and back; up and down arrows tilt right and left, up arrow is right."
-- The wooden toy has two knobs, one per hand: the LEFT hand's knob tips the board forward and back (W and S),
-- the RIGHT hand's knob tips it right and left (Up arrow = right, Down arrow = left). Nothing else tilts: A, D
-- and the Left and Right arrows do nothing at all while playing (LAB-C1). There is no remapping and no option.
-- Every device is boiled down to the same input the model takes each tick: a CODE 0..8 for two three-way
-- switches (right-left and forward-back), so a keyboard, a gamepad and a phone play the same game and the run's
-- log is the same kind of thing whoever made it (LAB-C5).
-- Pure; Lune-tested (tests/unit/labyrinth_rules.spec.luau).
-- Interface: KEYS (key name -> { axis, sign }), DEAD_KEYS, HELP, HELP_LINE, QUIT_KEY, HIDE_KEY, NEUTRAL;
--   code(right, forward) -> 0..8; axes(code) -> (right, forward); fromKeys({ [key name] = held }) -> code;
--   fromGamepad(pad) -> code; fromTouch(leftSlider, rightSlider) -> code; STICK_DEADZONE; knobs(tiltX, tiltY)
--   -> (left knob turn, right knob turn) in degrees, for the drawing (LAB-C4)

local Controls = {}

-- Enum.KeyCode names. "forward" is the left-hand knob, "right" the right-hand knob.
Controls.KEYS = table.freeze({
	W = table.freeze({ axis = "forward", sign = 1 }),
	S = table.freeze({ axis = "forward", sign = -1 }),
	Up = table.freeze({ axis = "right", sign = 1 }), -- the Up arrow tilts RIGHT
	Down = table.freeze({ axis = "right", sign = -1 }), -- the Down arrow tilts LEFT
}) :: { [string]: { axis: string, sign: number } }

-- Keys a player might expect to do something and which must do nothing here (they must not walk the body
-- either: the controller sinks them while a run is on).
Controls.DEAD_KEYS = table.freeze({ "A", "D", "Left", "Right" })

Controls.QUIT_KEY = "Q"
Controls.HIDE_KEY = "H"
-- the help card, word for word (LAB-C2)
Controls.HELP_LINE = "W tilt forward. S tilt back. Up arrow tilt right. Down arrow tilt left."
Controls.HELP = table.freeze({
	"W tilt forward.",
	"S tilt back.",
	"Up arrow tilt right.",
	"Down arrow tilt left.",
	"Q leaves. H hides this card.",
})

Controls.NEUTRAL = 4
Controls.STICK_DEADZONE = 0.35
Controls.KNOB_TURN = 20 -- degrees a knob turns for each degree the board tips

local function sign(v: number): number
	return if v > 0 then 1 elseif v < 0 then -1 else 0
end

-- right and forward are each -1, 0 or 1
function Controls.code(right: number, forward: number): number
	return (sign(right) + 1) * 3 + (sign(forward) + 1)
end

function Controls.axes(code: number): (number, number)
	return code // 3 - 1, code % 3 - 1
end

function Controls.valid(code: any): boolean
	return type(code) == "number" and code >= 0 and code <= 8 and code % 1 == 0
end

-- keys: { [KeyCode name] = true } for every key held down. Opposite keys cancel; other keys are ignored.
function Controls.fromKeys(keys: { [string]: boolean }): number
	local right, forward = 0, 0
	for name, binding in Controls.KEYS do
		if keys[name] then
			if binding.axis == "right" then
				right += binding.sign
			else
				forward += binding.sign
			end
		end
	end
	return Controls.code(right, forward)
end

export type Pad = {
	leftY: number?, -- left stick, + up
	rightY: number?, -- right stick, + up
	dpadUp: boolean?,
	dpadDown: boolean?,
	y: boolean?,
	a: boolean?,
}

local function stick(v: number?): number
	local n = v or 0
	return if n > Controls.STICK_DEADZONE then 1 elseif n < -Controls.STICK_DEADZONE then -1 else 0
end

-- Gamepad (LAB-C5): the two sticks are the two knobs. Left stick up/down is W/S; right stick up is RIGHT and
-- down is LEFT. The D-pad's up/down mirror the left stick and Y/A mirror the right (Y = right, A = left).
function Controls.fromGamepad(pad: Pad): number
	local forward = stick(pad.leftY) + (if pad.dpadUp then 1 else 0) - (if pad.dpadDown then 1 else 0)
	local right = stick(pad.rightY) + (if pad.y then 1 else 0) - (if pad.a then 1 else 0)
	return Controls.code(right, forward)
end

-- Touch (LAB-C5): two vertical sliders, each -1 (bottom) .. 1 (top), 0 when the thumb is off. The left thumb is
-- forward/back; the right thumb up = right, down = left.
function Controls.fromTouch(leftSlider: number, rightSlider: number): number
	return Controls.code(stick(rightSlider), stick(leftSlider))
end

-- How far each knob has turned for the board's tilt (LAB-C4): the left-hand knob follows forward/back, the
-- right-hand knob follows right/left.
function Controls.knobs(tiltX: number, tiltY: number): (number, number)
	return tiltY * Controls.KNOB_TURN, tiltX * Controls.KNOB_TURN
end

return Controls
