--!strict
-- The paintball server against THE GAME'S OWN BUILDING, whatever the arena lane has made of it
-- (Shared/Minigames/Paintball/ArenaData.build(); checklist PB-3, PB-5, PB-9). Building-blind: nothing here
-- knows a coordinate. Every place and every walk is read from the arena's own data (its spawn points, its
-- navigation nodes and links, its ramps), so these cases move with the building and say, of each new plan,
-- the one thing the server lane must know: that an honest player in it is never refused. The lane's
-- close-ups, which need a ledge and a rail at known places, stand on its own Greybox instead
-- (tools/games/paintball/server/Greybox; tests/unit/paintball_server_stream, paintball_server_core).
--   * every spawn point is a pose the server accepts, in its own team's room, and no click from it is a shot;
--   * every link of the navigation graph, walked and sprinted both ways as a client would send it (20 Moves
--     a second, the feet on the walking surface), costs not one refusal: the graph the bots walk is one the
--     server lets a person walk, stairs and doorways included;
--   * a hop taken running down every stair flight is free;
--   * the volume is sealed to balls: every ball ends inside it, on one of a box's six faces or at the end of
--     its life.
local Ballistics = require("@shared/Paintball/Ballistics")
local ArenaModule = require("@shared/Minigames/Paintball/Arena")
local ArenaData = require("@shared/Minigames/Paintball/ArenaData")
local Body = require("@shared/Minigames/Paintball/Body")
local Clock = require("@shared/Minigames/Paintball/Clock")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Wire = require("@shared/Minigames/Paintball/Wire")
local Stream = require("@server/Minigames/Paintball/Stream")
local Projectiles = require("@server/Paintball/Projectiles")

type Arena = ArenaModule.Arena
type NavNode = ArenaModule.NavNode

local SEND = 1 / Clock.SEND_HZ

local function lcg(seed: number): () -> number
	local s = seed
	return function(): number
		s = (s * 48271) % 2147483647
		return (s - 1) / 2147483646
	end
end

-- Walk a person from node a to node b in a straight line at `speed`, the feet following the walking surface,
-- as its client would send it. Returns how many Moves were refused, and the first refusal in words.
local function walk(arena: Arena, a: NavNode, b: NavNode, speed: number, bits: number): (number, string?)
	local feel = Contract.feel()
	local team = if a.team ~= 0 then a.team elseif b.team ~= 0 then b.team else 1
	local person = Stream.new("walker", 100)
	Stream.placed(person, a.x, a.y, a.z, 0, 100, feel, true)
	local dx, dz = b.x - a.x, b.z - a.z
	local length = math.sqrt(dx * dx + dz * dz)
	local refused, first = 0, nil :: string?
	local y = a.y
	local steps = math.max(1, math.ceil(length / (speed * SEND)))
	for i = 1, steps do
		local now = 100 + i * SEND
		local d = math.min(length, speed * SEND * i)
		local k = if length > 0 then d / length else 1
		local x, z = a.x + dx * k, a.z + dz * k
		-- (the feet follow the floor: up a step or a ramp, down a step or a ramp)
		local ground = arena.ground(x, y + 0.5, z)
		if ground == nil then
			return refused + 1, `no floor under the link at {x}, {y}, {z}`
		end
		y = ground
		local rec = { t = now, x = x, y = y, z = z, yaw = 0, pitch = 0, bits = bits, place = person.place }
		local verdict, why = Stream.judge(person, rec, now, arena, feel, arena.spawnRooms[3 - team])
		if verdict ~= "accepted" then
			refused += 1
			first = first or `{verdict} ({tostring(why)}) at {x}, {y}, {z}, {d} of {length} studs along`
		end
	end
	return refused, first
end

return function(t)
	local arena = ArenaData.build()
	local feel = Contract.feel()

	t.test(
		"the game's building: every spawn point is a pose the server accepts, in its own room, where no click is a shot",
		function()
			for team = 1, 2 do
				t.truthy(#arena.spawns[team] >= Contract.Rules.teamMax, `team {team} has a place for each of its eight`)
				for index, sp in arena.spawns[team] do
					local where = `team {team}'s spawn point {index}`
					t.truthy(
						ArenaModule.inRoom(arena.spawnRooms[team], sp.x, sp.y + 0.1, sp.z),
						`{where} is in its room`
					)
					local ground = arena.ground(sp.x, sp.y, sp.z)
					t.truthy(ground ~= nil and math.abs(ground - sp.y) < 0.05, `{where} is on the floor`)
					local person = Stream.new("ada", 100)
					Stream.placed(person, sp.x, sp.y, sp.z, sp.yaw, 100, feel, true)
					local rec =
						{ t = 100.05, x = sp.x, y = sp.y, z = sp.z, yaw = sp.yaw, pitch = 0, bits = 0, place = 1 }
					local verdict, why = Stream.judge(person, rec, 100.05, arena, feel, arena.spawnRooms[3 - team])
					t.eq(verdict, "accepted", `{where}: {tostring(why)}`)
					local ex, ey, ez = Body.eyePoint(sp.x, sp.y, sp.z, 0)
					t.eq(Stream.clickOk(person, 100.05, ex, ey, ez, arena, feel), "safe", where)
				end
			end
		end
	)

	t.test(
		"the game's building: every link of its navigation graph, walked and sprinted both ways at 20 Moves a second, costs not one refusal",
		function()
			t.truthy(#arena.links > 0, "the building has a graph")
			local walkSpeed = Body.speed(0, false, feel)
			local sprintSpeed = Body.speed(0, true, feel)
			local bad: { string } = {}
			local walked = 0
			for index, link in arena.links do
				local a, b = arena.nodes[link.a], arena.nodes[link.b]
				for _, pair in { { a, b }, { b, a } } do
					for _, pace in { { walkSpeed, 0 }, { sprintSpeed, Wire.BIT.sprint } } do
						local refused, first = walk(arena, pair[1], pair[2], pace[1], pace[2])
						walked += 1
						if refused > 0 and #bad < 12 then
							table.insert(
								bad,
								`link {index} ({link.kind}) from node {pair[1].id} to {pair[2].id} at {pace[1]} studs a second: {refused} refused, first {tostring(
									first
								)}`
							)
						end
					end
				end
			end
			t.eq(walked, #arena.links * 4)
			t.deepEq(bad, {})
		end
	)

	t.test("the game's building: a hop taken running down every stair flight is free", function()
		local V = math.sqrt(2 * 196.2 * Body.JUMP_HEIGHT)
		local G = 196.2
		local sprint = Body.speed(0, true, feel)
		t.truthy(#arena.ramps >= 2 * (ArenaModule.FLOORS - 1), "two flights a storey")
		for index, ramp in arena.ramps do
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
			for _, takeoffAfter in { 0.15, 0.3 } do
				local x0, y0, z0 = down(1)
				local person = Stream.new("dee", 100)
				Stream.placed(person, x0, y0, z0, 0, 100, feel, true)
				local refused = 0
				local takeoff, takeoffY = 100 + takeoffAfter, y0
				for i = 1, 200 do
					local now = 100 + i * SEND
					local d = 1 + sprint * (now - 100)
					if d > along - 0.5 then
						break
					end
					local x, y, z = down(d)
					local bits = Wire.BIT.sprint
					if now < takeoff then
						takeoffY = y
					else
						local tau = now - takeoff
						local arc = takeoffY + V * tau - G / 2 * tau * tau
						if arc > y then
							y = arc
							bits += Wire.BIT.air
						end
					end
					local rec = { t = now, x = x, y = y, z = z, yaw = 0, pitch = 0, bits = bits, place = 1 }
					if Stream.judge(person, rec, now, arena, feel) ~= "accepted" then
						refused += 1
					end
				end
				t.eq(refused, 0, `a hop {takeoffAfter} s into running down flight {index}`)
			end
		end
	end)

	t.test(
		"the game's building is sealed to balls: fired every way from its nodes, each ends on a box, on one of six faces, or at the end of its life, and none of them outside the volume",
		function()
			local sim = Projectiles.forArena(arena, feel)
			local rand = lcg(20261113)
			local ended, walls = 0, 0
			local bad: { string } = {}
			local half, top = ArenaModule.HALF, ArenaModule.HEIGHT
			local function onEnd(ball: Projectiles.Ball)
				ended += 1
				local x, y, z = ball.hx, ball.hy, ball.hz
				local face = 1
				if ball.hitWall then
					walls += 1
					face = Wire.faceOf(ball.nx, ball.ny, ball.nz)
				else
					-- (it flew its whole life: where it was then)
					x, y, z = Ballistics.position(
						ball.ox,
						ball.oy,
						ball.oz,
						ball.vx,
						ball.vy,
						ball.vz,
						feel.ballDrop,
						ball.age
					)
				end
				local inside = math.abs(x) <= half + 0.01
					and math.abs(z) <= half + 0.01
					and y >= -0.01
					and y <= top + 0.01
				if (not inside or face == Wire.FACE.none) and #bad < 8 then
					table.insert(bad, `a ball ended at {x}, {y}, {z} on face {face} (on a box: {ball.hitWall})`)
				end
			end
			local fired = 0
			local now = 100
			for _ = 1, 40 do
				for _ = 1, 25 do
					local node = arena.nodes[1 + math.floor(rand() * #arena.nodes)]
					local ex, ey, ez = Body.eyePoint(node.x, node.y, node.z, 0)
					local yaw, pitch = rand() * 2 * math.pi, (rand() - 0.5) * 2.4
					local lx, ly, lz = Body.look(yaw, pitch)
					local v = feel.ballSpeed
					Projectiles.fire(sim, 1, 1, ex, ey, ez, lx * v, ly * v, lz * v, 0, now)
					fired += 1
				end
				for _ = 1, 12 do
					now += 1 / 60
					Projectiles.step(sim, now, 1 / 60, {}, onEnd)
				end
			end
			for _ = 1, math.ceil(Contract.Rules.ballTtl * 60) + 2 do
				now += 1 / 60
				Projectiles.step(sim, now, 1 / 60, {}, onEnd)
			end
			t.eq(fired, 1000)
			t.eq(#sim.balls, 0, "none is still flying")
			t.eq(ended, fired)
			t.truthy(walls >= fired * 0.9, `{walls} of {fired} ended on a box`)
			t.deepEq(bad, {})
		end
	)
end
