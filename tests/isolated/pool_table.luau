--!strict
-- tests/isolated/pool_table.luau: cases for tests/unit/pool_table.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- What every screen shows of the cue tables once the rules have had their say, on tests/lib/MinigameRig (the real
-- service with the cue games' Table, the real client with Pool/CueController and Pool/Playback): a ball the rules
-- put back after a shot (the 8 potted on the break, a scratched cue ball, a practice ball back by its cup) is
-- where the rules have it on the shooter's screen, the other player's and a watcher's; a client that walks up
-- mid-game and mid-shot; the words when the other player leaves mid-shot or is taken off for idling; a bumper
-- pool opening the clock decides. Nothing here knows where a table stands: every position comes from
-- Attractions/AlleyLayout through the game's own Spec at run time.
-- Interface: return function(t) (the spec shape)
local Cue = require("@shared/Minigames/Pool/Cue")
local EightBall = require("@shared/Minigames/Pool/EightBall")
local Furniture = require("@shared/Minigames/Pool/Furniture")
local Shot = require("@shared/Minigames/Pool/Shot")
local Tables = require("@shared/Minigames/Pool/Tables")
local Wire = require("@shared/Minigames/Pool/Wire")
local Playback = require("@client/Minigames/Pool/Playback")
local Computer = require("@shared/Minigames/Pool/Computer")
local PoolRig = require("@tests/pool/PoolRig")
local Rig = require("@tests/lib/MinigameRig")

local POOL = "pool_1"
local BUMPER = "bumper_pool_1"

local function opts(id: string, extra: { [string]: any }?): { [string]: any }
	local o: { [string]: any } = { furnish = PoolRig.furnish, stand = PoolRig.stand(id) }
	for k, v in extra or {} do
		o[k] = v
	end
	return o
end

local function tableOf(id: string): any
	return if string.sub(id, 1, 6) == "bumper" then Tables.bumper() else Tables.eightBall()
end

-- Every ball of the table on this screen where the rules have it: on the cloth at its spot, or at home in the
-- tray (or out of sight, if `away` names it).
local function allAt(t: any, w: any, id: string, label: string, away: { [number]: boolean }?)
	local state = PoolRig.state(w, id)
	local tb = tableOf(id)
	local on: { [number]: boolean } = {}
	for _, s in state.spots do
		on[s.id] = true
		local bx, bz, by = PoolRig.ball(w, id, s.id)
		t.near(bx, s.x, 1e-3, `{label}: ball {s.id} lies where the rules have it (x)`)
		t.near(bz, s.z, 1e-3, `{label}: ball {s.id} lies where the rules have it (z)`)
		t.near(by, tb.ballR, 1e-3, `{label}: ball {s.id} is on the cloth`)
	end
	local ids = if tb.id == "bumper"
		then { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
		else { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }
	for _, b in ids do
		if not on[b] then
			local hx, hy, hz = Furniture.off(tb, b, away ~= nil and away[b] == true)
			local bx, bz, by = PoolRig.ball(w, id, b)
			t.near(bx, hx, 1e-3, `{label}: ball {b} is at home (x)`)
			t.near(bz, hz, 1e-3, `{label}: ball {b} is at home (z)`)
			t.near(by, hy, 1e-3, `{label}: ball {b} is at home (y)`)
		end
	end
end

-- The balls on this screen are where the script has them at this instant (a ball dropping or rolling home is
-- the playback's own and is left out).
local function onScript(t: any, w: any, id: string, script: any, label: string): number
	local now = assert(Playback.now(id), "nothing is playing")
	local at = math.min(math.max(now, 0), script.tEnd)
	local n = 0
	for i, b in script.ids do
		if #script.tracks[i] > 0 then
			local x, z, _, mode = Shot.pose(script, i, at)
			if mode ~= 3 then
				local bx, bz = PoolRig.ball(w, id, b)
				t.near(bx, x, 1e-3, `{label}: ball {b} x`)
				t.near(bz, z, 1e-3, `{label}: ball {b} z`)
				n += 1
			end
		end
	end
	return n
end

-- An eight-ball table laid out for a check: the given balls up, the rest down.
local function layout(w: any, spots: { { id: number, x: number, z: number } }, fields: { [string]: any })
	local ok, why = w.svc:debug(POOL, "layout", spots, fields)
	assert(ok, why)
	Rig.run(w, 0.3)
end

-- The cue ball and the 8 in line with the near left corner pocket, the 8 1.2 studs from it: a straight tap
-- pots it. A solid and a stripe lie out of the way.
local function eightByThePocket(): ({ { id: number, x: number, z: number } }, number)
	local tb = Tables.eightBall()
	local hole = tb.holes[1]
	local l = math.sqrt(hole.x * hole.x + hole.z * hole.z)
	local dx, dz = -hole.x / l, -hole.z / l
	return {
		{ id = 0, x = hole.x + dx * 2.4, z = hole.z + dz * 2.4 },
		{ id = 8, x = hole.x + dx * 1.2, z = hole.z + dz * 1.2 },
		{ id = 3, x = 0.5, z = 0.3 },
		{ id = 12, x = -0.5, z = 0.3 },
	},
		Cue.angleOf(-dx, -dz)
end

-- The cue ball 1.2 studs from the left side pocket, nothing between: straight in.
local function scratchLayout(): ({ { id: number, x: number, z: number } }, number)
	local tb = Tables.eightBall()
	local hole = tb.holes[3]
	return {
		{ id = 0, x = hole.x + 1.4, z = 0 },
		{ id = 8, x = 0.6, z = 3 },
		{ id = 3, x = 0.5, z = 0.9 },
		{ id = 12, x = -0.5, z = 2.2 },
	},
		Cue.angleOf(-1, 0)
end

return function(t)
	t.test(
		"the 8 potted on the break is back on its spot on the shooter's screen, and a scratch on the other's",
		function()
			Rig.play(function(w)
				PoolRig.clock(w)
				local bob = Rig.stub("Bob")
				Rig.press(w, POOL)
				Rig.run(w, 0.3)
				t.truthy(w.svc:join(bob, POOL))
				Rig.click(w, "Start now")
				Rig.run(w, 0.5)
				local state = PoolRig.state(w, POOL)
				t.eq(state.seat, 1, "Ann breaks")
				local spots, angle = eightByThePocket()
				layout(w, spots, { broken = false, inHand = "none", seat = 1 })
				allAt(t, w, POOL, "the scripted rack")
				-- Ann's break: the 8 drops, the rules put it back on the foot spot, and Ann keeps the table
				t.truthy(w.svc:debug(POOL, "shoot", { angle, 0.35, 0, -0.3 }))
				t.truthy(PoolRig.settle(w, POOL))
				Rig.run(w, 0.5)
				t.eq(state.last.pots[1], 8, "the 8 went down on the break")
				t.eq(state.seat, 1, "and Ann keeps the table")
				local eight: any = nil
				for _, s in state.spots do
					if s.id == 8 then
						eight = s
					end
				end
				t.truthy(eight, "the 8 is back on the cloth")
				allAt(t, w, POOL, "after the 8 on the break")
				-- Bob's go: he scratches in the side pocket; on Ann's screen the cue ball is on the head spot
				local spots2, angle2 = scratchLayout()
				layout(w, spots2, { broken = true, inHand = "none", seat = 2, group = {} })
				t.eq(state.seat, 2)
				local ok, why = Rig.input(w, bob, POOL, "shoot", { angle2, 0.3, 0, 0 })
				t.truthy(ok, why)
				t.truthy(PoolRig.settle(w, POOL))
				Rig.run(w, 0.5)
				t.eq(state.last.foul, "scratch", "Bob scratched")
				t.eq(state.seat, 1, "Ann has the table")
				t.eq(state.inHand, "anywhere", "with the cue ball in hand")
				allAt(t, w, POOL, "after Bob's scratch, on Ann's screen")
				-- and the shot message carried it: every screen ends where the rules have the balls
				local msg = Rig.last(w.got, "pool_shot")
				t.truthy(
					type(msg.after) == "table" and #msg.after == #state.spots * 3,
					"the judged layout rides with the shot"
				)
			end, opts(POOL))
		end
	)

	t.test(
		"someone who only watches sees the re-spotted 8 and the scratched cue ball where the rules have them",
		function()
			Rig.play(
				function(w)
					PoolRig.clock(w)
					local bob, cid = Rig.stub("Bob"), Rig.stub("Cid")
					t.truthy(w.svc:join(bob, POOL))
					t.truthy(w.svc:join(cid, POOL))
					t.truthy(Rig.input(w, bob, POOL, "start"))
					Rig.run(w, 0.5)
					local state = PoolRig.state(w, POOL)
					local spots, angle = eightByThePocket()
					layout(w, spots, { broken = false, inHand = "none", seat = 1 })
					t.truthy(Rig.input(w, bob, POOL, "shoot", { angle, 0.35, 0, -0.3 }))
					t.truthy(PoolRig.settle(w, POOL))
					Rig.run(w, 0.5)
					t.eq(state.last.pots[1], 8)
					allAt(t, w, POOL, "watched: the 8 on the break")
					local spots2, angle2 = scratchLayout()
					layout(w, spots2, { broken = true, inHand = "none", seat = 2, group = {} })
					t.truthy(Rig.input(w, cid, POOL, "shoot", { angle2, 0.3, 0, 0 }))
					t.truthy(PoolRig.settle(w, POOL))
					Rig.run(w, 0.5)
					t.eq(state.last.foul, "scratch")
					allAt(t, w, POOL, "watched: Cid's scratch")
					t.eq(w.client.active(), nil, "watching is not playing")
				end,
				opts(POOL, {
					stand = {
						site = "bowling_alley",
						x = PoolRig.stand("pool_2").x,
						y = 3,
						d = PoolRig.stand("pool_2").d,
					},
				})
			)
		end
	)

	t.test("bumper practice: a ball sunk in the near cup is back on its spot on screen, not in the tray", function()
		Rig.play(function(w)
			PoolRig.clock(w)
			Rig.press(w, BUMPER)
			Rig.run(w, 0.3)
			Rig.click(w, "Start now")
			Rig.run(w, 0.5)
			local state = PoolRig.state(w, BUMPER)
			local tb = Tables.bumper()
			local cup = tb.holes[1]
			local start = Tables.bumperStart({ true, false })
			-- the marked ball half a stud in front of the near cup, aimed straight into it
			local spots = {}
			for _, s in start do
				if s.id == 1 then
					table.insert(spots, { id = 1, x = cup.x, z = cup.z + 0.7 })
				else
					table.insert(spots, { id = s.id, x = s.x, z = s.z })
				end
			end
			local ok, why = w.svc:debug(BUMPER, "layout", spots, {})
			t.truthy(ok, why)
			Rig.run(w, 0.3)
			t.truthy(w.svc:debug(BUMPER, "shoot", { 1, Cue.angleOf(0, -1), 0.12, 0, 0 }))
			t.truthy(PoolRig.settle(w, BUMPER))
			Rig.run(w, 0.5)
			t.eq(state.last.respotted[1], 1, "the marked ball dropped in the near cup and was put back")
			local away: { [number]: boolean } = {}
			for id = 6, 10 do
				away[id] = true
			end
			allAt(t, w, BUMPER, "after the near cup", away)
			local msg = Rig.last(w.got, "bumper_pool_shot")
			t.eq(#msg.away, 5, "practice: the other five stay out of sight")
			t.truthy(Wire.decode(msg.text))
		end, opts(BUMPER))
	end)

	t.test(
		"a client the table reaches only mid-game and mid-shot takes the shot up where it is, then plays on",
		function()
			Rig.play(
				function(w)
					PoolRig.clock(w)
					-- Ann is across the building: pool table 1 is not on her client (streamed out). Bob plays Chalky.
					local room = w.roots.bowling_alley:FindFirstChild("GamesRoom")
					local model = room:FindFirstChild(Furniture.modelName("pool", 1))
					model.Parent = nil
					local bob = Rig.stub("Bob")
					t.truthy(w.svc:join(bob, POOL))
					t.truthy(Rig.input(w, bob, POOL, "addai", { "Chalky" }))
					t.truthy(Rig.input(w, bob, POOL, "start"))
					Rig.run(w, 0.3)
					local state = PoolRig.state(w, POOL)
					local st = PoolRig.station(w, POOL)
					local function bobsGo(seed: number)
						if EightBall.turn(state) == 1 then
							for _, input in Computer.eightBall(state, 2, seed) do
								assert(Rig.input(w, bob, POOL, input.verb, input.args))
							end
						end
					end
					-- two shots go by while the table is away from her
					local shots = 0
					local guard = 0
					while shots < 2 and guard < 30 do
						guard += 1
						t.truthy(PoolRig.settle(w, POOL))
						local before = Rig.count(w.got, "pool_shot")
						bobsGo(70 + guard)
						if
							Rig.untilTrue(w, 12, function()
								return Rig.count(w.got, "pool_shot") > before
							end)
						then
							shots += 1
							t.eq(Playback.playing(POOL), false, "nothing is drawn of a table that is not here")
						end
					end
					t.truthy(PoolRig.settle(w, POOL))
					-- the next shot: just after the strike she walks into the games room and the table arrives
					local before = Rig.count(w.got, "pool_shot")
					bobsGo(99)
					t.truthy(Rig.untilTrue(w, 12, function()
						return Rig.count(w.got, "pool_shot") > before
					end))
					local msg = Rig.last(w.got, "pool_shot")
					local script = assert(Wire.decode(msg.text))
					Rig.run(w, msg.lead + 0.3)
					t.truthy(st.tbl.pending ~= nil and script.tEnd > 0.6, "the shot is still running")
					model.Parent = room
					Rig.frame(w)
					t.truthy(Playback.playing(POOL), "the shot is taken up where it has got to")
					t.truthy((Playback.now(POOL) or 0) > 0.25, "part way through, not from its start")
					t.truthy(onScript(t, w, POOL, script, "taken up mid-shot") > 0)
					Rig.run(w, 0.2)
					onScript(t, w, POOL, script, "and played on")
					t.truthy(PoolRig.settle(w, POOL))
					Rig.run(w, 0.5)
					allAt(t, w, POOL, "the table still, on the late client")
					-- and the next shot plays from its start on her screen
					before = Rig.count(w.got, "pool_shot")
					bobsGo(101)
					t.truthy(Rig.untilTrue(w, 12, function()
						return Rig.count(w.got, "pool_shot") > before
					end))
					msg = Rig.last(w.got, "pool_shot")
					script = assert(Wire.decode(msg.text))
					t.truthy(Playback.playing(POOL))
					Rig.run(w, msg.lead + 0.2)
					onScript(t, w, POOL, script, "the next shot")
					t.truthy(PoolRig.settle(w, POOL))
					Rig.run(w, 0.5)
					allAt(t, w, POOL, "after the next shot")
				end,
				opts(POOL, {
					stand = {
						site = "bowling_alley",
						x = PoolRig.stand("pool_2").x,
						y = 3,
						d = PoolRig.stand("pool_2").d,
					},
				})
			)
		end
	)

	t.test("the other player leaves while my break rolls: I win by forfeit, and my shot is seen to its end", function()
		Rig.play(function(w)
			PoolRig.clock(w)
			local bob = Rig.stub("Bob")
			Rig.press(w, POOL)
			Rig.run(w, 0.3)
			t.truthy(w.svc:join(bob, POOL))
			Rig.click(w, "Start now")
			Rig.run(w, 0.5)
			local state = PoolRig.state(w, POOL)
			local st = PoolRig.station(w, POOL)
			local racks = Rig.count(w.got, "pool_rack")
			-- my break, through the same path as a strike of mine; Bob walks off while the balls run
			t.truthy(w.svc:debug(POOL, "shoot", { 0, 0.9, 0, 0 }))
			Rig.run(w, 0.4)
			t.truthy(st.tbl.pending, "the break is rolling")
			local msg = Rig.last(w.got, "pool_shot")
			w.svc:leave(bob, "left")
			Rig.run(w, 0.3)
			t.eq(state.how, "left")
			t.eq(state.winner, 1)
			t.truthy(PoolRig.settle(w, POOL))
			Rig.run(w, 0.8)
			t.eq(Rig.count(w.got, "pool_rack"), racks, "my break is not taken back")
			t.falsy(Rig.has(w.toasts, "does not count"), table.concat(w.toasts, " | "))
			local screen = Rig.screen(w)
			t.falsy(string.find(screen, "does not count", 1, true), screen)
			t.truthy(string.find(screen, "Ann wins: Bob left the table.", 1, true), screen)
			-- every ball lies where the break left it, on my screen and on the server's table
			local flat = msg.after
			for k = 1, #flat - 2, 3 do
				local bx, bz = PoolRig.ball(w, POOL, flat[k])
				t.near(bx, flat[k + 1], 1e-3, `ball {flat[k]} where the break left it`)
				t.near(bz, flat[k + 2], 1e-3)
				local at = st.tbl.hw:position(flat[k])
				local x, _, z = Furniture.fromWorld(w.places.bowling_alley, PoolRig.def(w, POOL), at.X, at.Y, at.Z)
				t.near(x, flat[k + 1], 1e-3, `and on the server's table`)
				t.near(z, flat[k + 2], 1e-3)
			end
		end, opts(POOL))
	end)

	t.test("taken off for not playing: the end card says so, and each timeout is one banner", function()
		Rig.play(function(w)
			PoolRig.clock(w)
			local bob = Rig.stub("Bob")
			Rig.press(w, POOL)
			Rig.run(w, 0.3)
			t.truthy(w.svc:join(bob, POOL))
			Rig.click(w, "Start now")
			Rig.run(w, 0.5)
			local state = PoolRig.state(w, POOL)
			local session = w.svc:sessionOf(POOL)
			local banners = 0
			local guard = 0
			while session.phase == "playing" and guard < 8 do
				guard += 1
				t.truthy(PoolRig.settle(w, POOL))
				if state.seat == 1 then
					-- my go: a tap that reaches nothing (a foul: Bob has the ball in hand), then Bob's clock runs
					if state.inHand ~= "none" then
						t.truthy(w.svc:debug(POOL, "layout", state.spots, { inHand = "none" }))
						Rig.run(w, 0.2)
					end
					t.truthy(w.svc:debug(POOL, "shoot", { math.pi, 0.04, 0, 0 }))
					t.truthy(PoolRig.settle(w, POOL))
					Rig.run(w, 0.5)
				else
					local before = #w.got
					Rig.run(w, 61)
					for i = before + 1, #w.got do
						local m = w.got[i]
						if
							m.kind == "event"
							and type(m.text) == "string"
							and string.find(m.text, "took too long", 1, true)
						then
							banners += 1
						end
						t.falsy(
							m.kind == "event"
								and type(m.text) == "string"
								and string.find(m.text, "ran out of time", 1, true),
							"what the timeout means is not a second banner"
						)
					end
				end
			end
			t.eq(session.phase, "done")
			t.eq(state.how, "removed")
			t.truthy(banners >= 2, `{banners} timeouts`)
			t.truthy(Rig.has(w.toasts, "Bob ran out of time"), table.concat(w.toasts, " | "))
			local screen = Rig.screen(w)
			t.truthy(string.find(screen, "Ann wins: Bob was taken off the table for not playing.", 1, true), screen)
			t.falsy(string.find(screen, "left the table", 1, true), screen)
		end, opts(POOL))
	end)

	t.test("bumper pool: the second opener strikes first; the first then strikes, and the table plays both", function()
		Rig.play(function(w)
			PoolRig.clock(w)
			local bob = Rig.stub("Bob")
			Rig.press(w, BUMPER)
			Rig.run(w, 0.3)
			t.truthy(w.svc:join(bob, BUMPER))
			Rig.click(w, "Start now")
			Rig.run(w, 0.5)
			local state = PoolRig.state(w, BUMPER)
			local c = PoolRig.controller(BUMPER)
			t.eq(state.phase, "opening")
			t.eq(c.phase, "aim", "I may strike my opening shot")
			-- Bob, the second seat, strikes first: it stands
			local shots = Rig.count(w.got, "bumper_pool_shot")
			local bobs = Computer.bumper(state, 2, 2, 9)
			local ok, why = Rig.input(w, bob, BUMPER, bobs[#bobs].verb, bobs[#bobs].args)
			t.truthy(ok, `the second opener's strike is taken: {why}`)
			Rig.run(w, 0.3)
			t.truthy(state.pending[2], "Bob's strike is in")
			t.eq(Rig.count(w.got, "bumper_pool_shot"), shots, "the table waits for mine")
			t.eq(c.phase, "aim", "and it is still my go")
			-- mine: the table plays the two together, and I watch my own opening
			PoolRig.play(w, c, Computer.bumper(state, 1, 2, 10))
			t.truthy(Rig.untilTrue(w, 2, function()
				return Rig.count(w.got, "bumper_pool_shot") > shots
			end))
			local script = assert(Wire.decode(Rig.last(w.got, "bumper_pool_shot").text))
			t.eq(#script.strikes, 12, "two strikes in one run")
			Rig.run(w, 0.1)
			t.eq(c.phase, "watch")
			t.truthy(PoolRig.settle(w, BUMPER))
			t.eq(state.phase, "play")
		end, opts(BUMPER))
	end)

	t.test(
		"bumper pool: one opener strikes and the other lets the clock run out; the opening plays on every screen",
		function()
			Rig.play(
				function(w)
					PoolRig.clock(w)
					local ann, bob = Rig.stub("Ann2"), Rig.stub("Bob")
					t.truthy(w.svc:join(ann, BUMPER))
					t.truthy(w.svc:join(bob, BUMPER))
					t.truthy(Rig.input(w, ann, BUMPER, "start"))
					Rig.run(w, 0.5)
					local state = PoolRig.state(w, BUMPER)
					local st = PoolRig.station(w, BUMPER)
					for _, input in Computer.bumper(state, 1, 2, 4) do
						assert(Rig.input(w, ann, BUMPER, input.verb, input.args))
					end
					local shots = Rig.count(w.got, "bumper_pool_shot")
					-- Bob idles out his opening
					t.truthy(
						Rig.untilTrue(w, 50, function()
							return Rig.count(w.got, "bumper_pool_shot") > shots
						end),
						"the opening was never shown"
					)
					t.truthy(st.tbl:busy(), "the turn clock waits while it plays")
					t.truthy(Rig.last(ann.events, "bumper_pool_shot"), "the opener is sent it")
					t.truthy(Playback.playing(BUMPER) or (Rig.last(w.got, "bumper_pool_shot").lead or 0) > 0)
					Rig.run(w, 0.3)
					t.truthy(Playback.playing(BUMPER), "the watcher sees the opening run")
					-- the words come when the balls stop
					t.falsy(Rig.last(ann.events, "event", function(m: any): boolean
						return type(m.text) == "string"
							and string.find(m.text, "opening", 1, true) ~= nil
							and m.shot ~= nil
					end))
					t.truthy(PoolRig.settle(w, BUMPER))
					Rig.run(w, 0.3)
					t.eq(state.phase, "play")
					allAt(t, w, BUMPER, "after the opening the clock decided")
				end,
				opts(BUMPER, {
					stand = {
						site = "bowling_alley",
						x = PoolRig.stand("pool_2").x,
						y = 3,
						d = PoolRig.stand("pool_2").d,
					},
				})
			)
		end
	)
end
