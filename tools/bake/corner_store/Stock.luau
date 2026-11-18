--!strict
-- tools/bake/corner_store/Stock: the corner store's 22 items (Shared/Items/ItemRules.CATALOG) as small plain-part
-- models, each recognisable at a glance from the aisle: a red frisbee, a brown football with white laces, a
-- bottle of bubbles with its wand, a box of chalk, a torch, a closed umbrella, a bag of peanuts, a big bag of
-- bird seed, a box of dog treats, a folded newspaper, a yellow disposable camera, a roll of duct tape, a pink
-- whoopee cushion, a harmonica, an air horn, a soda bottle, an ice cream bar, a folding lawn chair, a transistor
-- radio, a bike horn, a diamond kite with its tail, and an orange water gun.
-- Every model stands on its origin (the bottom centre) and faces local -D at yaw 0 (Roblox +Z); `yaw` turns it
-- about Y in Roblox's sense (pi/2 faces local +X). The parts are visual (no collision, no query): the shelf
-- under them is the solid. The server clones a shelf's "Sample" model as the item a player carries.
-- Interface: build(kit, parent, itemId, x, y, d, yaw) -> Model; SIZE[itemId] -> { w, h, d } (its rough box);
--   IDS (the 22 ids, in the catalogue's order).
-- No side effects on require. Lune only (@lune/roblox through the Kit).

local Kit = require("../alley/Kit")

local Stock = {}

Stock.IDS = {
	"water_gun",
	"frisbee",
	"football",
	"bubbles",
	"chalk",
	"flashlight",
	"umbrella",
	"peanuts",
	"bird_seed",
	"dog_treats",
	"newspaper",
	"camera",
	"duct_tape",
	"whoopee_cushion",
	"harmonica",
	"air_horn",
	"soda",
	"ice_cream_bar",
	"lawn_chair",
	"radio",
	"bike_horn",
	"kite",
}

-- the rough box each one fills (studs: across, up, deep), for laying them out on a shelf
Stock.SIZE = {
	water_gun = { 1.3, 0.9, 0.3 },
	frisbee = { 1.1, 0.15, 1.1 },
	football = { 1.0, 0.6, 0.6 },
	bubbles = { 0.4, 0.8, 0.4 },
	chalk = { 0.9, 0.5, 0.35 },
	flashlight = { 0.3, 1.0, 0.3 },
	umbrella = { 0.35, 3.0, 0.35 },
	peanuts = { 0.7, 0.9, 0.3 },
	bird_seed = { 1.2, 1.6, 0.6 },
	dog_treats = { 0.8, 1.0, 0.35 },
	newspaper = { 1.2, 0.25, 0.8 },
	camera = { 0.6, 0.4, 0.25 },
	duct_tape = { 0.7, 0.3, 0.7 },
	whoopee_cushion = { 1.0, 0.3, 1.0 },
	harmonica = { 0.8, 0.2, 0.3 },
	air_horn = { 0.4, 1.1, 0.4 },
	soda = { 0.4, 1.2, 0.4 },
	ice_cream_bar = { 0.5, 0.2, 1.0 },
	lawn_chair = { 2.0, 3.0, 2.0 },
	radio = { 1.2, 1.1, 0.5 },
	bike_horn = { 0.5, 0.5, 1.0 },
	kite = { 2.2, 3.4, 0.2 },
}

local VISUAL = { collide = false, query = false, shadow = false }

type Piece = {
	name: string,
	at: { number }, -- offset from the origin (X, Y, D) before the yaw
	size: { number },
	color: { number },
	material: string?,
	shape: string?, -- "Cylinder" (along the piece's own X) | "Ball" | nil (block)
	rot: { number }?, -- extra rotation (rx, ry, rz) radians, Roblox axes, before the yaw
	neon: boolean?,
}

local function P(
	name: string,
	at: { number },
	size: { number },
	color: { number },
	shape: string?,
	rot: { number }?,
	material: string?
): Piece
	return { name = name, at = at, size = size, color = color, shape = shape, rot = rot, material = material }
end

local UP = { 0, 0, math.pi / 2 } -- a cylinder standing up
local ALONG_D = { 0, math.pi / 2, 0 } -- a cylinder lying along D

-- stylua: ignore
local MODELS: { [string]: { Piece } } = {
	water_gun = {
		P("Body", { 0, 0.55, 0 }, { 1.1, 0.35, 0.25 }, { 255, 120, 20 }),
		P("Tank", { -0.1, 0.85, 0 }, { 0.5, 0.3, 0.3 }, { 60, 140, 230 }, "Cylinder"),
		P("Grip", { 0.3, 0.2, 0 }, { 0.25, 0.45, 0.22 }, { 255, 210, 40 }),
		P("Nozzle", { -0.65, 0.55, 0 }, { 0.3, 0.12, 0.12 }, { 255, 210, 40 }, "Cylinder"),
	},
	frisbee = {
		P("Disc", { 0, 0.07, 0 }, { 0.14, 1.1, 1.1 }, { 220, 40, 40 }, "Cylinder", UP),
	},
	football = {
		P("Ball", { 0, 0.3, 0 }, { 0.95, 0.56, 0.56 }, { 128, 70, 34 }, "Cylinder"),
		P("TipL", { -0.48, 0.3, 0 }, { 0.3, 0.3, 0.3 }, { 128, 70, 34 }, "Ball"),
		P("TipR", { 0.48, 0.3, 0 }, { 0.3, 0.3, 0.3 }, { 128, 70, 34 }, "Ball"),
		P("Laces", { 0, 0.585, 0 }, { 0.4, 0.03, 0.08 }, { 250, 250, 250 }),
	},
	bubbles = {
		P("Bottle", { 0, 0.3, 0 }, { 0.6, 0.35, 0.35 }, { 80, 200, 240 }, "Cylinder", UP, "Glass"),
		P("Cap", { 0, 0.66, 0 }, { 0.12, 0.25, 0.25 }, { 255, 90, 170 }, "Cylinder", UP),
		P("Wand", { 0.1, 0.85, 0 }, { 0.04, 0.3, 0.04 }, { 255, 90, 170 }),
	},
	chalk = {
		P("Box", { 0, 0.18, 0 }, { 0.9, 0.36, 0.35 }, { 250, 220, 60 }),
		P("Pink", { -0.25, 0.42, 0 }, { 0.15, 0.3, 0.15 }, { 255, 150, 190 }, "Cylinder", UP),
		P("Blue", { 0, 0.42, 0 }, { 0.15, 0.3, 0.15 }, { 130, 190, 255 }, "Cylinder", UP),
		P("Green", { 0.25, 0.42, 0 }, { 0.15, 0.3, 0.15 }, { 150, 230, 150 }, "Cylinder", UP),
	},
	flashlight = {
		P("Barrel", { 0, 0.4, 0 }, { 0.8, 0.22, 0.22 }, { 30, 30, 34 }, "Cylinder", UP),
		P("Head", { 0, 0.88, 0 }, { 0.2, 0.32, 0.32 }, { 250, 200, 40 }, "Cylinder", UP),
		P("Lens", { 0, 0.99, 0 }, { 0.02, 0.26, 0.26 }, { 255, 250, 220 }, "Cylinder", UP, "Glass"),
	},
	umbrella = {
		P("Shaft", { 0, 1.5, 0 }, { 2.6, 0.08, 0.08 }, { 60, 60, 64 }, "Cylinder", UP, "Metal"),
		P("Canopy", { 0, 1.7, 0 }, { 1.9, 0.3, 0.3 }, { 30, 70, 160 }, "Cylinder", UP, "Fabric"),
		P("Handle", { 0.1, 0.12, 0 }, { 0.3, 0.12, 0.12 }, { 90, 56, 30 }, nil, nil, "Wood"),
	},
	peanuts = {
		P("Bag", { 0, 0.45, 0 }, { 0.7, 0.9, 0.28 }, { 200, 40, 40 }, nil, nil, "Plastic"),
		P("Label", { 0, 0.5, -0.145 }, { 0.5, 0.35, 0.01 }, { 214, 170, 110 }),
	},
	bird_seed = {
		P("Sack", { 0, 0.8, 0 }, { 1.2, 1.6, 0.6 }, { 214, 190, 140 }, nil, nil, "Fabric"),
		P("Bird", { 0, 1.0, -0.305 }, { 0.5, 0.4, 0.01 }, { 60, 120, 200 }),
		P("Fold", { 0, 1.62, 0 }, { 1.1, 0.06, 0.5 }, { 180, 150, 100 }, nil, nil, "Fabric"),
	},
	dog_treats = {
		P("Box", { 0, 0.5, 0 }, { 0.8, 1.0, 0.35 }, { 250, 160, 30 }),
		P("Bone", { 0, 0.6, -0.18 }, { 0.5, 0.15, 0.01 }, { 250, 248, 240 }),
	},
	newspaper = {
		P("Paper", { 0, 0.1, 0 }, { 1.2, 0.2, 0.8 }, { 236, 232, 222 }),
		P("Masthead", { 0, 0.205, -0.25 }, { 1.0, 0.01, 0.15 }, { 40, 40, 40 }),
	},
	camera = {
		P("Body", { 0, 0.2, 0 }, { 0.6, 0.4, 0.25 }, { 250, 210, 30 }, nil, nil, "Plastic"),
		P("Lens", { 0.1, 0.2, -0.15 }, { 0.08, 0.18, 0.18 }, { 30, 30, 34 }, "Cylinder", ALONG_D),
	},
	duct_tape = {
		P("Roll", { 0, 0.15, 0 }, { 0.3, 0.7, 0.7 }, { 170, 172, 178 }, "Cylinder", UP, "Fabric"),
		P("Core", { 0, 0.15, 0 }, { 0.31, 0.35, 0.35 }, { 120, 90, 60 }, "Cylinder", UP),
	},
	whoopee_cushion = {
		P("Cushion", { 0, 0.14, 0 }, { 0.28, 1.0, 1.0 }, { 255, 120, 160 }, "Cylinder", UP, "Plastic"),
		P("Neck", { 0, 0.12, -0.6 }, { 0.12, 0.25, 0.3 }, { 255, 120, 160 }),
	},
	harmonica = {
		P("Cover", { 0, 0.1, 0 }, { 0.8, 0.2, 0.3 }, { 200, 202, 208 }, nil, nil, "Metal"),
		P("Comb", { 0, 0.1, -0.15 }, { 0.75, 0.08, 0.02 }, { 40, 30, 26 }),
	},
	air_horn = {
		P("Can", { 0, 0.35, 0 }, { 0.7, 0.36, 0.36 }, { 220, 40, 40 }, "Cylinder", UP),
		P("Horn", { 0, 0.88, 0 }, { 0.4, 0.22, 0.22 }, { 250, 250, 250 }, "Cylinder", UP, "Plastic"),
	},
	soda = {
		P("Bottle", { 0, 0.45, 0 }, { 0.9, 0.36, 0.36 }, { 120, 40, 30 }, "Cylinder", UP, "Glass"),
		P("Neck", { 0, 1.0, 0 }, { 0.3, 0.16, 0.16 }, { 120, 40, 30 }, "Cylinder", UP, "Glass"),
		P("Label", { 0, 0.5, 0 }, { 0.3, 0.38, 0.38 }, { 230, 40, 40 }, "Cylinder", UP),
	},
	ice_cream_bar = {
		P("Wrapper", { 0, 0.1, 0 }, { 0.5, 0.2, 0.9 }, { 250, 250, 250 }, nil, nil, "Plastic"),
		P("Stripe", { 0, 0.205, 0 }, { 0.5, 0.01, 0.3 }, { 60, 120, 220 }),
	},
	lawn_chair = {
		P("Seat", { 0, 1.0, 0 }, { 1.8, 0.1, 1.6 }, { 60, 150, 90 }, nil, nil, "Fabric"),
		P("Back", { 0, 1.9, 0.85 }, { 1.8, 1.8, 0.1 }, { 250, 200, 60 }, nil, { 0.25, 0, 0 }, "Fabric"),
		P("LegL", { -0.9, 0.5, 0 }, { 0.08, 1.0, 1.6 }, { 200, 202, 208 }, nil, nil, "Metal"),
		P("LegR", { 0.9, 0.5, 0 }, { 0.08, 1.0, 1.6 }, { 200, 202, 208 }, nil, nil, "Metal"),
	},
	radio = {
		P("Case", { 0, 0.5, 0 }, { 1.2, 1.0, 0.45 }, { 160, 40, 36 }, nil, nil, "Plastic"),
		P("Grille", { -0.2, 0.5, -0.23 }, { 0.6, 0.6, 0.01 }, { 200, 190, 170 }, nil, nil, "Metal"),
		P("Dial", { 0.38, 0.55, -0.24 }, { 0.04, 0.3, 0.3 }, { 240, 230, 200 }, "Cylinder", ALONG_D),
		P("Aerial", { 0.45, 1.4, 0 }, { 0.04, 0.9, 0.04 }, { 200, 202, 208 }, nil, nil, "Metal"),
	},
	bike_horn = {
		P("Bulb", { 0, 0.25, 0.25 }, { 0.5, 0.5, 0.5 }, { 30, 30, 34 }, "Ball", nil, "Rubber"),
		P("Horn", { 0, 0.25, -0.2 }, { 0.6, 0.22, 0.22 }, { 220, 180, 60 }, "Cylinder", ALONG_D, "Metal"),
	},
	kite = {
		P("Sail", { 0, 2.2, 0 }, { 1.6, 1.6, 0.05 }, { 230, 50, 50 }, nil, { 0, 0, math.pi / 4 }, "Fabric"),
		P("Spar", { 0, 2.2, -0.04 }, { 0.05, 2.3, 0.04 }, { 140, 100, 60 }, nil, nil, "Wood"),
		P("Tail", { 0, 0.6, 0 }, { 0.05, 1.2, 0.03 }, { 250, 220, 50 }),
	},
}

function Stock.build(kit: Kit.Kit, parent: any, id: string, x: number, y: number, d: number, yaw: number): any
	local pieces = MODELS[id]
	assert(pieces, "no model for " .. id)
	local r = kit.roblox
	local m = kit:model(parent, id)
	local turn = r.CFrame.Angles(0, yaw, 0)
	for _, p in pieces do
		-- the offset turned by the yaw (the Kit's local frame is Roblox's at yaw 0: Z = -D)
		local o = turn * r.Vector3.new(p.at[1], p.at[2], -p.at[3])
		local rot = turn
		if p.rot then
			rot = turn * r.CFrame.Angles(p.rot[1], p.rot[2], p.rot[3])
		end
		local opts = table.clone(VISUAL) :: Kit.Opts
		opts.rot = rot
		opts.shape = p.shape
		local part = kit:at(
			m,
			p.name,
			x + o.X,
			y + o.Y,
			d - o.Z,
			p.size[1],
			p.size[2],
			p.size[3],
			p.color,
			p.material or "SmoothPlastic",
			opts
		)
		if m.PrimaryPart == nil then
			m.PrimaryPart = part
		end
	end
	return m
end

return Stock
