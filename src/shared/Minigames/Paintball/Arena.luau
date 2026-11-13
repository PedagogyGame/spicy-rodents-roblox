--!strict
-- ReplicatedStorage.Shared.Minigames.Paintball.Arena
-- The arena interface of the paintball contract (brief v2 §13; checklist PB-5): what the five-storey
-- TV station IS to every piece of code. FROZEN: no lane edits this file. The arena lane fills in
-- ArenaData.build() beside this file, which returns the `Arena` described here; everybody else only
-- reads it.
--
-- THE FRAME. Every paintball position on the wire, in the match, in the bots and in the collision data
-- is in the ARENA FRAME: the origin is the middle of the ground floor of the arena volume, +y is up,
-- and the frame is the world moved to that origin and turned about Y by the site's yaw. It is a rigid,
-- right-handed frame (a CFrame: CFrame.new(place.x, place.y, place.z) * CFrame.Angles(0, place.yaw, 0)),
-- NOT the site's X/Y/D frame of Shared/Attractions/AlleyLayout (the frame of a minigame site: the
-- station anchors of the Spec, the bake's Kit), which is mirrored in D:
--   arena x = site X,  arena y = site Y,  arena z = 15 - site D   (the arena_origin anchor is at D = 15).
-- toSite / ofSite convert a point; placeOf(site place) is the arena's Place from the site's Place, which
-- is what the server (ServerGame.Ctx.place), the client (ClientGame.Ctx.place, or the `place` handed
-- to ClientGame.watch) and the bake (kit.place) each hold: nobody sends the arena's place.
-- The arena volume is x, z in [-HALF, HALF], y in [0, HEIGHT]; the lobby annex with the pass desk lies
-- outside it on the +z side (z 60..90). Only the code that touches Instances converts, with toWorld /
-- toLocal / dirToWorld / dirToLocal / yawToWorld below; pure code never sees a world coordinate.
--
-- THE VOLUME IS SEALED. No walkable opening joins the lobby and the arena, and no window is open: a
-- ball never leaves the volume, and a body gets in only by the framework's prompt (GATE: the server
-- puts it in its team's spawn room) and out only by Leave, by stepping into an `exits` room, or by
-- being taken out. Nobody who is not in the match is meant to be inside it, and the server makes that
-- true: twice a second it puts anybody it finds in the volume who is not seated at arena.lobby
-- (PaintballService). The lobby may look in through glass (a box like any other: solid to balls and
-- bodies).
--
-- WHAT AN ARENA HOLDS.
--   boxes   flat list, six numbers per box (minX, minY, minZ, maxX, maxY, maxZ): everything SOLID. A
--           ball stops on a box and nowhere else; the bake makes exactly one visible, collidable part
--           per box, the same size in the same place, so a ball stops where a wall is drawn and passes
--           where none is (PB-5). Every surface is axis-aligned, so a splat's normal is one of six faces.
--           Whatever is drawn inside the volume and is not one box's own part must be plainly not
--           solid (a curtain, a decal, a light). A MONITOR inside the volume is the part of a `prop`
--           box, named Arena.MONITOR: never a part of its own in front of a wall.
--   kinds   one KIND code per box (slab, wall, pillar, cover, rail, step, prop), for the bake's looks,
--           the splat's surface and the bots' reading of cover.
--   ramps   the walking surface over each stair flight: an axis-aligned rectangle whose height rises
--           from y0 to y1 along one axis. Bodies walk on ramps (the bake makes one invisible,
--           collidable part per ramp, lying on the steps); balls ignore ramps and hit the `step` boxes
--           under them. A step box's top never rises above the ramp surface over it.
--   spawns, spawnRooms   per team (1, 2): at least RULES.teamMax spawn points inside that team's room
--           (a box of air: the walls round it are boxes like any others). THE SPAWN ROOM HAS RULES
--           (Contract decision 12; the service keeps them with Arena.inRoom on a body's feet point,
--           raised 0.1): a body inside ITS OWN team's room cannot be hit and cannot fire (BIT.safe in
--           the snapshots); a pose inside THE OTHER team's room is refused like a wall. A spawn
--           point's yaw looks towards the room's nearest way out.
--   curtains   per team: one thin box of air filling each doorway of that team's spawn room. The bake
--           makes a part for each (named Arena.CURTAIN .. team, in the team's colour, see-through,
--           CanCollide false, NOT a box: balls and team-mates pass). A seated client sets CanCollide
--           true, on its own screen only, on the OTHER team's curtains, so an honest player is
--           stopped at the door by the engine and the server's refusal is only for a cheat.
--   exits, lobby   rooms inside the volume that end a player's match when stepped into (the way to
--           walk out; may be empty), and the point in the lobby annex where anyone who leaves the
--           match is put.
--   nodes, links, cover   the bots' navigation graph: nodes on the walking surface, links a body can
--           walk in a straight line ("walk": clear at chest height; "stair": along a ramp), and cover
--           spots (a node plus (nx, nz), the horizontal unit vector from the spot towards the side it
--           is sheltered from; low = RAIL_HEIGHT cover that only hides a crouched body).
--   sweep(x0, y0, z0, x1, y1, z1) -> (s?, nx, ny, nz, box)   THE ball test: the first box the segment
--           enters, as the fraction s in [0, 1] along it, the face normal and the box's index (1-based;
--           0 with s = nil when nothing is hit). The predicted ball on the client, the real ball on the
--           server and a bot's line of sight all call this one function, so they cannot disagree.
--           Semantics are those of Ballistics.segmentBox: a segment that starts inside a box reports
--           s = 0 with a zero normal.
--   ground(x, y, z) -> y?   the walking surface under a feet point: the highest box top or ramp
--           surface at (x, z) that is not above y + STEP_UP; nil over a void.
-- Arena.finish(parts) gives `sweep` and `ground` their REFERENCE implementation (a linear scan,
-- exact and slow). The real building has several hundred boxes, so the arena lane must hand back
-- faster ones (a grid) that return the same answers as the reference; consumers always call
-- arena.sweep / arena.ground and never scan `boxes` themselves.
--
-- RULES OF THE BUILDING (Arena.check enforces what it can; every arena must pass it):
--   * five floors FLOOR_HEIGHT apart, an atrium open from the ground to the roof, at least two stair
--     flights between each pair of neighbouring floors (decision D3: one is a choke point);
--   * THE STAIRS GO ON UP: the head of every flight is within STAIR_GAP of the foot of a flight to
--     the next storey, so climbing three storeys is three flights and three short turns, not three
--     walks round the atrium;
--   * rails round the atrium and all low cover are RAIL_HEIGHT high: a standing body's eye sees and
--     shoots over them, a crouched body is wholly hidden, from a ball as from the eye (a ball is its
--     centre line: Hit) (PB-5, PB-9; pinned in the contract spec);
--   * nowhere a body can walk has less than HEADROOM above it and no opening is lower than that, so
--     crouching never changes what a body collides with: crouch changes the eye and the hit shape only;
--   * a body cannot jump a rail (Body.JUMP_HEIGHT < RAIL_HEIGHT): floors are changed by the stairs
--     going up. GOING DOWN, A BODY MAY DROP: a stair's open side, a landing, an edge of the atrium
--     without a rail are all allowed, falling costs nothing and the server does not refuse it
--     (Contract, "who is trusted": height). A rail is cover, not a safety fence;
--   * THE SPAWN ROOMS (decision 12) are on the middle storey (SPAWN_FLOOR), on opposite sides of the
--     building, so no storey is more than two flights from a respawn. Each has at least two ways
--     out (a "walk" link from a node inside it to a node outside it), two of which come out at least
--     EXIT_APART apart with no clear line between them, so one opponent cannot watch both. No
--     navigation node outside a room has a clear line (eye to chest) to a spawn point inside it:
--     nobody is tagged where they appear. From a way out of each room, the walk to the nearest node
--     beside the atrium (within ATRIUM + ATRIUM_SIDE of the building's axis) of EVERY storey is at
--     most SPAWN_REACH studs along the links: under six seconds at a sprint.
-- Interface: types Place, SitePlace, Spawn, Ramp, Room, NavNode, NavLink, Cover, Parts, Arena; constants;
--   PLACE, ORIGIN, DESK, GATE, MODEL, MONITOR, CURTAIN; toWorld, toLocal, dirToWorld, dirToLocal, yawToWorld,
--   yawToLocal, fromSite, placeOf(site) -> Place, toSite(x, y, z) -> (X, Y, D), ofSite(X, Y, D) -> (x, y, z);
--   inVolume(x, y, z, margin?) -> boolean; sweepBoxes, groundAt, rampHeight, inRoom(room, x, y, z,
--   margin?); clearPath(sweep, x0, z0, x1, z1, h) -> boolean; finish(parts) -> Arena; check(arena,
--   teamMax) -> (ok, problems); T (type witnesses)

local Ballistics = require("../../Paintball/Ballistics")

-- where the arena origin is in the world, and how the frame is turned
export type Place = { x: number, y: number, z: number, yaw: number }
-- a minigame site's Place (Shared/Minigames/GameSpec.Place: the frame of AlleyLayout.toWorld)
export type SitePlace = { x: number, z: number, floorY: number, yaw: number }
export type Spawn = { x: number, y: number, z: number, yaw: number }
export type Ramp = {
	minX: number,
	minZ: number,
	maxX: number,
	maxZ: number,
	y0: number, -- height at the low end
	y1: number, -- height at the high end
	axis: "x" | "z", -- the axis it rises along
	dir: number, -- 1: rises towards +axis; -1: towards -axis
}
export type Room = { minX: number, minY: number, minZ: number, maxX: number, maxY: number, maxZ: number }
export type NavNode = {
	id: number, -- its index in `nodes`
	x: number,
	y: number, -- on the walking surface
	z: number,
	floor: number, -- 0..FLOORS - 1 (a node on a stair landing belongs to the floor it is level with)
	kind: "open" | "cover" | "stair" | "spawn",
	team: number, -- the team whose spawn room it is in, else 0
}
export type NavLink = { a: number, b: number, cost: number, kind: "walk" | "stair" }
export type Cover = { node: number, nx: number, nz: number, low: boolean }
export type Sweep = (
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number
) -> (number?, number, number, number, number)
export type Ground = (x: number, y: number, z: number) -> number?

-- what the arena lane authors
export type Parts = {
	boxes: { number },
	kinds: { number },
	ramps: { Ramp },
	spawns: { { Spawn } },
	spawnRooms: { Room },
	curtains: { { Room } },
	exits: { Room },
	lobby: Spawn,
	nodes: { NavNode },
	links: { NavLink },
	cover: { Cover },
	sweep: Sweep?, -- a faster ball test with the reference's answers; nil = the reference
	ground: Ground?,
}

-- what everybody reads
export type Arena = {
	half: number,
	floors: number,
	floorHeight: number,
	height: number,
	atrium: number,
	boxes: { number },
	kinds: { number },
	ramps: { Ramp },
	spawns: { { Spawn } },
	spawnRooms: { Room },
	curtains: { { Room } },
	exits: { Room },
	lobby: Spawn,
	nodes: { NavNode },
	links: { NavLink },
	cover: { Cover },
	sweep: Sweep,
	ground: Ground,
}

local Arena = {}

Arena.HALF = 60 -- the arena volume is 120 x 120 studs
Arena.FLOORS = 5
Arena.FLOOR_HEIGHT = 14 -- floor to floor
Arena.HEIGHT = 70 -- FLOORS * FLOOR_HEIGHT: the underside of the roof
Arena.ATRIUM = 15 -- half the 30 x 30 atrium
Arena.RAIL_HEIGHT = 3.4 -- atrium rails and low cover, above the floor they stand on
Arena.HEADROOM = 6.5 -- least clear height over any walking surface and through any opening
Arena.STEP_UP = 1.2 -- the tallest ledge a walking body climbs without jumping
Arena.CHEST = 2.5 -- the height above the feet at which "walk" links and movement are tested for walls
Arena.EYE = 4.5 -- a standing eye above the feet (Body.STAND_EYE; pinned equal by the contract spec)
Arena.SPAWN_FLOOR = 2 -- the storey (0..FLOORS - 1) both spawn rooms are on: the middle one
Arena.SPAWN_REACH = 130 -- studs along the links from a spawn room's way out to the atrium's side of any storey
Arena.ATRIUM_SIDE = 10 -- a node within ATRIUM + this of the building's axis (in x and in z) is beside the atrium
Arena.EXIT_APART = 20 -- two ways out of a spawn room come out at least this far apart
Arena.STAIR_GAP = 12 -- the head of a flight is within this of the foot of a flight to the next storey
Arena.AUDIENCE_MARGIN = 40 -- studs round the arena volume inside which a player is in the audience
Arena.KIND = table.freeze({ slab = 1, wall = 2, pillar = 3, cover = 4, rail = 5, step = 6, prop = 7 })

-- The arena_origin anchor of f3_tv_station in the site's frame (data/expansion.json: at [0, 0, 15]).
Arena.ORIGIN = table.freeze({ x = 0, y = 0, d = 15 })
-- Where that puts the arena in the world as the data stands (generated/Expansion `world`): the default
-- for code that has no site Place to hand (a bare spec). Everything in the game derives its place
-- with placeOf from the site's own Place. Pinned against generated/Expansion by the contract spec.
Arena.PLACE = table.freeze({ x = 2080, y = 8.6, z = -905, yaw = 0 }) :: Place
-- The pass desk, in the arena frame (site anchor pass_desk at X -20, D -62): the second prompt.
Arena.DESK = table.freeze({ x = -20, y = 0, z = 77, yaw = 0 }) :: Spawn
-- The arena door in the lobby (site X 0, D -47): the station's own prompt, "Join the match".
Arena.GATE = table.freeze({ x = 0, y = 0, z = 62, yaw = 0 }) :: Spawn
-- The bake's one sub-model under the site's Model (Workspace.Attractions.f3_tv_station). It is the
-- arena's "furniture" in the framework's sense: the server's Table is inert on a site without it.
Arena.MODEL = "PaintballArena"
-- The name of every part under that model that is a monitor (one in the lobby, old sets about the
-- floors): the bake makes them, the server puts the phase, the clock and both scores on each. Inside
-- the volume a monitor is the one part of a `prop` box (see "what an arena holds").
Arena.MONITOR = "Monitor"
-- The parts in the doorways of a spawn room are named CURTAIN .. team: "Curtain1", "Curtain2".
Arena.CURTAIN = "Curtain"

function Arena.toWorld(place: Place, x: number, y: number, z: number): (number, number, number)
	local c, s = math.cos(place.yaw), math.sin(place.yaw)
	return place.x + x * c + z * s, place.y + y, place.z - x * s + z * c
end

function Arena.toLocal(place: Place, wx: number, wy: number, wz: number): (number, number, number)
	local c, s = math.cos(place.yaw), math.sin(place.yaw)
	local dx, dz = wx - place.x, wz - place.z
	return dx * c - dz * s, wy - place.y, dx * s + dz * c
end

function Arena.dirToWorld(place: Place, dx: number, dy: number, dz: number): (number, number, number)
	local c, s = math.cos(place.yaw), math.sin(place.yaw)
	return dx * c + dz * s, dy, -dx * s + dz * c
end

function Arena.dirToLocal(place: Place, wx: number, wy: number, wz: number): (number, number, number)
	local c, s = math.cos(place.yaw), math.sin(place.yaw)
	return wx * c - wz * s, wy, wx * s + wz * c
end

local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- A body's yaw (Body.look) is an angle about Y in the frame it is given in.
function Arena.yawToWorld(place: Place, yaw: number): number
	return wrap(yaw + place.yaw)
end

function Arena.yawToLocal(place: Place, worldYaw: number): number
	return wrap(worldYaw - place.yaw)
end

-- The arena's Place from a site in the AlleyLayout frame ({ x, z, floorY, yaw }) and the arena_origin
-- anchor's (X, Y, D) in it. The arena frame keeps the site's yaw.
function Arena.fromSite(site: SitePlace, X: number, Y: number, D: number): Place
	local c, s = math.cos(site.yaw), math.sin(site.yaw)
	return { x = site.x + X * c - D * s, y = site.floorY + Y, z = site.z - X * s - D * c, yaw = site.yaw }
end

-- The arena's Place from the site's own (the framework's ctx.place on either side; the bake's).
function Arena.placeOf(site: SitePlace): Place
	return Arena.fromSite(site, Arena.ORIGIN.x, Arena.ORIGIN.y, Arena.ORIGIN.d)
end

-- A point of the arena frame in the site's frame (what a StationDef and the bake's Kit take), and back.
function Arena.toSite(x: number, y: number, z: number): (number, number, number)
	return x + Arena.ORIGIN.x, y + Arena.ORIGIN.y, Arena.ORIGIN.d - z
end

function Arena.ofSite(X: number, Y: number, D: number): (number, number, number)
	return X - Arena.ORIGIN.x, Y - Arena.ORIGIN.y, Arena.ORIGIN.d - D
end

-- Is a point inside the arena volume, grown by `margin` studs on every side?
function Arena.inVolume(x: number, y: number, z: number, margin: number?): boolean
	local m = margin or 0
	local edge = Arena.HALF + m
	return x >= -edge and x <= edge and z >= -edge and z <= edge and y >= -m and y <= Arena.HEIGHT + m
end

-- REFERENCE ball test: the first of `boxes` the segment enters (linear scan).
function Arena.sweepBoxes(
	boxes: { number },
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number
): (number?, number, number, number, number)
	local best: number? = nil
	local bnx, bny, bnz, index = 0, 0, 0, 0
	for k = 1, #boxes, 6 do
		local s, nx, ny, nz = Ballistics.segmentBox(
			x0,
			y0,
			z0,
			x1,
			y1,
			z1,
			boxes[k],
			boxes[k + 1],
			boxes[k + 2],
			boxes[k + 3],
			boxes[k + 4],
			boxes[k + 5]
		)
		if s ~= nil and (best == nil or s < best) then
			best, bnx, bny, bnz, index = s, nx, ny, nz, (k + 5) // 6
		end
	end
	return best, bnx, bny, bnz, index
end

-- The height of a ramp's surface at (x, z); nil outside its rectangle.
function Arena.rampHeight(r: Ramp, x: number, z: number): number?
	if x < r.minX or x > r.maxX or z < r.minZ or z > r.maxZ then
		return nil
	end
	local a: number
	if r.axis == "x" then
		a = (x - r.minX) / (r.maxX - r.minX)
	else
		a = (z - r.minZ) / (r.maxZ - r.minZ)
	end
	if r.dir < 0 then
		a = 1 - a
	end
	return r.y0 + (r.y1 - r.y0) * a
end

-- REFERENCE walking surface under a feet point (linear scan).
function Arena.groundAt(boxes: { number }, ramps: { Ramp }, x: number, y: number, z: number): number?
	local limit = y + Arena.STEP_UP
	local best: number? = nil
	for k = 1, #boxes, 6 do
		if x >= boxes[k] and x <= boxes[k + 3] and z >= boxes[k + 2] and z <= boxes[k + 5] then
			local top = boxes[k + 4]
			if top <= limit and (best == nil or top > best) then
				best = top
			end
		end
	end
	for _, r in ramps do
		local h = Arena.rampHeight(r, x, z)
		if h ~= nil and h <= limit and (best == nil or h > best) then
			best = h
		end
	end
	return best
end

-- Is a point inside a room? `margin` grows the room sideways (in x and z) by that many studs.
function Arena.inRoom(room: Room, x: number, y: number, z: number, margin: number?): boolean
	local m = margin or 0
	return x >= room.minX - m
		and x <= room.maxX + m
		and y >= room.minY
		and y <= room.maxY
		and z >= room.minZ - m
		and z <= room.maxZ + m
end

-- Could a body have got from (x0, z0) to (x1, z1) without passing through a box? True when the
-- straight line between them at height h is clear, or either L-shaped path is (along x then along z,
-- or along z then along x): every solid is an axis-aligned box, so a body that walked round a corner
-- while a pose or two were lost has walked one of the two Ls. `sweep` is the arena's ball test; h is
-- an arena-frame height: for a move, Arena.CHEST above the HIGHER of the two feet points; for a
-- shot's origin, the origin's own height.
function Arena.clearPath(sweep: Sweep, x0: number, z0: number, x1: number, z1: number, h: number): boolean
	if sweep(x0, h, z0, x1, h, z1) == nil then
		return true
	end
	if sweep(x0, h, z0, x1, h, z0) == nil and sweep(x1, h, z0, x1, h, z1) == nil then
		return true
	end
	return sweep(x0, h, z0, x0, h, z1) == nil and sweep(x0, h, z1, x1, h, z1) == nil
end

-- The Arena everybody reads, from what the arena lane authored. Missing queries get the reference.
function Arena.finish(parts: Parts): Arena
	local boxes, ramps = parts.boxes, parts.ramps
	local sweep: Sweep = parts.sweep
		or function(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number)
			return Arena.sweepBoxes(boxes, x0, y0, z0, x1, y1, z1)
		end
	local ground: Ground = parts.ground
		or function(x: number, y: number, z: number): number?
			return Arena.groundAt(boxes, ramps, x, y, z)
		end
	return {
		half = Arena.HALF,
		floors = Arena.FLOORS,
		floorHeight = Arena.FLOOR_HEIGHT,
		height = Arena.HEIGHT,
		atrium = Arena.ATRIUM,
		boxes = boxes,
		kinds = parts.kinds,
		ramps = ramps,
		spawns = parts.spawns,
		spawnRooms = parts.spawnRooms,
		curtains = parts.curtains,
		exits = parts.exits,
		lobby = parts.lobby,
		nodes = parts.nodes,
		links = parts.links,
		cover = parts.cover,
		sweep = sweep,
		ground = ground,
	}
end

-- Every arena must pass this (the contract spec runs it on ArenaData.build(); the arena lane keeps it
-- passing on the real building). `teamMax` is Contract.Rules.teamMax, passed in so this file needs
-- nothing but Ballistics.
function Arena.check(arena: Arena, teamMax: number): (boolean, { string })
	local bad: { string } = {}
	local function fail(text: string)
		if #bad < 40 then
			table.insert(bad, text)
		end
	end
	local boxes, kinds = arena.boxes, arena.kinds
	local n = #boxes // 6
	if #boxes % 6 ~= 0 then
		fail(`boxes holds {#boxes} numbers, not a multiple of six`)
	end
	if #kinds ~= n then
		fail(`{#kinds} kinds for {n} boxes`)
	end
	local edge = Arena.HALF + 2
	local rails: { [number]: number } = {}
	for i = 1, n do
		local k = (i - 1) * 6
		local x0, y0, z0, x1, y1, z1 =
			boxes[k + 1], boxes[k + 2], boxes[k + 3], boxes[k + 4], boxes[k + 5], boxes[k + 6]
		if not (x0 < x1 and y0 < y1 and z0 < z1) then
			fail(`box {i} is empty or inside out`)
		elseif x0 < -edge or x1 > edge or z0 < -edge or z1 > edge or y0 < -2 or y1 > Arena.HEIGHT + 2 then
			fail(`box {i} is outside the arena volume`)
		end
		local kind = kinds[i]
		if kind == nil or kind < 1 or kind > 7 or kind % 1 ~= 0 then
			fail(`box {i} has no KIND`)
		elseif kind == Arena.KIND.rail then
			local floor = math.floor(y0 / Arena.FLOOR_HEIGHT + 0.5)
			rails[floor] = (rails[floor] or 0) + 1
			if math.abs((y1 - floor * Arena.FLOOR_HEIGHT) - Arena.RAIL_HEIGHT) > 0.05 then
				fail(`rail box {i} is not RAIL_HEIGHT above its floor`)
			end
		end
	end
	for f = 1, Arena.FLOORS - 1 do
		if (rails[f] or 0) == 0 then
			fail(`floor {f} has no atrium rail`)
		end
	end
	for i, r in arena.ramps do
		if not (r.minX < r.maxX and r.minZ < r.maxZ and r.y0 < r.y1) then
			fail(`ramp {i} is empty or does not rise`)
		end
		if (r.axis ~= "x" and r.axis ~= "z") or (r.dir ~= 1 and r.dir ~= -1) then
			fail(`ramp {i} has a bad axis or dir`)
		end
	end
	for team = 1, 2 do
		local list = arena.spawns[team]
		local room = arena.spawnRooms[team]
		if list == nil or room == nil or #list < teamMax then
			fail(`team {team} needs a spawn room and at least {teamMax} spawn points`)
		else
			for i, sp in list do
				if not Arena.inRoom(room, sp.x, sp.y + 0.1, sp.z) then
					fail(`team {team} spawn {i} is outside its room`)
				end
				local g = arena.ground(sp.x, sp.y, sp.z)
				if g == nil or math.abs(g - sp.y) > 0.05 then
					fail(`team {team} spawn {i} is not on the floor`)
				end
				if arena.sweep(sp.x, sp.y + 0.2, sp.z, sp.x, sp.y + Arena.HEADROOM, sp.z) ~= nil then
					fail(`team {team} spawn {i} is inside something solid`)
				end
			end
		end
	end
	local lobby = arena.lobby
	if math.abs(lobby.x) <= Arena.HALF and math.abs(lobby.z) <= Arena.HALF then
		fail("the lobby point is inside the arena volume")
	end
	-- the navigation graph
	local nodes, links = arena.nodes, arena.links
	local perFloor: { [number]: number } = {}
	for i, node in nodes do
		if node.id ~= i then
			fail(`node {i} has id {node.id}`)
		end
		perFloor[node.floor] = (perFloor[node.floor] or 0) + 1
		local g = arena.ground(node.x, node.y, node.z)
		if g == nil or math.abs(g - node.y) > 0.05 then
			fail(`node {i} is not on the walking surface`)
		end
	end
	for f = 0, Arena.FLOORS - 1 do
		if (perFloor[f] or 0) == 0 then
			fail(`floor {f} has no navigation node`)
		end
	end
	local adjacent: { [number]: { number } } = {}
	local stairs: { [number]: number } = {}
	for i, link in links do
		local a, b = nodes[link.a], nodes[link.b]
		if a == nil or b == nil or link.a == link.b then
			fail(`link {i} names a missing node`)
			continue
		end
		adjacent[link.a] = adjacent[link.a] or {}
		adjacent[link.b] = adjacent[link.b] or {}
		table.insert(adjacent[link.a], link.b)
		table.insert(adjacent[link.b], link.a)
		if link.kind == "stair" then
			if math.abs(a.floor - b.floor) ~= 1 then
				fail(`stair link {i} does not join neighbouring floors`)
			end
			local low = math.min(a.floor, b.floor)
			stairs[low] = (stairs[low] or 0) + 1
		elseif link.kind == "walk" then
			if a.floor ~= b.floor then
				fail(`walk link {i} changes floor`)
			end
			local c = Arena.CHEST
			if arena.sweep(a.x, a.y + c, a.z, b.x, b.y + c, b.z) ~= nil then
				fail(`walk link {i} ({link.a} to {link.b}) goes through something solid`)
			end
		else
			fail(`link {i} has a bad kind`)
		end
	end
	for f = 0, Arena.FLOORS - 2 do
		if (stairs[f] or 0) < 2 then
			fail(`floors {f} and {f + 1} need two stair links, found {stairs[f] or 0}`)
		end
	end
	if #nodes > 0 then
		local seen: { [number]: boolean } = { [1] = true }
		local queue, reached = { 1 }, 1
		while #queue > 0 do
			local at = table.remove(queue) :: number
			local list = adjacent[at]
			if list then
				for _, to in list do
					if not seen[to] then
						seen[to] = true
						reached += 1
						table.insert(queue, to)
					end
				end
			end
		end
		if reached ~= #nodes then
			fail(`the navigation graph is in pieces: {reached} of {#nodes} nodes reached from node 1`)
		end
	end
	for i, c in arena.cover do
		if nodes[c.node] == nil then
			fail(`cover {i} names a missing node`)
		elseif math.abs(c.nx * c.nx + c.nz * c.nz - 1) > 1e-3 then
			fail(`cover {i} has no unit direction`)
		end
	end
	-- the stairs go on up: the head of a flight is near the foot of a flight to the next storey
	for i, link in links do
		local a, b = nodes[link.a], nodes[link.b]
		if link.kind ~= "stair" or a == nil or b == nil then
			continue
		end
		local head = if a.floor > b.floor then a else b
		if head.floor >= Arena.FLOORS - 1 then
			continue
		end
		local near = false
		for _, other in links do
			local c, d = nodes[other.a], nodes[other.b]
			if other.kind == "stair" and c ~= nil and d ~= nil then
				local foot = if c.floor < d.floor then c else d
				local dist = math.sqrt((foot.x - head.x) ^ 2 + (foot.y - head.y) ^ 2 + (foot.z - head.z) ^ 2)
				if foot.floor == head.floor and dist <= Arena.STAIR_GAP then
					near = true
					break
				end
			end
		end
		if not near then
			fail(`stair link {i} ends more than {Arena.STAIR_GAP} studs from the next flight up`)
		end
	end
	-- the spawn rooms (decision 12)
	local rooms = arena.spawnRooms
	local roomY = Arena.SPAWN_FLOOR * Arena.FLOOR_HEIGHT
	if rooms[1] ~= nil and rooms[2] ~= nil then
		local ax, az = (rooms[1].minX + rooms[1].maxX) / 2, (rooms[1].minZ + rooms[1].maxZ) / 2
		local bx, bz = (rooms[2].minX + rooms[2].maxX) / 2, (rooms[2].minZ + rooms[2].maxZ) / 2
		if math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2) < Arena.HALF then
			fail("the spawn rooms are not on opposite sides of the building")
		end
	end
	for team = 1, 2 do
		local room = rooms[team]
		local list = arena.spawns[team]
		if room == nil or list == nil then
			continue
		end
		if math.abs(room.minY - roomY) > 0.05 then
			fail(`team {team}'s spawn room is not on the middle storey`)
		end
		-- its ways out: walk links from a node of its own to a node of nobody's
		local outs: { NavNode } = {}
		for _, link in links do
			local a, b = nodes[link.a], nodes[link.b]
			if link.kind == "walk" and a ~= nil and b ~= nil then
				if a.team == team and b.team == 0 then
					table.insert(outs, b)
				elseif b.team == team and a.team == 0 then
					table.insert(outs, a)
				end
			end
		end
		local apart = false
		for i = 1, #outs do
			for j = i + 1, #outs do
				local a, b = outs[i], outs[j]
				local far = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) >= Arena.EXIT_APART
				local e = Arena.EYE
				if far and arena.sweep(a.x, a.y + e, a.z, b.x, b.y + e, b.z) ~= nil then
					apart = true
				end
			end
		end
		if not apart then
			fail(`team {team}'s spawn room needs two ways out that one opponent cannot watch together`)
		end
		local curtains = arena.curtains[team]
		if curtains == nil or #curtains < 2 then
			fail(`team {team}'s spawn room needs a curtain in each doorway`)
		end
		-- nobody outside sees a spawn point
		local seen = 0
		for _, node in nodes do
			if node.team ~= team then
				for _, sp in list do
					local clearLine = arena.sweep(node.x, node.y + Arena.EYE, node.z, sp.x, sp.y + Arena.CHEST, sp.z)
						== nil
					if clearLine then
						seen += 1
					end
				end
			end
		end
		if seen > 0 then
			fail(`team {team}'s spawn points can be seen from outside the room ({seen} clear lines from nodes)`)
		end
		-- every storey is near: the cheapest walk from a way out to a node beside the atrium on each
		local cost: { [number]: number } = {}
		local open: { number } = {}
		for _, node in outs do
			if cost[node.id] == nil then
				cost[node.id] = 0
				table.insert(open, node.id)
			end
		end
		while #open > 0 do
			local bestAt = 1
			for k = 2, #open do
				if cost[open[k]] < cost[open[bestAt]] then
					bestAt = k
				end
			end
			local at = open[bestAt]
			open[bestAt] = open[#open]
			open[#open] = nil
			for _, link in links do
				local to = if link.a == at then link.b elseif link.b == at then link.a else nil
				if to ~= nil and nodes[to] ~= nil then
					local c = cost[at] + link.cost
					local had = cost[to]
					if had == nil then
						cost[to] = c
						table.insert(open, to)
					elseif c < had then
						cost[to] = c
						if table.find(open, to) == nil then
							table.insert(open, to)
						end
					end
				end
			end
		end
		local side = Arena.ATRIUM + Arena.ATRIUM_SIDE
		for f = 0, Arena.FLOORS - 1 do
			local nearest = math.huge
			for _, node in nodes do
				local c = cost[node.id]
				if c ~= nil and node.floor == f and math.abs(node.x) <= side and math.abs(node.z) <= side then
					nearest = math.min(nearest, c)
				end
			end
			if nearest == math.huge then
				fail(`floor {f} cannot be reached from team {team}'s spawn room`)
			elseif nearest > Arena.SPAWN_REACH then
				fail(`floor {f} is {math.floor(nearest)} studs from team {team}'s spawn room: over {Arena.SPAWN_REACH}`)
			end
		end
	end
	return #bad == 0, bad
end

-- Type witnesses (Contract, HOW TO IMPORT): from another root, type Arena = typeof(ArenaModule.T.Arena).
Arena.T = ({} :: any) :: {
	Place: Place,
	SitePlace: SitePlace,
	Spawn: Spawn,
	Ramp: Ramp,
	Room: Room,
	NavNode: NavNode,
	NavLink: NavLink,
	Cover: Cover,
	Parts: Parts,
	Arena: Arena,
}

return Arena
