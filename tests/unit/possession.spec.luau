--!strict
-- Spike S2 under Lune (BUILD_PLAN §4.3 S2, §1.5, D1, Addendum B4): the possession ledger,
-- the LoopWalker brain contract, Possession + ActorService + RoleService driven with table bodies
-- and PlayerLike stubs through the shared soak (tests/engine/PossessionSoak, which the engine
-- suite runs again on real Models), and the 49-slot cap.
local PossessionState = require("@shared/Actors/PossessionState")
local LoopWalker = require("@shared/Actors/LoopWalker")
local ActorService = require("@server/Actors/ActorService")
local Possession = require("@server/Actors/Possession")
local RoleService = require("@server/Roles/RoleService")
local Soak = require("@tests/engine/PossessionSoak")

type Body = { x: number, y: number, z: number, yaw: number, anchored: boolean, owner: any, alive: boolean }

local function fakeOps(): any
	return {
		pose = function(b: Body): (number, number, number, number)
			return b.x, b.y, b.z, b.yaw
		end,
		setMode = function(b: Body, mode: string, _snap: any)
			b.anchored = mode == "ai"
		end,
		alive = function(b: Body): boolean
			return b.alive
		end,
	}
end

local function world(nHumans: number, nSquirrels: number)
	local clock = { t = 0 }
	local engine = {
		streamAround = function() end,
		setOwner = function(root: Body, player: any)
			if player ~= nil and root.anchored then
				error("SetNetworkOwner on an anchored part")
			end
			root.owner = player
		end,
		setCharacter = function(player: any, model: any)
			player.Character = model
		end,
		rootOf = function(b: Body): Body
			return b
		end,
		markDriver = function() end,
		teleport = function(b: Body, x: number, y: number, z: number, yaw: number)
			b.x, b.y, b.z, b.yaw = x, y, z, yaw
		end,
		now = function(): number
			return clock.t
		end,
		serverTime = function(): number
			return clock.t
		end,
	}
	local actors = ActorService.new(fakeOps())
	local walkers: { [string]: LoopWalker.Walker } = {}
	local loop = { { x = -40, z = -40 }, { x = 40, z = -40 }, { x = 40, z = 40 }, { x = -40, z = 40 } }
	for i = 1, nHumans + nSquirrels do
		local species = if i <= nHumans then "human" else "squirrel"
		local w = LoopWalker.new(loop, if species == "human" then 3 else 20, i * 37, "walk")
		local x, z, yaw = LoopWalker.pose(w)
		local body: Body = { x = x, y = 3, z = z, yaw = yaw, anchored = true, owner = nil, alive = true }
		local id = `{species}_{i}`
		walkers[id] = w
		actors:register(ActorService.actor(id, species, "test", body, LoopWalker.brain(w)))
	end
	local possession = Possession.new({ actors = actors, engine = engine :: any })
	local function pickBody(_p: any): any
		for _, a in actors:all() do
			if possession:controllerOf(a) == "ai" then
				return a
			end
		end
		return nil
	end
	local roles = RoleService.new({
		possession = possession,
		pickBody = pickBody,
		kick = function(p: any, msg: string)
			p.kicked = msg
		end,
	})
	local function stepAI(dt: number)
		for _, a in actors:all() do
			if a.mode == "ai" then
				local x, z, yaw = LoopWalker.step(walkers[a.id], dt)
				local b = a.body :: Body
				b.x, b.z, b.yaw = x, z, yaw
			end
		end
	end
	return {
		clock = clock,
		actors = actors,
		possession = possession,
		roles = roles,
		walkers = walkers,
		stepAI = stepAI,
	}
end

return function(t)
	t.test("ledger: bind/unbind keep a bijection; double binds error", function()
		local l = PossessionState.newLedger()
		PossessionState.bind(l, 1, "a")
		PossessionState.bind(l, -2, "b")
		t.eq(PossessionState.actorOf(l, 1), "a")
		t.eq(PossessionState.driverOf(l, "b"), -2)
		t.fails(function()
			PossessionState.bind(l, 1, "c")
		end, "already drives")
		t.fails(function()
			PossessionState.bind(l, 3, "a")
		end, "already driven")
		t.eq(PossessionState.unbind(l, 1), "a")
		t.eq(PossessionState.unbind(l, 1), nil)
		t.eq(PossessionState.count(l), 1)
		t.truthy((PossessionState.check(l)))
	end)

	t.test("B4: 49 admitted, the 50th is turned away", function()
		t.truthy(PossessionState.admits(48))
		t.falsy(PossessionState.admits(49))
		t.eq(PossessionState.MAX_PLAYERS, 49)
	end)

	t.test("LoopWalker: walks at its speed, suspends still, resumes at the nearest arc point", function()
		local w = LoopWalker.new({ { x = 0, z = 0 }, { x = 10, z = 0 }, { x = 10, z = 10 }, { x = 0, z = 10 } }, 2)
		t.near(w.length, 40, 1e-9)
		LoopWalker.step(w, 1)
		local x, z = LoopWalker.pose(w)
		t.near(x, 2, 1e-9)
		t.near(z, 0, 1e-9)
		local snap = LoopWalker.suspend(w)
		t.near(snap.vx, 2, 1e-9)
		t.near(snap.yaw, math.atan2(-1, 0), 1e-9) -- facing +X
		LoopWalker.step(w, 1)
		t.near(LoopWalker.pose(w), 2, 1e-9) -- suspended: no motion
		local d = LoopWalker.resume(w, 11, 5)
		t.near(d, 1, 1e-9)
		t.near(w.s, 15, 1e-9)
		t.truthy(w.active)
	end)

	t.test("possess / release: body modes, Character, owner, payload snapshot", function()
		local wd = world(2, 1)
		local p = { UserId = 7, Name = "p7", Character = nil }
		local granted: any = nil
		wd.possession.deps.onGranted = function(_pl: any, payload: any)
			granted = payload
		end
		local a = wd.actors:get("human_1") :: any
		wd.stepAI(0.5)
		local ok = wd.possession:possess(p, a)
		t.truthy(ok)
		t.eq(p.Character, a.body)
		t.eq(a.body.owner, p)
		t.falsy(a.body.anchored)
		t.eq(a.mode, "player")
		t.eq(granted.actorId, "human_1")
		t.near(granted.snapshot.x, a.body.x, 1e-9)
		t.near(math.sqrt(granted.snapshot.vx ^ 2 + granted.snapshot.vz ^ 2), 3, 1e-9)
		t.eq(granted.holdSeconds, 0.75)
		t.falsy(wd.walkers.human_1.active)
		-- the player moves the body off the loop; release resumes the AI from there
		a.body.x += 2
		t.eq(wd.possession:release(p, "test"), "human_1")
		t.eq(p.Character, nil)
		t.eq(a.body.owner, nil)
		t.truthy(a.body.anchored)
		t.truthy(wd.walkers.human_1.active)
		t.truthy((wd.possession:check()))
	end)

	t.test("a driven body cannot be taken; a non-possessable one is refused", function()
		local wd = world(2, 0)
		local p1 = { UserId = 1, Name = "a", Character = nil }
		local p2 = { UserId = 2, Name = "b", Character = nil }
		local a = wd.actors:get("human_1") :: any
		t.truthy((wd.possession:possess(p1, a)))
		local ok, why = wd.possession:possess(p2, a)
		t.falsy(ok)
		t.eq(why, "body is driven")
		local b = wd.actors:get("human_2") :: any
		b.possessable = false
		t.falsy((wd.possession:possess(p2, b)))
		t.eq(p2.Character, nil)
	end)

	t.test("swap releases the old body and possesses the new one in one step", function()
		local wd = world(1, 1)
		local p = { UserId = 3, Name = "c", Character = nil }
		local h, s = wd.actors:get("human_1") :: any, wd.actors:get("squirrel_2") :: any
		wd.possession:possess(p, h)
		t.truthy((wd.possession:swap(p, s)))
		t.eq(h.mode, "ai")
		t.eq(s.mode, "player")
		t.eq(p.Character, s.body)
		t.eq(wd.possession.stats.swapped, 1)
		t.truthy((wd.possession:check()))
	end)

	t.test("a failing engine step rolls the body back to AI", function()
		local wd = world(1, 0)
		local p = { UserId = 4, Name = "d", Character = nil }
		local engine = wd.possession.engine :: any
		local real = engine.setOwner
		engine.setOwner = function(root: any, player: any)
			if player ~= nil then
				error("boom")
			end
			real(root, player)
		end
		local a = wd.actors:get("human_1") :: any
		local ok = wd.possession:possess(p, a)
		t.falsy(ok)
		t.eq(a.mode, "ai")
		t.truthy(a.body.anchored)
		t.eq(p.Character, nil)
		t.truthy(wd.walkers.human_1.active)
		t.truthy((wd.possession:check()))
	end)

	t.test("recover moves the body, never kills or replaces it", function()
		local wd = world(1, 0)
		local p = { UserId = 5, Name = "e", Character = nil }
		local a = wd.actors:get("human_1") :: any
		wd.possession:possess(p, a)
		local body = a.body
		local y0 = body.y
		for _ = 1, 100 do
			t.truthy(wd.possession:recover(p))
		end
		t.eq(a.body, body)
		t.eq(p.Character, body)
		t.near(body.y, y0 + 300, 1e-9)
		t.eq(wd.possession.stats.recovered, 100)
	end)

	t.test("soak: 500 possess/release cycles, 0 leaks, 0 errors, owners match, AI resumes <= 0.2 s", function()
		local wd = world(6, 3)
		local players = {}
		for i = 1, 6 do
			players[i] = { UserId = -i, Name = `Player{i}`, Character = nil }
		end
		local r = Soak.run({
			possession = wd.possession,
			actors = wd.actors,
			roles = wd.roles,
			players = players,
			cycles = 500,
			advance = function(dt: number)
				wd.clock.t += dt
			end,
			stepAI = wd.stepAI,
			aiTicks = function(a: any): number
				return wd.walkers[a.id].ticks
			end,
		})
		t.eq(#r.errors, 0, r.errors[1])
		t.eq(#r.invariantFailures, 0, r.invariantFailures[1])
		t.eq(r.leakedBodies, 0)
		t.truthy(r.possessed >= 500 and r.released >= 500, `{r.possessed}/{r.released}`)
		t.truthy(r.swaps > 0 and r.leaves > 0 and r.recovers > 0 and r.refusedAsExpected > 0)
		t.truthy(r.resumeSamples > 400, tostring(r.resumeSamples))
		t.truthy(r.resumeMaxSeconds <= 0.2, tostring(r.resumeMaxSeconds))
		t.truthy(r.ok)
	end)

	t.test("cap: 50 arrivals -> 49 admitted, the 50th kicked before any body", function()
		local wd = world(60, 0)
		local r = Soak.capCheck(wd.roles, wd.possession, function(i: number): any
			return { UserId = i, Name = `P{i}`, Character = nil }
		end, 50)
		t.eq(r.admitted, 49)
		t.eq(r.kicked, 1)
		t.falsy(r.kickedHadBody)
		t.eq(r.message, PossessionState.FULL_MESSAGE)
		t.truthy(r.ok)
	end)
end
