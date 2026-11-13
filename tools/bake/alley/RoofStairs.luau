--!strict
-- tools/bake/alley/RoofStairs: the people's way up to guard the vent (BRIEF_ADDENDUM D9: "people ... can climb up metal
-- stairs on the back of the bowling alley, and can keep watch and guard the area around where that access to that
-- upper vent is"; owner questions Q3, Q6 and Q12's defaults), as the model "RoofStairs", from Shared/Attractions/
-- AlleyRoof's STAIR, PLATFORM, PEOPLE_FENCE and SQUIRREL_FENCE:
--   a three-flight steel stair against the games wing's back wall in the yard: a concrete foot pad, open diamond-plate
--     treads on two stringers per flight, landings on columns to the ground, a rail along the wall and an outer
--     guard rail (top and middle rails) on posts; under each flight an invisible ramp through the nosings so a
--     person's feet go up smoothly (people only: CanQuery off);
--   the parapet cut where the top landing meets the roof, bridged by a grating;
--   the guard platform: gratings on the wing roof round the vent (the walkway, the strip in front of the louvre and the
--     north strip), the bare apron in front of the louvre left as roof;
--   the people fence: a visible rail on posts on each of its lines (squirrels pass under the bottom rail and between
--     the posts) and an invisible wall up to PEOPLE_FENCE.wallY1 in the collision group PeopleFence, plus the
--     invisible caps over the unit and the duct (people meet them, squirrels' queries do not:
--     Shared/World/CollisionGroups);
--   the squirrel fence: an invisible wall in the group SquirrelFence along the back wall over the top flight (people
--     pass it, squirrels do not: owner question Q12's default, the house is the only way up).
-- Interface: build(kit, root) -> Model; C (the palette); treads(flight) -> { { x0, x1, y } } (each tread's run along
--   X, west edge first, and its top)

local AlleyRoof = require("../../../src/shared/Attractions/AlleyRoof")
local CollisionGroups = require("../../../src/shared/World/CollisionGroups")
local Height = require("../../../src/shared/World/Height")

local RoofStairs = {}

local R = AlleyRoof
local ST = R.STAIR
local PF = R.PEOPLE_FENCE

local C = {
	steel = { 64, 70, 78 },
	tread = { 112, 118, 124 },
	rail = { 214, 168, 40 }, -- safety yellow
	grating = { 92, 96, 100 },
	concrete = { 160, 158, 150 },
}
RoofStairs.C = C

local VISUAL = { collide = false, query = false }
local PEOPLE_ONLY = {
	transparency = 1,
	query = false,
	shadow = false,
	group = CollisionGroups.PEOPLE_FENCE,
}
local SQUIRREL_ONLY = {
	transparency = 1,
	query = false,
	shadow = false,
	group = CollisionGroups.SQUIRREL_FENCE,
}

local function groundY(kit: any, X: number, D: number): number
	local p = kit:cf(X, 0, D).Position
	return Height.at(p.X, p.Z) - p.Y
end

-- A flight's treads, bottom to top: { x0, x1, y } (x0 the west, uphill edge).
function RoofStairs.treads(f: { x0: number, x1: number, y0: number, y1: number }): { { number } }
	local out = {}
	for k = 1, 8 do
		local east = f.x0 - (k - 1) * ST.tread
		table.insert(out, { east - ST.tread, east, f.y0 + k * ST.riser })
	end
	return out
end

-- A box between two local points (a sloped member), w across D and h thick, its long axis along X-Y.
local function member(
	kit: any,
	m: any,
	name: string,
	ax: number,
	ay: number,
	bx: number,
	by: number,
	d: number,
	w: number,
	h: number,
	color: { number },
	opts: any?
): any
	local CFrame = kit.roblox.CFrame
	local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
	local o = table.clone(opts or {})
	o.rot = CFrame.Angles(0, 0, math.atan2(by - ay, bx - ax))
	return kit:at(m, name, (ax + bx) / 2, (ay + by) / 2, d, len, h, w, color, "Metal", o)
end

local function flights(kit: any, m: any)
	local CFrame = kit.roblox.CFrame
	local d0, d1 = ST.d0, ST.d1
	local dm = (d0 + d1) / 2
	local rise = 9 * ST.riser
	for i, f in ST.flights do
		local fm = kit:model(m, `Flight{i}`)
		for _, t in RoofStairs.treads(f) do
			kit:box(fm, "Tread", t[1], t[2], t[3] - 0.12, t[3], d0 + 0.2, d1 - 0.2, C.tread, "DiamondPlate")
		end
		-- the stringers, from the foot to the landing, under the treads' ends
		for _, d in { d0 + 0.1, d1 - 0.1 } do
			member(kit, fm, "Stringer", f.x0 + 0.4, f.y0 - 0.2, f.x1, f.y1 - 0.2, d, 0.2, 0.6, C.steel, VISUAL)
		end
		-- the people's ramp: through every nosing, from a tread out past the foot to the landing (a wedge rising west)
		local run = (9 + 1) * ST.tread - ST.tread -- from one tread east of the foot to the landing
		local x0, x1 = f.x1, f.x0 + ST.tread
		kit:wedge(fm, "Ramp", (x0 + x1) / 2, f.y0 + rise / 2, dm, d1 - d0, rise, run, C.tread, "SmoothPlastic", {
			rot = CFrame.Angles(0, -math.pi / 2, 0),
			transparency = 1,
			query = false,
			shadow = false,
		})
		-- the rails: along the wall, and the outer guard rail's top and middle rails on posts
		local nose0y, nose1y = f.y0 + ST.riser, f.y1
		local nose0x, nose1x = f.x0, f.x1 + ST.tread
		member(
			kit,
			fm,
			"WallRail",
			nose0x,
			nose0y + 3.0,
			nose1x - 1.5,
			nose1y + 3.0,
			d0 + 0.15,
			0.12,
			0.12,
			C.rail,
			VISUAL
		)
		for _, h in { ST.railTop, ST.railMid } do
			member(kit, fm, "GuardRail", nose0x + 0.2, nose0y + h, f.x1, f.y1 + h, d1 - 0.1, 0.12, 0.14, C.rail)
		end
		for k = 0, 2 do
			local x = f.x0 - k * 4.5 - 0.3
			local y = f.y0 + ST.riser * (1 + k * 3)
			kit:box(fm, "RailPost", x - 0.08, x + 0.08, y - 0.2, y + ST.railTop, d1 - 0.18, d1 - 0.02, C.rail, "Metal")
		end
	end
	-- the landings on their columns, with their guard rails
	for i, l in ST.landings do
		local lm = kit:model(m, `Landing{i}`)
		kit:box(lm, "Landing", l.x0, l.x1, l.y - 0.15, l.y, d0, d1, C.tread, "DiamondPlate")
		kit:box(lm, "LandingBeam", l.x0, l.x1, l.y - 0.55, l.y - 0.15, d1 - 0.3, d1, C.steel, "Metal", VISUAL)
		for _, x in { l.x0 + 0.2, l.x1 - 0.2 } do
			local g = groundY(kit, x, d1 - 0.2)
			kit:box(lm, "Column", x - 0.15, x + 0.15, g - 0.3, l.y - 0.15, d1 - 0.35, d1 - 0.05, C.steel, "Metal")
		end
		for _, h in { ST.railTop, ST.railMid } do
			kit:box(lm, "GuardRail", l.x0, l.x1, l.y + h - 0.07, l.y + h + 0.07, d1 - 0.16, d1 - 0.04, C.rail, "Metal")
		end
		-- the outer post at the corner
		kit:box(lm, "RailPost", l.x0 + 0.02, l.x0 + 0.18, l.y, l.y + ST.railTop, d1 - 0.18, d1 - 0.02, C.rail, "Metal")
	end
	-- the foot pad and a column under each flight's foot
	local f1 = ST.flights[1]
	local padX0, padX1 = f1.x0 - 0.5, f1.x0 + ST.tread + 1.5
	kit:box(m, "FootPad", padX0, padX1, ST.footY - 0.6, ST.footY, d0 - 0.2, d1 + 0.2, C.concrete, "Concrete")
end

local function platform(kit: any, m: any)
	local y = R.PLATFORM.y
	local roof = R.WING_ROOF.y
	local pm = kit:model(m, "Platform")
	local function grating(name: string, x0: number, x1: number, d0: number, d1: number)
		kit:box(pm, name, x0, x1, roof + 0.02, y, d0, d1, C.grating, "DiamondPlate")
	end
	local rs = R.PLATFORM.rects
	-- (the strips meet without overlapping: the louvre strip runs between the north strip and the walkway)
	grating("Walkway", rs[1].x0, rs[1].x1, rs[1].d0, rs[1].d1)
	grating("LouvreStrip", rs[2].x0, rs[2].x1, rs[3].d1, rs[1].d0)
	grating("NorthStrip", rs[3].x0, rs[3].x1, rs[3].d0, rs[3].d1)
	-- the cut in the wing's back parapet, bridged to the top landing
	local cut = ST.parapetCut
	grating("CutBridge", cut.x0, cut.x1, R.WING_ROOF.d1, ST.d0)
end

local function fences(kit: any, m: any)
	local fm = kit:model(m, "PeopleFence")
	local y = R.PLATFORM.y
	for i, l in PF.lines do
		local alongD = l.x0 == l.x1
		local a0, a1 = if alongD then l.d0 else l.x0, if alongD then l.d1 else l.x1
		-- the invisible wall
		if alongD then
			kit:box(
				fm,
				"FenceWall",
				l.x0 - 0.05,
				l.x0 + 0.05,
				PF.wallY0,
				PF.wallY1,
				l.d0,
				l.d1,
				{ 255, 140, 30 },
				"SmoothPlastic",
				PEOPLE_ONLY
			)
		else
			kit:box(
				fm,
				"FenceWall",
				l.x0,
				l.x1,
				PF.wallY0,
				PF.wallY1,
				l.d0 - 0.05,
				l.d0 + 0.05,
				{ 255, 140, 30 },
				"SmoothPlastic",
				PEOPLE_ONLY
			)
		end
		-- the visible rail: on the parapet (the south line) only its top rail, else top and bottom rails
		local onParapet = i == 3
		local rails = if onParapet then { PF.railTop } else { PF.railTop, PF.bottomRail }
		for _, h in rails do
			if alongD then
				kit:box(fm, "FenceRail", l.x0 - 0.06, l.x0 + 0.06, y + h - 0.07, y + h + 0.07, a0, a1, C.rail, "Metal")
			else
				kit:box(fm, "FenceRail", a0, a1, y + h - 0.07, y + h + 0.07, l.d0 - 0.06, l.d0 + 0.06, C.rail, "Metal")
			end
		end
		-- posts: at both ends and every postPitch from the line's first post
		local first = if alongD then PF.posts.d0 else PF.posts.x0
		local at = { a0 + 0.08, a1 - 0.08 }
		local v = first
		while v < a1 - 0.5 do
			if v > a0 + 0.5 then
				table.insert(at, v)
			end
			v += PF.postPitch
		end
		local base = if onParapet then R.WING_ROOF.copingY else R.WING_ROOF.y
		for _, p in at do
			if alongD then
				kit:box(
					fm,
					"FencePost",
					l.x0 - 0.08,
					l.x0 + 0.08,
					base,
					y + PF.railTop + 0.07,
					p - 0.08,
					p + 0.08,
					C.rail,
					"Metal"
				)
			else
				kit:box(
					fm,
					"FencePost",
					p - 0.08,
					p + 0.08,
					base,
					y + PF.railTop + 0.07,
					l.d0 - 0.08,
					l.d0 + 0.08,
					C.rail,
					"Metal"
				)
			end
		end
	end
	for _, c in PF.caps do
		kit:box(fm, "PeopleCap", c.x0, c.x1, c.y0, c.y1, c.d0, c.d1, { 255, 140, 30 }, "SmoothPlastic", PEOPLE_ONLY)
	end
	local sf = R.SQUIRREL_FENCE
	kit:box(
		m,
		"SquirrelFence",
		sf.x0,
		sf.x1,
		sf.y0,
		sf.y1,
		sf.d0,
		sf.d1,
		{ 60, 220, 255 },
		"SmoothPlastic",
		SQUIRREL_ONLY
	)
end

-- build(kit, root): the model RoofStairs under root.
function RoofStairs.build(kit: any, root: any): any
	local m = kit:model(root, "RoofStairs")
	flights(kit, m)
	platform(kit, m)
	fences(kit, m)
	return m
end

return RoofStairs
