--!strict
-- ServerScriptService.Server.WorldGen.Builders.Fixtures
-- Small structures that were still drawn as one bare box (owner 2026-11-11: "clean up a few things on
-- the map"): the two pergolas, the doghouses, the Quay market stalls, the park gazebo, the clock tower,
-- the radio mast and the cell tower. Each keeps its lot's single block as its first part (the lot's
-- PrimaryPart and the reference other checks use), reshaped into the piece of the structure that stands
-- where it stood (a paving pad, the kennel's walls, a counter, a floor, a shaft, a base, a pole), and
-- gets the rest added in the lot's own frame (X across the front, Y up from the seat, front at -Z).
-- Interface: dress(lot, body, list, frame) -> boolean (true when the lot's type is one of these). Pure.

local Geometry = require("../Geometry")
local Spec = require("../Spec")

local Fixtures = {}

local WOOD = { 140, 104, 70 }
local WOOD_DARK = { 104, 76, 52 }
local STONE = { 176, 170, 158 }
local SLATE = { 74, 80, 88 }
local STEEL = { 150, 156, 160 }
local DARK = { 34, 28, 24 }
local AWNINGS = { { 196, 62, 54 }, { 52, 110, 160 }, { 214, 170, 60 }, { 70, 140, 96 }, { 150, 80, 150 } }

-- The block becomes a low or narrow piece standing on the seat at the lot's centre.
local function reshape(body: Spec.PartSpec, seat: number, sx: number, sy: number, sz: number)
	body.sx, body.sy, body.sz = sx, sy, sz
	body.cy = seat + sy / 2
end

local function pergola(body: Spec.PartSpec, list: Spec.PartList, f: Geometry.Frame, W: number, H: number, D: number)
	reshape(body, f.cy, W, 0.3, D) -- the paved floor
	body.color, body.material = STONE, "Slate"
	local px, pz = W / 2 - 1, D / 2 - 1
	local n = 0
	for _, x in { -px, px } do
		for _, z in { -pz, 0, pz } do
			n += 1
			list:add(f, `Post{n}`, x, H / 2, z, 0.8, H, 0.8, { color = WOOD, material = "WoodPlanks", role = "Post" })
		end
		list:add(
			f,
			`Beam{n}`,
			x,
			H + 0.3,
			0,
			0.8,
			0.6,
			D,
			{ color = WOOD_DARK, material = "WoodPlanks", role = "Trim" }
		)
	end
	for i = 1, 7 do
		local z = -pz + (i - 1) * (2 * pz / 6)
		list:add(
			f,
			`Slat{i}`,
			0,
			H + 0.75,
			z,
			W + 1.5,
			0.3,
			0.5,
			{ color = WOOD, material = "WoodPlanks", canCollide = false, role = "Trim" }
		)
	end
	-- the summer kitchen: a stone counter along the back
	list:add(
		f,
		"Counter",
		0,
		1.6,
		pz - 1.2,
		W * 0.5,
		3.2,
		2.4,
		{ color = STONE, material = "Slate", role = "Furniture" }
	)
end

local function doghouse(body: Spec.PartSpec, list: Spec.PartList, f: Geometry.Frame, W: number, H: number, D: number)
	local wall = H * 0.7
	reshape(body, f.cy, W, wall, D)
	body.color, body.material = WOOD, "WoodPlanks"
	-- a gable: two boards leaning to a ridge that runs front to back
	local half = W / 2 + 0.6
	local rise = H * 0.55
	local board = math.sqrt(half * half + rise * rise)
	local lean = math.atan2(rise, half)
	for side, sign in { 1, -1 } do
		list:add(
			f,
			`Roof{side}`,
			sign * half / 2,
			wall + rise / 2,
			0,
			board,
			0.3,
			D + 1,
			{ color = WOOD_DARK, material = "WoodPlanks", roll = -sign * lean, role = "Roof" }
		)
	end
	list:add(
		f,
		"Doorway",
		0,
		wall * 0.42,
		-D / 2 - 0.06,
		W * 0.42,
		wall * 0.84,
		0.1,
		{ color = DARK, canCollide = false, role = "Trim" }
	)
end

local function stall(
	lot: any,
	body: Spec.PartSpec,
	list: Spec.PartList,
	f: Geometry.Frame,
	W: number,
	H: number,
	D: number
)
	reshape(body, f.cy, W, 3.2, D * 0.55) -- the counter
	body.color, body.material = WOOD, "WoodPlanks"
	local px, pz = W / 2 - 0.3, D / 2 - 0.3
	local n = 0
	for _, x in { -px, px } do
		for _, z in { -pz, pz } do
			n += 1
			list:add(
				f,
				`Post{n}`,
				x,
				H / 2,
				z,
				0.4,
				H,
				0.4,
				{ color = WOOD_DARK, material = "WoodPlanks", role = "Post" }
			)
		end
	end
	local cloth = AWNINGS[(#lot.id + (string.byte(lot.id, #lot.id) or 0)) % #AWNINGS + 1]
	list:add(
		f,
		"Awning",
		0,
		H + 0.1,
		-0.4,
		W + 1.6,
		0.25,
		D + 2,
		{ color = cloth, material = "Fabric", pitch = 0.1, canCollide = false, role = "Trim" }
	)
	list:add(
		f,
		"Goods",
		0,
		3.2 + 0.45,
		0,
		W * 0.7,
		0.9,
		D * 0.3,
		{ color = { 205, 150, 70 }, material = "Fabric", canCollide = false, role = "Furniture" }
	)
end

local function gazebo(body: Spec.PartSpec, list: Spec.PartList, f: Geometry.Frame, W: number, H: number, D: number)
	reshape(body, f.cy, W, 0.8, D) -- the floor
	body.color, body.material = WOOD, "WoodPlanks"
	local r = math.min(W, D) / 2 - 1.5
	for i = 1, 8 do
		local a = (i - 0.5) * math.pi / 4
		list:add(
			f,
			`Post{i}`,
			r * math.cos(a),
			0.8 + (H - 0.8) / 2,
			r * math.sin(a),
			0.9,
			H - 0.8,
			0.9,
			{ color = { 236, 232, 222 }, material = "WoodPlanks", role = "Post" }
		)
	end
	-- the roof: two eaves a quarter turn apart make eight corners, then it steps in to a cap
	local tiles = { color = SLATE, material = "Slate", role = "Roof" }
	list:add(f, "Eave1", 0, H + 0.3, 0, W * 0.78, 0.6, D * 0.78, tiles)
	list:add(f, "Eave2", 0, H + 0.3, 0, W * 0.78, 0.6, D * 0.78, {
		color = SLATE,
		material = "Slate",
		role = "Roof",
		yaw = math.pi / 4,
	})
	list:add(f, "Roof2", 0, H + 1.5, 0, W * 0.6, 1.8, D * 0.6, tiles)
	list:add(f, "Roof3", 0, H + 3.3, 0, W * 0.34, 1.8, D * 0.34, {
		color = SLATE,
		material = "Slate",
		role = "Roof",
		yaw = math.pi / 4,
	})
	list:add(
		f,
		"Finial",
		0,
		H + 5,
		0,
		0.8,
		1.6,
		0.8,
		{ color = { 214, 190, 110 }, material = "Metal", canCollide = false }
	)
end

local function clockTower(body: Spec.PartSpec, list: Spec.PartList, f: Geometry.Frame, W: number, H: number, D: number)
	body.material = "Brick"
	local trim = { color = STONE, material = "Slate", canCollide = false, role = "Trim" }
	list:add(f, "Plinth", 0, 3, 0, W + 4, 6, D + 4, { color = STONE, material = "Slate", role = "Body" })
	list:add(f, "Cornice", 0, H - 1.5, 0, W + 3, 2, D + 3, trim)
	local face = math.min(W, D) * 0.55
	local y = H * 0.8
	local white = { color = { 244, 240, 228 }, canCollide = false, role = "Trim" }
	list:add(f, "ClockFront", 0, y, -D / 2 - 0.16, face, face, 0.3, white)
	list:add(f, "ClockBack", 0, y, D / 2 + 0.16, face, face, 0.3, white)
	list:add(f, "ClockLeft", -W / 2 - 0.16, y, 0, 0.3, face, face, white)
	list:add(f, "ClockRight", W / 2 + 0.16, y, 0, 0.3, face, face, white)
	-- the hands, at ten past ten on every face
	local hand = { color = DARK, canCollide = false, role = "Trim" }
	local long, short = face * 0.4, face * 0.28
	for i, side in { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
		local ox, oz = side[1] * (W / 2 + 0.34), side[2] * (D / 2 + 0.34)
		local alongX = side[1] == 0
		for j, h in { { long, 0.35 }, { short, -1.05 } } do
			local len, turn = h[1], h[2]
			local dx = math.sin(turn) * len / 2
			local dy = math.cos(turn) * len / 2
			list:add(
				f,
				`Hand{i}_{j}`,
				ox + (if alongX then dx else 0),
				y + dy,
				oz + (if alongX then 0 else dx),
				if alongX then 0.5 else 0.12,
				len,
				if alongX then 0.12 else 0.5,
				{
					color = hand.color,
					canCollide = false,
					role = "Trim",
					roll = if alongX then -turn else nil,
					pitch = if alongX then nil else turn,
				}
			)
		end
	end
	local roof = { color = SLATE, material = "Slate", role = "Roof" }
	list:add(f, "Roof1", 0, H + 2, 0, W - 2, 4, D - 2, roof)
	list:add(f, "Roof2", 0, H + 6.5, 0, W * 0.6, 5, D * 0.6, roof)
	list:add(f, "Roof3", 0, H + 12, 0, W * 0.25, 6, D * 0.25, roof)
end

local function radioMast(body: Spec.PartSpec, list: Spec.PartList, f: Geometry.Frame, W: number, H: number, D: number)
	-- the block is the mast's slim core, full height (the far skyline is drawn from a lot's first part);
	-- wider sleeves stand round it lower down, in the red and white of a real mast
	reshape(body, f.cy, 3, H, 3)
	body.color, body.material = { 236, 234, 228 }, "Metal"
	list:add(f, "Pad", 0, 1, 0, W, 2, D, { color = STONE, material = "Concrete", role = "Body" })
	local widths = { 10, 7.5, 5 }
	local each = (H - 2) / 4
	for i, w in widths do
		list:add(f, `Mast{i}`, 0, 2 + (i - 0.5) * each, 0, w, each, w, {
			color = if i % 2 == 1 then { 190, 58, 48 } else { 236, 234, 228 },
			material = "Metal",
			role = "Body",
		})
	end
	list:add(f, "Band", 0, H - each / 2, 0, 3.3, each * 0.5, 3.3, {
		color = { 190, 58, 48 },
		material = "Metal",
		canCollide = false,
		role = "Trim",
	})
	list:add(
		f,
		"Aerial",
		0,
		H + H * 0.1,
		0,
		0.6,
		H * 0.2,
		0.6,
		{ color = STEEL, material = "Metal", canCollide = false }
	)
	list:add(f, "Beacon", 0, H + H * 0.2 + 0.8, 0, 1.6, 1.6, 1.6, {
		color = { 255, 60, 40 },
		material = "Neon",
		shape = "Ball",
		canCollide = false,
	})
end

local function cellTower(body: Spec.PartSpec, list: Spec.PartList, f: Geometry.Frame, W: number, H: number, D: number)
	reshape(body, f.cy, 2.2, H, 2.2) -- the pole
	body.color, body.material = STEEL, "Metal"
	list:add(f, "Platform", 0, H - 9, 0, 5.5, 0.4, 5.5, { color = STEEL, material = "Metal", canCollide = false })
	for i = 1, 3 do
		local a = i * 2 * math.pi / 3
		list:add(f, `Panel{i}`, 2.6 * math.sin(a), H - 5, 2.6 * math.cos(a), 2.2, 7, 0.8, {
			color = { 232, 232, 228 },
			material = "Metal",
			yaw = a,
			canCollide = false,
		})
	end
	list:add(f, "Cabinet", W / 2 - 1.5, 2.5, D / 2 - 1.5, 3, 5, 3, { color = { 150, 162, 150 }, material = "Metal" })
end

-- Dresses one of the fixture lots; false for any other lot (it stays the block it was).
function Fixtures.dress(lot: any, body: Spec.PartSpec, list: Spec.PartList, frame: Geometry.Frame): boolean
	local t = lot.type
	local W, H, D = body.sx, body.sy, body.sz
	if t == "pergola_summer_kitchen" then
		pergola(body, list, frame, W, H, D)
	elseif t == "doghouse" or t == "backyard_doghouse" then
		doghouse(body, list, frame, W, H, D)
	elseif t == "market_stall" then
		stall(lot, body, list, frame, W, H, D)
	elseif t == "gazebo" then
		gazebo(body, list, frame, W, H, D)
	elseif t == "landmark_tower" then
		if string.find(lot.id, "clock", 1, true) then
			clockTower(body, list, frame, W, H, D)
		elseif W >= 20 then
			radioMast(body, list, frame, W, H, D)
		else
			cellTower(body, list, frame, W, H, D)
		end
	else
		return false
	end
	return true
end

return Fixtures
