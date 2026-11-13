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
local Hit = require("@shared/Minigames/Paintball/Hit")
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
local F = Contract.FEEL

return function(t)
	t.test("PB-1: a ball travels at 150 studs/s and drops a little: 45 studs in 0.3 s, about 0.9 low", function()
		t.eq(F.ballSpeed, 150)
		t.eq(F.ballDrop, 19.6)
		t.eq(R.ballTtl, 1.5)
		t.eq(R.ballRadius, 0.25)
		local x, y = Ballistics.position(0, 0, 0, F.ballSpeed, 0, 0, F.ballDrop, 0.3)
		t.near(x, 45, 1e-9)
		t.near(y, -0.882, 1e-9)
		-- and the arc still shows at the building's longest ranges: about two studs low over 70
		local _, y70 = Ballistics.position(0, 0, 0, F.ballSpeed, 0, 0, F.ballDrop, 70 / F.ballSpeed)
		t.truthy(y70 < -2 and y70 > -2.5)
		-- the longest flat shot stays inside the arena, at the slowest speed a feel may have: nothing is
		-- decided by the ttl
		t.truthy(F.ballSpeed * R.ballTtl >= 2 * Arena.HALF)
		t.truthy(Contract.FEEL_RANGE.ballSpeed[1] * R.ballTtl >= 2 * Arena.HALF)
		t.eq(Tunables.tree.paintball.projectileSpeed.v, F.ballSpeed)
		t.eq(Tunables.tree.paintball.drop.v, F.ballDrop)
	end)

	t.test("PB-2: five shots a quarter second apart, reload 1.6 s, by itself on the fifth or on R", function()
		t.eq(R.magazine, 5)
		t.eq(F.fireInterval, 0.25)
		t.eq(F.reloadSecs, 1.6)
		t.eq(Tunables.tree.paintball.magazine.v, R.magazine)
		local mag = Magazine.new(R.magazine, F.fireInterval, F.reloadSecs)
		for i = 0, 4 do
			t.truthy(Magazine.fire(mag, i * F.fireInterval))
		end
		t.falsy(Magazine.fire(mag, 1.5), "no firing while reloading")
		t.truthy(Magazine.fire(mag, 1.0 + F.reloadSecs), "full again 1.6 s after the fifth ball")
		t.truthy(Magazine.reload(mag, 3.0), "R when not full")
		-- a press during a reload asked for with balls left cancels it and fires (the review); the reload on the
		-- last ball cannot be cancelled
		t.truthy(Magazine.fire(mag, 3.2), "R cancelled by a press")
		t.eq(mag.reloadDoneAt, nil)
		t.eq(mag.rounds, R.magazine - 2)
		local empty = Magazine.new(R.magazine, F.fireInterval, F.reloadSecs)
		for i = 0, 4 do
			Magazine.fire(empty, i * F.fireInterval)
		end
		t.falsy(Magazine.fire(empty, 1.5), "the reload on the last ball runs its course")
		-- a click a little early is held, never lost: at six clicks a second the held click leaves the
		-- moment the interval is up, so the marker fires four balls a second, not three
		t.truthy(Contract.MARGIN.click >= F.fireInterval - 1 / 6, "a held click covers the gap to the next ball")
		t.truthy(Contract.MARGIN.click < F.fireInterval, "one click is held, not a queue")
	end)

	t.test("the feel: one table a match holds; the defaults, the ranges, a tuned copy", function()
		t.deepEq(Contract.FEEL, {
			ballSpeed = 150,
			ballDrop = 19.6,
			fireInterval = 0.25,
			reloadSecs = 1.6,
			sprintMult = 1.4,
			crouchSecs = 0.2,
			respawnSecs = 4,
			protectSecs = 2,
		})
		t.eq(#Contract.FEEL_KEYS, 8)
		for _, key in Contract.FEEL_KEYS do
			local range = Contract.FEEL_RANGE[key]
			local v = (Contract.FEEL :: any)[key]
			t.truthy(range ~= nil and range[1] <= v and v <= range[2], key)
		end
		-- the defaults are the plan's (the S18 Config and Tunables), so nothing moved at the default feel, but for
		-- the ball, which the review made faster (Contract, "the ball"; the S18 harness keeps its own 90)
		t.eq(F.ballSpeed, Tunables.tree.paintball.projectileSpeed.v)
		t.truthy(F.ballSpeed > Config.projectile.speed)
		t.eq(F.fireInterval, Config.fireInterval)
		t.eq(F.reloadSecs, Config.reloadSecs)
		t.eq(F.sprintMult, Tunables.tree.paintball.sprintMult.v)
		-- a fresh copy each time; unknown keys and bad values dropped, numbers held in range
		local a = Contract.feel()
		t.deepEq(a, Contract.FEEL)
		t.truthy(a ~= Contract.feel())
		local b = Contract.feel({ ballSpeed = 120, reloadSecs = 99, nonsense = 1, crouchSecs = "fast" })
		t.eq(b.ballSpeed, 120)
		t.eq(b.reloadSecs, Contract.FEEL_RANGE.reloadSecs[2])
		t.eq(b.crouchSecs, F.crouchSecs)
		t.eq((b :: any).nonsense, nil)
		-- the owner's playtest: one number changed, for the next match
		local c, why = Contract.tuned(a, "ballSpeed", 120)
		t.eq(why, nil)
		t.eq((c :: Contract.Feel).ballSpeed, 120)
		t.eq(a.ballSpeed, 150, "the table it was made from is untouched")
		t.eq((Contract.tuned(a, "ballSpeed", 5000)), nil)
		t.eq((Contract.tuned(a, "ballSpeed", "fast")), nil)
		local none, words = Contract.tuned(a, "gravity", 1)
		t.eq(none, nil)
		t.isType(words, "string")
		-- a feel goes on the wire as it is
		t.truthy(Schema.check(Wire.FEEL, c))
		t.falsy(Schema.check(Wire.FEEL, { ballSpeed = 90 }))
		-- the fastest fire a feel may have still fits the click's rate limit, the fastest sprint the framework's pace
		t.truthy(Wire.REMOTES["Paintball.Fire"].rate :: number >= 1.5 / Contract.FEEL_RANGE.fireInterval[1])
		t.truthy(Contract.FEEL_RANGE.sprintMult[2] <= Human.MAX_SCALE)
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
		t.truthy(F.respawnSecs >= 3 and F.respawnSecs <= 5, "tagged out for 3 to 5 s")
		t.eq(F.protectSecs, 2)
		t.eq(R.friendlyFire, false)
		t.eq(R.splatPool, 400)
		t.eq(R.bodySplats, 24)
		t.eq(R.idleSecs, 60)
		t.truthy(R.idleSecs > 4 * (F.respawnSecs + F.protectSecs), "nobody is idle for being tagged out a few times")
		t.eq(Contract.nextMatch(6.2), "The next match starts in 7 s.")
		t.eq(Contract.nextMatch(-3), "The next match starts in 1 s.")
		t.eq(Contract.COLLISION_GROUP, "PaintballBody")
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
		-- the S18 capsule's top and foot; the review widened it by 0.3 and shortened the axis by as much
		t.deepEq({ low, high + radius }, { Config.body.low, Config.body.high + Config.body.radius })
		t.near(radius, Config.body.radius + 0.3, 1e-9)
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
		t.eq((Body :: any).isSprinting, nil, "nobody reads sprint from a measured speed: the sprint bit is the fact")
		-- the match's feel is what the speeds, the pace and the crouch are read with
		local quick = Contract.feel({ sprintMult = 1.6, crouchSecs = 0.1 })
		t.near(Body.speed(0, true, quick), Body.WALK * 1.6, 1e-9)
		t.eq(Body.speed(0, false, quick), Body.WALK)
		t.near(Body.pace(0, 1, quick), 1.6, 1e-9)
		t.near(Body.crouchStep(0, true, 0.05, quick), 0.5, 1e-9)
		t.near(Body.crouchStep(0, true, 0.05), 0.25, 1e-9)
		-- sprint and the marker: the server's gate is the client's less one send interval
		t.eq(Body.SPRINT_FIRE_DELAY, 0.15)
		t.near(Contract.MARGIN.sprint, 1 / Clock.SEND_HZ, 1e-12)
		t.truthy(Body.SPRINT_FIRE_DELAY - Contract.MARGIN.sprint > 0)
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
		-- the rooms' low cover is a little higher than a rail: a standing eye near it cannot reach over onto the
		-- crown of a crouched head (settled at the join; tools/games/paintball/arena/LowCover)
		t.truthy(Arena.COVER_HEIGHT >= Body.CROUCH_TOP + 0.3, "low cover hides the crown from a standing eye nearby")
		t.truthy(Body.STAND_EYE - R.ballRadius > Arena.COVER_HEIGHT, "a standing eye shoots over low cover")
		t.truthy(Body.JUMP_HEIGHT < Arena.COVER_HEIGHT - Arena.STEP_UP, "a jump does not clear low cover")
		-- with the ball test itself: a rail on the atrium's edge of the stand-in arena
		local arena = ArenaData.build()
		local y = Arena.FLOOR_HEIGHT
		local x0, x1 = Arena.ATRIUM + 6, -Arena.ATRIUM - 6
		t.truthy(arena.sweep(x0, y + Body.CROUCH_EYE, 0, x1, y + Body.CROUCH_EYE, 0) ~= nil, "crouched: blocked")
		t.eq((arena.sweep(x0, y + Body.STAND_EYE, 0, x1, y + Body.STAND_EYE, 0)), nil)
		t.eq(Arena.EYE, Body.STAND_EYE)
	end)

	t.test("PB-3, PB-5: the hit test: a ball is its centre line, a body is hit where it is entered", function()
		-- the capsule alone: axis x = 0, z = 0, from 1 to 4.1 above the feet, radius 1.5 (a standing body)
		local low, high, r = Body.capsule(0)
		t.near(
			Hit.capsule(-5, 2, 0, 5, 2, 0, 0, low, high, 0, r) :: number,
			0.35,
			1e-9,
			"the side, where it is entered"
		)
		t.near(Hit.capsule(0, 10, 0, 0, 0, 0, 0, low, high, 0, r) :: number, 0.44, 1e-9, "the round top")
		t.eq(Hit.capsule(-5, 2, 1.6, 5, 2, 1.6, 0, low, high, 0, r), nil, "a miss by a tenth of a stud")
		t.eq(Hit.capsule(-5, 5.7, 0, 5, 5.7, 0, 0, low, high, 0, r), nil, "over the head")
		t.eq(Hit.capsule(0.5, 3, 0, 9, 3, 0, 0, low, high, 0, r), 0, "a step that starts inside")
		t.eq(Hit.capsule(-5, 2, 0, -2, 2, 0, 0, low, high, 0, r), nil, "a step that stops short")
		local under = Hit.capsule(-3, -2, 0, 3, 4, 0, 0, low, high, 0, r) :: number
		t.truthy(under > 0 and under < 0.5, "up into the round bottom")
		local ex, ey = -3 + 6 * under, -2 + 6 * under
		t.near(math.sqrt(ex * ex + (ey - low) ^ 2), r, 1e-9, "the entry point is on the shape")
		-- nothing is added for the ball: the reach is the hit shape's radius, so the entry is 1.5 from the axis
		local s = Hit.capsule(-5, 2, 0, 5, 2, 0, 0, low, high, 0, r) :: number
		t.near(-5 + 10 * s, -Body.HIT_RADIUS, 1e-9)
		-- the hit shape is wider than the body, never taller: its top is the body's top, standing and crouched
		for _, c in { 0, 0.5, 1 } do
			local cl, ch, cr = Body.capsule(c)
			t.near(ch + cr, Body.top(c), 1e-9)
			t.truthy(ch >= cl)
		end
		t.eq(Body.HIT_RADIUS, Body.RADIUS + 0.3)

		-- a body crouched behind the atrium rail of the stand-in arena (the rail's faces are at x = 15 and 15.5)
		local arena = ArenaData.build()
		local y = Arena.FLOOR_HEIGHT
		local railTop = y + Arena.RAIL_HEIGHT
		local bx = Arena.ATRIUM + 0.5 + 0.6 -- pressed against the rail: its shape pokes 0.1 out of the far face
		t.truthy(bx - Body.HIT_RADIUS < Arena.ATRIUM, "the shape does poke through the rail")
		-- (1) a level ball 0.05 above the rail passes over a fully crouched body, and tags a standing one
		local over = railTop + 0.05
		t.eq((arena.sweep(-10, over, 0, 30, over, 0)), nil, "the ball clears the rail")
		t.eq((Hit.body(arena.sweep, -10, over, 0, 30, over, 0, bx, y, 0, 1)), nil, "crouched: not tagged over the rail")
		t.truthy(Hit.body(arena.sweep, -10, over, 0, 30, over, 0, bx, y, 0, 0) ~= nil, "standing: tagged")
		-- (the S18 test, with the ball's radius added to the body, tagged the crouched one)
		local cl, ch = Body.capsule(1)
		t.truthy(Ballistics.segmentCapsule(-10, over, 0, 30, over, 0, bx, y + cl, y + ch, 0, r + R.ballRadius) ~= nil)
		-- (2) a ball at the crouched body's middle whose tick ends just short of the rail, inside the part
		-- of the shape that pokes through: the old test called it a hit; the entry is covered, so it is none
		local mid = y + 1.5 -- (on the crouched shape's upright side, between its axis's ends)
		local stop = Arena.ATRIUM - 0.05
		t.truthy(Ballistics.segmentCapsule(13.5, mid, 0, stop, mid, 0, bx, y + cl, y + ch, 0, r) ~= nil)
		t.truthy(Hit.capsule(13.5, mid, 0, stop, mid, 0, bx, y + cl, y + ch, 0, r) ~= nil, "the shape is entered")
		t.eq((Hit.body(arena.sweep, 13.5, mid, 0, stop, mid, 0, bx, y, 0, 1)), nil, "but the rail stands between")
		-- the next tick starts inside the shape, still covered, and the ball stops on the rail where it is drawn
		t.eq((Hit.body(arena.sweep, stop, mid, 0, stop + 1.5, mid, 0, bx, y, 0, 1)), nil)
		local ws, nx = arena.sweep(stop, mid, 0, stop + 1.5, mid, 0)
		t.truthy(ws ~= nil and nx == -1, "the rail's atrium face")
		-- (3) the same body with no rail in the way is hit at the entry point, which is what is reported
		local hs, hx, hy, hz = Hit.body(arena.sweep, 30, mid, 0, 14, mid, 0, bx, y, 0, 1)
		t.truthy(hs ~= nil)
		t.near(hx, bx + Body.HIT_RADIUS, 1e-9)
		t.deepEq({ hy, hz }, { mid, 0 })
		-- a ball flies under 3.4 studs a tick even at the fastest feel: the entry test loses nothing between ticks
		t.truthy(Contract.FEEL_RANGE.ballSpeed[2] / Clock.TICK_HZ < 2 * Body.RADIUS + 1)
	end)

	t.test("trust: the numbers behind the move checks, and a path round a corner", function()
		local T = Contract.TRUST
		-- a walker's budget never runs dry and a sprinter's bit buys sprint pace
		t.truthy(T.speedTolerance > 1 and T.speedTolerance <= 1.25)
		t.truthy(T.moveGap >= 2 / Clock.SEND_HZ, "one lost Move costs nothing")
		-- the store holds a gap of lost Moves and one Move more, and no more (the review: half a second of it was a
		-- ten-stud jump in one Move, or two seconds of sprint pace without the bit)
		t.truthy(T.speedWindow >= T.moveGap + 1 / Clock.SEND_HZ - 1e-9)
		t.truthy(
			Body.WALK * T.speedTolerance * T.speedWindow < 2 * 2 * Body.RADIUS,
			"under two body widths in one Move"
		)
		t.truthy(T.moveAge <= Clock.HISTORY_SECS)
		-- falling: the whole building is a shorter fall than the longest a body may be unsupported
		t.truthy(T.fallSecs > math.sqrt(2 * Arena.HEIGHT / 196.2))
		t.truthy(Body.JUMP_HEIGHT + T.jumpSlack < Arena.FLOOR_HEIGHT / 2, "a storey is never a jump")
		-- a shot's origin: a crouched body that stays crouched cannot claim an eye over the rail
		t.truthy(Body.CROUCH_EYE + T.originSlackY < Arena.RAIL_HEIGHT)
		t.truthy(T.originSlack <= Body.RADIUS, "the origin is inside the body it came from")
		-- the client's gates are the stricter by these
		local M = Contract.MARGIN
		t.truthy(M.room >= Body.WALK / Clock.SEND_HZ + T.originSlack, "a step past the newest Move is still clear")
		t.truthy(M.gate > 0 and M.gate < 1 / Clock.SEND_HZ)
		t.truthy(T.clockSlack >= M.gate)
		-- the cost, shared out under the checklist's 1.5 ms
		local C = Contract.COST
		t.truthy(C.ballsMs + C.botsMs + C.restMs <= C.totalMs)
		t.eq(C.totalMs, 1.5)
		t.eq(C.atBots, R.slots - 1)
		-- Arena.clearPath: the straight line, or either L (a pillar's corner cut by a lost pose)
		local boxes = { 2, 0, 2, 6, 10, 6 }
		local function sweep(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number)
			return Arena.sweepBoxes(boxes, x0, y0, z0, x1, y1, z1)
		end
		t.truthy(Arena.clearPath(sweep, 0, 0, 1, 8, 2.5), "nothing in the way")
		t.truthy(sweep(0, 2.5, 1, 7, 2.5, 5) ~= nil, "the straight line cuts the corner")
		t.truthy(Arena.clearPath(sweep, 0, 1, 7, 5, 2.5), "along x then along z is clear")
		t.truthy(Arena.clearPath(sweep, 1, 0, 5, 7, 2.5), "along z then along x is clear")
		t.falsy(Arena.clearPath(sweep, 0, 4, 8, 4, 2.5), "straight through the pillar: no L helps")
		t.falsy(Arena.clearPath(sweep, 4, 4, 8, 8, 2.5), "from inside it")
		t.truthy(Arena.clearPath(sweep, 0, 4, 8, 4, 11), "over it")
		-- a room, and a room grown sideways (the client's no-fire margin round a spawn room)
		local room: Arena.Room = { minX = 0, minY = 28, minZ = 0, maxX = 10, maxY = 34, maxZ = 10 }
		t.truthy(Arena.inRoom(room, 5, 28.1, 5))
		t.falsy(Arena.inRoom(room, 11, 28.1, 5))
		t.truthy(Arena.inRoom(room, 11, 28.1, 5, M.room))
		t.falsy(Arena.inRoom(room, 5, 27, 5, M.room), "the margin is sideways only")
	end)

	t.test("time: the rates, and the history is long enough for the furthest rewind", function()
		t.eq(Clock.TICK_HZ, 60)
		t.eq(Clock.SNAP_HZ, 20)
		t.eq(Clock.SEND_HZ, 20)
		t.near(Clock.INTERP_SECS, 2 / Clock.SNAP_HZ, 1e-12)
		t.eq(Clock.HISTORY_SECS, 1.0)
		t.eq(Tunables.tree.paintball.lagHistorySecs.v, Clock.HISTORY_SECS)
		-- the furthest back a ball is judged: a 300 ms round trip (half of it down, plus the interpolation
		-- delay), and no longer: it is how long after ducking a body can still be tagged
		t.eq(Clock.MAX_REWIND, 0.25)
		t.truthy(Clock.MAX_REWIND <= Config.maxRewindSecs)
		t.near(0.15 + Clock.INTERP_SECS, Clock.MAX_REWIND, 1e-12)
		-- a ball flown forward by MAX_LATE and rewound by MAX_REWIND still reads inside the history
		t.truthy(Clock.MAX_LATE + Clock.MAX_REWIND + 1 / Clock.SNAP_HZ < Clock.HISTORY_SECS)
		-- 150 ms of round trip is inside the clamp with the whole tolerance to spare
		t.truthy(0.075 + Clock.INTERP_SECS + Clock.REWIND_TOLERANCE <= Clock.MAX_REWIND)
		t.truthy(Clock.STALE_SECS < Clock.DROP_SECS)
		t.eq((Clock :: any).SYNC_SLACK, nil, "the model is slaved to the shared clock: there is no slack to keep")
		-- the Moves the server keeps reach back past any fire time and any pose time it will ask for
		t.truthy(Clock.MOVES_KEPT / Clock.SEND_HZ > Clock.MAX_LATE + 2 / Clock.SEND_HZ)
		t.truthy(Clock.MAG_LATE >= Clock.MAX_LATE and Clock.MAG_LATE / F.fireInterval <= 2)
		t.truthy(Clock.AUDIENCE_SECS <= 1, "somebody walking in sees the match within a second")
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

	t.test("time: a shot's stamps are clamped: fire time, lateness, rewind, and the magazine's own time", function()
		-- an honest shot at 150 ms round trip: 75 ms up, 75 ms down + interpolation
		local now = 100
		local up = 0.075
		local ft = now - up
		local vt = ft - (0.075 + Clock.INTERP_SECS)
		local f, late, rewind, clamped, m = Clock.stamp(now, vt, ft, nil, up)
		t.near(f, ft, 1e-9)
		t.near(late, 0.075, 1e-9)
		t.near(rewind, 0.175, 1e-9)
		t.falsy(clamped)
		t.eq(m, ft, "an honest magazine time is the click")
		-- a fire time from the future: the ball is born now; the magazine may be judged a clock's slack ahead
		local f2, _, _, _, m2 = Clock.stamp(now, now - 0.2, now + 5, nil, nil)
		t.eq(f2, now)
		t.eq(m2, now + Contract.TRUST.clockSlack)
		-- a fire time from the distant past, with no measure of the way up: MAX_LATE, and MAG_LATE
		local f3, _, _, _, m3 = Clock.stamp(now, now - 0.2, now - 5, nil, nil)
		t.eq(f3, now - Clock.MAX_LATE)
		t.eq(m3, now - Clock.MAG_LATE)
		-- THE LIAR'S BOUND: a client that always claims the oldest fire time is held to its own measured
		-- delay plus the tolerance, not to MAX_LATE: under 7 studs of free flight, not 22
		local f4, late4 = Clock.stamp(now, now - 0.5, now - Clock.MAX_LATE, nil, 0.02)
		t.near(late4, 0.02 + Clock.REWIND_TOLERANCE, 1e-9)
		t.near(f4, now - 0.095, 1e-9)
		t.truthy(late4 * F.ballSpeed < 15)
		-- and its rewind to the estimate's edge (the way down taken to be as long as the way up)
		local _, _, r4, c4 = Clock.stamp(now, now - 0.5, now - Clock.MAX_LATE, nil, 0.02)
		t.near(r4, 0.02 + Clock.INTERP_SECS + Clock.REWIND_TOLERANCE, 1e-9)
		t.truthy(c4)
		-- HONEST SHOTS THE NETWORK BUNCHED: three clicks a fire interval apart all arrive together half a
		-- second late. Each ball is born as late as allowed, and each magazine time keeps its own stamp,
		-- so the magazine refuses none of them
		local mag = Magazine.new(R.magazine, F.fireInterval, F.reloadSecs)
		local arrive = 50.5
		local lastM: number? = nil
		for i = 0, 2 do
			local click = 50 + i * F.fireInterval
			local bf, _, _, _, bm = Clock.stamp(arrive, click - 0.15, click, lastM, 0.05)
			t.eq(bm, click, `shot {i + 1} keeps its own time`)
			t.truthy(bf >= arrive - Clock.MAX_LATE and bf <= arrive)
			t.truthy(Magazine.fire(mag, bm), `shot {i + 1} is not "too fast"`)
			lastM = bm
		end
		-- a magazine time never runs back behind the shooter's last one
		t.eq(select(5, Clock.stamp(now, now - 0.2, now - 0.3, now - 0.1, nil)), now - 0.1)
		-- a view time claimed far in the past is held at MAX_REWIND, and at the estimate's edge
		local _, _, r1, c1 = Clock.stamp(now, now - 3, now, nil, nil)
		t.eq(r1, Clock.MAX_REWIND)
		t.truthy(c1)
		local _, _, r2 = Clock.stamp(now, now - 3, now, nil, 0.05)
		t.near(r2, 0.05 + Clock.INTERP_SECS + Clock.REWIND_TOLERANCE, 1e-9)
		local _, _, r3 = Clock.stamp(now, now + 1, now, nil, 0.075)
		t.near(r3, 0.075 + Clock.INTERP_SECS - Clock.REWIND_TOLERANCE, 1e-9)
		-- WITH THE ROUND TRIP THE SERVER MEASURES (the review): a client on a fast link that stamps its Moves
		-- early, to look slow, is held to the link it really has ...
		local _, lateL, rL = Clock.stamp(now, now - 0.5, now - Clock.MAX_LATE, nil, 0.2, 0.03)
		t.near(lateL, 0.03 + Clock.REWIND_TOLERANCE, 1e-9, "the way up is no longer than the round trip")
		t.near(rL, 0.03 + Clock.INTERP_SECS + Clock.REWIND_TOLERANCE, 1e-9, "nor is the way down")
		-- ... and an honest link whose two ways differ keeps the rewind it saw: 17 ms up and 150 down
		local ftA = now - 0.017
		local _, _, rA, cA = Clock.stamp(now, ftA - 0.15 - Clock.INTERP_SECS, ftA, nil, 0.017, 0.167)
		t.near(rA, 0.15 + Clock.INTERP_SECS, 1e-9)
		t.falsy(cA, "not clamped (centred on the way up taken twice, it was: 0.042 to 0.192)")
		-- past MAX_REWIND both the shooter's drawing and the server clamp alike
		local ftB = now - 0.033
		local _, _, rB = Clock.stamp(now, ftB - 0.266 - Clock.INTERP_SECS, ftB, nil, 0.033, 0.3)
		t.eq(rB, Clock.MAX_REWIND)
		t.eq(select(3, Clock.stamp(now, now + 1, now, nil, nil)), 0)
		-- a slow connection is covered to a 300 ms round trip and held there beyond it
		local _, _, r5, c5 = Clock.stamp(now, now - 0.125 - 0.225, now - 0.125, nil, 0.125)
		t.near(r5, 0.225, 1e-9)
		t.falsy(c5)
		local _, _, r6, c6 = Clock.stamp(now, now - 0.2 - 0.3, now - 0.2, nil, 0.2)
		t.eq(r6, Clock.MAX_REWIND)
		t.truthy(c6)
	end)

	t.test("time: a person's pose for a snapshot is read one send interval behind its Moves", function()
		-- Moves sampled SEND_HZ times a second arrive 40 ms later with a few ms of jitter; the server reads
		-- the pose at poseTime, and there is a Move on each side of that time at every snapshot tick
		local up = Clock.newView()
		local arrivals: { { t: number, at: number } } = {}
		for i = 0, 60 do
			local sampled = i / Clock.SEND_HZ + 0.013
			table.insert(arrivals, { t = sampled, at = sampled + 0.04 + (i % 3) * 0.004 })
		end
		local have: { number } = {}
		local last = -math.huge
		local checked = 0
		for frame = 0, 180 do
			local now = frame / Clock.TICK_HZ
			while arrivals[1] and arrivals[1].at <= now do
				local a = table.remove(arrivals, 1) :: { t: number, at: number }
				Clock.observe(up, a.t, a.at)
				table.insert(have, a.t)
			end
			if frame % (Clock.TICK_HZ // Clock.SNAP_HZ) == 0 and #have >= 4 then
				local pt = Clock.poseTime(up, now)
				t.truthy(pt >= last, "the pose time never runs back")
				last = pt
				t.truthy(pt <= have[#have] + 0.005, `tick {frame}: a Move at the pose time, or within a few ms of it`)
				t.truthy(pt >= have[#have - 3], `tick {frame}: and the pose time is no further back than it need be`)
				checked += 1
			end
		end
		t.truthy(checked > 40)
		t.near(up.lag :: number, 0.045, 0.01)
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
		-- (the server's measure of this shooter's way up is `up`; its way down is 20 ms longer, inside the tolerance)
		local f, late, rewind, clamped = Clock.stamp(now, vt, ft, nil, up)
		t.near(late, up, 1e-9)
		t.near(rewind, down + Clock.INTERP_SECS, 1e-9)
		t.falsy(clamped)
		-- aimed, on the shooter's screen, at where the drawn body will be when a flat ball gets there
		local dist = 30
		local tof = dist / F.ballSpeed
		local ax, ay, az = PoseHistory.sample(history, vt)
		local lead = Body.SPRINT * tof
		local vx, vy, vz = Ballistics.aim(ax + lead, ay + 3, az - dist, ax + lead, ay + 3, az, F.ballSpeed, F.ballDrop)
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
				["Paintball.Move"] = { "c2s", false, 28 },
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
			t.truthy(Wire.REMOTES["Paintball.Fire"].rate :: number >= 1.5 / F.fireInterval)
			-- the placement number a Move carries: 0 before the first, then 1 to PLACE_MAX and round again
			t.eq(Wire.nextPlace(0), 1)
			t.eq(Wire.nextPlace(7), 8)
			t.eq(Wire.nextPlace(Wire.PLACE_MAX), 1)
			t.eq(Wire.PLACE_MAX, 255)
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
			local move =
				{ t = 12.5, seq = 9, x = 1.5, y = 14, z = -20.25, yaw = 1, pitch = -0.5, bits = bits, place = 3 }
			t.truthy(net:receive(p, "Paintball.Move", BufferCodec.encode(Wire.Move, move), 0))
			t.eq(got["Paintball.Move"].t, 12.5)
			t.eq(got["Paintball.Move"].z, -20.25)
			t.near(got["Paintball.Move"].yaw, 1, 1e-4)
			t.near(got["Paintball.Move"].pitch, -0.5, 1e-4)
			t.truthy(Wire.has(got["Paintball.Move"].bits, Wire.BIT.crouch))
			t.falsy(Wire.has(got["Paintball.Move"].bits, Wire.BIT.sprint))
			t.eq(got["Paintball.Move"].place, 3, "the placement the client last obeyed rides on every pose")
			t.deepEq({ net:receive(p, "Paintball.Move", buffer.create(27), 0) }, { false, "bad buffer" })
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
			-- R goes the framework's way, with its stamp; so does a change of side
			t.deepEq(Wire.VERBS, { "reload", "side" })
			t.deepEq(Spec.verbs, Wire.VERBS)
			local input = Schemas.REMOTES["Minigame.Input"].payload :: any
			t.truthy(Schema.check(input, { gameId = Contract.STATION, seat = 3, verb = "reload", args = { 1000.25 } }))
			t.truthy(Schema.check(input, { gameId = Contract.STATION, seat = 3, verb = "side", args = {} }))
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
					{ id = 1, team = 1, name = "Ada", bot = false, user = 1234567 },
					{ id = 2, team = 1, name = "Rusty (computer)", bot = true, user = 0 },
				},
				now = 5,
				feel = Contract.feel({ ballSpeed = 120 }),
				station = Contract.STATION,
			},
			{ kind = "paintball_unwatch", station = Contract.STATION },
			{
				kind = "paintball_tag",
				by = 2,
				id = 1,
				ball = 17,
				scores = { 0, 1 },
				tags = 3,
				outs = 2,
				at = 9,
				x = 0,
				y = 1,
				z = 2,
			},
			{ kind = "paintball_respawn", id = 1, x = 0, y = 0, z = 0, yaw = 0, at = 11, place = 4 },
			{ kind = "paintball_reload", id = 1, at = 12 },
			{ kind = "paintball_say", id = 3, line = "floor", n = 3 },
			{ kind = "paintball_tuned", text = "Ball speed: 150 -> 120, from the next match" },
			{ kind = "paintball_ack", shot = 4, ok = true, ball = 17, rounds = 4 },
			{ kind = "paintball_ack", shot = 5, ok = false, why = "sprint", rounds = 4, reloadAt = 12 },
			{
				kind = "paintball_correct",
				x = 0,
				y = 0,
				z = 0,
				yaw = 0,
				why = "speed",
				place = 5,
				station = Contract.STATION,
			},
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
		t.eq(kinds, 9)
		t.falsy((Wire.checkMessage({ kind = "paintball_tag", by = 2, id = 1 })))
		t.falsy((Wire.checkMessage({
			kind = "paintball_tag",
			by = 2,
			id = 99,
			ball = 1,
			scores = { 0, 1 },
			tags = 1,
			outs = 1,
			at = 9,
			x = 0,
			y = 1,
			z = 2,
		})))
		t.falsy((Wire.checkMessage({
			kind = "paintball_correct",
			x = 0,
			y = 0,
			z = 0,
			yaw = 0,
			why = "because",
			place = 1,
		})))
		-- a placement always says its number, and a watcher is always told the feel and whose body is whose
		t.falsy((Wire.checkMessage({ kind = "paintball_respawn", id = 1, x = 0, y = 0, z = 0, yaw = 0, at = 11 })))
		t.falsy((Wire.checkMessage({ kind = "paintball_correct", x = 0, y = 0, z = 0, yaw = 0, why = "wall" })))
		t.falsy((Wire.checkMessage({ kind = "paintball_watch", match = 2, slots = {}, now = 5 })))
		t.falsy((Wire.checkMessage({
			kind = "paintball_watch",
			match = 2,
			slots = { { id = 1, team = 1, name = "Ada", bot = false } },
			now = 5,
			feel = Contract.feel(),
		})))
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

	t.test("wire: at 8 v 8 a player costs under 8 kB/s of stream, 11.5 kB/s in all, and 1.5 kB/s up", function()
		local b = Wire.budget(R.slots)
		t.eq(b.snap, 220)
		t.truthy(b.stream < 8000, `stream {b.stream}`)
		-- the table messages are counted too: the framework's "state" for sixteen seats is the most of it,
		-- which is why a tag does not send one
		t.truthy(b.tables > 2000 and b.tables < 4000, `tables {b.tables}`)
		t.near(b.down, b.stream + b.tables, 1e-9)
		t.truthy(b.down < 11500, `down {b.down}`)
		t.truthy(b.up < 1500, `up {b.up}`)
		t.truthy(Wire.budget(2 * R.teamMin).down < b.down)
		-- once, on coming into the audience: both splat pools, full
		t.eq(b.join, (R.splatPool + R.slots * R.bodySplats) * Wire.Splat.size)
		t.truthy(b.join < 18000)
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
		-- THE SPAWN ROOMS (decision 12): on the middle storey, opposite each other, a curtain in each doorway
		t.eq(Arena.SPAWN_FLOOR, Arena.FLOORS // 2)
		local midY = Arena.SPAWN_FLOOR * Arena.FLOOR_HEIGHT
		for team = 1, 2 do
			local room = arena.spawnRooms[team]
			t.eq(room.minY, midY, `team {team}'s room is on the middle storey`)
			t.eq(#arena.curtains[team], 2)
			for _, sp in arena.spawns[team] do
				t.truthy(Arena.inRoom(room, sp.x, sp.y + 0.1, sp.z))
				-- a spawn point looks along the room, not into the wall behind it
				local dx, _, dz = Body.look(sp.yaw, 0)
				t.eq((arena.sweep(sp.x, sp.y + Arena.EYE, sp.z, sp.x + dx * 3, sp.y + Arena.EYE, sp.z + dz * 3)), nil)
			end
			for _, curtain in arena.curtains[team] do
				-- a curtain is air (a ball and a team-mate pass), and it touches the room it shuts
				local cx, cy, cz =
					(curtain.minX + curtain.maxX) / 2, curtain.minY + Arena.CHEST, (curtain.minZ + curtain.maxZ) / 2
				t.eq((arena.sweep(cx, cy, cz, cx, cy, cz)), nil)
				t.truthy(Arena.inRoom(room, cx, cy, cz, 1.5), "a curtain hangs in a doorway of its room")
			end
		end
		t.truthy(arena.spawnRooms[1].maxX < 0 and arena.spawnRooms[2].minX > 0, "one room on each side")
		-- an opponent standing in a doorway sees a baffle wall, not the spawn points
		local door = arena.curtains[1][1]
		local ex, ez = (door.minX + door.maxX) / 2, (door.minZ + door.maxZ) / 2
		for i, sp in arena.spawns[1] do
			t.truthy(
				arena.sweep(ex, midY + Arena.EYE, ez, sp.x, sp.y + Arena.CHEST, sp.z) ~= nil,
				`spawn point {i} is hidden from the doorway`
			)
		end
		-- THE STAIRS GO ON UP: from the ground to the top floor on one side is four flights and three
		-- short steps across a landing, each flight's head beside the next one's foot
		local stairs: { Arena.NavLink } = {}
		for _, link in arena.links do
			if link.kind == "stair" then
				table.insert(stairs, link)
			end
		end
		t.eq(#stairs, 2 * (Arena.FLOORS - 1))
		for _, link in stairs do
			local head = arena.nodes[link.b]
			if head.floor < Arena.FLOORS - 1 then
				local near = math.huge
				for _, other in stairs do
					local foot = arena.nodes[other.a]
					if foot.floor == head.floor then
						near = math.min(near, math.sqrt((foot.x - head.x) ^ 2 + (foot.z - head.z) ^ 2))
					end
				end
				t.truthy(near <= Arena.STAIR_GAP, `the flight to floor {head.floor} goes on up within {near} studs`)
			end
		end
		-- a body may drop off a stair's open side: there is ground under it, and nothing in the way
		local flight = arena.ramps[1]
		local sideZ = if math.abs(flight.minZ) < math.abs(flight.maxZ) then flight.minZ else flight.maxZ
		local inward = if sideZ > 0 then -1 else 1
		local halfway = (flight.y0 + flight.y1) / 2
		t.eq(arena.ground(0, halfway, sideZ + inward * 2), 0, "the ground floor is under the stair's open side")
		t.eq((arena.sweep(0, halfway + Arena.CHEST, sideZ - inward, 0, halfway + Arena.CHEST, sideZ + inward * 2)), nil)
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
		-- and the rules of the spawn room (decision 12), one broken at a time
		local function broken(change: (a: Arena.Arena) -> ()): string
			local a = ArenaData.build()
			change(a)
			local fine, list = Arena.check(a, R.teamMax)
			t.falsy(fine)
			return table.concat(list, "; ")
		end
		local function says(text: string, part: string)
			t.truthy(string.find(text, part, 1, true) ~= nil, `'{part}' in: {text}`)
		end
		-- a spawn point in the corridor behind a door: whoever stands outside that door sees it
		says(
			broken(function(a)
				local sp = a.spawns[1][1]
				sp.x, sp.z = -57.5, -9.5
			end),
			"team 1's spawn points can be seen from outside the room"
		)
		-- a room that is not on the middle storey
		says(
			broken(function(a)
				a.spawnRooms[2].minY = 0
			end),
			"team 2's spawn room is not on the middle storey"
		)
		-- a doorway with no curtain
		says(
			broken(function(a)
				a.curtains[1] = { a.curtains[1][1] }
			end),
			"team 1's spawn room needs a curtain in each doorway"
		)
		-- one way out only: the link through one of the doors is gone
		says(
			broken(function(a)
				for i, link in a.links do
					local from, to = a.nodes[link.a], a.nodes[link.b]
					if link.kind == "walk" and from.team == 1 and to.team == 0 then
						table.remove(a.links, i)
						break
					end
				end
			end),
			"team 1's spawn room needs two ways out"
		)
		-- stairs that do not go on up: a flight's foot dragged to the far end of the building
		says(
			broken(function(a)
				for _, link in a.links do
					local foot = a.nodes[link.a]
					if link.kind == "stair" and foot.floor == 1 then
						foot.x, foot.z = 40, 40
					end
				end
			end),
			"studs from the next flight up"
		)
		-- rooms side by side: nowhere is far from a respawn, but one team walks out into the other
		says(
			broken(function(a)
				a.spawnRooms[2] = table.clone(a.spawnRooms[1])
			end),
			"the spawn rooms are not on opposite sides of the building"
		)
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
				t.isType(client.sounds[`paintball.{cue}`], "string", cue)
			end
			-- the owner's bar asks for distinct audio for fire and hits: a silent marker fails the gate (found at
			-- the review: every id was empty). Placeholders until his licensed set; the fire and the two hits
			-- are not one sound
			for _, cue in { "fire", "tag", "tagged", "dry", "splat" } do
				t.truthy(client.sounds[`paintball.{cue}`] ~= "", `paintball.{cue} has a sound`)
			end
			t.truthy(client.sounds["paintball.fire"] ~= client.sounds["paintball.tag"])
			t.truthy(client.sounds["paintball.tag"] ~= client.sounds["paintball.tagged"])
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
			t.falsy(state.synced)
			Session.step(s, 4)
			local before = state.now
			t.truthy(before > 0 and before <= 4)
			local left = state.endsAt - state.now
			Rules.sync(state, 1000)
			t.truthy(state.synced)
			t.eq(state.now, 1000)
			t.near(state.endsAt - state.now, left, 1e-9, "the first sync moved every time in the State with it")
			t.near(Rules.view(state).endsAt, 1000 + left, 1e-9)
			-- from then on it is SLAVED to the shared clock: a step adds nothing of its own, and a later sync
			-- sets the clock and moves no other time (a server hitch must not push a magazine or a respawn late)
			local endsAt = state.endsAt
			local slot1 = Rules.slot(state, 1) :: Rules.Slot
			slot1.mag.nextFireAt = 1000.25
			slot1.safeUntil = 1002
			Rules.step(state, 0.1)
			t.eq(state.now, 1000, "a step does not count a clock of its own")
			Rules.sync(state, 1000.4)
			t.eq(state.now, 1000.4)
			t.eq(state.endsAt, endsAt)
			t.eq(slot1.mag.nextFireAt, 1000.25)
			t.eq(slot1.safeUntil, 1002)
			-- nothing fires, tags or ends on a clock nobody has run out
			t.eq(Rules.result(state), nil)
			t.deepEq(Rules.drain(state), {})
		end
	)

	t.test(
		"teams: a slot's team is its own: dealt by seat, kept by the seat, levelled by who joins, changed by assign",
		function()
			local state = Rules.init(3, 1)
			t.deepEq({ state.slots[1].team, state.slots[2].team, state.slots[3].team }, { 1, 2, 1 })
			-- a new seat joins the smaller side, whatever its number; level sides fall back on the seat's parity
			Rules.join(state, 4)
			t.eq(state.slots[4].team, 2)
			Rules.join(state, 5)
			t.eq(state.slots[5].team, Contract.teamOf(5))
			-- two friends on one side (the "side" verb; people kept together at the next match): the bots
			-- that fill the match then all join the other side until it is level
			local match = Rules.init(2, 1)
			t.truthy(Rules.assign(match, 2, 1))
			t.falsy(Rules.assign(match, 2, 1), "already there")
			t.falsy(Rules.assign(match, 9, 1), "no such slot")
			for seat = 3, 8 do
				Rules.join(match, seat)
			end
			local sides = { 0, 0 }
			for _, slot in match.slots do
				sides[slot.team] += 1
			end
			t.deepEq(sides, { 4, 4 })
			t.deepEq({ match.slots[1].team, match.slots[2].team }, { 1, 1 }, "the friends are still together")
			t.eq(Rules.view(match).slots[2].team, 1, "and that is the team everybody is told")
			-- a seat keeps its side when it changes hands: a person takes a bot's seat, a bot a person's
			Rules.gone(match, 2)
			Rules.join(match, 2)
			t.eq(match.slots[2].team, 1)
			t.truthy(match.slots[2].on)
			-- the feel is the match's own, and tune rebuilds the magazines with it
			t.deepEq(match.feel, Contract.FEEL)
			Rules.tune(match, Contract.feel({ fireInterval = 0.4, reloadSecs = 2 }))
			t.eq(match.feel.fireInterval, 0.4)
			t.eq(match.slots[1].mag.fireInterval, 0.4)
			t.eq(match.slots[1].mag.reloadSecs, 2)
			t.eq(match.slots[1].mag.rounds, R.magazine)
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
			"tune",
			"sync",
			"step",
			"join",
			"gone",
			"assign",
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
		has(Hit, { "capsule", "body" }, "Hit")
		t.eq(Arena.MODEL, "PaintballArena")
		t.eq(Arena.MONITOR, "Monitor")
		t.eq(Arena.CURTAIN, "Curtain")
		-- the service on a bare framework context (no site model, no net, and no engine at all under this
		-- runner): inert, and every hook is there. Built where the arena is not, it touches nothing
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
			"command",
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
		-- the framework's own table verbs are not a player's to send: the match starts, rolls on and fills itself
		for _, verb in { "start", "again", "addai", "mode" } do
			t.deepEq({ service:command("ada", verb, {}) }, { true, false, "Not now." }, verb)
		end
		t.eq((service:command("ada", "leave", {})), false, "leaving is the framework's")
		-- the feel of the next match is the service's to hold, and one number of it can be turned (the playtest)
		t.deepEq(service.feel, Contract.FEEL)
		t.deepEq({ service:debug("tune", "ballSpeed", 120) }, { true, nil })
		t.eq(service.feel.ballSpeed, 120)
		t.eq(service.feel.ballDrop, F.ballDrop)
		t.eq((service:debug("tune", "ballSpeed", 9000)), false)
		t.eq(service.feel.ballSpeed, 120, "a refused change changes nothing")
		local extras = service:state("ada", 1) :: Contract.Extras
		t.eq(extras.shot, 0)
		t.truthy(Schema.check(Wire.FEEL, extras.feel), "the Extras carry a feel the wire accepts")
		-- every stat the contract names is there to be reported
		local stats = service:stats() :: { [string]: number }
		for _, name in
			{
				"steps",
				"snapshots",
				"balls",
				"tags",
				"movesAccepted",
				"movesRefused",
				"movesDropped",
				"shotsRefused",
				"corrections",
				"rewindsClamped",
				"stepMs",
				"ballsMs",
				"botsMs",
				"restMs",
			}
		do
			t.isType(stats[name], "number", name)
		end
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
		-- (the client's seat and show are built where there is an engine: tests/isolated/paintball_contract)
		-- the match model and the bots line up: a fresh State steps through the bots without a word
		local state = Rules.init(1, 3)
		t.eq(state.phase, "briefing")
		local heard: { Bots.Heard } = {
			{ kind = "born", id = 2, x = 0, y = 4.5, z = 0, vx = 90, vy = 0, vz = 0 },
			{ kind = "ended", id = 2, x = 20, y = 4, z = 0 },
			{ kind = "tag", id = 1, by = 2, x = 20, y = 4, z = 0 },
		}
		t.deepEq(Bots.step(Bots.new(service.arena), state, {}, heard, 0, 1 / Clock.TICK_HZ), {})
		t.deepEq({ Rules.canFire(state, 1, 0) }, { false, "phase" })
		t.deepEq({ Rules.fire(state, 1, 0, 0) }, { false, "phase" })
		t.eq(Rules.tag(state, 1, 1, 0, 0), false)
		-- a bot is fair: it turns before it fires, it hears a near miss, it reacts no faster than a person
		local B = Contract.BOT
		t.truthy(B.reactMin >= 0.25 and B.reactMax <= 0.45 and B.reactMin < B.reactMax)
		t.truthy(B.turn <= 2 * math.pi + 1e-9, "half a turn takes half a second: the puppet is seen to turn")
		t.truthy(B.aimSlack <= math.rad(5))
		t.truthy(B.sightHalf < math.pi / 2, "nobody is seen from behind")
		t.truthy(B.hear >= 2 * Body.RADIUS)
		t.truthy(B.faced <= B.reactMin)
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
