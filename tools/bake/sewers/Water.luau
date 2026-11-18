--!strict
-- tools/bake/sewers/Water: the water in the storm drains (mild: clear grey-green, a trickle; brief v2 decision 24).
-- Static parts: the client lane (S3) scrolls nothing on them yet. Never collides, never queried.
-- Interface: channel(kit, parent, frame, z0, z1, section); sump(kit, parent, frame, half, top); fall(kit, parent,
--   frame, x, y0, y1, z, width); Water.COLOUR

local Kit = require("./Kit")

local Water = {}

Water.COLOUR = { 78, 104, 96 }
Water.MATERIAL = "SmoothPlastic"
local OPTS: Kit.Opts = { visual = true, transparency = 0.22, reflectance = 0.18, shadow = false }

-- the channel between the walkways, its surface at the section's water level (studs under the walkway top)
function Water.channel(kit: Kit.Kit, parent: any, frame: any, z0: number, z1: number, section: any): any?
	if section.water == nil then
		return nil
	end
	local top = section.water
	local half = section.walkway[1] - 0.02
	return kit:box(parent, "Water", frame, -half, half, top - 0.1, top, z0, z1, Water.COLOUR, Water.MATERIAL, OPTS)
end

-- the still water in the junction's sump, under its grate
function Water.sump(kit: Kit.Kit, parent: any, frame: any, half: number, top: number): any
	return kit:box(parent, "Water", frame, -half, half, top - 0.1, top, -half, half, Water.COLOUR, Water.MATERIAL, OPTS)
end

-- a thin fall of water from an outlet into the channel (frame-local x, from y1 down to y0, at z)
function Water.fall(
	kit: Kit.Kit,
	parent: any,
	frame: any,
	x: number,
	y0: number,
	y1: number,
	z: number,
	width: number
): any
	local o: Kit.Opts = table.clone(OPTS)
	o.transparency = 0.45
	return kit:box(
		parent,
		"WaterFall",
		frame,
		x - width / 2,
		x + width / 2,
		y0,
		y1,
		z - 0.04,
		z + 0.04,
		{ 168, 190, 186 },
		Water.MATERIAL,
		o
	)
end

return Water
