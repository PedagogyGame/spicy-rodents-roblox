--!strict
-- ReplicatedStorage.Shared.Minigames.Paintball.Hit
-- THE test of a ball against a body (checklist PB-3, PB-5, PB-9; Contract decision 10). FROZEN: no lane
-- edits this file. One function, so that the three who ask cannot disagree:
--   the server    Server/Paintball/Projectiles, for every ball each tick, against each opposing body
--                 where its pose history puts it at the ball's rewound time;
--   the shooter   Client/Minigames/Paintball, for its own predicted ball each frame, against each
--                 opposing puppet where it is DRAWN (the same pose, number for number: Clock);
--   the bots      the match-and-bots lane's headless ball loop.
-- THE RULES
--   1. A ball is its CENTRE LINE: the segment its centre flies in one step. Nothing is added for its
--      radius, against a wall (arena.sweep) or against a body (reach = Body.RADIUS). So "wholly
--      behind the rail" is one comparison of heights and holds for the ball too.
--   2. A body is touched where the segment ENTERS its capsule (Body.capsule at the body's crouch
--      fraction), not where it comes nearest to the axis. The S18 test returned the closest approach,
--      which can be the far end of a step whose near part is still in front of a wall.
--   3. The touch COUNTS only if no box stands between that entry point and the body's middle: the
--      point of the axis at the entry point's height (held to the axis's ends). A shape that pokes a
--      little through a thin rail or round a pillar's corner cannot be hit on the part that pokes: the
--      ball goes on and stops on the rail or the pillar, where it is drawn to. (A ball that only
--      grazes a covered edge and leaves again within the step is a miss.)
--   4. The first thing along the step wins: of arena.sweep's s and every body's s, the smallest; a tie
--      goes to the wall. The hit point reported (the splat, "paintball_tag" x y z) is the entry point.
--   5. A step that starts inside a capsule enters at s = 0 (and rule 3 is asked from there).
-- Who may be hit at all (team, out, protection, the spawn room) is not decided here: the caller skips
-- those bodies (PaintballService, "balls"; PaintballClient, "firing").
-- Interface: capsule(p0x, p0y, p0z, p1x, p1y, p1z, cx, cyLow, cyHigh, cz, r) -> s?; body(sweep, p0x,
--   p0y, p0z, p1x, p1y, p1z, x, y, z, crouch) -> (s?, hx, hy, hz)

local Arena = require("./Arena")
local Body = require("./Body")

local Hit = {}

-- Where the segment P0 -> P1 enters the vertical capsule whose axis runs from (cx, cyLow, cz) to
-- (cx, cyHigh, cz) with radius r: the fraction s in [0, 1] along the segment, 0 when it starts
-- inside, nil when it never enters.
function Hit.capsule(
	p0x: number,
	p0y: number,
	p0z: number,
	p1x: number,
	p1y: number,
	p1z: number,
	cx: number,
	cyLow: number,
	cyHigh: number,
	cz: number,
	r: number
): number?
	local rx, rz = p0x - cx, p0z - cz
	local rr = r * r
	local flat = rx * rx + rz * rz
	-- already inside?
	local ay = math.clamp(p0y, cyLow, cyHigh)
	if flat + (p0y - ay) * (p0y - ay) <= rr then
		return 0
	end
	local dx, dy, dz = p1x - p0x, p1y - p0y, p1z - p0z
	local best: number? = nil
	-- the side: the upright cylinder, where the entry is between the axis's ends
	local a = dx * dx + dz * dz
	if a > 1e-12 then
		local b = rx * dx + rz * dz
		local disc = b * b - a * (flat - rr)
		if disc >= 0 then
			local s = (-b - math.sqrt(disc)) / a
			if s >= 0 and s <= 1 then
				local y = p0y + dy * s
				if y >= cyLow and y <= cyHigh then
					best = s
				end
			end
		end
	end
	-- the two round ends
	local len = a + dy * dy
	if len > 1e-12 then
		for i = 1, 2 do
			local ry = p0y - (if i == 1 then cyLow else cyHigh)
			local b = rx * dx + ry * dy + rz * dz
			local disc = b * b - len * (flat + ry * ry - rr)
			if disc >= 0 then
				local s = (-b - math.sqrt(disc)) / len
				if s >= 0 and s <= 1 and (best == nil or s < best) then
					best = s
				end
			end
		end
	end
	return best
end

-- A ball's step against one body: feet at (x, y, z), crouch fraction `crouch`, `sweep` the arena's
-- ball test. Returns the fraction along the step and the entry point when the body is touched and
-- the touch counts (rules 2 and 3); nil and the step's start otherwise.
function Hit.body(
	sweep: Arena.Sweep,
	p0x: number,
	p0y: number,
	p0z: number,
	p1x: number,
	p1y: number,
	p1z: number,
	x: number,
	y: number,
	z: number,
	crouch: number
): (number?, number, number, number)
	local low, high, r = Body.capsule(crouch)
	local s = Hit.capsule(p0x, p0y, p0z, p1x, p1y, p1z, x, y + low, y + high, z, r)
	if s == nil then
		return nil, p0x, p0y, p0z
	end
	local hx, hy, hz = p0x + (p1x - p0x) * s, p0y + (p1y - p0y) * s, p0z + (p1z - p0z) * s
	if sweep(hx, hy, hz, x, math.clamp(hy, y + low, y + high), z) ~= nil then
		return nil, p0x, p0y, p0z -- something solid stands between the ball and the body's middle
	end
	return s, hx, hy, hz
end

return Hit
