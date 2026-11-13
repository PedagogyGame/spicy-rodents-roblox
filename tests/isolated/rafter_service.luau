--!strict
-- tests/isolated/rafter_service.luau: cases for tests/unit/rafter_service.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Server/Attractions/RafterService on that fake engine (BRIEF_ADDENDUM D9, lane L5): a player's squirrel walking
-- chord 9120 under two people and two players in the hall is spotted, gets at most two "rafters" lines, a callout
-- naming the lane on both players' screens (and the guard's on the platform), the glow for 6 s and the meter on its
-- own player; creeping is not spotted and the meter goes when it drops onto a lane; a blocked line of sight sees
-- nothing; the vent hides it; the computer bowlers watch an otherwise empty hall; the Spicy Rodent gets the
-- "spotting" lines, its own callout and the alarm (people run, the nearest officer heads for the front door) with
-- the Town built from the game's own parts; a guard's kick at the louvre lands and through the unit's walls does
-- not, until the service stops; stop() takes everything away.
-- Interface: return function(t) (the spec shape)
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local AlleyRoof = require("@shared/Attractions/AlleyRoof")
local Curve = require("@shared/Routes/Curve")
local Lines = require("@shared/Speech/Lines")
local PlayRules = require("@shared/Combat/PlayRules")
local Cover = require("@shared/Combat/Cover")
local RafterService = require("@server/Attractions/RafterService")
local FakeEngine = require("@tests/lib/FakeEngine")
local roblox = require("@lune/roblox")

local V3 = roblox.Vector3
local CF = roblox.CFrame
local PLACE = RafterService.DEFAULT_PLACE
local HIP = 0.6
local DT = 1 / 30

local function world(X: number, Y: number, D: number): any
	local x, y, z = AlleyLayout.toWorld(PLACE, X, Y, D)
	return V3.new(x, y, z)
end

-- A body: a Model whose PrimaryPart is its root, standing at the alley's local point (X, D) with its soles at Y,
-- facing the local direction (fX, fD).
local function body(name: string, X: number, Y: number, D: number, hip: number, fX: number?, fD: number?): any
	local at = world(X, Y + hip, D)
	local dx, dz = AlleyLayout.dirToWorld(PLACE, fX or 0, fD or 1)
	local cf = CF.lookAt(at, at + V3.new(dx, 0, dz))
	local m = FakeEngine.model(name, cf, nil)
	local root = FakeEngine.part("Root", cf, m)
	m.PrimaryPart = root
	m:SetAttribute("HipHeight", hip)
	return m
end

local function place(m: any, X: number, Y: number, D: number)
	local hip = m:GetAttribute("HipHeight")
	local rot = m.PrimaryPart.CFrame.Rotation
	m.PrimaryPart.CFrame = CF.new(world(X, Y + hip, D)) * rot
end

type Rig = {
	svc: any,
	clock: number,
	bodies: { any },
	sent: { [any]: { { [string]: any } } },
	seeing: boolean,
	step: (seconds: number, each: ((clock: number) -> ())?) -> (),
}

-- The service on a stub Town: `bodies` are Body records; what it sends lands in rig.sent[player].
local function rig(bodies: { any }, opts: { [string]: any }?): Rig
	local o = opts or {}
	local r: Rig = {
		svc = nil,
		clock = 1000,
		bodies = bodies,
		sent = {},
		seeing = true,
		step = nil :: any,
	}
	r.svc = RafterService.new({
		town = {
			bodies = function(): { any }
				return r.bodies
			end,
			bowlers = o.bowlers,
			send = function(player: any, payload: { [string]: any })
				r.sent[player] = r.sent[player] or {}
				table.insert(r.sent[player], table.clone(payload))
			end,
			alarm = o.alarm,
		},
		now = function(): number
			return r.clock
		end,
		canSee = function(_eye: any, _aim: any): boolean
			return r.seeing
		end,
		rand = function(): number
			return 0
		end,
	})
	function r.step(seconds: number, each: ((clock: number) -> ())?)
		local n = math.ceil(seconds / DT - 1e-9)
		for _ = 1, n do
			r.clock += DT
			if each then
				each(r.clock)
			end
			r.svc:step(DT)
		end
	end
	return r
end

local function said(models: { any }): { string }
	local out = {}
	for _, m in models do
		local line = m:GetAttribute("Say")
		if line then
			table.insert(out, line)
		end
	end
	return out
end

local function noticeOf(r: Rig, player: any): string?
	for _, p in r.sent[player] or {} do
		if p.kind == "notice" then
			return p.text
		end
	end
	return nil
end

local LANE_X = AlleyLayout.laneX(17)

-- the people in the hall: two townspeople on lane 17's and 18's approaches facing the pins, two players beside them
local function hall(): ({ any }, { any }, { any })
	local ai1 = body("ai1", LANE_X, 0, -6, 3)
	local ai2 = body("ai2", AlleyLayout.laneX(18), 0, -6, 3)
	local p1, p2 = FakeEngine.new("Player", "P1"), FakeEngine.new("Player", "P2")
	local h1 = body("h1", AlleyLayout.laneX(15), 0, -8, 3)
	local h2 = body("h2", AlleyLayout.laneX(13), 0, -8, 3)
	local records = {
		{ id = "ai1", kind = "human", model = ai1 },
		{ id = "ai2", kind = "human", model = ai2 },
		{ id = "h1", kind = "human", model = h1, player = p1 },
		{ id = "h2", kind = "human", model = h2, player = p2 },
	}
	return records, { ai1, ai2 }, { p1, p2 }
end

-- the squirrel's feet along chord 9120 (D 16.5) from the boot west, `speed` studs a second, to and fro over lanes
-- 13 to 18
local function walker(m: any, speed: number): (clock: number) -> ()
	local X0, X1 = AlleyLayout.laneX(13), AlleyRoof.BOOT.x0
	local X, dir = X1, -1
	return function(_clock: number)
		X += dir * speed * DT
		if X < X0 or X > X1 then
			X = math.clamp(X, X0, X1)
			dir = -dir
		end
		place(m, X, AlleyRoof.CHORD.y1, 16.5)
	end
end

return function(t)
	t.test(
		"a squirrel walking a chord is spotted: two lines at most, the lane on both players' screens, 6 s glow",
		function()
			FakeEngine.with(function()
				local records, people, players = hall()
				local owner = FakeEngine.new("Player", "Owner")
				local sq = body("sq", AlleyRoof.BOOT.x0, AlleyRoof.CHORD.y1, 16.5, HIP)
				table.insert(records, { id = "sq", kind = "squirrel", model = sq, player = owner })
				-- a guard on the platform by the louvre hears it too; a player out in the street does not
				local guardP, streetP = FakeEngine.new("Player", "Guard"), FakeEngine.new("Player", "Street")
				local guard = body("guard", AlleyRoof.GUARD.x, AlleyRoof.PLATFORM.y, AlleyRoof.GUARD.d, 3, -1, 0)
				local street = body("street", 40, 0, -120, 3)
				table.insert(records, { id = "guard", kind = "human", model = guard, player = guardP })
				table.insert(records, { id = "street", kind = "human", model = street, player = streetP })
				local r = rig(records)
				local spottedAt: number? = nil
				local walk = walker(sq, 18)
				r.step(6, function(clock: number)
					walk(clock)
					if spottedAt == nil and sq:FindFirstChild(RafterService.GLOW_NAME) then
						spottedAt = clock - 1000
					end
				end)
				t.truthy(spottedAt ~= nil and (spottedAt :: number) <= 4, `spotted after {spottedAt}`)
				t.eq(r.svc.stats.spotted, 1)
				local lines = said(people)
				t.truthy(#lines >= 1 and #lines <= 2, `{#lines} lines`)
				for _, line in lines do
					t.truthy(table.find(Lines.of("rafters"), line) ~= nil, line)
				end
				local text = noticeOf(r, players[1])
				t.truthy(
					text ~= nil and string.find(text :: string, "A squirrel in the rafters over lane", 1, true) ~= nil
				)
				t.eq(noticeOf(r, players[2]), text, "both players")
				t.eq(noticeOf(r, guardP), text, "the guard on the platform")
				t.eq(noticeOf(r, streetP), nil, "not someone in the street")
				t.eq(noticeOf(r, owner), nil, "the squirrel's own player reads its meter instead")
				-- the meter on the owner's screen: seen
				t.eq(owner:GetAttribute("RafterMeter"), 1)
				t.eq(owner:GetAttribute("RafterSeen"), true)
				t.truthy(type(sq:GetAttribute("RafterSeen")) == "number", "the glow's end on the body")
				-- it keeps still out of sight: 6 s after the spot the glow is gone, 8 s after it went out of sight it is
				-- lost and the meter falls
				r.seeing = false
				r.step(8.5)
				t.eq(sq:FindFirstChild(RafterService.GLOW_NAME), nil, "the glow is off after 6 s")
				t.eq(sq:GetAttribute("RafterSeen"), nil)
				t.eq(owner:GetAttribute("RafterSeen"), false)
				t.truthy((owner:GetAttribute("RafterMeter") :: number) <= 0.5, "lost: the meter drops")
				-- down onto a lane: the meter goes from the screen
				place(sq, LANE_X, 0, 16.5)
				r.step(0.5)
				t.eq(owner:GetAttribute("RafterMeter"), nil)
				t.eq(owner:GetAttribute("RafterSeen"), nil)
				r.svc:stop()
			end)
		end
	)

	t.test(
		"creeping along the chord in front of them is not spotted for 15 s; the meter shows on its screen",
		function()
			FakeEngine.with(function()
				local records = hall()
				local owner = FakeEngine.new("Player", "Owner")
				local sq = body("sq", AlleyRoof.BOOT.x0, AlleyRoof.CHORD.y1, 16.5, HIP)
				table.insert(records, { id = "sq", kind = "squirrel", model = sq, player = owner })
				local r = rig(records)
				local walk = walker(sq, 3)
				local most = 0
				r.step(15, function(clock: number)
					walk(clock)
					most = math.max(most, (owner:GetAttribute("RafterMeter") or 0) :: number)
				end)
				t.eq(r.svc.stats.spotted, 0)
				t.eq(sq:FindFirstChild(RafterService.GLOW_NAME), nil)
				t.truthy(most > 0 and most < 1, `the eye filled to {most}`)
				t.eq(owner:GetAttribute("RafterSeen"), false)
				r.svc:stop()
				t.eq(owner:GetAttribute("RafterMeter"), nil, "stop clears the screen")
			end)
		end
	)

	t.test(
		"nobody sees through what stands between; in the vent it is hidden; an AI squirrel shows no meter",
		function()
			FakeEngine.with(function()
				local records = hall()
				local owner = FakeEngine.new("Player", "Owner")
				local sq = body("sq", AlleyRoof.BOOT.x0, AlleyRoof.CHORD.y1, 16.5, HIP)
				local wild = body("wild", 40, AlleyRoof.CHORD.y1, 25.5, HIP)
				table.insert(records, { id = "sq", kind = "squirrel", model = sq, player = owner })
				table.insert(records, { id = "wild", kind = "squirrel", model = wild })
				local r = rig(records)
				r.seeing = false
				r.step(6, walker(sq, 18))
				t.eq(r.svc.stats.spotted, 0, "the line of sight is blocked")
				-- in the duct, running about: never spotted
				r.seeing = true
				local c = Curve.fromArrays(AlleyRoof.route(AlleyRoof.VENT).points)
				local u, dir = 0.3, 1
				r.step(6, function()
					u += dir * 0.02
					if u > 0.8 or u < 0.2 then
						dir = -dir
					end
					local p = c:getPointAt(u)
					place(sq, p.x, p.y, p.z)
				end)
				t.eq(r.svc.stats.spotted, 0, "hidden in the vent")
				t.truthy(owner:GetAttribute("RafterMeter") ~= nil, "the eye stays while it is in the vent")
				-- the AI squirrel on chord 9124 is watched (it never moves, so it is never spotted) and shows nothing
				t.eq(select(1, r.svc:meter("wild")), 0)
				r.svc:stop()
			end)
		end
	)

	t.test(
		"the computer bowlers watch: a game against the computer spots a walking squirrel in an empty hall",
		function()
			FakeEngine.with(function()
				local owner = FakeEngine.new("Player", "Owner")
				local sq = body("sq", AlleyRoof.BOOT.x0, AlleyRoof.CHORD.y1, 16.5, HIP)
				local records = { { id = "sq", kind = "squirrel", model = sq, player = owner } }
				local lanes = {}
				local r = rig(records, {
					bowlers = function(): { number }
						return lanes
					end,
				})
				local walk = walker(sq, 18)
				r.step(8, walk)
				t.eq(r.svc.stats.spotted, 0, "nobody in the hall")
				lanes = { 17, 18 }
				r.step(8, walk)
				t.eq(r.svc.stats.spotted, 1, "the computer bowlers on lanes 17 and 18")
				t.eq(r.svc.stats.lines, 0, "bodiless: no lines")
				r.svc:stop()
			end)
		end
	)

	t.test(
		"the Spicy Rodent through start(game): the spotting lines, its callout, people run, an officer comes",
		function()
			FakeEngine.with(function()
				local holder = FakeEngine.new("Player", "Holder")
				local bowlerP = FakeEngine.new("Player", "Bowler")
				local rodent = body("rodent", AlleyRoof.BOOT.x0, AlleyRoof.CHORD.y1, 16.5, HIP)
				local walkerPed = body("ped", LANE_X, 0, -6, 3)
				local other = body("ped2", AlleyLayout.laneX(18), 0, -6, 3)
				local bowler = body("bowler", AlleyLayout.laneX(3), 0, -6, 3)
				local cop = body("cop", 30, 0, -90, 3)
				local farCop = body("cop2", 400, 0, -400, 3)
				local events: { [number]: { { [string]: any } } } = {}
				local function brain(id: number, kind: string): any
					events[id] = {}
					return {
						kind = kind,
						onEvent = function(_self: any, e: { [string]: any })
							table.insert(events[id], e)
						end,
					}
				end
				local function actor(id: string, species: string, model: any, extra: { [string]: any }?)
					local a = { id = id, species = species, body = model }
					for k, v in extra or {} do
						(a :: any)[k] = v
					end
					return a
				end
				local byTownId = {
					[1] = actor("a-rodent", "squirrel", rodent, { variant = "spicy", driver = holder }),
					[2] = actor("a-ped", "human", walkerPed),
					[3] = actor("a-ped2", "human", other),
					[4] = actor("a-bowler", "human", bowler, { driver = bowlerP }),
					[5] = actor("a-cop", "human", cop),
					[6] = actor("a-cop2", "human", farCop),
					[7] = actor("a-deer", "deer", body("deer", 0, 0, -200, 1)),
				}
				local actors = {}
				for townId, a in byTownId do
					local p = a.body.PrimaryPart.Position
					table.insert(actors, { id = townId, x = p.X, z = p.Z, species = a.species })
				end
				local actorsById = {}
				for _, a in actors do
					actorsById[a.id] = a
				end
				local rt = {
					world = {
						actors = actors,
						actorsById = actorsById,
						brains = {
							[2] = brain(2, "Pedestrian"),
							[3] = brain(3, "Staff"),
							[5] = brain(5, "Officer"),
							[6] = brain(6, "Officer"),
						},
						now = 500,
					},
					byTownId = byTownId,
				}
				local possession = {
					controllerOf = function(_self: any, a: any): any
						return a.driver or "ai"
					end,
				}
				local sent: { [any]: { { [string]: any } } } = {}
				local clock = 2000
				local svc = RafterService.start({
					possession = possession,
					runtime = rt,
					fire = function(player: any, payload: { [string]: any })
						sent[player] = sent[player] or {}
						table.insert(sent[player], payload)
					end,
					attractions = {
						place = PLACE,
						minigames = {
							stations = function(_self: any): { [string]: any }
								return {
									["bowling:3"] = {
										game = "bowling",
										lane = 3,
										session = { phase = "playing", seats = { bowlerP, { ai = true } } },
									},
								}
							end,
						},
					},
					canSee = function(): boolean
						return true
					end,
					now = function(): number
						return clock
					end,
				})
				local walk = walker(rodent, 18)
				for _ = 1, math.ceil(6 / DT) do
					clock += DT
					walk(clock)
					svc:step(DT)
					if svc.stats.spotted > 0 then
						break
					end
				end
				t.eq(svc.stats.spotted, 1)
				t.eq(svc.stats.alarms, 1)
				-- the lines are the spotting ones (the owner's own line among them)
				local lines = said({ walkerPed, other })
				t.truthy(#lines >= 1, "a line")
				for _, line in lines do
					t.truthy(table.find(Lines.GROUPS.spotting, line) ~= nil, line)
				end
				t.eq(bowler:GetAttribute("Say"), nil, "a player's body says nothing")
				-- the bowling player is told, in the rodent's words
				local note = (sent[bowlerP] or {})[1]
				t.truthy(
					note
						and note.kind == "notice"
						and string.find(note.text, "The Spicy Rodent is in the rafters", 1, true)
				)
				-- people run (the Pedestrian brain's witness flee), the nearest officer heads for the front door
				local ped = events[2][1]
				t.truthy(ped and ped.type == "witness" and ped.threat == actorsById[1], "the pedestrian runs from it")
				t.eq(#events[3], 0, "a staff brain has no flee of its own")
				local respond = events[5][1]
				t.truthy(respond and respond.type == "respond", "the nearer officer responds")
				t.eq(#events[6], 0, "not the far one")
				local en = AlleyLayout.ENTRANCE
				local dx, _, dz = AlleyLayout.toWorld(PLACE, (en.x0 + en.x1) / 2, 0, AlleyLayout.FRONT_D - 6)
				t.near(respond.x, dx, 1e-6)
				t.near(respond.z, dz, 1e-6)
				t.eq(respond.untilTime, 560)
				-- the glow on the rodent, the meter on its holder
				t.truthy(rodent:FindFirstChild(RafterService.GLOW_NAME) ~= nil)
				t.eq(holder:GetAttribute("RafterSeen"), true)
				svc:stop()
				t.eq(rodent:FindFirstChild(RafterService.GLOW_NAME), nil, "stop takes the glow off")
				t.eq(holder:GetAttribute("RafterMeter"), nil)
			end)
		end
	)

	t.test(
		"a guard's kick reaches the squirrel at the louvre, not inside the unit; after stop() nothing is shielded",
		function()
			FakeEngine.with(function()
				Cover.clear()
				local r = rig({})
				local function at(X: number, Y: number, D: number, id: string): { [string]: any }
					local p = world(X, Y, D)
					return { id = id, x = p.X, y = p.Y, z = p.Z }
				end
				-- the guard's root on the platform by the louvre, facing it (local -X)
				local guard = at(AlleyRoof.GUARD.x, AlleyRoof.PLATFORM.y + 3, AlleyRoof.GUARD.d, "guard")
				local lx, lz = AlleyLayout.dirToWorld(PLACE, -1, 0)
				local look = { x = lx, z = lz }
				local inside = at(112, 14.30 + HIP, 16.5, "inside")
				local mouth = at(AlleyRoof.MOUTH.x, AlleyRoof.MOUTH.y + HIP, AlleyRoof.MOUTH.d, "mouth")
				t.eq(PlayRules.kickTarget(guard, look, { inside }), nil, "inside the unit at X 112: missed")
				t.eq(PlayRules.kickTarget(guard, look, { inside, mouth }), "mouth", "at the louvre: hit")
				-- just inside the bent slat (X 115.2, still in the kick's reach) is inside too
				t.eq(PlayRules.kickTarget(guard, look, { at(115.2, 13.62 + HIP, 16.5, "slat") }), nil, "past the slat")
				-- nor does the Spicy Rodent bite out through the housing
				t.eq(#PlayRules.biteVictims(inside, { guard }, 0, {}), 0)
				r.svc:stop()
				t.eq(#Cover.list(), 0)
				t.eq(PlayRules.kickTarget(guard, look, { inside }), "inside", "without the service the old reach")
			end)
		end
	)

	t.test("a leap from chord to chord keeps the eye's fill, and the landing in view is seen at once", function()
		FakeEngine.with(function()
			local records = hall()
			local owner = FakeEngine.new("Player", "Owner")
			-- (the landing is on chord 9123, D 7.5, straight over the cans of lanes 17-18: lit)
			local lit = AlleyLayout.pairX(9)
			local sq = body("sq", lit + 6, AlleyRoof.CHORD.y1, 16.5, HIP)
			table.insert(records, { id = "sq", kind = "squirrel", model = sq, player = owner })
			local r = rig(records)
			-- creep a little along chord 9120: the eye fills a bit
			local X = lit + 6
			r.step(4, function()
				X -= 3 * DT
				place(sq, X, AlleyRoof.CHORD.y1, 16.5)
			end)
			local before = owner:GetAttribute("RafterMeter") :: number
			t.truthy(before > 0 and before < 0.5, `the eye has filled a little ({before})`)
			t.eq(r.svc.stats.spotted, 0)
			-- the leap: up and across to the chord at D 7.5 in 0.6 s, then land
			local t0, X0 = r.clock, X
			r.step(0.6, function(clock: number)
				local f = math.min(1, (clock - t0) / 0.6)
				place(sq, X0 + (lit - X0) * f, AlleyRoof.CHORD.y1 + 4 * math.sin(math.pi * f), 16.5 - 9 * f)
			end)
			t.truthy((owner:GetAttribute("RafterMeter") :: number) >= before, "the air keeps it")
			t.eq(r.svc.stats.spotted, 0, "not yet")
			place(sq, lit, AlleyRoof.CHORD.y1, 7.5)
			r.step(0.4)
			t.eq(r.svc.stats.spotted, 1, "landing on a lit beam in view")
			r.svc:stop()
		end)
	end)
end
