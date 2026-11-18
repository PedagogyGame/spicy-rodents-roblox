--!strict
-- tools/bake/sewers/Shaft: a mouth's shaft (Shared/World/SewerLayout Mouth.shaft: a square well `inside` across,
-- walls `wall` thick, square to the world; iron rungs on the `rungs` wall, the route `rungGap` off it).
--   walls(kit, parent, mouth, top)   the four walls, from the shaft chamber's roof (the walkway at the shaft's foot
--        plus Section.ROOF) up to `top` (the underside of the mouth's frame or cover)
--   roof(kit, parent, mouth, section)   the shaft chamber's flat roof: four slabs square to the shaft round its hole,
--        reaching ROOF_REACH out (over the chamber, and harmlessly over the vault next to it and the void outside),
--        from Section.ROOF to Section.TOP over the walkway
--   ladder(kit, parent, mouth, top)   the iron ladder on the rungs wall up to the street: two rails and rungs every
--        RUNG_STEP (the squirrel climbs it: its belly 0.4 from the wall, the rungs 0.21 at most). It stops
--        LADDER_FOOT over the walkway, as a sewer ladder does: the body turning off it at the foot is that tall.
-- All in world coordinates (the shaft is square to the world).

local Kit = require("./Kit")
local Section = require("./Section")

local Shaft = {}

Shaft.ROOF_REACH = 7.0 -- studs from the shaft's centre each roof slab reaches
Shaft.RUNG_STEP = 1.6 -- studs between rungs
Shaft.RUNG_WIDTH = 0.9
Shaft.RUNG_OFF = 0.16 -- studs from the wall face to the rung's axis
Shaft.RAIL_OFF = 0.11
Shaft.LADDER_FOOT = 1.85 -- studs over the walkway

local function box(
	kit: Kit.Kit,
	parent: any,
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
	c: { number },
	m: string,
	o: Kit.Opts?
)
	local CF = kit.roblox.CFrame
	return kit:at(
		parent,
		name,
		CF.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
		{ x1 - x0, y1 - y0, z1 - z0 },
		c,
		m,
		o
	)
end

function Shaft.walls(kit: Kit.Kit, parent: any, mouth: any, top: number, section: any)
	local sh = mouth.shaft
	local h, t = sh.inside / 2, sh.wall
	local y0 = sh.bottom + Section.ROOF
	local c, m = (Section.PALETTE :: any).brick[1], (Section.PALETTE :: any).brick[2]
	if section.kind == "dry" then
		c, m = (Section.PALETTE :: any).dry[1], (Section.PALETTE :: any).dry[2]
	end
	local cx, cz = sh.cx, sh.cz
	box(kit, parent, "ShaftWall", cx + h, cx + h + t, y0, top, cz - h - t, cz + h + t, c, m)
	box(kit, parent, "ShaftWall", cx - h - t, cx - h, y0, top, cz - h - t, cz + h + t, c, m)
	box(kit, parent, "ShaftWall", cx - h, cx + h, y0, top, cz + h, cz + h + t, c, m)
	box(kit, parent, "ShaftWall", cx - h, cx + h, y0, top, cz - h - t, cz - h, c, m)
end

function Shaft.roof(kit: Kit.Kit, parent: any, mouth: any, section: any)
	local sh = mouth.shaft
	local h, R = sh.inside / 2, Shaft.ROOF_REACH
	local y0, y1 = sh.bottom + Section.ROOF, sh.bottom + Section.TOP
	local c, m = (Section.PALETTE :: any).brick[1], (Section.PALETTE :: any).brick[2]
	if section.kind == "dry" then
		c, m = (Section.PALETTE :: any).dry[1], (Section.PALETTE :: any).dry[2]
	end
	local cx, cz = sh.cx, sh.cz
	box(kit, parent, "ChamberRoof", cx - R, cx + R, y0, y1, cz + h, cz + R, c, m)
	box(kit, parent, "ChamberRoof", cx - R, cx + R, y0, y1, cz - R, cz - h, c, m)
	box(kit, parent, "ChamberRoof", cx + h, cx + R, y0, y1, cz - h, cz + h, c, m)
	box(kit, parent, "ChamberRoof", cx - R, cx - h, y0, y1, cz - h, cz + h, c, m)
end

function Shaft.ladder(kit: Kit.Kit, parent: any, mouth: any, top: number)
	local sh = mouth.shaft
	local V, CF = kit.roblox.Vector3, kit.roblox.CFrame
	local h = sh.inside / 2
	local nx, nz = sh.rungs.x, sh.rungs.z -- from the centre toward the rungs wall
	local lx, lz = -nz, nx -- along the wall
	-- the ladder's centre line: the route's line on the wall (the mouth point's lateral position)
	local along = (mouth.x - sh.cx) * lx + (mouth.z - sh.cz) * lz
	local ic, im = (Section.PALETTE :: any).iron[1], (Section.PALETTE :: any).iron[2]
	local function point(off: number, lat: number, y: number): any
		local d = h - off
		return V.new(sh.cx + nx * d + lx * (along + lat), y, sh.cz + nz * d + lz * (along + lat))
	end
	local y0, y1 = sh.bottom + Shaft.LADDER_FOOT, top - 0.05
	for _, lat in { -Shaft.RUNG_WIDTH / 2, Shaft.RUNG_WIDTH / 2 } do
		local p = point(Shaft.RAIL_OFF, lat, (y0 + y1) / 2)
		kit:at(parent, "LadderRail", CF.new(p), { 0.07, y1 - y0, 0.07 }, ic, im)
	end
	local y = y0 + 0.2
	while y < y1 - 0.3 do
		local a, b = point(Shaft.RUNG_OFF, -Shaft.RUNG_WIDTH / 2, y), point(Shaft.RUNG_OFF, Shaft.RUNG_WIDTH / 2, y)
		local cf = CF.lookAt((a + b) / 2, b) * CF.Angles(0, math.pi / 2, 0)
		kit:at(parent, "Rung", cf, { Shaft.RUNG_WIDTH, 0.09, 0.09 }, ic, im, { shape = "Cylinder" })
		y += Shaft.RUNG_STEP
	end
end

return Shaft
