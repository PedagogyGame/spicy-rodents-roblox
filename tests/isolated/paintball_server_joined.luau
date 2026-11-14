--!strict
-- tests/isolated/paintball_server_joined.luau: the paintball server WITH THE OTHER LANES' WORK BESIDE IT, for
-- tests/unit/paintball_server.spec.luau (run in its own Lune process: tests/lib/Isolated). The server lane's
-- other cases put a scripted match model in Rules' place, scripted bots in the brains', and stand in a hall
-- of the lane's own, because in the lane's base all three are stubs or stand-ins. These cases put NOTHING in
-- anything's place: the real PaintballService on the real match model (Shared/Minigames/Paintball/Rules),
-- the real brains (Server/Minigames/Paintball/Bots) and the game's own building (ArenaData.build()),
-- building-blind (every place is read from the arena's own spawn points and navigation graph).
-- THEY RUN BY THEMSELVES ONCE THE MATCH MODEL IS REAL. real() looks at Rules.luau on disk: while it is the
-- contract's stub the one case here says so and passes, and nothing is proven (with PAINTBALL_JOINED=1 that
-- line is a failure); once it is the lane's own, it must go live when its briefing is over, and a model that
-- errors or does not fails the case with why. So in the server lane's own tree this file is one line of a report, and in the joined tree it is:
--   * the server check (tests/engine/PaintballFlow) with the real match and the real brains in the real
--     building: the pass, four a side, the briefing, the bots' own balls and tags, a scripted tag, the end
--     card, the next match, leaving;
--   * a person at 80 ms among the real bots: she walks out of her spawn room along the building's own graph
--     and patrols outside it, firing; over half a minute of live play not one of her Moves is refused, no
--     click of hers is refused for anything her own stream said (origin, sprint, stale), her magazine counts
--     down in the acks and comes back after the reload, she may be tagged by a bot and comes back placed
--     anew, and every message she hears is one the wire knows;
--   * a whole match from its briefing to the next one's: people at 80, 150 and 300 ms (jitter, and one
--     unreliable packet in twenty lost) patrol and fire among the real bots; one leaves and a bot has her
--     seat and her side; one joins late and is shown the match so far (the roster, the feel, the paint);
--     the clock runs out, the card names the result, a join is refused for as long as the card is up, and
--     the next match begins by itself with the people on the sides they ended on, placed anew, on a clean
--     building. All along: no Move and no click of an honest client refused for what its own stream said,
--     the sides level, the scores the tags, every message one the wire knows; what a step cost is printed.
-- (The lane's other cases can be run against the real model too: PAINTBALL_REAL=1, see the kit.)
-- Interface: return function(t) (the spec shape); real() -> boolean
local Arena = require("@shared/Minigames/Paintball/Arena")
local ArenaData = require("@shared/Minigames/Paintball/ArenaData")
local Body = require("@shared/Minigames/Paintball/Body")
local Clock = require("@shared/Minigames/Paintball/Clock")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Rules = require("@shared/Minigames/Paintball/Rules")
local PaintballFlow = require("@tests/engine/PaintballFlow")
local Kit = require("@tests/isolated/paintball_server_kit")

local R = Contract.Rules

-- Is the match model the real one? Decided by the file (Kit.laneBuilt: Rules.luau no longer the contract's
-- stub). When it is the real one it must go live when its briefing is over: an error, or a model that does not,
-- fails here with what went wrong (never a quiet "not joined").
local RULES_FILE = "src/shared/Minigames/Paintball/Rules.luau"
local function real(): boolean
	if not Kit.laneBuilt(RULES_FILE) then
		return false
	end
	local state = Rules.init(2, 1)
	Rules.sync(state, 1000)
	Rules.step(state, 0)
	Rules.sync(state, 1000 + R.briefingSecs + 1)
	Rules.step(state, 0.1)
	assert(state.phase == "live", `the real match model did not go live after its briefing (phase {state.phase})`)
	return true
end

-- The nodes to walk from `from` to the nearest node that is `beyond` links outside every spawn room, by the
-- building's own links (breadth first); nil if there is no way.
local function wayOut(arena: Arena.Arena, from: number, beyond: number): { number }?
	local next: { [number]: { number } } = {}
	for _, link in arena.links do
		next[link.a] = next[link.a] or {}
		next[link.b] = next[link.b] or {}
		table.insert(next[link.a], link.b)
		table.insert(next[link.b], link.a)
	end
	local cameFrom: { [number]: number } = { [from] = 0 }
	local outside: { [number]: number } = { [from] = 0 } -- links walked since leaving the rooms
	local queue = { from }
	local head = 1
	while head <= #queue do
		local at = queue[head]
		head += 1
		if outside[at] >= beyond then
			local path = {}
			local n = at
			while n ~= 0 do
				table.insert(path, 1, n)
				n = cameFrom[n]
			end
			return path
		end
		for _, to in next[at] or {} do
			if cameFrom[to] == nil then
				local node = arena.nodes[to]
				cameFrom[to] = at
				outside[to] = if node.team ~= 0 or node.kind == "spawn" then 0 else outside[at] + 1
				table.insert(queue, to)
			end
		end
	end
	return nil
end

-- A person who walks out of her spawn room along the building's own graph and patrols the last link of the
-- way out, clicking along her look every `every` frames while she is outside her room. step(frame) is called
-- once a frame, before kit.frame(); she plans her way afresh every time she is placed anew.
type Patrol = { step: (frame: number) -> (), fired: number, placements: number }
local function patrol(kit: Kit.Kit, c: Kit.Client, every: number): Patrol
	local arena: Arena.Arena = kit.arena
	local route: { Arena.NavNode } = {}
	local at, leg, lastPlace = 1, 1, -1
	local p = { fired = 0, placements = 0 } :: Patrol
	-- her route: from the spawn point to the nearest node of her room in clear sight, out by the links
	local function plan()
		local best: Arena.NavNode? = nil
		local bestD = math.huge
		for _, node in arena.nodes do
			local d = (node.x - c.x) ^ 2 + (node.z - c.z) ^ 2
			if
				math.abs(node.y - c.y) < 1
				and d < bestD
				and Arena.clearPath(arena.sweep, c.x, c.z, node.x, node.z, c.y + Arena.CHEST)
			then
				best, bestD = node, d
			end
		end
		assert(best, "a node of the graph stands in clear sight of the spawn point")
		local path = wayOut(arena, (best :: Arena.NavNode).id, 3)
		assert(path and #path >= 3, "the graph leads out of the spawn room")
		route = {}
		for _, id in path :: { number } do
			table.insert(route, arena.nodes[id])
		end
		at, leg = 1, 1
	end
	function p.step(frame: number)
		if c.seat == nil or c.place == 0 then
			return
		end
		if c.place ~= lastPlace then
			-- (placed anew: at the start, after every time a bot tags her, at a new match)
			p.placements += 1
			lastPlace = c.place
			plan()
		end
		if c.out then
			return
		end
		local state = kit.state()
		local slot = state.slots[c.seat]
		local target = route[at]
		local dx, dz = target.x - c.x, target.z - c.z
		local d = math.sqrt(dx * dx + dz * dz)
		if d < 0.05 then
			-- the next node of the way out; at its end, to and fro along its last link
			if at == #route then
				leg = -1
			elseif at == #route - 1 and leg == -1 then
				leg = 1
			end
			at += leg
		else
			local step = math.min(d, Body.speed(0, false, state.feel) / 60)
			c.x += dx / d * step
			c.z += dz / d * step
			local ground = arena.ground(c.x, c.y + 0.5, c.z)
			assert(ground, "the graph's links lie over floor")
			c.y = ground
			c.yaw = math.atan2(-dx, -dz)
		end
		local outside = not Arena.inRoom(arena.spawnRooms[slot.team], c.x, c.y + 0.1, c.z, 1.5)
		if outside and frame % every == 0 then
			local lx, ly, lz = Body.look(c.yaw, 0)
			c.fire(lx, ly, lz)
			p.fired += 1
		end
	end
	return p
end

return function(t)
	local asked, isReal = pcall(real)
	if not asked then
		t.test("joined: the real match model works", function()
			error(isReal, 0)
		end)
		return
	end
	if not isReal then
		Kit.waiting(t, "the lanes are not joined here: the match model is the contract's stub (it never goes live)")
		return
	end

	t.test(
		"joined: the server check passes with the real match and the real brains in the game's own building (the pass, four a side, the bots' own balls and tags, a scripted tag, the end card, the next match, leaving)",
		function()
			local result: any = nil
			Kit.play(function(kit: Kit.Kit)
				local ann, bob = kit.client("Ann", { auto = false }), kit.client("Bob", { auto = false })
				result = PaintballFlow.play(kit.w.svc, { Arena = Arena, Contract = Contract, Clock = Clock }, {
					players = { ann.stub, bob.stub },
					step = kit.run,
					liveSeconds = 12,
					positionOf = function(player: any): (number?, number?, number?)
						return player.body.x, player.body.y + 3, player.body.z
					end,
					groupOf = function(player: any): string?
						return if player.body.ghost then Contract.COLLISION_GROUP else "Default"
					end,
				})
			end, { realPass = true, realModel = true, arena = ArenaData.build() })
			t.eq(table.concat(result.failures, "; "), "", "what the server check found")
			t.truthy(result.ok)
			t.truthy(result.numbers.balls >= 1, `the bots fired {result.numbers.balls} balls`)
			t.truthy(type(result.numbers.banner) == "string")
			print(
				`  (joined flow: live watched {result.numbers.liveSeconds} s, {result.numbers.balls} balls, {result.numbers.tags} tags, banner "{result.numbers.banner}")`
			)
		end
	)

	t.test(
		"joined: a person at 80 ms among the real bots walks out of her spawn room along the building's own graph and patrols, firing: no Move refused, no click refused for what her own stream said, the magazine counted in the acks, every message one the wire knows",
		function()
			Kit.play(function(kit: Kit.Kit)
				local stats = kit.service:stats()
				local ada = kit.client("Ada", { delay = 5, jitter = 1 })
				t.truthy((kit.join(ada)))
				kit.run(0.5)
				t.truthy(ada.seat ~= nil and ada.place ~= 0, "seated and placed")
				kit.live()

				local walk = patrol(kit, ada, 20) -- (a click every third of a second while she is outside her room)
				local okShots, lowest = 0, R.magazine
				local badWhy: { string } = {}
				local seenAcks = 0
				local tagsOnHer = 0
				for frame = 1, 30 * 60 do
					walk.step(frame)
					kit.frame()
					for shot = seenAcks + 1, ada.shot do
						local a = ada.acks[shot]
						if a == nil then
							break
						end
						seenAcks = shot
						t.truthy(a.rounds >= 0 and a.rounds <= R.magazine, `an ack with {a.rounds} rounds`)
						lowest = math.min(lowest, a.rounds)
						if a.ok then
							okShots += 1
						elseif a.why == "origin" or a.why == "sprint" or a.why == "stale" then
							table.insert(badWhy, `shot {shot}: {a.why}`)
						end
					end
					local tags = 0
					for _, tag in ada.tags do
						if tag.id == ada.seat then
							tags += 1
						end
					end
					tagsOnHer = tags
				end
				local fired, respawnsAfterTag = walk.fired, walk.placements - 1
				t.eq(stats.movesRefused, 0, "an honest walk in the real building, among the real bots")
				t.eq(stats.corrections, 0)
				t.truthy(stats.movesAccepted > 200, `{stats.movesAccepted} Moves accepted`)
				t.deepEq(badWhy, {}, `no click was refused for what her own stream said: {table.concat(badWhy, ", ")}`)
				t.truthy(fired >= 10, `she clicked {fired} times`)
				t.truthy(okShots >= 5, `{okShots} of her {fired} clicks were shots`)
				t.truthy(lowest <= 1, `her magazine was counted down in the acks (lowest {lowest})`)
				t.truthy(respawnsAfterTag >= tagsOnHer - 1, `tagged {tagsOnHer} times, placed anew {respawnsAfterTag}`)
				local state = kit.state()
				t.eq(state.scores[1] + state.scores[2], stats.tags, "the scores are the tags")
				print(
					`  (joined person: {stats.movesAccepted} Moves accepted, {fired} clicks, {okShots} shots, lowest magazine {lowest}, tagged {tagsOnHer} times, {stats.balls} balls and {stats.tags} tags in all, {stats.shotsRefused} clicks refused)`
				)
			end, { realModel = true, arena = ArenaData.build() })
		end
	)

	t.test(
		"joined: a whole match from its briefing to the next one's, among the real bots in the game's own building: people at 80, 150 and 300 ms with jitter and loss patrol and fire; one leaves and a bot has her seat and side; one joins late and is shown the match so far; the clock runs out, a join is refused while the card is up, and the next match begins by itself with the people on the sides they ended on, on a clean building; no honest Move or click refused, the sides level, the scores the tags",
		function()
			Kit.play(function(kit: Kit.Kit)
				local arena: Arena.Arena = kit.arena
				local stats = kit.service:stats()
				local session = kit.session
				local ada = kit.client("Ada", { delay = 2, jitter = 1 })
				local bo = kit.client("Bo", { up = 4, down = 5, jitter = 2, lose = 0.05 })
				local cy = kit.client("Cy", { delay = 9, jitter = 2, lose = 0.05 })
				local dee = kit.client("Dee", { delay = 3, jitter = 1 })
				local eve = kit.client("Eve")
				local walks: { [any]: Patrol } = {}
				for _, c in { ada, bo, cy, dee } do
					walks[c] = patrol(kit, c, 20)
				end
				local stepMs: { number } = {}
				local badWhy: { string } = {}
				local seen: { [any]: number } = {}
				local frame = 0
				local function sides(): (number, number, number)
					local one, two, people = 0, 0, 0
					for id, slot in kit.state().slots do
						if slot.on then
							if slot.team == 1 then
								one += 1
							else
								two += 1
							end
							local key = session.seats[id]
							if key ~= nil and not session.gone[id] and (type(key) ~= "table" or key.ai ~= true) then
								people += 1
							end
						end
					end
					return one, two, people
				end
				-- `seconds` of everybody playing; the sides are looked at once a second
				local function play(seconds: number)
					for _ = 1, math.floor(seconds * 60) do
						frame += 1
						for c, walk in walks do
							if c.seat ~= nil then
								walk.step(frame)
							end
						end
						kit.frame()
						table.insert(stepMs, stats.stepMs)
						for c in walks do
							for shot = (seen[c] or 0) + 1, c.shot do
								local a = c.acks[shot]
								if a == nil then
									break
								end
								seen[c] = shot
								if not a.ok and (a.why == "origin" or a.why == "sprint" or a.why == "stale") then
									table.insert(badWhy, `{c.name}'s shot {shot}: {a.why}`)
								end
							end
						end
						if frame % 60 == 0 and session.phase == "playing" then
							local one, two = sides()
							t.truthy(one == two and one >= R.teamMin, `the sides are level: {one} v {two}`)
						end
					end
				end

				for _, c in { ada, bo, cy } do
					t.truthy((kit.join(c)))
				end
				kit.run(0.5)
				local one, two, people = sides()
				t.deepEq({ one, two, people }, { R.teamMin, R.teamMin, 3 }, "three people, and bots to four a side")
				t.eq(kit.service.match, 1)
				kit.live()
				play(15)

				-- Cy walks away: a bot has her seat and her side
				local cySeat, cyTeam = cy.seat, kit.state().slots[cy.seat].team
				kit.w.svc:leave(cy.stub, "left")
				play(1)
				t.truthy(cy.left ~= nil and cy.seat == nil, "Cy was told she left")
				local holder = session.seats[cySeat]
				t.truthy(type(holder) == "table" and holder.ai == true, "a bot has her seat")
				t.eq(kit.state().slots[cySeat].team, cyTeam, "on her side")
				local lx, ly, lz = Arena.toLocal(kit.place, cy.stub.body.x, cy.stub.body.y, cy.stub.body.z)
				t.falsy(Arena.inVolume(lx, ly, lz), "and she stands in the lobby")
				t.falsy(cy.stub.body.ghost, "in her own collision group")

				-- Dee joins late: a bot gives her its seat, and she is shown the match so far
				local wallPaint = 0
				for _, rec in ada.splats do
					if rec.body == 0 then
						wallPaint += 1
					end
				end
				t.truthy(wallPaint > 0, "there is paint on the building by now")
				t.truthy((kit.join(dee)))
				play(1)
				t.truthy(dee.seat ~= nil and dee.place ~= 0, "Dee is seated and placed")
				t.eq(dee.watch.match, 1)
				t.eq(#dee.watch.slots, 2 * R.teamMin, "the roster she was sent")
				t.eq(dee.extras.feel.ballSpeed, kit.state().feel.ballSpeed, "the feel")
				local had: { [number]: any } = {}
				for _, rec in ada.splats do
					had[rec.seq] = rec
				end
				local walls = 0
				for _, rec in dee.splats do
					if rec.body == 0 then
						walls += 1
					end
					t.truthy(had[rec.seq] ~= nil, `a splat of the match (seq {rec.seq})`)
				end
				t.truthy(
					walls >= math.min(wallPaint, R.splatPool),
					`the building's paint: {walls} of {wallPaint} (the pool keeps {R.splatPool})`
				)
				_, _, people = sides()
				t.eq(people, 3, "Ada, Bo and Dee")
				play(15)

				-- the clock runs out
				local sidesWere = {
					[ada] = kit.state().slots[ada.seat].team,
					[bo] = kit.state().slots[bo.seat].team,
					[dee] = kit.state().slots[dee.seat].team,
				}
				local state = kit.state()
				t.truthy((kit.service:debug("end")))
				play(1)
				t.eq(session.phase, "done", "the end card is up")
				t.eq(state.scores[1] + state.scores[2], stats.tags, "the scores are the tags")
				local card = ada.last("state", function(msg: any): boolean
					return msg.view ~= nil and msg.view.phase == "done"
				end)
				t.truthy(card ~= nil and type(card.view.result) == "table", "Ada was sent the result")
				local ok, words = kit.join(eve)
				t.falsy(ok, "a join during the end card is refused")
				t.truthy(type(words) == "string" and string.find(words :: string, "next match", 1, true), words)
				local ballsAtCard = stats.balls
				play(3)
				t.eq(stats.balls, ballsAtCard, "nothing is fired while the card is up")

				-- the next match begins by itself (the people stand where they are until they are placed in it)
				local placesWere = { [ada] = ada.place, [bo] = bo.place, [dee] = dee.place }
				t.truthy(
					kit.untilTrue(R.endCardSecs, function(): boolean
						return kit.service.match == 2
					end),
					"the service rolled on"
				)
				kit.run(0.5)
				t.eq(session.phase, "playing")
				t.eq(kit.service.match, 2, "the second match")
				t.truthy(kit.state() ~= state, "a new match model")
				t.deepEq(kit.state().scores, { 0, 0 })
				one, two, people = sides()
				t.deepEq({ one, two, people }, { R.teamMin, R.teamMin, 3 }, "the same three people, four a side")
				for c, team in sidesWere do
					t.truthy(c.seat ~= nil, `{c.name} is still seated`)
					t.eq(kit.state().slots[c.seat].team, team, `{c.name} is on the side she ended on`)
					t.truthy(c.place ~= placesWere[c], `{c.name} was placed anew`)
					t.truthy(
						Arena.inRoom(arena.spawnRooms[team], c.x, c.y + 0.1, c.z),
						`{c.name} stands in her spawn room`
					)
				end
				t.truthy((kit.join(eve)), "and the door is open again")
				play(1)
				t.eq(eve.watch.match, 2)
				t.eq(#eve.splats, 0, "the building is clean")
				kit.live()
				play(5)

				t.deepEq(badWhy, {}, `no click was refused for what its own stream said: {table.concat(badWhy, ", ")}`)
				t.eq(stats.movesRefused, 0, "no honest Move was refused, in two matches at 80, 150 and 300 ms")
				t.eq(stats.corrections, 0)
				local fired = 0
				for _, walk in walks do
					fired += walk.fired
				end
				t.truthy(fired >= 40, `the people clicked {fired} times`)
				table.sort(stepMs)
				local median, p99 = stepMs[#stepMs // 2], stepMs[math.floor(#stepMs * 0.99)]
				print(
					string.format(
						"  (joined match: %d Moves accepted, %d dropped, %d clicks, %d refused, %d balls, %d tags; the step with the real brains at 4 v 4: median %.3f ms, 99th centile %.3f ms)",
						stats.movesAccepted,
						stats.movesDropped,
						fired,
						stats.shotsRefused,
						stats.balls,
						stats.tags,
						median,
						p99
					)
				)
			end, { realModel = true, arena = ArenaData.build() })
		end
	)
end
