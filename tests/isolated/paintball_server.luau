--!strict
-- tests/isolated/paintball_server.luau: the paintball service in a whole game on the fake engine, for
-- tests/unit/paintball_server.spec.luau (run in its own Lune process: tests/lib/Isolated). The door, the
-- pass, the roster and the bots that fill it, the match rolling on, the audience; then what a client may
-- and may not claim about where it is (tests/isolated/paintball_server_kit has the scripted clients and
-- the scripted match model these cases run on).
-- Interface: return function(t) (the spec shape)
local Arena = require("@shared/Minigames/Paintball/Arena")
local ArenaData = require("@shared/Minigames/Paintball/ArenaData")
local Body = require("@shared/Minigames/Paintball/Body")
local Clock = require("@shared/Minigames/Paintball/Clock")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Wire = require("@shared/Minigames/Paintball/Wire")
local Rig = require("@tests/lib/MinigameRig")
local Kit = require("@tests/isolated/paintball_server_kit")

local R = Contract.Rules
local T = Contract.TRUST

local function isBot(key: any): boolean
	return type(key) == "table" and key.ai == true
end

-- who holds the seats now: people and bots, and the size of each side
local function roster(kit: Kit.Kit): { people: number, bots: number, sides: { number }, peopleSides: { number } }
	local s = kit.session
	local out = { people = 0, bots = 0, sides = { 0, 0 }, peopleSides = { 0, 0 } }
	local state = kit.state()
	for seat, key in s.seats do
		if not s.gone[seat] then
			local team = state.slots[seat].team
			out.sides[team] += 1
			if isBot(key) then
				out.bots += 1
			else
				out.people += 1
				out.peopleSides[team] += 1
			end
		end
	end
	return out
end

local function teamOf(kit: Kit.Kit, c: Kit.Client): number
	return kit.state().slots[c.seat].team
end

-- two people in the hall, one a side, the match live and both out of their spawn rooms' protection
local function pair(kit: Kit.Kit, copts: { [string]: any }?): (Kit.Client, Kit.Client)
	local ada, bea = kit.client("Ada", copts), kit.client("Bea")
	assert(kit.join(ada))
	assert(kit.join(bea))
	kit.run(0.2)
	assert(teamOf(kit, ada) == 1 and teamOf(kit, bea) == 2, "Ada plays for team 1, Bea for team 2")
	kit.live()
	return ada, bea
end

return function(t)
	t.test(
		"the pass: refused at the door without one, sold once at the desk for 20c through the town, good for five game days",
		function()
			local charged: { any } = {}
			local day = 3
			local purse = 100
			Kit.play(function(kit)
				local ada = kit.client("Ada")
				t.deepEq({ kit.join(ada) }, { false, Contract.textFor("pass") })
				t.eq(kit.session.phase, "idle", "nobody was seated")
				-- the desk sells, and seats nobody
				t.deepEq({ kit.join(ada, Contract.DESK) }, { false, Contract.textFor("bought") })
				t.eq(kit.session.phase, "idle")
				t.deepEq(charged, { { ada.stub, R.passCents, "a paintball pass" } })
				t.deepEq({ kit.join(ada, Contract.DESK) }, { false, Contract.textFor("has_pass") })
				t.eq(#charged, 1, "a holder is not charged again")
				t.truthy((kit.join(ada)))
				t.eq(kit.session.phase, "playing")
				-- a pass that runs out in mid-match: the match goes on, and pressing the door again changes nothing
				day += R.passDays + 0.01
				kit.run(1)
				t.truthy(kit.session.seats[1] == ada.stub and not kit.session.gone[1])
				t.truthy((kit.join(ada)), "already seated")
				-- only the next join is refused
				local bea = kit.client("Bea")
				purse = 7
				local ok, words = kit.join(bea, Contract.DESK)
				t.falsy(ok)
				t.eq(words, Contract.passShort(R.passCents, 7), "the town's own words for a short purse")
				t.deepEq({ kit.join(bea) }, { false, Contract.textFor("pass") })
				kit.w.svc:leave(ada.stub, "left")
				kit.run(0.2)
				t.deepEq({ kit.join(ada) }, { false, Contract.textFor("pass") }, "five days on, the pass has run out")
			end, {
				realPass = true,
				paintball = {
					day = function(): number
						return day
					end,
				},
				service = {
					games = {
						charge = function(player: any, cents: number, why: string): (boolean, string?)
							if purse < cents then
								return false, Contract.passShort(cents, purse)
							end
							purse -= cents
							table.insert(charged, { player, cents, why })
							return true, nil
						end,
					},
				},
			})
		end
	)

	t.test("an unfit player is refused at the door with the reason (see a doctor first)", function()
		Kit.play(function(kit)
			local ada = kit.client("Ada")
			t.deepEq({ kit.join(ada) }, { false, Contract.textFor("infected") })
			t.eq(kit.session.phase, "idle")
		end, {
			paintball = {
				fit = function(): (boolean, string?)
					return false, "infected"
				end,
			},
		})
	end)

	t.test(
		"the roster: one person starts four a side; each who joins takes a bot's seat on the side with fewer people; one who leaves is replaced by a bot",
		function()
			Kit.play(function(kit)
				local ada = kit.client("Ada")
				t.truthy((kit.join(ada)))
				kit.run(0.2)
				local r = roster(kit)
				t.deepEq({ r.people, r.bots, r.sides }, { 1, 7, { 4, 4 } }, "three bot team-mates against four bots")
				t.eq(ada.seat, 1)
				-- everybody was placed in a spawn room; hers is a numbered placement of her real body
				t.eq(ada.count("paintball_respawn"), 8)
				t.eq(ada.place, 1)
				local sp = kit.arena.spawns[1][1]
				t.deepEq({ ada.x, ada.y, ada.z }, { sp.x, sp.y, sp.z })
				local wx, wy, wz = Arena.toWorld(kit.place, sp.x, sp.y, sp.z)
				t.deepEq({ ada.stub.body.x, ada.stub.body.y, ada.stub.body.z }, { wx, wy, wz })
				t.truthy(ada.stub.body.ghost, "bodies in a match pass through each other")
				t.eq(#ada.watch.slots, 8, "the audience is told who holds which slot")
				t.eq(ada.watch.slots[1].user, ada.stub.UserId)
				t.truthy(ada.watch.slots[2].bot)
				-- the second person takes a bot's seat on the other side
				local bea = kit.client("Bea")
				t.truthy((kit.join(bea)))
				kit.run(0.2)
				r = roster(kit)
				t.deepEq({ r.people, r.bots, r.sides, r.peopleSides }, { 2, 6, { 4, 4 }, { 1, 1 } })
				t.eq(bea.seat, 2, "the lowest seat a bot held on that side")
				-- eight people: every bot has given up its seat; the ninth makes five a side with a bot
				local more: { Kit.Client } = {}
				for i = 3, 9 do
					local c = kit.client(`P{i}`)
					t.truthy((kit.join(c)), `P{i}`)
					more[i] = c
					kit.run(0.1)
					if i == 8 then
						r = roster(kit)
						t.deepEq({ r.people, r.bots, r.sides, r.peopleSides }, { 8, 0, { 4, 4 }, { 4, 4 } })
					end
				end
				kit.run(0.2)
				r = roster(kit)
				t.deepEq({ r.people, r.bots, r.sides }, { 9, 1, { 5, 5 } })
				-- one leaves: a bot has the seat and the side at once; she stands in the lobby, solid again
				local side = teamOf(kit, ada)
				kit.w.svc:leave(ada.stub, "left")
				kit.run(0.2)
				r = roster(kit)
				t.deepEq({ r.people, r.bots, r.sides }, { 8, 2, { 5, 5 } })
				t.truthy(isBot(kit.session.seats[1]) and not kit.session.gone[1])
				t.eq(kit.state().slots[1].team, side)
				t.falsy(ada.stub.body.ghost)
				local _, _, lz = Arena.toLocal(kit.place, ada.stub.body.x, ada.stub.body.y, ada.stub.body.z)
				t.truthy(lz > Arena.HALF, "outside the arena volume, in the lobby")
				-- everything the service said was a message the wire knows; the framework's own verbs are refused
				t.deepEq({ Rig.input(kit.w, bea.stub, Contract.STATION, "addai", {}) }, { false, "Not now." })
			end, { arena = ArenaData.build() })
		end
	)

	t.test(
		"eight a side: sixteen people are a match with no bot in it and the seventeenth is refused (full); one leaves and a bot has the seat, another trades sides with that bot, and the seventeenth takes the seat from it; all sixteen walk and fire with nothing refused; at the next match every one of them is on the side they ended on, the two who crossed as well",
		function()
			Kit.play(function(kit)
				local stats = kit.service:stats()
				local people: { Kit.Client } = {}
				for i = 1, R.slots do
					-- (every sort of connection among them: 0 to 300 ms there and back, some with jitter and loss)
					local c =
						kit.client(`P{i}`, { delay = i % 10, jitter = i % 3, lose = if i % 4 == 0 then 0.05 else 0 })
					t.truthy((kit.join(c)), `P{i} joins`)
					people[i] = c
					kit.run(0.1)
				end
				kit.run(0.5)
				local r = roster(kit)
				t.deepEq(
					{ r.people, r.bots, r.sides, r.peopleSides },
					{ R.slots, 0, { R.teamMax, R.teamMax }, { R.teamMax, R.teamMax } },
					"eight people a side and no bot"
				)
				local late = kit.client("Late")
				t.deepEq({ kit.join(late) }, { false, Contract.textFor("full") })
				for _, c in people do
					t.truthy(c.seat ~= nil and c.place ~= 0, `{c.name} is seated and placed`)
					t.eq(#c.watch.slots, R.slots, "everybody is told of all sixteen")
				end
				-- (still the briefing) one leaves: a bot has the seat and the side
				local goer, trader = people[1], people[2]
				local seat, side = goer.seat, teamOf(kit, goer)
				t.eq(teamOf(kit, trader), 3 - side, "the first two joined opposite each other")
				kit.w.svc:leave(goer.stub, "left")
				kit.run(0.3)
				r = roster(kit)
				t.deepEq({ r.people, r.bots, r.sides }, { R.slots - 1, 1, { R.teamMax, R.teamMax } })
				t.truthy(isBot(kit.session.seats[seat]) and not kit.session.gone[seat], "a bot has the seat")
				t.eq(kit.state().slots[seat].team, side, "and the side")
				-- another trades sides with that bot, and the seventeenth takes the bot's seat on the side it now has
				t.deepEq({ Rig.input(kit.w, trader.stub, Contract.STATION, "side", {}) }, { true, nil })
				kit.run(0.3)
				t.eq(teamOf(kit, trader), side)
				t.truthy((kit.join(late)), "now there is room")
				kit.run(0.5)
				r = roster(kit)
				t.deepEq(
					{ r.people, r.bots, r.sides, r.peopleSides },
					{ R.slots, 0, { R.teamMax, R.teamMax }, { R.teamMax, R.teamMax } }
				)
				t.eq(late.seat, seat, "the bot gave her its seat")
				t.eq(teamOf(kit, late), 3 - side, "on the side the bot had after the trade")
				people[1] = late
				-- live: each walks a few studs out of its room and back along its own lane, clicking along its look
				kit.live()
				local start: { number } = {}
				for i, c in people do
					start[i] = c.x
				end
				local step = Body.WALK / 60
				for frame = 1, 6 * 60 do
					local out = frame <= 3 * 60
					for i, c in people do
						if c.seat ~= nil and not c.out then
							local dir = if teamOf(kit, c) == 1 then 1 else -1
							local dx = start[i] + (if out then 14 * dir else 0) - c.x
							if math.abs(dx) > 1e-6 then
								c.x += math.clamp(dx, -step, step)
							end
							c.yaw = math.atan2(-dir, 0)
							if frame % 30 == i % 30 and math.abs(c.x - start[i]) > 11 then
								c.fire(Body.look(c.yaw, 0))
							end
						end
					end
					kit.frame()
				end
				t.eq(stats.movesRefused, 0, "sixteen honest walkers, not one Move refused")
				t.eq(stats.corrections, 0)
				t.truthy(stats.movesAccepted > 16 * 60, `{stats.movesAccepted} Moves accepted`)
				t.truthy(stats.balls >= R.slots, `{stats.balls} balls`)
				local bad = 0
				for _, c in people do
					for _, a in c.acks do
						if not a.ok and (a.why == "origin" or a.why == "sprint" or a.why == "stale") then
							bad += 1
						end
					end
				end
				t.eq(bad, 0, "no click refused for what its own stream said")
				local state = kit.state()
				t.eq(state.scores[1] + state.scores[2], stats.tags, "the scores are the tags")
				-- the clock runs out; the next match is the same sixteen on the same sides
				local sidesWere: { number } = {}
				for i, c in people do
					sidesWere[i] = teamOf(kit, c)
				end
				t.truthy((kit.service:debug("end")))
				kit.run(1)
				t.eq(kit.session.phase, "done")
				t.truthy(
					kit.untilTrue(R.endCardSecs, function(): boolean
						return kit.service.match == 2
					end),
					"the service rolled on"
				)
				kit.run(0.6)
				r = roster(kit)
				t.deepEq(
					{ r.people, r.bots, r.sides, r.peopleSides },
					{ R.slots, 0, { R.teamMax, R.teamMax }, { R.teamMax, R.teamMax } },
					"the second match: the same sixteen, eight a side"
				)
				for i, c in people do
					t.eq(teamOf(kit, c), sidesWere[i], `{c.name} is on the side it ended on`)
					t.truthy(
						Arena.inRoom(kit.arena.spawnRooms[sidesWere[i]], c.x, c.y + 0.1, c.z),
						`{c.name} stands in its spawn room`
					)
				end
			end, { arena = Kit.hall() })
		end
	)

	t.test(
		"a join during the end card is refused; the next match rolls on by itself with people on the sides they ended on",
		function()
			Kit.play(function(kit)
				local ada, bea = kit.client("Ada"), kit.client("Bea")
				t.truthy((kit.join(ada)))
				t.truthy((kit.join(bea)))
				kit.run(0.2)
				local side = teamOf(kit, ada)
				t.truthy(teamOf(kit, bea) ~= side, "a joiner lands on the side with fewer people")
				-- in the briefing Bea trades places with a bot on Ada's side
				local places = bea.place
				t.deepEq({ Rig.input(kit.w, bea.stub, Contract.STATION, "side", {}) }, { true, nil })
				kit.run(0.2)
				t.eq(teamOf(kit, bea), side)
				local r = roster(kit)
				t.deepEq({ r.sides, r.peopleSides[side] }, { { 4, 4 }, 2 })
				t.eq(bea.place, places + 1, "she was put in her new side's room")
				t.truthy(Arena.inRoom(kit.arena.spawnRooms[side], bea.x, bea.y + 0.1, bea.z))
				-- live: no changing sides while in play
				kit.live()
				local ok, words = Rig.input(kit.w, bea.stub, Contract.STATION, "side", {})
				t.deepEq({ ok, words }, { false, Contract.textFor("side") })
				-- the clock runs out: the end card
				t.truthy((kit.service:debug("end")))
				kit.run(0.5)
				t.eq(kit.session.phase, "done")
				t.truthy(ada.last("event", function(m)
					return m.over == true
				end) ~= nil, "the end banner")
				local cy = kit.client("Cy")
				local joined, why = kit.join(cy)
				t.falsy(joined)
				t.truthy(string.find(why :: string, "The next match starts in %d+ s%."), tostring(why))
				t.eq(kit.session.phase, "done", "the card and its seats are untouched")
				t.truthy(kit.session.seats[1] == ada.stub)
				-- people may still walk about at the end card
				local accepted = kit.service:stats().movesAccepted
				kit.walk(ada, ada.x + 3, ada.z)
				t.truthy(kit.service:stats().movesAccepted > accepted)
				-- it rolls on by itself
				local match = kit.service.match
				t.truthy(kit.untilTrue(R.endCardSecs + 2, function(): boolean
					return kit.session.phase == "playing"
				end))
				kit.run(0.3)
				t.eq(kit.service.match, match + 1)
				t.eq(kit.state().phase, "briefing")
				t.eq(teamOf(kit, ada), side)
				t.eq(teamOf(kit, bea), side, "who played together stays together")
				r = roster(kit)
				t.deepEq({ r.people, r.bots, r.sides }, { 2, 6, { 4, 4 } })
				t.eq(ada.watch.match, match + 1, "the audience is told of the new match")
				t.truthy(Arena.inRoom(kit.arena.spawnRooms[side], ada.x, ada.y + 0.1, ada.z), "back in the spawn room")
				t.truthy((kit.join(cy)), "and the door is open again")
			end)
		end
	)

	t.test(
		"the audience: whoever is near is shown the match, whoever is found inside the arena unseated is put in the lobby, an empty arena says unwatch and costs nothing",
		function()
			Kit.play(function(kit)
				local w = kit.w
				local ada = kit.client("Ada")
				local far, intruder = Rig.stub("Far"), Rig.stub("Intruder")
				local fx, fy, fz = Arena.toWorld(kit.place, 400, 0, 0)
				table.insert(w.people, { key = far, name = "Far", x = fx, y = fy, z = fz })
				local ix, iy, iz = Arena.toWorld(kit.place, 0, 3, 0)
				intruder.body = { x = ix, y = iy - 3, z = iz, ghost = true, teleports = 0 }
				local listed = { key = intruder, name = "Intruder", x = ix, y = iy, z = iz }
				table.insert(w.people, listed)
				t.truthy((kit.join(ada)))
				kit.run(0.7)
				-- the rig's own player stands at the arena door, in no game: she is in the audience
				t.truthy(kit.service:watching(w.player))
				local watch = Rig.last(w.got, "paintball_watch")
				t.truthy(watch ~= nil and Wire.checkMessage(watch))
				t.truthy(#kit.wires.got["Paintball.Snap"] >= 8, "and is sent the snapshots")
				local time, _, match, bodies = Wire.decodeSnap(kit.wires.got["Paintball.Snap"][1])
				t.truthy(time ~= nil and match == 1)
				t.eq(#bodies, 8, "every slot that is on is in every snapshot")
				-- a player far away hears nothing at all
				t.falsy(kit.service:watching(far))
				t.eq(#far.events, 0)
				t.eq(far.streams, nil)
				-- the intruder is put out, and is shown the match from the lobby
				t.truthy(intruder.body.teleports >= 1)
				local _, _, lz = Arena.toLocal(kit.place, intruder.body.x, intruder.body.y, intruder.body.z)
				t.truthy(lz > Arena.HALF)
				t.falsy(intruder.body.ghost)
				listed.x, listed.y, listed.z = intruder.body.x, intruder.body.y + 3, intruder.body.z
				local teleports = intruder.body.teleports
				kit.run(1.1)
				t.eq(intruder.body.teleports, teleports, "once out, left alone")
				t.truthy(kit.service:watching(intruder))
				-- the seated are placed, never swept
				t.eq(ada.stub.body.teleports, 1)
				-- the last person leaves: the table resets, the audience is told, and nothing more is sent
				w.svc:leave(ada.stub, "left")
				kit.run(0.3)
				t.eq(kit.session.phase, "idle")
				t.truthy(Rig.last(w.got, "paintball_unwatch") ~= nil)
				t.falsy(kit.service:watching(w.player))
				local snaps, steps = #kit.wires.got["Paintball.Snap"], kit.service:stats().steps
				kit.run(1)
				t.eq(#kit.wires.got["Paintball.Snap"], snaps)
				t.eq(kit.service:stats().steps, steps, "an idle arena is not stepped")
			end)
		end
	)

	t.test(
		"a Move with an old placement number is dropped, not counted against the player; a tagged-out slot's Moves are dropped and its pose held; it comes back placed anew",
		function()
			Kit.play(function(kit)
				local ada, bea = pair(kit)
				local stats = kit.service:stats()
				kit.walk(ada, -36, -2)
				kit.run(0.2)
				local pose = kit.service.poses[ada.seat]
				t.near(pose.x, -36, 0.01)
				t.eq(stats.movesRefused, 0)
				-- a Move sampled before the client heard of a placement names the old number
				local dropped = stats.movesDropped
				ada.auto = false
				for i = 1, 5 do
					ada.move({ place = ada.place - 1, x = -36 + i * 5 })
					kit.run(0.05)
				end
				t.eq(stats.movesDropped, dropped + 5)
				t.eq(stats.movesRefused, 0, "dropped is not refused: no correction comes of it")
				t.eq(stats.corrections, 0)
				t.near(kit.service.poses[ada.seat].x, -36, 0.01, "the pose the server holds stands")
				ada.auto = true
				kit.run(0.2)
				-- tagged out
				local place = ada.place
				t.truthy((kit.service:debug("tag", bea.seat, ada.seat)))
				kit.run(0.1)
				t.truthy(ada.out)
				local tag = ada.last("paintball_tag")
				t.deepEq({ tag.by, tag.id, tag.scores, tag.tags, tag.outs }, { bea.seat, ada.seat, { 0, 1 }, 1, 1 })
				-- a client that goes on walking while out gets nowhere
				dropped = stats.movesDropped
				ada.out = false
				kit.walk(ada, -30, -2)
				ada.out = true
				t.truthy(stats.movesDropped > dropped)
				t.eq(stats.movesRefused, 0)
				t.near(kit.service.poses[ada.seat].x, -36, 0.01, "held where it was tagged")
				local snap = ada.snaps[#ada.snaps]
				local mine: any = nil
				for _, body in snap.bodies do
					if body.id == ada.seat then
						mine = body
					end
				end
				t.truthy(Wire.has(mine.bits, Wire.BIT.out), "and shown as out")
				-- back after respawnSecs: a new placement, in her room, protected
				local feel = kit.state().feel
				t.truthy(kit.untilTrue(feel.respawnSecs + 0.5, function(): boolean
					return ada.place == place + 1
				end))
				t.falsy(ada.out)
				t.truthy(Arena.inRoom(kit.arena.spawnRooms[1], ada.x, ada.y + 0.1, ada.z))
				t.near(ada.safeUntil - tag.at, feel.protectSecs, 1e-6)
				t.eq(ada.stub.body.teleports, 2)
				kit.run(0.3)
				t.eq(stats.movesRefused, 0, "and her stream goes on from the new placement")
			end)
		end
	)

	t.test("stepping off a ledge and dropping is accepted; hovering is not, and the body is put down", function()
		Kit.play(function(kit)
			local ada = pair(kit)
			local stats = kit.service:stats()
			local top = Arena.FLOOR_HEIGHT
			t.eq(ada.y, top, "her spawn room stands on the platform")
			kit.walk(ada, -30.2, -2)
			-- off the east edge (x = -30) and down, 196 studs/s^2, still drifting east
			ada.auto = false
			ada.air = true
			local fell = 0
			while ada.y > 0 do
				fell += 1 / Clock.SEND_HZ
				ada.x += Body.WALK / Clock.SEND_HZ
				ada.y = math.max(0, top - 0.5 * 196.2 * fell * fell)
				ada.move()
				kit.run(1 / Clock.SEND_HZ)
			end
			ada.air = false
			ada.move()
			kit.run(0.2)
			t.eq(stats.movesRefused, 0, "the fall cost nothing")
			t.near(kit.service.poses[ada.seat].y, 0, 0.01)
			t.truthy(kit.service.poses[ada.seat].x > -30)
			-- rising into the air from the floor is refused, three times is a correction back to the floor
			local place, landedX = ada.place, ada.x
			for i = 1, 3 do
				ada.move({ y = 4 + i })
				kit.run(1 / Clock.SEND_HZ)
			end
			kit.run(0.1)
			t.eq(stats.movesRefused, 3)
			t.eq(stats.corrections, 1)
			local fix = ada.last("paintball_correct")
			t.deepEq({ fix.why, fix.place, fix.y }, { "wall", place + 1, 0 })
			t.near(fix.x, landedX, 0.01)
			t.eq(ada.place, place + 1, "the client obeys: its Moves carry the new number")
			ada.auto = true
			kit.run(0.3)
			t.eq(stats.movesRefused, 3)
		end, { arena = Kit.hall({ ledge = true }) })
	end)

	t.test(
		"a running jump off a ledge costs nothing: every Move of the arc is accepted, at 0 and at 150 ms, and she lands where a jump lands",
		function()
			for _, delay in { 0, 5 } do
				Kit.play(function(kit)
					local ada = pair(kit, { delay = delay, jitter = if delay > 0 then 2 else 0 })
					local stats = kit.service:stats()
					local top = Arena.FLOOR_HEIGHT
					local sprint = Body.speed(0, true, kit.state().feel)
					kit.walk(ada, -36, -2)
					local before = ada.stub.body.teleports
					-- she sprints east, leaves the ground a stud before the edge (x = -30) and sails out
					ada.sprint = true
					kit.walk(ada, -31, -2, sprint)
					local g, v = 196.2, math.sqrt(2 * 196.2 * Body.JUMP_HEIGHT)
					-- (the body the server sees is the engine's replica of hers, nine frames behind her own Moves:
					-- ten studs above her by the end of the drop)
					local tau = 0
					local trail: { { number } } = {}
					local function replica()
						table.insert(trail, { ada.x, ada.y, ada.z })
						local was = trail[math.max(1, #trail - 9)]
						local body = ada.stub.body
						body.x, body.y, body.z = Arena.toWorld(kit.place, was[1], was[2], was[3])
					end
					ada.bodyApart = true
					ada.air = true
					while ada.y > 0 do
						tau += 1 / 60
						ada.x += sprint / 60
						ada.y = math.max(0, top + v * tau - g / 2 * tau * tau)
						replica()
						kit.frame()
					end
					ada.air = false
					for _ = 1, 10 do
						ada.x += sprint / 60
						replica()
						kit.frame()
					end
					ada.bodyApart = false
					kit.walk(ada, ada.x + 4, -2, sprint)
					kit.run(0.5)
					t.eq(stats.movesRefused, 0, `no Move of the jump was refused ({delay} frames of delay each way)`)
					t.eq(stats.corrections, 0)
					t.eq(ada.stub.body.teleports, before, "and her body was never put back")
					t.near(kit.service.poses[ada.seat].y, 0, 0.01)
					t.truthy(kit.service.poses[ada.seat].x > -30 + 10, "a dozen studs out from the ledge")
				end, { arena = Kit.hall({ ledge = true }) })
			end
		end
	)

	t.test(
		"walking out over the edge without falling lasts a third of a second, and ends on the floor below",
		function()
			Kit.play(function(kit)
				local ada = pair(kit)
				local stats = kit.service:stats()
				local top = Arena.FLOOR_HEIGHT
				kit.walk(ada, -30.2, -2)
				-- on past the edge at the same height: a "fall" that does not come down
				kit.walk(ada, 20, -2)
				t.truthy(stats.corrections >= 1)
				local fix = ada.last("paintball_correct")
				t.eq(fix.y, 0, "put down on the floor under where it hung")
				local reach = fix.x - -30
				-- (a stud of footprint at the edge, then no longer level than a hop is)
				t.truthy(reach <= 1 + Body.WALK * 0.45, `{reach} studs of air`)
				t.eq(ada.y, 0)
				t.truthy(top > 0 and T.fallSecs > 0.45)
			end, { arena = Kit.hall({ ledge = true }) })
		end
	)

	t.test(
		"a corner cut by two lost Moves is accepted; a step through the wall is refused and the body put back",
		function()
			Kit.play(function(kit)
				local ada = pair(kit)
				local stats = kit.service:stats()
				kit.walk(ada, -36, -2)
				kit.walk(ada, -31.5, -1.5) -- beside the wall's end, on its west side
				kit.run(0.1)
				t.eq(stats.movesRefused, 0)
				-- she walks round the end of the wall; the two Moves of the corner are lost
				ada.silent = true
				kit.walk(ada, -31.5, 1.2)
				kit.walk(ada, -29.3, 1.2)
				ada.silent = false
				kit.walk(ada, -27.5, 1.2)
				kit.run(0.1)
				t.eq(stats.movesRefused, 0, "the straight line clips the corner; the L she walked is clear")
				t.near(kit.service.poses[ada.seat].x, -27.5, 0.01)
				kit.walk(ada, -27, -5) -- down the east side
				kit.run(0.1)
				t.eq(stats.movesRefused, 0)
				-- and now straight through it
				local place = ada.place
				ada.auto = false
				for _ = 1, 3 do
					ada.move({ x = -31 })
					kit.run(1 / Clock.SEND_HZ)
				end
				kit.run(0.1)
				t.eq(stats.movesRefused, 3)
				t.eq(stats.corrections, 1)
				local fix = ada.last("paintball_correct")
				t.deepEq({ fix.why, fix.place }, { "wall", place + 1 })
				t.near(fix.x, -27, 0.01, "back on the last pose the server accepted")
				t.eq(ada.stub.body.teleports, 2, "the real body was put there (once at the spawn, once now)")
				ada.auto = true
				kit.walk(ada, -27, -8)
				t.eq(stats.movesRefused, 3, "and walks on from it")
			end, { arena = Kit.hall({ wall = true }) })
		end
	)

	t.test(
		"a speed liar gains nothing: it is refused, corrected, and over three seconds gets no further than a walk",
		function()
			Kit.play(function(kit)
				local ada = pair(kit)
				local stats = kit.service:stats()
				kit.walk(ada, -36, -2)
				kit.run(0.2)
				local from = kit.service.poses[ada.seat].x
				-- three times walking pace, and it keeps going from wherever the server puts it back
				local began = kit.now()
				kit.walk(ada, 30, -2, 3 * Body.WALK)
				local took = kit.now() - began
				kit.run(0.2)
				t.truthy(stats.movesRefused > 10 and stats.corrections >= 3, `{stats.corrections} corrections`)
				t.eq(ada.last("paintball_correct").why, "speed")
				-- (kit.walk ends when the CLIENT believes it has arrived: the server's pose is the truth)
				local got = kit.service.poses[ada.seat].x - from
				local honest = Body.WALK * T.speedTolerance * took + Body.WALK * T.speedTolerance * T.speedWindow
				t.truthy(got <= honest, `{got} studs in {took} s; walking allows {honest}`)
				-- a body moved apart from the pose it reports (the real body left behind) is refused too
				ada.x = kit.service.poses[ada.seat].x
				kit.run(0.3)
				local refused = stats.movesRefused
				ada.bodyApart = true
				ada.stub.body.x += 2 * T.bodySlack
				kit.run(0.2)
				t.truthy(stats.movesRefused > refused)
			end)
		end
	)

	t.test("the other team's spawn room is shut: a pose inside it is refused like a wall", function()
		Kit.play(function(kit)
			local ada = pair(kit)
			local stats = kit.service:stats()
			kit.walk(ada, -32, -2)
			t.eq(stats.movesRefused, 0)
			-- team 2's room begins at x = -30: she keeps walking east for a second
			for _ = 1, 60 do
				ada.x += Body.WALK / 60
				kit.frame()
			end
			kit.run(0.2)
			t.truthy(stats.corrections >= 1)
			local fix = ada.last("paintball_correct")
			t.eq(fix.why, "wall")
			t.truthy(fix.x < -30, "put back outside it")
			t.eq(ada.left, nil)
			t.truthy(kit.service.poses[ada.seat].x < -30)
		end, { arena = Kit.hall({ room2 = -30 }) })
	end)

	t.test("walking into an exit room ends your match: you stand in the lobby and a bot has your seat", function()
		Kit.play(function(kit)
			local ada, bea = pair(kit)
			kit.walk(ada, -36, -2)
			kit.walk(ada, -36, 12)
			kit.run(0.2)
			t.eq(ada.seat, nil)
			t.deepEq({ ada.left.why, ada.left.text }, { "exit", Contract.textFor("exit") })
			local _, _, lz = Arena.toLocal(kit.place, ada.stub.body.x, ada.stub.body.y, ada.stub.body.z)
			t.truthy(lz > Arena.HALF)
			local r = roster(kit)
			t.deepEq({ r.people, r.bots, r.sides }, { 1, 7, { 4, 4 } })
			t.truthy(bea.seat ~= nil)
		end, { arena = Kit.hall({ exit = true }) })
	end)

	t.test(
		"a client that goes silent holds its pose and cannot fire after half a second, and after five is taken off and a bot takes the seat",
		function()
			Kit.play(function(kit)
				local ada, bea = pair(kit)
				kit.walk(ada, -36, -2)
				kit.run(0.2)
				ada.silent = true
				kit.run(Clock.STALE_SECS + 0.1)
				local shot = ada.fire(1, 0, 0)
				kit.run(0.1)
				t.deepEq({ ada.acks[shot].ok, ada.acks[shot].why }, { false, "stale" })
				t.near(kit.service.poses[ada.seat].x, -36, 0.01, "it stands where it last was, and can be hit")
				t.truthy(kit.service.ctx.session.rules.canBeHit(kit.state(), ada.seat, kit.now()))
				kit.run(Clock.DROP_SECS)
				t.eq(ada.seat, nil)
				t.deepEq({ ada.left.why, ada.left.text }, { "dropped", Contract.textFor("dropped") })
				local r = roster(kit)
				t.deepEq({ r.people, r.bots, r.sides }, { 1, 7, { 4, 4 } })
				t.truthy(bea.seat ~= nil, "the match goes on for the others")
			end)
		end
	)

	t.test(
		"a player who neither moves, turns nor fires for a minute of live play is taken off; one who only turns is not",
		function()
			Kit.play(function(kit)
				local ada, bea = pair(kit)
				kit.walk(ada, -36, -2)
				kit.walk(bea, 36, -2)
				-- Ada stands and sends the same pose; Bea stands and looks about
				for i = 1, R.idleSecs + 2 do
					bea.yaw = (i % 2) * 0.3
					kit.run(1)
				end
				t.eq(ada.seat, nil)
				t.deepEq({ ada.left.why, ada.left.text }, { "idle", Contract.textFor("idle") })
				t.truthy(bea.seat ~= nil)
				local r = roster(kit)
				t.deepEq({ r.people, r.bots }, { 1, 7 })
			end)
		end
	)

	t.test(
		"the monitors: the station's name while the arena is empty, both scores and the clock during a match, the result at the end card",
		function()
			Kit.play(function(kit)
				local FakeEngine = require("@tests/lib/FakeEngine")
				local roblox = require("@lune/roblox")
				local monitor = FakeEngine.part(Arena.MONITOR, roblox.CFrame.new(0, 0, 0), kit.service.hw)
				local function shown(): string
					local gui = monitor:FindFirstChild("PaintballScreen")
					local label = gui and gui:FindFirstChild("Text")
					return if label then label.Text else ""
				end
				local ada, bea = pair(kit)
				kit.run(1.1)
				t.truthy(string.find(shown(), "ORANGE 0  -  0 TEAL", 1, true), shown())
				t.truthy(string.find(shown(), "\n7:5%d$"), "eight minutes on the clock, counting down: " .. shown())
				t.truthy((kit.service:debug("tag", bea.seat, ada.seat)))
				kit.run(1.1)
				t.truthy(string.find(shown(), "ORANGE 0  -  1 TEAL", 1, true), shown())
				t.truthy((kit.service:debug("end")))
				kit.run(1.2)
				t.truthy(string.find(shown(), "Teal wins 1 - 0", 1, true), shown())
				kit.w.svc:leave(ada.stub, "left")
				kit.w.svc:leave(bea.stub, "left")
				kit.run(1.2)
				t.eq(shown(), "Paintball match")
			end)
		end
	)

	t.test(
		"the service's own hands on a real body: the rig's player joins at the prompt, her body is put in her spawn room in the match's collision group, and back in the lobby in its own group when she is dropped",
		function()
			Kit.play(function(kit)
				local w = kit.w
				local body = w.body
				local FakeEngine = require("@tests/lib/FakeEngine")
				body.Parent = FakeEngine.workspace() -- (a body that is in the world: one with no parent is gone)
				local limb = FakeEngine.part("LeftFoot", body.PrimaryPart.CFrame, body)
				Rig.press(w, Contract.STATION)
				kit.run(0.5)
				t.truthy(kit.session.seats[1] == w.player and not kit.session.gone[1], "she is seated")
				local root = body.PrimaryPart
				local sp = kit.arena.spawns[1][1]
				local x, y, z = Arena.toLocal(kit.place, root.Position.X, root.Position.Y, root.Position.Z)
				t.near(x, sp.x, 1e-3)
				t.near(y, sp.y + 3, 1e-3, "her root stands its own height over the spawn point")
				t.near(z, sp.z, 1e-3)
				t.deepEq(
					{ root.CollisionGroup, limb.CollisionGroup },
					{ Contract.COLLISION_GROUP, Contract.COLLISION_GROUP }
				)
				t.truthy(kit.service:inPlay(w.player, body))
				-- while her client is the contract's stub it sends no pose: she is silent, and then taken off. Once
				-- the client lane's own client is behind the rig's player it speaks for her, and she leaves by
				-- the framework instead: either way the service's hands put her body back
				kit.run(Clock.DROP_SECS + T.placeGrace + 0.5)
				if kit.session.phase == "idle" then
					local left = Rig.last(w.got, "left")
					t.truthy(left ~= nil and left.why == "dropped", "she was told why")
				else
					local stats = kit.service:stats()
					t.eq(
						stats.movesRefused,
						0,
						`her own client's Moves are not refused ({stats.movesAccepted} accepted, {stats.movesDropped} dropped)`
					)
					w.svc:leave(w.player, "left")
					kit.run(0.5)
					t.eq(kit.session.phase, "idle")
				end
				x, y, z = Arena.toLocal(kit.place, root.Position.X, root.Position.Y, root.Position.Z)
				t.falsy(Arena.inVolume(x, y, z), "back in the lobby")
				t.deepEq({ root.CollisionGroup, limb.CollisionGroup }, { "Default", "Default" })
			end, { realEngine = true })
		end
	)
end
