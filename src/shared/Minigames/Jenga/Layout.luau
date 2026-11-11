--!strict
-- ReplicatedStorage.Shared.Minigames.Jenga.Layout
-- Giant Jenga's geometry in one place (brief v2 §13a: "a playable four-foot giant Jenga on a deck table";
-- checklist JEN-R1, C18): the blocks, the tower, the deck table it stands on and where the players stand. The
-- model (Tower, Stability, Physics, Fall), the bake and the client all read these numbers, so what is drawn is
-- what is simulated.
-- Table frame (studs): the origin is the middle of the table top; Y is up from the table top (the deck is at
-- -TABLE_H); level 1 lies on the table with its blocks running along X, level 2 runs along Z, and so on.
-- Scale: 3.8 studs to the metre, as the alley's hardware (a person stands about 5 studs tall): 18 levels of
-- 0.26 are 4.68 studs, a hair over four feet.
-- Pure. Interface: the constants below; alongX(level) -> boolean; levelY(level) -> centre height;
--   slotOffset(slot) -> across offset; slotCentre(level, slot) -> (x, y, z); seat(i) -> (x, z, yaw);
--   onTable(x, z) -> boolean; toWorld(place, x, y, z) -> (wx, wy, wz); yawToWorld(place, yaw) -> world yaw

local Layout = {}

export type Place = { x: number, y: number, z: number, yaw: number } -- world position of the table-top middle

Layout.BLOCKS = 54
Layout.PER_LEVEL = 3
Layout.START_LEVELS = 18

Layout.BLOCK_L = 1.32 -- length: exactly three widths, so three blocks make a square
Layout.BLOCK_W = 0.44
Layout.BLOCK_T = 0.26 -- thickness (the real 1.5 : 2.5 : 7.5 proportions)
Layout.TOWER_H = Layout.START_LEVELS * Layout.BLOCK_T -- 4.68 studs = 1.23 m = four feet

Layout.GRAVITY = 37.3 -- studs/s^2: 9.81 m/s^2 at this scale, so a toppling tower takes as long as a real one

-- The deck table: low and square, so the top of the starting tower is at about chest height.
Layout.TABLE_TOP = 4.0 -- side of the square top
Layout.TABLE_HALF = Layout.TABLE_TOP / 2
Layout.TABLE_H = 1.2 -- table top above the deck boards
Layout.DECK_HALF_X = 25 -- the raised deck is 50 x 40 with the table in the middle (data/expansion.json)
Layout.DECK_HALF_Z = 20
Layout.RAIL = 9 -- no block is ever drawn further than this from the table middle (C10)

-- Where the (up to four) players stand, one on each side of the table, facing the tower.
Layout.SEATS = 4
Layout.STAND = 3.3 -- distance from the table middle
Layout.VIEW_RADIUS = 7.5 -- the camera's walk round the tower
Layout.LEAVE_RADIUS = 70

function Layout.alongX(level: number): boolean
	return level % 2 == 1
end

function Layout.levelY(level: number): number
	return (level - 0.5) * Layout.BLOCK_T
end

function Layout.slotOffset(slot: number): number
	return (slot - 2) * Layout.BLOCK_W
end

-- The centre of a block sitting square in its slot.
function Layout.slotCentre(level: number, slot: number): (number, number, number)
	local off = Layout.slotOffset(slot)
	if Layout.alongX(level) then
		return 0, Layout.levelY(level), off
	end
	return off, Layout.levelY(level), 0
end

-- seat(i): where player i stands (table frame) and the yaw that faces the tower. Seats 1 and 3 look along X
-- (at the ends of the odd levels), 2 and 4 along Z.
function Layout.seat(i: number): (number, number, number)
	local k = (i - 1) % 4
	if k == 0 then
		return -Layout.STAND, 0, 0
	elseif k == 1 then
		return 0, -Layout.STAND, math.pi / 2
	elseif k == 2 then
		return Layout.STAND, 0, math.pi
	end
	return 0, Layout.STAND, -math.pi / 2
end

function Layout.onTable(x: number, z: number): boolean
	return math.abs(x) <= Layout.TABLE_HALF and math.abs(z) <= Layout.TABLE_HALF
end

function Layout.toWorld(place: Place, x: number, y: number, z: number): (number, number, number)
	local c, s = math.cos(place.yaw), math.sin(place.yaw)
	return place.x + x * c + z * s, place.y + y, place.z - x * s + z * c
end

function Layout.yawToWorld(place: Place, yaw: number): number
	return yaw + place.yaw
end

return Layout
