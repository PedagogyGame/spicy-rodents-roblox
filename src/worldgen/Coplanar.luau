--!strict
-- ServerScriptService.Server.WorldGen.Coplanar
-- The flicker check (owner: "the doors glitch and shimmer in a strobe light way"): two drawn faces
-- that look the same way on one plane fight for the same pixels as the camera moves. This finds every
-- such pair inside one BuildPlan, so trim, window bars, eaves and furniture can be added freely and
-- the bake still proves that nothing shimmers.
-- Rule: opaque or translucent Blocks (no mesh, no wedge, cylinder or ball) are grouped by orientation
-- (all quarter-turn parts share the world-axis group; any other yaw/pitch/roll forms its own group and
-- is compared in its local frame, which covers roof plates and the eave strips that continue them).
-- Two same-facing faces within TOL of one plane whose rectangles overlap by more than MIN on both
-- sides clash when the parts differ in colour or material, unless
--   * a third drawn Block covers the overlap from the outside (a back face against a wall or body), or
--   * the faces look down at or below the lot's seat (bottoms resting on the ground).
-- Interface: clashes(parts, seatY?) -> { Clash }; run(plans) -> { checked, clashes = { "<plan>: A and B (axis)" } }
-- Pure.

local Geometry = require("./Geometry")
local Spec = require("./Spec")

local Coplanar = {}

Coplanar.TOL = 0.02 -- studs: faces nearer than this to one plane fight
Coplanar.MIN = 0.3 -- studs: the shared rectangle must exceed this on both sides

export type Clash = { a: string, b: string, axis: number, side: number, plane: number }

type Box = { s: Spec.PartSpec, lo: { number }, hi: { number } }

local HALF = math.pi / 2
local AXIS = { "x", "y", "z" }

local function drawnBlock(s: Spec.PartSpec): boolean
	return (s.shape == nil or s.shape == "Block") and s.mesh == nil and (s.transparency or 0) < 1
end

-- Orientation group and the part's box in that group's frame.
local function boxOf(s: Spec.PartSpec): (string, Box)
	local q = s.yaw / HALF
	local pitch, roll = s.pitch or 0, s.roll or 0
	if math.abs(q - math.round(q)) < 1e-6 and pitch == 0 and roll == 0 then
		local swap = math.round(q) % 2 ~= 0
		local hx, hz = (if swap then s.sz else s.sx) / 2, (if swap then s.sx else s.sz) / 2
		return "axis",
			{
				s = s,
				lo = { s.cx - hx, s.cy - s.sy / 2, s.cz - hz },
				hi = { s.cx + hx, s.cy + s.sy / 2, s.cz + hz },
			}
	end
	local c = Geometry.unrotate({ s.cx, s.cy, s.cz }, s.yaw, pitch, roll)
	return string.format("%.4f|%.4f|%.4f", s.yaw % (2 * math.pi), pitch, roll),
		{
			s = s,
			lo = { c[1] - s.sx / 2, c[2] - s.sy / 2, c[3] - s.sz / 2 },
			hi = { c[1] + s.sx / 2, c[2] + s.sy / 2, c[3] + s.sz / 2 },
		}
end

local function sameLook(a: Spec.PartSpec, b: Spec.PartSpec): boolean
	return a.material == b.material
		and a.color[1] == b.color[1]
		and a.color[2] == b.color[2]
		and a.color[3] == b.color[3]
		and (a.transparency or 0) == (b.transparency or 0)
end

function Coplanar.clashes(parts: { Spec.PartSpec }, seatY: number?): { Clash }
	local groups: { [string]: { Box } } = {}
	local order: { string } = {}
	for _, s in parts do
		if drawnBlock(s) then
			local key, box = boxOf(s)
			if not groups[key] then
				groups[key] = {}
				table.insert(order, key)
			end
			table.insert(groups[key], box)
		end
	end
	local out: { Clash } = {}
	local TOL, MIN = Coplanar.TOL, Coplanar.MIN
	for _, key in order do
		local boxes = groups[key]
		for ax = 1, 3 do
			local u, v = ax % 3 + 1, (ax + 1) % 3 + 1
			for side = -1, 1, 2 do
				local faces: { { number } } = {}
				for i, b in boxes do
					table.insert(faces, { if side < 0 then b.lo[ax] else b.hi[ax], i })
				end
				table.sort(faces, function(f1, f2)
					if f1[1] == f2[1] then
						return f1[2] < f2[2]
					end
					return f1[1] < f2[1]
				end)
				for i = 1, #faces do
					local A = boxes[faces[i][2]]
					local j = i + 1
					while j <= #faces and faces[j][1] - faces[i][1] < TOL do
						local B = boxes[faces[j][2]]
						j += 1
						local u0, u1 = math.max(A.lo[u], B.lo[u]), math.min(A.hi[u], B.hi[u])
						local v0, v1 = math.max(A.lo[v], B.lo[v]), math.min(A.hi[v], B.hi[v])
						if u1 - u0 > MIN and v1 - v0 > MIN and not sameLook(A.s, B.s) then
							local plane = faces[i][1]
							local hidden = key == "axis"
								and ax == 2
								and side < 0
								and seatY ~= nil
								and plane <= seatY + 0.05
							if not hidden then
								-- covered from the outside by a third drawn block
								for _, C in boxes do
									if C ~= A and C ~= B then
										local over = if side > 0
											then C.lo[ax] <= plane + TOL and C.hi[ax] >= plane + 0.05
											else C.hi[ax] >= plane - TOL and C.lo[ax] <= plane - 0.05
										if
											over
											and C.lo[u] <= u0 + 0.01
											and C.hi[u] >= u1 - 0.01
											and C.lo[v] <= v0 + 0.01
											and C.hi[v] >= v1 - 0.01
										then
											hidden = true
											break
										end
									end
								end
							end
							if not hidden then
								table.insert(out, { a = A.s.name, b = B.s.name, axis = ax, side = side, plane = plane })
							end
						end
					end
				end
			end
		end
	end
	return out
end

-- Every plan's own parts (one model each): the clashes as "<plan>: A and B (+x)".
function Coplanar.run(plans: { Spec.BuildPlan }): { checked: number, clashes: { string } }
	local checked = 0
	local out: { string } = {}
	for _, p in plans do
		local seat = if p.kind == "lot" then p.attributes.SeatY :: number? else nil
		for _, s in p.parts do
			if drawnBlock(s) then
				checked += 1
			end
		end
		for _, c in Coplanar.clashes(p.parts, seat) do
			table.insert(out, `{p.id}: {c.a} and {c.b} ({if c.side > 0 then "+" else "-"}{AXIS[c.axis]})`)
		end
	end
	return { checked = checked, clashes = out }
end

return Coplanar
