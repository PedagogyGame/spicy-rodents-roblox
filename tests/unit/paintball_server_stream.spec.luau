--!strict
-- What the paintball service keeps for one person and how it judges what that person's client claims
-- (Server/Minigames/Paintball/Stream; Shared/Minigames/Paintball/Contract, "who is trusted for what"), and
-- the pass desk (Server/Minigames/Paintball/PassDesk; checklist PB-12). Pure: the whole-game cases are in
-- tests/unit/paintball_server.spec.luau. Here each rule is held on its own, with the contract's numbers, in
-- the stand-in building: the time rules, the distance budget and what refills it, the height rule (as the
-- contract words it, a hop taken off a ledge included, with the two things Stream adds: a body's footprint
-- at an edge, and a fall that must fall), the pose at a time, the sprint window, the origin of a shot, and
-- silence.
local ArenaData = require("@shared/Minigames/Paintball/ArenaData")
local ArenaModule = require("@shared/Minigames/Paintball/Arena")
local Body = require("@shared/Minigames/Paintball/Body")
local Clock = require("@shared/Minigames/Paintball/Clock")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Wire = require("@shared/Minigames/Paintball/Wire")
local PassDesk = require("@server/Minigames/Paintball/PassDesk")
local Stream = require("@server/Minigames/Paintball/Stream")

local T = Contract.TRUST
local SEND = 1 / Clock.SEND_HZ
local FLOOR = ArenaModule.FLOOR_HEIGHT

-- a person placed at (x, y, z) at time 100, and a way to hand it Moves
local function placed(
	x: number,
	y: number,
	z: number
): (
	Stream.Person,
	(rec: { [string]: number }, now: number?) -> (Stream.Verdict, string?),
	ArenaModule.Arena
)
	local arena = ArenaData.build()
	local feel = Contract.feel()
	local person = Stream.new("ada", 100)
	Stream.placed(person, x, y, z, 0, 100, feel, true)
	local function send(rec: { [string]: number }, now: number?): (Stream.Verdict, string?)
		local full: { [string]: number } = { yaw = 0, pitch = 0, bits = 0, place = person.place, x = x, y = y, z = z }
		for k, v in rec do
			full[k] = v
		end
		return Stream.judge(person, full, now or full.t, arena, feel, arena.spawnRooms[2])
	end
	return person, send, arena
end

return function(t)
	t.test(
		"a Move is dropped, not refused: before the first placement, with another placement number, out, or with a bad stamp",
		function()
			local feel = Contract.feel()
			local arena = ArenaData.build()
			local fresh = Stream.new("ada", 100)
			local rec = { t = 100, x = 20, y = 0, z = 0, yaw = 0, pitch = 0, bits = 0, place = 0 }
			t.eq(
				(Stream.judge(fresh, rec, 100, arena, feel)),
				"dropped",
				"nothing is judged before the first placement"
			)
			local person, send = placed(20, 0, 0)
			t.eq(person.place, 1)
			t.eq((send({ t = 100.05, place = 0 })), "dropped")
			t.eq((send({ t = 100.05, place = 2 })), "dropped")
			t.eq((send({ t = 100.05 })), "accepted")
			t.eq((send({ t = 100.05 }, 100.1)), "dropped", "not later than the last accepted")
			t.eq((send({ t = 100.04 }, 100.1)), "dropped", "an older one that arrived late")
			t.eq((send({ t = 100.1 + T.clockSlack + 0.01 }, 100.1)), "dropped", "from the future")
			t.eq((send({ t = 100.2 }, 100.2 + T.moveAge + 0.01)), "dropped", "too old")
			person.out = true
			t.eq((send({ t = 100.3 })), "dropped", "tagged out")
			t.eq(#person.moves, 1)
			t.eq(#person.refusals, 0)
			-- a placement number outlives a re-seating: the next one counts on from the last ever given
			local again = Stream.new("ada", 200, person.place)
			Stream.placed(again, 0, 0, 0, 0, 200, feel, true)
			t.eq(again.place, 2)
			again.place = Wire.PLACE_MAX
			Stream.placed(again, 0, 0, 0, 0, 201, feel, true)
			t.eq(again.place, 1, "and wraps past zero, which means none yet")
		end
	)

	t.test(
		"the distance budget: walking pace for a walker whatever the jitter, sprint pace only with the bit, half a second of burst and no more",
		function()
			local _, send = placed(20, 0, -40)
			local feel = Contract.feel()
			-- twenty Moves at walking pace; they ARRIVE bunched and late, and none is refused
			local z = -40
			for i = 1, 20 do
				z += Body.WALK * SEND
				local arrive = 100 + i * SEND + (if i % 4 == 0 then 0.12 else 0.01)
				t.eq((send({ t = 100 + i * SEND, z = z }, arrive)), "accepted", `walking, Move {i}`)
			end
			-- twice walking pace runs the budget down and is refused; sprint pace with the bit is not
			local n = 0
			for i = 21, 60 do
				z += 2 * Body.WALK * SEND
				local verdict, why = send({ t = 100 + i * SEND, z = z })
				if verdict == "refused" then
					t.eq(why, "speed")
					break
				end
				n += 1
			end
			t.truthy(n > 0 and n < 39, `a runner without the bit was stopped after {n} Moves`)
			local sprinter, run = placed(20, 0, -40)
			z = -40
			for i = 1, 40 do
				z += Body.WALK * feel.sprintMult * SEND
				t.eq((run({ t = 100 + i * SEND, z = z, bits = Wire.BIT.sprint })), "accepted", `sprinting, Move {i}`)
			end
			t.truthy(sprinter.budget <= Body.speed(0, true, feel) * T.speedTolerance * T.speedWindow + 1e-9)
			-- one Move after a long gap buys TRUST.moveGap of distance, not the whole gap
			local late, jump = placed(20, 0, -40)
			t.eq((jump({ t = 100.05, z = -35 })), "accepted", "five studs of the burst a placement starts with")
			local left = late.budget
			t.eq((jump({ t = 100.9, z = -35 })), "accepted")
			t.near(late.budget, left + Body.WALK * T.speedTolerance * T.moveGap, 1e-9)
			-- a respawn fills the budget; a CORRECTION empties it (a refused client is not paid in distance)
			Stream.placed(late, 20, 0, -35, 0, 101, feel, false)
			t.eq(late.budget, 0)
			t.eq(
				(jump({ t = 101.05, z = -35 + Body.WALK * SEND })),
				"accepted",
				"an honest step fills it from its own time"
			)
			Stream.placed(late, 20, 0, -40, 0, 102, feel, true)
			t.near(late.budget, Body.WALK * T.speedTolerance * T.speedWindow, 1e-9)
		end
	)

	t.test(
		"inside: out of the volume, in a box, in the other team's spawn room and through a wall are each refused as a wall; the third refusal in a second is a correction",
		function()
			local person, send, arena = placed(-35, 0, -30)
			t.deepEq({ send({ t = 100.05, x = -35, z = -35 }) }, { "refused", "wall" }, "inside a pillar")
			t.falsy(Stream.refused(person, 100.05))
			t.deepEq({ send({ t = 100.1, x = -35, y = -3 }) }, { "refused", "wall" }, "under the floor")
			t.falsy(Stream.refused(person, 100.1))
			t.deepEq({ send({ t = 100.15, x = -35, z = -39 }) }, { "refused", "wall" }, "the far side of the pillar")
			t.truthy(Stream.refused(person, 100.15), "three inside TRUST.refusalWindow")
			t.eq(person.anchor.z, -30, "a refused pose never becomes the anchor")
			t.eq(#person.moves, 0)
			-- refusals a second apart are not a correction
			local slow = placed(-35, 0, -30)
			t.falsy(Stream.refused(slow, 100))
			t.falsy(Stream.refused(slow, 100.6))
			t.falsy(Stream.refused(slow, 101.3))
			-- the other team's room (team 2's, against the east wall on the middle storey)
			local room = arena.spawnRooms[2]
			local cx, cz = (room.minX + room.maxX) / 2, (room.minZ + room.maxZ) / 2
			local near, step = placed(cx, room.minY, room.maxZ + 3)
			t.eq(near.place, 1)
			t.deepEq({ step({ t = 100.05, x = cx, y = room.minY, z = cz }) }, { "refused", "wall" })
			-- the body: a pose far from where the replicated body really is
			local feel = Contract.feel()
			local apart = Stream.new("bea", 100)
			Stream.placed(apart, 20, 0, 0, 0, 100, feel, true)
			local rec = { t = 100.05, x = 20, y = 0, z = 0.5, yaw = 0, pitch = 0, bits = 0, place = 1 }
			t.deepEq(
				{ Stream.judge(apart, rec, 100.05, arena, feel, nil, 20, 0, T.bodySlack + 1) },
				{ "refused", "wall" }
			)
			t.eq((Stream.judge(apart, rec, 100.05, arena, feel, nil, 20, 0, T.bodySlack - 1)), "accepted")
		end
	)

	t.test(
		"the height rule: a jump on the floor and a drop are free, a body at an edge still stands on it, a rise in the air is refused, and a fall must fall",
		function()
			-- on the first storey's slab, north of the atrium
			local person, send = placed(-5, FLOOR, -17)
			-- a jump where it stands: up to JUMP_HEIGHT + jumpSlack over the floor is supported
			t.eq((send({ t = 100.05, y = FLOOR + 1.2, bits = Wire.BIT.air })), "accepted")
			t.eq((send({ t = 100.1, y = FLOOR + Body.JUMP_HEIGHT, bits = Wire.BIT.air })), "accepted")
			t.eq((send({ t = 100.2, y = FLOOR })), "accepted")
			t.eq(person.fallSince, nil)
			t.deepEq(
				{ send({ t = 100.25, y = FLOOR + Body.JUMP_HEIGHT + T.jumpSlack + 0.5 }) },
				{ "refused", "wall" },
				"higher than a jump"
			)
			-- the landing at the head of the ground floor's north flight (x 10.5..15, z -15..-7, level with the
			-- first storey) has an open south edge: past z = -7 there is nothing under a body but the ground floor
			t.eq(ArenaData.build().ground(12.5, FLOOR, -8), FLOOR)
			t.eq(ArenaData.build().ground(12.5, FLOOR, -6), 0)
			local faller, fall = placed(12.5, FLOOR, -8)
			t.eq((fall({ t = 100.05, z = -5.5, y = FLOOR - 0.2, bits = Wire.BIT.air })), "accepted", "stepping off")
			t.truthy(faller.fallSince ~= nil, "it is falling")
			t.eq((fall({ t = 100.3, z = -5, y = FLOOR - 6, bits = Wire.BIT.air })), "accepted", "and dropping")
			t.eq((fall({ t = 100.45, z = -4, y = 0 })), "accepted", "to the floor below")
			t.eq(faller.fallSince, nil)
			-- A BODY HAS A FOOTPRINT: a feet point up to a stud past the edge is still standing on the landing,
			-- for as long as it likes (the contract's point test would refuse it after TRUST.fallSecs)
			local edger, edge = placed(12.5, FLOOR, -8)
			local at = 100
			for _ = 1, 40 do
				at += 0.1
				t.eq((edge({ t = at, z = -6.2 })), "accepted", "at the very edge, looking down")
			end
			t.eq(edger.fallSince, nil)
			t.eq(
				(edge({ t = at + 0.05, z = -6.2, y = FLOOR + 1.5, bits = Wire.BIT.air })),
				"accepted",
				"and it may hop there"
			)
			-- THE HOP OFF A LEDGE. As written, an unsupported pose may be no more than TRUST.riseSlack above the
			-- last accepted one: stepping off and dropping is free, and a hop taken off the edge is refused while
			-- it is still rising. (Reported as a gap in the contract: the rise ought to be measured from where
			-- the body left the ground. It is one function, Stream's supportedOrFalling.)
			local hopper, hop = placed(12.5, FLOOR, -8)
			t.eq(
				(hop({ t = 100.05, z = -7.5, y = FLOOR + 0.5, bits = Wire.BIT.air })),
				"accepted",
				"still over the landing"
			)
			t.deepEq(
				{ hop({ t = 100.1, z = -5.5, y = FLOOR + 1.2, bits = Wire.BIT.air }) },
				{ "refused", "wall" },
				"rising, with nothing under it"
			)
			t.eq(
				(hop({ t = 100.15, z = -5.2, y = FLOOR + 0.5, bits = Wire.BIT.air })),
				"accepted",
				"coming down past where it left"
			)
			t.truthy(hopper.fallSince ~= nil, "it is falling")
			t.eq((hop({ t = 100.3, z = -4.5, y = FLOOR - 4, bits = Wire.BIT.air })), "accepted")
			-- A FALL MUST FALL: a "fall" that does not come down is flying, and is refused within a fifth of a
			-- second (the contract as written lets it walk level for the whole of TRUST.fallSecs)
			local hover, hang = placed(12.5, FLOOR, -8)
			t.eq((hang({ t = 100.05, z = -5, bits = Wire.BIT.air })), "accepted", "the first Move past the edge")
			t.eq((hang({ t = 100.15, z = -5, bits = Wire.BIT.air })), "accepted", "a tenth of a second is no fall yet")
			t.deepEq({ hang({ t = 100.25, z = -5, bits = Wire.BIT.air }) }, { "refused", "wall" }, "hovering")
			t.deepEq({ hang({ t = 100.3, z = -4.5, bits = Wire.BIT.air }) }, { "refused", "wall" }, "walking on air")
			t.truthy(hover.fallSince ~= nil)
			-- a feather fall (an eighth of gravity) is refused; half of gravity is a fall (the engine's is 196.2,
			-- and the rule asks for a quarter of it)
			for _, case in { { 1 / 8, false }, { 1 / 2, true } } do
				local share, honest = case[1] :: number, case[2] :: boolean
				local _, drift = placed(12.5, FLOOR, -8)
				t.eq((drift({ t = 100.05, z = -5, bits = Wire.BIT.air })), "accepted")
				local all = true
				for i = 1, 5 do
					local tau = i * 0.05
					local y = FLOOR - share * 196.2 / 2 * tau * tau
					all = all and drift({ t = 100.05 + tau, z = -5, y = y, bits = Wire.BIT.air }) == "accepted"
				end
				t.eq(all, honest, `a fall at {share} of gravity`)
			end
			-- and no fall, however fast, lasts longer than TRUST.fallSecs by the Moves' own t
			local long, drop = placed(12.5, FLOOR, -8)
			t.eq((drop({ t = 100.05, z = -5, bits = Wire.BIT.air })), "accepted")
			long.fallSince = 100.05 - T.fallSecs
			long.fallFromY = FLOOR + 400
			t.deepEq({ drop({ t = 100.1, z = -5, y = FLOOR - 0.5, bits = Wire.BIT.air }) }, { "refused", "wall" })
		end
	)

	t.test(
		"the pose at a time: on the line between the two Moves either side, held at the newest and the oldest, the anchor when there are none",
		function()
			local person, send = placed(20, 0, -40)
			t.deepEq({ Stream.poseAt(person, 150) }, { 20, 0, -40, 0, 0, 0, 100 }, "the placed pose")
			send({ t = 100.05, z = -39.5, yaw = 0.25, bits = Wire.BIT.crouch })
			send({ t = 100.1, z = -39, yaw = 0.5 })
			send({ t = 100.2, z = -38, yaw = 0.75, bits = Wire.BIT.sprint })
			local x, y, z, yaw, _, bits, newest = Stream.poseAt(person, 100.15)
			t.deepEq(
				{ x, y, yaw, bits, newest },
				{ 20, 0, 0.75, Wire.BIT.sprint, 100.2 },
				"yaw and bits of the newer of the two"
			)
			t.near(z, -38.5, 1e-9)
			t.near(select(3, Stream.poseAt(person, 100.07)), -39.5 + 0.5 * 0.4, 1e-9)
			t.eq(select(3, Stream.poseAt(person, 99)), -39.5, "held at the oldest")
			t.eq(select(3, Stream.poseAt(person, 101)), -38, "held at the newest")
			-- only the last Clock.MOVES_KEPT are kept
			for i = 1, 20 do
				send({ t = 100.2 + i * SEND, z = -38 })
			end
			t.eq(#person.moves, Clock.MOVES_KEPT)
		end
	)

	t.test("the sprint window and the origin of a shot", function()
		local person, send, arena = placed(20, 0, -40)
		local feel = Contract.feel()
		send({ t = 100.05, bits = Wire.BIT.sprint })
		send({ t = 100.1 })
		local last = 100.05
		t.truthy(Stream.sprinting(person, last + 0.05))
		t.truthy(Stream.sprinting(person, last + Body.SPRINT_FIRE_DELAY - Contract.MARGIN.sprint - 0.001))
		t.falsy(Stream.sprinting(person, last + Body.SPRINT_FIRE_DELAY), "a click 0.15 s after the last sprint Move")
		t.falsy(Stream.sprinting(person, last - 0.01), "a Move stamped after the click says nothing of it")
		-- the origin: the eye over the pose at f, a stud of slack, walking pace for whatever f is past the newest Move
		local eye = Body.STAND_EYE
		t.truthy(Stream.originOk(person, 100.1, 20, eye, -40, arena.sweep, feel))
		t.truthy(Stream.originOk(person, 100.1, 20 + T.originSlack - 0.01, eye, -40, arena.sweep, feel))
		t.falsy(Stream.originOk(person, 100.1, 20 + T.originSlack + 0.01, eye, -40, arena.sweep, feel))
		t.truthy(
			Stream.originOk(person, 100.2, 20 + T.originSlack + 0.9 * Body.WALK * 0.1, eye, -40, arena.sweep, feel)
		)
		t.falsy(Stream.originOk(person, 100.1, 20, eye + T.originSlackY + 0.01, -40, arena.sweep, feel))
		t.falsy(Stream.originOk(person, 100.1, 20, eye - T.originSlackY - 0.01, -40, arena.sweep, feel))
		-- in the air (a hop) the eye may be a jump higher or lower than the newest Move puts it
		send({ t = 100.15, y = 1, bits = Wire.BIT.air })
		t.truthy(Stream.originOk(person, 100.2, 20, 1 + eye + Body.JUMP_HEIGHT, -40, arena.sweep, feel))
		t.truthy(Stream.originOk(person, 100.2, 20, 1 + eye - Body.JUMP_HEIGHT, -40, arena.sweep, feel))
		t.falsy(
			Stream.originOk(
				person,
				100.2,
				20,
				1 + eye + Body.JUMP_HEIGHT + T.originSlackY + 0.01,
				-40,
				arena.sweep,
				feel
			)
		)
		-- crouching: between the eye of the server's own crouch fraction and the eye the crouch bit is heading for
		local ducker, duck = placed(20, 0, -40)
		duck({ t = 100.05, bits = Wire.BIT.crouch })
		ducker.crouch = 0.5
		t.truthy(Stream.originOk(ducker, 100.05, 20, Body.eye(0.5), -40, arena.sweep, feel))
		t.truthy(
			Stream.originOk(ducker, 100.05, 20, Body.CROUCH_EYE, -40, arena.sweep, feel),
			"the client is ahead of the server"
		)
		t.falsy(
			Stream.originOk(ducker, 100.05, 20, Body.STAND_EYE, -40, arena.sweep, feel),
			"standing height while crouching"
		)
		-- and no further than its own side of a wall: a pillar stands at x 33..37, z -37..-33
		local hider, hide = placed(32.6, 0, -35)
		hide({ t = 100.05 })
		t.falsy(
			Stream.originOk(hider, 100.05, 33.4, eye, -35, arena.sweep, feel),
			"within a stud, but inside the pillar"
		)
		t.truthy(Stream.originOk(hider, 100.05, 32.0, eye, -35, arena.sweep, feel))
	end)

	t.test("silence: stale after half a second, to be taken off after five; never while out or just placed", function()
		local feel = Contract.feel()
		local fresh = Stream.new("ada", 100)
		t.deepEq({ Stream.silent(fresh, 130) }, { true, false }, "not placed yet: it may not fire, and is not dropped")
		local person, send = placed(20, 0, -40)
		t.deepEq({ Stream.silent(person, 100 + T.placeGrace) }, { false, false }, "just placed")
		send({ t = 101.2 })
		t.deepEq({ Stream.silent(person, 101.2 + Clock.STALE_SECS - 0.01) }, { false, false })
		t.deepEq({ Stream.silent(person, 101.2 + Clock.STALE_SECS + 0.01) }, { true, false })
		t.deepEq({ Stream.silent(person, 101.2 + Clock.DROP_SECS + 0.01) }, { true, true })
		person.out = true
		t.deepEq({ Stream.silent(person, 150) }, { false, false }, "a client sends nothing while tagged out")
		-- a new match: the placement number, the upstream delay and the magazine time carry on
		person.lastM = 101
		Stream.restart(person, 200)
		t.deepEq({ person.place, person.lastM, person.out, #person.moves }, { 1, 101, false, 0 })
		t.truthy(person.up.lag ~= nil)
		Stream.placed(person, 0, 0, 0, 0, 200, feel, true)
		t.eq(person.place, 2)
	end)

	t.test(
		"the pass desk: sold once for 20c through the town, good for five game days from the minute of buying, kept by user",
		function()
			local day, charged, refuse = 10.5, {} :: { any }, false
			local desk = PassDesk.new(function(player: any, cents: number, why: string): (boolean, string?)
				if refuse then
					return false, Contract.passShort(cents, 7)
				end
				table.insert(charged, { player.UserId, cents, why })
				return true, nil
			end, function(): number
				return day
			end)
			local ada, bea = { UserId = 41 }, { UserId = 42 }
			t.falsy(desk.has(ada))
			t.deepEq({ desk.buy(ada) }, { true, Contract.textFor("bought") })
			t.deepEq(charged, { { 41, Contract.Rules.passCents, "a paintball pass" } })
			t.truthy(desk.has(ada))
			t.truthy(desk.has({ UserId = 41 }), "the same user in another Player object")
			t.falsy(desk.has(bea))
			t.deepEq({ desk.buy(ada) }, { false, Contract.textFor("has_pass") })
			t.eq(#charged, 1)
			t.eq(desk.untilDay(ada), 10.5 + Contract.Rules.passDays)
			day = 15.49
			t.truthy(desk.has(ada))
			day = 15.5
			t.falsy(desk.has(ada), "five days to the minute")
			t.deepEq({ desk.buy(ada) }, { true, Contract.textFor("bought") }, "and it can be bought again")
			refuse = true
			t.deepEq(
				{ desk.buy(bea) },
				{ false, "You need 20c; you have 7c" },
				"the town's own words for a short purse"
			)
			t.falsy(desk.has(bea))
			t.eq(PassDesk.daySecs(), 720, "a game day is the town's twelve minutes")
		end
	)
end
