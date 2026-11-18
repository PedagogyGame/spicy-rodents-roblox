--!strict
-- ReplicatedStorage.Shared.Combat.Cover
-- Solid housings a kick or a bite cannot reach through. Combat/PlayRules has no line of sight (a kick reaches 7
-- studs in front whatever stands between), so a squirrel inside an enclosed run could be kicked through its walls:
-- the alley roof's air-handling unit (BRIEF_ADDENDUM D9, owner question Q7: a guard's kick "reaches the louvre but
-- not inside"). A cover is a box in a placed frame (the alley's local frame: X across, Y up, D down-lane, placed as
-- Shared/Attractions/AlleyLayout places it). A body inside a cover cannot be reached from outside it, nor the other
-- way round: between(a, b) is true when one of the two points lies inside a cover the other is not inside.
-- The covers in force are a small registry: the server service that owns a housing adds its boxes when it starts
-- and removes them when it stops (Server/Attractions/RafterService: the vent unit and its duct); PlayRules'
-- kickTarget and biteVictims ask between(). With no cover added (the client, every other spec) nothing changes.
-- Interface: Box; add(box) -> key; remove(key); clear(); list() -> { Box }; inside(box, x, y, z) -> boolean;
--   between(ax, ay, az, bx, by, bz) -> boolean
-- Pure apart from the registry; no engine calls.

export type Place = { x: number, z: number, floorY: number, yaw: number } -- AlleyLayout.Place
export type Box = {
	name: string,
	place: Place,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	d0: number,
	d1: number,
}

local Cover = {}

local boxes: { [number]: Box } = {}
local nextKey = 0

-- add(box) -> key: the box is in force until remove(key).
function Cover.add(box: Box): number
	nextKey += 1
	boxes[nextKey] = table.freeze(table.clone(box))
	return nextKey
end

function Cover.remove(key: number)
	boxes[key] = nil
end

function Cover.clear()
	table.clear(boxes)
end

function Cover.list(): { Box }
	local out = {}
	for _, b in boxes do
		table.insert(out, b)
	end
	return out
end

-- inside(box, x, y, z): the world point lies inside the box (AlleyLayout.toLocal's turn, written out here).
function Cover.inside(box: Box, x: number, y: number, z: number): boolean
	local p = box.place
	local c, s = math.cos(p.yaw), math.sin(p.yaw)
	local dx, dz = x - p.x, z - p.z
	local X = dx * c - dz * s
	local D = -(dx * s + dz * c)
	local Y = y - p.floorY
	return X >= box.x0 and X <= box.x1 and Y >= box.y0 and Y <= box.y1 and D >= box.d0 and D <= box.d1
end

-- between(a, b): a cover stands between the two world points (one is inside it, the other is not).
function Cover.between(ax: number, ay: number, az: number, bx: number, by: number, bz: number): boolean
	for _, box in boxes do
		if Cover.inside(box, ax, ay, az) ~= Cover.inside(box, bx, by, bz) then
			return true
		end
	end
	return false
end

return Cover
