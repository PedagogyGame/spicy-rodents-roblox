--!strict
-- tools/bake/sewers/Section: the storm drains' cross-section drawn in parts, in a run's frame (Kit.frame: x across,
-- left +; y up from the walkway top; z along). The numbers are the owner's modules' (data/sewers.json sections,
-- from art_pack/Metadata 01 and 03): walls 3.0..3.32 off the axis to the spring line (2.2), a round vault (inner
-- radius 3.0 from the spring, outer 3.32), brick walkways 0.9..3.0 either side of a channel (bed 0.7..0.98 down,
-- water at 0.34 down), or a dry floor wall to wall.
--   arched(kit, parent, frame, z0, z1, section, lane, pipes?)   floor, walkways, channel and its water, walls, the
--        vault in six facets, and (pipes) two service pipes on the wall away from the squirrel's lane (lane: +1 or -1,
--        the side the route runs, 0 on the dry floor's middle). Every part but the water collides, so the camera
--        and anyone's body stay inside.
--   box(kit, parent, frame, z0, z1, section, endWall?, header?)   the chamber under a shaft: the same floor, straight
--        walls up to the flat roof (Shaft.roof), the end wall behind (endWall "z0" or "z1": the end it stands at) and,
--        on the open side (header "z0" or "z1"), the header: the arch ring wall that closes the box down to the
--        vault's profile
--   header(kit, parent, frame, za, zb, section)          that ring wall alone (the junction's arches use it too)
--   backing(kit, parent, frame, z0, z1, section, roof)   the opaque casing outside the shell (the art pack's import
--        notes: at least a stud of Part backing round an interior, so no outdoor light leaks in): side walls, floor
--        slab and (roof = true) Section.roof
--   roof(kit, parent, frame, z0, z1, section)            the backing's slab over the vault, a stud thick
-- Colours and materials: Section.PALETTE.

local Kit = require("./Kit")
local Water = require("./Water")

local Section = {}

Section.FACETS = 6
Section.ROOF = 5.3 -- studs over the walkway: the underside of a shaft chamber's flat roof (over the vault's inner top)
Section.TOP = 6.52 -- studs over the walkway: the top of the backing (the vault's outer top plus a stud)
Section.PALETTE = {
	brick = { { 146, 88, 66 }, "Brick" },
	concrete = { { 126, 122, 114 }, "Concrete" },
	dry = { { 138, 134, 124 }, "Concrete" },
	trim = { { 168, 160, 144 }, "Slate" },
	iron = { { 50, 52, 54 }, "Metal" },
	teal = { { 62, 106, 104 }, "Metal" },
	backing = { { 38, 34, 32 }, "Slate" },
}

local function paint(kind: string): ({ number }, string)
	local p = (Section.PALETTE :: any)[kind]
	return p[1], p[2]
end

local function wallPaint(section: any): ({ number }, string)
	return paint(if section.kind == "dry" then "dry" else "brick")
end

-- floor, walkways, channel bed and water
local function floor(kit: Kit.Kit, parent: any, frame: any, z0: number, z1: number, section: any)
	local c, m = paint("concrete")
	local below = section.below
	local inner = section.innerHalf
	if section.water ~= nil then
		local w = section.walkway[1]
		kit:box(parent, "Walkway", frame, w, inner, -below, 0, z0, z1, c, m)
		kit:box(parent, "Walkway", frame, -inner, -w, -below, 0, z0, z1, c, m)
		kit:box(parent, "ChannelBed", frame, -w, w, -below - 0.1, -0.7, z0, z1, c, m)
		Water.channel(kit, parent, frame, z0, z1, section)
	else
		kit:box(parent, "Floor", frame, -inner, inner, -below, 0, z0, z1, c, m)
	end
end

local function walls(kit: Kit.Kit, parent: any, frame: any, z0: number, z1: number, section: any, top: number)
	local c, m = wallPaint(section)
	local inner, outer = section.innerHalf, section.outerHalf
	kit:box(parent, "Wall", frame, inner, outer, -section.below, top, z0, z1, c, m)
	kit:box(parent, "Wall", frame, -outer, -inner, -section.below, top, z0, z1, c, m)
end

local function vault(kit: Kit.Kit, parent: any, frame: any, z0: number, z1: number, section: any)
	local c, m = wallPaint(section)
	local inner, outer, spring = section.innerHalf, section.outerHalf, section.spring
	local n = Section.FACETS
	local rm = (inner + outer) / 2
	local width = 2 * outer * math.sin(math.pi / (2 * n)) + 0.04
	local zc = (z0 + z1) / 2
	for i = 0, n - 1 do
		local th = (i + 0.5) * math.pi / n
		kit:rolled(
			parent,
			"Vault",
			frame,
			rm * math.cos(th),
			spring + rm * math.sin(th),
			zc,
			th - math.pi / 2,
			{ width, outer - inner, z1 - z0 },
			c,
			m
		)
	end
end

function Section.header(kit: Kit.Kit, parent: any, frame: any, za: number, zb: number, section: any)
	local c, m = wallPaint(section)
	local inner, spring = section.innerHalf, section.spring
	local n = Section.FACETS
	local thick = 1.4 -- radially, from the arch out past the box's corner (to the walls and the roof)
	local chord = 2 * inner * math.tan(math.pi / (2 * n))
	for i = 0, n - 1 do
		local th = (i + 0.5) * math.pi / n
		local r = inner + thick / 2
		kit:rolled(
			parent,
			"Header",
			frame,
			r * math.cos(th),
			spring + r * math.sin(th),
			(za + zb) / 2,
			th - math.pi / 2,
			{ chord + 1.2, thick, zb - za },
			c,
			m
		)
	end
end

local function pipes(kit: Kit.Kit, parent: any, frame: any, z0: number, z1: number, section: any, lane: number)
	if lane == 0 then
		return
	end
	local side = -lane
	local tc, tm = paint("teal")
	local x = side * (section.innerHalf - 0.27)
	kit:cyl(parent, "ServicePipe", frame, { x, 1.65, z0 }, { x, 1.65, z1 }, 0.26, tc, tm)
	local xu = side * (section.innerHalf - 0.27)
	kit:cyl(parent, "ServicePipe", frame, { xu, 1.99, z0 }, { xu, 1.99, z1 }, 0.12, tc, tm)
end

function Section.arched(
	kit: Kit.Kit,
	parent: any,
	frame: any,
	z0: number,
	z1: number,
	section: any,
	lane: number,
	withPipes: boolean?
)
	floor(kit, parent, frame, z0, z1, section)
	walls(kit, parent, frame, z0, z1, section, section.spring)
	vault(kit, parent, frame, z0, z1, section)
	if withPipes then
		pipes(kit, parent, frame, z0, z1, section, lane)
	end
end

function Section.box(
	kit: Kit.Kit,
	parent: any,
	frame: any,
	z0: number,
	z1: number,
	section: any,
	endWall: string?,
	header: string?
)
	floor(kit, parent, frame, z0, z1, section)
	walls(kit, parent, frame, z0, z1, section, Section.ROOF + 0.25)
	local c, m = wallPaint(section)
	local outer = section.outerHalf
	if endWall == "z0" then
		kit:box(parent, "EndWall", frame, -outer, outer, -section.below, Section.TOP, z0 - 0.32, z0, c, m)
	elseif endWall == "z1" then
		kit:box(parent, "EndWall", frame, -outer, outer, -section.below, Section.TOP, z1, z1 + 0.32, c, m)
	end
	if header == "z1" then
		Section.header(kit, parent, frame, z1 - 0.3, z1, section)
	elseif header == "z0" then
		Section.header(kit, parent, frame, z0, z0 + 0.3, section)
	end
end

function Section.backing(kit: Kit.Kit, parent: any, frame: any, z0: number, z1: number, section: any, roof: boolean)
	local c, m = paint("backing")
	local outer = section.outerHalf
	local bottom = -section.below - 1.0
	kit:box(parent, "Backing", frame, outer, outer + 1, bottom, Section.TOP, z0, z1, c, m)
	kit:box(parent, "Backing", frame, -outer - 1, -outer, bottom, Section.TOP, z0, z1, c, m)
	kit:box(parent, "Backing", frame, -outer, outer, bottom, -section.below - 0.1, z0, z1, c, m)
	if roof then
		Section.roof(kit, parent, frame, z0, z1, section)
	end
end

-- the backing's roof slab over the vault
function Section.roof(kit: Kit.Kit, parent: any, frame: any, z0: number, z1: number, section: any)
	local c, m = paint("backing")
	local outer = section.outerHalf
	kit:box(parent, "Backing", frame, -outer, outer, section.crown, Section.TOP, z0, z1, c, m)
end

return Section
