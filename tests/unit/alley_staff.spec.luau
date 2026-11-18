--!strict
-- The bowling alley's employees (Shared/Attractions/AlleyStaff; BRIEF_ADDENDUM D5): five people, each with their own
-- work on a loop, held to the alley's plan and to the building the bake makes:
--   * every stop and every step of every leg is on the alley's floor, in that employee's own rooms, and never in a
--     lane's ball path (from the foul line to the pit);
--   * a body walking each leg meets no colliding part of the baked building (the walls, the counters, the games'
--     tables, the shops' fittings): it never walks through a wall or a desk;
--   * on the real town (AI/TownAI) the five are the first attraction staff, each a Staff brain on their work loop:
--     over a few simulated minutes each one walks, stops and works (the body's task: the shoe clerk sprays, the
--     mechanic kneels at the pinsetters, the cleaner mops, the front desk cooks and greets, the attendant polishes
--     and racks), stays inside the building on its floor, and can be suspended and resumed (a player takes over);
--   * the client poses a kneel (AnimationDriver.taskPose: the sit clip, part way down) and a patient's pose wins.
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local AlleyStaff = require("@shared/Attractions/AlleyStaff")
local Data = require("@shared/Data")
local TownAI = require("@server/AI/TownAI")
local BakedWorld = require("../lib/BakedWorld")
local AnimationDriver = require("@client/Animation/AnimationDriver")

local L = AlleyLayout
local BODY_HALF = 0.9 -- studs: half a person's width
local KNEE = 0.6 -- studs: what a person steps over (a rail, a mat) without meeting it
local HEAD = 5.2

local function zoneOf(rooms: { string }, X: number, D: number, grow: number): string?
	for _, id in rooms do
		local z = L.zone(id)
		if X >= z.x0 - grow and X <= z.x1 + grow and D >= z.d0 - grow and D <= z.d1 + grow then
			return id
		end
	end
	return nil
end

local function inBallPath(X: number, D: number): boolean
	return X > L.LANE_BLOCK_X0 and X < L.LANE_BLOCK_X1 and D >= L.FOUL_D and D <= L.PIT_END
end

local function legs(e: AlleyStaff.Employee, fn: (X: number, D: number, leg: number) -> ())
	local n = #e.stops
	for i = 1, n do
		local a, b = e.stops[i], e.stops[i % n + 1]
		local len = math.sqrt((b.x - a.x) ^ 2 + (b.d - a.d) ^ 2)
		local k = math.max(1, math.ceil(len / 0.5))
		for j = 0, k do
			fn(a.x + (b.x - a.x) * j / k, a.d + (b.d - a.d) * j / k, i)
		end
	end
end

return function(t)
	t.test("five employees, each with their own work, every act a known one", function()
		t.eq(#AlleyStaff.EMPLOYEES, 5)
		local seen: { [string]: boolean } = {}
		for _, e in AlleyStaff.EMPLOYEES do
			t.truthy(not seen[e.id], e.id)
			seen[e.id] = true
			local acts: { [string]: boolean } = {}
			for _, s in e.stops do
				if s.hold > 0 then
					t.truthy(s.act ~= nil and AlleyStaff.ACTS[s.act :: string] ~= nil, `{e.id}: an unknown act`)
					t.truthy(s.face ~= nil, `{e.id}: a work stop faces its work`)
					acts[s.act :: string] = true
				else
					t.eq(s.act, nil)
				end
			end
			local n = 0
			for _ in acts do
				n += 1
			end
			t.truthy(n >= 2, `{e.id} does {n} kinds of work`)
		end
		for _, id in { "shoe_clerk", "mechanic", "cleaner", "front_desk", "games_attendant" } do
			t.truthy(seen[id], id)
		end
		-- what the brief asks of each
		local function does(id: string, act: string): boolean
			for _, s in AlleyStaff.employee(id).stops do
				if s.act == act then
					return true
				end
			end
			return false
		end
		t.truthy(does("shoe_clerk", "serve") and does("shoe_clerk", "spray"), "the clerk takes and sprays shoes")
		t.truthy(does("mechanic", "kneel"), "the mechanic kneels at the pinsetters")
		t.truthy(does("cleaner", "mop"), "the cleaner mops")
		t.truthy(does("front_desk", "cook") and does("front_desk", "greet"), "the snack bar and the front desk")
		t.truthy(does("games_attendant", "polish") and does("games_attendant", "rack"), "the games room")
	end)

	t.test("in their own rooms, on the floor, never in a lane's ball path", function()
		for _, e in AlleyStaff.EMPLOYEES do
			for _, s in e.stops do
				t.truthy(zoneOf(e.rooms, s.x, s.d, 0) ~= nil, `{e.id}: a stop at ({s.x}, {s.d}) is outside its rooms`)
			end
			local bad = 0
			legs(e, function(X: number, D: number, leg: number)
				local ok = zoneOf(e.rooms, X, D, L.PARTITION_T) ~= nil
					and L.floorAt(X, D) ~= nil
					and not inBallPath(X, D)
				if not ok then
					bad += 1
					if bad <= 3 then
						t.truthy(false, `{e.id}: leg {leg} at ({X}, {D}) leaves its rooms or enters a lane`)
					end
				end
			end)
		end
		-- the mechanic kneels behind the machines (the back corridor), the cleaner's line is behind every run-up
		for _, s in AlleyStaff.employee("mechanic").stops do
			t.truthy(s.d > L.MACHINE_D1, "the mechanic stays behind the machines")
		end
		t.truthy(AlleyStaff.APPROACH_MOP < L.FOUL_D - 12, "the mop's line is at the back of the approaches")
	end)

	t.test("no leg walks through a wall, a counter, a table or a shop's fittings", function()
		local world, place = BakedWorld.bakeAlley()
		local function solid(p: any): boolean
			return p.collide == true
		end
		for _, e in AlleyStaff.EMPLOYEES do
			local bad = 0
			legs(e, function(X: number, D: number, leg: number)
				local floor = L.floorAt(X, D) or 0
				local x, y, z = L.toWorld(place, X, floor + KNEE + (HEAD - KNEE) / 2, D)
				local hits = world.overlapBox(
					x,
					y,
					z,
					{ { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } },
					{ BODY_HALF, (HEAD - KNEE) / 2, BODY_HALF },
					solid
				)
				if #hits > 0 then
					bad += 1
					if bad <= 3 then
						t.truthy(false, `{e.id}: leg {leg} at ({X}, {D}) walks into {hits[1].path}`)
					end
				end
			end)
		end
	end)

	t.test("on the real town: the first attraction staff, each at work on their loop, inside on the floor", function()
		local data = Data.default()
		local world = TownAI.build({ data = data, seed = 3 })
		local place = (data:module("Attractions") :: any).attractions[1].place
		local staff: { [string]: any } = {}
		for _, a in world.actors do
			if a.job then
				staff[a.job] = a
			end
		end
		for _, e in AlleyStaff.EMPLOYEES do
			t.truthy(staff[e.id] ~= nil, `{e.id} is in the town`)
		end
		local acts: { [string]: { [string]: boolean } } = {}
		local moved: { [string]: number } = {}
		local last: { [string]: { number } } = {}
		for job, a in staff do
			acts[job] = {}
			moved[job] = 0
			last[job] = { a.x, a.z }
			t.eq(a.post, "attraction_staff")
			t.eq(world.brains[a.id].kind, "Staff")
		end
		local outside = 0
		for f = 1, 60 * 150 do
			TownAI.stepFrame(world, 1 / 15)
			if f % 4 == 0 then
				for job, a in staff do
					if a.task then
						acts[job][a.task] = true
					end
					moved[job] += math.sqrt((a.x - last[job][1]) ^ 2 + (a.z - last[job][2]) ^ 2)
					last[job] = { a.x, a.z }
					local fl = AlleyStaff.floorAt(place, a.x, a.z)
					if fl == nil or math.abs(a.y - a.hip - fl) > 0.05 then
						outside += 1
					end
				end
			end
		end
		t.eq(outside, 0, "every employee stays inside, on the floor")
		for _, e in AlleyStaff.EMPLOYEES do
			local n = 0
			for _ in acts[e.id] do
				n += 1
			end
			t.truthy(n >= 2, `{e.id}: {n} kinds of work in ten minutes`)
			t.truthy(moved[e.id] > 60, `{e.id} walked {moved[e.id]} studs`)
		end
		t.truthy(acts.mechanic.kneel, "the mechanic knelt")
		t.truthy(acts.shoe_clerk.spray, "the clerk sprayed")
		t.truthy(acts.cleaner.mop, "the cleaner mopped")
		-- a player takes over one and lets go: the brain picks up its loop again
		local clerk = staff.shoe_clerk
		TownAI.suspend(world, clerk.id)
		t.eq(clerk.task, nil, "no work shown on a body a player holds")
		TownAI.resume(world, clerk.id, clerk.x, clerk.y, clerk.z)
		for _ = 1, 60 * 20 do
			TownAI.stepFrame(world, 1 / 15)
		end
		t.truthy(AlleyStaff.inside(place, clerk.x, clerk.z), "back at work inside")
	end)
	t.test("the client's pose for the work: a kneel is the sit clip part way down; a patient's pose wins", function()
		local foot = 3.1
		local k = AnimationDriver.taskPose("kneel", foot)
		t.eq(k.clip, "sit")
		t.truthy(k.drop > 0 and k.drop < foot - AnimationDriver.SIT_SEAT, `kneel drop {k.drop}`)
		t.eq(k.flat, false)
		for act in AlleyStaff.ACTS do
			if act ~= "kneel" then
				t.eq(AnimationDriver.taskPose(act, foot).clip, nil, act)
			end
		end
		t.eq(AnimationDriver.pose("down", "kneel", foot).drop, AnimationDriver.medPose("down", foot).drop)
		t.eq(AnimationDriver.pose(nil, nil, foot).clip, nil)
	end)
end
