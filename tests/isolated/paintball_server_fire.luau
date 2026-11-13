--!strict
-- tests/isolated/paintball_server_fire.luau: the click, on the paintball service in a whole game on the fake
-- engine, for tests/unit/paintball_server.spec.luau (its own Lune process: tests/lib/Isolated). What makes a
-- click a shot and what refuses it (the magazine, the sprint, the spawn room, the origin), what a liar gets
-- for lying about its fire rate, its ammunition, where it stood and what it saw; every tag, the paint it
-- leaves and who is told; two verdicts in one tick; a late joiner's splats; the bots' commands; and scripted
-- clients at 0, 80, 150 and 300 ms of round trip with jitter and loss, each hitting what it saw (standing,
-- and strafing with clicks that are themselves jittered and now and then behind a lost packet).
-- Interface: return function(t) (the spec shape)
local Ballistics = require("@shared/Paintball/Ballistics")
local Magazine = require("@shared/Paintball/Magazine")
local Arena = require("@shared/Minigames/Paintball/Arena")
local Body = require("@shared/Minigames/Paintball/Body")
local Clock = require("@shared/Minigames/Paintball/Clock")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Hit = require("@shared/Minigames/Paintball/Hit")
local Rules = require("@shared/Minigames/Paintball/Rules")
local Wire = require("@shared/Minigames/Paintball/Wire")
local Bots = require("@server/Minigames/Paintball/Bots")
local Stream = require("@server/Minigames/Paintball/Stream")
local PaintballFlow = require("@tests/engine/PaintballFlow")
local Kit = require("@tests/isolated/paintball_server_kit")

local R = Contract.Rules
local FRAME = 1 / 60

local function teamOf(kit: Kit.Kit, c: Kit.Client): number
	return kit.state().slots[c.seat].team
end

-- people in the hall, the first on team 1, the second on team 2, a third on team 1 again; the match live
local function people(kit: Kit.Kit, names: { string }, copts: { { [string]: any } }?): ...Kit.Client
	local out: { Kit.Client } = {}
	for i, name in names do
		local c = kit.client(name, if copts then copts[i] else nil)
		assert(kit.join(c))
		kit.run(0.1)
		out[i] = c
	end
	kit.run(0.5)
	for i, c in out do
		assert(teamOf(kit, c) == (if i % 2 == 1 then 1 else 2), `{c.name} is on the wrong side for this case`)
	end
	kit.live()
	return table.unpack(out)
end

local function ack(kit: Kit.Kit, c: Kit.Client, shot: number): any
	kit.untilTrue(1, function(): boolean
		return c.acks[shot] ~= nil
	end)
	return c.acks[shot] or error(`{c.name} heard no ack for shot {shot}`)
end

-- the splat a ball left, as this client was told
local function splatOf(c: Kit.Client, ball: number): any
	for _, rec in c.splats do
		if rec.ball == ball then
			return rec
		end
	end
	return nil
end

return function(t)
	t.test(
		"a click is a shot: born at the eye along the look, told to everybody, acked with the magazine; five, then the reload; too fast and empty are refused",
		function()
			Kit.play(function(kit)
				local ada, bea = people(kit, { "Ada", "Bea" })
				local stats = kit.service:stats()
				kit.walk(ada, -36, -2)
				kit.run(0.2)
				local feel = kit.state().feel
				local fired = kit.now()
				local shot = ada.fire(1, 0, 0)
				local a = ack(kit, ada, shot)
				t.deepEq({ a.ok, a.rounds, a.why, a.reloadAt }, { true, R.magazine - 1, nil, nil })
				t.eq(stats.balls, 1)
				-- everybody in the audience is told of the ball: when it was born, from where, how fast
				kit.run(0.1)
				local born = bea.shots[1]
				t.deepEq({ born.ball, born.id, born.t }, { a.ball, ada.seat, fired })
				t.near(born.ox, -36, 1e-4)
				t.near(born.oy, Body.STAND_EYE, 1e-4)
				t.deepEq({ born.vx, born.vy, born.vz }, { feel.ballSpeed, 0, 0 })
				-- it drops as it flies (4.9 t^2 from the eye) and ends on the floor: one splat, on a face, for all
				kit.run(1.2)
				local splat = splatOf(bea, a.ball)
				t.truthy(splat ~= nil, "the splat was sent")
				t.deepEq({ splat.body, splat.by, splat.team, splat.face }, { 0, ada.seat, 1, Wire.FACE.py })
				local flight = math.sqrt(Body.STAND_EYE / (feel.ballDrop / 2))
				t.near(splat.x, -36 + feel.ballSpeed * flight, 0.01, "where the drop brings it down")
				t.near(splat.y, 0, 1e-4)
				t.eq(splatOf(ada, a.ball).seq, splat.seq, "the same record on every screen")
				-- a second click inside the fire interval is refused, and says so; the magazine is as it was
				local second = ada.fire(1, 0, 0)
				kit.run(0.1)
				local third = ada.fire(1, 0, 0)
				t.deepEq({ ack(kit, ada, second).ok, ack(kit, ada, second).rounds }, { true, 3 })
				local refused = ack(kit, ada, third)
				t.deepEq({ refused.ok, refused.why, refused.rounds, refused.ball }, { false, "fast", 3, nil })
				t.eq(stats.shotsRefused, 1)
				-- the rest of the magazine: the fifth ball starts the reload, and only the reloader is told
				for want = 2, 0, -1 do
					kit.run(feel.fireInterval + 0.02)
					local next = ack(kit, ada, ada.fire(1, 0, 0))
					t.deepEq({ next.ok, next.rounds }, { true, want })
					if want == 0 then
						t.near(next.reloadAt, ada.lastFire.ft + feel.reloadSecs, 1e-6)
						kit.run(0.1)
						local reload = ada.last("paintball_reload")
						t.deepEq({ reload.id, reload.at }, { ada.seat, next.reloadAt })
						t.eq(bea.count("paintball_reload"), 0)
					end
				end
				kit.run(feel.fireInterval + 0.02)
				local dry = ack(kit, ada, ada.fire(1, 0, 0))
				t.deepEq({ dry.ok, dry.why, dry.rounds }, { false, "empty", 0 })
				-- everybody else hears the reload from the bit in the snapshots
				local snap = bea.snaps[#bea.snaps]
				for _, body in snap.bodies do
					if body.id == ada.seat then
						t.truthy(Wire.has(body.bits, Wire.BIT.reload))
					end
				end
				kit.run(feel.reloadSecs)
				local full = ack(kit, ada, ada.fire(1, 0, 0))
				t.deepEq({ full.ok, full.rounds }, { true, R.magazine - 1 })
				t.eq(stats.balls, 6)
				-- R on a magazine that is not full reloads; on a full one it is refused with words
				t.deepEq(
					{ kit.w.svc:input(ada.stub, { gameId = Contract.STATION, verb = "reload", args = { kit.now() } }) },
					{ true, nil }
				)
				kit.run(feel.reloadSecs + 0.2)
				local again =
					{ kit.w.svc:input(ada.stub, { gameId = Contract.STATION, verb = "reload", args = { kit.now() } }) }
				t.deepEq(again, { false, Contract.textFor("phase") })
			end)
		end
	)

	t.test("three shots bunched half a second late are all accepted, as three balls a fire interval apart", function()
		Kit.play(function(kit)
			local ada = people(kit, { "Ada", "Bea" })
			kit.walk(ada, -36, -2)
			kit.run(0.2)
			local feel = kit.state().feel
			-- three clicks a fire interval apart by the client's own magazine (each stamp is the last plus the
			-- interval, as Magazine counts it); the first is held up 29 frames behind a lost packet, the
			-- second 14, and all three reach the server in one frame, the oldest just under half a second late
			local ft = kit.now()
			local s1 = ada.fire(1, 0, 0, { ft = ft }, 29)
			kit.run(15 * FRAME)
			local s2 = ada.fire(1, 0, 0, { ft = ft + feel.fireInterval }, 14)
			kit.run(14 * FRAME)
			local s3 = ada.fire(1, 0, 0, { ft = ft + feel.fireInterval + feel.fireInterval })
			kit.run(0.2)
			for i, shot in { s1, s2, s3 } do
				local a = ada.acks[shot]
				t.truthy(a ~= nil and a.ok, `shot {i}: {a and a.why}`)
				t.eq(a.rounds, R.magazine - i)
			end
			t.eq(kit.service:stats().shotsRefused, 0)
		end)
	end)

	t.test(
		"a strafing shooter's click held up behind a lost packet is still a shot, from where she clicked; a liar who back-dates a click gets nothing but a shot from where she really stood, inside her own window",
		function()
			Kit.play(function(kit)
				local ada, bea = people(kit, { "Ada", "Bea" })
				local stats = kit.service:stats()
				kit.walk(ada, -36, -10)
				kit.run(0.2)
				local function strafe(seconds: number)
					for _ = 1, math.floor(seconds * 60 + 0.5) do
						ada.z += Body.WALK * FRAME
						kit.frame()
					end
				end
				-- she walks north and clicks as she goes; the click is 15 frames behind a lost packet
				strafe(0.5)
				local clicked, at = kit.now(), ada.z
				local shot = ada.fire(1, 0, 0, nil, 15)
				strafe(0.5)
				local a = ada.acks[shot]
				t.truthy(a ~= nil and a.ok, `the late click: {a and a.why}`)
				local born = bea.shots[#bea.shots]
				t.eq(born.ball, a.ball)
				t.near(born.oz, at, 1e-3, "the ball leaves from where she clicked")
				t.truthy(
					born.t >= clicked + 15 * FRAME - Clock.REWIND_TOLERANCE - 2 * FRAME,
					`but is born no earlier than her own delay allows ({born.t - clicked} s after the click)`
				)
				t.eq(stats.shotsRefused, 0)
				-- THE LIAR. She stands, walks on for a quarter of a second, and stamps a click a quarter of a second
				-- back from where she stood then: that is a shot (she was there, inside her own window: with no delay
				-- that is the resend floor and the tolerance, Stream.lateWindow), born no earlier than f
				kit.run(0.7)
				local window = Stream.lateWindow(Stream.new(ada.stub, 0))
				t.truthy(window < 0.3, `a client with no delay is held to a short window ({window} s)`)
				local stoodZ = ada.z
				strafe(0.25)
				local now = kit.now()
				local back = ack(kit, ada, ada.fire(1, 0, 0, { ft = now - 0.25, oz = stoodZ }))
				t.truthy(back.ok, tostring(back.why))
				t.truthy(bea.shots[#bea.shots].t >= now - Clock.REWIND_TOLERANCE - 2 * FRAME)
				-- from where she never stood, it is not
				kit.run(0.3)
				local never = ack(kit, ada, ada.fire(1, 0, 0, { ft = kit.now() - 0.25, ox = -33, oz = stoodZ }))
				t.deepEq({ never.ok, never.why }, { false, "origin" })
				-- and not from where she stood longer ago than her window: 0.45 s, which the magazine's own bound
				-- would have let through, is judged at the window's edge, where she was not
				kit.run(0.7)
				local stoodAgain = ada.z
				strafe(0.45)
				local far = ack(kit, ada, ada.fire(1, 0, 0, { ft = kit.now() - 0.45, oz = stoodAgain }))
				t.deepEq({ far.ok, far.why }, { false, "origin" })
				kit.run(0.7)
				local longAgo = ada.z
				strafe(1)
				local old = ack(kit, ada, ada.fire(1, 0, 0, { ft = kit.now() - 1, oz = longAgo }))
				t.deepEq({ old.ok, old.why }, { false, "origin" })
				t.eq(stats.corrections, 0)
			end)
		end
	)

	-- FOUND IN REVIEW: a back-dated click had its spawn room, its sprint and its stance judged at the time it
	-- named, while its ball was born at f from a body in the present. Each of these was a shot; each is now
	-- refused, and the honest strafer's late click above is still a shot.
	t.test(
		"a back-dated click buys no shot from safety: a shooter who has walked back into her spawn room cannot fire from the doorway she left",
		function()
			Kit.play(function(kit)
				local ada, bea = people(kit, { "Ada", "Bea" })
				kit.walk(ada, -38, -2) -- two studs out of her room (x -50..-40)
				kit.run(0.3)
				local stoodT = kit.now()
				local ex, ey, ez = ada.eye()
				kit.walk(ada, -42, -2) -- back inside, in a quarter of a second
				local now = kit.now()
				t.truthy(now - stoodT < Stream.lateWindow(Stream.new(ada.stub, 0)), "the stamp is inside her window")
				t.truthy(Arena.inRoom(kit.arena.spawnRooms[1], ada.x, ada.y + 0.1, ada.z))
				local a = ack(kit, ada, ada.fire(1, 0, 0, { ft = stoodT, ox = ex, oy = ey, oz = ez }))
				t.deepEq({ a.ok, a.why, a.ball }, { false, "safe", nil })
				-- (where she stands, nobody can tag her: that is what the refusal protects)
				kit.run(0.2)
				local snap = bea.snaps[#bea.snaps]
				for _, body in snap.bodies do
					if body.id == ada.seat then
						t.truthy(Wire.has(body.bits, Wire.BIT.safe))
					end
				end
				t.eq(kit.service:stats().balls, 0)
			end)
		end
	)

	t.test(
		"a back-dated click buys no shot while sprinting: a click stamped before the sprint began is refused while the marker is down",
		function()
			Kit.play(function(kit)
				local ada = people(kit, { "Ada", "Bea" })
				kit.walk(ada, -36, -15)
				kit.run(0.3)
				local walkT = kit.now()
				local ex, ey, ez = ada.eye()
				ada.sprint = true
				local feel = kit.state().feel
				for _ = 1, 12 do -- a fifth of a second of sprint
					ada.z += Body.WALK * feel.sprintMult * FRAME
					kit.frame()
				end
				local honest = ack(kit, ada, ada.fire(1, 0, 0))
				t.deepEq({ honest.ok, honest.why }, { false, "sprint" })
				local back = ack(kit, ada, ada.fire(1, 0, 0, { ft = walkT - 0.03, ox = ex, oy = ey, oz = ez }))
				t.deepEq({ back.ok, back.why }, { false, "sprint" }, "stamped while she walked, sent while she runs")
				t.eq(kit.service:stats().movesRefused, 0)
				t.eq(kit.service:stats().balls, 0)
				-- she stops; once the marker is up, a click is a shot again
				ada.sprint = false
				kit.run(Body.SPRINT_FIRE_DELAY + 0.1)
				t.truthy(ack(kit, ada, ada.fire(1, 0, 0)).ok)
			end)
		end
	)

	t.test(
		"a back-dated click buys no shot over a rail from a crouch: the standing eye of a moment ago is refused while the server holds her crouched",
		function()
			Kit.play(function(kit)
				local ada, bea = people(kit, { "Ada", "Bea" })
				kit.walk(bea, 12, 0)
				kit.walk(ada, -1.8, 0) -- west of the rail (x 0..0.5)
				kit.run(0.5)
				local standT = kit.now()
				local ex, ey, ez = ada.eye()
				ada.crouch = true
				kit.run(0.25)
				t.truthy(kit.service.poses[ada.seat].crouch >= 0.75, "the server holds her crouched")
				local bx, by, bz = Body.eyePoint(12, 0, 0, 0)
				local a = ack(kit, ada, ada.fire(bx - ex, by - ey, bz - ez, { ft = standT, ox = ex, oy = ey, oz = ez }))
				t.deepEq({ a.ok, a.why }, { false, "origin" })
				kit.run(0.6)
				t.eq(#bea.tags, 0, "Bea is not tagged")
				-- from her own crouched eye the click is hers (and meets the rail)
				local cx, cy, cz = ada.aim(12, Body.STAND_EYE, 0)
				t.truthy(ack(kit, ada, ada.fire(cx, cy, cz)).ok)
				kit.run(0.6)
				t.eq(#bea.tags, 0)
			end, { arena = Kit.hall({ rail = true, room2 = 20 }), feel = Contract.feel({ ballDrop = 0 }) })
		end
	)

	t.test("a click 0.15 s after the last sprint Move is accepted; one inside the delay is refused", function()
		Kit.play(function(kit)
			local ada = people(kit, { "Ada", "Bea" })
			kit.walk(ada, -36, -2)
			ada.sprint = true
			kit.walk(ada, -30, -2, Body.WALK * kit.state().feel.sprintMult)
			t.eq(kit.service:stats().movesRefused, 0, "the sprint bit buys sprint pace")
			-- the last Move that carries the bit
			ada.auto = false
			local last = ada.move().t
			ada.sprint = false
			kit.run(1 / Clock.SEND_HZ)
			ada.move()
			local early = ada.fire(1, 0, 0)
			t.deepEq({ ack(kit, ada, early).ok, ack(kit, ada, early).why }, { false, "sprint" })
			ada.move()
			kit.untilTrue(1, function(): boolean
				return kit.now() >= last + Body.SPRINT_FIRE_DELAY - 1e-9
			end)
			ada.move()
			local shot = ada.fire(1, 0, 0)
			t.near(ada.lastFire.ft, last + Body.SPRINT_FIRE_DELAY, FRAME)
			t.truthy(ack(kit, ada, shot).ok, tostring(ack(kit, ada, shot).why))
		end)
	end)

	t.test("a shot from inside a spawn room is refused; a step outside it, it is a shot", function()
		Kit.play(function(kit)
			local ada = people(kit, { "Ada", "Bea" })
			kit.run(0.3)
			local inside = ack(kit, ada, ada.fire(1, 0, 0))
			t.deepEq({ inside.ok, inside.why }, { false, "safe" })
			-- her snapshot says so too: safe while she stands in her own room, whatever the protection clock says
			local snap = ada.snaps[#ada.snaps]
			for _, body in snap.bodies do
				if body.id == ada.seat then
					t.truthy(Wire.has(body.bits, Wire.BIT.safe))
				end
			end
			kit.walk(ada, -39, -2) -- the room ends at x = -40
			kit.run(0.2)
			t.truthy(ack(kit, ada, ada.fire(1, 0, 0)).ok)
		end)
	end)

	t.test(
		"a liar about where the shot came from is refused: beyond a stud of the eye, through cover, from standing height while crouched, with no direction",
		function()
			Kit.play(function(kit)
				local ada = people(kit, { "Ada", "Bea" })
				local stats = kit.service:stats()
				kit.walk(ada, -36, -2)
				kit.walk(ada, -30.6, -5) -- pressed against the west face of the wall (x -30..-28)
				kit.run(0.2)
				local function refusedOrigin(over: { [string]: number }, what: string)
					kit.run(0.3)
					local a = ack(kit, ada, ada.fire(1, 0, 0, over))
					t.deepEq(
						{ a.ok, a.why },
						{ false, "origin" },
						`{what} (the server said {tostring(a.ok)}, {tostring(a.why)})`
					)
				end
				refusedOrigin({ ox = -27 }, "from the far side of the wall")
				refusedOrigin({ ox = -29.8 }, "within a stud, but inside the cover")
				-- (the slack is a stud, and walking pace for the twentieth of a second since her newest Move: 1.85 at the most)
				refusedOrigin({ oz = -5 + 2.5 }, "two and a half studs to one side")
				refusedOrigin({ dx = 0 }, "no direction")
				-- an honest shot from the eye, with the stud of slack a moving body needs
				kit.run(0.3)
				t.truthy(ack(kit, ada, ada.fire(-1, 0, 0, { oz = -5 + 0.8 })).ok)
				-- crouched: the eye is at 2.7, and a shot from standing height is not hers
				ada.crouch = true
				kit.run(0.5)
				t.near(kit.service.poses[ada.seat].crouch, 1, 1e-6, "the server eased her hit shape down")
				refusedOrigin({ oy = Body.STAND_EYE }, "standing height while crouched")
				kit.run(0.3)
				local low = ack(kit, ada, ada.fire(-1, 0, 0))
				t.truthy(low.ok, tostring(low.why))
				t.near(ada.lastFire.oy, Body.CROUCH_EYE, 1e-9)
				t.eq(stats.shotsRefused, 5)
				t.deepEq(stats.shotsRefusedBy, { origin = 5 }, "counted by why")
				t.eq(stats.balls, 2, "none of the refused clicks became a ball")
			end, { arena = Kit.hall({ wall = true }) })
		end
	)

	t.test(
		"a tag: the ball ends where it entered the body, everyone seated hears who, the score and the tallies with no state message, the paint rides on the body, and the tagged come back with a full magazine",
		function()
			Kit.play(function(kit)
				local ada, bea = people(kit, { "Ada", "Bea" })
				local st = kit.w.svc.stations[Contract.STATION]
				kit.walk(ada, -36, -2)
				kit.walk(bea, -6, -2) -- out of her room (x -20..-10), thirty studs from Ada
				for _ = 1, 3 do
					kit.run(0.3)
					ack(kit, bea, bea.fire(0, 0, 1)) -- (Bea has fired three of her five)
				end
				kit.run(1.2)
				local feel = kit.state().feel
				local bx, by, bz = ada.drawn(bea.seat)
				t.near(bx :: number, -6, 0.01, "Ada's screen draws Bea where she stands")
				local shot = ada.fire(ada.aim(bx :: number, by + 3, bz))
				local a = ack(kit, ada, shot)
				t.truthy(a.ok)
				t.truthy(kit.untilTrue(1, function(): boolean
					return #bea.tags > 0
				end))
				t.truthy(kit.w.svc.clock - st.lastBroadcast > 2 * FRAME, "the tag did not send the framework's state")
				local tag = bea.tags[1]
				t.deepEq(
					{ tag.by, tag.id, tag.ball, tag.scores, tag.tags, tag.outs },
					{ ada.seat, bea.seat, a.ball, { 1, 0 }, 1, 1 }
				)
				t.near(tag.at, kit.now() + feel.respawnSecs, 2 * FRAME)
				t.near(tag.x, -6 - Body.RADIUS, 0.01, "the entry point: the near side of her shape")
				t.truthy(tag.y > 2 and tag.y < 3)
				t.eq(#ada.tags, 1, "the shooter's hit marker is this message")
				t.truthy(bea.out)
				-- the splat is on her body: an offset in her own frame, which puts it back on the entry point
				kit.run(0.1)
				local splat = splatOf(ada, a.ball)
				t.deepEq({ splat.body, splat.by, splat.team, splat.face }, { bea.seat, ada.seat, 1, 0 })
				local pose = kit.service.poses[bea.seat]
				local wx, wy, wz = Wire.fromBody(splat.x, splat.y, splat.z, pose.x, pose.y, pose.z, pose.yaw)
				t.near(wx, tag.x, 0.01)
				t.near(wy, tag.y, 0.01)
				t.near(wz, tag.z, 0.01)
				-- while out she cannot be tagged again, and a ball passes where she stood
				local second = ack(kit, ada, ada.fire(ada.aim(bx :: number, by + 3, bz)))
				kit.run(1.2)
				t.eq(#bea.tags, 1)
				t.eq(splatOf(ada, second.ball).body, 0, "it flew on to the wall")
				-- back after respawnSecs, placed in her room, with all five
				t.truthy(kit.untilTrue(feel.respawnSecs, function(): boolean
					return not bea.out
				end))
				kit.run(1.1)
				t.eq(bea.extras.rounds, R.magazine, "nobody comes back with the two balls they had left")
				t.deepEq(bea.view.game.scores, { 1, 0 })
				t.eq(kit.service:stats().tags, 1)
			end, { arena = Kit.hall({ room2 = -20 }) })
		end
	)

	t.test(
		"the owner's tuning: a number out of its range, or one that is no feel number, is refused with words; a faster, heavier ball and a slower trigger are in force from the next match and not before: every client is told, the server's ball flies and falls by the new numbers and the magazine keeps the new interval",
		function()
			Kit.play(function(kit)
				local ada, bea = people(kit, { "Ada", "Bea" })
				local service = kit.service
				local was = kit.state().feel
				local ok, why = service:debug("tune", "ballSpeed", 500)
				t.falsy(ok, "out of its range")
				t.truthy(type(why) == "string" and string.find(why :: string, "ballSpeed", 1, true), why)
				ok, why = service:debug("tune", "gravity", 1)
				t.falsy(ok, "no such number")
				t.truthy(type(why) == "string" and string.find(why :: string, "gravity", 1, true), why)
				t.falsy((service:debug("tune", "ballSpeed", "fast")), "not a number")
				t.truthy((service:debug("tune", "ballSpeed", 150)))
				t.truthy((service:debug("tune", "ballDrop", 40)))
				t.truthy((service:debug("tune", "fireInterval", 0.5)))
				-- the match in play keeps its own
				t.eq(kit.state().feel.ballSpeed, was.ballSpeed)
				kit.walk(ada, -36, -2)
				kit.run(0.2)
				local old = ack(kit, ada, ada.fire(1, 0, 0))
				t.truthy(old.ok)
				kit.run(0.1)
				t.deepEq({ bea.shots[#bea.shots].ball, bea.shots[#bea.shots].vx }, { old.ball, was.ballSpeed })
				-- the next match is played with the new numbers, and everybody is told
				t.truthy((service:debug("end")))
				kit.run(1)
				t.truthy(
					kit.untilTrue(R.endCardSecs, function(): boolean
						return service.match == 2
					end),
					"the service rolled on"
				)
				kit.run(0.6)
				local feel = kit.state().feel
				t.deepEq({ feel.ballSpeed, feel.ballDrop, feel.fireInterval }, { 150, 40, 0.5 })
				t.eq(feel.reloadSecs, was.reloadSecs, "the rest as it was")
				for _, c in { ada, bea } do
					t.deepEq({ c.watch.match, c.watch.feel.ballSpeed, c.watch.feel.ballDrop }, { 2, 150, 40 })
					t.deepEq({ c.extras.match, c.extras.feel.ballSpeed, c.extras.feel.fireInterval }, { 2, 150, 0.5 })
				end
				kit.live()
				kit.walk(ada, -36, -2)
				kit.run(0.2)
				local first = ack(kit, ada, ada.fire(1, 0, 0))
				t.truthy(first.ok)
				-- a click a third of a second later was a shot with the old trigger, and is too fast for the new
				kit.run(0.3)
				local second = ack(kit, ada, ada.fire(1, 0, 0))
				t.deepEq({ second.ok, second.why, second.rounds }, { false, "fast", R.magazine - 1 })
				local born = bea.shots[#bea.shots]
				t.deepEq({ born.ball, born.vx }, { first.ball, 150 })
				-- and the ball comes down where the new speed and the new drop bring it
				kit.run(1)
				local splat = splatOf(bea, first.ball)
				t.truthy(splat ~= nil, "the splat was sent")
				-- (to the width of the chord a tick's flight is: a heavier ball bends more inside one tick)
				t.near(splat.x, -36 + 150 * math.sqrt(Body.STAND_EYE / (40 / 2)), 0.05)
				t.near(splat.y, 0, 1e-4)
			end)
		end
	)

	t.test(
		"what one screen is sent at 8 v 8 with everybody firing as fast as the magazine allows, no two in step, is under the 8 kB a second the contract holds the stream to: the snapshots, every ball and every splat, and no click refused",
		function()
			Kit.play(function(kit)
				local stats = kit.service:stats()
				local list: { Kit.Client } = {}
				for i = 1, R.slots do
					local c = kit.client(`P{i}`)
					assert(kit.join(c))
					kit.run(0.1)
					list[i] = c
				end
				kit.run(0.5)
				kit.live()
				local feel = kit.state().feel
				-- everybody steps out of its room and paints the floor in front of it
				local step = Body.WALK / 60
				local start: { number } = {}
				for i, c in list do
					start[i] = c.x
				end
				for _ = 1, 60 do
					for i, c in list do
						local dir = if teamOf(kit, c) == 1 then 1 else -1
						c.x += math.clamp(start[i] + 12 * dir - c.x, -step, step)
						c.yaw, c.pitch = math.atan2(-dir, 0), -0.6
					end
					kit.frame()
				end
				kit.run(0.5)
				-- each with a magazine of its own, as a client has: a click the moment it allows one
				local mags: { any } = {}
				for i in list do
					mags[i] = Magazine.new(R.magazine, feel.fireInterval, feel.reloadSecs)
				end
				local watcher = list[1].stub
				local REMOTES = { "Paintball.Snap", "Paintball.Shot", "Splat" }
				local function sent(): (number, number)
					local bytes, messages = 0, 0
					for _, remote in REMOTES do
						for _, payload in (watcher.streams and watcher.streams[remote]) or {} do
							bytes += buffer.len(payload)
							messages += 1
						end
					end
					return bytes, messages
				end
				-- (no two of them in step: sixteen clicks in one frame would go out as one message, and a real
				-- match's go out one by one)
				for frame = 1, 16 * 7 do
					local now = kit.now()
					for i, c in list do
						if frame > i * 7 and Magazine.canFire(mags[i], now) then
							Magazine.fire(mags[i], now)
							c.fire(Body.look(c.yaw, c.pitch))
						end
					end
					kit.frame()
				end
				local SECONDS = 10
				local bytesWere, messagesWere = sent()
				local ballsWere = stats.balls
				for _ = 1, SECONDS * 60 do
					local now = kit.now()
					for i, c in list do
						if Magazine.canFire(mags[i], now) then
							Magazine.fire(mags[i], now)
							c.fire(Body.look(c.yaw, c.pitch))
						end
					end
					kit.frame()
				end
				local bytes, messages = sent()
				local balls = stats.balls - ballsWere
				local budget = Wire.budget(R.slots)
				-- (the wire's own guess at what the engine adds to a message: Wire.budget's FRAMING)
				local perSec = ((bytes - bytesWere) + (messages - messagesWere) * 16) / SECONDS
				local magazinePace = R.slots * R.magazine / ((R.magazine - 1) * feel.fireInterval + feel.reloadSecs)
				t.eq(stats.shotsRefused, 0, "a client's own magazine and the server's agree on every click")
				t.truthy(
					balls / SECONDS > 0.95 * magazinePace,
					`{balls / SECONDS} balls a second; the magazine allows {magazinePace}`
				)
				t.truthy(
					perSec < 8000,
					`{perSec} bytes a second to one screen; the contract holds the stream under 8000`
				)
				t.truthy(perSec > 0.75 * budget.stream, "and the measure is of the same thing the wire's budget is")
				print(
					string.format(
						"  (8 v 8, %.1f balls a second: %.0f bytes a second to one screen in %.0f messages a second; Wire.budget(16).stream reckons %.0f)",
						balls / SECONDS,
						perSec,
						(messages - messagesWere) / SECONDS,
						budget.stream
					)
				)
			end)
		end
	)

	t.test("a crouched body behind a rail is not tagged by a ball 0.05 over it; standing, it is", function()
		Kit.play(function(kit)
			local ada, bea = people(kit, { "Ada", "Bea" })
			kit.walk(ada, -10, 0)
			kit.walk(bea, 2.5, 0) -- behind the rail (x 0..0.5), her shape wholly east of it
			ada.crouch, bea.crouch = true, true
			kit.run(0.6)
			t.near(kit.service.poses[bea.seat].crouch, 1, 1e-6)
			-- from Ada's crouched eye, rising to pass 0.05 over the middle of the rail
			local over = Arena.RAIL_HEIGHT + 0.05
			local dx, dy, dz = ada.aim(0.25, over, 0)
			local first = ack(kit, ada, ada.fire(dx, dy, dz))
			t.truthy(first.ok, tostring(first.why))
			kit.run(1.5)
			t.eq(#bea.tags, 0, "crouched, she is lower than the ball's line")
			t.eq(splatOf(ada, first.ball).body, 0)
			-- she stands up; the same line now enters her shape
			bea.crouch = false
			kit.run(0.6)
			local second = ack(kit, ada, ada.fire(dx, dy, dz))
			kit.run(0.5)
			t.eq(#bea.tags, 1)
			t.eq(bea.tags[1].ball, second.ball)
			t.near(bea.tags[1].x, 2.5 - Body.RADIUS, 0.01)
			-- a ball a little lower stops on the rail, whoever is behind it
			kit.run(0.3)
			local lx, ly, lz = ada.aim(0.25, Arena.RAIL_HEIGHT - 0.3, 0)
			local third = ack(kit, ada, ada.fire(lx, ly, lz))
			kit.run(0.5)
			local splat = splatOf(ada, third.ball)
			t.deepEq({ splat.body, splat.face }, { 0, Wire.FACE.nx })
			t.near(splat.x, 0, 1e-4)
		end, { arena = Kit.hall({ rail = true, room2 = 10 }), feel = Contract.feel({ ballDrop = 0 }) })
	end)

	t.test(
		"two tags in one tick resolve the same way every time: the older ball tags, the younger flies on; two who tag each other are both out",
		function()
			local function once(cyFirst: boolean): { any }
				local log: { any } = {}
				Kit.play(function(kit)
					local ada, bea, cy = people(kit, { "Ada", "Bea", "Cy" })
					-- Ada and Cy stand either side of the line to Bea, the same distance from her
					kit.walk(ada, -36, -2)
					kit.walk(cy, -36, 2)
					kit.walk(bea, -6, 0)
					kit.run(1.2)
					local a1 = { ada.aim(-6, 3, 0) }
					local c1 = { cy.aim(-6, 3, 0) }
					local sa: number, sc: number
					if cyFirst then
						sc = cy.fire(c1[1], c1[2], c1[3])
						sa = ada.fire(a1[1], a1[2], a1[3])
					else
						sa = ada.fire(a1[1], a1[2], a1[3])
						sc = cy.fire(c1[1], c1[2], c1[3])
					end
					local ballA, ballC = ack(kit, ada, sa).ball, ack(kit, cy, sc).ball
					kit.run(1.5)
					t.eq(#bea.tags, 1, "one tag, not two")
					local tag = bea.tags[1]
					local elder = if cyFirst then cy else ada
					t.eq(tag.by, elder.seat)
					t.eq(tag.ball, if cyFirst then ballC else ballA)
					local other = splatOf(bea, if cyFirst then ballA else ballC)
					t.eq(other.body, 0, "the younger ball went on to the wall")
					table.insert(log, { tag.by, tag.ball, tag.x, tag.y, tag.z, tag.at, other.x, other.y, other.z })
					-- Bea comes back; she and Ada fire at each other in the same frame
					kit.untilTrue(kit.state().feel.respawnSecs + 0.5, function(): boolean
						return not bea.out
					end)
					kit.state().slots[bea.seat].safeUntil = kit.now()
					kit.walk(bea, -6, -2)
					kit.run(1.2)
					local tb = { bea.aim(-36, 3, -2) }
					local ta = { ada.aim(-6, 3, -2) }
					bea.fire(tb[1], tb[2], tb[3])
					ada.fire(ta[1], ta[2], ta[3])
					kit.run(1.5)
					t.eq(#ada.tags, 3, "three tags in all were heard")
					t.truthy(ada.out and bea.out, "each ball was good whatever became of its shooter")
					t.deepEq(ada.tags[3].scores, { 2, 1 })
					for i = 2, 3 do
						table.insert(log, { ada.tags[i].by, ada.tags[i].id, ada.tags[i].x, ada.tags[i].at })
					end
				end, { arena = Kit.hall({ room2 = -20 }) })
				return log
			end
			local first = once(false)
			t.deepEq(once(false), first, "the same again, number for number")
			local swapped = once(true)
			t.truthy(swapped[1][1] ~= first[1][1], "whoever fired first tags")
		end
	)

	t.test(
		"a late joiner gets the whole match and every splat: the batch is exactly the two pools, and a slot's paint goes when its occupant does",
		function()
			Kit.play(function(kit)
				local ada, bea = people(kit, { "Ada", "Bea" })
				kit.walk(ada, -36, -2)
				kit.walk(bea, -6, -2)
				kit.run(1.2)
				-- paint on the building, then on Bea
				for i = 1, 3 do
					ack(kit, ada, ada.fire(ada.aim(-36 + 10 * i, 0, 6)))
					kit.run(0.3)
				end
				ack(kit, ada, ada.fire(ada.aim(-6, 3, -2)))
				kit.run(1)
				t.eq(#bea.tags, 1)
				t.eq(#ada.splats, 4)
				-- Dan walks up and joins
				local dan = kit.client("Dan")
				t.truthy((kit.join(dan)))
				kit.run(1.2)
				t.eq(#dan.splats, 4, "every splat of the match so far")
				for i, rec in dan.splats do
					t.deepEq(rec, ada.splats[i], "the same records, oldest first")
				end
				t.eq(dan.watch.match, 1)
				t.eq(#dan.watch.slots, 8)
				t.deepEq(dan.view.game.scores, { 1, 0 })
				t.eq(dan.view.game.slots[ada.seat].tags, 1, "and the tallies")
				t.truthy(dan.extras.feel.ballSpeed == kit.state().feel.ballSpeed)
				t.eq(dan.extras.bots[ada.seat], false)
				t.eq(dan.place, 1, "and is placed in a spawn room")
				-- Bea leaves: a bot has her seat, and does not wear her paint
				kit.w.svc:leave(bea.stub, "left")
				kit.run(0.3)
				local eve = kit.client("Eve")
				t.truthy((kit.join(eve)))
				kit.run(0.5)
				t.eq(#eve.splats, 3, "the walls' paint only")
				for _, rec in eve.splats do
					t.eq(rec.body, 0)
				end
			end, { arena = Kit.hall({ room2 = -20 }) })
		end
	)

	t.test(
		"a liar about time gains nothing: a back-dated click is born no earlier than its own delay allows, a far view time is clamped and the body judged where the server holds it",
		function()
			Kit.play(function(kit)
				local ada, bea = people(kit, { "Ada", "Bea" })
				local stats = kit.service:stats()
				kit.walk(ada, -36, -2)
				kit.walk(bea, -6, -8)
				kit.run(1.2)
				-- claimed fired a quarter of a second ago: 22 studs of free flight if it were believed
				local now = kit.now()
				local a = ack(kit, ada, ada.fire(1, 0, 0, { ft = now - Clock.MAX_LATE }))
				t.truthy(a.ok)
				kit.run(0.1)
				local born = bea.shots[#bea.shots]
				t.eq(born.ball, a.ball)
				t.truthy(born.t >= now - Clock.REWIND_TOLERANCE - 2 * FRAME, `born {now - born.t} s back`)
				-- Bea runs north; Ada claims she saw her a second ago and fires at where Bea was then
				kit.walk(bea, -6, 8)
				local clamped = stats.rewindsClamped
				local sx, sy, sz = ada.aim(-6, 3, 8 - Body.WALK * 1)
				local old = ack(kit, ada, ada.fire(sx, sy, sz, { vt = kit.now() - 1 }))
				t.truthy(old.ok, "the click is a shot")
				kit.run(1.2)
				t.eq(stats.rewindsClamped, clamped + 1, "but its rewind is the server's own")
				t.eq(#bea.tags, 0, "and it hits nobody who is no longer there")
			end, { arena = Kit.hall({ room2 = -20 }) })
		end
	)

	t.test(
		"the bots: a fire command along the bot's own look is a ball from its eye, one off its look or from a spawn room is dropped; they hear every ball and tag; a call-out is broadcast",
		function()
			local stepWas = Bots.step
			local script: { Bots.Command } = {}
			local heardAll: { Bots.Heard } = {}
			local steps = 0
			(Bots :: any).step = function(_bots: any, _state: any, _poses: any, heard: { Bots.Heard }): { Bots.Command }
				steps += 1
				for _, h in heard do
					table.insert(heardAll, h)
				end
				local out = script
				script = {}
				return out
			end
			local ok, err = pcall(Kit.play, function(kit: Kit.Kit)
				local ada = people(kit, { "Ada" })
				local stats = kit.service:stats()
				local bot = 2 -- a bot of team 2
				t.eq(kit.state().slots[bot].team, 2)
				local pose = kit.service.poses[bot]
				local speed = kit.state().feel.ballSpeed
				local function fire(yawOff: number): Bots.Command
					local lx, ly, lz = Body.look(pose.yaw + yawOff, pose.pitch)
					return { id = bot, kind = "fire", vx = lx * speed, vy = ly * speed, vz = lz * speed }
				end
				-- from inside its spawn room: dropped
				script = { fire(0) }
				kit.run(0.1)
				t.eq(stats.balls, 0)
				-- its brain walks it out and turns it towards Ada's side
				pose.x, pose.z, pose.yaw = 30, 0, math.pi / 2
				script = { fire(math.rad(10)) }
				kit.run(0.1)
				t.eq(stats.balls, 0, "ten degrees off its own look: its puppet was not facing that way")
				script = { fire(math.rad(2)) }
				kit.run(0.1)
				t.eq(stats.balls, 1)
				local born = ada.shots[1]
				t.eq(born.id, bot)
				t.deepEq(
					{ born.ox, born.oy, born.oz },
					{ 30, Body.STAND_EYE, 0 },
					"from its eye, whatever the command said"
				)
				t.near(math.sqrt(born.vx ^ 2 + born.vy ^ 2 + born.vz ^ 2), speed, 1e-3)
				t.eq(kit.state().slots[bot].shots, 1, "through the match's own magazine")
				-- it is in the snapshots where its brain put it, like anybody
				local snap = ada.snaps[#ada.snaps]
				t.near(snap.bodies[bot].x, 30, 0.01)
				-- reload and a call-out
				script = { { id = bot, kind = "reload" }, { id = bot, kind = "say", line = "reloading" } }
				kit.run(0.1)
				t.truthy(kit.state().slots[bot].mag.reloadDoneAt ~= nil)
				local said = ada.last("paintball_say")
				t.deepEq({ said.id, said.line }, { bot, "reloading" })
				t.eq(ada.count("paintball_reload"), 0, "a bot's reload is nobody's message")
				script = { { id = bot, kind = "say", line = "something rude" } }
				kit.run(0.1)
				t.eq(ada.count("paintball_say"), 1, "only the lines of the contract are said")
				-- what the bots were told: the ball born, the ball ended; and a tag when there is one
				kit.run(1.5)
				local kinds: { [string]: number } = {}
				for _, h in heardAll do
					kinds[h.kind] = (kinds[h.kind] or 0) + 1
				end
				t.deepEq({ kinds.born, kinds.ended, kinds.tag }, { 1, 1, nil })
				t.truthy((kit.service:debug("tag", bot, ada.seat)))
				kit.run(0.1)
				t.eq(heardAll[#heardAll].kind, "tag")
				-- at the end card the bots stand where they stood
				t.truthy((kit.service:debug("end")))
				kit.run(0.5)
				t.eq(kit.session.phase, "done")
				local at = steps
				kit.run(0.5)
				t.eq(steps, at)
			end);
			(Bots :: any).step = stepWas
			if not ok then
				error(err, 0)
			end
		end
	)

	-- Scripted clients with a real connection's faults: a shooter and a runner, each with its own delay,
	-- jitter and loss. The shooter aims at the runner WHERE ITS OWN SCREEN DRAWS HER (its snapshots, its view
	-- time), leads her, and flies its own ball against the bodies it draws, frame by frame, as the client
	-- lane's predicted ball does (Hit.body on the drawn pose). The server's verdict on each ball is then set
	-- beside the shooter's own.
	-- `strafe`: the shooter walks from side to side as she fires, and her clicks have a connection's faults
	-- too: each is jittered like a Move, and one in twenty is behind a lost packet, a fifth of a second late.
	local function duel(
		rttMs: number,
		shots: number,
		strafe: boolean?
	): { agree: number, shots: number, hits: number, refused: number, late: number }
		local out = { agree = 0, shots = 0, hits = 0, refused = 0, late = 0 }
		local tagWas = Rules.tag
		local ok, err = pcall(Kit.play, function(kit: Kit.Kit)
			-- (the runner is hit and runs on: a tag here would send her back to her room after every hit)
			local model = Rules.tag;
			(Rules :: any).tag = function(): boolean
				return false
			end
			local half = rttMs / 1000 / 2 * 60
			local up, down = math.floor(half), math.ceil(half)
			local net =
				{ up = up, down = down, jitter = if rttMs > 0 then 2 else 0, lose = if rttMs > 0 then 0.05 else 0 }
			local ada, bea = people(kit, { "Ada", "Bea" }, { net, net })
			local arena = kit.arena
			local feel = kit.state().feel
			kit.walk(ada, -36, 0)
			kit.walk(bea, -6, -8)
			kit.run(1.5)
			local rand = ada.rand
			local mag = Magazine.new(R.magazine, feel.fireInterval, feel.reloadSecs) -- the shooter's own
			local dir = 1
			local side = 1
			local flying: { any } = {}
			local nextShot = kit.now() + 0.4
			local fired = 0
			local verdicts: { [number]: any } = {} -- by shot
			for _ = 1, 60 * 90 do
				-- the runner strafes between z = -8 and z = 8, crouching now and then
				bea.z += dir * Body.speed(if bea.crouch then 1 else 0, false, feel) * FRAME
				if bea.z > 8 or bea.z < -8 then
					dir = -dir
					bea.crouch = rand() < 0.3
				end
				if strafe then
					ada.z += side * Body.WALK * FRAME
					if ada.z > 3 or ada.z < -3 then
						side = -side
					end
				end
				-- the shooter's own ball, against what it draws
				local vt = ada.viewTime()
				for i = #flying, 1, -1 do
					local b = flying[i]
					local age0, age1 = b.age, kit.now() - b.ft
					if age1 > age0 then
						local p0x, p0y, p0z =
							Ballistics.position(b.ox, b.oy, b.oz, b.vx, b.vy, b.vz, feel.ballDrop, age0)
						local p1x, p1y, p1z =
							Ballistics.position(b.ox, b.oy, b.oz, b.vx, b.vy, b.vz, feel.ballDrop, age1)
						local wall = arena.sweep(p0x, p0y, p0z, p1x, p1y, p1z)
						local x, y, z, c = ada.drawnAt(bea.seat, vt)
						local s = if x ~= nil
							then Hit.body(arena.sweep, p0x, p0y, p0z, p1x, p1y, p1z, x, y, z, c)
							else nil
						b.age = age1
						if s ~= nil and (wall == nil or s < wall) then
							verdicts[b.shot].saw = true
							table.remove(flying, i)
						elseif wall ~= nil or age1 >= R.ballTtl then
							table.remove(flying, i)
						end
					end
				end
				if fired < shots and kit.now() >= nextShot and Magazine.canFire(mag, kit.now()) then
					nextShot = kit.now() + 0.3 + rand() * 0.3
					local x, y, z = ada.drawnAt(bea.seat, vt)
					local x2, _, z2 = ada.drawnAt(bea.seat, vt - 0.1)
					if x ~= nil and x2 ~= nil then
						Magazine.fire(mag, kit.now())
						-- lead her by the flight time, with a hand that is not quite steady
						local ex, ey, ez = ada.eye()
						local tof = math.sqrt((x - ex) ^ 2 + (z - ez) ^ 2) / feel.ballSpeed
						local ax = x + (x - x2) / 0.1 * tof
						local az = z + (z - z2) / 0.1 * tof + (rand() - 0.5) * 3.2
						local ay = y + 1.5 + rand() * 3.5 -- (over 3.4 it meets her only if she stands)
						local vx, vy, vz = Ballistics.aim(ex, ey, ez, ax, ay, az, feel.ballSpeed, feel.ballDrop)
						local held = 0
						if strafe then
							held = math.floor(rand() * 3)
							if rand() < 0.05 then
								held += 12
								out.late += 1
							end
						end
						local shot = ada.fire(vx / feel.ballSpeed, vy / feel.ballSpeed, vz / feel.ballSpeed, nil, held)
						fired += 1
						verdicts[shot] = { saw = false }
						table.insert(flying, {
							shot = shot,
							ft = ada.lastFire.ft,
							age = 0,
							ox = ex,
							oy = ey,
							oz = ez,
							vx = vx,
							vy = vy,
							vz = vz,
						})
					end
				end
				kit.frame()
				if fired >= shots and #flying == 0 and kit.now() > nextShot + 2 then
					break
				end
			end
			kit.run(1)
			for shot, v in verdicts do
				local a = ada.acks[shot]
				if a == nil or not a.ok then
					out.refused += 1
					continue
				end
				local splat = splatOf(ada, a.ball)
				local server = splat ~= nil and splat.body == bea.seat
				out.shots += 1
				out.hits += if server then 1 else 0
				out.agree += if server == v.saw then 1 else 0
			end
			local stats = kit.service:stats()
			assert(stats.corrections == 0, `{stats.corrections} corrections of honest clients at {rttMs} ms`)
			assert(stats.movesRefused == 0, `{stats.movesRefused} Moves of honest clients refused at {rttMs} ms`)
			assert(stats.movesAccepted > 1500, `only {stats.movesAccepted} Moves were judged at {rttMs} ms`);
			(Rules :: any).tag = model
		end, { arena = Kit.hall({ room2 = -20 }), feel = Contract.feel({ reloadSecs = 0.5 }) });
		(Rules :: any).tag = tagWas
		if not ok then
			error(err, 0)
		end
		return out
	end

	for _, case in
		{ { rtt = 0, bar = 0.99 }, { rtt = 80, bar = 0.95 }, { rtt = 150, bar = 0.95 }, { rtt = 300, bar = 0.9 } }
	do
		t.test(
			`a shooter at {case.rtt} ms hits what it saw: the server agrees with its screen on at least {case.bar * 100} % of 100 shots at a runner who crouches`,
			function()
				local r = duel(case.rtt, 100)
				t.eq(r.refused, 0, "an honest client's shot is never refused")
				t.truthy(r.shots >= 95, `{r.shots} shots judged`)
				t.truthy(
					r.hits >= 5 and r.hits <= r.shots - 5,
					`{r.hits} hits of {r.shots}: both verdicts were put to the test`
				)
				t.truthy(r.agree / r.shots >= case.bar, `agreement {r.agree} of {r.shots} at {case.rtt} ms`)
			end
		)
	end

	for _, case in { { rtt = 80, bar = 0.95 }, { rtt = 150, bar = 0.95 } } do
		t.test(
			`a strafing shooter at {case.rtt} ms whose clicks are jittered and now and then a fifth of a second late: none is refused, and the server agrees with her screen on at least {case.bar * 100} % of 100 shots`,
			function()
				local r = duel(case.rtt, 100, true)
				t.eq(r.refused, 0, "an honest client's shot is never refused, however late it came")
				t.truthy(r.late >= 2, `{r.late} clicks came late`)
				t.truthy(r.shots >= 95, `{r.shots} shots judged`)
				t.truthy(r.hits >= 5 and r.hits <= r.shots - 5, `{r.hits} hits of {r.shots}`)
				t.truthy(r.agree / r.shots >= case.bar, `agreement {r.agree} of {r.shots} at {case.rtt} ms`)
			end
		)
	end

	-- WHERE THE 300 ms SHOOTER'S MISSES COME FROM (measured: 92 of 100 agree). Its picture is its upstream
	-- delay (0.15 s, more with jitter) plus the interpolation (0.1 s) behind the server, and the contract
	-- judges no ball further back than Clock.MAX_REWIND = 0.25 s: the last few hundredths are cut off and a
	-- runner is judged half a stud on from where she was drawn. The case below is the evidence, for whoever
	-- owns the contract: with the bound at 0.3 s the same hundred shots agree as at 150 ms. (Clock is
	-- frozen: the constant is turned here for the length of this case only.)
	t.test(
		"what a 300 ms shooter still loses is the rewind bound's doing: with Clock.MAX_REWIND at 0.3 s the server agrees on at least 95 % of the same shots",
		function()
			local was = Clock.MAX_REWIND;
			(Clock :: any).MAX_REWIND = 0.3
			local ok, r = pcall(duel, 300, 100);
			(Clock :: any).MAX_REWIND = was
			if not ok then
				error(r, 0)
			end
			t.eq(r.refused, 0)
			t.truthy(r.agree / r.shots >= 0.95, `agreement {r.agree} of {r.shots} at 300 ms with a 0.3 s bound`)
		end
	)

	t.test(
		"the rewind bound can be tried at a playtest: debug rewind sets Clock.MAX_REWIND on this server between a tenth and four tenths of a second, and nothing else",
		function()
			local was = Clock.MAX_REWIND
			local ok, err = pcall(Kit.play, function(kit: Kit.Kit)
				t.deepEq({ kit.service:debug("rewind", 0.3) }, { true, nil })
				t.eq(Clock.MAX_REWIND, 0.3)
				t.falsy((kit.service:debug("rewind", 0.5)))
				t.falsy((kit.service:debug("rewind", "soon")))
				t.eq(Clock.MAX_REWIND, 0.3, "a refused value changes nothing")
			end);
			(Clock :: any).MAX_REWIND = was
			if not ok then
				error(err, 0)
			end
		end
	)

	t.test(
		"the server check (tests/engine/PaintballFlow) passes here first: the pass, a match of bots round one person, a scripted tag, the end card, the next match, leaving",
		function()
			-- (the real bots are another lane's: here a brain of four lines walks each bot out of its spawn room
			-- and has them fire along their own look in turn, four balls a second in all)
			local stepWas = Bots.step;
			(Bots :: any).step = function(
				_bots: any,
				state: Rules.State,
				poses: any,
				_heard: any,
				now: number
			): { Bots.Command }
				local out: { Bots.Command } = {}
				local speed = state.feel.ballSpeed
				for id, slot in state.slots do
					local pose = poses[id]
					if id == 1 or pose == nil or not slot.on or slot.out then
						continue
					end
					pose.x, pose.z = if slot.team == 1 then -36 else 36, id - 4
					pose.yaw = if slot.team == 1 then -math.pi / 2 else math.pi / 2
					if math.floor(now * 4) ~= math.floor((now - FRAME) * 4) and id == math.floor(now * 4) % 8 + 1 then
						local lx, ly, lz = Body.look(pose.yaw, pose.pitch)
						table.insert(out, { id = id, kind = "fire", vx = lx * speed, vy = ly * speed, vz = lz * speed })
					end
				end
				return out
			end
			local result: any = nil
			local ok, err = pcall(Kit.play, function(kit: Kit.Kit)
				local ann, bob = kit.client("Ann", { auto = false }), kit.client("Bob", { auto = false })
				result = PaintballFlow.play(kit.w.svc, { Arena = Arena, Contract = Contract, Clock = Clock }, {
					players = { ann.stub, bob.stub },
					step = kit.run,
					liveSeconds = 6,
					positionOf = function(player: any): (number?, number?, number?)
						return player.body.x, player.body.y + 3, player.body.z
					end,
					groupOf = function(player: any): string?
						return if player.body.ghost then Contract.COLLISION_GROUP else "Default"
					end,
				})
			end, { realPass = true });
			(Bots :: any).step = stepWas
			if not ok then
				error(err, 0)
			end
			t.eq(table.concat(result.failures, "; "), "", "what the server check found")
			t.truthy(result.ok)
			t.truthy(result.numbers.balls >= 3, `{result.numbers.balls} balls`) -- (lined up as they are, nearly every ball tags)
			t.truthy(result.numbers.tags > 0, "the bots tagged each other")
			t.truthy(type(result.numbers.banner) == "string")
			t.isType(result.numbers.stepMs.avg, "number")
			t.isType(result.numbers.stepMs.p95, "number")
			t.deepEq(result.numbers.stats.movesRefusedBy, {}, "the refusals by rule are reported (none)")
		end
	)
end
