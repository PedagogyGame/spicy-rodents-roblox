--!strict
-- Where squirrels find nuts (Shared/Foraging/NutSpots; owner D16 #22): every spot is on open, level ground in the baked
-- town (build/Town.rbxm and build/Attractions.rbxm: lune run tools/bake/main.luau and attractions.luau), its ground
-- the terrain's (the server lays the acorns at World/Height), nothing standing on it or low over it, clear of every
-- building and venue (World/Colliders), road, path, tree trunk, hollow hole and river; the tree spots under the acorn
-- oaks; ids unique; every kind known; spread over the town.
local fs = require("@lune/fs")
local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local Colliders = require("@shared/World/Colliders")
local Recovery = require("@shared/Movement/Recovery")
local HollowLayout = require("@shared/World/HollowLayout")
local NutSpots = require("@shared/Foraging/NutSpots")
local BakedWorld = require("@tests/lib/BakedWorld")
local Lots = require("../../generated/Lots")
local Roads = require("../../generated/Roads")
local Wildlife = require("../../generated/Wildlife")
local TerrainExtensions = require("../../generated/TerrainExtensions")

local function segDist(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number
	local vx, vz = bx - ax, bz - az
	local l2 = vx * vx + vz * vz
	local t = if l2 > 0 then math.clamp(((px - ax) * vx + (pz - az) * vz) / l2, 0, 1) else 0
	local dx, dz = ax + vx * t - px, az + vz * t - pz
	return math.sqrt(dx * dx + dz * dz)
end

return function(t)
	local trees = (Wildlife :: any).studs.trees.trees

	t.test("ids unique, kinds known, every kind stocked and growing back; 49 spots spread over the town", function()
		local ids = {}
		local per: { [string]: number } = {}
		local stock = 0
		for _, s in NutSpots.SPOTS do
			t.falsy(ids[s.id], s.id)
			ids[s.id] = true
			t.truthy(NutSpots.KINDS[s.kind], `{s.id}: kind {s.kind}`)
			t.eq(NutSpots.byId(s.id), s)
			per[s.kind] = (per[s.kind] or 0) + 1
			stock += NutSpots.stockOf(s)
			t.truthy(NutSpots.regrowDaysOf(s) > 0 and NutSpots.regrowDaysOf(s) < 2, `{s.id}: grows back`)
		end
		t.eq(#NutSpots.SPOTS, 49)
		t.eq(per.tree, 18)
		t.eq(per.yard, 17)
		t.eq(per.park, 11)
		t.eq(per.premium, 3)
		t.eq(stock, 128, "nuts in the town when every spot is full")
		-- spread: spots in every quarter of the town, and none closer than 3.5 studs to another
		local quarters = {}
		for i, a in NutSpots.SPOTS do
			quarters[(if a.x < 0 then 1 else 0) + (if a.z < 0 then 2 else 0)] = true
			for j = i + 1, #NutSpots.SPOTS do
				local b = NutSpots.SPOTS[j]
				t.truthy(math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) >= 3.5, `{a.id} next to {b.id}`)
			end
		end
		for q = 0, 3 do
			t.truthy(quarters[q], `a spot in quarter {q}`)
		end
	end)

	t.test("the tree spots lie under acorn oaks, a few studs off the bark", function()
		for _, s in NutSpots.SPOTS do
			if s.kind ~= "tree" then
				continue
			end
			local oak: any = nil
			for _, tr in trees do
				if tr.name == s.near then
					oak = tr
				end
			end
			t.truthy(oak, `{s.id}: {s.near}`)
			t.truthy(type(oak.acorns) == "number" and oak.acorns > 0, `{s.near} has acorns`)
			local d = math.sqrt((s.x - oak.x) ^ 2 + (s.z - oak.z) ^ 2)
			t.truthy(d > oak.trunkBaseRadius + 1.5 and d < oak.trunkBaseRadius + 8, `{s.id}: {d} from the axis`)
		end
	end)

	t.test("every spot: open, level ground in the baked town, clear of buildings, roads and trunks", function()
		t.truthy(fs.isFile("build/Town.rbxm"), "build/Town.rbxm (lune run tools/bake/main.luau)")
		t.truthy(fs.isFile("build/Attractions.rbxm"), "build/Attractions.rbxm (lune run tools/bake/attractions.luau)")
		Height.configure(TerrainExtensions :: any)
		local town = BakedWorld.load("build/Town.rbxm")
		local att = BakedWorld.load("build/Attractions.rbxm")
		local cols = Colliders.fromData(Data.default())
		local layout = HollowLayout.default() :: HollowLayout.Layout
		local solidNotMesh = function(p: BakedWorld.Part): boolean
			-- (BakedWorld takes a MeshPart as its whole box: a tree's canopy)
			return p.shape ~= "box" and (p.visible or p.collide)
		end
		for _, s in NutSpots.SPOTS do
			local x, z = s.x, s.z
			local h = Height.at(x, z)
			local g = town.groundAt(x, z, h + 3)
			t.truthy(math.abs(g - h) <= 0.35, `{s.id}: the baked ground {g} is the terrain's {h}`)
			for dx = -1.5, 1.5, 1.5 do
				for dz = -1.5, 1.5, 1.5 do
					t.truthy(math.abs(Height.at(x + dx, z + dz) - h) <= 1.2, `{s.id}: level`)
				end
			end
			local b = town.blocker(x, z, g, 1.0) or att.blocker(x, z, g, 1.0)
			t.eq(b and b.path, nil, `{s.id}: nothing standing on it`)
			local over = town.containing(x, g + 0.4, z, solidNotMesh)
			t.eq(over[1] and over[1].path, nil, `{s.id}: nothing low over it`)
			t.eq(Colliders.pointIn(cols, x, z, g + 1, 1.5), nil, `{s.id}: in a building or venue`)
			for _, r in Roads :: { any } do
				local w = (r.width or 0) / 2 + 2
				local on = false
				if r.axis == "z" then
					on = math.abs(x - r.coord) < w and z > r.start - 2 and z < r["end"] + 2
				elseif r.axis == "x" then
					on = math.abs(z - r.coord) < w and x > r.start - 2 and x < r["end"] + 2
				elseif r.axis == "free" then
					on = segDist(x, z, r.start[1], r.start[2], r["end"][1], r["end"][2]) < w
				end
				t.falsy(on, `{s.id} on road {r.id}`)
			end
			for _, l in Lots :: { any } do
				local ty = string.lower(l.type or "")
				local fp = l.footprint or { w = 0, d = 0 }
				local hw = math.max(fp.w or 0, fp.d or 0) / 2 + 1
				local soft = string.find(ty, "fence") or string.find(ty, "park") or string.find(ty, "garden")
				if not soft then
					t.falsy(math.abs(x - l.x) < hw and math.abs(z - l.z) < hw, `{s.id} on lot {l.id} ({l.type})`)
				end
			end
			for _, tr in trees do
				local d = math.sqrt((x - tr.x) ^ 2 + (z - tr.z) ^ 2)
				t.truthy(d >= (tr.trunkBaseRadius or 2) + 1.2, `{s.id} at the trunk of {tr.name}`)
			end
			for _, hl in layout.hollows do
				for _, m in hl.mouths do
					if m.opens == "ground" then
						t.truthy(math.sqrt((x - m.x) ^ 2 + (z - m.z) ^ 2) >= 6, `{s.id} at {hl.id}'s hole`)
					end
				end
			end
			t.eq(Recovery.riverFall(x, h + 1, z), nil, `{s.id}: in the river`)
		end
		Height.configure(nil)
	end)
end
