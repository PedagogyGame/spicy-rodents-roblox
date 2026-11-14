--!strict
-- tools/games/paintball/arena/LowCover: can a standing shooter tag a crouched body on a low cover spot? (checklist
-- PB-5, PB-9; the contract's rule that low cover wholly hides a crouched body "from a ball as from the eye".)
-- OWNED BY THE ARENA LANE. For a low spot of the graph, standing shooters on its sheltered side, SPREAD degrees
-- either side of (nx, nz) and DISTANCES studs out from the spot wherever a body can stand, aim at points all over
-- the near half of the crouched body's hit shape (its round top most of all: that is where the danger is) with the
-- game's own ball test: Hit.body for the body, `sweep` for everything in front of it. A shooter tags the body when a
-- ball reaches the body before any box.
-- WHAT IT FOUND (2026-11-13): with the contract's numbers (Arena.RAIL_HEIGHT 3.4 over Body.CROUCH_TOP 3.36, a
-- standing eye at 4.5) a shooter straight out tags the crown of a crouched head over most low cover: the margin is
-- 0.04 studs, so any eye nearer than some thirty studs sees over the cover onto the top of the head. No place the
-- arena could put a spot mends that (a body cannot stand nearer the face than its own width). With every low piece
-- raised to ENOUGH no shooter straight out tags any low spot of the arena: the change the contract needs (the
-- lane's report, contractGaps). SETTLED AT THE JOIN: raising only the rooms' low cover (KIND.cover) to ENOUGH
-- is enough (no low spot is then tagged, with the atrium's rails left at RAIL_HEIGHT, which keeps a standing
-- eye at a rail looking down across the atrium), so that is Arena.COVER_HEIGHT.
-- Pure. Interface: probe(sweep, ground, x, y, z, nx, nz) -> (tags, aims, lowest): the aims that tag, of how many,
--   and the lowest point a tag lands at above the feet (math.huge for none); raised(boxes, kinds, rail) -> boxes: a
--   copy of the boxes with every low piece (cover, rail) raised to `rail` above its foot; ENOUGH; DISTANCES; SPREAD
local Arena = require("../../../../src/shared/Minigames/Paintball/Arena")
local Body = require("../../../../src/shared/Minigames/Paintball/Body")
local Hit = require("../../../../src/shared/Minigames/Paintball/Hit")
local NavBuild = require("./NavBuild")

local LowCover = {}

LowCover.DISTANCES = { 5, 8, 12, 18, 25, 30 }
LowCover.SPREAD = { 0 } -- degrees off the sheltered side (low cover shelters from that side, not round its ends)
LowCover.ENOUGH = 3.7 -- the least rail height at which no standing shooter straight out tags a low spot

function LowCover.probe(
	sweep: Arena.Sweep,
	ground: Arena.Ground,
	x: number,
	y: number,
	z: number,
	nx: number,
	nz: number
): (number, number, number)
	local tags, aims, lowest = 0, 0, math.huge
	local low, high, r = Body.capsule(1)
	for _, deg in LowCover.SPREAD do
		local a = math.rad(deg)
		local dx, dz = nx * math.cos(a) - nz * math.sin(a), nx * math.sin(a) + nz * math.cos(a)
		for _, d in LowCover.DISTANCES do
			local sx, sz = x + dx * d, z + dz * d
			local g = NavBuild.standable(sweep, ground, sx, y, sz)
			if g == nil or math.abs(g - y) > Arena.STEP_UP then
				continue
			end
			local ex, ey, ez = sx, g + Body.STAND_EYE, sz
			-- the horizontal from the body to the shooter, and across it
			local hx, hz = ex - x, ez - z
			local len = math.sqrt(hx * hx + hz * hz)
			hx, hz = hx / len, hz / len
			local px, pz = -hz, hx
			-- points on the near half of the shape: the round top (12 heights of it, 5 ways round) and the side
			local targets: { { number } } = {}
			for i = 0, 12 do
				local phi = math.rad(90 * i / 12) -- 0: the very top; 90: the top's equator
				for _, turn in { -60, -30, 0, 30, 60 } do
					local tr = math.rad(turn)
					local ux, uz = hx * math.cos(tr) + px * math.sin(tr), hz * math.cos(tr) + pz * math.sin(tr)
					table.insert(targets, {
						x + ux * r * math.sin(phi),
						y + high + r * math.cos(phi),
						z + uz * r * math.sin(phi),
					})
				end
			end
			for h = low, high, 0.25 do
				table.insert(targets, { x + hx * r, y + h, z + hz * r })
			end
			for _, p in targets do
				aims += 1
				-- the ball flies through the point and on, a stud and a half past the body
				local fx, fy, fz = p[1] - ex, p[2] - ey, p[3] - ez
				local l = math.sqrt(fx * fx + fy * fy + fz * fz)
				local k = (l + 2 * r + 1.5) / l
				fx, fy, fz = ex + fx * k, ey + fy * k, ez + fz * k
				local s, _, ty = Hit.body(sweep, ex, ey, ez, fx, fy, fz, x, y, z, 1)
				if s ~= nil then
					local wall = sweep(ex, ey, ez, fx, fy, fz)
					if wall == nil or s < wall then
						tags += 1
						lowest = math.min(lowest, ty - y)
					end
				end
			end
		end
	end
	return tags, aims, lowest
end

function LowCover.raised(boxes: { number }, kinds: { number }, rail: number): { number }
	local out = table.clone(boxes)
	for i, kind in kinds do
		local k = (i - 1) * 6
		if kind == Arena.KIND.cover or kind == Arena.KIND.rail then
			out[k + 5] = math.max(out[k + 5], out[k + 2] + rail)
		end
	end
	return out
end

return LowCover
