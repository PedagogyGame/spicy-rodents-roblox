--!strict
-- The S18 core as the paintball server lane extended it (Server/Paintball: PoseHistory, Projectiles,
-- Splats; checklist PB-1, PB-3, PB-4): the crouch channel of the pose history, a ball judged the
-- contract's way (Shared/Minigames/Paintball/Hit: its centre line, the entry point, nothing through a
-- wall), a ball that is already late flown forward through the bodies of its own past moments, the
-- early reject, the order two verdicts in one tick are given in, and the two splat pools.
local ArenaData = require("@shared/Minigames/Paintball/ArenaData")
local ArenaModule = require("@shared/Minigames/Paintball/Arena")
local Body = require("@shared/Minigames/Paintball/Body")
local Clock = require("@shared/Minigames/Paintball/Clock")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Wire = require("@shared/Minigames/Paintball/Wire")
local PoseHistory = require("@server/Paintball/PoseHistory")
local Projectiles = require("@server/Paintball/Projectiles")
local Splats = require("@server/Paintball/Splats")

local FLOOR = ArenaModule.FLOOR_HEIGHT

-- a body that has stood at one pose for a second, as the snapshot stream would have recorded it
local function standing(id: number, team: number, x: number, y: number, z: number, crouch: number): Projectiles.Target
	local history = PoseHistory.new(Clock.HISTORY_SECS, Clock.SNAP_HZ)
	for k = -20, 0 do
		PoseHistory.push(history, 100 + k / Clock.SNAP_HZ, x, y, z, crouch)
	end
	return { id = id, team = team, history = history, live = true, x = x, y = y, z = z }
end

-- fly every ball of a sim to its end, a server tick at a time, from t = 100
local function finish(sim: Projectiles.Sim, targets: { Projectiles.Target }, onEnd: Projectiles.OnEnd?)
	local now = 100
	for _ = 1, 120 do
		now += 1 / 60
		Projectiles.step(sim, now, 1 / 60, targets, onEnd)
	end
end

return function(t)
	t.test("pose history: the crouch fraction rides in the ring and is interpolated like the position", function()
		local h = PoseHistory.new(Clock.HISTORY_SECS, Clock.SNAP_HZ)
		PoseHistory.push(h, 10, 0, 14, 0, 0)
		PoseHistory.push(h, 10.05, 1, 14, 0, 1)
		local x, y, _, c = PoseHistory.sample(h, 10.025)
		t.near(x, 0.5, 1e-9)
		t.eq(y, 14)
		t.near(c, 0.5, 1e-9)
		t.eq(select(4, PoseHistory.sample(h, 99)), 1, "held at the newest")
		t.eq(select(4, PoseHistory.sample(h, 0)), 0, "held at the oldest")
		local at, nx, _, _, nc = PoseHistory.newest(h)
		t.deepEq({ at, nx, nc }, { 10.05, 1, 1 })
		PoseHistory.push(h, 10.1, 2, 14, 0)
		t.eq(select(4, PoseHistory.sample(h, 10.1)), 0, "no crouch given means standing")
		PoseHistory.clear(h)
		t.eq(h.count, 0)
		t.deepEq({ PoseHistory.sample(h, 10) }, { 0, 0, 0, 0 })
	end)

	t.test("a ball 0.05 over the rail misses the crouched body behind it and tags the standing one", function()
		local arena = ArenaData.build()
		local feel = Contract.feel({ ballDrop = 0 })
		-- the west rail of the first storey: x -15.5 .. -15, its top RAIL_HEIGHT over the floor
		local railTop = FLOOR + ArenaModule.RAIL_HEIGHT
		local over = railTop + 0.05
		t.truthy(Body.top(1) < ArenaModule.RAIL_HEIGHT, "a crouched body is lower than the rail")
		for _, case in { { crouch = 1, hit = 0 }, { crouch = 0, hit = 2 } } do
			local sim = Projectiles.forArena(arena, feel)
			local target = standing(2, 2, -17, FLOOR, 0, case.crouch)
			local ball = Projectiles.fire(sim, 1, 1, 10, over, 0, -feel.ballSpeed, 0, 0, 0, 100)
			finish(sim, { target })
			t.truthy(ball.done)
			t.eq(ball.hitBody, case.hit, `crouch {case.crouch}`)
			if case.hit ~= 0 then
				-- the entry point: on the capsule's near side, at the ball's own height
				t.near(ball.hx, -17 + Body.RADIUS, 1e-6)
				t.near(ball.hy, over, 1e-6)
				t.deepEq({ ball.bx, ball.by, ball.bz }, { -17, FLOOR, 0 }, "and the feet it was judged at")
			else
				t.truthy(ball.hitWall, "it flew on to the far wall")
			end
		end
		-- a ball level with the rail's middle stops on the rail, whoever stands behind it
		local sim = Projectiles.forArena(arena, feel)
		local ball = Projectiles.fire(sim, 1, 1, 10, FLOOR + 2, 0, -feel.ballSpeed, 0, 0, 0, 100)
		finish(sim, { standing(2, 2, -17, FLOOR, 0, 0) })
		t.truthy(ball.hitWall)
		t.near(ball.hx, -15, 1e-6)
		t.deepEq({ ball.nx, ball.ny, ball.nz }, { 1, 0, 0 })
	end)

	t.test(
		"who may be hit: a team-mate, a body that is not live and a body in its own spawn room are passed over",
		function()
			local arena = ArenaData.build()
			local feel = Contract.feel({ ballDrop = 0 })
			local function shot(target: Projectiles.Target): number
				local sim = Projectiles.forArena(arena, feel)
				local ball = Projectiles.fire(sim, 1, 1, 30, 3, 40, -feel.ballSpeed, 0, 0, 0, 100)
				finish(sim, { target })
				return ball.hitBody
			end
			t.eq(shot(standing(2, 2, 0, 0, 40, 0)), 2)
			t.eq(shot(standing(2, 1, 0, 0, 40, 0)), 0, "no friendly fire")
			local out = standing(2, 2, 0, 0, 40, 0)
			out.live = false
			t.eq(shot(out), 0)
			local roomed = standing(2, 2, 0, 0, 40, 0)
			roomed.room = { minX = -5, minY = 0, minZ = 35, maxX = 5, maxY = 6, maxZ = 45 }
			t.eq(shot(roomed), 0, "its rewound feet are inside its own room")
			local empty = standing(2, 2, 0, 0, 40, 0)
			PoseHistory.clear(empty.history)
			t.eq(shot(empty), 0, "a body with no history is nowhere")
		end
	)

	t.test(
		"a late ball is flown forward at once, each piece against the bodies of its own moment; the rewind is clamped",
		function()
			local arena = ArenaData.build()
			local feel = Contract.feel({ ballDrop = 0 })
			-- a runner crossing the ball's line at 20 studs/s, recorded at the snapshot rate
			local history = PoseHistory.new(Clock.HISTORY_SECS, Clock.SNAP_HZ)
			local function zAt(time: number): number
				return 40 + (time - 100) * 20
			end
			local target: Projectiles.Target = { id = 2, team = 2, history = history, live = true }
			local now = 100
			for k = -20, 0 do
				PoseHistory.push(history, now + k / Clock.SNAP_HZ, 0, 0, zAt(now + k / Clock.SNAP_HZ), 0)
			end
			-- the shooter saw the runner 0.15 s ago and fired 0.2 s ago at where it then was: the ball needs
			-- 30 studs (a third of a second) to get there, so the body it meets is the one of born + age - rewind
			local born, rewind = now - 0.2, 0.15
			local meet = born + 30 / feel.ballSpeed - rewind
			local sim = Projectiles.forArena(arena, feel)
			local ball = Projectiles.fire(sim, 1, 1, 30, 3, zAt(meet), -feel.ballSpeed, 0, 0, rewind, born)
			local ended = 0
			Projectiles.advance(sim, ball, now, { target }, function()
				ended += 1
			end)
			t.near(ball.age, 0.2, 1e-9, "it has flown the part the shooter already saw")
			t.falsy(ball.done)
			for _ = 1, 30 do
				now += 1 / 60
				if (now * Clock.SNAP_HZ) % 1 < 0.34 then
					PoseHistory.push(history, now, 0, 0, zAt(now), 0)
				end
				Projectiles.step(sim, now, 1 / 60, { target }, function()
					ended += 1
				end)
			end
			t.eq(ball.hitBody, 2, "it met the body where the shooter saw it")
			t.eq(ended, 1, "and was reported once")
			t.eq(#sim.balls, 0)
			-- the same shot judged at the present misses: the runner has moved three studs on
			local naive = Projectiles.forArena(arena, feel)
			local miss = Projectiles.fire(naive, 1, 1, 30, 3, zAt(meet), -feel.ballSpeed, 0, 0, 0, born)
			Projectiles.advance(naive, miss, now, { target })
			t.eq(miss.hitBody, 0)
			local far = Projectiles.fire(naive, 1, 1, 0, 3, 0, 1, 0, 0, 5, now)
			t.eq(far.rewind, Clock.MAX_REWIND)
			t.eq(naive.stats.rewindClamped, 1)
		end
	)

	t.test("the early reject: a body a storey away or across the building costs no history sample", function()
		local arena = ArenaData.build()
		local feel = Contract.feel()
		local sim = Projectiles.forArena(arena, feel)
		local targets = {
			standing(2, 2, 40, 0, -40, 0), -- far across the floor
			standing(3, 2, 0, 3 * FLOOR, 40, 0), -- three storeys up
		}
		Projectiles.fire(sim, 1, 1, -40, 3, 40, feel.ballSpeed, 0, 0, 0, 100)
		Projectiles.step(sim, 100 + 1 / 60, 1 / 60, targets)
		t.eq(sim.stats.samples, 0)
		t.eq(sim.stats.rejected, 2)
		-- without a newest pose a target is always sampled
		targets[1].x = nil
		Projectiles.step(sim, 100 + 2 / 60, 1 / 60, targets)
		t.eq(sim.stats.samples, 1)
	end)

	t.test(
		"two verdicts in one tick: the older ball tags, the younger flies on; a tie between bodies goes to the lower slot",
		function()
			local arena = ArenaData.build()
			local feel = Contract.feel({ ballDrop = 0 })
			for round = 1, 3 do
				local sim = Projectiles.forArena(arena, feel)
				local victim = standing(2, 2, 0, 0, 40, 0)
				local bystander = standing(9, 2, 0, 0, 20, 0)
				-- two balls from two shooters reach the one body in the same tick
				local first = Projectiles.fire(sim, 1, 1, 30, 3, 40, -feel.ballSpeed, 0, 0, 0, 100)
				local second = Projectiles.fire(sim, 3, 1, -30, 3, 40, feel.ballSpeed, 0, 0, 0, 100)
				local order: { number } = {}
				finish(sim, if round == 2 then { bystander, victim } else { victim, bystander }, function(ball)
					table.insert(order, ball.id)
					if ball.hitBody ~= 0 then
						victim.live = false -- what the service does on a tag, before the next ball is stepped
					end
				end)
				t.eq(first.hitBody, 2, `round {round}`)
				t.eq(second.hitBody, 0, "the younger ball found nobody there to tag")
				t.truthy(second.hitWall)
				t.eq(order[1], first.id)
			end
			-- one ball, two bodies at the same place: the lower slot id is the one tagged
			local sim = Projectiles.forArena(arena, feel)
			local ball = Projectiles.fire(sim, 1, 1, 30, 3, 40, -feel.ballSpeed, 0, 0, 0, 100)
			finish(sim, { standing(4, 2, 0, 0, 40, 0), standing(6, 2, 0, 0, 40, 0) })
			t.eq(ball.hitBody, 4)
		end
	)

	t.test("ball ids run 1..65535 and round again; clear empties the sim", function()
		local sim = Projectiles.forArena(ArenaData.build(), Contract.feel())
		sim.nextId = 65534
		t.eq(Projectiles.fire(sim, 1, 1, 0, 3, 0, 1, 0, 0, 0, 100).id, 65535)
		t.eq(Projectiles.fire(sim, 1, 1, 0, 3, 0, 1, 0, 0, 0, 100).id, 1)
		Projectiles.clear(sim)
		t.eq(#sim.balls, 0)
	end)

	t.test("splats: two pools with one seq; paint on the walls never pushes paint off a body", function()
		local R = Contract.Rules
		local pools = Splats.pools(R.splatPool, R.bodySplats)
		local onBody = Splats.body(pools, 7, 1, 1, 4, 0.5, 3, -1.2)
		t.deepEq(onBody, { seq = 1, ball = 7, by = 1, body = 4, team = 1, face = 0, x = 0.5, y = 3, z = -1.2 })
		for i = 1, R.splatPool + 50 do
			Splats.wall(pools, i, 2, 2, Wire.FACE.px, i, 0, 0)
		end
		local walls, bodies = Splats.count(pools)
		t.eq(walls, R.splatPool)
		t.eq(bodies, 1, "the body's splat is still there")
		for i = 1, R.bodySplats + 5 do
			Splats.body(pools, i, 1, 1, 4, 0, i, 0)
		end
		t.eq(select(2, Splats.count(pools)), R.bodySplats, "a body keeps its newest few")
		local batch = Splats.batch(pools)
		t.eq(#batch, R.splatPool + R.bodySplats)
		for i = 2, #batch do
			t.truthy(batch[i].seq > batch[i - 1].seq, "oldest first")
		end
		t.eq(batch[#batch].seq, pools.seq)
		-- every record is one the wire carries
		local back = Wire.unpack(Wire.Splat, Wire.pack(Wire.Splat, batch))
		t.eq(#back, #batch)
		t.eq(back[1].seq, batch[1].seq)
		-- a slot whose occupant changed loses its paint; a new match loses all of it
		Splats.clearBody(pools, 4)
		t.eq(select(2, Splats.count(pools)), 0)
		Splats.reset(pools)
		t.deepEq({ Splats.count(pools) }, { 0, 0 })
		t.eq(Splats.wall(pools, 1, 1, 1, 0, 0, 0, 0).seq, 1)
	end)
end
