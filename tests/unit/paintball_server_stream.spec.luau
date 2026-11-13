--!strict
-- What the paintball service keeps for one person and how it judges what that person's client claims
-- (Server/Minigames/Paintball/Stream; Shared/Minigames/Paintball/Contract, "who is trusted for what"), and
-- the pass desk (Server/Minigames/Paintball/PassDesk; checklist PB-12). Pure: the whole-game cases are in
-- tests/unit/paintball_server.spec.luau. Here each rule is held on its own, with the contract's numbers, in
-- the stand-in building: the time rules, the distance budget and what refills it, the height rule (Stream's
-- header says where it is not the contract's wording: a body's footprint at an edge, a running jump off a
-- ledge, a fall that must fall), the body rule, the pose at a time, the sprint window, the origin of a
-- shot, a click that came late, and silence.
local Greybox = require("../../tools/games/paintball/server/Greybox")
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
	local arena = Greybox.build()
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
		"a Move is dropped, not refused: before the first placement, with another placement number, out, owed a placement after a change of side, or with a bad stamp",
		function()
			local feel = Contract.feel()
			local arena = Greybox.build()
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
			-- its side has just been changed: until the match places it (a second at the most) its Moves, which
			-- come from the room that is now the other side's, are dropped
			local trader, tell = placed(20, 0, 0)
			trader.owedSince = 100.1
			t.eq((tell({ t = 100.15 }, 100.15)), "dropped", "owed a placement")
			t.eq((tell({ t = 100.2 }, 100.1 + T.placeGrace + 0.01)), "accepted", "a placement that never came")
			trader.owedSince = 101.2
			Stream.placed(trader, 20, 0, 0, 0, 101.25, feel, true)
			t.eq(trader.owedSince, nil, "the placement came")
			t.eq((tell({ t = 101.3, place = trader.place }, 101.3)), "accepted")
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
			-- ... but only sideways while it falls: a body dropping off the landing (x 10.5..15, z -15..-7, a
			-- storey up) is replicated a tenth of a second behind its own Moves, a dozen studs higher
			local faller = Stream.new("cyd", 100)
			Stream.placed(faller, 12.5, FLOOR, -8, 0, 100, feel, true)
			local function drop(at: number, z: number, y: number, bodyY: number, bodyZ: number?): Stream.Verdict
				local move = { t = at, x = 12.5, y = y, z = z, yaw = 0, pitch = 0, bits = Wire.BIT.air, place = 1 }
				return (Stream.judge(faller, move, at, arena, feel, nil, 12.5, bodyY, bodyZ or z))
			end
			t.eq(drop(100.05, -5.5, FLOOR - 0.3, FLOOR), "accepted")
			t.eq(drop(100.25, -5, FLOOR - 4, FLOOR + 8), "accepted", "falling: the body is twelve studs behind it")
			t.eq(drop(100.3, -5, FLOOR - 6, FLOOR - 6, -5 - T.bodySlack - 1), "refused", "sideways it still counts")
			t.eq(drop(100.4, -4.5, 0, 9), "accepted", "landed, the body still coming down")
			t.eq(drop(100.5, -4.5, 0, 3), "accepted")
			t.eq(drop(100.7, -4.5, 0, 9), "refused", "a body that stands is held to it up and down as well")
		end
	)

	t.test(
		"the height rule: a jump on the floor, a drop and a running jump off a ledge are free; a body at an edge still stands on it; higher than a hop, level on air and a glide are refused",
		function()
			local G = 196.2 -- the engine's gravity, studs/s^2
			local V = math.sqrt(2 * G * Body.JUMP_HEIGHT) -- the speed a hop leaves the ground at
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
			t.eq(Greybox.build().ground(12.5, FLOOR, -8), FLOOR)
			t.eq(Greybox.build().ground(12.5, FLOOR, -6), 0)
			local faller, fall = placed(12.5, FLOOR, -8)
			t.eq((fall({ t = 100.05, z = -5.5, y = FLOOR - 0.2, bits = Wire.BIT.air })), "accepted", "stepping off")
			t.truthy(faller.fallSince ~= nil, "it is falling")
			t.eq((fall({ t = 100.3, z = -5, y = FLOOR - 6, bits = Wire.BIT.air })), "accepted", "and dropping")
			t.eq((fall({ t = 100.45, z = -4, y = 0 })), "accepted", "to the floor below")
			t.eq(faller.fallSince, nil)
			t.eq(faller.standY, 0, "it stands on the ground floor now")
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
			-- THE RUNNING JUMP OFF A LEDGE: she sprints south, jumps a stud before the edge and sails out over
			-- the ground floor. Every Move of the arc is accepted, at any phase of the send clock (the contract
			-- as written refuses the ones that rise with nothing under them: three of them is a yank back)
			local sprint = Body.speed(0, true, Contract.feel())
			for phase = 0, 4 do
				local jumper, jump = placed(12.5, FLOOR, -8)
				local t0 = 100.2 + phase * 0.01 -- when she leaves the ground, at z = -8
				local refused = 0
				local i = 0
				while true do
					i += 1
					local now = 100 + i * SEND
					local z = -8 - sprint * (t0 - now) -- (walking up to the take-off; z < -8 before it)
					local tau = now - t0
					local y = FLOOR
					if tau > 0 then
						y = math.max(0, FLOOR + V * tau - G / 2 * tau * tau)
					end
					local bits = Wire.BIT.sprint + (if tau > 0 and y > 0 then Wire.BIT.air else 0)
					if jump({ t = now, z = z, y = y, bits = bits }) ~= "accepted" then
						refused += 1
					end
					if tau > 0 and y == 0 then
						break
					end
				end
				t.eq(refused, 0, `a running jump off the landing, phase {phase}`)
				t.eq(jumper.standY, 0)
			end
			-- A HOP TAKEN RUNNING DOWN A STAIR is a hop from the step it left: the stair falls away under the
			-- body faster than the hop comes down, so its Moves are "unsupported" over the lower steps
			for index, ramp in Greybox.build().ramps do
				if index > 4 then
					break
				end
				local along = if ramp.axis == "x" then ramp.maxX - ramp.minX else ramp.maxZ - ramp.minZ
				local cx, cz = (ramp.minX + ramp.maxX) / 2, (ramp.minZ + ramp.maxZ) / 2
				-- a point `d` studs down the flight from its head, on its middle line
				local function down(d: number): (number, number, number)
					local a = 1 - d / along -- 1 at the head
					local k = if ramp.dir > 0 then a else 1 - a
					local x = if ramp.axis == "x" then ramp.minX + (ramp.maxX - ramp.minX) * k else cx
					local z = if ramp.axis == "z" then ramp.minZ + (ramp.maxZ - ramp.minZ) * k else cz
					return x, ramp.y0 + (ramp.y1 - ramp.y0) * a, z
				end
				local x0, y0, z0 = down(1)
				local stair = Stream.new("dee", 100)
				Stream.placed(stair, x0, y0, z0, 0, 100, Contract.feel(), true)
				local arena = Greybox.build()
				local refused = 0
				local takeoff, takeoffY = 100.15, 0
				for i = 1, 200 do
					local now = 100 + i * SEND
					local d = 1 + sprint * (now - 100)
					if d > along - 0.5 then
						break
					end
					local x, y, z = down(d)
					if now < takeoff then
						takeoffY = y
					else
						local tau = now - takeoff
						y = math.max(y, takeoffY + V * tau - G / 2 * tau * tau)
					end
					local rec = { t = now, x = x, y = y, z = z, yaw = 0, pitch = 0, bits = Wire.BIT.sprint, place = 1 }
					if Stream.judge(stair, rec, now, arena, Contract.feel()) ~= "accepted" then
						refused += 1
					end
				end
				t.eq(refused, 0, `a hop taken running down flight {index}`)
			end
			-- no higher than a hop from where it last stood
			local hopper, hop = placed(12.5, FLOOR, -8)
			t.eq((hop({ t = 100.05, z = -7.5, y = FLOOR + 0.5, bits = Wire.BIT.air })), "accepted", "over the landing")
			t.eq(hopper.standY, FLOOR, "a body in the air keeps the surface it took off from")
			t.deepEq(
				{ hop({ t = 100.1, z = -5.5, y = FLOOR + Body.JUMP_HEIGHT + T.jumpSlack + 0.2, bits = Wire.BIT.air }) },
				{ "refused", "wall" },
				"higher than a hop, with nothing under it"
			)
			t.eq((hop({ t = 100.15, z = -5.2, y = FLOOR + 1.9, bits = Wire.BIT.air })), "accepted", "the top of a hop")
			t.truthy(hopper.fallSince ~= nil, "it is falling")
			t.eq((hop({ t = 100.35, z = -4.5, y = FLOOR - 4, bits = Wire.BIT.air })), "accepted")
			t.deepEq(
				{ hop({ t = 100.45, z = -4.2, y = FLOOR + 1.9, bits = Wire.BIT.air }) },
				{ "refused", "wall" },
				"and no second hop in the air"
			)
			-- A FALL MUST FALL: a pose that stays level on air is refused after a third of a second (the contract
			-- as written lets it walk level for the whole of TRUST.fallSecs)
			local hover, hang = placed(12.5, FLOOR, -8)
			local level = 0
			for i = 1, 12 do
				if hang({ t = 100 + i * SEND, z = -5 + i * 0.5, bits = Wire.BIT.air }) == "accepted" then
					level = i * SEND
				else
					break
				end
			end
			t.truthy(level >= 0.25 and level <= 0.4, `walking on air lasted {level} s`)
			t.truthy(hover.fallSince ~= nil)
			-- a feather fall (an eighth of gravity) is refused; half of gravity is a fall (the rule asks for a
			-- quarter of the engine's)
			for _, case in { { 1 / 8, false }, { 1 / 2, true } } do
				local share, honest = case[1] :: number, case[2] :: boolean
				local _, drift = placed(12.5, FLOOR, -8)
				t.eq((drift({ t = 100.05, z = -5, bits = Wire.BIT.air })), "accepted")
				local all = true
				for i = 1, 20 do
					local tau = i * 0.05
					local y = math.max(0, FLOOR - share * G / 2 * tau * tau)
					all = all and drift({ t = 100.05 + tau, z = -5, y = y, bits = Wire.BIT.air }) == "accepted"
				end
				t.eq(all, honest, `a fall at {share} of gravity`)
			end
			-- and no fall, however fast, lasts longer than TRUST.fallSecs by the Moves' own t
			local long, drop = placed(12.5, FLOOR, -8)
			t.eq((drop({ t = 100.05, z = -5, bits = Wire.BIT.air })), "accepted")
			long.fallSince = 100.05 - T.fallSecs
			long.standY = FLOOR + 400
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
		-- back from being out: the silence is measured from the placement, not from before the tag
		Stream.placed(person, 20, 0, -40, 0, 150, feel, true)
		t.deepEq({ Stream.silent(person, 150 + T.placeGrace) }, { false, false })
		t.deepEq({ Stream.silent(person, 150 + T.placeGrace + 0.01) }, { true, false }, "it may not fire unheard")
		t.deepEq({ Stream.silent(person, 150 + Clock.DROP_SECS - 0.01) }, { true, false })
		t.deepEq({ Stream.silent(person, 150 + Clock.DROP_SECS + 0.01) }, { true, true })
		Stream.placed(person, 20, 0, -40, 0, 160, feel, true)
		-- a new match: the placement number, the upstream delay and the magazine time carry on
		person.lastM = 101
		Stream.restart(person, 200)
		t.deepEq({ person.place, person.lastM, person.out, #person.moves }, { 3, 101, false, 0 })
		t.truthy(person.up.lag ~= nil)
		Stream.placed(person, 0, 0, 0, 0, 200, feel, true)
		t.eq(person.place, 4)
	end)

	t.test(
		"a click that came late is judged where and how its body was when it was clicked: the pose, the sprint window, the rooms and the stance of that time, and no click is judged at a time it was not made",
		function()
			local person, send, arena = placed(20, 0, -40)
			local feel = Contract.feel()
			local eye = Body.STAND_EYE
			-- she strafes north at a walk, a Move every send interval, and the server ticks its crouch as it goes
			local z = -40
			local function walk(from: number, to: number, bits: number?)
				local at = from
				while at < to - 1e-9 do
					at += SEND
					z += Body.WALK * SEND
					t.eq((send({ t = at, z = z, bits = bits or 0 })), "accepted")
					Stream.ease(person, at, feel)
				end
			end
			walk(100, 100.6)
			local clickZ = z -- where she was at 100.6, when she clicked
			walk(100.6, 100.9)
			-- the click reaches the server at 100.9 behind a lost packet; her delay is nothing, so f = 100.825
			local f = 100.9 - Clock.REWIND_TOLERANCE
			t.eq(Stream.clickOk(person, f, 20, eye, clickZ, arena, feel), "origin", "at f she has walked on")
			t.eq(Stream.clickOk(person, 100.6, 20, eye, clickZ, arena, feel, 100.9), nil, "at the click she was there")
			t.eq(
				Stream.clickOk(person, 100.6, 20 + T.originSlack + 0.5, eye, clickZ, arena, feel, 100.9),
				"origin",
				"and nowhere else"
			)
			t.eq(
				Stream.clickOk(person, 100.4, 20, eye, clickZ, arena, feel, 100.9),
				"origin",
				"nor at another time than the one it names"
			)
			-- she ran on after the click: the sprint Moves stamped after it say nothing of it
			walk(100.9, 101.1, Wire.BIT.sprint)
			t.eq(Stream.clickOk(person, 101.1, 20, eye, clickZ, arena, feel), "sprint")
			t.eq(Stream.clickOk(person, 100.6, 20, eye, clickZ, arena, feel, 101.1), nil)
			t.eq(Stream.clickOk(person, 101.0, 20, eye, z, arena, feel, 101.1), "sprint", "a click made while running")
			-- the stance is the one the server held then: she ducked after the click, and is fully crouched now
			local ducker, duck = placed(20, 0, -40)
			local at = 100
			for i = 1, 16 do
				at += SEND
				duck({ t = at, bits = if i > 6 then Wire.BIT.crouch else 0 })
				Stream.ease(ducker, at, feel)
			end
			t.eq(ducker.crouch, 1)
			t.eq(Stream.crouchAt(ducker, 100.3), 0, "standing then")
			t.eq(Stream.crouchAt(ducker, 100.45), 0.75, "three ticks into the crouch")
			t.eq(Stream.crouchAt(ducker, 99), 0, "before the log: its oldest")
			t.eq(Stream.clickOk(ducker, 100.8, 20, eye, -40, arena, feel), "origin", "standing height while crouched")
			t.eq(Stream.clickOk(ducker, 100.3, 20, eye, -40, arena, feel, 100.8), nil, "a click made standing")
			t.eq(
				Stream.clickOk(ducker, 100.6, 20, eye, -40, arena, feel, 100.8),
				"origin",
				"a click made crouched is not a standing shot"
			)
			-- the rooms: a click made inside her own spawn room is no shot, whenever it arrives
			local room = arena.spawnRooms[1]
			local cx, cz = (room.minX + room.maxX) / 2, (room.minZ + room.maxZ) / 2
			local homer = placed(cx, room.minY, cz)
			t.eq(Stream.clickOk(homer, 100, cx, room.minY + eye, cz, arena, feel), "safe")
			t.eq(Stream.clickOk(homer, 99.8, cx, room.minY + eye, cz, arena, feel, 100), "safe")
		end
	)

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

	t.test(
		"the pass desk charges once however the desk is pressed: a second press while the town is still taking the money is answered and costs nothing; a town that fails leaves the desk open",
		function()
			local charged = 0
			local waiting: thread? = nil
			local fail = false
			local desk = PassDesk.new(function(_player: any, _cents: number, _why: string): (boolean, string?)
				if fail then
					error("the wallet is away", 0)
				end
				charged += 1
				waiting = coroutine.running()
				coroutine.yield() -- (a wallet kept in a store takes its time)
				return true, nil
			end, function(): number
				return 1
			end)
			local ada, bea = { UserId = 41 }, { UserId = 42 }
			local first: { any } = {}
			local press = coroutine.create(function()
				first = { desk.buy(ada) }
			end)
			coroutine.resume(press)
			t.eq(charged, 1, "the town is taking the money")
			t.falsy(desk.has(ada), "no pass until it is paid for")
			-- she presses again (and from another Player object of hers) before the first has come back
			t.deepEq({ desk.buy(ada) }, { false, Contract.textFor("phase") })
			t.deepEq({ desk.buy({ UserId = 41 }) }, { false, Contract.textFor("phase") })
			t.eq(charged, 1, "charged once")
			coroutine.resume(waiting :: thread)
			t.deepEq(first, { true, Contract.textFor("bought") })
			t.truthy(desk.has(ada))
			t.deepEq({ desk.buy(ada) }, { false, Contract.textFor("has_pass") })
			t.eq(charged, 1)
			-- a town that fails: the fault is shown, nothing is sold, and the desk is not left shut
			fail = true
			t.falsy(pcall(desk.buy, bea), "the town's fault is not swallowed")
			t.falsy(desk.has(bea))
			fail = false
			local second = coroutine.create(function()
				first = { desk.buy(bea) }
			end)
			coroutine.resume(second)
			t.eq(charged, 2, "the desk is open to her again")
			coroutine.resume(waiting :: thread)
			t.deepEq(first, { true, Contract.textFor("bought") })
			t.truthy(desk.has(bea))
		end
	)
end
