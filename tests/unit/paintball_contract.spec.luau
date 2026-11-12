--!strict
-- The paintball contract (Shared/Paintball: Contract, Body, Clock, Wire, Arena) pinned against the
-- owner's bar (brief v2 §13, §14; checklist PB-1 to PB-15) and against itself. FROZEN with the
-- contract: no lane edits this spec. It also holds every lane's stub to its names, so a lane that
-- renames a function another lane calls fails here, and it runs Arena.check on whatever
-- ArenaData.build() returns, today's stand-in and the real building alike.
local Ballistics = require("@shared/Paintball/Ballistics")
local Config = require("@shared/Paintball/Config")
local Magazine = require("@shared/Paintball/Magazine")
local Contract = require("@shared/Paintball/Contract")
local Body = require("@shared/Paintball/Body")
local Clock = require("@shared/Paintball/Clock")
local Wire = require("@shared/Paintball/Wire")
local Arena = require("@shared/Paintball/Arena")
local ArenaData = require("@shared/Paintball/ArenaData")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local EconomyRules = require("@shared/Economy/EconomyRules")
local Tunables = require("@shared/Config/Tunables")
local Net = require("@shared/Net/Net")
local Schemas = require("@shared/Net/Schemas")
local BufferCodec = require("@shared/Util/BufferCodec")
local Log = require("@shared/Util/Log")
local Human = require("@client/Controllers/Human")
local Match = require("@server/Paintball/Match")
local PoseHistory = require("@server/Paintball/PoseHistory")
local Projectiles = require("@server/Paintball/Projectiles")
local Bots = require("@server/Paintball/Bots")
local PaintballService = require("@server/Paintball/PaintballService")
local PaintballClient = require("@client/Paintball/PaintballClient")

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
		t.deepEq(Contract.PHASES, { "idle", "briefing", "live", "ended" })
		t.eq(#Contract.TEAMS, 2)
		for _, team in Contract.TEAMS do
			-- decision D4: bright paint that is not blood red
			t.falsy(team.color[1] > 200 and team.color[2] < 80 and team.color[3] < 80, team.name)
		end
		t.eq(Contract.textFor("infected"), "See a doctor first.")
		t.eq(Contract.textFor("no such code"), "Not now.")
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
				table.insert(inbox, { at = now + down, b = Wire.encodeSnap(now, seq, { body }) })
				nextSnap += 1 / Clock.SNAP_HZ
			end
			-- the client, at the same instant on the shared clock
			while inbox[1] and inbox[1].at <= now + 1e-9 do
				local time, _, bodies = Wire.decodeSnap((table.remove(inbox, 1) :: any).b)
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

	t.test("wire: the remotes are in Net/Schemas with their direction, reliability, rate and size", function()
		local expect = {
			["Paintball.Move"] = { "c2s", false, 27 },
			["Paintball.Fire"] = { "c2s", true, 42 },
			["Paintball.Cmd"] = { "c2s", true, 0 },
			["Paintball.State"] = { "s2c", true, 0 },
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
		t.eq(n, 7)
		t.eq(Wire.SnapHead.size, 11)
		t.eq(Wire.SnapBody.size, 13)
		-- the client's send rate fits its bucket with room for jitter; so does the fastest honest fire
		local move = Wire.REMOTES["Paintball.Move"]
		t.truthy(move.rate :: number >= Clock.SEND_HZ * 1.25)
		t.truthy(Wire.REMOTES["Paintball.Fire"].rate :: number >= 1.5 / R.fireInterval)
		-- positions fit the quantised range
		t.truthy(Wire.XZ > Arena.HALF + 1 and Wire.Y_LO < -1 and Wire.Y_HI > Arena.HEIGHT + Body.STAND_TOP)
	end)

	t.test("wire: Net takes a Move, a Fire and a Cmd, and drops what is malformed", function()
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
		for _, name in { "Paintball.Move", "Paintball.Fire", "Paintball.Cmd" } do
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
		t.deepEq({ net:receive(p, "Paintball.Fire", BufferCodec.encode(Wire.Fire, fire), 0) }, { false, "non-finite" })
		t.truthy(net:receive(p, "Paintball.Cmd", { verb = "reload", t = 5 }, 0))
		t.truthy(net:receive(p, "Paintball.Cmd", { verb = "join" }, 0))
		t.deepEq({ net:receive(p, "Paintball.Cmd", { verb = "win" }, 0) }, { false, "schema" })
		t.deepEq(Wire.CMD_VERBS, { "pass", "join", "leave", "reload" })
	end)

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
		local b = Wire.encodeSnap(1234.5678, 70000, bodies)
		t.eq(buffer.len(b), Wire.SnapHead.size + R.slots * Wire.SnapBody.size)
		local time, seq, back = Wire.decodeSnap(b)
		t.eq(time, 1234.5678)
		t.eq(seq, 70000 % 65536)
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

	t.test("wire: every kind of State message has a schema; good ones pass, bad ones do not", function()
		local view = Match.view(Match.new())
		view.slots = { { id = 1, team = 1, name = "Ada", bot = false, userId = 12, tags = 0, outs = 0 } }
		local place = { x = Arena.PLACE.x, y = Arena.PLACE.y, z = Arena.PLACE.z, yaw = Arena.PLACE.yaw }
		local card = Match.card(Match.new(), 0)
		card.rows = {
			{ id = 1, name = "Ada", team = 1, bot = false, tags = 3, outs = 1, shots = 20, hits = 3, accuracy = 0.15 },
		}
		card.awards = { { title = "Most Paint Wasted", id = 1, name = "Ada" } }
		local good: { { [string]: any } } = {
			{ k = "pass", ok = false, text = Contract.passShort(20, 7), cents = 7 },
			{ k = "joined", you = 1, match = view, place = place, splats = buffer.create(0), now = 5 },
			{ k = "watch", match = view, place = place, splats = buffer.create(Wire.Splat.size), now = 5 },
			{ k = "unwatch" },
			{ k = "left", why = "dropped", text = Contract.textFor("dropped") },
			{ k = "match", match = view },
			{ k = "tag", by = 2, id = 1, ball = 17, scores = { 0, 1 }, at = 9, x = 0, y = 1, z = 2 },
			{ k = "respawn", id = 1, x = 0, y = 0, z = 0, yaw = 0, at = 11 },
			{ k = "ack", shot = 4, ok = true, ball = 17, rounds = 4 },
			{ k = "ack", shot = 5, ok = false, why = "sprint", rounds = 4, reloadAt = 12 },
			{ k = "reload", id = 1, at = 12 },
			{ k = "refused", what = "join", why = "pass", text = Contract.textFor("pass") },
			{ k = "correct", x = 0, y = 0, z = 0, yaw = 0, why = "fast" },
			{ k = "end", card = card },
			{ k = "say", id = 3, line = "floor", n = 3 },
		}
		local seen: { [string]: boolean } = {}
		for _, msg in good do
			local ok, err = Wire.checkState(msg)
			t.truthy(ok, `{msg.k}: {err}`)
			seen[msg.k] = true
		end
		for k in Wire.STATE do
			t.truthy(seen[k], `no example of '{k}'`)
		end
		t.falsy((Wire.checkState({ k = "tag", by = 2, id = 1 })))
		t.falsy(
			(Wire.checkState({ k = "tag", by = 2, id = 99, ball = 1, scores = { 0, 1 }, at = 9, x = 0, y = 1, z = 2 }))
		)
		t.falsy((Wire.checkState({ k = "left", why = "because", text = "" })))
		t.falsy((Wire.checkState({ k = "unwatch", extra = 1 })))
		t.falsy((Wire.checkState({ k = "nope" })))
		t.falsy((Wire.checkState("joined")))
	end)

	t.test("wire: at 8 v 8 a player costs under 8 kB/s down and 1.5 kB/s up", function()
		local b = Wire.budget(R.slots)
		t.eq(b.snap, 219)
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

	t.test("stubs: every lane's module keeps the names the other lanes call", function()
		local function has(module: any, names: { string }, label: string)
			for _, name in names do
				t.isType(module[name], "function", `{label}.{name}`)
			end
		end
		has(Match, {
			"new",
			"join",
			"leave",
			"slot",
			"slotOf",
			"humans",
			"step",
			"drain",
			"canFire",
			"fire",
			"reload",
			"canBeHit",
			"hit",
			"bits",
			"view",
			"card",
		}, "Match")
		has(Bots, { "new", "sync", "place", "step" }, "Bots")
		has(ArenaData, { "build" }, "ArenaData")
		has(PaintballService, { "new", "start" }, "PaintballService")
		has(PaintballClient, { "new", "start" }, "PaintballClient")
		local service = PaintballService.new({})
		has(service, {
			"buyPass",
			"join",
			"leave",
			"onMove",
			"onFire",
			"onCmd",
			"step",
			"watching",
			"stats",
			"stop",
		}, "Service")
		local client = PaintballClient.new({
			send = function() end,
			now = function()
				return 0
			end,
		})
		has(client, { "onState", "onSnap", "onShots", "onSplats", "input", "step", "stop" }, "Client")
		-- a match that nobody has joined is idle and its view is a well-formed wire message
		local match = Match.new({ seed = 3 })
		t.eq(match.phase, "idle")
		t.eq(Match.humans(match), 0)
		t.truthy(Wire.checkState({ k = "match", match = Match.view(match) }))
		t.truthy(Wire.checkState({ k = "end", card = Match.card(match, 0) }))
		t.deepEq(Bots.step(Bots.new(service.arena), match, {}, 0, 1 / Clock.TICK_HZ), {})
	end)
end
