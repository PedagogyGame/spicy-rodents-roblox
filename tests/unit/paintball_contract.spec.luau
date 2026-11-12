--!strict
-- The paintball contract (Shared/Minigames/Paintball: Contract, Body, Clock, Wire, Arena, Spec) pinned
-- against the owner's bar (brief v2 §13, §14; checklist PB-1 to PB-15), against the minigame framework
-- it sits in, and against itself. FROZEN with the contract: no lane edits this spec. It also holds
-- every lane's stub to its names, so a lane that renames a function another lane calls fails here, and
-- it runs Arena.check on whatever ArenaData.build() returns, today's stand-in and the real building
-- alike. The cases that need the fake engine (paintball on the framework's rig, with its own remotes
-- beside it) live in tests/isolated/paintball_contract.luau and are reported here one by one.
local Ballistics = require("@shared/Paintball/Ballistics")
local Config = require("@shared/Paintball/Config")
local Magazine = require("@shared/Paintball/Magazine")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Body = require("@shared/Minigames/Paintball/Body")
local Clock = require("@shared/Minigames/Paintball/Clock")
local Wire = require("@shared/Minigames/Paintball/Wire")
local Arena = require("@shared/Minigames/Paintball/Arena")
local ArenaData = require("@shared/Minigames/Paintball/ArenaData")
local Rules = require("@shared/Minigames/Paintball/Rules")
local Spec = require("@shared/Minigames/Paintball/Spec")
local Games = require("@shared/Minigames/Games")
local Minigame = require("@shared/Minigames/Minigame")
local Session = require("@shared/Minigames/Session")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local EconomyRules = require("@shared/Economy/EconomyRules")
local Tunables = require("@shared/Config/Tunables")
local Net = require("@shared/Net/Net")
local Schemas = require("@shared/Net/Schemas")
local BufferCodec = require("@shared/Util/BufferCodec")
local Log = require("@shared/Util/Log")
local Schema = require("@shared/Util/Schema")
local Human = require("@client/Controllers/Human")
local ClientGames = require("@client/Minigames/ClientGames")
local PaintballClient = require("@client/Minigames/Paintball/PaintballClient")
local ServerGames = require("@server/Minigames/ServerGames")
local Bots = require("@server/Minigames/Paintball/Bots")
local PaintballService = require("@server/Minigames/Paintball/PaintballService")
local PoseHistory = require("@server/Paintball/PoseHistory")
local Projectiles = require("@server/Paintball/Projectiles")
local Isolated = require("@tests/lib/Isolated")

local R = Contract.Rules

return function(t)
	t.test("PB-1: a ball travels at 90 studs/s and drops a little: 45 studs in half a second, about 1.2 low", function()
		t.eq(R.ballSpeed, 90)
		t.eq(R.ballDrop, 9.8)
		t.eq(R.ballTtl, 1.5)
		t.eq(R.ballRadius, 0.25)
		local x, y = Ballistics.position(0, 0, 0, R.ballSpeed, 0, 0, R.ballDrop, 0.5)
		t.near(x, 45, 1e-9)
		t.near(y, -1.225, 1e-9)
		-- the longest flat shot stays inside the arena: nothing is decided by the ttl
		t.truthy(R.ballSpeed * R.ballTtl >= 2 * Arena.HALF)
		t.eq(Tunables.tree.paintball.projectileSpeed.v, R.ballSpeed)
		t.eq(Tunables.tree.paintball.drop.v, R.ballDrop)
	end)

	t.test("PB-2: five shots a quarter second apart, reload 1.6 s, by itself on the fifth or on R", function()
		t.eq(R.magazine, 5)
		t.eq(R.fireInterval, 0.25)
		t.eq(R.reloadSecs, 1.6)
		t.eq(Tunables.tree.paintball.magazine.v, R.magazine)
		local mag = Magazine.new(R.magazine, R.fireInterval, R.reloadSecs)
		for i = 0, 4 do
			t.truthy(Magazine.fire(mag, i * R.fireInterval))
		end
		t.falsy(Magazine.fire(mag, 1.5), "no firing while reloading")
		t.truthy(Magazine.fire(mag, 1.0 + R.reloadSecs), "full again 1.6 s after the fifth ball")
		t.truthy(Magazine.reload(mag, 3.0), "R when not full")
	end)

	t.test("PB-6, PB-7, PB-12, PB-14: team sizes, the match clock, respawn, protection, the pass", function()
		t.eq(R.teamMin, 4)
		t.eq(R.teamMax, 8)
		t.eq(R.slots, 2 * R.teamMax)
		t.deepEq(Tunables.tree.paintball.teamSize.v, { R.teamMin, R.teamMax })
		t.eq(R.matchSecs, 480)
		t.eq(Tunables.tree.paintball.matchSecs.v, R.matchSecs)
		t.eq(R.briefingSecs, 10)
		t.truthy(
			R.endCardSecs >= 10 and R.endCardSpare > 0,
			"an end card long enough to read, and never cut by a reset"
		)
		t.truthy(R.respawnSecs >= 3 and R.respawnSecs <= 5, "tagged out for 3 to 5 s")
		t.eq(R.protectSecs, 2)
		t.eq(R.friendlyFire, false)
		t.eq(R.splatPool, 400)
		t.eq(R.passCents, 20)
		t.eq(R.passDays, 5)
		t.eq(EconomyRules.price("paintball_pass"), R.passCents)
		t.eq(Tunables.tree.economy.paintballPassCents.v, R.passCents)
		t.eq(Tunables.tree.economy.paintballPassDays.v, R.passDays)
		t.eq(Contract.passShort(20, 7), "You need 20c; you have 7c")
		t.deepEq(Contract.PHASES, { "briefing", "live", "ended" })
		t.eq(#Contract.TEAMS, 2)
		for _, team in Contract.TEAMS do
			-- decision D4: bright paint that is not blood red
			t.falsy(team.color[1] > 200 and team.color[2] < 80 and team.color[3] < 80, team.name)
		end
		t.eq(Contract.textFor("infected"), "See a doctor first.")
		t.eq(Contract.textFor("no such code"), "Not now.")
		-- odd seats one side, even seats the other; sixteen bots to draw on, no two of a name
		t.eq(Contract.teamOf(1), 1)
		t.eq(Contract.teamOf(2), 2)
		t.eq(Contract.teamOf(15), 1)
		t.eq(#Contract.BOTS, R.slots)
		local names: { [string]: boolean } = {}
		for _, bot in Contract.BOTS do
			t.falsy(names[bot.name], bot.name)
			names[bot.name] = true
			t.truthy(bot.skill >= 0 and bot.skill <= 1)
		end
	end)

	t.test("PB-9: the body: heights, the eye, the hit shape, crouch at 0.6, speeds", function()
		t.near(Body.STAND_TOP, 5.6, 1e-9)
		t.near(Body.CROUCH_TOP, 3.36, 1e-9)
		t.eq(Body.STAND_EYE, 4.5)
		t.near(Body.CROUCH_EYE, 2.7, 1e-9)
		t.eq(Tunables.tree.human.crouchHeightMult.v, Body.CROUCH_MULT)
		local low, high, radius = Body.capsule(0)
		t.deepEq({ low, high, radius }, { Config.body.low, Config.body.high, Config.body.radius })
		low, high, radius = Body.capsule(1)
		t.near(high + radius, Body.CROUCH_TOP, 1e-9)
		t.truthy(high > low, "a crouched capsule still has an axis")
		t.near(Body.eye(0.5), (Body.STAND_EYE + Body.CROUCH_EYE) / 2, 1e-9)
		-- speeds: the town's walk, the plan's sprint multiplier, half speed crouched
		t.eq(Body.WALK, Human.WALK)
		t.near(Body.SPRINT, Body.WALK * Tunables.tree.paintball.sprintMult.v, 1e-9)
		t.eq(Body.CROUCH_SPEED, Body.WALK / 2)
		t.eq(Body.speed(0, false), Body.WALK)
		t.eq(Body.speed(0, true), Body.SPRINT)
		t.eq(Body.speed(1, true), Body.CROUCH_SPEED)
		t.truthy(Body.isSprinting(Body.SPRINT) and not Body.isSprinting(Body.WALK))
		-- the pace the client hands the framework's ctx.pace: Controllers/Human turns it back into these speeds
		t.eq(Body.pace(0, 0), 1)
		t.near(Body.pace(0, 1), Tunables.tree.paintball.sprintMult.v, 1e-9)
		t.eq(Body.pace(1, 1), 0.5)
		t.truthy(Body.pace(0, 1) <= Human.MAX_SCALE)
		t.near(Human.speed(false, Body.pace(0, 1), true), Body.SPRINT, 1e-9)
		t.near(Human.speed(true, Body.pace(1, 0), true), Body.CROUCH_SPEED, 1e-9)
		t.near(Human.speed(false, Body.pace(0.5, 1), true), Body.speed(0.5, false), 1e-9)
		-- the crouch eases over CROUCH_SECS, the same on both sides whatever the step
		local c = 0
		for _ = 1, 4 do
			c = Body.crouchStep(c, true, Body.CROUCH_SECS / 4)
		end
		t.near(c, 1, 1e-9)
		t.eq(Body.crouchStep(0.05, false, 1), 0)
		-- look angles: yaw 0 looks along -z, positive pitch up; the two functions are inverses
		local dx, dy, dz = Body.look(0, 0)
		t.near(dx, 0, 1e-12)
		t.near(dy, 0, 1e-12)
		t.near(dz, -1, 1e-12)
		local yaw, pitch = Body.yawPitch(Body.look(1.1, -0.4))
		t.near(yaw, 1.1, 1e-9)
		t.near(pitch, -0.4, 1e-9)
		t.eq(Body.PARTS[Body.partAt(0.5, 0)], "legs")
		t.eq(Body.PARTS[Body.partAt(3.5, 0)], "torso")
		t.eq(Body.PARTS[Body.partAt(5.2, 0)], "head")
	end)

	t.test("PB-5, PB-9: a rail hides a crouched body and a standing eye sees over it; nobody jumps it", function()
		t.truthy(Body.CROUCH_TOP < Arena.RAIL_HEIGHT, "a crouched body is wholly behind a rail")
		t.truthy(Body.CROUCH_EYE + R.ballRadius < Arena.RAIL_HEIGHT, "and cannot shoot over it")
		t.truthy(Body.STAND_EYE - R.ballRadius > Arena.RAIL_HEIGHT, "a standing eye shoots over it")
		t.truthy(Body.JUMP_HEIGHT < Arena.RAIL_HEIGHT - Arena.STEP_UP, "a jump does not clear a rail")
		t.truthy(Body.JUMP_HEIGHT + Contract.TRUST.jumpSlack < Arena.RAIL_HEIGHT, "nor does the server think it might")
		t.truthy(Arena.HEADROOM > Body.STAND_TOP, "crouching is never needed to fit")
		t.truthy(Arena.CHEST < Arena.RAIL_HEIGHT, "a rail stops a walking body")
		-- with the ball test itself: a rail on the atrium's edge of the stand-in arena
		local arena = ArenaData.build()
		local y = Arena.FLOOR_HEIGHT
		local x0, x1 = Arena.ATRIUM + 6, -Arena.ATRIUM - 6
		t.truthy(arena.sweep(x0, y + Body.CROUCH_EYE, 0, x1, y + Body.CROUCH_EYE, 0) ~= nil, "crouched: blocked")
		t.eq((arena.sweep(x0, y + Body.STAND_EYE, 0, x1, y + Body.STAND_EYE, 0)), nil)
	end)

	t.test("time: the rates, and the history is long enough for the furthest rewind", function()
		t.eq(Clock.TICK_HZ, 60)
		t.eq(Clock.SNAP_HZ, 20)
		t.eq(Clock.SEND_HZ, 20)
		t.near(Clock.INTERP_SECS, 2 / Clock.SNAP_HZ, 1e-12)
		t.eq(Clock.HISTORY_SECS, 1.0)
		t.eq(Tunables.tree.paintball.lagHistorySecs.v, Clock.HISTORY_SECS)
		t.eq(Clock.MAX_REWIND, Config.maxRewindSecs)
		-- a ball flown forward by MAX_LATE and rewound by MAX_REWIND still reads inside the history
		t.truthy(Clock.MAX_LATE + Clock.MAX_REWIND + 1 / Clock.SNAP_HZ < Clock.HISTORY_SECS)
		-- 150 ms of round trip: half of it down, plus the interpolation delay, is well inside the clamp
		t.truthy(0.075 + Clock.INTERP_SECS + Clock.REWIND_TOLERANCE < Clock.MAX_REWIND)
		t.truthy(Clock.STALE_SECS < Clock.DROP_SECS)
	end)

	t.test("time: the view time trails the newest snapshot by the interpolation delay and never runs back", function()
		local view = Clock.newView()
		local down = 0.06
		local last = -math.huge
		for i = 0, 40 do
			local snapT = i / Clock.SNAP_HZ
			local now = snapT + down
			Clock.observe(view, snapT, now)
			local vt = Clock.viewTime(view, now)
			t.truthy(vt >= last)
			last = vt
			t.near(vt, snapT - Clock.INTERP_SECS, 1e-9)
		end
		-- a snapshot that arrives very late pushes the lag up at once; the view holds, it does not run back
		Clock.observe(view, 1.0, 2.06)
		local lag = view.lag :: number
		t.truthy(lag > 0.5, "the lag rises quickly")
		t.eq(Clock.viewTime(view, 2.06), last)
		-- and comes down slowly once packets are on time again
		Clock.observe(view, 2.05, 2.05 + down)
		t.truthy((view.lag :: number) < lag and (view.lag :: number) > lag * 0.9)
	end)

	t.test("time: a shot's stamps are clamped: fire time, lateness, rewind", function()
		-- an honest shot at 150 ms round trip: 75 ms up, 75 ms down + interpolation
		local now = 100
		local ft = now - 0.075
		local vt = ft - (0.075 + Clock.INTERP_SECS)
		local f, late, rewind, clamped = Clock.stamp(now, vt, ft, nil, 0.075 + Clock.INTERP_SECS)
		t.near(f, ft, 1e-9)
		t.near(late, 0.075, 1e-9)
		t.near(rewind, 0.175, 1e-9)
		t.falsy(clamped)
		-- a fire time from the future or the distant past
		t.eq((Clock.stamp(now, now - 0.2, now + 5, nil, nil)), now)
		t.eq((Clock.stamp(now, now - 0.2, now - 5, nil, nil)), now - Clock.MAX_LATE)
		-- never before the shooter's last shot
		t.eq((Clock.stamp(now, now - 0.2, now - 0.2, now - 0.1, nil)), now - 0.1)
		-- a view time claimed far in the past is held at MAX_REWIND, and at the estimate's edge
		local _, _, r1, c1 = Clock.stamp(now, now - 3, now, nil, nil)
		t.eq(r1, Clock.MAX_REWIND)
		t.truthy(c1)
		local _, _, r2 = Clock.stamp(now, now - 3, now, nil, 0.175)
		t.near(r2, 0.175 + Clock.REWIND_TOLERANCE, 1e-9)
		local _, _, r3 = Clock.stamp(now, now + 1, now, nil, 0.175)
		t.near(r3, 0.175 - Clock.REWIND_TOLERANCE, 1e-9)
		t.eq(select(3, Clock.stamp(now, now + 1, now, nil, nil)), 0)
	end)

	t.test("the keystone: what a client draws at its view time is what the server rewinds to, exactly", function()
		-- a body running and strafing; the server snapshots it SNAP_HZ times a second, pushing the
		-- quantised pose into the history; a client 60 ms away draws it at its view time
		local function truth(time: number): (number, number, number)
			return -30 + Body.SPRINT * time, Arena.FLOOR_HEIGHT, 12 + 6 * math.sin(time * 3)
		end
		local history = PoseHistory.new(Clock.HISTORY_SECS, Clock.SNAP_HZ)
		local down = 0.06
		local view = Clock.newView()
		local inbox: { { at: number, b: buffer } } = {}
		local snaps: { { t: number, body: Wire.SnapBody } } = {}
		local nextSnap, seq, checked = 0, 0, 0
		for frame = 0, 150 do
			local now = frame / Clock.TICK_HZ
			if now >= nextSnap - 1e-9 then
				local x, y, z = truth(now)
				local qx, qy, qz = Wire.quantPose(x, y, z, 0)
				PoseHistory.push(history, now, qx, qy, qz)
				seq += 1
				local body = { id = 1, x = x, y = y, z = z, yaw = 0, pitch = 0, crouch = 0, bits = 0 }
				table.insert(inbox, { at = now + down, b = Wire.encodeSnap(now, seq, 1, { body }) })
				nextSnap += 1 / Clock.SNAP_HZ
			end
			-- the client, at the same instant on the shared clock
			while inbox[1] and inbox[1].at <= now + 1e-9 do
				local time, _, _, bodies = Wire.decodeSnap((table.remove(inbox, 1) :: any).b)
				Clock.observe(view, time :: number, now)
				table.insert(snaps, { t = time :: number, body = bodies[1] })
			end
			if #snaps >= 3 then
				local vt = Clock.viewTime(view, now)
				local older, newer = snaps[1], snaps[2]
				for i = 2, #snaps do
					if snaps[i].t >= vt then
						older, newer = snaps[i - 1], snaps[i]
						break
					end
					older, newer = snaps[i], snaps[i]
				end
				local cx, cy, cz = Wire.between(older.body, older.t, newer.body, newer.t, vt)
				local sx, sy, sz = PoseHistory.sample(history, vt)
				t.deepEq({ cx, cy, cz }, { sx, sy, sz }, `frame {frame}`)
				-- and the view is the past: about the delay plus the interpolation behind the truth
				local tx = truth(vt)
				t.near(cx, tx, 0.05)
				t.near(now - vt, down + Clock.INTERP_SECS, 0.03)
				checked += 1
			end
		end
		t.truthy(checked > 100)
		-- so a ball stamped the contract's way hits what was under the crosshair, and an unrewound one misses
		local target = { id = 1, team = 2, history = history }
		local now = 150 / Clock.TICK_HZ
		local up = 0.04
		local ft = now - up
		local vt = ft - (down + Clock.INTERP_SECS)
		local f, late, rewind = Clock.stamp(now, vt, ft, nil, down + Clock.INTERP_SECS)
		t.near(late, up, 1e-9)
		t.near(rewind, down + Clock.INTERP_SECS, 1e-9)
		-- aimed, on the shooter's screen, at where the drawn body will be when a flat ball gets there
		local dist = 30
		local tof = dist / R.ballSpeed
		local ax, ay, az = PoseHistory.sample(history, vt)
		local lead = Body.SPRINT * tof
		local vx, vy, vz = Ballistics.aim(ax + lead, ay + 3, az - dist, ax + lead, ay + 3, az, R.ballSpeed, R.ballDrop)
		local sim = Projectiles.new({}, nil)
		local rewound = Projectiles.fire(sim, 2, 1, ax + lead, ay + 3, az - dist, vx, vy, vz, rewind)
		local naive = Projectiles.fire(sim, 2, 1, ax + lead, ay + 3, az - dist, vx, vy, vz, 0)
		for k = 1, 40 do
			-- the server keeps snapshotting the runner while the balls fly from the clamped fire time
			local time = f + k / Clock.TICK_HZ
			if time >= nextSnap - 1e-9 then
				local x, y, z = truth(nextSnap)
				local qx, qy, qz = Wire.quantPose(x, y, z, 0)
				PoseHistory.push(history, nextSnap, qx, qy, qz)
				nextSnap += 1 / Clock.SNAP_HZ
			end
			Projectiles.step(sim, time, 1 / Clock.TICK_HZ, { target })
		end
		t.eq(rewound.hitBody, 1, "the rewound ball tags the body the shooter led")
		t.eq(naive.hitBody, 0, "without the rewind the same ball passes behind where the body now is")
	end)

	t.test(
		"wire: five remotes of paintball's own, in Net/Schemas with direction, reliability, rate and size",
		function()
			local expect = {
				["Paintball.Move"] = { "c2s", false, 27 },
				["Paintball.Fire"] = { "c2s", true, 42 },
				["Paintball.Snap"] = { "s2c", false, 0 },
				["Paintball.Shot"] = { "s2c", false, 35 },
				Splat = { "s2c", true, 22 },
			}
			local n = 0
			for name, def in Wire.REMOTES do
				n += 1
				local e = expect[name]
				t.truthy(e ~= nil, name)
				t.eq(Schemas.REMOTES[name], def, name)
				t.eq(def.dir, e[1], name)
				t.eq(def.reliable, e[2], name)
				t.eq(if def.layout then def.layout.size else 0, e[3], name)
			end
			t.eq(n, 5)
			-- nothing else of paintball's is a remote: every table message rides the framework's Minigame.State
			for name in Schemas.REMOTES do
				if string.sub(name, 1, 10) == "Paintball." or name == "Splat" then
					t.truthy(Wire.REMOTES[name] ~= nil, `{name} is in Net/Schemas but not in the contract`)
				end
			end
			t.eq(Wire.SnapHead.size, 12)
			t.eq(Wire.SnapBody.size, 13)
			-- an unreliable message stays under the size the engine delivers
			t.truthy(Wire.SnapHead.size + R.slots * Wire.SnapBody.size < 900)
			t.truthy(Wire.SHOTS_PER_MESSAGE * Wire.Shot.size < 900)
			-- the client's send rate fits its bucket with room for jitter; so does the fastest honest fire
			local move = Wire.REMOTES["Paintball.Move"]
			t.truthy(move.rate :: number >= Clock.SEND_HZ * 1.25)
			t.truthy(Wire.REMOTES["Paintball.Fire"].rate :: number >= 1.5 / R.fireInterval)
			-- positions fit the quantised range
			t.truthy(Wire.XZ > Arena.HALF + 1 and Wire.Y_LO < -1 and Wire.Y_HI > Arena.HEIGHT + Body.STAND_TOP)
		end
	)

	t.test(
		"wire: Net takes a Move and a Fire and drops what is malformed; reload is a verb of Minigame.Input",
		function()
			Log.capture()
			local net = Net.new({
				send = function() end,
				players = function()
					return {}
				end,
			}, {
				clock = function()
					return 0
				end,
			})
			local got: { [string]: any } = {}
			for _, name in { "Paintball.Move", "Paintball.Fire" } do
				net:on(name, function(_player, payload)
					got[name] = payload
				end)
			end
			local p = { UserId = 7 }
			local bits = Wire.BIT.crouch + Wire.BIT.air
			local move = { t = 12.5, seq = 9, x = 1.5, y = 14, z = -20.25, yaw = 1, pitch = -0.5, bits = bits }
			t.truthy(net:receive(p, "Paintball.Move", BufferCodec.encode(Wire.Move, move), 0))
			t.eq(got["Paintball.Move"].t, 12.5)
			t.eq(got["Paintball.Move"].z, -20.25)
			t.near(got["Paintball.Move"].yaw, 1, 1e-4)
			t.near(got["Paintball.Move"].pitch, -0.5, 1e-4)
			t.truthy(Wire.has(got["Paintball.Move"].bits, Wire.BIT.crouch))
			t.falsy(Wire.has(got["Paintball.Move"].bits, Wire.BIT.sprint))
			t.deepEq({ net:receive(p, "Paintball.Move", buffer.create(26), 0) }, { false, "bad buffer" })
			t.deepEq({ net:receive(p, "Paintball.Move", { x = 1 }, 0) }, { false, "bad buffer" })
			local fire = { shot = 3, vt = 99.8, ft = 99.95, ox = 1, oy = 4.5, oz = 2, dx = 0, dy = 0, dz = -1 }
			t.truthy(net:receive(p, "Paintball.Fire", BufferCodec.encode(Wire.Fire, fire), 0))
			t.eq(got["Paintball.Fire"].vt, 99.8)
			t.eq(got["Paintball.Fire"].shot, 3)
			fire.dx = 0 / 0
			t.deepEq(
				{ net:receive(p, "Paintball.Fire", BufferCodec.encode(Wire.Fire, fire), 0) },
				{ false, "non-finite" }
			)
			-- the old table messages are gone from the wire
			t.deepEq({ net:receive(p, "Paintball.Cmd", { verb = "join" }, 0) }, { false, "unknown remote" })
			t.eq(Schemas.REMOTES["Paintball.State"], nil)
			-- R goes the framework's way, with its stamp
			t.deepEq(Wire.VERBS, { "reload" })
			t.deepEq(Spec.verbs, Wire.VERBS)
			local input = Schemas.REMOTES["Minigame.Input"].payload :: any
			t.truthy(Schema.check(input, { gameId = Contract.STATION, seat = 3, verb = "reload", args = { 1000.25 } }))
			t.truthy(Schema.check(input, { gameId = Contract.STATION, seat = 3, verb = "leave", args = {} }))
			t.falsy(Schema.check(input, { gameId = Contract.STATION, seat = 3, verb = "fire", args = {} }))
		end
	)

	t.test("wire: a snapshot round-trips, and quantPose is what comes back", function()
		local bodies = {}
		for id = 1, R.slots do
			bodies[id] = {
				id = id,
				x = -59.37 + id * 7.111,
				y = (id % 5) * Arena.FLOOR_HEIGHT + 0.123,
				z = 58.2 - id * 6.5,
				yaw = -3 + id * 0.37,
				pitch = -1.2 + id * 0.15,
				crouch = (id % 4) / 3,
				bits = id * 3 % 64,
			}
		end
		local b = Wire.encodeSnap(1234.5678, 70000, 258, bodies)
		t.eq(buffer.len(b), Wire.SnapHead.size + R.slots * Wire.SnapBody.size)
		local time, seq, match, back = Wire.decodeSnap(b)
		t.eq(time, 1234.5678)
		t.eq(seq, 70000 % 65536)
		t.eq(match, 258 % 256)
		t.eq(#back, R.slots)
		for id, body in bodies do
			local got = back[id]
			local qx, qy, qz, qc = Wire.quantPose(body.x, body.y, body.z, body.crouch)
			t.deepEq({ got.x, got.y, got.z, got.crouch }, { qx, qy, qz, qc }, `body {id}`)
			t.near(got.x, body.x, 0.002)
			t.near(got.y, body.y, 0.002)
			t.near(got.z, body.z, 0.002)
			t.near(got.crouch, body.crouch, 0.003)
			t.near(got.yaw, body.yaw, 1e-4)
			t.near(got.pitch, body.pitch, 1e-4)
			t.eq(got.id, id)
			t.eq(got.bits, body.bits)
		end
		t.eq((Wire.decodeSnap(buffer.create(5))), nil)
		t.eq((Wire.decodeSnap(buffer.create(Wire.SnapHead.size + 3))), nil)
		t.eq((Wire.decodeSnap("no")), nil)
	end)

	t.test("wire: shots and splats pack and unpack; faces and body offsets invert", function()
		local shots = {
			{ ball = 65535, id = 16, t = 77.25, ox = 1, oy = 2, oz = 3, vx = 90, vy = 0, vz = 0 },
			{ ball = 1, id = 2, t = 77.5, ox = -4, oy = 18.5, oz = 6, vx = 0, vy = 1.5, vz = -89.5 },
		}
		t.deepEq(Wire.unpack(Wire.Shot, Wire.pack(Wire.Shot, shots)), shots)
		local splats =
			{ { seq = 4000000000, ball = 9, by = 3, body = 0, team = 1, face = 5, x = 1.5, y = 2.5, z = -60 } }
		t.deepEq(Wire.unpack(Wire.Splat, Wire.pack(Wire.Splat, splats)), splats)
		t.eq(#Wire.unpack(Wire.Splat, buffer.create(Wire.Splat.size + 1)), 0)
		for face = 1, 6 do
			t.eq(Wire.faceOf(Wire.normalOf(face)), face)
		end
		t.eq(Wire.faceOf(0, 0, 0), Wire.FACE.none)
		local lx, ly, lz = Wire.toBody(3, 5, -2, 1, 1, 1, 0.8)
		local px, py, pz = Wire.fromBody(lx, ly, lz, 1, 1, 1, 0.8)
		t.near(px, 3, 1e-9)
		t.near(py, 5, 1e-9)
		t.near(pz, -2, 1e-9)
		-- in the body's own frame "ahead" is -z, the way Body.look(yaw, 0) points
		local ax, _, az = Body.look(0.8, 0)
		local fx, _, fz = Wire.toBody(1 + ax, 1, 1 + az, 1, 1, 1, 0.8)
		t.near(fx, 0, 1e-9)
		t.near(fz, -1, 1e-9)
	end)

	t.test("wire: every paintball kind on Minigame.State has a schema; good ones pass, bad ones do not", function()
		local good: { { [string]: any } } = {
			{
				kind = "paintball_watch",
				match = 2,
				slots = {
					{ id = 1, team = 1, name = "Ada", bot = false },
					{ id = 2, team = 2, name = "Rusty (computer)", bot = true },
				},
				now = 5,
				station = Contract.STATION,
			},
			{ kind = "paintball_unwatch", station = Contract.STATION },
			{ kind = "paintball_tag", by = 2, id = 1, ball = 17, scores = { 0, 1 }, at = 9, x = 0, y = 1, z = 2 },
			{ kind = "paintball_respawn", id = 1, x = 0, y = 0, z = 0, yaw = 0, at = 11 },
			{ kind = "paintball_reload", id = 1, at = 12 },
			{ kind = "paintball_say", id = 3, line = "floor", n = 3 },
			{ kind = "paintball_ack", shot = 4, ok = true, ball = 17, rounds = 4 },
			{ kind = "paintball_ack", shot = 5, ok = false, why = "sprint", rounds = 4, reloadAt = 12 },
			{ kind = "paintball_correct", x = 0, y = 0, z = 0, yaw = 0, why = "fast", station = Contract.STATION },
		}
		local seen: { [string]: boolean } = {}
		for _, msg in good do
			local ok, err = Wire.checkMessage(msg)
			t.truthy(ok, `{msg.kind}: {err}`)
			seen[msg.kind] = true
		end
		local kinds = 0
		for k in Wire.KINDS do
			kinds += 1
			t.truthy(seen[k], `no example of '{k}'`)
			t.eq(string.sub(k, 1, 10), "paintball_", "a game's kinds carry its name")
		end
		t.eq(kinds, 8)
		t.falsy((Wire.checkMessage({ kind = "paintball_tag", by = 2, id = 1 })))
		t.falsy((Wire.checkMessage({
			kind = "paintball_tag",
			by = 2,
			id = 99,
			ball = 1,
			scores = { 0, 1 },
			at = 9,
			x = 0,
			y = 1,
			z = 2,
		})))
		t.falsy((Wire.checkMessage({ kind = "paintball_correct", x = 0, y = 0, z = 0, yaw = 0, why = "because" })))
		t.falsy((Wire.checkMessage({ kind = "paintball_unwatch", extra = 1 })))
		t.falsy((Wire.checkMessage({ kind = "state" })), "the framework's kinds are not paintball's")
		t.falsy((Wire.checkMessage("paintball_watch")))
		-- the two that reach a player who is not seated are exactly the client half's `kinds`
		t.deepEq(Wire.EVERYONE_KINDS, { "paintball_watch", "paintball_unwatch" })
		local client = ClientGames.get(Contract.GAME) :: any
		t.deepEq(client.kinds, Wire.EVERYONE_KINDS)
		for _, kind in Wire.EVERYONE_KINDS do
			t.eq((ClientGames.ownerOf(kind) :: any).game, Contract.GAME)
		end
	end)

	t.test("wire: at 8 v 8 a player costs under 8 kB/s down and 1.5 kB/s up", function()
		local b = Wire.budget(R.slots)
		t.eq(b.snap, 220)
		t.truthy(b.down < 8000, `down {b.down}`)
		t.truthy(b.up < 1500, `up {b.up}`)
		t.truthy(Wire.budget(2 * R.teamMin).down < b.down)
	end)

	t.test("arena frame: a rigid frame at the arena_origin anchor; the pass desk is where the data puts it", function()
		local place = Arena.PLACE
		local expansion = require("../../generated/Expansion") :: any
		local venue
		for _, v in expansion.venues do
			if v.id == "f3_tv_station" then
				venue = v
			end
		end
		t.truthy(venue ~= nil, "f3_tv_station is in generated/Expansion")
		local anchors: { [string]: any } = {}
		for _, a in venue.anchors do
			anchors[a.id] = a
		end
		local origin = anchors.arena_origin
		t.deepEq({ place.x, place.y, place.z }, origin.world)
		t.eq(place.yaw, venue.yaw)
		local desk = anchors.pass_desk
		local wx, wy, wz = Arena.toWorld(place, Arena.DESK.x, Arena.DESK.y, Arena.DESK.z)
		t.deepEq({ wx, wy, wz }, desk.world)
		t.truthy(Arena.DESK.z > Arena.HALF, "the lobby annex is outside the arena volume, on +z")
		t.truthy(Arena.GATE.z > Arena.HALF and Arena.GATE.z < Arena.DESK.z, "the arena door is in the lobby too")
		-- the arena's place comes from the site's own, as every side holds it
		t.deepEq(origin.at, { Arena.ORIGIN.x, Arena.ORIGIN.y, Arena.ORIGIN.d })
		local venuePlace = { x = venue.place.x, z = venue.place.z, floorY = venue.place.floorY, yaw = venue.place.yaw }
		local derived = Arena.placeOf(venuePlace)
		t.deepEq({ derived.x, derived.y, derived.z, derived.yaw }, { place.x, place.y, place.z, place.yaw })
		local X, Y, D = Arena.toSite(Arena.DESK.x, Arena.DESK.y, Arena.DESK.z)
		t.deepEq({ X, Y, D }, desk.at)
		t.deepEq({ Arena.ofSite(X, Y, D) }, { Arena.DESK.x, Arena.DESK.y, Arena.DESK.z })
		t.truthy(Arena.inVolume(0, 1, 0) and Arena.inVolume(-60, 70, 60))
		t.falsy(Arena.inVolume(Arena.GATE.x, 1, Arena.GATE.z), "the lobby is not in the volume")
		t.truthy(Arena.inVolume(Arena.DESK.x, 1, Arena.DESK.z, Arena.AUDIENCE_MARGIN), "but it is in the audience")
		t.falsy(Arena.inVolume(0, 1, Arena.HALF + Arena.AUDIENCE_MARGIN + 1, Arena.AUDIENCE_MARGIN))
		-- fromSite agrees with the AlleyLayout frame the venue data is written in, at any yaw
		local site = { x = 300, z = -40, floorY = 7, yaw = 0.7 }
		local p = Arena.fromSite(site, origin.at[1], origin.at[2], origin.at[3])
		local sx, sy, sz = AlleyLayout.toWorld(site, origin.at[1], origin.at[2], origin.at[3])
		t.near(p.x, sx, 1e-9)
		t.near(p.y, sy, 1e-9)
		t.near(p.z, sz, 1e-9)
		-- arena x = site X, arena z = 15 - site D
		local ax, ay, az = Arena.toLocal(p, AlleyLayout.toWorld(site, -20, 3, -62))
		t.near(ax, -20, 1e-9)
		t.near(ay, 3, 1e-9)
		t.near(az, 15 - -62, 1e-9)
		-- toWorld and toLocal invert; directions turn without moving; yaw adds
		local x, y, z = Arena.toLocal(p, Arena.toWorld(p, 12, 28, -33))
		t.near(x, 12, 1e-9)
		t.near(y, 28, 1e-9)
		t.near(z, -33, 1e-9)
		local dx, dy, dz = Arena.dirToLocal(p, Arena.dirToWorld(p, 0.6, 0, -0.8))
		t.near(dx, 0.6, 1e-9)
		t.near(dy, 0, 1e-9)
		t.near(dz, -0.8, 1e-9)
		-- a body's look in the world is its look in the arena, turned: yawToWorld is consistent with dirToWorld
		local lx, _, lz = Arena.dirToWorld(p, Body.look(0.3, 0))
		local wyaw = Body.yawPitch(lx, 0, lz)
		t.near(wyaw, Arena.yawToWorld(p, 0.3), 1e-9)
		t.near(Arena.yawToLocal(p, Arena.yawToWorld(p, 0.3)), 0.3, 1e-9)
	end)

	t.test("arena: ArenaData.build() passes Arena.check and has the building's bones (PB-5)", function()
		local arena = ArenaData.build()
		local ok, problems = Arena.check(arena, R.teamMax)
		t.truthy(ok, table.concat(problems, "; "))
		t.eq(arena.floors, 5)
		t.eq(arena.floorHeight, 14)
		t.eq(arena.half, 60)
		t.eq(arena.height, arena.floors * arena.floorHeight)
		t.eq(Arena.FLOORS * Arena.FLOOR_HEIGHT, Arena.HEIGHT)
		-- every floor is a floor; the atrium is open from the ground to the roof
		for f = 0, arena.floors - 1 do
			t.eq(arena.ground(40, f * 14 + 0.5, 40), f * 14, `floor {f}`)
		end
		t.eq((arena.sweep(0.5, 1, 0.5, 0.5, Arena.HEIGHT - 0.5, 0.5)), nil)
		t.truthy(arena.sweep(40, 1, 40, 40, 20, 40) ~= nil, "a floor is solid from below")
		-- a ball stops on the outer wall, with the wall's face and the box's index
		local s, nx, ny, nz, box = arena.sweep(0, 2, 0, 100, 2, 0)
		t.near(s :: number, 0.6, 1e-9)
		t.deepEq({ nx, ny, nz }, { -1, 0, 0 })
		t.eq(arena.kinds[box], Arena.KIND.wall)
		-- both teams' spawn points are apart, on the floor and clear; the lobby is outside
		t.truthy(#arena.spawns[1] >= R.teamMax and #arena.spawns[2] >= R.teamMax)
		for i, a in arena.spawns[1] do
			for j, b in arena.spawns[1] do
				if i ~= j then
					t.truthy((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2 >= (2 * Body.RADIUS) ^ 2, "spawn points do not overlap")
				end
			end
		end
		-- the same data every call
		local again = ArenaData.build()
		t.deepEq(again.boxes, arena.boxes)
		t.eq(#again.nodes, #arena.nodes)
	end)

	t.test("arena: the reference ball test and walking surface, and the checker catching a bad arena", function()
		local boxes = { 0, 0, 0, 10, 1, 10, 4, 1, 4, 6, 4, 6 }
		local s, nx, ny, nz, box = Arena.sweepBoxes(boxes, 5, 10, 5, 5, 0, 5)
		t.near(s :: number, 0.6, 1e-9)
		t.deepEq({ nx, ny, nz, box }, { 0, 1, 0, 2 })
		t.eq((Arena.sweepBoxes(boxes, 20, 10, 5, 20, 0, 5)), nil)
		local ramp: Arena.Ramp = { minX = 10, minZ = 0, maxX = 20, maxZ = 4, y0 = 1, y1 = 6, axis = "x", dir = 1 }
		t.eq(Arena.rampHeight(ramp, 15, 2), 3.5)
		t.eq(Arena.rampHeight(ramp, 15, 5), nil)
		ramp.dir = -1
		t.eq(Arena.rampHeight(ramp, 12, 2), 5)
		t.eq(Arena.groundAt(boxes, { ramp }, 1, 1, 1), 1)
		t.eq(Arena.groundAt(boxes, { ramp }, 5, 1, 5), 1, "the 3-stud block is too tall to step onto")
		t.eq(Arena.groundAt(boxes, { ramp }, 5, 4, 5), 4)
		t.eq(Arena.groundAt(boxes, { ramp }, 19, 1.5, 2), 1.5, "on the ramp")
		t.eq(Arena.groundAt(boxes, {}, 50, 1, 50), nil, "a void")
		-- stairs of the stand-in: the walking surface climbs a whole storey along a flight
		local arena = ArenaData.build()
		local r = arena.ramps[1]
		local zMid = (r.minZ + r.maxZ) / 2
		local lowX = if r.dir > 0 then r.minX else r.maxX
		local highX = if r.dir > 0 then r.maxX else r.minX
		t.near(arena.ground(lowX, r.y0, zMid) :: number, r.y0, 1e-9)
		t.near(arena.ground(highX, r.y1, zMid) :: number, r.y1, 1e-9)
		t.near(arena.ground((lowX + highX) / 2, (r.y0 + r.y1) / 2, zMid) :: number, (r.y0 + r.y1) / 2, 1e-9)
		t.eq(r.y1 - r.y0, Arena.FLOOR_HEIGHT)
		-- the checker
		local bad = ArenaData.build()
		bad.spawns[2] = { bad.spawns[2][1] }
		table.insert(bad.links, { a = 1, b = #bad.nodes + 5, cost = 1, kind = "walk" })
		bad.nodes[3].y += 2
		local ok, problems = Arena.check(bad, R.teamMax)
		t.falsy(ok)
		t.eq(#problems, 3)
	end)

	t.test(
		"the registry: paintball is a sound game of flow match, with the arena's station and the desk's prompt",
		function()
			local ok, err = Games.check(Spec)
			t.truthy(ok, tostring(err))
			t.truthy(Games.get(Contract.GAME) == Spec, "its line is in Shared/Minigames/Games")
			t.eq(Spec.soon, nil)
			t.eq(Spec.flow, "match")
			t.truthy(Spec.rules == Rules)
			t.truthy(Minigame.check(Rules))
			t.eq(Rules.def.game, Contract.GAME)
			t.eq(Rules.def.seats, R.slots)
			t.eq(Rules.def.lateJoin, true)
			t.eq(Rules.def.class, "arena")
			t.truthy(Rules.verbs.reload)
			t.eq(Rules.serverVerbs, nil, "the service calls the model directly: no server verb")
			local session = Spec.session :: Session.Opts
			t.eq(session.lobbySeconds, 0, "the first person in starts the match; the briefing is its lobby")
			t.eq(session.doneSeconds, R.endCardSecs + R.endCardSpare)
			t.eq(session.idleSeconds, nil)
			t.eq(Spec.fill, 2 * R.teamMin)
			t.truthy(Spec.computers == Contract.BOTS :: any)
			-- no site, no station; on the site, the door and the desk
			t.eq(#Spec.stations({}), 0)
			local site = { x = 2080, z = -890, floorY = 8.6, yaw = 0 }
			local list = Spec.stations({ [Contract.SITE] = site })
			t.eq(#list, 2)
			local door, desk = list[1], list[2]
			t.eq(door.id, Contract.STATION)
			t.eq(door.joins, nil)
			t.eq(desk.id, Contract.DESK)
			t.eq(desk.joins, Contract.STATION)
			for _, st in list do
				t.eq(st.game, Contract.GAME)
				t.eq(st.site, Contract.SITE)
			end
			-- the desk's prompt is at the pass_desk anchor of the venue, the door's at the lobby's inner wall
			t.deepEq({ desk.x, desk.d }, { -20, -62 })
			t.deepEq({ door.x, door.d }, { 0, -47 })
			t.truthy(door.d > -75 and door.d < -45, "inside the lobby annex (D -75..-45)")
			t.deepEq({ Arena.ofSite(door.x, door.y, door.d) }, { Arena.GATE.x, 3, Arena.GATE.z })
			-- both halves have their line, and a real module behind it
			t.truthy(ServerGames.get(Contract.GAME) ~= nil, "the server half is more than a name")
			local client = ClientGames.get(Contract.GAME) :: any
			t.isType(client.new, "function")
			t.isType(client.watch, "function")
			t.deepEq(
				client.keys,
				{ Q = "", ButtonB = "" },
				"Q and gamepad B are the game's: a deliberate Leave, a crouch"
			)
			t.deepEq(client.buttons("joined", nil), { { "leave", "Leave the match" } })
			t.eq(client.buttons("playing", {}), nil, "the seat owns the bar while playing")
			t.deepEq(
				client.buttons("done", {}),
				{ { "leave", "Leave the match" } },
				"no Play again: the next match starts itself"
			)
			for _, cue in { "fire", "fire_far", "splat", "tag", "tagged", "reload", "dry", "step" } do
				t.eq(client.sounds[`paintball.{cue}`], "", cue)
			end
		end
	)

	t.test(
		"the Session on the match model: a join starts it, a seat is a slot, late seats join, sync moves its clock",
		function()
			local s = Session.new(Rules, Spec.session)
			local ok, _, seat = Session.join(s, "ada", "Ada", 0)
			t.truthy(ok)
			t.eq(seat, 1)
			t.eq(s.phase, "playing", "no lobby to wait in")
			local state = (s.game :: Minigame.Game).state :: Rules.State
			t.eq(state.phase, "briefing")
			t.eq(state.endsAt, R.briefingSecs)
			t.eq(#state.slots, 1)
			-- a late seat (a bot filling a side, a friend) is a slot of the other team
			local ok2, _, seat2 = Session.join(s, { ai = true, name = "Rusty" }, "Rusty (computer)", 1)
			t.truthy(ok2)
			t.eq(seat2, 2)
			local slot = Rules.slot(state, 2) :: Rules.Slot
			t.truthy(slot.on)
			t.eq(slot.team, Contract.teamOf(2))
			t.eq(slot.mag.rounds, R.magazine)
			-- the view is the wire's MatchView: phase, clock, scores, a row a slot without gaps
			local view = Session.view(s, 1)
			t.eq(view.phase, "playing")
			t.eq(#view.seats, 2)
			local g = view.game
			t.eq(g.phase, "briefing")
			t.deepEq(g.scores, { 0, 0 })
			t.eq(#g.slots, 2)
			t.deepEq(g.slots[2], { id = 2, team = 2, on = true, tags = 0, outs = 0, shots = 0, hits = 0 })
			t.truthy(g.size >= R.teamMin and g.size <= R.teamMax)
			-- a seat left is a slot off; the same seat can be taken again
			Session.leave(s, "ada", 2)
			t.falsy((Rules.slot(state, 1) :: Rules.Slot).on)
			local ok3, _, seat3 = Session.join(s, "bea", "Bea", 3)
			t.truthy(ok3)
			t.eq(seat3, 1, "the vacated seat first: the sides stay as they were")
			t.truthy((Rules.slot(state, 1) :: Rules.Slot).on)
			-- the model's clock: it counts from nothing until the service tells it the shared clock
			Session.step(s, 4)
			local before = state.now
			t.truthy(before > 0 and before <= 4)
			local left = state.endsAt - state.now
			Rules.sync(state, 1000)
			t.eq(state.now, 1000)
			t.near(state.endsAt - state.now, left, 1e-9, "every time in the State moved with it")
			t.near(Rules.view(state).endsAt, 1000 + left, 1e-9)
			-- nothing fires, tags or ends on a clock nobody has run out
			t.eq(Rules.result(state), nil)
			t.deepEq(Rules.drain(state), {})
		end
	)

	t.test("stubs: every lane's module keeps the names the other lanes call", function()
		local function has(module: any, names: { string }, label: string)
			for _, name in names do
				t.isType(module[name], "function", `{label}.{name}`)
			end
		end
		has(Rules, {
			"init",
			"sync",
			"step",
			"join",
			"gone",
			"input",
			"result",
			"view",
			"drain",
			"slot",
			"canFire",
			"fire",
			"reload",
			"canBeHit",
			"tag",
			"bits",
			"card",
		}, "Rules")
		has(Bots, { "new", "sync", "place", "step" }, "Bots")
		has(ArenaData, { "build" }, "ArenaData")
		has(PaintballService, { "new", "port" }, "PaintballService")
		has(PaintballClient, { "watch", "new", "show", "link" }, "PaintballClient")
		t.eq(PaintballService.MONITOR, "Monitor")
		-- the service on a bare framework context (no site model, no net): inert, and every hook is there
		local sent = 0
		local ctx: any = {
			station = { id = Contract.STATION },
			place = { x = 2080, z = -890, floorY = 8.6, yaw = 0 },
			root = nil,
			opts = {},
			net = nil,
			send = function()
				sent += 1
			end,
		}
		local service = PaintballService.new(ctx)
		has(service, {
			"join",
			"joined",
			"input",
			"step",
			"event",
			"state",
			"inPlay",
			"screen",
			"sig",
			"prompt",
			"doneText",
			"debug",
			"onMove",
			"onFire",
			"watching",
			"stats",
		}, "Service")
		t.eq(service.hw, nil)
		t.eq(service.port, nil)
		t.deepEq(
			{ service.place.x, service.place.y, service.place.z },
			{ Arena.PLACE.x, Arena.PLACE.y, Arena.PLACE.z },
			"the arena's place from the site's"
		)
		service:step(1 / Clock.TICK_HZ)
		t.eq(sent, 0)
		-- the Port onto a Net: handlers in, buffers out
		local fired: { any } = {}
		local port = PaintballService.port({
			on = function(_self: any, name: string, fn: any)
				table.insert(fired, { "on", name, fn })
			end,
			fire = function(_self: any, player: any, name: string, payload: any)
				table.insert(fired, { "fire", player, name, payload })
			end,
		})
		port.on("Paintball.Move", function() end)
		port.fire("ada", "Splat", buffer.create(0))
		t.eq(fired[1][2], "Paintball.Move")
		t.deepEq({ fired[2][1], fired[2][2], fired[2][3] }, { "fire", "ada", "Splat" })
		-- the seat of a player, on a bare client context
		local seat = PaintballClient.new({ station = Contract.STATION, game = Contract.GAME } :: any)
		has(seat, { "onState", "onMessage", "onRefused", "input", "step", "stop" }, "Seat")
		t.eq(seat.mag.rounds, R.magazine)
		-- the match model and the bots line up: a fresh State steps through the bots without a word
		local state = Rules.init(1, 3)
		t.eq(state.phase, "briefing")
		t.deepEq(Bots.step(Bots.new(service.arena), state, {}, 0, 1 / Clock.TICK_HZ), {})
		t.deepEq({ Rules.canFire(state, 1, 0) }, { false, "phase" })
		-- the end card the framework draws from a finished view
		local endCard = (ClientGames.get(Contract.GAME) :: any).endCard
		t.eq(endCard({ seats = {}, result = nil }, 1), nil)
		local card: Contract.EndCard = {
			winner = 2,
			scores = { 3, 5 },
			rows = {
				{ id = 2, team = 2, tags = 4, outs = 1, shots = 20, hits = 4, accuracy = 0.2 },
				{ id = 1, team = 1, tags = 3, outs = 2, shots = 10, hits = 3, accuracy = 0.3 },
			},
			awards = { { title = "Most Paint Wasted", id = 2 } },
		}
		local result: Contract.Result =
			{ done = true, scores = { 3, 4 }, winners = { 2 }, text = "Teal wins 5 - 3", card = card }
		local sum = endCard({
			seats = { { name = "Ada", gone = false }, { name = "Rusty (computer)", gone = false } },
			result = result,
		}, 1)
		t.eq(sum.line, "Teal wins 5 - 3")
		t.eq(#sum.rows, 2)
		t.eq(sum.rows[1].name, "Rusty (computer)")
		t.eq(sum.rows[1].place, 1)
		t.eq(sum.rows[1].side, "Teal")
		t.eq(sum.rows[2].place, 2)
		t.eq(sum.rows[2].accuracy, "30%")
		t.truthy(string.find(sum.foot, "%d", 1, true) ~= nil, "the foot counts down to the next match")
	end)

	-- paintball on the framework's rig, with its own remotes beside it (tests/lib/PaintballRig)
	Isolated.register(t, "tests/isolated/paintball_contract")
end
