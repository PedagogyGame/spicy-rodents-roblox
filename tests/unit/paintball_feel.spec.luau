--!strict
-- tests/unit/paintball_feel.spec.luau: does the marker shoot right at the default feel (brief v2 §13, the
-- owner's cut line; Contract.FEEL, "the ball")? The real Ballistics and Hit.body, a shooter's eye at a
-- standing height and a body walking across the view at Body.WALK, 20, 40 and 70 studs off (the
-- building's ranges): how often a ball tags it when aimed at it, aimed with the lead it needs, and
-- when the body strafes left and right (a direction change every 0.25 to 0.6 s, as a child on A and D
-- does). Found at the review: at the S18 core's 90 studs/s a ball aimed at a walker never tagged it
-- past a few studs, and a strafer at 70 studs was never tagged even with a perfect lead.
local Ballistics = require("@shared/Paintball/Ballistics")
local Body = require("@shared/Minigames/Paintball/Body")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Hit = require("@shared/Minigames/Paintball/Hit")

local function open(): (number?, number, number, number, number)
	return nil, 0, 0, 0, 0
end

local function lcg(seed: number): () -> number
	local st = seed
	return function(): number
		st = (st * 1103515245 + 12345) % 2147483648
		return st / 2147483648
	end
end

-- One ball. The body's feet start at (0, 0, -d), walking along x; `strafe` reverses it every 0.25 to
-- 0.6 s, the click falling at a random moment of a leg. `lead` is the share of the straight walker's
-- lead the shooter aims ahead (0: at the body).
local function trial(rand: () -> number, d: number, speed: number, drop: number, lead: number, strafe: boolean): boolean
	local vx = if rand() < 0.5 then Body.WALK else -Body.WALK
	local legs = {}
	for i = 1, 12 do
		legs[i] = 0.25 + 0.35 * rand()
	end
	local first = if strafe then 0.6 * rand() else math.huge
	local function xAt(tt: number): number
		local x, v, turn, k, now = 0, vx, first, 1, 0
		while now < tt do
			local step = math.min(tt - now, turn - now)
			x += v * step
			now += step
			if now >= turn then
				v = -v
				turn += legs[k] or 1
				k += 1
			end
		end
		return x
	end
	local aimX = vx * (d / speed) * lead
	local eye = Body.STAND_EYE
	local vxA, vyA, vzA = Ballistics.aim(0, eye, 0, aimX, 2.8, -d, speed, drop)
	local px, py, pz = 0, eye, 0
	local dt = 1 / 120
	for i = 1, 240 do
		local nx, ny, nz = Ballistics.position(0, eye, 0, vxA, vyA, vzA, drop, i * dt)
		if Hit.body(open, px, py, pz, nx, ny, nz, xAt(i * dt), 0, -d, 0) ~= nil then
			return true
		end
		if nz < -d - 3 then
			return false
		end
		px, py, pz = nx, ny, nz
	end
	return false
end

local function share(d: number, lead: number, strafe: boolean, feel: Contract.Feel?): number
	local f = feel or Contract.FEEL
	local rand = lcg(5)
	local hits, n = 0, 400
	for _ = 1, n do
		if trial(rand, d, f.ballSpeed, f.ballDrop, lead, strafe) then
			hits += 1
		end
	end
	return hits / n
end

return function(t)
	t.test(
		"the lead a walker needs is at most three and a half body widths at the building's ranges, not five and a half",
		function()
			local F = Contract.FEEL
			for _, d in { 20, 40, 70 } do
				local lead = Body.WALK * d / F.ballSpeed
				t.truthy(lead <= 3.5 * 2 * Body.RADIUS, `{d} studs: a lead of {lead}`)
			end
			-- (at the S18 core's 90 it was 13.2 studs at 70: five and a half body widths)
			t.truthy(Body.WALK * 70 / 90 > 5 * 2 * Body.RADIUS)
		end
	)

	t.test("a perfect lead tags a walker every time; a lead 30 % out still tags at 20 and 40 studs", function()
		for _, d in { 20, 40, 70 } do
			t.eq(share(d, 1, false), 1, `{d} studs, perfect lead`)
		end
		t.truthy(share(20, 0.7, false) >= 0.95, "20 studs, lead 30 % short")
		t.truthy(share(40, 0.7, false) >= 0.95, "40 studs, lead 30 % short")
		t.truthy(share(40, 1.3, false) >= 0.95, "40 studs, lead 30 % long")
	end)

	t.test("aimed straight at a walker, a ball tags it up close", function()
		t.truthy(share(10, 0, false) >= 0.95, "10 studs, aimed at the body")
		-- (and further off it needs a lead: that is the game, not a fault)
		t.truthy(share(40, 0, false) < 0.5)
	end)

	t.test("a body strafing left and right is not a dodge that always works", function()
		local s20, s40, s70 = share(20, 1, true), share(40, 1, true), share(70, 1, true)
		-- (measured: 81 %, 60 % and 27 %; at 200 studs/s, 46 % at 70)
		t.truthy(s20 >= 0.75, `20 studs: {s20}`)
		t.truthy(s40 >= 0.55, `40 studs: {s40}`)
		t.truthy(s70 >= 0.2, `70 studs: {s70}`)
		-- the S18 core's feel, with the old narrow shape's reach, for comparison: a strafer at 70 was never tagged
		local old = Contract.feel({ ballSpeed = 90, ballDrop = 9.8 })
		t.eq(share(70, 1, true, old), 0)
	end)
end
