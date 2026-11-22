--!strict
-- Validator round 8 (the round-7 review's findings; invariant D: no server system reads a PLAYER-HELD squirrel's root
-- to decide anything, it reads the place the server holds, MovementService.heldPlace, through one accessor):
--   D        a client writes its root far off between the server's watches (inside the paintball station, on a lane):
--            every place a server system reads for the body (ActorsRuntime.placeOf, the AI world record the duel,
--            the overhead watch, the lounge's guards, the drains and the hollows read, Game.animals for the paintball
--            pass, the bowling lanes and the pool tables) stays where the server holds it, and nothing acts there
--   release  the real Possession and MovementService: a root written 600 st off, the body given up and taken back: the
--            body let go, put and re-gated at the held place; a plain squirrel re-seats on the rail nearest it
--   audit    every read of a body's root in src/server is one the round-8 audit classified (a new one fails here)
--   slab     greedy falls through the hospital's roof at 2 to 30 packets a second, straight and slanting; a rise into a
--            low slab; a grounded claim sinking under the glue's old allowance
--   LOWs     lastGrab kept across a reset; the next driver inherits the meter, gaps and wall gaps; a Reset with no safe
--            sample on a wire goes to the first floor under the held place
-- The slab cases need build/Town.rbxm (bake first). About 15 s: `lune run tests/run.luau validator_r8`.
local fs = require("@lune/fs")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local Height = require("@shared/World/Height")
local Data = require("@shared/Data")
local Arena = require("@shared/Minigames/Paintball/Arena")
local MoveValidator = require("@server/Movement/MoveValidator")
local MovementService = require("@server/Movement/MovementService")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local ActorService = require("@server/Actors/ActorService")
local ActorsRuntime = require("@server/Actors/ActorsRuntime")
local Possession = require("@server/Actors/Possession")
local Squirrel = require("@server/Actors/Brains/Squirrel")
local Game = require("@server/Boot/Game")
local TestWorld = require("@tests/cheat/TestWorld")
local LiveRig = require("@tests/lib/LiveRig")
local BakedWorld = require("@tests/lib/BakedWorld")

type State = SquirrelMotor.State
type V3 = { x: number, y: number, z: number }

-- a flat world (ground at groundHeight), with optional floating slabs { minX, maxX, minZ, maxZ, bottom, top }: the
-- rays as the engine casts them (a ray starting inside a part does not meet it)
type Slab = { minX: number, maxX: number, minZ: number, maxZ: number, bottom: number, top: number }
local function worldWith(slabs: { Slab }?): (any, any)
	local world = TestWorld.build({ boxes = {} })
	local g = world.groundHeight
	local function wall(_ox: number, _oy: number, _oz: number, _dx: number, _dy: number, _dz: number): boolean
		return false
	end
	local function down(ox: number, oy: number, oz: number, _dx: number, dy: number, _dz: number): boolean
		local lo, hi = math.min(oy, oy + dy), math.max(oy, oy + dy)
		if lo <= g and hi >= g then
			return true
		end
		for _, s in slabs or {} do
			if ox > s.minX and ox < s.maxX and oz > s.minZ and oz < s.maxZ then
				local inside = oy > s.bottom and oy < s.top
				if
					not inside
					and ((dy < 0 and s.top <= hi and s.top >= lo) or (dy > 0 and s.bottom >= lo and s.bottom <= hi))
				then
					return true
				end
			end
		end
		return false
	end
	return world, ValidatorWorld.build(world, { wall = wall, down = down })
end

local function dist(a: V3, b: V3): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end

local function idle(_now: number): SquirrelMotor.Input
	return SquirrelMotor.idleInput(0)
end

return function(t)
	-- D ---------------------------------------------------------------------------------------------------------------
	t.test(
		"D: a root written inside the paintball station between watches: every place a system reads stays held",
		function()
			local world, vworld = worldWith(nil)
			local g = world.groundHeight
			-- (the station put 600 st off: the arena's frame there, its volume's inside at its local origin)
			local place = { x = 600, y = g, z = 0, yaw = 0 }
			local inside = { x = 600, y = g + 1, z = 0 }
			local cheating = false
			local rig: any
			rig = LiveRig.new({
				world = world,
				vworld = vworld,
				link = { latency = 0.05, jitter = 0, loss = 0 },
				seed = 8,
				rootCheat = function(p: V3, _now: number, _s: State)
					if cheating then
						p.x, p.y, p.z = inside.x, inside.y, inside.z
					end
				end,
			})
			rig:possess(SquirrelMotor.new(0, g, 0), idle)
			rig:run(3)
			local home = rig:place() :: V3
			t.truthy(home ~= nil, "a held place")
			local actor = { id = "squirrel_1", species = "squirrel", variant = "spicy", mode = "player" }
			local a = { id = 1, x = home.x, y = home.y, z = home.z, hip = 0, speed = 0 }
			local byTownId = { [1] = actor }
			local function placeOf(x: any): (number, number, number)
				return ActorsRuntime.placeOf(rig.movement, x, 0, a, 0, function(): (number, number, number)
					local r = rig.server.root
					return r.x, r.y, r.z
				end)
			end
			cheating = true
			local rootIn, readFar, frames, paintRoot, paintRead = 0, 0, 0, 0, 0
			for _ = 1, 120 do
				rig:run(1 / 60)
				frames += 1
				local r = rig.server.root
				if dist(r, inside) < 1 then
					rootIn += 1
				end
				-- the world record (the duel, the overhead watch, the lounge's guards, traffic, the drains, the hollows)
				ActorsRuntime.feedHeld(rig.movement, a, actor, 0, 0)
				-- the minigames' list (the paintball pass, the bowling lanes, the pool tables) and the kick's targets
				local list = Game.animals({ a }, byTownId, placeOf)
				local px, py, pz = placeOf(actor)
				for _, p in { { x = a.x, y = a.y, z = a.z }, list[1] :: any, { x = px, y = py, z = pz } } do
					if dist(p, home) > 1 then
						readFar += 1
					end
					local lx, ly, lz = Arena.toLocal(place, p.x, p.y, p.z)
					if Arena.inVolume(lx, ly, lz) then
						paintRead += 1
					end
				end
				local lx, ly, lz = Arena.toLocal(place, r.x, r.y, r.z)
				if Arena.inVolume(lx, ly, lz) then
					paintRoot += 1
				end
			end
			print(
				string.format(
					"      %d frames: the root inside the station in %d (the paintball pass would have knocked it %d times);"
						.. " a read off the held place %d, inside the station %d",
					frames,
					rootIn,
					paintRoot,
					readFar,
					paintRead
				)
			)
			t.truthy(rootIn > 0, "the root read the client's write")
			t.eq(readFar, 0, "reads off the held place")
			t.eq(paintRead, 0, "reads inside the station")
		end
	)

	-- release ---------------------------------------------------------------------------------------------------------
	t.test(
		"release: the real Possession lets the body go at the held place, never the root; the retake gates there",
		function()
			local world, vworld = worldWith(nil)
			local g = world.groundHeight
			local clock = { t = 0 }
			local body = { x = 0, y = g, z = 0, yaw = 0, anchored = true, alive = true }
			local resumed: V3? = nil
			local ops = {
				pose = function(b: any): (number, number, number, number)
					return b.x, b.y, b.z, b.yaw
				end,
				setMode = function(b: any, mode: string, _snap: any)
					b.anchored = mode == "ai"
				end,
				alive = function(b: any): boolean
					return b.alive
				end,
			}
			local engine = {
				streamAround = function() end,
				setOwner = function() end,
				setCharacter = function(p: any, m: any)
					p.Character = m
				end,
				rootOf = function(b: any): any
					return b
				end,
				markDriver = function() end,
				teleport = function(b: any, x: number, y: number, z: number, yaw: number)
					b.x, b.y, b.z, b.yaw = x, y, z, yaw
				end,
				now = function(): number
					return clock.t
				end,
				serverTime = function(): number
					return clock.t
				end,
			}
			local actors = ActorService.new(ops)
			local actor = actors:register(ActorService.actor(
				"squirrel_1",
				"squirrel",
				"normal",
				body,
				{
					suspend = function(): any
						return { vx = 0, vy = 0, vz = 0, mode = "idle" }
					end,
					resume = function(x: number, y: number, z: number)
						resumed = { x = x, y = y, z = z }
					end,
				} :: any
			))
			local validator = MoveValidator.new(vworld)
			local movement = MovementService.new({
				validator = validator,
				enforce = true,
				poseOf = function(a: any): (number?, number?, number?)
					local b = a.body
					return b.x, b.y, b.z
				end,
			})
			local possession = Possession.new({
				actors = actors,
				engine = engine :: any,
				onHandoff = function(a: any, p: any, kind: string)
					movement:onHandoff(a, p, kind)
				end,
				heldPose = function(a: any): (number?, number?, number?)
					return ActorsRuntime.heldPoseOf(movement, a, 0)
				end,
			})
			local player = { UserId = 7 }
			local ok = possession:possess(player, actor)
			t.truthy(ok, "possessed")
			-- packets at home, one a twentieth of a second; the root written 600 st off between the watches
			local seq = 0
			local function send(at: number)
				seq += 1
				local s = SquirrelMotor.new(0, g, 0)
				s.grounded, s.clock = true, at
				movement:packet("squirrel_1", "squirrel", {
					seq = seq,
					epoch = movement:epochOf("squirrel_1"),
					snapshot = SquirrelMotor.serialize(s),
				}, at)
			end
			for i = 1, 40 do
				clock.t = i / 20
				send(clock.t)
			end
			body.x, body.y, body.z = 600, g, 0 -- (the client's write: the root)
			local hx, hy, hz = movement:heldPlace("squirrel_1")
			possession:release(player, "swap")
			local r = resumed :: V3
			print(
				string.format(
					"      root at 600 st; held place %.1f, %.1f, %.1f; released at %.1f, %.1f, %.1f; the body at %.1f, %.1f, %.1f",
					hx or -1,
					hy or -1,
					hz or -1,
					r.x,
					r.y,
					r.z,
					body.x,
					body.y,
					body.z
				)
			)
			t.truthy(dist(r, { x = 0, y = g, z = 0 }) < 0.5, "released at the held place")
			t.truthy(dist(body :: any, { x = 0, y = g, z = 0 }) < 0.5, "the body put there")
			-- taken back: the gate is where the body is (the server's own pose since)
			possession:possess(player, actor)
			local gx, _, gz = movement:heldPlace("squirrel_1")
			t.truthy(
				gx ~= nil and math.abs(gx :: number) < 0.5 and math.abs(gz :: number) < 0.5,
				"the retake gated there"
			)
			-- a plain squirrel's brain re-seats on the rail nearest that place, not on the point it was taken from
			local routes = {
				{ id = 1, kind = "branch", length = 10, points = { { 100, g + 4, 0 }, { 110, g + 4, 0 } }, links = {} },
				{ id = 2, kind = "branch", length = 10, points = { { -5, g + 2, 3 }, { 5, g + 2, 3 } }, links = {} },
			}
			local near, s = Squirrel.reseat({
				routes = routes :: any,
				byId = function(id: number): any
					return routes[id]
				end,
			}, 0, g, 0)
			t.eq(near and near.id, 2, "the nearest rail")
			t.truthy(math.abs(s - 5) < 1e-6, `at its nearest point ({s})`)
		end
	)

	-- audit -----------------------------------------------------------------------------------------------------------
	t.test("audit: every read of a body's root in src/server is one the round-8 audit classified", function()
		-- (file -> the number of READS of a body's root: each occurrence, not each line (validator round 9, the round-8
		-- review's LOW: a second read on a counted line, or a new call of a root helper, hid), of PrimaryPart, GetPivot, a
		-- registry's poseOf, HumanoidRootPart, FindFirstChild("Root"), and the call sites (and definitions) of the root
		-- helpers rootOf, aheadOf and pivotOf; each classified in the round-8 and round-9 reports: art and props (never a
		-- body; the yard dogs' own CFrame, PeopleArt's figure), the AI's bodies (the server's own place), a held person,
		-- deer or fox (a kind the validator does not watch: ItemWorld's users, the lounge's guests and drinks, the sky
		-- lift's riders, paintball's players put where the service decided, the rafters' people), the watch itself (it
		-- judges the root), the network owner (Possession's setOwner: no place), a body the server has just put somewhere
		-- (read in the same thread), a rotation or a parent kept. A held squirrel's place is ActorsRuntime.placeOf /
		-- MovementService.heldPlace)
		local AUDITED: { [string]: number } = {
			["AI/Puppets.luau"] = 3,
			["Actors/ActorService.luau"] = 12,
			["Actors/ActorsRuntime.luau"] = 3,
			["Actors/BodyFactory.luau"] = 1,
			-- (9th, 2026-11-22, owner D29: tidy reads a shared vehicle's root, never a body)
			-- (10th to 12th, 2026-11-22, owner D30: the golf cart's passenger: the cart's root twice (its side to get off on,
			-- its network owner kept the driver's) and a person's body checked before it is put beside the cart; only
			-- people ride, never a squirrel)
			["Actors/DeviceService.luau"] = 12,
			["Actors/Possession.luau"] = 9,
			["Assets/HeroArt.luau"] = 3,
			["Assets/PeopleArt.luau"] = 5,
			["Assets/PinballArt.luau"] = 3,
			["Assets/TreeArt.luau"] = 2,
			["Assets/WhackArt.luau"] = 1,
			["Attractions/AttractionService.luau"] = 4,
			["Attractions/LoungeService.luau"] = 11,
			["Attractions/RafterService.luau"] = 5,
			-- (12th, 2026-11-21, owner D21: the road squirrels' cue parents a Sound to a knocked-flat body's PrimaryPart:
			-- a parent kept, not a place read; the body is the computer's)
			-- (13th and 14th, 2026-11-22, owner D29: the shared vehicles' roots for Vehicles/RideBumps, never a body; a held
			-- squirrel a shared vehicle bumped is put aside from its held place (ActorsRuntime.placeOf), its rotation kept)
			["Boot/Game.luau"] = 14,
			["Items/CornerStore.luau"] = 1,
			-- (14th, 2026-11-22, owner D30: F by the kick ball on the ground reads the kicker's root: a person's, checked
			-- human first, never a held squirrel's)
			["Items/ItemWorld.luau"] = 14,
			["Minigames/BowlingLane.luau"] = 2,
			["Minigames/FortuneCabinet.luau"] = 1,
			["Minigames/Games/AirHockey.luau"] = 1,
			["Minigames/MinigameService.luau"] = 3,
			["Minigames/Paintball/RealEngine.luau"] = 6,
			["Minigames/Pool/Hardware.luau"] = 1,
			["Movement/BodyPin.luau"] = 1,
			["Rides/SkyLiftService.luau"] = 13,
			["Wildlife/YardHazards.luau"] = 4,
		}
		local NEEDLES = {
			"PrimaryPart",
			"GetPivot",
			":poseOf(",
			"HumanoidRootPart",
			'FindFirstChild("Root")',
			"rootOf(",
			"aheadOf(",
			"pivotOf(",
		}
		local counts: { [string]: number } = {}
		local function scan(dir: string, rel: string)
			for _, e in fs.readDir(dir) do
				local path = `{dir}/{e}`
				local r = if rel == "" then e else `{rel}/{e}`
				if fs.isDir(path) then
					scan(path, r)
				elseif string.sub(e, -5) == ".luau" then
					local n = 0
					for line in string.gmatch(fs.readFile(path), "[^\n]+") do
						local code = string.gsub(line, "%-%-.*$", "")
						for _, needle in NEEDLES do
							local from = 1
							while true do
								local at = string.find(code, needle, from, true)
								if at == nil then
									break
								end
								n += 1
								from = at + #needle
							end
						end
					end
					if n > 0 then
						counts[r] = n
					end
				end
			end
		end
		scan("src/server", "")
		local bad = {}
		for file, n in counts do
			if AUDITED[file] ~= n then
				table.insert(bad, `{file}: {n} root reads (audited {AUDITED[file] or 0})`)
			end
		end
		for file, n in AUDITED do
			if n > 0 and counts[file] == nil then
				table.insert(bad, `{file}: none now (audited {n})`)
			end
		end
		table.sort(bad)
		for _, b in bad do
			print(`      {b}`)
		end
		t.eq(#bad, 0, "every root read classified (see the round-8 report's table; classify a new one there and here)")
		-- and the readers of a held squirrel go through the accessor
		local game = fs.readFile("src/server/Boot/Game.luau")
		for _, needle in
			{ "Game.animals(world.actors, rt.byTownId, rt.placeOf)", "rt.placeOf(other)", "rt.placeOf(actor)" }
		do
			t.truthy(string.find(game, needle, 1, true) ~= nil, `Boot/Game reads {needle}`)
		end
		local runtime = fs.readFile("src/server/Actors/ActorsRuntime.luau")
		t.truthy(string.find(runtime, "local feet = ActorsRuntime.feedHeld(", 1, true) ~= nil, "the world record")
		t.truthy(string.find(runtime, "heldPose = heldPose", 1, true) ~= nil, "Possession's release")
	end)

	-- slab ------------------------------------------------------------------------------------------------------------
	t.test("slab: greedy falls through the hospital's roof, straight and slanting, 2 to 30 packets a second", function()
		if not fs.isFile("build/Town.rbxm") then
			t.truthy(false, "build/Town.rbxm (lune run tools/bake/main.luau)")
			return
		end
		Height.configure(Data.default():module("TerrainExtensions"))
		local town = BakedWorld.load("build/Town.rbxm")
		local w = town:motorWorld(Data.default())
		local wall, down, cover = BakedWorld.validatorRays(town)
		local vworld = ValidatorWorld.build(w, { wall = wall, down = down, cover = cover })
		local P = SquirrelMotor.params
		local roof: any = nil
		for _, p in town.parts do
			if p.path == "Lots.hospital_main.Roof" then
				roof = p
			end
		end
		t.truthy(roof ~= nil, "the hospital's roof")
		if roof == nil then
			Height.configure(nil)
			return
		end
		local cx, cz = (roof.x0 + roof.x1) / 2, (roof.z0 + roof.z1) / 2
		local top = town.groundAt(cx, cz, roof.y1 + 1)
		local under = town.groundAt(cx, cz, roof.y0 - 1.6)
		local evaded, cases = {}, 0
		for _, rate in { 2, 4, 10, 20, 30 } do
			for _, slant in { 0, 5, 10, 20 } do -- (st/s across while it sinks)
				cases += 1
				local v = MoveValidator.new(vworld)
				local s0 = SquirrelMotor.new(cx, top, cz)
				s0.grounded, s0.clock = true, 1
				v:accept("a", { seq = 0, snapshot = SquirrelMotor.serialize(s0) }, 1)
				local seq, now, n = 0, 1, 0
				local function send(st: State)
					seq += 1
					now += 1 / rate
					st.clock = now
					n += #v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(st) }, now).violations
				end
				for _ = 1, rate do
					local st = SquirrelMotor.new(cx, top, cz)
					st.grounded = true
					send(st)
				end
				local t0 = now
				local landedAt: number? = nil
				while true do
					local tt = now + 1 / rate - t0
					local y = top - 0.5 * P.gravity * tt * tt
					local x = cx + slant * tt
					local st = SquirrelMotor.new(x, math.max(y, under), cz)
					st.vx = slant
					if y <= under then
						st.grounded = true
						st.vx = 0
						send(st)
						landedAt = x
						break
					end
					st.grounded, st.vy = false, -P.gravity * tt
					send(st)
				end
				if n == 0 then
					table.insert(
						evaded,
						string.format(
							"%d/s at %d st/s across (landed %.1f st across)",
							rate,
							slant,
							(landedAt :: number) - cx
						)
					)
				end
			end
		end
		Height.configure(nil)
		print(
			`      {cases - #evaded} of {cases} greedy falls judged; not judged: {if #evaded == 0
				then "none"
				else table.concat(evaded, "; ")}`
		)
		t.eq(#evaded, 0, "every greedy fall through the roof judged")
	end)

	t.test("slab: a rise into a low slab is judged only where the motor would not have stood on it", function()
		-- the client's motor stands a body on any top within 1.5 st over its feet, rising or falling (its ground ray
		-- from 1.5 over them): an honest rise under a slab ends on it. A packet whose feet are in that band under a top
		-- is inside it (judged); a rise from under it to on it is the motor's own pop-up (not judged)
		local slab = { minX = -5, maxX = 5, minZ = -5, maxZ = 5, bottom = 5.5, top = 6 }
		local world, vworld = worldWith({ slab })
		local g = world.groundHeight
		local rows = {}
		local inBand, onTop = 0, 0
		for _, rate in { 20, 4 } do
			local v = MoveValidator.new(vworld)
			local s0 = SquirrelMotor.new(0, g, 0)
			s0.grounded, s0.clock = true, 1
			v:accept("a", { seq = 0, snapshot = SquirrelMotor.serialize(s0) }, 1)
			local seq, now = 0, 1
			local P = SquirrelMotor.params
			local band, landed = 0, 0
			local t0 = now
			while true do
				local tt = now + 1 / rate - t0
				local y = g + P.leapUp * tt - 0.5 * P.gravity * tt * tt
				local st = SquirrelMotor.new(0, y, 0)
				seq += 1
				now += 1 / rate
				local stop = y >= slab.top or tt > 1
				if y >= slab.top then
					st.y, st.grounded = slab.top, true
				else
					st.grounded, st.vy = false, P.leapUp - P.gravity * tt
				end
				st.clock = now
				local r = v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(st) }, now)
				for _, x in r.violations do
					if x.code == "slab" then
						if st.grounded then
							landed += 1
						else
							band += 1
						end
					end
				end
				if stop then
					break
				end
			end
			inBand += band
			onTop += landed
			table.insert(rows, `{rate}/s: in the band {band} slab flags, standing on it {landed}`)
		end
		print(`      {table.concat(rows, "; ")}`)
		t.truthy(inBand > 0, "a packet inside the band under the slab is judged")
		t.eq(onTop, 0, "standing on the slab after the rise is not")
	end)

	t.test("glue: a grounded claim sinks no faster than a kerb and the slope over the distance moved", function()
		-- round 7: downCap less frames x max(glueMin, glueSlope x groundCap x substep): 0.75 st a frame, 22.5 st beyond
		-- gravity's 9.4 in a 0.5 s gap. A greedy client standing still, every packet grounded, each the deepest it may
		local world, vworld = worldWith(nil)
		local g = world.groundHeight
		local P = SquirrelMotor.params
		local rows = {}
		local worst = 0
		for _, rate in { 2, 4, 20 } do
			local dt = 1 / rate
			-- (the deepest a packet may claim, found by bisection on a fresh validator each time)
			local lo, hi = 0, 60
			for _ = 1, 30 do
				local mid = (lo + hi) / 2
				local v = MoveValidator.new(vworld)
				local s0 = SquirrelMotor.new(0, g + 100, 0)
				s0.grounded, s0.clock = true, 1
				v:accept("a", { seq = 0, snapshot = SquirrelMotor.serialize(s0) }, 1)
				local st = SquirrelMotor.new(0, g + 100 - mid, 0)
				st.grounded, st.clock = false, 1 + dt
				st.vy = -P.gravity * dt
				local r = v:accept("a", { seq = 1, snapshot = SquirrelMotor.serialize(st) }, 1 + dt)
				local teleport = false
				for _, x in r.violations do
					teleport = teleport or x.code == "teleport"
				end
				if teleport then
					hi = mid
				else
					lo = mid
				end
			end
			-- (the envelope's own fall: the claimed vy over the gap and gravity's g dt^2, and posSlack)
			local gravity = 2 * P.gravity * dt * dt + SquirrelMotor.envelopeParams.posSlack
			worst = math.max(worst, lo - gravity)
			table.insert(
				rows,
				string.format(
					"%d/s: %.2f st in one gap, %.2f beyond the fall (round 7: %.2f)",
					rate,
					lo,
					lo - gravity,
					math.ceil(dt / P.substep - 1e-6) * P.glueMin
				)
			)
		end
		print(`      the deepest a grounded body may sink standing still: {table.concat(rows, "; ")}`)
		t.truthy(worst <= P.glueMin + 0.01, `beyond the fall {worst} st`)
	end)

	-- LOWs ------------------------------------------------------------------------------------------------------------
	t.test("lastGrab survives a reset; the next driver inherits the meter, gaps and wall gaps", function()
		local _, vworld = worldWith(nil)
		local v = MoveValidator.new(vworld)
		local s0 = SquirrelMotor.new(0, 0, 0)
		s0.grounded, s0.clock = true, 1
		v:accept("a", { seq = 0, snapshot = SquirrelMotor.serialize(s0) }, 1)
		local marks = (v :: any)._marks["a"]
		marks.lastGrab = 0.97
		marks.stamina = -0.3
		marks.staminaAt = 1
		table.insert(marks.wallGaps, 1)
		table.insert(marks.gaps, 1)
		v:reset("a", nil)
		t.eq((v :: any)._marks["a"].lastGrab, 0.97, "lastGrab kept across a reset")
		v:forget("a")
		v:takeOver("a", 5, 0, 5, 2)
		local m2 = (v :: any)._marks["a"]
		t.eq(m2.stamina, -0.3, "the meter as the last driver left it")
		t.eq(m2.staminaAt, 1, "refilled from then by the server's time")
		t.eq(#m2.wallGaps, 1, "its wall gaps")
		t.eq(#m2.gaps, 1, "its gaps")
		t.truthy(m2.gov ~= nil, "its governor history")
	end)

	t.test("Reset with no safe sample, the held place on a wire: the first floor under it", function()
		local world, vworld = worldWith(nil)
		local g = world.groundHeight
		local movement = MovementService.new({
			validator = MoveValidator.new(vworld),
			enforce = true,
			poseOf = function(_a: any): (number?, number?, number?)
				return 3, g + 20, 4 -- (taken off a wire 20 st up)
			end,
		})
		movement:onHandoff({ id = "a", species = "squirrel" }, nil, "possess")
		local x, y, z = movement:safeTarget("a")
		print(string.format("      held at 3, %.1f, 4: Reset to %.2f, %.2f, %.2f", g + 20, x or -1, y or -1, z or -1))
		t.truthy(x == 3 and z == 4, "the same column")
		t.truthy(y ~= nil and math.abs((y :: number) - g) <= 0.06, `on the ground ({y})`)
	end)

	t.test("slab, honest: Q off every third branch and wire of the baked town, then a walk on: no slab flag", function()
		-- (the round-7 review's sweep: the real motor, Q at t 0.35 and 0.7 along the route, judged at 20 packets a second;
		-- here 3 s each, the last 1.5 s walking on: off the bough, off roofs' and walls' edges, down the banks)
		if not fs.isFile("build/Town.rbxm") then
			t.truthy(false, "build/Town.rbxm (lune run tools/bake/main.luau)")
			return
		end
		Height.configure(Data.default():module("TerrainExtensions"))
		local town = BakedWorld.load("build/Town.rbxm")
		local w = town:motorWorld(Data.default())
		local wall, down, cover = BakedWorld.validatorRays(town)
		local vworld = ValidatorWorld.build(w, { wall = wall, down = down, cover = cover })
		local routes = {}
		for _, r in w.registry:all() do
			if r.kind ~= "trunk" and not r.enclosure then
				table.insert(routes, r)
			end
		end
		table.sort(routes, function(a: any, b: any): boolean
			return a.id < b.id
		end)
		local drops, flagged, packets, rays = 0, 0, 0, 0
		local slab0 = vworld.slab
		vworld.slab = function(...: any): boolean
			rays += 1
			return slab0(...)
		end
		local examples = {}
		for i = 1, #routes, 3 do
			local r = routes[i]
			for _, at in { 0.35, 0.7 } do
				drops += 1
				local q = w.registry:pointAt(r, at)
				local s = SquirrelMotor.new(q.x, q.y, q.z)
				s.grounded = false
				s.routeId, s.railT, s.railDir = r.id, at, 1
				s.clock = 1
				local v = MoveValidator.new(vworld)
				v:accept("a", { seq = 0, snapshot = SquirrelMotor.serialize(s) }, 1)
				local seq, frame, bad = 0, 0, false
				local yaw = (r.id * 0.618) % 1 * 2 * math.pi
				while frame < 180 do
					frame += 1
					local now = frame / 60
					local _ = SquirrelMotor.step(
						s,
						BakedWorld.keys(yaw, { drop = now < 0.1, fw = if now > 1.5 then 1 else 0 }),
						1 / 60,
						w
					)
					s.clock = 1 + now
					if frame % 3 == 0 then
						seq += 1
						packets += 1
						local res = v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(s) }, 1 + now)
						for _, x in res.violations do
							if x.code == "slab" and not bad then
								bad = true
								if #examples < 5 then
									table.insert(examples, `route {r.id} at {at}: {x.detail}`)
								end
							end
						end
					end
				end
				if bad then
					flagged += 1
				end
			end
		end
		vworld.slab = slab0
		Height.configure(nil)
		print(`      {drops} drops ({packets} packets, {rays} slab rays): {flagged} with a slab flag`)
		for _, e in examples do
			print(`      {e}`)
		end
		t.eq(flagged, 0, "honest drops flagged for a slab")
	end)
end
