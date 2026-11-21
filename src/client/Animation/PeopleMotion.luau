--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Animation.PeopleMotion
-- How a person is drawn moving (owner D27, 2026-11-21: "waddles, jolts left right, rocks, does not walk or run in a
-- straight smooth line ... bring it into a smooth dynamic forward motion, torso led"). The numbers
-- Animation/AnimationDriver draws people with; how they look (the bodies, the clips) is untouched.
--   * The drawn place (follow): a computer-run person's root is anchored and placed by the server, and a client is
--     sent its place and facing a few times a second: drawn as sent, the body stood still for two or three frames
--     and then jumped a step, and the speed read off it rippled. The drawn body walks after the root instead: each
--     frame straight toward it, at the root's own pace (read between the poses of the last LEAD_WINDOW, so a pose a
--     little late or early hardly changes it), a little faster or slower to stay BEHIND of where the root must be by
--     now. A steady walk is drawn at a steady pace on the root's own line; the body never goes past where its root
--     is (so it never rocks back at a stop) and is about one pose behind it. The facing turns after the root's on a
--     critically damped follower. Only the drawing: the root (what the game reads) is where the server put it.
--   * The torso (steady, lean, twist): the stock walk and run swing the hips and the chest from side to side. The
--     roll and the yaw the clip gives the hips and the chest are cut to KEEP of themselves (a small counter-swing
--     stays), the hips' sideways shift likewise and the bob to BOB_KEEP; the chest leans forward a little, more the
--     faster the person goes; and into a turn the chest turns first, toward where the person is going, the feet
--     following. The legs and arms keep the clip's stride.
-- Interface: newFollow() -> Follow; follow(state, x, z, yaw, dt) -> dx, dz, dyaw (the drawn body's offset from the
--   root; state.speed, state.vx, state.vz the drawn velocity); steady(rx, ry, rz, px, py, weight) -> rx, ry, rz, px, py;
--   lean(speed) -> rad; twist(prev, facing, vx, vz, dt) -> rad; facing(lookX, lookZ) -> rad
-- Pure (no engine). Studs, seconds, radians; yaw as CFrame.Angles(0, yaw, 0) turns (+ to the left).

local PeopleMotion = {}

PeopleMotion.LEAD_WINDOW = 0.35 -- s: the root's pace is read between the poses that came in this long
PeopleMotion.LEAD_TAU = 0.12 -- s: the smoothing of that pace
PeopleMotion.LEAD_STALE = 2.5 -- of the usual time between poses with no new pose: the root has stopped
PeopleMotion.BEHIND = 0.04 -- s: the drawn body keeps the usual time between poses and this behind its root
PeopleMotion.CATCH = 3 -- 1/s: how fast the drawn body makes up (or gives back) what it is off that
PeopleMotion.EVERY = { 1 / 120, 0.3 } -- s: the time between poses is taken to be within these (0.05 until seen)
PeopleMotion.FOLLOW_YAW = 12 -- 1/s: the facing follower's stiffness
PeopleMotion.MAX_LAG = 4 -- studs: the drawn body never strays further than this from its root
PeopleMotion.SNAP = 6 -- studs: a root moved further than this in one frame was put there: no easing
PeopleMotion.RANGE = 300 -- studs from the camera: further bodies are drawn at their roots, their clips as they come

PeopleMotion.KEEP = 0.35 -- of the clip's roll and yaw of the hips and the chest, and of the hips' sideways shift
PeopleMotion.BOB_KEEP = 0.7 -- of the clip's rise and fall of the hips
PeopleMotion.LEAN_WALK = math.rad(2) -- the chest's forward lean at a stroll
PeopleMotion.LEAN_RUN = math.rad(7) -- ... and at LEAN_AT studs/s or faster
PeopleMotion.LEAN_AT = 28
PeopleMotion.TWIST_GAIN = 0.5 -- of the angle between where the person faces and where they go
PeopleMotion.TWIST_MAX = math.rad(25)
PeopleMotion.TWIST_RATE = 8 -- 1/s: how fast the chest's turn comes and goes
PeopleMotion.TWIST_ABOVE = 1 -- studs/s: slower than this nobody is going anywhere
PeopleMotion.TWIST_FADE = { 1.9, 2.6 } -- rad: walking backwards is not a turn (faded out between these)

local EVENTS = 16 -- the poses remembered

export type Follow = {
	live: boolean,
	x: number, -- the drawn place
	z: number,
	vx: number, -- the drawn velocity
	vz: number,
	speed: number, -- the drawn pace
	yaw: number, -- the drawn facing
	w: number,
	rx: number, -- the root as last seen
	rz: number,
	ux: number, -- the way the root last moved (unit)
	uz: number,
	lead: number, -- the root's pace (smoothed)
	clock: number,
	at: number, -- when the newest pose came in
	every: number, -- the usual time between poses
	et: { number }, -- the poses: when each came in, and how far the root had walked by then
	es: { number },
	head: number,
	count: number,
	walked: number,
}

local function delta(a: number, b: number): number
	return (b - a + math.pi) % (2 * math.pi) - math.pi
end

function PeopleMotion.newFollow(): Follow
	return {
		live = false,
		x = 0,
		z = 0,
		vx = 0,
		vz = 0,
		speed = 0,
		yaw = 0,
		w = 0,
		rx = 0,
		rz = 0,
		ux = 0,
		uz = 0,
		lead = 0,
		clock = 0,
		at = 0,
		every = 0.05,
		et = table.create(EVENTS, 0),
		es = table.create(EVENTS, 0),
		head = 1,
		count = 0,
		walked = 0,
	}
end

-- facing(lookX, lookZ): the yaw of a root whose LookVector is (lookX, _, lookZ)
function PeopleMotion.facing(lookX: number, lookZ: number): number
	return math.atan2(-lookX, -lookZ)
end

-- follow(state, x, z, yaw, dt): one frame of the drawn body after its root at (x, z) facing `yaw`; returns how far
-- the drawn body is from the root (dx, dz) and how far it is turned from it (dyaw).
function PeopleMotion.follow(st: Follow, x: number, z: number, yaw: number, dt: number): (number, number, number)
	if not st.live or dt <= 0 or math.abs(x - st.rx) > PeopleMotion.SNAP or math.abs(z - st.rz) > PeopleMotion.SNAP then
		st.live = true
		st.x, st.z, st.vx, st.vz, st.speed = x, z, 0, 0, 0
		st.yaw, st.w, st.lead = yaw, 0, 0
		st.rx, st.rz, st.at = x, z, st.clock
		st.head, st.count = 1, 1
		st.et[1], st.es[1] = st.clock, st.walked
		return 0, 0, 0
	end
	st.clock += dt
	if x ~= st.rx or z ~= st.rz then
		-- a new pose came in (a longer wait than EVERY allows was a person standing, not the time between poses)
		local waited = st.clock - st.at
		if waited <= PeopleMotion.EVERY[2] then
			st.every += (math.max(waited, PeopleMotion.EVERY[1]) - st.every) * 0.25
		end
		local sx, sz = x - st.rx, z - st.rz
		local len = math.sqrt(sx * sx + sz * sz)
		st.ux, st.uz = sx / len, sz / len
		st.walked += len
		st.rx, st.rz, st.at = x, z, st.clock
		st.head = st.head % EVENTS + 1
		st.count = math.min(st.count + 1, EVENTS)
		st.et[st.head], st.es[st.head] = st.clock, st.walked
	end
	-- the root's pace: between the poses of the last LEAD_WINDOW (two at least), nothing once they stop coming
	local newest = st.head
	local oldest, n = newest, 1
	while n < st.count do
		local i = (oldest - 2) % EVENTS + 1
		if n > 1 and st.clock - st.et[i] > PeopleMotion.LEAD_WINDOW then
			break
		end
		oldest = i
		n += 1
	end
	local age = st.clock - st.at
	local span = st.et[newest] - st.et[oldest]
	local pace = 0
	if n > 1 and span > 0 and span <= 2 * PeopleMotion.LEAD_WINDOW and age <= PeopleMotion.LEAD_STALE * st.every then
		pace = (st.es[newest] - st.es[oldest]) / span
	end
	st.lead += (pace - st.lead) * (1 - math.exp(-dt / PeopleMotion.LEAD_TAU))
	-- where the root must be by now (its newest pose, walked on at its pace), and the drawn body BEHIND of that:
	-- straight toward the root at its pace, made up or given back at CATCH; never past the root itself
	local reach = st.lead * math.min(age, PeopleMotion.LEAD_STALE * st.every)
	local px, pz = x + st.ux * reach - st.x, z + st.uz * reach - st.z
	local behind = st.lead * (st.every + PeopleMotion.BEHIND)
	local speed = math.max(0, st.lead + PeopleMotion.CATCH * (math.sqrt(px * px + pz * pz) - behind))
	local ox, oz = x - st.x, z - st.z
	local dist = math.sqrt(ox * ox + oz * oz)
	local step = math.min(speed * dt, dist)
	if dist > 1e-9 then
		st.x += ox / dist * step
		st.z += oz / dist * step
		st.vx, st.vz = ox / dist * step / dt, oz / dist * step / dt
	else
		st.vx, st.vz = 0, 0
	end
	st.speed = step / dt
	-- the facing: a critically damped follower (semi-implicit substeps: stable for any frame time)
	local wy = PeopleMotion.FOLLOW_YAW
	local total = math.min(dt, 0.1)
	local steps = math.clamp(math.ceil(total * 240), 1, 24)
	local h = total / steps
	for _ = 1, steps do
		st.w += (wy * wy * delta(st.yaw, yaw) - 2 * wy * st.w) * h
		st.yaw += st.w * h
	end
	local dx, dz = st.x - x, st.z - z
	local far = math.sqrt(dx * dx + dz * dz)
	if far > PeopleMotion.MAX_LAG then
		dx, dz = dx / far * PeopleMotion.MAX_LAG, dz / far * PeopleMotion.MAX_LAG
		st.x, st.z = x + dx, z + dz
	end
	return dx, dz, delta(yaw, st.yaw)
end

-- steady(rx, ry, rz, px, py, weight): what a walk or run clip gave the hips or the chest this frame (the joint's
-- rotation as pitch rx, yaw ry, roll rz; its sideways shift px and rise py), steadied: the roll, the yaw and the
-- shift cut to KEEP, the rise to BOB_KEEP; the pitch is the clip's. `weight` 0 leaves the clip as it is, 1 is the
-- whole of it.
function PeopleMotion.steady(
	rx: number,
	ry: number,
	rz: number,
	px: number,
	py: number,
	weight: number
): (number, number, number, number, number)
	local keep = 1 - (1 - PeopleMotion.KEEP) * weight
	local bob = 1 - (1 - PeopleMotion.BOB_KEEP) * weight
	return rx, ry * keep, rz * keep, px * keep, py * bob
end

-- lean(speed): how far the chest leans forward at `speed` studs/s: nothing standing, LEAN_WALK at a stroll, up to
-- LEAN_RUN at a sprint.
function PeopleMotion.lean(speed: number): number
	if speed <= 0 then
		return 0
	end
	local t = math.clamp(speed / PeopleMotion.LEAN_AT, 0, 1)
	return math.min(1, speed / 2) * (PeopleMotion.LEAN_WALK + (PeopleMotion.LEAN_RUN - PeopleMotion.LEAN_WALK) * t)
end

-- twist(prev, facing, vx, vz, dt): the chest's turn toward where the person is going (vx, vz: the velocity over the
-- ground), one frame on from `prev`: TWIST_GAIN of the angle between the facing and the way gone, at most
-- TWIST_MAX, eased at TWIST_RATE. Nothing for someone hardly moving, or going backwards.
function PeopleMotion.twist(prev: number, facing: number, vx: number, vz: number, dt: number): number
	local want = 0
	if vx * vx + vz * vz > PeopleMotion.TWIST_ABOVE * PeopleMotion.TWIST_ABOVE then
		local d = delta(facing, math.atan2(-vx, -vz))
		local fade = PeopleMotion.TWIST_FADE
		local share = math.clamp((fade[2] - math.abs(d)) / (fade[2] - fade[1]), 0, 1)
		want = math.clamp(PeopleMotion.TWIST_GAIN * d, -PeopleMotion.TWIST_MAX, PeopleMotion.TWIST_MAX) * share
	end
	return prev + (want - prev) * (1 - math.exp(-dt * PeopleMotion.TWIST_RATE))
end

return PeopleMotion
