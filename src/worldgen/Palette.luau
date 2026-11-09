--!strict
-- ServerScriptService.Server.WorldGen.Palette
-- The v5.4 look per lot (FRB look pass): wall, roof, trim, door, window and accent colours plus
-- materials, read from the lot's `style` text (labelled "wall #.." / "roof #.." / "cap #.." hexes, else
-- the first hex is the wall) and the v5.4 tables in docs/spec/worldgen_core.md §5.1 (core houses), §6.1
-- (outer homes) and worldgen_districts_art.md §3.4 (quay plaster/roof/fascia), §11 (materials and
-- district palettes). Unknown lots fall back to the muted v5.4 town palette (§11 statistics).
-- Interface: hex(s) -> {r,g,b}; hexes(text) -> { {r,g,b} }; forLot(lot, kit) -> Look;
--   plate(lotType, style) -> (color, material, transparency); LEAVES; ROAD
-- Pure: no Instances, no side effects on require.

local Palette = {}

export type Rgb = { number }
export type Look = {
	wall: Rgb,
	roof: Rgb,
	trim: Rgb,
	door: Rgb,
	window: Rgb,
	accent: Rgb,
	material: string,
	roofMaterial: string,
	timber: boolean, -- Tudor half-timber bands (quay)
	chimney: boolean,
}

function Palette.hex(s: string): Rgb
	local h = string.gsub(s, "#", "")
	return {
		tonumber(string.sub(h, 1, 2), 16) or 200,
		tonumber(string.sub(h, 3, 4), 16) or 200,
		tonumber(string.sub(h, 5, 6), 16) or 200,
	}
end
local hex = Palette.hex

function Palette.hexes(text: string?): { Rgb }
	local out: { Rgb } = {}
	for h in string.gmatch(text or "", "#(%x%x%x%x%x%x)") do
		table.insert(out, hex(h))
	end
	return out
end

-- "<label> #rrggbb" anywhere in the text (labels: wall, roof, cap, trim, ...).
local function labelled(text: string, label: string): Rgb?
	local h = string.match(text, label .. "%s*#(%x%x%x%x%x%x)")
	return if h then hex(h) else nil
end

local function list(hs: { string }): { Rgb }
	local out = {}
	for _, h in hs do
		table.insert(out, hex(h))
	end
	return out
end

-- worldgen_core §5.1: core houses wall / trim / roof, door odd #597e77, even #5b4239.
local CORE = {
	["core_house_0_victorian"] = list({ "#ded7b7", "#f5ecd5", "#63524c", "#5b4239" }),
	["core_house_1_bungalow"] = list({ "#b6c1b1", "#f2ecdf", "#686a60", "#597e77" }),
	["core_house_2_brick"] = list({ "#bb8e71", "#e4d6c5", "#615653", "#5b4239" }),
	["core_house_3_blue_cottage"] = list({ "#aebbc4", "#f4e8cf", "#6f6f75", "#597e77" }),
}
-- worldgen_core §6.1: outer homes.
local OUTER_WALL = list({ "#c1b5a2", "#b7c5c1", "#d4b998", "#a69f8b", "#dfd6ba", "#a6b5ac" })
local OUTER_ROOF = list({ "#5e5d5d", "#71625c", "#5d6b65", "#755a50" })
local OUTER_DOOR = list({ "#4b6d61", "#6e5144", "#3d5e78", "#a3835b" })
-- worldgen_districts_art §3.4: quay townhouses.
local QUAY_PLASTER = list({ "#d8c6a1", "#c0b9a0", "#d7b399", "#b9c2b0", "#c9bda7" })
local QUAY_ROOF = list({ "#6e635a", "#505e63", "#71695b", "#72615b" })
-- fallback walls for buildings without colour data (muted, earthy: §11 statistics)
local GENERIC_WALL = list({ "#d8cdb4", "#c9bda7", "#b9c2b0", "#d4b998", "#c1b5a2", "#dfd6ba" })
local GENERIC_ROOF = list({ "#5e5d5d", "#6e635a", "#505e63", "#755a50" })

local TRIM = hex("#efecdc")
local GLASS = hex("#5f7f86") -- v5.4 glass #8db9bf seen against interiors: darker so windows read
local OAK = hex("#4e4136")

-- A stable small integer from the lot id's trailing digits (v5.4 used the build index).
local function index(id: string): number
	local digits = string.match(id, "(%d+)$") or string.match(id, "_(%d+)_") or "0"
	local n = tonumber(digits) or 0
	-- the quay rows restart at 0: offset by row so neighbours differ
	if string.find(id, "quay_bldg_m_", 1, true) then
		n += 2
	elseif string.find(id, "quay_bldg_e_", 1, true) then
		n += 3
	end
	return n
end

local function at(t: { Rgb }, i: number): Rgb
	return t[(i % #t) + 1]
end

local function hashIndex(s: string): number
	local h = 0
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 65521
	end
	return h
end

function Palette.forLot(lot: any, kit: any): Look
	local id: string = lot.id or ""
	local style: string = lot.style or ""
	local t: string = lot.type or ""
	local i = index(id)
	local look: Look = {
		wall = at(GENERIC_WALL, hashIndex(id)),
		roof = at(GENERIC_ROOF, hashIndex(id) // 7),
		trim = TRIM,
		door = at(OUTER_DOOR, i),
		window = GLASS,
		accent = hex("#405b51"),
		material = "SmoothPlastic",
		roofMaterial = "Slate",
		timber = false,
		chimney = false,
	}
	local core = CORE[id]
	if core then
		look.wall, look.trim, look.roof, look.door = core[1], core[2], core[3], core[4]
		look.material = if id == "core_house_2_brick" then "Brick" else "WoodPlanks"
		look.chimney = id ~= "core_house_1_bungalow"
		return look
	end
	if string.find(id, "outer_home_", 1, true) then
		look.wall, look.roof, look.door = at(OUTER_WALL, i), at(OUTER_ROOF, i), at(OUTER_DOOR, i)
		look.material = "WoodPlanks"
		look.chimney = i % 3 ~= 1
		return look
	end
	if t == "quay_building" then
		look.wall, look.roof = at(QUAY_PLASTER, i), at(QUAY_ROOF, i)
		look.accent = if i % 2 == 1 then hex("#405b51") else hex("#745547")
		look.door = hex("#75604b")
		look.material = "Plaster"
		look.timber = true
		look.chimney = true
		return look
	end
	if t == "mall" then
		look.wall, look.trim, look.window = hex("#ded2ba"), hex("#f0e4cb"), hex("#477b88")
		look.roof, look.accent, look.door = hex("#aaa697"), hex("#344c49"), hex("#b69a53")
		look.material, look.roofMaterial = "Limestone", "Concrete"
		return look
	end
	if t == "hospital" then
		look.wall, look.roof, look.accent = hex("#e6e5db"), hex("#718c90"), hex("#628e9d")
		look.window, look.material, look.roofMaterial = hex("#628e9d"), "SmoothPlastic", "Concrete"
		return look
	end
	-- labelled colours, then the first hex as the wall
	local hs = Palette.hexes(style)
	local wall = labelled(style, "wall") or labelled(style, "shop") or hs[1]
	local roof = labelled(style, "roof") or labelled(style, "cap") or labelled(style, "canopy")
	if wall then
		look.wall = wall
	end
	if roof then
		look.roof = roof
	elseif hs[2] then
		look.accent = hs[2]
	end
	if string.find(string.lower(style), "brick", 1, true) then
		look.material = "Brick"
	elseif kit and kit.category == "building" then
		look.material = "Plaster"
	end
	if t == "house" or t == "guesthouse" then
		look.material = if look.material == "Brick" then "Brick" else "WoodPlanks"
	end
	return look
end

-- Ground plates (lawns, plazas, pools, courts): colour, material, transparency.
local GRASS = hex("#819762")
function Palette.plate(lotType: string, style: string?): (Rgb, string, number)
	local s = style or ""
	local hs = Palette.hexes(s)
	if lotType == "estate_pool" or lotType == "backyard_pool" then
		return hex("#63c3d0"), "Glass", 0.15
	elseif lotType == "river" or lotType == "stream" or lotType == "pond" then
		return hex("#4f9fae"), "Glass", 0.25
	elseif lotType == "tennis_court" then
		return hs[1] or hex("#476c59"), "Concrete", 0
	elseif lotType == "parking" or lotType == "intersection" or lotType == "ambulance_bay" then
		return hex("#4b5153"), "Asphalt", 0
	elseif lotType == "plaza" or lotType == "bridge" then
		return hex("#d1c7ae"), "Limestone", 0
	elseif lotType == "district_ground" or lotType == "path" then
		return hex("#c4bdab"), "Cobblestone", 0
	elseif lotType == "sports_field" or lotType == "community_garden" or lotType == "garden" then
		return hs[1] or hex("#7a5132"), "Ground", 0
	elseif lotType == "playground" then
		return hex("#d9c9a0"), "Sand", 0
	end
	return GRASS, "Grass", 0
end

-- v5.4 leaf greens (makeTree QUAY WILLOW, Treehouse Oak; worldgen_districts_art §3.7, §6).
Palette.LEAVES = list({ "#769377", "#6a8c3e", "#95a580", "#586f5b", "#89ab55", "#7d9a4f" })
Palette.BARK = hex("#655342")

-- Road surfaces (§11: asphalt #40484a under the #929493 tint, sidewalk concrete #c3beb1).
Palette.ROAD = {
	asphalt = hex("#4b5153"),
	concrete = hex("#c3beb1"),
	cobble = hex("#c4bdab"),
	path = hex("#b5a888"),
	rail = hex("#5a5650"),
	paint = hex("#ece6cf"),
	curb = hex("#aaa79c"),
}

Palette.OAK = OAK

return Palette
