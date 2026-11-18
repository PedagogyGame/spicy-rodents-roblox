--!strict
-- The words painted on the three playfields (tools/bake/games/Pinball's Bake.ART: the bake's SurfaceGui and the
-- board textures tools/blender/pinball/boards.py draws from the same list) stand clear of everything else on the
-- table, measured from the model's own data (Shared/Minigames/Pinball/Table*): no word's box overlaps another
-- word, a lamp's insert, a ramp's footprint, a guide (a wall at the thickness the bake draws it, a post), a pop
-- bumper, a target, a flipper at rest or a kick-out hole; and every word is on the board.
local Layout = require("@shared/Minigames/Pinball/Layout")
local Tables = require("@shared/Minigames/Pinball/Tables")
local Bake = require("../../tools/bake/games/Pinball")

local LAMP_R = 0.05 -- the lamp's insert (the bake's Lamp part and the board's ring)
local CLEAR = 0.01 -- studs kept between a word's box and anything else
-- a wall's half thickness as the bake draws it (Bake WALL)
local HALF = { wood = 0.03, metal = 0.011, plastic = 0.0225, rubber = 0.0175 }

type Rect = { x0: number, x1: number, y0: number, y1: number, text: string }

local function rectOf(p: any, lamps: { [string]: any }): Rect
	local lamp = p.lamp and lamps[p.lamp]
	local x = (if lamp then lamp.x else p.x or 0) + p.dx
	local y = (if lamp then lamp.y else p.y or 0) + p.dy
	return { x0 = x - p.w / 2, x1 = x + p.w / 2, y0 = y - p.h / 2, y1 = y + p.h / 2, text = p.text }
end

-- distance from a point to a rectangle (0 inside)
local function pointRect(px: number, py: number, r: Rect): number
	local dx = math.max(r.x0 - px, 0, px - r.x1)
	local dy = math.max(r.y0 - py, 0, py - r.y1)
	return math.sqrt(dx * dx + dy * dy)
end

local function pointSeg(px: number, py: number, ax: number, ay: number, bx: number, by: number): number
	local dx, dy = bx - ax, by - ay
	local l2 = dx * dx + dy * dy
	local t = if l2 < 1e-12 then 0 else math.clamp(((px - ax) * dx + (py - ay) * dy) / l2, 0, 1)
	local qx, qy = ax + dx * t - px, ay + dy * t - py
	return math.sqrt(qx * qx + qy * qy)
end

local function segsCross(ax: number, ay: number, bx: number, by: number, cx: number, cy: number, dx: number, dy: number)
	local function side(px: number, py: number, qx: number, qy: number, rx: number, ry: number): number
		return (qx - px) * (ry - py) - (qy - py) * (rx - px)
	end
	local d1, d2 = side(cx, cy, dx, dy, ax, ay), side(cx, cy, dx, dy, bx, by)
	local d3, d4 = side(ax, ay, bx, by, cx, cy), side(ax, ay, bx, by, dx, dy)
	return d1 * d2 < 0 and d3 * d4 < 0
end

-- distance from a segment to a rectangle (0 when it touches or enters it)
local function segRect(ax: number, ay: number, bx: number, by: number, r: Rect): number
	if pointRect(ax, ay, r) == 0 or pointRect(bx, by, r) == 0 then
		return 0
	end
	local cs = { { r.x0, r.y0 }, { r.x1, r.y0 }, { r.x1, r.y1 }, { r.x0, r.y1 } }
	for i = 1, 4 do
		local c, d = cs[i], cs[i % 4 + 1]
		if segsCross(ax, ay, bx, by, c[1], c[2], d[1], d[2]) then
			return 0
		end
	end
	local best = math.min(pointRect(ax, ay, r), pointRect(bx, by, r))
	for _, c in cs do
		best = math.min(best, pointSeg(c[1], c[2], ax, ay, bx, by))
	end
	return best
end

-- every thing on the table a word must keep clear of: { what, distance-from-rect function }
local function obstacles(tbl: any): { { what: string, dist: (Rect) -> number } }
	local def = tbl.def
	local out = {}
	local function circle(what: string, x: number, y: number, r: number)
		table.insert(out, {
			what = what,
			dist = function(rect: Rect): number
				return pointRect(x, y, rect) - r
			end,
		})
	end
	local function line(what: string, pts: { number }, stride: number, half: number)
		table.insert(out, {
			what = what,
			dist = function(rect: Rect): number
				local best = math.huge
				for i = 1, #pts - stride, stride do
					best = math.min(best, segRect(pts[i], pts[i + 1], pts[i + stride], pts[i + stride + 1], rect))
				end
				return best - half
			end,
		})
	end
	for _, l in def.lamps do
		circle(`lamp {l.id}`, l.x, l.y, LAMP_R)
	end
	for _, rail in def.rails do
		line(`ramp {rail.id}`, rail.pts, 3, Layout.BALL_R + 0.03)
	end
	for i, w in def.walls do
		line(`{w.mat} guide {i}`, w.pts, 2, HALF[w.mat] or 0.011)
	end
	for i, p in def.posts do
		circle(`post {i}`, p.x, p.y, p.r)
	end
	for _, b in def.bumpers do
		circle(`bumper {b.id}`, b.x, b.y, b.r)
	end
	for _, g in def.targets do
		line(`target {g.id}`, { g.x1, g.y1, g.x2, g.y2 }, 2, 0.015)
	end
	for _, s in def.saucers do
		circle(`hole {s.id}`, s.x, s.y, s.r + Layout.BALL_R)
	end
	for _, f in def.flippers do
		local sgn = if f.mirror then -1 else 1
		local tx, ty = f.x + sgn * math.cos(f.rest) * f.len, f.y + math.sin(f.rest) * f.len
		line(`flipper {f.id}`, { f.x, f.y, tx, ty }, 2, f.rBase)
	end
	return out
end

local function rects(variant: string, tbl: any): { Rect }
	local lamps: { [string]: any } = {}
	for _, l in tbl.def.lamps do
		lamps[l.id] = l
	end
	local out = {}
	for _, p in Bake.ART[variant] do
		table.insert(out, rectOf(p, lamps))
	end
	return out
end

return function(t)
	for _, variant in { "acorn", "rodent", "space" } do
		local tbl = Tables.need(Tables.forVariant(variant) :: string)
		local words = rects(variant, tbl)

		t.test(`{variant}: every painted word is on the board`, function()
			for _, r in words do
				t.truthy(
					r.x0 >= 0 and r.x1 <= Layout.WIDTH and r.y0 >= -0.16 and r.y1 <= Layout.LENGTH,
					`{r.text} off the board`
				)
			end
		end)

		t.test(`{variant}: no painted word overlaps another`, function()
			local bad = {}
			for i = 1, #words do
				for j = i + 1, #words do
					local a, b = words[i], words[j]
					if a.x0 < b.x1 + CLEAR and b.x0 < a.x1 + CLEAR and a.y0 < b.y1 + CLEAR and b.y0 < a.y1 + CLEAR then
						table.insert(bad, `{a.text} / {b.text}`)
					end
				end
			end
			t.eq(table.concat(bad, "; "), "")
		end)

		t.test(`{variant}: no painted word lies on a lamp, a ramp, a guide or a part the ball hits`, function()
			local bad = {}
			for _, r in words do
				for _, o in obstacles(tbl) do
					local d = o.dist(r)
					if d < CLEAR then
						table.insert(bad, `{r.text} on {o.what} ({string.format("%.3f", d)})`)
					end
				end
			end
			t.eq(table.concat(bad, "; "), "")
		end)
	end
end
