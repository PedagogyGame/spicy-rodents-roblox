--!strict
-- The bite-to-hospital sequence in the bowling alley (Server/Infection/InfectionService with the alley's employees,
-- Shared/Attractions/AlleyStaff and AlleyWalk), walked through the baked building (tests/lib/BakedWorld):
--   * the alley is a building to the town's colliders (its hall and its games-room wing);
--   * a bitten employee runs along the alley's own ways, from the rodent on each of four sides, then goes back to
--     work: through no wall, counter, machine or table, never into a lane's ball path, never out of the building;
--   * the walk in to the hospital from anywhere on an employee's loop leaves by the main doors and the alley's
--     routes, through nothing inside (the way back in, for the crew or a cured employee, is the same AlleyWalk
--     from outside: tests/unit/alley_walk.spec.luau).
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local AlleyStaff = require("@shared/Attractions/AlleyStaff")
local Colliders = require("@shared/World/Colliders")
local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local InfectionRules = require("@shared/Infection/InfectionRules")
local Rng = require("@shared/Util/Rng")
local TownAI = require("@server/AI/TownAI")
local TrafficService = require("@server/Traffic/TrafficService")
local InfectionService = require("@server/Infection/InfectionService")
local BakedWorld = require("../lib/BakedWorld")

local L = AlleyLayout
local BODY_HALF = 0.9
local KNEE = 0.6
local HEAD = 5.2

local function inBallPath(X: number, D: number): boolean
	return X > L.LANE_BLOCK_X0 and X < L.LANE_BLOCK_X1 and D >= L.FOUL_D and D <= L.PIT_END
end

return function(t)
	local data = Data.default()
	local place = AlleyStaff.placeOf(data) :: AlleyLayout.Place
	local baked = BakedWorld.bakeAlley()
	local function solidAt(x: number, z: number): any?
		local X, _, D = L.toLocal(place, x, 0, z)
		local floor = L.floorAt(X, D) or 0
		local wx, wy, wz = L.toWorld(place, X, floor + KNEE + (HEAD - KNEE) / 2, D)
		return baked.overlapBox(
			wx,
			wy,
			wz,
			{ { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } },
			{ BODY_HALF, (HEAD - KNEE) / 2, BODY_HALF },
			function(p: any): boolean
				return p.collide == true
			end
		)[1]
	end

	local function harness(): any
		local world = TownAI.build({ data = data, seed = 1, squirrels = 3, deer = 0, fox = 0 })
		local traffic =
			TrafficService.new({ lanes = data:lanes(), roads = data:roads(), heightAt = Height.at, seed = 7 })
		local rng = Rng.new(71)
		local params = InfectionRules.defaults()
		params.immediateChance = 0
		local svc = InfectionService.new({
			world = world,
			traffic = traffic,
			data = data,
			params = params,
			rand = function(): number
				return rng.next()
			end,
			controllerOf = function(): string
				return "ai"
			end,
			driverOf = function(): any?
				return nil
			end,
			setAttr = function() end,
			setPossessable = function() end,
			busy = function(): boolean
				return false
			end,
			notify = function() end,
			serverTime = function(): number
				return 5000
			end,
		})
		local rodent = 0
		local staff = {}
		for _, a in world.actors do
			if a.variant == "spicy" then
				rodent = a.id
			end
			if a.job then
				table.insert(staff, a)
			end
		end
		return { world = world, svc = svc, rodent = rodent, staff = staff }
	end

	t.test("the alley is a building to the town's colliders: its hall and its wing", function()
		local c = Colliders.fromData(data)
		local function at(X: number, D: number): Colliders.Box?
			local x, _, z = L.toWorld(place, X, 0, D)
			return Colliders.pointIn(c, x, z, place.floorY + 2)
		end
		for _, p in { { 22, -60 }, { 40, 30 }, { 0, 75 }, { 125, -20 }, { 140, 25 } } do
			local b = at(p[1], p[2])
			t.truthy(b ~= nil and b.id == "bowling_alley", `({p[1]}, {p[2]}) is inside the alley`)
		end
		for _, p in { { 22, -80 }, { 125, 60 }, { -40, 0 }, { 40, 95 } } do
			local b = at(p[1], p[2])
			t.truthy(b == nil or b.id ~= "bowling_alley", `({p[1]}, {p[2]}) is outside the alley`)
		end
	end)

	t.test(
		"a bitten employee runs along the alley's ways, then back to work: through nothing, off the lanes",
		function()
			local h = harness()
			for _ = 1, 100 do
				TownAI.stepFrame(h.world, 0.2)
				h.svc:step(0.2)
			end
			t.eq(#h.staff, #AlleyStaff.EMPLOYEES)
			for side = 0, 3 do
				for n, a in h.staff do
					local r = h.world.actorsById[h.rodent]
					local ang = side * math.pi / 2 + n
					h.world.possessed[h.rodent] = true
					r.x, r.z = a.x + math.cos(ang) * 2, a.z + math.sin(ang) * 2
					h.world.grid:set(h.rodent, r.x, r.z)
					h.svc.records[a.id] = nil
					t.truthy(h.svc:bite(a.id, h.rodent), `{a.job} bitten`)
					local d = h.world.brains[a.id].directive
					t.eq(d.mode, "route", `{a.job} runs`)
					h.world.possessed[h.rodent] = nil
					r.x, r.z = r.x + 400, r.z + 400 -- out of the way
					h.world.grid:set(h.rodent, r.x, r.z)
					local hits, lanes, outside, worked = 0, 0, 0, false
					for _ = 1, 150 do -- 30 s: the run, then back to work
						TownAI.stepFrame(h.world, 0.2)
						h.svc:step(0.2)
						local X, _, D = L.toLocal(place, a.x, 0, a.z)
						if inBallPath(X, D) then
							lanes += 1
						end
						if not AlleyStaff.inside(place, a.x, a.z) then
							outside += 1
						end
						local hit = solidAt(a.x, a.z)
						if hit then
							hits += 1
							if hits <= 1 then
								t.truthy(false, `{a.job} (side {side}) walks into {hit.path} at ({X}, {D})`)
							end
						end
						worked = worked or a.task ~= nil
					end
					t.eq(lanes, 0, `{a.job} (side {side}): steps in a lane's ball path`)
					t.eq(outside, 0, `{a.job} (side {side}): steps outside the walls`)
					t.truthy(worked, `{a.job} (side {side}) back at work`)
					h.svc.records[a.id] = nil
				end
			end
		end
	)

	t.test("the walk in to the hospital leaves by the main doors, through nothing inside", function()
		local h = harness()
		local door = L.opening("entrance")
		local walks, checked = 0, 0
		local function check(job: string, x0: number, z0: number, route: { { number } }, outward: boolean)
			-- every step inside the walls is clear; the step across the front wall is in the doorway
			local px, pz = x0, z0
			local wasIn = AlleyStaff.inside(place, x0, z0)
			for _, p in route do
				local len = math.sqrt((p[1] - px) ^ 2 + (p[2] - pz) ^ 2)
				local k = math.max(1, math.ceil(len / 0.5))
				for j = 1, k do
					local sx, sz = px + (p[1] - px) * j / k, pz + (p[2] - pz) * j / k
					local X, _, D = L.toLocal(place, sx, 0, sz)
					local isIn = AlleyStaff.inside(place, sx, sz)
					if isIn ~= wasIn then
						t.truthy(
							X > door.a and X < door.b and math.abs(D - L.FRONT_D) < 1,
							`{job}: {if outward then "out" else "in"} at ({X}, {D}), not by the main doors`
						)
						wasIn = isIn
					end
					t.truthy(not inBallPath(X, D), `{job}: on a lane at ({X}, {D})`)
					if isIn then
						checked += 1
						local hit = solidAt(sx, sz)
						t.truthy(hit == nil, `{job}: walks into {if hit then hit.path else ""} at ({X}, {D})`)
					end
				end
				px, pz = p[1], p[2]
			end
		end
		for f = 1, 300 do
			TownAI.stepFrame(h.world, 0.2)
			if f % 30 == 0 then
				for _, a in h.staff do
					local route = h.svc:walkRoute(a.x, a.z)
					if route then
						walks += 1
						check(a.job, a.x, a.z, route, true)
					end
				end
			end
		end
		t.truthy(walks > 0, "some employee has a walk in (the test has no teeth)")
		t.truthy(checked > 100, `{checked} steps inside checked`)
	end)
end
