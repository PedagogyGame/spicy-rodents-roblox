--!strict
-- ReplicatedStorage.Shared.Minigames.Bowling.AimModel
-- The bowler's aiming, as pure state the client feeds with input (Client/Minigames/BowlingClient) so it can be
-- tested: where you stand along the foul line (A / D), the angle (mouse, or Left / Right, or the gamepad
-- stick), the hook in five notches (Z / X or the mouse wheel), and the power meter (hold Space or the mouse
-- button: the needle runs up and back; let go to bowl; the green band is the clean release, full power is
-- wild). It also owns the words: one HELP card and one status line, so the screen never says two different
-- things about the keys. A throw the server refuses puts you straight back to aiming (input is never
-- swallowed).
-- Pure; Lune-tested (tests/unit/bowling_aim.spec.luau).
-- Interface: new() -> Aim; step(aim, input, dt); hook(aim, dir); charge(aim, down) -> Params? (on let-go);
--   power(aim) -> 0..1; params(aim) -> Params; sent(aim); refused(aim); nextBall(aim); canAim(aim) -> bool;
--   preview(aim) -> { { x, d, hooked } }; spinText(aim); statusText(aim, touch); warning(turnLeft) -> text?;
--   HELP; SWEET; SWEET_TEXT; MAX_ANGLE; POWER_PERIOD

local BallPath = require("./BallPath")

local AimModel = {}

AimModel.MAX_ANGLE = BallPath.RANGES.angle
AimModel.POWER_PERIOD = 1.5 -- seconds for the needle to run from empty to full
AimModel.STEP_RATE = 0.9 -- offset units a second along the foul line
AimModel.AIM_RATE = 0.06 -- radians a second on the keys
AimModel.MOUSE_SENS = 0.0003 -- radians per pixel of mouse travel when the cursor is locked
AimModel.STICK_RATE = 0.09 -- radians a second at full stick
AimModel.NOTCHES = 2 -- hook notches either side of straight
AimModel.PREVIEW_D = 40 -- the aim line stops here: reading the rest of a hook is the bowler's skill
AimModel.WARN_AT = 15 -- seconds left on the turn clock when the warning starts
AimModel.SWEET = BallPath.RANGES.sweet
AimModel.SWEET_TEXT = "POWER - let go in the green: the ball goes exactly where you aimed. Full power is wild."

AimModel.HELP = {
	how = {
		"Ten frames each, up to four bowlers (add a computer if you like). All ten pins with your first ball is a STRIKE, with two balls a SPARE.",
		"Aim for the POCKET: just right (or just left) of the front pin. Dead centre leaves splits.",
		"The dotted line shows your throw two thirds of the way. Hook bends the ball late (orange dots): judging the rest is the skill.",
		"The scoreboard over the lane keeps score for everyone.",
	},
	keys = {
		"A / D  step left / right along the line",
		"Mouse or Left / Right arrows  aim",
		"Z / X or mouse wheel  hook left / right",
		"Hold Space or the mouse button  power meter",
		"Let go in the green band to bowl",
		"Q  leave the lane",
	},
}

export type Aim = {
	offset: number,
	angle: number,
	notch: number, -- -NOTCHES .. NOTCHES (negative hooks left)
	charging: boolean,
	chargeT: number,
	phase: "aim" | "sent" | "watch",
}

export type Input = {
	left: boolean?, -- step along the line
	right: boolean?,
	aimL: boolean?, -- turn the angle on the keys
	aimR: boolean?,
	mouseDx: number?, -- pixels of locked-cursor travel this frame
	mouseX01: number?, -- the free cursor's place across the screen (0..1), only when it moved
	stickAim: number?, -- gamepad -1..1
	stickStep: number?, -- gamepad -1..1
}

function AimModel.new(): Aim
	return { offset = 0, angle = 0, notch = 0, charging = false, chargeT = 0, phase = "aim" }
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
	local angle = aim.angle
	if input.mouseX01 ~= nil then
		angle = (math.clamp(input.mouseX01, 0, 1) - 0.5) * 2 * AimModel.MAX_ANGLE
	end
	if input.mouseDx ~= nil then
		angle += input.mouseDx * AimModel.MOUSE_SENS
	end
	angle += ((if input.aimR then 1 else 0) - (if input.aimL then 1 else 0)) * AimModel.AIM_RATE * dt
	angle += (input.stickAim or 0) * AimModel.STICK_RATE * dt
	aim.angle = math.clamp(angle, -AimModel.MAX_ANGLE, AimModel.MAX_ANGLE)
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
		angle = aim.angle,
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

-- The dotted aim line: the real path of this throw at a clean release, as far as PREVIEW_D. hooked marks the
-- dots where the hook has begun to bend it.
function AimModel.preview(aim: Aim): { { x: number, d: number, hooked: boolean } }
	local p = AimModel.params(aim)
	p.power = if aim.charging then p.power else 0.7
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
	return if math.abs(aim.notch) >= AimModel.NOTCHES then `full hook {side}` else `half hook {side}`
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
	if touch then
		return `Your turn ({AimModel.spinText(aim)}) - arrows step and aim, Hook buttons bend it, hold BOWL and let go`
	end
	return `Your turn ({AimModel.spinText(aim)}) - A/D step, mouse aims, Z/X hook, hold Space for power, let go to bowl`
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
