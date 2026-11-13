--!strict
-- tools/compile: data/art/neighbourhood_shop.json -> generated/ShopArt.luau.
-- The owner's Neighbourhood Shop (brief addendum D12) as the bake (tools/bake/neighbourhood_shop.luau) and the
-- loader (Server/Assets/ShopArt) need it: the uploaded Models (the shop, its gable roof), the colour of every
-- mesh (an untextured material may arrive grey from the importer), which meshes are glass, his colliders,
-- the lamps, the doorway and the roof's deck planes. STUDS in the venue's local frame (Shared/Attractions/
-- AlleyLayout: X across the frontage, Y up from the floor, D into the building; the manifest's Roblox Z is -D).
-- Invariants: both Models uploaded and Approved; 355 shop meshes and 41,264 triangles as his metadata says,
-- no mesh over the engine's 20,000 triangles; the entrance node in the doorway; every collider inside the
-- shop's walls.
-- Interface: compile(ctx) -> Module? (nil when the file is absent)
local fs = require("@lune/fs")
local Json = require("./Json")

local ShopArt = {}

ShopArt.MESHES = 355 -- his metadata: mesh_objects
ShopArt.TRIANGLES = 41264 -- his metadata: triangle_count
ShopArt.MAX_MESH_TRIS = 20000 -- the engine's limit per MeshPart
-- Floor-standing furniture that gets a plain box collider from its mesh's bounds (floor to top), so a person
-- walks round a table or a rack instead of through it. His metadata gives the counters; small things (plants,
-- hats, posters, the bead curtain) stay walk-through.
ShopArt.FURNITURE = table.freeze({
	"CAFE_Stool_01_Legs",
	"CAFE_Stool_02_Legs",
	"CAFE_Stool_03_Legs",
	"CAFE_Stool_04_Legs",
	"CAFE_Stool_05_Legs",
	"CAFE_WindowTable_Legs",
	"OFFICE_DeskLegs",
	"OFFICE_FilingCabinet",
	"RACK_clear_signal",
	"RACK_loose_wire",
	"RACK_midnight_static",
	"RETAIL_DisplayTable_Legs",
	"RETAIL_HatBench_Legs",
	"RETAIL_SmallShelf_Sides",
	"RETAIL_WallShelving_Sides",
})

local function r4(n: number): number
	return math.floor(n * 1e4 + 0.5) / 1e4
end

-- (X, Y, Z) at yaw 0 -> (X, Y, D)
local function pt(p: { number }): { number }
	return { r4(p[1]), r4(p[2]), r4(-p[3]) }
end

local function parts(list: { any }): { any }
	local out = {}
	for _, m in list do
		-- at: the MeshPart's centre in the Model's own frame (Roblox axes, the shop floor's centre), for the loader
		local rec: any = { name = m.name, colour = m.colour, tris = m.tris, at = m.centre }
		if m.alpha and m.alpha < 0.99 then
			rec.glass = true
		end
		if m.texture then
			rec.textured = true
		end
		table.insert(out, rec)
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out
end

local function oriented(b: any): any
	return {
		name = b.name,
		centre = pt(b.centre),
		size = b.size,
		right = pt(b.right),
		up = pt(b.up),
		back = pt(b.back),
	}
end

function ShopArt.compile(ctx: any): any?
	local rel = "data/art/neighbourhood_shop.json"
	local path = ctx.repo .. "/" .. rel
	if not fs.isFile(path) then
		return nil
	end
	local doc = Json.decodeFile(path)
	local assets = {}
	for _, key in { "shop", "roof" } do
		local a = doc.assets[key]
		ctx.invariant(`shop art: the {key} Model is uploaded`, a ~= nil and type(a.assetId) == "string")
		ctx.invariant(`shop art: the {key} Model is Approved`, a ~= nil and a.moderation == "Approved")
		assets[key] = { id = tonumber(a.assetId), moderation = a.moderation, displayName = a.displayName }
	end
	local tris, biggest = 0, 0
	for _, m in doc.shop do
		tris += m.tris
		biggest = math.max(biggest, m.tris)
	end
	ctx.compare("shop art meshes (his metadata: mesh_objects)", ShopArt.MESHES, #doc.shop)
	ctx.compare("shop art triangles (his metadata: triangle_count)", ShopArt.TRIANGLES, tris)
	ctx.invariant("shop art: no mesh over the engine's 20,000 triangles", biggest <= ShopArt.MAX_MESH_TRIS)

	-- the doorway: the gap between the front piers either side of his entrance node, as high as the door frame
	local entrance = pt(doc.entrance.at)
	local x0, x1 = -math.huge, math.huge
	local frontD0, frontD1, frontX0, frontX1, frontTop = math.huge, -math.huge, math.huge, -math.huge, 0
	for _, b in doc.front.FRONT_Piers do
		local c = pt(b.centre)
		local lo, hi = c[1] - b.size[1] / 2, c[1] + b.size[1] / 2
		if hi <= entrance[1] then
			x0 = math.max(x0, hi)
		elseif lo >= entrance[1] then
			x1 = math.min(x1, lo)
		end
		frontD0 = math.min(frontD0, c[3] - b.size[3] / 2)
		frontD1 = math.max(frontD1, c[3] + b.size[3] / 2)
		frontX0, frontX1 = math.min(frontX0, lo), math.max(frontX1, hi)
		frontTop = math.max(frontTop, c[2] + b.size[2] / 2)
	end
	local doorTop = 0
	for _, b in doc.front.DOOR_OpenFrame do
		doorTop = math.max(doorTop, b.centre[2] + b.size[2] / 2)
	end
	ctx.invariant(
		"shop art: the entrance node stands in a doorway between two piers",
		x0 > -math.huge and x1 < math.huge
	)
	ctx.invariant(
		"shop art: the doorway is as wide as his metadata's clear width",
		math.abs((x1 - x0) - doc.entrance.clearWidth) < 0.05
	)

	local colliders = {}
	-- inside the walls: the front piers' outer edge across, the front plane's depth both ways (12 x 14 m)
	local half = { x = frontX1, d = math.max(math.abs(frontD0), math.abs(frontD1)) }
	for _, c in doc.colliders do
		table.insert(colliders, { name = c.name, centre = pt(c.centre), size = c.size, from = "his metadata" })
	end
	-- his metadata leaves out the office's side wall (the utility void beside the office): its mesh is there
	for _, b in doc.front.WALL_OfficeSide do
		table.insert(colliders, { name = "OfficeSide", centre = pt(b.centre), size = b.size, from = "his mesh" })
	end
	local byName: { [string]: any } = {}
	for _, m in doc.shop do
		byName[m.name] = m
	end
	for _, name in ShopArt.FURNITURE do
		local m = byName[name]
		ctx.invariant(`shop art: furniture mesh {name} exists`, m ~= nil)
		if m then
			local c = pt(m.centre)
			local top = c[2] + m.size[2] / 2
			table.insert(colliders, {
				name = name,
				centre = { c[1], r4(top / 2), c[3] },
				size = { m.size[1], r4(top), m.size[3] },
				from = "his mesh bounds",
			})
		end
	end
	for _, c in colliders do
		ctx.invariant(
			`shop art: collider {c.name} inside the walls`,
			math.abs(c.centre[1]) - c.size[1] / 2 <= half.x + 0.75
				and math.abs(c.centre[3]) - c.size[3] / 2 <= half.d + 0.75
		)
	end
	local lamps = {}
	for _, l in doc.lamps do
		table.insert(lamps, { kind = l.kind, at = pt(l.at) })
	end
	local decks = {}
	for _, name in { "RoofDeck_East", "RoofDeck_West" } do
		table.insert(decks, oriented(doc.roof.decks[name]))
	end
	local roofColliders = {}
	for _, b in doc.roofColliders do
		table.insert(roofColliders, oriented(b))
	end
	local value = {
		venue = "f1_neighbourhood_shop",
		scale = doc.scale,
		assets = assets,
		entrance = { X = entrance[1], D = entrance[3], width = doc.entrance.clearWidth },
		doorway = { x0 = r4(x0), x1 = r4(x1), top = r4(doorTop) },
		front = { x0 = r4(frontX0), x1 = r4(frontX1), d0 = r4(frontD0), d1 = r4(frontD1), top = r4(frontTop) },
		colliders = colliders,
		lamps = lamps,
		roof = {
			span = doc.roof.span,
			run = doc.roof.run,
			decks = decks,
			colliders = roofColliders,
			top = r4(doc.roof.box.centre[2] + doc.roof.box.size[2] / 2),
		},
		shop = parts(doc.shop),
		roofParts = parts(doc.roofMeshes),
	}
	return {
		name = "ShopArt",
		value = value,
		records = #value.shop + #value.roofParts,
		map = true,
		source = rel,
		header = {
			"STUDS, the venue's local frame (X across, Y up from the floor, D into the building). The owner's shop and",
			"roof Models (loaded at boot by Server/Assets/ShopArt), mesh colours, colliders, lamps, doorway, roof decks.",
		},
	}
end

return ShopArt
