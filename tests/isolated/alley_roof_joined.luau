--!strict
-- tests/isolated/alley_roof_joined.luau: the case for tests/unit/alley_roof_joined.spec.luau, run in its own Lune
-- process (tests/lib/Isolated) because it installs fake engine globals (tests/lib/FakeEngine).
-- The alley roof run joined into the game, end to end (BRIEF_ADDENDUM D9, D10), on the alley baked in memory by its
-- own bake code (tests/lib/BakedWorld.bakeAlley: the house, the tree, the wing roof, the vent unit, the raised hall
-- roof and its trusses, the stair and the platform) and on the routes the game ships (Shared/Data):
--   * a squirrel, on the real SquirrelMotor at 60 Hz with scripted keys, climbs the house's downspout, runs the
--     gutter and the ridge, leaps onto the bough, crosses it, drops onto the wing roof, goes in at the louvre, along
--     the duct and out of the boot onto the truss chord 9120;
--   * there, under the Server/Attractions/RafterService the game starts (Boot/Game's own arguments: possession,
--     runtime, fire, attractions with a bowling game against the computer), walking along the chord it is spotted by
--     the computer bowler, glows, its player's meter reads "Spotted!" (Client/UI/SneakMeter.look) and the guard on
--     the platform is told the lane; creeping (Ctrl) along the same chord from the same place it is not; tapping W
--     to get on at more than twice a creep's speed is walking, and it is seen;
--   * a person walks from the foot of the stair in the yard up the three flights to the guard's spot on the platform
--     (tests/lib/HumanWalk) and, from there, kicks the squirrel standing at the louvre (where the motor put it), but
--     not the one inside the unit (where the motor took it), until the service stops;
--   * Boot/Game and Client/Main start, step and stop these (read from their source: neither runs here).
-- Interface: return function(t) (the spec shape)
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local AlleyRoof = require("@shared/Attractions/AlleyRoof")
local Curve = require("@shared/Routes/Curve")
local Data = require("@shared/Data")
local PlayRules = require("@shared/Combat/PlayRules")
local Cover = require("@shared/Combat/Cover")
local CollisionGroups = require("@shared/World/CollisionGroups")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local RafterService = require("@server/Attractions/RafterService")
local SneakMeter = require("@client/UI/SneakMeter")
local BakedWorld = require("@tests/lib/BakedWorld")
local FakeEngine = require("@tests/lib/FakeEngine")
local HumanWalk = require("@tests/lib/HumanWalk")

local R = AlleyRoof
local V3 = roblox.Vector3
local CF = roblox.CFrame
local DT = 1 / 60
local HIP = 0.6 -- the squirrel's root over its feet (its body's HipHeight attribute)
local ROOT = 3 -- a person's root over their soles
local BOWLER_LANE = 17
local TURN = 6 -- studs either side of the bowler's lane the squirrel turns back at
local TAP = { 12, 5 } -- tapping W five times a second: held 5 frames of every 12 (7.5 st/s on the rail)

type State = SquirrelMotor.State

local function copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = copy(x)
	end
	return out
end

return function(t)
	local baked, place = BakedWorld.bakeAlley()
	local motorWorld = baked:motorWorld(Data.default())
	local registry = motorWorld.registry
	local function pt(id: number, tt: number): Curve.Vec3
		return registry:pointAt(registry:get(id) :: any, tt)
	end
	local function toLocal(x: number, y: number, z: number): (number, number, number)
		return AlleyLayout.toLocal(place, x, y, z)
	end
	local function yawToward(s: State, p: Curve.Vec3): number
		-- the camera behind the squirrel looking at p (forward = (-sin yaw, -cos yaw))
		return math.atan2(-(p.x - s.x), -(p.z - s.z))
	end
	local mx, my, mz = AlleyLayout.toWorld(place, R.MOUTH.x, R.MOUTH.y, R.MOUTH.d)
	local mouth = Curve.vec3(mx, my, mz)

	-- The way in with W held (no sprint), as a player keys it: run at the downspout, up it, along the gutter and
	-- the ridge looking west, Space at the ridge's end, W through the air onto the bough, along it, Q at its end
	-- onto the wing roof, to the louvre and in, along the duct and out onto the chord. Returns the phase it got to,
	-- the routes ridden, and the states it passed at the louvre, inside the unit and on the chord.
	local function wayIn(): (string, { number }, { [string]: State })
		local foot = pt(9101, 0)
		local sx, sz = foot.x, foot.z + 7
		local s = SquirrelMotor.new(sx, motorWorld.groundAt(sx, sz, 1e4), sz)
		s.yaw = 0
		local phase, visits, kept, onBough = "pipe", {}, {}, 0
		for _ = 1, 60 * 60 do
			local input = SquirrelMotor.idleInput(0)
			local rid = s.routeId
			if phase == "pipe" then
				input.fw = 1
				input.cameraYaw = if rid == 9103 then math.pi / 2 else 0
				if rid == 9103 and s.railT >= 1 then
					phase = "leap"
				end
			elseif phase == "leap" then
				input.cameraYaw, input.leap, input.fw = math.pi / 2, true, 1
				phase = "air"
			elseif phase == "air" then
				input.cameraYaw, input.fw = math.pi / 2, 1
				if rid == R.BOUGH then
					phase = "bough"
				elseif s.grounded then
					return "missed the bough", visits, kept
				end
			elseif phase == "bough" then
				onBough += 1
				input.cameraYaw = yawToward(s, pt(R.BOUGH, if s.railT < R.BOUGH_FORK_T then R.BOUGH_FORK_T else 1))
				input.fw = if onBough <= 3 then 0 else 1
				if s.railT >= 1 then
					input.drop = true
					phase = "down"
				end
			elseif phase == "down" then
				input.cameraYaw = yawToward(s, mouth)
				if s.grounded then
					phase = "roof"
				end
			elseif phase == "roof" then
				input.cameraYaw = yawToward(s, mouth)
				input.fw = 1
				if rid == R.VENT or math.sqrt((s.x - mouth.x) ^ 2 + (s.z - mouth.z) ^ 2) < 1.2 then
					kept.louvre = copy(s)
					phase = "louvre"
				end
			elseif phase == "louvre" then
				input.cameraYaw = yawToward(s, pt(R.VENT, 0.15))
				input.fw = 1
				if rid == R.VENT then
					phase = "vent"
				end
			elseif phase == "vent" then
				input.cameraYaw = yawToward(s, pt(R.VENT, 1))
				input.fw = 1
				local X = toLocal(s.x, s.y, s.z)
				if rid == R.VENT and kept.inside == nil and X > 108 and X < 114 then
					kept.inside = copy(s)
				end
				if rid == R.FIRST_RAFTER then
					kept.rafter = copy(s)
					return "rafter", visits, kept
				end
			end
			SquirrelMotor.step(s, input, DT, motorWorld :: any)
			local here = s.routeId or 0
			if visits[#visits] ~= here then
				table.insert(visits, here)
			end
		end
		return phase, visits, kept
	end

	-- A body on the fake engine: a Model whose PrimaryPart is its root, `hip` over the feet at world (x, y, z).
	local function body(name: string, x: number, y: number, z: number, hip: number, face: Vector3?): any
		local at = V3.new(x, y + hip, z)
		local cf = if face then CF.lookAt(at, at + face) else CF.new(at)
		local m = FakeEngine.model(name, cf, nil)
		local root = FakeEngine.part("Root", cf, m)
		m.PrimaryPart = root
		m:SetAttribute("HipHeight", hip)
		return m
	end

	-- The line of sight on the baked alley, as the game's raycast sees it: a ray in the service's collision group
	-- (Shared/World/CollisionGroups.rayHits: Roblox's rule).
	local function canSee(eye: any, aim: any): boolean
		local d = aim - eye
		local hit = baked.raycast(eye.X, eye.Y, eye.Z, d.X, d.Y, d.Z, function(q: any): boolean
			return CollisionGroups.rayHits(RafterService.SIGHT_GROUP, q.collide, q.query, q.group)
		end)
		return hit == nil or (1 - hit) * d.Magnitude <= RafterService.C.beamSlack
	end

	-- The game round the service, shaped as Boot/Game hands it over (possession, runtime, fire, attractions): the
	-- held squirrel, the guard held by another player on the platform, a bowling game against the computer on
	-- BOWLER_LANE. Then `seconds` of the motor from `from` with W held along the chord (and Ctrl when `creep`), the
	-- body following it and the service stepped every frame.
	local function onTheChord(from: State, creep: boolean | string, seconds: number): { [string]: any }
		local out: { [string]: any } = {}
		FakeEngine.with(function()
			local squirrelP, guardP = FakeEngine.new("Player", "Squirrel"), FakeEngine.new("Player", "Guard")
			local s: State = copy(from)
			local sq = body("sq", s.x, s.y, s.z, HIP)
			local gx, gy, gz = AlleyLayout.toWorld(place, R.GUARD.x, R.PLATFORM.y, R.GUARD.d)
			local lx, lz = AlleyLayout.dirToWorld(place, -1, 0)
			local guard = body("guard", gx, gy, gz, ROOT, V3.new(lx, 0, lz))
			local byTownId = {
				[1] = { id = "a-squirrel", species = "squirrel", body = sq, driver = squirrelP },
				[2] = { id = "a-guard", species = "human", body = guard, driver = guardP },
			}
			local actors = {}
			for townId, a in byTownId do
				local p = a.body.PrimaryPart.Position
				table.insert(actors, { id = townId, x = p.X, z = p.Z, species = a.species })
			end
			local sent: { [any]: { { [string]: any } } } = {}
			local clock = 100
			local svc = RafterService.start({
				possession = {
					controllerOf = function(_self: any, a: any): any
						return a.driver or "ai"
					end,
				},
				runtime = { world = { actors = actors, actorsById = {}, brains = {}, now = 0 }, byTownId = byTownId },
				fire = function(player: any, payload: { [string]: any })
					sent[player] = sent[player] or {}
					table.insert(sent[player], payload)
				end,
				attractions = {
					place = place,
					minigames = {
						stations = function(_self: any): { [string]: any }
							return {
								[`bowling:{BOWLER_LANE}`] = {
									game = "bowling",
									lane = BOWLER_LANE,
									session = { phase = "playing", seats = { { ai = true } } },
								},
							}
						end,
					},
				},
				canSee = canSee,
				now = function(): number
					return clock
				end,
			})
			-- to and fro over the bowler's lane: west to TURN studs past it, then back east (not into the boot)
			local laneX = AlleyLayout.laneX(BOWLER_LANE)
			local west, pause, travelled = true, 0, 0
			local frames = math.ceil(seconds / DT)
			for frame = 1, frames do
				local X = toLocal(s.x, s.y, s.z)
				if (west and X < laneX - TURN) or (not west and X > laneX + TURN) then
					west, pause = not west, 6
				end
				local input = SquirrelMotor.idleInput(yawToward(s, pt(R.FIRST_RAFTER, if west then 1 else 0)))
				local key = if creep == "tap" then frame % TAP[1] < TAP[2] else true
				input.fw, input.focus = if pause > 0 or not key then 0 else 1, creep == true
				pause = math.max(0, pause - 1)
				local ox, oz = s.x, s.z
				SquirrelMotor.step(s, input, DT, motorWorld :: any)
				travelled += math.sqrt((s.x - ox) ^ 2 + (s.z - oz) ^ 2)
				sq.PrimaryPart.CFrame = CF.new(s.x, s.y + HIP, s.z)
				clock += DT
				svc:step(DT)
				if out.spottedAt == nil and svc.stats.spotted > 0 then
					out.spottedAt = frame * DT
					out.glow = sq:FindFirstChild(RafterService.GLOW_NAME) ~= nil
					local m, seen = squirrelP:GetAttribute("RafterMeter"), squirrelP:GetAttribute("RafterSeen")
					out.look = SneakMeter.look(m, seen == true, false)
				end
				if s.routeId ~= R.FIRST_RAFTER then
					out.left = frame
					break
				end
			end
			out.travelled = travelled
			out.route = s.routeId
			out.spotted = svc.stats.spotted
			out.meter = squirrelP:GetAttribute("RafterMeter")
			out.toGuard = sent[guardP] and sent[guardP][1]
			svc:stop()
		end)
		return out
	end

	t.test(
		"the roof run in the game: up the house, over the bough, in at the louvre, spotted walking, not creeping; the guard's kick",
		function()
			-- the squirrel's way in, on the routes the game ships and the baked alley
			local phase, visits, kept = wayIn()
			local seq = table.concat(visits, " ")
			t.eq(phase, "rafter", `got as far as {phase} (routes {seq})`)
			t.eq(
				seq,
				"0 9101 9102 9103 0 9105 0 9107 9120",
				"the downspout, gutter, ridge, leap, bough, roof, vent, chord"
			)
			local onChord = kept.rafter
			local cX, cY, cD = toLocal(onChord.x, onChord.y, onChord.z)
			t.near(cD, 16.5, 0.3, "on the truss at D 16.5")
			t.near(cY, R.CHORD.y1, 0.3, "on its plate")

			-- walking to and fro over lane 17, the computer bowler there sees it (one dash straight across the dark
			-- hall, 24 studs from that one bowler, fills the eye to about 0.7: it is dawdling in view that is seen)
			local walk = onTheChord(onChord, false, 8)
			t.eq(walk.spotted, 1, `walking: spotted once (meter {walk.meter})`)
			t.truthy(walk.spottedAt ~= nil and walk.spottedAt < 6, `walking: spotted after {walk.spottedAt} s`)
			t.truthy(walk.glow, "it glows")
			t.eq(walk.look and walk.look.state, "spotted", "its player's eye says so")
			t.eq(walk.look and walk.look.shout, SneakMeter.WORDS.spotted)
			local note = walk.toGuard
			t.truthy(note and note.kind == "notice", "the guard on the platform is told")
			t.truthy(
				note and string.find(note.text, "A squirrel in the rafters over lane", 1, true) ~= nil,
				note and note.text
			)
			-- creeping (Ctrl) along the same chord from the same place for as long, it is not
			local creep = onTheChord(onChord, true, 8)
			t.eq(creep.route, R.FIRST_RAFTER, "still on the chord")
			t.truthy(creep.travelled > 15, `creeping it got on ({creep.travelled} st)`)
			t.eq(creep.spotted, 0, `creeping: not spotted (meter {creep.meter})`)
			t.truthy(type(creep.meter) == "number" and creep.meter < 1, "watched, the eye not full")
			-- tapping W (no Ctrl) gets on at more than twice a creep: that is walking, and it is seen
			local tap = onTheChord(onChord, "tap", 8)
			t.truthy(tap.travelled > 1.8 * creep.travelled, `tapping got on {tap.travelled} st`)
			t.eq(tap.spotted, 1, `tapping W: spotted (meter {tap.meter})`)
			t.truthy(tap.spottedAt ~= nil and tap.spottedAt < 8, `tapping W: spotted after {tap.spottedAt} s`)
			print(
				`      {seq}: on chord 9120 at X {string.format("%.1f", cX)}; walking spotted by the lane {BOWLER_LANE} bowler after {string.format(
					"%.1f",
					walk.spottedAt
				)} s; creeping {string.format("%.1f", creep.travelled)} st in 8 s, meter {creep.meter}; tapping W {string.format(
					"%.1f",
					tap.travelled
				)} st, spotted after {tap.spottedAt} s`
			)

			-- a person climbs the stair from the yard to the guard's spot
			local ax, _, az = AlleyLayout.toWorld(place, 95, 0, 2)
			local bx, _, bz = AlleyLayout.toWorld(place, 156, 0, 40)
			local fx, _, fz = AlleyLayout.toWorld(place, R.STAIR.footX + 2.5, 0, (R.STAIR.d0 + R.STAIR.d1) / 2)
			local reach = HumanWalk.fill(baked, { fx, baked.groundAt(fx, fz, 1000), fz }, {
				x0 = math.min(ax, bx),
				x1 = math.max(ax, bx),
				z0 = math.min(az, bz),
				z1 = math.max(az, bz),
			})
			local gx, gy, gz = AlleyLayout.toWorld(place, R.GUARD.x, R.PLATFORM.y, R.GUARD.d)
			local at: number? = nil
			for _, h in reach.at(gx, gz) do
				if math.abs(h - gy) < 0.3 then
					at = h
				end
			end
			t.truthy(at ~= nil, "a person walks up the stair to the guard's spot")

			-- from there, facing the louvre, the kick
			FakeEngine.with(function()
				Cover.clear()
				local svc = RafterService.start({
					possession = {
						controllerOf = function(): any
							return "ai"
						end,
					},
					runtime = { world = { actors = {}, actorsById = {}, brains = {}, now = 0 }, byTownId = {} },
					fire = function() end,
					attractions = { place = place },
					canSee = canSee,
					now = function(): number
						return 0
					end,
				})
				local guard = { id = "guard", x = gx, y = (at :: number) + ROOT, z = gz }
				local lx, lz = AlleyLayout.dirToWorld(place, -1, 0)
				local look = { x = lx, z = lz }
				local function sq(id: string, s: State): { [string]: any }
					return { id = id, x = s.x, y = s.y + HIP, z = s.z }
				end
				local atLouvre, inside = sq("at the louvre", kept.louvre), sq("inside", kept.inside)
				t.eq(
					PlayRules.kickTarget(guard, look, { atLouvre }),
					"at the louvre",
					"the guard kicks it at the louvre"
				)
				t.eq(PlayRules.kickTarget(guard, look, { inside }), nil, "not inside the unit")
				svc:stop()
				t.eq(PlayRules.kickTarget(guard, look, { inside }), "inside", "(the unit's walls are what stop it)")
			end)

			-- the game starts, steps and stops it; the client starts the eye (neither runs here: read that they do)
			local game = fs.readFile("src/server/Boot/Game.luau")
			for _, line in
				{
					'local RafterService = require("../Attractions/RafterService")',
					"rafters = RafterService.start({ possession = possession, runtime = rt, fire = fire, attractions = attractions })",
					"pcall(rafters.step, rafters, dt)",
					"rafters:stop()",
				}
			do
				t.truthy(string.find(game, line, 1, true), `Boot/Game no longer has: {line}`)
			end
			local main = fs.readFile("src/client/Main.client.luau")
			t.truthy(string.find(main, "pcall(SneakMeter.start)", 1, true), "Client/Main starts the sneak meter")
		end
	)
end
