--!strict
-- Owner D30 (2026-11-22): "the npcs at the top of the skylift dont move!" (Shared/Rides/LookoutLife: the Lookout's
-- own way on foot; Server/Rides/SkyLiftService walks the host and the visitors along it).
--   clear    THE LOOKOUT and the summit station baked in memory (tools/bake/lookout, tools/bake/skylift/Summit):
--            every node stands on a floor, a deck or a platform, and every edge, the four arrival spots' first
--            steps and every chair's last step are walked with a body's width without meeting a wall, a table,
--            a chair, a rail, the counter, the telescope or a planter (a stride over a step is fine)
--   ways     every table's aisle-side chairs and every stroll stop are reached from the arrival platform and
--            lead to the queue behind the boarding gate; the host's round loops through all its stops
--   walker   the walk goes at its speed, holds each stop facing its work, loops (the host) or ends (a visitor)
local roblox = require("@lune/roblox")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local SkyLift = require("@shared/Rides/SkyLift")
local LookoutLife = require("@shared/Rides/LookoutLife")
local Kit = require("../../tools/bake/alley/Kit")
local Lookout = require("../../tools/bake/lookout/Lookout")
local Summit = require("../../tools/bake/skylift/Summit")

type Box = { name: string, x0: number, x1: number, y0: number, y1: number, d0: number, d1: number }

local R = 0.8 -- a walker's half width
local STRIDE = 0.8 -- what a walker steps over (the platform's front step is 1.0 in two)
local HEAD = 5.6

return function(t)
	local mod = require("../../generated/Expansion") :: any
	local venue: any
	for _, v in mod.venues do
		if v.id == "f3_hilltop" then
			venue = v
		end
	end
	local place = venue.place
	local folder = roblox.Instance.new("Folder")
	local kit = Kit.new(roblox, place)
	local roots = { Lookout.build(kit, folder, venue), Summit.build(kit, folder, venue) }

	local function under(p: any, name: string, root: any): boolean
		local a = p.Parent
		while a and a ~= root do
			if a.Name == name then
				return true
			end
			a = a.Parent
		end
		return false
	end
	-- every visible built part, as a box in the venue's frame
	local boxes: { Box } = {}
	for _, root in roots do
		for _, d in root:GetDescendants() do
			if
				d:IsA("BasePart")
				and d.Transparency < 0.99
				and not under(d, "TerrainCarve", root)
				and not under(d, "Anchors", root)
			then
				local s = d.Size / 2
				local b: Box = {
					name = d.Name,
					x0 = math.huge,
					x1 = -math.huge,
					y0 = math.huge,
					y1 = -math.huge,
					d0 = math.huge,
					d1 = -math.huge,
				}
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local w = d.CFrame * roblox.Vector3.new(sx * s.X, sy * s.Y, sz * s.Z)
							local X, Y, D = AlleyLayout.toLocal(place, w.X, w.Y, w.Z)
							b.x0, b.x1 = math.min(b.x0, X), math.max(b.x1, X)
							b.y0, b.y1 = math.min(b.y0, Y), math.max(b.y1, Y)
							b.d0, b.d1 = math.min(b.d0, D), math.max(b.d1, D)
						end
					end
				end
				table.insert(boxes, b)
			end
		end
	end

	-- what a body standing on `surface` at local (X, D) meets: the first box its width reaches between a stride
	-- over its feet and the top of its head
	local function hit(X: number, D: number, surface: number): Box?
		for _, b in boxes do
			if
				X > b.x0 - R
				and X < b.x1 + R
				and D > b.d0 - R
				and D < b.d1 + R
				and b.y1 > surface + STRIDE
				and b.y0 < surface + HEAD
			then
				return b
			end
		end
		return nil
	end
	local function walk(tag: string, a: { number }, b: { number })
		local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local n = math.max(1, math.ceil(len / 0.4))
		for k = 0, n do
			local f = k / n
			local X, D = a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
			local Y = a[3] + (b[3] - a[3]) * f
			local box = hit(X, D, Y)
			if box then
				error(
					string.format(
						"%s: at (%.1f, %.1f) a walker meets %s (X %.1f..%.1f D %.1f..%.1f Y %.1f..%.1f)",
						tag,
						X,
						D,
						box.name,
						box.x0,
						box.x1,
						box.d0,
						box.d1,
						box.y0,
						box.y1
					)
				)
			end
		end
	end
	local function localOf(p: LookoutLife.Point): { number }
		local X, Y, D = AlleyLayout.toLocal(place, p.x, p.y, p.z)
		return { X, D, Y }
	end

	t.test("clear: every node on a floor, every edge walked with a body's width meets nothing", function()
		for id, n in LookoutLife.NODES do
			local floor = false
			for _, b in boxes do
				if n[1] >= b.x0 and n[1] <= b.x1 and n[2] >= b.d0 and n[2] <= b.d1 and math.abs(b.y1 - n[3]) < 0.3 then
					floor = true
					break
				end
			end
			t.truthy(floor, `{id}: nothing to stand on at {n[1]}, {n[2]} (Y {n[3]})`)
		end
		for _, e in LookoutLife.EDGES do
			walk(`{e[1]} -> {e[2]}`, LookoutLife.NODES[e[1]], LookoutLife.NODES[e[2]])
		end
	end)

	t.test("clear: off the cabin at any arrival spot to the platform's way; a chair's last steps", function()
		for k = 1, 4 do
			local x, y, z = SkyLift.alightSpot("summit", k)
			local X, Y, D = AlleyLayout.toLocal(place, x, y, z)
			walk(`arrival spot {k}`, { X, D, Y }, LookoutLife.NODES.hall_platform)
		end
		for id in LookoutLife.TABLES do
			for _, side in { "front", "back" } do
				local _seat, _yaw, stand, node = LookoutLife.chair(place, id, side)
				walk(`{id} {side}: the aisle to behind the chair`, LookoutLife.NODES[node], localOf(stand))
			end
		end
	end)

	t.test("ways: every chair and stroll stop from the platform, and on to the boarding queue", function()
		for id in LookoutLife.TABLES do
			for _, side in { "front", "back" } do
				local pts = LookoutLife.plan(place, { tableId = id, side = side, dine = 30 })
				local seated = 0
				for _, p in pts do
					if p.sit then
						seated += 1
						t.eq(p.hold, 30)
					end
				end
				t.eq(seated, 1, `{id} {side}: one chair`)
				local last = localOf(pts[#pts])
				t.near(last[1], LookoutLife.NODES.board_queue[1], 1e-6)
				t.near(last[2], LookoutLife.NODES.board_queue[2], 1e-6)
			end
		end
		local stroll = LookoutLife.plan(place, { strollFrom = 2 })
		local held = 0
		for _, p in stroll do
			if (p.hold or 0) > 0 then
				held += 1
			end
		end
		t.eq(held, #LookoutLife.STROLL)
		-- the host's round passes every stop of its, in order, and comes back to the lectern
		local round = LookoutLife.hostRound(place)
		local k = 1
		for _, p in round do
			if (p.hold or 0) > 0 then
				local s = LookoutLife.HOST[k]
				local n = LookoutLife.NODES[s.node]
				local here = localOf(p)
				t.near(here[1], n[1], 1e-6, s.node)
				t.near(here[2], n[2], 1e-6, s.node)
				k += 1
			end
		end
		t.eq(k, #LookoutLife.HOST + 1, "every host stop held once")
		local route = LookoutLife.route("board_queue", "view_43")
		t.truthy(route ~= nil and #route > 10, "the far corner of the terrace from the boarding queue")
	end)

	t.test("walker: at its speed, holds its stops facing them, loops or ends", function()
		local pts: { LookoutLife.Point } = {
			{ x = 0, y = 0, z = 0 },
			{ x = 10, y = 0, z = 0, hold = 2, act = "serve", yaw = 1.25 },
			{ x = 10, y = 0, z = 10 },
		}
		local w = LookoutLife.walker(pts, 5, false)
		local x, _, _, yaw, speed, act = LookoutLife.advance(w, 1)
		t.near(x, 5, 1e-9)
		t.eq(speed, 5)
		t.eq(act, nil)
		t.near(yaw, math.atan2(-1, 0), 1e-9, "facing the way it walks (+X)")
		x, _, _, yaw, speed, act = LookoutLife.advance(w, 1.5) -- 1 s to the stop, 0.5 s held
		t.near(x, 10, 1e-9)
		t.eq(speed, 0)
		t.eq(act, "serve")
		t.near(yaw, 1.25, 1e-9, "facing its work")
		local _, _, z = LookoutLife.advance(w, 2.5) -- 1.5 s more held, 1 s on
		t.near(z, 5, 1e-9)
		LookoutLife.advance(w, 10)
		t.truthy(w.done, "a visitor's walk ends")
		local loop = LookoutLife.walker(pts, 5, true)
		LookoutLife.advance(loop, 40)
		t.falsy(loop.done, "the host's round never ends")
		-- the host's round, stepped as the server steps it: always somewhere on it, never still for long
		local round = LookoutLife.walker(LookoutLife.hostRound(place), LookoutLife.HOST_SPEED, true)
		local still, longest, moved = 0, 0, 0
		local lx, lz = nil :: number?, nil :: number?
		for _ = 1, 3000 do
			local hx, _, hz, _, s = LookoutLife.advance(round, 0.1)
			if s == 0 then
				still += 0.1
				longest = math.max(longest, still)
			else
				still = 0
			end
			if lx and lz then
				moved += math.sqrt((hx - lx) ^ 2 + (hz - lz) ^ 2)
			end
			lx, lz = hx, hz
		end
		t.truthy(longest <= 12.05, `the host stood still {longest} s`)
		t.truthy(moved > 600, `the host walked only {moved} studs in 300 s`)
	end)
end
