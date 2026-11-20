--!strict
-- Validator round 11 (the round-10 review, scratchpad review_validator_r10.md; its failing cases are validator_r10rv):
--   meter, pounces   a client that keeps its own meter full and pounces as often as the cooldown lets it: snapped (a
--                    pounce costs pounceCost; with the server's meter empty a pounce carries no faster than a walk);
--                    the same keys honest: 0 snaps
--   meter, walk-hop  honest: W and Space held, no sprint key, 60 s (every leap's landing carries faster than a walk on
--                    the ground for a moment, and the air refills nothing): 0 snaps
--   ray budget       the ways round a corner one actor's judgements may search are held to ValidatorWorld.C.AROUND_BUDGET
--                    wall rays a second once its pool (that much) is spent (MoveValidator.budgeted); without it the same
--                    calls cost several times that
-- About 5 s: `lune run tests/run.luau validator_r11`.
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local MoveValidator = require("@server/Movement/MoveValidator")
local LiveRig = require("@tests/lib/LiveRig")
local TestWorld = require("@tests/cheat/TestWorld")

type State = SquirrelMotor.State

return function(t)
	t.test(
		"meter, pounces: a client that keeps its own meter full and pounces whenever the cooldown lets it, 30 s on open ground: snapped; the same keys honest: 0 snaps",
		function()
			local town = LiveRig.town()
			local results = {}
			for _, cheat in { false, true } do
				local rig = LiveRig.new({
					world = town.noWalls,
					vworld = town.vworld,
					link = { latency = 0.06, jitter = 0.02, loss = 0 },
					seed = 11,
					cheat = if cheat
						then function(s: State)
							s.stamina = 1
							s.winded = false
						end
						else nil,
				})
				local s0 = town.openStart()
				rig:possess(s0, function(_now: number, s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
					local inp = SquirrelMotor.idleInput(-math.pi / 2)
					inp.fw = 1
					inp.pounce = s.cooldown <= 0 and s.grounded
					return inp
				end)
				rig:run(30)
				local r = rig:result()
				local pace = math.sqrt((r.root.x - s0.x) ^ 2 + (r.root.z - s0.z) ^ 2) / 30
				print(
					`      {if cheat then "meter kept full" else "honest"}: {string.format("%.1f", pace)} st/s; {LiveRig.describe(
						"",
						r
					)}`
				)
				results[cheat] = r.snaps
			end
			t.eq(results[false], 0, "the honest pouncer is not snapped")
			t.truthy(results[true] > 0, "a pouncer whose meter never empties is snapped")
		end
	)

	t.test(
		"meter, walk-hop: honest, W and Space held with no sprint key, 60 s on open ground and on a lossy link: 0 snaps",
		function()
			local town = LiveRig.town()
			local snaps = 0
			for _, link in
				{
					{ latency = 0.06, jitter = 0.02, loss = 0 },
					{ latency = 0.12, jitter = 0.1, loss = 0.02, dropEvery = 3, dropFor = 0.6 },
				} :: { LiveRig.Link }
			do
				local rig = LiveRig.new({ world = town.noWalls, vworld = town.vworld, link = link, seed = 12 })
				rig:possess(
					town.openStart(),
					function(_now: number, s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
						local inp = SquirrelMotor.idleInput(-math.pi / 2)
						inp.fw = 1
						inp.leap = s.grounded
						return inp
					end
				)
				rig:run(60)
				local r = rig:result()
				print(`      {LiveRig.describe("walk-hop", r)}`)
				snaps += r.snaps
			end
			t.eq(snaps, 0, "an honest walking hopper is not snapped")
		end
	)

	t.test(
		"ray budget: ways round asked for a line into a closed room 60 times a second for 4 s: the pool, then at most AROUND_BUDGET wall rays a second (and one search over), against several times that unbudgeted",
		function()
			-- (a closed room, walls 1 st thick, -6..6 on both axes, 30 st high, open-topped; the rays are counted)
			local boxes = {
				{ -6, -6, 6, -5 },
				{ -6, 5, 6, 6 },
				{ -6, -6, -5, 6 },
				{ 5, -6, 6, 6 },
			}
			local count = 0
			local function wall(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number): boolean
				count += 1
				for _, b in boxes do
					-- (the segment against the box across, its height 0..30)
					local t0, t1 = 0, 1
					local ok = true
					for _, ax in { { ox, dx, b[1], b[3] }, { oz, dz, b[2], b[4] }, { oy, dy, 0, 30 } } do
						local o, d, lo, hi = ax[1], ax[2], ax[3], ax[4]
						if math.abs(d) < 1e-12 then
							if o < lo or o > hi then
								ok = false
							end
						else
							local a, c = (lo - o) / d, (hi - o) / d
							t0, t1 = math.max(t0, math.min(a, c)), math.min(t1, math.max(a, c))
						end
					end
					if ok and t0 <= t1 then
						return true
					end
				end
				return false
			end
			local function down(): boolean
				return false
			end
			local C = ValidatorWorld.C
			local function run(budgeted: boolean): (number, number)
				local v = MoveValidator.new(ValidatorWorld.build(TestWorld.build({}), { wall = wall, down = down }))
				if not budgeted then
					v.world.aroundBudget = math.huge
				end
				local perSecond: { number } = {}
				local calls = 0
				for i = 0, 239 do
					local now = 10 + i / 60
					local before = count
					v:budgeted("a", now, function(): any
						calls += 1
						-- (from outside the room, 0.5 to 8 st off its wall, to 3 st inside: no way round; the path long)
						local off = 0.5 + (i % 16) / 2
						return v.world.around(-6 - off, 0.3 * (i % 7), 3, -1, 0, 0, 1, 0, 80)
					end)
					local k = math.floor(i / 60) + 1
					perSecond[k] = (perSecond[k] or 0) + count - before
				end
				-- (the first second spends the full pool and what refills in it; every later one only what refills)
				local first, later = perSecond[1], 0
				for k = 2, #perSecond do
					later = math.max(later, perSecond[k])
				end
				return first, later, calls
			end
			local first, later, calls = run(true)
			local free = run(false)
			print(
				`      {calls} searches in 4 s: {first} wall rays in the first second, at most {later} in each after, budgeted (AROUND_BUDGET {C.AROUND_BUDGET}); {free} a second unbudgeted`
			)
			t.truthy(
				first <= 2 * C.AROUND_BUDGET + C.AROUND_RAYS,
				`the first second within the pool and its refill ({first})`
			)
			t.truthy(later <= C.AROUND_BUDGET + C.AROUND_RAYS, `every later second within the budget ({later})`)
			t.truthy(free > 3 * C.AROUND_BUDGET, `the budget binds here ({free} unbudgeted)`)
		end
	)
end
