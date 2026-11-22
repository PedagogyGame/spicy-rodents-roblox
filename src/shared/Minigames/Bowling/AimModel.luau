--!strict
-- ReplicatedStorage.Shared.Minigames.Bowling.AimModel
-- The bowler's aiming, as pure state the client feeds with input (Client/Minigames/BowlingClient) so it can be
-- tested. It aims the way a real bowler does (owner D32: "no way to put any angle or twist ... the aiming
-- wasn't very good"): where you STAND along the foul line (A / D), the TARGET you roll the ball over at the
-- lane's arrows (the mouse, Left / Right or the gamepad stick move it board by board), and the line through the
-- two is the throw's angle; the HOOK in four notches each way (Z / X, the mouse wheel, LB / RB); and the power
-- meter (hold Space, the mouse button, R2 or A: the needle runs up and back; let go to bowl; the green band is
-- the clean release, full power is wild). It also owns the words: one HELP card and one status line, so the
-- screen never says two different things about the keys. A throw the server refuses puts you straight back to
-- aiming (input is never swallowed).
-- Pure; Lune-tested (tests/unit/bowling_aim.spec.luau).
-- Interface: new() -> Aim; step(aim, input, dt); hook(aim, dir); charge(aim, down) -> Params? (on let-go);
--   power(aim) -> 0..1; params(aim) -> Params; angleOf(offset, target) -> radians; sent(aim); refused(aim);
--   nextBall(aim); canAim(aim) -> bool; preview(aim) -> { { x, d, hooked } }; standX(aim) -> x at the foul
--   line; targetPoint(aim) -> (x, d) on the arrows; board(x) -> 1..39 (from the right, as a right-hander
--   counts); targetText(aim); standText(aim); spinText(aim); statusText(aim, touch); warning(turnLeft) ->
--   text?; HELP; SWEET; SWEET_TEXT; MAX_TARGET; POWER_PERIOD; NOTCHES

local AlleyLayout = require("../../Attractions/AlleyLayout")
local BallPath = require("./BallPath")

local AimModel = {}

AimModel.POWER_PERIOD = 1.5 -- seconds for the needle to run from empty to full
AimModel.STEP_RATE = 0.9 -- offset units a second along the foul line
AimModel.BOARD = AlleyLayout.LANE_W / AlleyLayout.BOARDS -- one board, in studs
AimModel.MAX_TARGET = AlleyLayout.LANE_W / 2 - AimModel.BOARD / 2 -- the target stays on the outside boards
AimModel.TARGET_RATE = 1.0 -- studs a second on the keys (about ten boards: a tap moves it one or two)
AimModel.MOUSE_SENS = 0.004 -- studs of target per pixel of mouse travel (250 pixels is a stud: ten boards)
AimModel.STICK_RATE = 1.6 -- studs a second at full stick
AimModel.NOTCHES = 4 -- hook notches either side of straight
AimModel.PREVIEW_D = 42 -- the aim line runs over the arrows and on to where the back end starts to bite: how
-- far a hook then bends is the bowler's to learn
AimModel.PREVIEW_POWER = 0.7 -- the line is drawn for a clean release in the green until the meter runs
AimModel.WARN_AT = 15 -- seconds left on the turn clock when the warning starts
AimModel.SWEET = BallPath.RANGES.sweet
AimModel.SWEET_TEXT = "POWER - let go in the green: the ball goes exactly where you aimed. Full power is wild."
AimModel.HOOK_WORDS = { "a touch of", "some", "strong", "full" }

AimModel.HELP = {
	how = {
		"Ten frames each. All ten pins with your first ball is a STRIKE, with two balls a SPARE.",
		"Aim like a real bowler: pick where you STAND on the line, then the ARROW the ball rolls over. Your feet and the arrow make the angle.",
		"HOOK spins the ball: it skids on the oily front of the lane and curls on the dry end. A hook into the POCKET (just beside the front pin) strikes most.",
		"A straight ball works too, but only dead on the pocket. Dead centre leaves splits.",
	},
	keys = {
		"A / D  step left / right along the line",
		"Mouse or Left / Right arrows  move your target arrow",
		"Z / X or mouse wheel  hook left / right",
		"Hold Space or the mouse button  power meter",
		"Let go in the green band to bowl",
		"Gamepad: stick aims, D-pad steps, LB / RB hook, hold R2",
		"Q  leave the lane",
	},
}

export type Aim = {
	offset: number, -- where you stand: -1 .. 1 along the foul line
	target: number, -- the target across the lane at the arrows (studs from the lane's centre, bowler's right +)
	angle: number, -- the line through the two (kept up to date by step)
	notch: number, -- -NOTCHES .. NOTCHES (negative hooks left)
	charging: boolean,
	chargeT: number,
	phase: "aim" | "sent" | "watch",
}

export type Input = {
	left: boolean?, -- step along the line
	right: boolean?,
	aimL: boolean?, -- move the target on the keys
	aimR: boolean?,
	mouseDx: number?, -- pixels of mouse travel this frame (relative, so the keys' fine aim is kept)
	mouseX01: number?, -- or the cursor's place across the screen (0..1) as an absolute target
	stickAim: number?, -- gamepad -1..1
	stickStep: number?, -- gamepad -1..1
}

-- The angle of the line from where you stand through the target (both at their own d).
function AimModel.angleOf(offset: number, target: number): number
	local rx = BallPath.releaseX(offset)
	local run = AlleyLayout.arrowsD(target) - BallPath.RELEASE_D
	local lim = BallPath.RANGES.angle
	return math.clamp(math.atan((target - rx) / run), -lim, lim)
end

function AimModel.new(): Aim
	return { offset = 0, target = 0, angle = 0, notch = 0, charging = false, chargeT = 0, phase = "aim" }
end

function AimModel.canAim(aim: Aim): boolean
	return aim.phase == "aim"
end

-- One frame of aiming. Nothing moves once the ball is on its way.
function AimModel.step(aim: Aim, input: Input, dt: number)
	if aim.phase ~= "aim" then
		return
	end
	local step = (if input.right then 1 else 0) - (if input.left then 1 else 0) + (input.stickStep or 0)
	aim.offset = math.clamp(aim.offset + math.clamp(step, -1, 1) * AimModel.STEP_RATE * dt, -1, 1)
	local target = aim.target
	if input.mouseX01 ~= nil then
		target = (math.clamp(input.mouseX01, 0, 1) - 0.5) * 2 * AimModel.MAX_TARGET
	end
	if input.mouseDx ~= nil then
		target += input.mouseDx * AimModel.MOUSE_SENS
	end
	target += ((if input.aimR then 1 else 0) - (if input.aimL then 1 else 0)) * AimModel.TARGET_RATE * dt
	target += (input.stickAim or 0) * AimModel.STICK_RATE * dt
	aim.target = math.clamp(target, -AimModel.MAX_TARGET, AimModel.MAX_TARGET)
	aim.angle = AimModel.angleOf(aim.offset, aim.target)
	if aim.charging then
		aim.chargeT += dt
	end
end

-- One notch of hook left (dir < 0) or right.
function AimModel.hook(aim: Aim, dir: number)
	if aim.phase ~= "aim" then
		return
	end
	aim.notch = math.clamp(aim.notch + (if dir < 0 then -1 else 1), -AimModel.NOTCHES, AimModel.NOTCHES)
end

-- The power meter: up to full in POWER_PERIOD seconds, back down, and so on.
function AimModel.power(aim: Aim): number
	local p = (aim.chargeT / AimModel.POWER_PERIOD) % 2
	return if p <= 1 then p else 2 - p
end

function AimModel.params(aim: Aim): BallPath.Params
	return {
		offset = aim.offset,
		angle = AimModel.angleOf(aim.offset, aim.target),
		power = AimModel.power(aim),
		spin = aim.notch / AimModel.NOTCHES,
	}
end

-- The bowl button: down starts the meter, letting go throws. Returns the throw on the let-go (the caller
-- sends it); nil otherwise.
function AimModel.charge(aim: Aim, down: boolean): BallPath.Params?
	if down then
		if aim.phase == "aim" and not aim.charging then
			aim.charging = true
			aim.chargeT = 0
		end
		return nil
	end
	if not aim.charging then
		return nil
	end
	aim.charging = false
	if aim.phase ~= "aim" then
		return nil
	end
	local p = AimModel.params(aim)
	aim.phase = "sent"
	return p
end

-- The server took the throw: the ball is on its way.
function AimModel.sent(aim: Aim)
	aim.phase = "watch"
	aim.charging = false
end

-- The server refused the throw (or never answered): straight back to aiming, the same line kept.
function AimModel.refused(aim: Aim)
	if aim.phase == "sent" then
		aim.phase = "aim"
		aim.charging = false
		aim.chargeT = 0
	end
end

-- The lane is set again: aim the next ball (the line is kept so a good one can be repeated).
function AimModel.nextBall(aim: Aim)
	aim.phase = "aim"
	aim.charging = false
	aim.chargeT = 0
end

-- Where you stand: the ball's line at the foul line.
function AimModel.standX(aim: Aim): number
	return BallPath.releaseX(aim.offset)
end

function AimModel.targetPoint(aim: Aim): (number, number)
	return aim.target, AlleyLayout.arrowsD(aim.target)
end

-- The board under x, counted from the right edge (1) to the left (39), as a right-handed bowler counts them.
function AimModel.board(x: number): number
	local b = math.floor((AlleyLayout.LANE_W / 2 - x) / AimModel.BOARD) + 1
	return math.clamp(b, 1, AlleyLayout.BOARDS)
end

local ORDINAL = { "1st", "2nd", "3rd" }

-- The target in words: an arrow when it is on one ("the middle arrow", "2nd arrow from the right"), else the
-- board.
function AimModel.targetText(aim: Aim): string
	local b = AimModel.board(aim.target)
	if b % 5 == 0 and b >= 5 and b <= 35 then
		local k = b // 5 -- 1..7 from the right
		if k == 4 then
			return "the middle arrow"
		end
		local n = if k < 4 then k else 8 - k
		return `{ORDINAL[n]} arrow from the {if k < 4 then "right" else "left"}`
	end
	return `board {b}`
end

function AimModel.standText(aim: Aim): string
	return `board {AimModel.board(AimModel.standX(aim))}`
end

-- The dotted aim line: the real path of this throw at a clean release (or the meter's power while it runs),
-- as far as PREVIEW_D. hooked marks the dots where the back end has begun to bend a hook.
function AimModel.preview(aim: Aim): { { x: number, d: number, hooked: boolean } }
	local p = AimModel.params(aim)
	p.power = if aim.charging then p.power else AimModel.PREVIEW_POWER
	local path = BallPath.trace(p)
	local out = {}
	local d = 1.5
	local tEnd = path.tEnd
	local t = 0
	-- walk the path in time, dropping a dot each time the next mark down the lane is passed
	while t <= tEnd and d <= AimModel.PREVIEW_D do
		local x, _, bd = BallPath.at(path, t)
		if bd >= d then
			if path.gutterT and t >= path.gutterT then
				break
			end
			table.insert(out, { x = x, d = bd, hooked = aim.notch ~= 0 and bd > BallPath.HOOK_START })
			d += if d < 20 then 1.6 else 2.4
		end
		t += 1 / 120
	end
	return out
end

function AimModel.spinText(aim: Aim): string
	if aim.notch == 0 then
		return "straight"
	end
	local side = if aim.notch < 0 then "left" else "right"
	local n = math.abs(aim.notch)
	return `{AimModel.HOOK_WORDS[n] or "full"} hook {side}`
end

-- The one status line for the bowler whose turn it is.
function AimModel.statusText(aim: Aim, touch: boolean): string
	if aim.phase == "sent" then
		return "Bowling..."
	elseif aim.phase == "watch" then
		return "There it goes..."
	end
	if aim.charging then
		return "Let go in the green to bowl!"
	end
	local line = `stand {AimModel.standText(aim)}, aim at {AimModel.targetText(aim)}, {AimModel.spinText(aim)}`
	if touch then
		return `Your turn: {line}. Step and Aim buttons, Hook buttons curl it. Hold BOWL and let go`
	end
	return `Your turn: {line}. A/D step, mouse aims, Z/X hook. Hold Space, let go to bowl`
end

-- The turn clock's warning, once it is running low.
function AimModel.warning(turnLeft: number?): string?
	if turnLeft == nil or turnLeft > AimModel.WARN_AT then
		return nil
	end
	local n = math.max(0, math.ceil(turnLeft))
	return `Bowl within {n} second{if n == 1 then "" else "s"} or your turn is skipped`
end

return AimModel
