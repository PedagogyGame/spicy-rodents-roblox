--!strict
-- ReplicatedStorage.Shared.Stealth.RafterSense
-- What the server can tell about a squirrel over the alley's lanes from where its body is (BRIEF_ADDENDUM D9; lane
-- L5). A held squirrel's motor runs on its player's computer: the server sees only the body, so it works out the
-- rest here, for Stealth/RafterWatch: which rafter (or the vent) the feet are on and how far along, how fast the
-- body moves, and whether it just came down on a beam out of a leap.
--   locate(X, Y, D)  the rafter route (or the vent duct 9107) whose line passes within C.across studs of the feet
--                    point level and C.updown vertically (routes draw the body on the line: kind fence, and the
--                    vent with visualOffset 0), with its arc-length t; nil off every one.
--   sense(state, id, X, Y, D, dt) -> RafterWatch.Squirrel?  one tick for one body. nil when the body is neither on
--                    one of those routes nor in the air of the roof space (the squirrel left the rafters: its watch
--                    ends). speed is the distance moved since its last tick over dt; creeping is any speed up to
--                    RafterWatch.C.stalkSpeed (the rail stalk is 3 st/s and nothing else on a beam is that slow, so
--                    the Ctrl key the server cannot see is read from the speed). In the air between beams (a leap)
--                    the body still counts on the beam it left (a leap does not wipe the meter); the first tick on
--                    a beam after the air is a landing (`landed`). In the vent, away from its mouths, it is hidden
--                    (Routes/Enclosure.hidden).
-- Everything in the alley's local frame (Shared/Attractions/AlleyLayout: X across, Y up from the floor, D down the
-- lane), the FEET point (the caller takes the body's hip off its root).
-- Interface: C; ROUTES (the ids it knows); locate(X, Y, D) -> (routeId?, t); inRoofSpace(X, Y, D) -> boolean;
--   new() -> State; sense(state, id, X, Y, D, dt) -> RafterWatch.Squirrel?; forget(state, id)
-- Pure.

local AlleyRoof = require("../Attractions/AlleyRoof")
local Curve = require("../Routes/Curve")
local Enclosure = require("../Routes/Enclosure")
local RafterWatch = require("./RafterWatch")

local RafterSense = {}

RafterSense.C = {
	across = 0.9, -- level distance from the route's line that still counts as on it (the drawn body eases after it)
	updown = 1.0, -- vertical
	step = 0.5, -- studs between the samples the lines are cut into
	-- the roof space over the lanes (AlleyRoof.HALL_ROOF), from under the light rails to the deck
	airY0 = 8.5,
	airY1 = AlleyRoof.HALL_ROOF.deckY0,
}
local C = RafterSense.C

type Seg = { ax: number, ay: number, ad: number, bx: number, by: number, bd: number, t0: number, t1: number }
type Line = { id: number, segs: { Seg }, x0: number, x1: number, y0: number, y1: number, d0: number, d1: number }

-- The routes it knows: every rafter (AlleyRoof.isRafter) and the vent duct.
local lines: { Line } = {}
RafterSense.ROUTES = {} :: { number }
local vent: Enclosure.RouteLike
do
	for _, r in AlleyRoof.routes() do
		if not (AlleyRoof.isRafter(r.id) or r.id == AlleyRoof.VENT) then
			continue
		end
		local curve = Curve.fromArrays(r.points)
		local length = curve:getLength()
		local n = math.max(1, math.ceil(length / C.step))
		local line: Line = {
			id = r.id,
			segs = {},
			x0 = math.huge,
			x1 = -math.huge,
			y0 = math.huge,
			y1 = -math.huge,
			d0 = math.huge,
			d1 = -math.huge,
		}
		local prev = curve:getPointAt(0)
		for i = 1, n do
			local p = curve:getPointAt(i / n)
			table.insert(
				line.segs,
				{ ax = prev.x, ay = prev.y, ad = prev.z, bx = p.x, by = p.y, bd = p.z, t0 = (i - 1) / n, t1 = i / n }
			)
			for _, q in { prev, p } do
				line.x0, line.x1 = math.min(line.x0, q.x), math.max(line.x1, q.x)
				line.y0, line.y1 = math.min(line.y0, q.y), math.max(line.y1, q.y)
				line.d0, line.d1 = math.min(line.d0, q.z), math.max(line.d1, q.z)
			end
			prev = p
		end
		-- (the vent last: where the boot meets chord 9120 the chord wins a tie)
		table.insert(lines, if r.id == AlleyRoof.VENT then #lines + 1 else 1, line)
		table.insert(RafterSense.ROUTES, r.id)
		if r.id == AlleyRoof.VENT then
			vent = {
				id = r.id,
				kind = r.kind,
				length = length,
				enclosure = Enclosure.fromRecord((r.enclosure :: any) :: Enclosure.Record),
			}
		end
	end
end

-- locate(X, Y, D): the route the feet are on and how far along it (arc-length t), or nil.
function RafterSense.locate(X: number, Y: number, D: number): (number?, number)
	local bestId, bestT, best = nil :: number?, 0, math.huge
	for _, line in lines do
		if
			X < line.x0 - C.across
			or X > line.x1 + C.across
			or D < line.d0 - C.across
			or D > line.d1 + C.across
			or Y < line.y0 - C.updown
			or Y > line.y1 + C.updown
		then
			continue
		end
		for _, s in line.segs do
			-- the nearest point of the segment, level (the line's height there is then compared on its own)
			local ex, ey, ed = s.bx - s.ax, s.by - s.ay, s.bd - s.ad
			local len2 = ex * ex + ed * ed
			local u = if len2 > 1e-9 then math.clamp(((X - s.ax) * ex + (D - s.ad) * ed) / len2, 0, 1) else 0
			local px, py, pd = s.ax + ex * u, s.ay + ey * u, s.ad + ed * u
			local level = math.sqrt((X - px) ^ 2 + (D - pd) ^ 2)
			local dy = math.abs(Y - py)
			if level <= C.across and dy <= C.updown then
				local score = level + dy
				if score < best then
					best, bestId, bestT = score, line.id, s.t0 + (s.t1 - s.t0) * u
				end
			end
		end
	end
	return bestId, bestT
end

-- In the air of the roof space over the lanes (where a leap between beams flies).
function RafterSense.inRoofSpace(X: number, Y: number, D: number): boolean
	local h = AlleyRoof.HALL_ROOF
	return X >= h.x0 and X <= h.x1 and D >= h.d0 and D <= h.d1 and Y >= C.airY0 and Y <= C.airY1
end

type Track = { X: number, Y: number, D: number, routeId: number?, beam: number? }
export type State = { tracks: { [string]: Track } }

function RafterSense.new(): State
	return { tracks = {} }
end

function RafterSense.forget(state: State, id: string)
	state.tracks[id] = nil
end

-- sense(state, id, X, Y, D, dt): this tick's RafterWatch squirrel for the body `id` (feet at X, Y, D), or nil.
function RafterSense.sense(state: State, id: string, X: number, Y: number, D: number, dt: number): RafterWatch.Squirrel?
	local prev = state.tracks[id]
	local routeId, t = RafterSense.locate(X, Y, D)
	local air = routeId == nil and RafterSense.inRoofSpace(X, Y, D)
	-- the beam it counts on: the one it is on, or in the air the one it left
	local beam = if routeId and AlleyRoof.isRafter(routeId) then routeId elseif air and prev then prev.beam else nil
	if routeId == nil and beam == nil then
		state.tracks[id] = nil
		return nil
	end
	local speed = 0
	if prev and dt > 0 then
		speed = math.sqrt((X - prev.X) ^ 2 + (Y - prev.Y) ^ 2 + (D - prev.D) ^ 2) / dt
	end
	local landed = prev ~= nil and prev.routeId == nil and routeId ~= nil and AlleyRoof.isRafter(routeId)
	state.tracks[id] = { X = X, Y = Y, D = D, routeId = routeId, beam = beam }
	return {
		id = id,
		routeId = if routeId == AlleyRoof.VENT then routeId else beam,
		X = X,
		Y = Y,
		D = D,
		speed = speed,
		focus = speed <= RafterWatch.C.stalkSpeed,
		sprint = false, -- (RafterWatch reads a sprint from the speed)
		landed = landed,
		hidden = routeId == AlleyRoof.VENT and Enclosure.hidden(vent, t),
	}
end

return RafterSense
