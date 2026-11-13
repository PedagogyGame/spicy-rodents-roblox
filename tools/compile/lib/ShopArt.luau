--!strict
-- tools/compile: data/art/neighbourhood_shop.json -> generated/ShopArt.luau.
-- The owner's Neighbourhood Shop (brief addendum D12) as the bake (tools/bake/neighbourhood_shop.luau) and the
-- loader (Server/Assets/ShopArt) need it: the uploaded Models (the shop, its gable roof), the colour of every
-- mesh (an untextured material may arrive grey from the importer; a textured one gets its map's mean colour
-- as a fallback), which meshes are glass, which glow (his lamp shades), which are plain boxes (drawn as Parts),
-- his colliders plus boxes round the floor-standing furniture, the camera's occluders inside his walls, the
-- lamps, the doorway, the roof's deck planes and its slope colliders (his decks up to his shingles). STUDS in the venue's local frame (Shared/Attractions/
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
-- Floor-standing furniture that gets a plain box collider over its meshes' bounds (floor to top), so a person
-- walks round a table, a rack, a chair, a big plant's pot or the open door's leaf instead of through it. His
-- metadata gives the counters; small and soft things (leaves, hats, posters, the bead curtain) stay
-- walk-through, as his pack says.
ShopArt.FURNITURE = table.freeze({
	{ name = "CAFE_Stool_01_Legs" },
	{ name = "CAFE_Stool_02_Legs" },
	{ name = "CAFE_Stool_03_Legs" },
	{ name = "CAFE_Stool_04_Legs" },
	{ name = "CAFE_Stool_05_Legs" },
	{ name = "CAFE_WindowTable_Legs" },
	{ name = "OFFICE_DeskLegs" },
	{ name = "OFFICE_FilingCabinet" },
	{ name = "RACK_clear_signal" },
	{ name = "RACK_loose_wire" },
	{ name = "RACK_midnight_static" },
	{ name = "RETAIL_DisplayTable_Legs" },
	{ name = "RETAIL_HatBench_Legs" },
	{ name = "RETAIL_SmallShelf_Sides" },
	{ name = "RETAIL_WallShelving_Sides" },
	-- the chairs: legs, seat and back as one box (the back stands at the seat's edge)
	{
		name = "CAFE_Chair_A",
		meshes = { "CAFE_Chair_A_Legs", "CAFE_Chair_A_Seat", "CAFE_Chair_A_Back", "CAFE_Chair_A_Backrest" },
	},
	{
		name = "CAFE_Chair_B",
		meshes = { "CAFE_Chair_B_Legs", "CAFE_Chair_B_Seat", "CAFE_Chair_B_Back", "CAFE_Chair_B_Backrest" },
	},
	{
		name = "OFFICE_Chair",
		meshes = { "OFFICE_Chair_Legs", "OFFICE_Chair_Seat", "OFFICE_Chair_Back", "OFFICE_Chair_Backrest" },
	},
	-- the floor-standing plants: their pots (the leaves above stay soft)
	{ name = "PLANT_BambooCafe_Pot" },
	{ name = "PLANT_BambooTall_Pot" },
	{ name = "PLANT_FernCafe_Pot" },
	{ name = "PLANT_Office_Pot" },
	{ name = "PLANT_RubberDivider_Pot" },
	{ name = "PLANT_RubberEntrance_Pot" },
	-- the open door's leaf, swung into the retail room beside the doorway
	{ name = "DOOR_OpenFrame", meshes = { "DOOR_OpenFrame", "DOOR_OpenGlass", "DOOR_KickPanel" } },
})
-- The walls that stop a camera (Roblox's default camera and Client/Camera/CameraRig only stop at an opaque part
-- that collides; his wall meshes are visual only and the colliders are invisible): an opaque box of the wall's
-- colour just inside each of these colliders, so it never shows while his mesh is there and is the wall if
-- his Model does not load. The shopfront is glass and stays clear.
ShopArt.OCCLUDES = table.freeze({
	Left = "WALL_Left",
	Back = "WALL_Back",
	Right = "WALL_Right",
	RoomDivider = "WALL_RoomDivider",
	OfficePartition = "WALL_OfficePartition",
	OfficeSide = "WALL_OfficeSide",
})
ShopArt.LINTELS = table.freeze({ "WALL_DividerLintel", "WALL_OfficeLintel" })
ShopArt.INSET = 0.06 -- studs: each occluder face inside his wall's face

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
		local rec: any = { name = m.name, colour = m.colour, at = m.centre }
		if m.alpha and m.alpha < 0.99 then
			rec.glass = true
		end
		if m.texture then
			rec.textured = true
			-- the map's mean colour times the material's tint: painted if the importer drops the texture
			rec.fallback = m.fallback
		end
		if m.emissive then
			rec.emissive = true
		end
		if m.box then
			-- a plain box (12 triangles, untextured): drawn as a Part (size; turn when not axis-aligned)
			rec.box = m.box.size
			if m.box.right then
				rec.right, rec.up = m.box.right, m.box.up
			end
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
	for _, f in ShopArt.FURNITURE do
		local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
		for _, name in f.meshes or { f.name } do
			local m = byName[name]
			ctx.invariant(`shop art: furniture mesh {name} exists`, m ~= nil)
			if m then
				local c = pt(m.centre)
				for k = 1, 3 do
					lo[k] = math.min(lo[k], c[k] - m.size[k] / 2)
					hi[k] = math.max(hi[k], c[k] + m.size[k] / 2)
				end
			end
		end
		if lo[1] < math.huge then
			table.insert(colliders, {
				name = f.name,
				centre = { r4((lo[1] + hi[1]) / 2), r4(hi[2] / 2), r4((lo[3] + hi[3]) / 2) },
				size = { r4(hi[1] - lo[1]), r4(hi[2]), r4(hi[3] - lo[3]) },
				from = "his mesh bounds",
			})
		end
	end
	-- the camera's occluders: inside his walls (the colliders above), and his two lintels over the doorways
	local occluders = {}
	local function colourOf(m: any): { number }
		return if m.texture and m.fallback then m.fallback else m.colour
	end
	local inset = ShopArt.INSET
	for _, c in colliders do
		local mesh = ShopArt.OCCLUDES[c.name]
		if mesh and (c.from == "his metadata" or c.from == "his mesh") then
			ctx.invariant(`shop art: wall mesh {mesh} exists`, byName[mesh] ~= nil)
			table.insert(occluders, {
				name = c.name,
				centre = c.centre,
				size = { r4(c.size[1] - 2 * inset), r4(c.size[2] - 2 * inset), r4(c.size[3] - 2 * inset) },
				colour = colourOf(byName[mesh]),
			})
		end
	end
	for _, name in ShopArt.LINTELS do
		local m = byName[name]
		ctx.invariant(`shop art: lintel {name} exists`, m ~= nil)
		if m then
			table.insert(occluders, {
				name = name,
				centre = pt(m.centre),
				size = { r4(m.size[1] - 2 * inset), r4(m.size[2] - 2 * inset), r4(m.size[3] - 2 * inset) },
				colour = colourOf(m),
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
		table.insert(lamps, { kind = l.kind, at = pt(l.at), size = l.size })
	end
	local decks = {}
	for _, name in { "RoofDeck_East", "RoofDeck_West" } do
		table.insert(decks, oriented(doc.roof.decks[name]))
	end
	-- his roof's colliders: each slope is his deck's own box (as wide as the drawn roof, out over both gables)
	-- reaching up to the top of his shingles; his ridge perch proxy, as wide as the decks
	local roofColliders = {}
	local deckWidth = 0
	for _, name in { "RoofDeck_East", "RoofDeck_West" } do
		local d = doc.roof.decks[name]
		local bottom, top = -d.size[2] / 2, d.shingleTop or d.size[2] / 2
		local mid = (bottom + top) / 2
		local box = oriented(d)
		box.name = if d.centre[3] > 0 then "RoofSlope_Front" else "RoofSlope_Back"
		box.centre = pt({
			d.centre[1] + d.up[1] * mid,
			d.centre[2] + d.up[2] * mid,
			d.centre[3] + d.up[3] * mid,
		})
		box.size = { d.size[1], r4(top - bottom), d.size[3] }
		deckWidth = math.max(deckWidth, d.size[1])
		table.insert(roofColliders, box)
	end
	for _, b in doc.roofColliders do
		if string.find(b.name, "Ridge") then
			local box = oriented(b)
			box.size = { deckWidth, b.size[2], b.size[3] }
			table.insert(roofColliders, box)
		end
	end
	local value = {
		venue = "f1_neighbourhood_shop",
		scale = doc.scale,
		assets = assets,
		entrance = { X = entrance[1], D = entrance[3], width = doc.entrance.clearWidth },
		doorway = { x0 = r4(x0), x1 = r4(x1), top = r4(doorTop) },
		front = { x0 = r4(frontX0), x1 = r4(frontX1), d0 = r4(frontD0), d1 = r4(frontD1), top = r4(frontTop) },
		colliders = colliders,
		occluders = occluders,
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
