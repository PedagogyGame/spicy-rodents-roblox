--!strict
-- tools/bake/alley/RoofKit: the pieces of the owner's roof and rafter kit (docs/reference/store_roofs/roof_rafter_kit,
-- brief addendum D13: use his deliveries where they fit) that the yard house takes, at the game's one scale.
-- His meshes are plain boxes (12 triangles each, one colour each), so they come to the bake as data:
-- data/art/roof_rafter_kit.json, written from his GLBs by tools/blender/roof_kit/extract_boxes.py (each box's
-- centre, size, axes and colour in his file's frame: metres, x across the span, y up, z along the ridge), and are
-- built as Parts here. No upload: a box mesh is drawn as a Part anyway (Server/Assets/ShopArt.boxes does that with
-- his roof on the Neighbourhood Shop), and a Part costs no asset and batches.
-- The scale is the one his Neighbourhood Shop pack is fitted at, SCALE studs per metre
-- (tools/blender/neighbourhood_shop/export_shop.py), never stretched. What fits the yard house at that scale:
--   03_Ridge_Eave_Route_Perches  two of his ridge perch planks end to end with their grips, along the house's
--                                ridge (route 9103 runs on the planks' top)
--   05_Gutter_Fascia_Details     his gutter brackets at his spacing under the house's gutters
-- What does not, and why (the yard house, Shared/Attractions/AlleyRoof.HOUSE, is 24 x 24 studs and pinned by the
-- routes up its downspout, gutter and ridge and the leap off the ridge's west end onto the bough):
--   02_Full_Gable_Roof_14m       spans 10 m (34.5 studs with its gutters) and runs 15 m (45 studs) at SCALE: the
--                                house would have to grow by half one way and nearly double the other, moving the
--                                ridge, the leap and the tree's limb; fitting it to 24 x 24 means stretching it
--                                0.8 across and 0.54 along, not one scale
--   his eave landings and slope footholds (03): flat pads and 2-stud steps stood on his 33-degree slope; on the
--                                house's 35-degree north slope they stand across route 9102 where the drawn squirrel
--                                walks 0.15 over the slates
--   his gutter runs and downpipes (05): 15 m runs; the house's gutters and downspout are drawn round route 9101
--   01_Exposed_Rafter_Bay_2m, 04_Roof_Collider_Proxies: see tools/bake/alley/Roof (a timber gable bay under a
--                                flat-decked steel hall) and Yard (the house's own boards collide)
-- Interface: SCALE; data() -> the decoded file; piece(file, name) -> Piece; lay(kit, parent, name, piece, ref, at,
--   material, opts?) -> Part (his point `ref` lands on the local point `at`; his z along local X, y up, x along D)
-- Lune only (@lune/fs: the file is read from the repo root, where the bakes and specs run).

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local RoofKit = {}

RoofKit.SCALE = 3.0 -- studs per metre: a person (5.5 studs) is 1.83 m
RoofKit.FILE = "data/art/roof_rafter_kit.json"

export type Piece = {
	name: string,
	centre: { number },
	size: { number },
	right: { number },
	up: { number },
	back: { number },
	color: { number },
}

local cache: any = nil

function RoofKit.data(): any
	if cache == nil then
		cache = serde.decode("json", fs.readFile(RoofKit.FILE))
	end
	return cache
end

function RoofKit.piece(file: string, name: string): Piece
	for _, p in RoofKit.data().pieces[file] do
		if p.name == name then
			return p :: Piece
		end
	end
	error(`{RoofKit.FILE}: no piece {name} in {file}`)
end

-- His box `piece` as a Part, its point `ref` (his frame, metres) on the local point `at` (X, Y, D). Only his
-- square-on boxes (the pieces used here are all axis-aligned in his file).
function RoofKit.lay(
	kit: any,
	parent: any,
	name: string,
	piece: Piece,
	ref: { number },
	at: { number },
	material: string,
	opts: any?
): any
	assert(piece.right[1] == 1 and piece.up[2] == 1, `{piece.name} is not square-on in his file`)
	local s = RoofKit.SCALE
	local c = piece.centre
	return kit:at(
		parent,
		name,
		at[1] + (c[3] - ref[3]) * s,
		at[2] + (c[2] - ref[2]) * s,
		at[3] + (c[1] - ref[1]) * s,
		piece.size[3] * s,
		piece.size[2] * s,
		piece.size[1] * s,
		piece.color,
		material,
		opts
	)
end

return RoofKit
