--!strict
-- ReplicatedStorage.Shared.Paintball.Body
-- The player body of the paintball contract (checklist PB-3, PB-9): heights, the hit shape, the eye,
-- speeds, the crouch and the look angles, as one set of pure functions the client, the server and the
-- bots all use. FROZEN: no lane edits this file.
--
-- A POSE is a feet point (x, y, z in the arena frame: y is the walking surface under the body), a yaw
-- and pitch, and a crouch fraction c in 0..1 (0 standing, 1 fully crouched).
--
-- THE HIT SHAPE is a vertical capsule above the feet: axis from LOW to top(c) - RADIUS, radius RADIUS
-- (the S18 capsule of Config.body standing; 0.6 of its height crouched, Tunables crouchHeightMult).
-- Garb never changes it (PB-13). The server judges every ball against this shape and nothing else.
--
-- THE EYE is eye(c) above the feet: 4.5 standing, which is where the stock first-person camera of an
-- R15 body already sits (root 3.0 above the feet + 1.5), so nothing moves at the arena door; 2.7
-- crouched. A ball leaves from the eye point along the look direction (the marker is drawn lower and
-- to the right and its ball visibly joins that line), so what is under the crosshair is what is hit.
-- (Config.body.eye = 4.0 is the S18 harness's own number and stays for its spec only.)
--
-- CROUCH ON A HUMANOID BODY. Nothing about the Humanoid's collision changes: the arena has no gap
-- lower than Arena.HEADROOM. Crouching is (1) the crouch fraction eased by crouchStep, (2) on the
-- owning client the camera lowered to eye(c) with Humanoid.CameraOffset and WalkSpeed set to
-- speed(c, sprint), (3) on the server the same crouchStep run from the crouch bit of the move stream,
-- so the hit shape sinks at the same rate for everybody and cannot be flicked, (4) on every other
-- screen the puppet drawn at that fraction. The client eases its own eye with the same function, so
-- it agrees with the server's shape to within its latency.
--
-- SPEEDS (studs/s): WALK is the town's (Client/Controllers/Human.WALK, so the door changes nothing),
-- SPRINT is WALK x Tunables paintball.sprintMult, CROUCH is half of WALK. A sprinting body cannot fire
-- and the marker comes back up SPRINT_FIRE_DELAY after sprint ends; the server judges "sprinting" from
-- the speed it measures (isSprinting), not from the client's word.
-- Interface: constants; top(c), eye(c), capsule(c) -> (low, high, radius); eyePoint(x, y, z, c);
--   crouchStep(c, want, dt) -> c; speed(c, sprint) -> studs/s; isSprinting(speed) -> boolean;
--   look(yaw, pitch) -> (dx, dy, dz); yawPitch(dx, dy, dz) -> (yaw, pitch); partAt(localY, c) -> 1..3

local Config = require("./Config")

local Body = {}

Body.RADIUS = Config.body.radius -- 1.2
Body.LOW = Config.body.low -- 1.0: the capsule axis starts here above the feet
Body.CROUCH_MULT = 0.6
Body.STAND_TOP = Config.body.high + Config.body.radius -- 5.6: the top of the standing hit shape
Body.CROUCH_TOP = Body.STAND_TOP * Body.CROUCH_MULT -- 3.36
Body.STAND_EYE = 4.5
Body.CROUCH_EYE = Body.STAND_EYE * Body.CROUCH_MULT -- 2.7
Body.CROUCH_SECS = 0.2 -- standing to fully crouched, and back

Body.WALK = 17
Body.SPRINT = 17 * 1.4 -- 23.8
Body.CROUCH_SPEED = 8.5
Body.SPRINT_RAMP_SECS = 0.25 -- walk speed to sprint speed on the client (PB-9 "a short ramp up")
Body.SPRINT_FIRE_DELAY = 0.15 -- after sprint ends the marker is up and may fire
Body.JUMP_HEIGHT = 2 -- studs (Humanoid.JumpHeight in the arena): a hop, not a way over a rail

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

-- The hit capsule above the feet at crouch fraction c: (axis low, axis high, radius).
function Body.capsule(c: number): (number, number, number)
	return Body.LOW, Body.top(c) - Body.RADIUS, Body.RADIUS
end

function Body.eyePoint(x: number, y: number, z: number, c: number): (number, number, number)
	return x, y + Body.eye(c), z
end

-- One step of the crouch fraction towards crouched (want = true) or standing; linear, CROUCH_SECS
-- end to end. The server runs it once per snapshot tick, the client once per frame.
function Body.crouchStep(c: number, want: boolean, dt: number): number
	local step = dt / Body.CROUCH_SECS
	return if want then math.min(1, c + step) else math.max(0, c - step)
end

-- The fastest a body may move over the floor. Sprint needs a standing body.
function Body.speed(c: number, sprint: boolean): number
	if sprint and c <= 0 then
		return Body.SPRINT
	end
	return Body.WALK + (Body.CROUCH_SPEED - Body.WALK) * clamp01(c)
end

-- The server's reading of sprint from a measured horizontal speed.
function Body.isSprinting(speed: number): boolean
	return speed > Body.WALK * 1.1
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
