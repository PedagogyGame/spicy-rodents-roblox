--!strict
-- tests/isolated/paintball_server_joined.luau: the paintball server WITH THE OTHER LANES' WORK BESIDE IT, for
-- tests/unit/paintball_server.spec.luau (run in its own Lune process: tests/lib/Isolated). The server lane's
-- other cases put a scripted match model in Rules' place, scripted bots in the brains', and stand in a hall
-- of the lane's own, because in the lane's base all three are stubs or stand-ins. These cases put NOTHING in
-- anything's place: the real PaintballService on the real match model (Shared/Minigames/Paintball/Rules),
-- the real brains (Server/Minigames/Paintball/Bots) and the game's own building (ArenaData.build()),
-- building-blind (every place is read from the arena's own spawn points and navigation graph).
-- THEY RUN BY THEMSELVES ONCE THE MATCH MODEL IS REAL. real() asks the model the one thing the stub cannot
-- do (go live when its briefing is over); while it cannot, the one case here says so and passes, and nothing
-- is proven. So in the server lane's own tree this file is one line of a report, and in the joined tree it is:
--   * the server check (tests/engine/PaintballFlow) with the real match and the real brains in the real
--     building: the pass, four a side, the briefing, the bots' own balls and tags, a scripted tag, the end
--     card, the next match, leaving;
--   * a person at 80 ms among the real bots: she walks out of her spawn room along the building's own graph
--     and patrols outside it, firing; over half a minute of live play not one of her Moves is refused, no
--     click of hers is refused for anything her own stream said (origin, sprint, stale), her magazine counts
--     down in the acks and comes back after the reload, she may be tagged by a bot and comes back placed
--     anew, and every message she hears is one the wire knows.
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

-- Is the match model the real one? The stub seats slots and keeps its clock, and never leaves the briefing.
local function real(): boolean
	local ok, live = pcall(function(): boolean
		local state = Rules.init(2, 1)
		Rules.sync(state, 1000)
		Rules.step(state, 0)
		Rules.sync(state, 1000 + R.briefingSecs + 1)
		Rules.step(state, 0.1)
		return state.phase == "live"
	end)
	return ok and live
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

return function(t)
	if not real() then
		t.test(
			"the lanes are not joined here: the match model is the contract's stub (it never goes live), so the joined cases wait and nothing of them is proven",
			function() end
		)
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
				local arena: Arena.Arena = kit.arena
				local stats = kit.service:stats()
				local ada = kit.client("Ada", { delay = 5, jitter = 1 })
				t.truthy((kit.join(ada)))
				kit.run(0.5)
				t.truthy(ada.seat ~= nil and ada.place ~= 0, "seated and placed")
				local team = kit.state().slots[ada.seat].team
				kit.live()

				-- her route: from the spawn point to the nearest node of her room, out by the links, and a
				-- patrol between the last two nodes of the way out
				local route: { Arena.NavNode } = {}
				local at, leg, lastPlace = 1, 1, -1
				local function plan()
					local best: Arena.NavNode? = nil
					local bestD = math.huge
					for _, node in arena.nodes do
						local d = (node.x - ada.x) ^ 2 + (node.z - ada.z) ^ 2
						if
							math.abs(node.y - ada.y) < 1
							and d < bestD
							and Arena.clearPath(arena.sweep, ada.x, ada.z, node.x, node.z, ada.y + Arena.CHEST)
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

				local fired, okShots, lowest = 0, 0, R.magazine
				local badWhy: { string } = {}
				local seenAcks = 0
				local tagsOnHer, respawnsAfterTag = 0, 0
				local speed = Body.speed(0, false, kit.state().feel) / 60
				for frame = 1, 30 * 60 do
					if ada.place ~= lastPlace then
						-- (placed anew: at the start, and after every time a bot tags her)
						if lastPlace ~= -1 then
							respawnsAfterTag += 1
						end
						lastPlace = ada.place
						plan()
					end
					if not ada.out and ada.seat ~= nil then
						local target = route[at]
						local dx, dz = target.x - ada.x, target.z - ada.z
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
							local step = math.min(d, speed)
							ada.x += dx / d * step
							ada.z += dz / d * step
							local ground = arena.ground(ada.x, ada.y + 0.5, ada.z)
							assert(ground, "the graph's links lie over floor")
							ada.y = ground
							ada.yaw = math.atan2(-dx, -dz)
						end
						-- a click every third of a second while she is outside her room
						local outside = not Arena.inRoom(arena.spawnRooms[team], ada.x, ada.y + 0.1, ada.z, 1.5)
						if outside and frame % 20 == 0 then
							local lx, ly, lz = Body.look(ada.yaw, 0)
							ada.fire(lx, ly, lz)
							fired += 1
						end
					end
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
				t.eq(stats.movesRefused, 0, "an honest walk in the real building, among the real bots")
				t.eq(stats.corrections, 0)
				t.truthy(stats.movesAccepted > 200, `{stats.movesAccepted} Moves accepted`)
				t.deepEq(badWhy, {}, "no click was refused for what her own stream said")
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
end
