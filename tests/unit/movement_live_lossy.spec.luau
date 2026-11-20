--!strict
-- Honest play on a lossy link (validator round 10): loss bursts of 0.3 to 1.0 s every 2 to 5 s (everything sent up in
-- one is lost: the packets and the root's updates), on top of 120 ms, 100 ms jitter and 2 % loss, through the client's
-- motor, the link and the server's MovementService with enforcement on (tests/lib/LiveRig). Every case must end with 0
-- snaps:
--   * running close round a house (2.5 st off its walls, walking and sprinting with the key held): a burst hides a corner
--     or two, so the first packet after it is a line through the house;
--   * sprinting with the key held in the open (the meter runs out, refills, runs out again): a burst hides the sprint's
--     end or start;
--   * the S3 driver in town (leaps, pounces, sprints, transfers on the rails).
-- The round-9 review measured, before round 10: 73 "wall" snaps over 64 runs x 40 s hugging a house with 0.65 to 0.8 s
-- bursts every 5 s, and 18 "stamina" snaps over 32 sprint runs with 0.5 s bursts every 5 s.
-- SPICY_LOSSY_RUNS=<n> plays n runs of each kind (default 4; the sweep the fix was measured with: 32);
-- SPICY_LOSSY_BURSTS="lo,hi,every0,every1" sets the bursts (seconds; default "0.3,1.0,2,5").
local process = require("@lune/process")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local BakedWorld = require("@tests/lib/BakedWorld")
local Rng = require("@tests/cheat/Rng")
local LiveRig = require("@tests/lib/LiveRig")

type State = SquirrelMotor.State

local RUNS = tonumber(process.env.SPICY_LOSSY_RUNS) or 4
local B = { 0.3, 1.0, 2, 5 }
for i, v in string.split(process.env.SPICY_LOSSY_BURSTS or "", ",") do
	B[i] = tonumber(v) or B[i]
end
local SECONDS = 40

-- bursts(rng, seconds, lo, hi, every0, every1): a loss schedule: a burst lo..hi s long every every0..every1 s
local function bursts(
	rng: Rng.Rng,
	seconds: number,
	lo: number,
	hi: number,
	every0: number,
	every1: number
): (t: number) -> boolean
	local spans: { { number } } = {}
	local at = 1 + rng.next() * every1
	while at < seconds do
		local len = lo + rng.next() * (hi - lo)
		table.insert(spans, { at, at + len })
		at += math.max(len + 0.5, every0 + rng.next() * (every1 - every0))
	end
	return function(t: number): boolean
		for _, s in spans do
			if t >= s[1] and t < s[2] then
				return true
			end
			if t < s[1] then
				return false
			end
		end
		return false
	end
end

return function(t)
	local town = LiveRig.town()
	local world, vworld, boxes = town.world, town.vworld, town.boxes

	local function lossy(rng: Rng.Rng, lo: number, hi: number, every0: number, every1: number): LiveRig.Link
		return {
			latency = 0.12,
			jitter = 0.1,
			loss = 0.02,
			dropAt = bursts(rng, SECONDS + 5, lo, hi, every0, every1),
		}
	end

	local totals: { [string]: { runs: number, snaps: number, reasons: { [string]: number } } } = {}
	local function tally(kind: string, r: LiveRig.Result)
		local k = totals[kind] or { runs = 0, snaps = 0, reasons = {} }
		totals[kind] = k
		k.runs += 1
		k.snaps += r.snaps
		for why, n in r.reasons do
			k.reasons[why] = (k.reasons[why] or 0) + n
		end
	end
	local function report(kind: string)
		local k = totals[kind]
		local reasons = {}
		for why, n in k.reasons do
			table.insert(reasons, `{why}={n}`)
		end
		table.sort(reasons)
		print(`      {kind}: {k.snaps} snaps over {k.runs} runs x {SECONDS} s ({table.concat(reasons, " ")})`)
	end

	-- the houses a ring 2.5 st off the walls goes round with no other house within 3 st of it
	local OFF = 2.5
	local rings: { { { x: number, z: number } } } = {}
	for i, b in boxes do
		local clear = true
		for j, o in boxes do
			if
				i ~= j
				and o.minX < b.maxX + OFF + 3
				and o.maxX > b.minX - OFF - 3
				and o.minZ < b.maxZ + OFF + 3
				and o.maxZ > b.minZ - OFF - 3
			then
				clear = false
			end
		end
		if clear then
			table.insert(rings, {
				{ x = b.minX - OFF, z = b.minZ - OFF },
				{ x = b.maxX + OFF, z = b.minZ - OFF },
				{ x = b.maxX + OFF, z = b.maxZ + OFF },
				{ x = b.minX - OFF, z = b.maxZ + OFF },
			})
		end
	end
	-- round the ring, corner to corner (the camera turned to the next corner a stud before it), either way round
	local function hug(ring: { { x: number, z: number } }, sprint: boolean, backwards: boolean): LiveRig.Keys
		local k = 1
		return function(_now: number, s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
			local w = ring[k]
			if math.sqrt((w.x - s.x) ^ 2 + (w.z - s.z) ^ 2) < 1 then
				k = if backwards then (k - 2) % 4 + 1 else k % 4 + 1
				w = ring[k]
			end
			return BakedWorld.keys(BakedWorld.cameraYawToward(w.x - s.x, w.z - s.z), { fw = 1, sprint = sprint })
		end
	end

	t.test(
		`honest: running close round a house, lost bursts of {B[1]} to {B[2]} s every {B[3]} to {B[4]} s ({RUNS} runs walking, {RUNS} sprinting): 0 snaps`,
		function()
			t.truthy(#rings >= 3, `houses with a clear ring ({#rings})`)
			for run = 1, 2 * RUNS do
				local sprint = run > RUNS
				local rng = Rng.new(1000 + run)
				local ring = rings[(run - 1) % #rings + 1]
				local start = ring[1]
				local rig = LiveRig.new({
					world = world,
					vworld = vworld,
					link = lossy(rng, B[1], B[2], B[3], B[4]),
					seed = 1000 + run,
				})
				rig:possess(SquirrelMotor.new(start.x, world.groundHeight, start.z), hug(ring, sprint, run % 2 == 0))
				rig:run(SECONDS)
				local r = rig:result()
				tally("round a house", r)
				if r.snaps > 0 then
					print(`      run {run}: {LiveRig.describe(if sprint then "sprinting" else "walking", r)}`)
					for i, v in r.violations do
						if i <= 6 then
							print(`        {v}`)
						end
					end
				end
			end
			report("round a house")
			t.eq(totals["round a house"].snaps, 0, "snaps")
		end
	)

	t.test(
		`honest: sprinting with the key held, the meter running out and back, lost bursts of {B[1]} to {B[2]} s every {B[3]} to {B[4]} s ({RUNS} runs): 0 snaps`,
		function()
			for run = 1, RUNS do
				local rng = Rng.new(2000 + run)
				local rig = LiveRig.new({
					world = town.noWalls,
					vworld = vworld,
					link = lossy(rng, B[1], B[2], B[3], B[4]),
					seed = 2000 + run,
				})
				local leapEvery = 1.3 + run * 0.4
				rig:possess(
					town.openStart(),
					function(now: number, _s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
						local inp =
							SquirrelMotor.idleInput(if math.floor(now / 3) % 2 == 0 then -math.pi / 2 else math.pi / 2)
						inp.fw = 1
						inp.sprint = true
						inp.leap = run % 2 == 0 and (now % leapEvery) < 0.05
						return inp
					end
				)
				rig:run(SECONDS)
				local r = rig:result()
				tally("sprinting", r)
				if r.snaps > 0 then
					print(`      run {run}: {LiveRig.describe("sprinting", r)}`)
					for i, v in r.violations do
						if i <= 6 then
							print(`        {v}`)
						end
					end
				end
			end
			report("sprinting")
			t.eq(totals["sprinting"].snaps, 0, "snaps")
		end
	)

	t.test(
		`honest: the S3 driver in town (rails, leaps, pounces), lost bursts of {B[1]} to {B[2]} s every {B[3]} to {B[4]} s ({RUNS} runs): 0 snaps`,
		function()
			for run = 1, RUNS do
				local rng = Rng.new(3000 + run)
				local rig = LiveRig.new({
					world = world,
					vworld = vworld,
					link = lossy(rng, B[1], B[2], B[3], B[4]),
					seed = 3000 + run,
				})
				rig:possess(town.startAt(rng), town.driven(rng))
				rig:run(SECONDS)
				local r = rig:result()
				tally("rails", r)
				if r.snaps > 0 then
					print(`      run {run}: {LiveRig.describe("rails", r)}`)
					for i, v in r.violations do
						if i <= 6 then
							print(`        {v}`)
						end
					end
				end
			end
			report("rails")
			t.eq(totals["rails"].snaps, 0, "snaps")
		end
	)
end
