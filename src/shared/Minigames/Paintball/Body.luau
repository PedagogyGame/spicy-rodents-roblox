--!strict
-- ReplicatedStorage.Shared.Minigames.Paintball.Body
-- The player body of the paintball contract (checklist PB-3, PB-9): heights, the hit shape, the eye,
-- speeds, the crouch and the look angles, as one set of pure functions the client, the server and the
-- bots all use. FROZEN: no lane edits this file.
--
-- A POSE is a feet point (x, y, z in the arena frame: y is the walking surface under the body), a yaw
-- and pitch, and a crouch fraction c in 0..1 (0 standing, 1 fully crouched).
--
-- THE HIT SHAPE is a vertical capsule above the feet: axis from LOW to top(c) - RADIUS, radius RADIUS
-- (the S18 capsule of Config.body standing; 0.6 of its height crouched, Tunables crouchHeightMult).
-- Garb never changes it (PB-13). The server judges every ball against this shape and nothing else,
-- WITH NOTHING ADDED FOR THE BALL: a ball is its centre line, against a body as against a wall (Hit),
-- so a body whose shape is wholly behind a wall cannot be tagged over or through it. (The S18 core
-- added the ball's radius to a body and nothing to a wall; a crouched body's 3.36 then reached 3.61,
-- over the 3.4 rail it was hiding behind.)
-- THE HIT SHAPE IS A LITTLE WIDER THAN THE BODY, NOT TALLER (settled at the review, 2026-11-13): its radius
-- is HIT_RADIUS, 0.3 more than the body's RADIUS, and its axis is shortened by the same, so the top of the
-- shape is still top(c) and every "wholly behind the rail" comparison holds as before. A ball that passes
-- a hair beside an arm counts; one over a crouched crown does not. It forgives most where aiming is
-- hardest (a gamepad or a phone, with no aim assist), and nowhere does it reach over cover.
--
-- THE EYE is eye(c) above the feet: 4.5 standing, which is where the stock first-person camera of an
-- R15 body already sits (root 3.0 above the feet + 1.5), so nothing moves at the arena door; 2.7
-- crouched. A ball leaves from the eye point along the look direction (the marker is drawn lower and
-- to the right and its ball visibly joins that line), so what is under the crosshair is what is hit.
-- (Config.body.eye = 4.0 is the S18 harness's own number and stays for its spec only.)
--
-- CROUCH ON A HUMANOID BODY. Nothing about the Humanoid's collision changes: the arena has no gap
-- lower than Arena.HEADROOM. Crouching is (1) the crouch fraction eased by crouchStep, (2) on the
-- owning client the camera lowered to eye(c) with Humanoid.CameraOffset and the walking pace set
-- through the minigame framework's ctx.pace(pace(c, k, feel), false) (Client/Minigames/ClientGame: the
-- "MoveScale" and "NoSprint" attributes Controllers/Human reads every frame; nobody writes
-- Humanoid.WalkSpeed), (3) on the server the same crouchStep run for every PERSON from the crouch bit
-- of its newest accepted Move, once a snapshot tick (a bot eases its own fraction, in Bots.step, and
-- the service does not touch it), so the hit shape sinks at the same rate for everybody and cannot be
-- flicked, (4) on every other screen the puppet drawn at that fraction. The client eases its own eye
-- with the same function, so it agrees with the server's shape to within its latency.
--
-- SPEEDS (studs/s): WALK is the town's (Client/Controllers/Human.WALK, so the door changes nothing),
-- sprint is WALK x feel.sprintMult (slower than the town's sprint: the framework's Shift is switched
-- off and the client ramps its own scale, k from 0 to 1 over SPRINT_RAMP_SECS), CROUCH_SPEED is half
-- of WALK.
-- SPRINT AND THE MARKER (PB-9; Contract, "the sprint bit is the fact"). The client's ramp k rises while
-- sprint is wanted, the body is standing and no click is waiting, and DROPS TO 0 AT ONCE when sprint
-- is let go, on a fire press, on a crouch and on being tagged: there is no ramp down. Every Move
-- sampled while k > 0 carries BIT.sprint. The marker may fire SPRINT_FIRE_DELAY after the frame k
-- dropped to 0; a fire press while sprinting ends the sprint and is held until then (Contract.MARGIN
-- click), so a click is never dead. The server's side of it is one comparison of stamps (Contract,
-- "a click is a shot when"); it never measures a speed to decide who is sprinting.
-- Interface: constants (RADIUS, HIT_RADIUS ...); top(c), eye(c), capsule(c) -> (low, high, radius); eyePoint(x, y, z, c);
--   crouchStep(c, want, dt, feel?) -> c; speed(c, sprint, feel?) -> studs/s; pace(c, k, feel?) -> the
--   scale for ctx.pace; look(yaw, pitch) -> (dx, dy, dz); yawPitch(dx, dy, dz) -> (yaw, pitch);
--   partAt(localY, c) -> 1..3. `feel` is the match's Contract.Feel; nil means the defaults.

local Config = require("../../Paintball/Config")
local Contract = require("./Contract")

local Body = {}

Body.RADIUS = Config.body.radius -- 1.2: the body's own width (navigation, spacing, the puppet)
Body.HIT_RADIUS = Body.RADIUS + 0.3 -- 1.5: the hit shape's (see "the hit shape is a little wider")
Body.LOW = Config.body.low -- 1.0: the capsule axis starts here above the feet
Body.CROUCH_MULT = 0.6
Body.STAND_TOP = Config.body.high + Config.body.radius -- 5.6: the top of the standing hit shape
Body.CROUCH_TOP = Body.STAND_TOP * Body.CROUCH_MULT -- 3.36
Body.STAND_EYE = 4.5
Body.CROUCH_EYE = Body.STAND_EYE * Body.CROUCH_MULT -- 2.7
Body.CROUCH_SECS = Contract.FEEL.crouchSecs -- 0.2 at the default feel: standing to fully crouched, and back

Body.WALK = 17
Body.SPRINT = Body.WALK * Contract.FEEL.sprintMult -- 23.8 at the default feel
Body.CROUCH_SPEED = 8.5
Body.SPRINT_RAMP_SECS = 0.25 -- walk speed to sprint speed on the client (PB-9 "a short ramp up"); no ramp down
Body.SPRINT_FIRE_DELAY = 0.15 -- after sprint ends the marker is up and may fire
Body.JUMP_HEIGHT = 2 -- studs (the client sets Humanoid.JumpHeight to this while in a match): a hop, not a way over a rail

-- body parts a splat rides on, by height (the client's puppet has these three)
Body.PARTS = table.freeze({ "legs", "torso", "head" })

local function clamp01(v: number): number
	return if v < 0 then 0 elseif v > 1 then 1 else v
end

function Body.top(c: number): number
	return Body.STAND_TOP + (Body.CROUCH_TOP - Body.STAND_TOP) * clamp01(c)
end

function Body.eye(c: number): number
	return Body.STAND_EYE + (Body.CROUCH_EYE - Body.STAND_EYE) * clamp01(c)
end

-- The hit capsule above the feet at crouch fraction c: (axis low, axis high, radius). Its top is top(c).
function Body.capsule(c: number): (number, number, number)
	return Body.LOW, Body.top(c) - Body.HIT_RADIUS, Body.HIT_RADIUS
end

function Body.eyePoint(x: number, y: number, z: number, c: number): (number, number, number)
	return x, y + Body.eye(c), z
end

-- One step of the crouch fraction towards crouched (want = true) or standing; linear, feel.crouchSecs
-- end to end. The server runs it once per snapshot tick for a person, the client once per frame, a
-- bot's brain once per server tick.
function Body.crouchStep(c: number, want: boolean, dt: number, feel: Contract.Feel?): number
	local step = dt / (if feel then feel.crouchSecs else Body.CROUCH_SECS)
	return if want then math.min(1, c + step) else math.max(0, c - step)
end

-- The fastest a body may move over the floor. Sprint needs a standing body.
function Body.speed(c: number, sprint: boolean, feel: Contract.Feel?): number
	if sprint and c <= 0 then
		return Body.WALK * (if feel then feel.sprintMult else Contract.FEEL.sprintMult)
	end
	return Body.WALK + (Body.CROUCH_SPEED - Body.WALK) * clamp01(c)
end

-- What the owning client hands the framework's ctx.pace(scale, false): this body's speed over the
-- town's walk, at crouch fraction c and sprint ramp k (0 walking, 1 at full sprint; a crouching body
-- does not sprint). Between 0.5 and feel.sprintMult, inside Controllers/Human's 0..2.
function Body.pace(c: number, k: number, feel: Contract.Feel?): number
	local sprint = if c <= 0 then clamp01(k) else 0
	local speed = Body.speed(c, false, feel) + (Body.speed(0, true, feel) - Body.WALK) * sprint
	return speed / Body.WALK
end

-- The look direction of (yaw, pitch): a body's CFrame in its frame is CFrame.new(x, y, z) *
-- CFrame.Angles(0, yaw, 0), so yaw 0 looks along -z and a positive yaw turns left; a positive pitch
-- looks up.
function Body.look(yaw: number, pitch: number): (number, number, number)
	local cp = math.cos(pitch)
	return -math.sin(yaw) * cp, math.sin(pitch), -math.cos(yaw) * cp
end

function Body.yawPitch(dx: number, dy: number, dz: number): (number, number)
	local flat = math.sqrt(dx * dx + dz * dz)
	if flat < 1e-9 and math.abs(dy) < 1e-9 then
		return 0, 0
	end
	return math.atan2(-dx, -dz), math.atan2(dy, flat)
end

-- Which of PARTS a point at height localY above the feet is on.
function Body.partAt(localY: number, c: number): number
	local f = localY / Body.top(c)
	return if f < 0.45 then 1 elseif f < 0.8 then 2 else 3
end

return Body
