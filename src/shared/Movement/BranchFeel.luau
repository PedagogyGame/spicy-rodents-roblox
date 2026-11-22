--!strict
-- ReplicatedStorage.Shared.Movement.BranchFeel
-- The little shift of running over a branch's nodules (owner D34: "the user experience feels like they are a squirrel,
-- a little shift from running over the nodules, but still smooth movement feel and play"). The knots are where
-- Shared/World/BranchNooks.nodules puts them on every branch's run path; as the motor's point passes one, the DRAWN body
-- (Controllers/Squirrel: the root's CFrame, and the camera that follows it) gets a quick settle: a lift of up to
-- C.amp studs and a roll of up to C.roll radians either way, gone in C.life seconds (a peak of a few studs a second up
-- and down), scaled with the pace (a stalk barely feels it, a sprint a little more). Nothing here feeds back into the
-- motor: its point, speed, jump and the server's validator never see a nodule (owner rule 2026-11-09: animation never
-- moves the authoritative position), so there is never a stop, a stumble or a lost jump.
-- Interface: new() -> Feel; step(feel, route?, railT?, dt) -> (lift studs, roll radians) (route: the motor's route this
--   frame, nil off the rails); bump(age, amp) -> studs, rollAt(age, amp) -> radians (one nodule's shape); C.
-- Pure. No side effects on require.

local BranchNooks = require("../World/BranchNooks")

local BranchFeel = {}

BranchFeel.C = table.freeze({
	amp = 0.12, -- studs at the reference pace
	roll = 0.05, -- radians at the reference pace
	rise = 0.06, -- seconds up over the knot
	life = 0.15, -- seconds until it has settled (a small dip after the rise)
	dip = 0.3, -- the settle's dip, of the rise
	refSpeed = 4.3, -- studs/s: the tree pace (Routes/Motion railWalk x treeTravelMult)
	minScale = 0.35, -- the scale at a crawl
	maxScale = 1.25, -- ... and at a sprint
	maxStep = 3, -- studs: a jump of the point further than this in a frame is a teleport or a new route: no bump
	maxBumps = 3, -- at once (overlapping knots add, never pile up)
})
local C = BranchFeel.C

export type Bump = { age: number, amp: number, side: number }
export type Feel = { route: number?, s: number?, bumps: { Bump } }

function BranchFeel.new(): Feel
	return { route = nil, s = nil, bumps = {} }
end

-- one nodule's lift `age` seconds after the point reached it: up over the knot (half a sine over C.rise), then a small
-- dip as it settles (over the rest of C.life), then nothing
function BranchFeel.bump(age: number, amp: number): number
	if age < 0 or age >= C.life then
		return 0
	end
	if age < C.rise then
		return amp * math.sin(math.pi * age / C.rise)
	end
	return -amp * C.dip * math.sin(math.pi * (age - C.rise) / (C.life - C.rise))
end

-- one nodule's roll: one sway and back, easing out over C.life
function BranchFeel.rollAt(age: number, amp: number): number
	if age < 0 or age >= C.life then
		return 0
	end
	local u = age / C.life
	return amp * math.sin(2 * math.pi * u) * (1 - u)
end

-- step(feel, route, railT, dt): this frame's lift and roll for a body whose motor is on `route` at `railT` (nil: off the
-- rails, or on anything without nodules: what is under way eases out)
function BranchFeel.step(feel: Feel, route: any?, railT: number?, dt: number): (number, number)
	if route ~= nil and railT ~= nil and route.kind == "branch" then
		local s = railT * route.length
		local prev = feel.s
		if feel.route == route.id and prev ~= nil and math.abs(s - prev) > 1e-6 and math.abs(s - prev) <= C.maxStep then
			local speed = math.abs(s - prev) / math.max(dt, 1e-3)
			local scale = math.clamp(speed / C.refSpeed, C.minScale, C.maxScale)
			for i, n in BranchNooks.nodules(route) do
				-- (passed this frame, either way along the branch; a knot the point stops on counts once)
				if (prev - n) * (s - n) < 0 or (s == n and prev ~= n) then
					if #feel.bumps >= C.maxBumps then
						table.remove(feel.bumps, 1)
					end
					table.insert(feel.bumps, { age = 0, amp = scale, side = if i % 2 == 0 then 1 else -1 })
				end
			end
		end
		feel.route, feel.s = route.id, s
	else
		feel.route, feel.s = nil, nil
	end
	local lift, roll = 0, 0
	local keep: { Bump } = {}
	for _, b in feel.bumps do
		b.age += dt
		if b.age < C.life then
			lift += BranchFeel.bump(b.age, C.amp * b.amp)
			roll += BranchFeel.rollAt(b.age, C.roll * b.amp) * b.side
			table.insert(keep, b)
		end
	end
	feel.bumps = keep
	return lift, roll
end

return BranchFeel
