--!strict
-- ReplicatedStorage.Shared.Minigames.Paintball.ArenaDataPlan
-- THE BUILDING (checklist PB-5; decision D3): WBLW Channel 7, an abandoned five-storey TV station, as
-- a list of axis-aligned boxes. OWNED BY THE ARENA LANE. ArenaData.build() turns this plan into the
-- contract's Arena (with ArenaGrid's queries and ArenaDataNav's graph); the bake (tools/bake/games/
-- Paintball through tools/games/paintball/arena/PartList) draws one part per box from the same plan,
-- so what is drawn is what a ball stops on.
--
-- THE PLAN IS TURNED HALF ROUND ON ITSELF: every solid has a twin at (-x, -z), so the west team's
-- building is the east team's building exactly (the looks of the two halves differ; the solids do
-- not). Positions are in the arena frame (Arena): -z is called north, -x west; the lobby annex is
-- outside the south wall.
--
-- THE BONES, on every storey (14 studs floor to floor, slabs 1 thick):
--   the atrium       30 x 30, open from the ground to a glass roof; rails 3.4 high round it from the
--                    first floor up, with a gap on two sides of each storey to drop through;
--   two stair cores  north and south of the atrium (z 22..30 either side, x -15..15): a switchback of
--                    straight flights in two strips, a landing at one end of each storey with a
--                    doorway to the gallery, to the hall behind and to the concourse beside it. The
--                    flight sides are open: a body may step off. On the ground the core has no front;
--                    on the second and fourth floors its front is a parapet;
--   galleries        north and south of the atrium (between its rail and the core), and the east and
--                    west concourses (x 16..30) that run the building's length;
--   the halls        north and south of z = 31, and the wings west and east of x = 31.
-- THE STOREYS
--   0  loading dock and workshop: the outside-broadcast van, crates, drums, scenery flats; the fallen
--      lighting rig on the atrium floor; the way out (an alcove in the south wall: Arena `exits`).
--   1  the newsroom: cubicles, the editor's office, the news set with its desk on a riser, cameras,
--      the weather wall, edit suites.
--   2  the studios, and BOTH SPAWN ROOMS (the green rooms against the west and east walls): Studio A
--      and B with stage risers, set walls, cameras and lighting grids; make-up, wardrobe.
--   3  master control behind windows, the tape library's shelving, telecine, the audio booth.
--   4  offices, the boardroom, the transmitter hall; the hanging half of the lighting rig under the
--      glass roof.
-- HEIGHTS A BODY MEETS: every low piece is exactly Arena.RAIL_HEIGHT above what it stands on (a
-- crouched body is hidden, a standing eye sees over); a riser is 1 stud (walked onto); everything
-- else a body could stand beside is at least Arena.HEADROOM tall, and no doorway is lower than DOOR.
-- Pure. Interface: build() -> Plan (a fresh table each call); LOOKS (names, by code); DOOR
local Arena = require("./Arena")

-- Words on a box's face. Without `at` they fill the face; with it they are painted in the w x h rectangle
-- whose middle is the point `at` (arena coordinates, on the face). `bg` is a painted panel behind them.
export type Sign = {
	box: number,
	face: string,
	text: string,
	tone: string,
	at: { number }?,
	w: number?,
	h: number?,
	bg: string?,
}
export type Lamp = { box: number, range: number, brightness: number, tone: string }
export type Flight = { f: number, side: number, dir: number, z: number }
export type Doorway = { level: number, ax: number, az: number, bx: number, bz: number }
export type Plan = {
	boxes: { number },
	kinds: { number },
	looks: { number }, -- by box: an index into LOOKS
	ramps: { Arena.Ramp },
	flights: { Flight }, -- by ramp
	spawns: { { Arena.Spawn } },
	spawnRooms: { Arena.Room },
	curtains: { { Arena.Room } },
	exits: { Arena.Room },
	lobby: Arena.Spawn,
	doorways: { Doorway }, -- the two points either side of every doorway: the navigation graph has a node at each
	monitors: { [number]: string }, -- box -> the face its screen is on ("+x", "-x", "+z", "-z")
	signs: { Sign }, -- words on a box's face
	lamps: { Lamp }, -- boxes that give light
}

local Plan = {}

Plan.DOOR = 8 -- studs: the height of a doorway under its lintel
Plan.LOOKS = table.freeze({
	"floor0",
	"floor1",
	"floor2",
	"floor3",
	"floor4",
	"roof",
	"skylight",
	"shell",
	"glass",
	"gate",
	"shutter",
	"wall0",
	"wall1",
	"wall2",
	"wall3",
	"wall4",
	"core",
	"pillar",
	"rail",
	"parapet",
	"step",
	"landing",
	"spawn1",
	"spawn2",
	"crate",
	"drum",
	"case",
	"van",
	"van_cab",
	"chassis",
	"container",
	"flat",
	"set_blue",
	"set_warm",
	"green_screen",
	"riser",
	"desk",
	"news_desk",
	"cubicle",
	"cabinet",
	"rack",
	"console",
	"shelf",
	"camera_base",
	"camera_head",
	"lens",
	"truss",
	"lamp",
	"ceiling_light",
	"tray",
	"cable",
	"monitor",
	"cart",
	"sofa",
	"planter",
	"on_air",
	"locker",
	"transmitter",
	"table",
	"bench",
	"stand",
	"terminal",
	"sheet",
	"ceiling_dead",
})

local LOOK: { [string]: number } = {}
for i, name in Plan.LOOKS do
	LOOK[name] = i
end

function Plan.build(): Plan
	local KIND = Arena.KIND
	local H, RAIL = Arena.FLOOR_HEIGHT, Arena.RAIL_HEIGHT
	local half, atrium, floors = Arena.HALF, Arena.ATRIUM, Arena.FLOORS
	local DOOR = Plan.DOOR
	local boxes: { number } = {}
	local kinds: { number } = {}
	local looks: { number } = {}
	local plan: Plan = {
		boxes = boxes,
		kinds = kinds,
		looks = looks,
		ramps = {},
		flights = {},
		spawns = {},
		spawnRooms = {},
		curtains = {},
		exits = {},
		lobby = { x = -14, y = 0, z = 72, yaw = 0 },
		doorways = {},
		monitors = {},
		signs = {},
		lamps = {},
	}

	-- one box, in arena coordinates; returns its index
	local function raw(
		kind: number,
		look: string,
		x0: number,
		y0: number,
		z0: number,
		x1: number,
		y1: number,
		z1: number
	): number
		table.insert(boxes, math.min(x0, x1))
		table.insert(boxes, math.min(y0, y1))
		table.insert(boxes, math.min(z0, z1))
		table.insert(boxes, math.max(x0, x1))
		table.insert(boxes, math.max(y0, y1))
		table.insert(boxes, math.max(z0, z1))
		table.insert(kinds, kind)
		table.insert(looks, LOOK[look] or error(`ArenaDataPlan: no look {look}`))
		return #kinds
	end
	-- a box and its twin, turned half round; look2 dresses the twin. Returns both indices.
	local function pair(
		kind: number,
		look: string,
		x0: number,
		y0: number,
		z0: number,
		x1: number,
		y1: number,
		z1: number,
		look2: string?
	): (number, number)
		local a = raw(kind, look, x0, y0, z0, x1, y1, z1)
		local b = raw(kind, look2 or look, -x1, y0, -z1, -x0, y1, -z0)
		return a, b
	end
	-- on a storey: heights are above that storey's floor
	local function on(
		level: number,
		kind: number,
		look: string,
		x0: number,
		z0: number,
		x1: number,
		z1: number,
		h0: number,
		h1: number,
		look2: string?
	): (number, number)
		return pair(kind, look, x0, level * H + h0, z0, x1, level * H + h1, z1, look2)
	end
	local function ceiling(level: number): number
		return if level == floors - 1 then H else H - 1
	end
	local function doorway(level: number, ax: number, az: number, bx: number, bz: number)
		table.insert(plan.doorways, { level = level, ax = ax, az = az, bx = bx, bz = bz })
		table.insert(plan.doorways, { level = level, ax = -ax, az = -az, bx = -bx, bz = -bz })
	end
	local function opposite(face: string): string
		return (if string.sub(face, 1, 1) == "+" then "-" else "+") .. string.sub(face, 2)
	end
	local function sign(a: number, b: number, face: string, text: string, tone: string, text2: string?)
		table.insert(plan.signs, { box = a, face = face, text = text, tone = tone })
		table.insert(plan.signs, { box = b, face = opposite(face), text = text2 or text, tone = tone })
	end
	local function lamp(a: number, b: number, range: number, brightness: number, tone: string)
		table.insert(plan.lamps, { box = a, range = range, brightness = brightness, tone = tone })
		table.insert(plan.lamps, { box = b, range = range, brightness = brightness, tone = tone })
	end
	-- PAINT: words in a w x h rectangle on whichever box has a face looking `face` that holds the whole
	-- rectangle about (x, y, z); the twin's are painted on the twin box (text2, or the same words). Paint
	-- is not a solid and not a part: it is on the wall a ball stops on. Called after the boxes it is
	-- painted on are made; a rectangle that lies on no one face is a mistake in this file.
	local function faceBox(x: number, y: number, z: number, face: string, w: number, h: number): number
		local e = 1e-6
		for i = 1, #kinds do
			local k = (i - 1) * 6
			local x0, y0, z0, x1, y1, z1 =
				boxes[k + 1], boxes[k + 2], boxes[k + 3], boxes[k + 4], boxes[k + 5], boxes[k + 6]
			if y0 <= y - h / 2 + e and y1 >= y + h / 2 - e then
				local alongX = x0 <= x - w / 2 + e and x1 >= x + w / 2 - e
				local alongZ = z0 <= z - w / 2 + e and z1 >= z + w / 2 - e
				if
					(face == "+z" and math.abs(z1 - z) < e and alongX)
					or (face == "-z" and math.abs(z0 - z) < e and alongX)
					or (face == "+x" and math.abs(x1 - x) < e and alongZ)
					or (face == "-x" and math.abs(x0 - x) < e and alongZ)
				then
					return i
				end
			end
		end
		error(`ArenaDataPlan: no face {face} holds a {w} x {h} sign at ({x}, {y}, {z})`)
	end
	local function paint(
		x: number,
		y: number,
		z: number,
		face: string,
		w: number,
		h: number,
		text: string,
		tone: string,
		text2: string?,
		bg: string?
	)
		table.insert(plan.signs, {
			box = faceBox(x, y, z, face, w, h),
			face = face,
			text = text,
			tone = tone,
			at = { x, y, z },
			w = w,
			h = h,
			bg = bg,
		})
		local back = opposite(face)
		table.insert(plan.signs, {
			box = faceBox(-x, y, -z, back, w, h),
			face = back,
			text = text2 or text,
			tone = tone,
			at = { -x, y, -z },
			w = w,
			h = h,
			bg = bg,
		})
	end
	-- a room's name over its doorway, on the lintel: (x, z) is the middle of the doorway on the face the
	-- name is read from
	local function over(level: number, x: number, z: number, face: string, w: number, text: string, text2: string?)
		paint(x, level * H + DOOR + 1.5, z, face, w, 1.7, text, "white", text2, "plate")
	end

	-- A full-height wall 1 thick, with openings. `along` "x": it runs along x at z = c from a to b;
	-- "z": along z at x = c. Each opening is { centre, width, kind? }: a doorway (a lintel over it
	-- from DOOR up, and a `doorways` entry: a point either side of it), or with WINDOW after them a sill
	-- RAIL_HEIGHT high with the lintel over it (low cover to shoot over; nobody walks through).
	type Opening = { number }
	local WINDOW = 1
	local function wall(
		level: number,
		look: string,
		along: string,
		c: number,
		a: number,
		b: number,
		openings: { Opening }?
	)
		local top = ceiling(level)
		local function piece(p: number, q: number, h0: number, h1: number, kind: number)
			if q - p < 1e-6 then
				return
			end
			if along == "x" then
				on(level, kind, look, p, c - 0.5, q, c + 0.5, h0, h1)
			else
				on(level, kind, look, c - 0.5, p, c + 0.5, q, h0, h1)
			end
		end
		local list: { Opening } = table.clone(openings or {})
		table.sort(list, function(p: Opening, q: Opening): boolean
			return p[1] < q[1]
		end)
		local cursor = a
		for _, o in list do
			local p, q = o[1] - o[2] / 2, o[1] + o[2] / 2
			piece(cursor, p, 0, top, KIND.wall)
			piece(p, q, DOOR, top, KIND.wall)
			if o[3] == WINDOW then
				piece(p, q, 0, RAIL, KIND.cover)
			elseif along == "x" then
				doorway(level, o[1], c - 2.6, o[1], c + 2.6)
			else
				doorway(level, c - 2.6, o[1], c + 2.6, o[1])
			end
			cursor = q
		end
		piece(cursor, b, 0, top, KIND.wall)
	end

	-- THE SHELL: the ground, the roof with its glass over the atrium, the outer walls storey by storey
	raw(KIND.slab, "floor0", -half, -1, -half, half, 0, half)
	local top = floors * H
	pair(KIND.slab, "roof", -half - 1, top, -half - 1, half + 1, top + 1, -atrium)
	pair(KIND.slab, "roof", -half - 1, top, -atrium, -atrium, top + 1, atrium)
	raw(KIND.slab, "skylight", -atrium, top, -atrium, atrium, top + 1, atrium)
	for level = 0, floors - 1 do
		local y0 = if level == 0 then -1 else level * H - 1
		local y1 = if level == floors - 1 then top + 1 else (level + 1) * H - 1
		if level == 0 then
			-- the east wall's loading shutter (its twin on the west wall is boarded up), and the south
			-- wall: the arena gate behind the lobby's prompt and the two windows the lobby looks in by
			pair(KIND.wall, "shell", half, y0, -half, half + 1, y1, -29)
			pair(KIND.wall, "shutter", half, y0, -29, half + 1, 10, -21)
			pair(KIND.wall, "shell", half, 10, -29, half + 1, y1, -21)
			pair(KIND.wall, "shell", half, y0, -21, half + 1, y1, half)
			raw(KIND.wall, "shell", -half - 1, y0, -half - 1, half + 1, y1, -half)
			local z0, z1 = half, half + 1
			raw(KIND.wall, "shell", -half - 1, y0, z0, -38, y1, z1)
			raw(KIND.wall, "shell", 38, y0, z0, half + 1, y1, z1)
			raw(KIND.wall, "shell", -22, y0, z0, -4, y1, z1)
			raw(KIND.wall, "shell", 4, y0, z0, 22, y1, z1)
			local gate = raw(KIND.wall, "gate", -4, y0, z0, 4, 9, z1)
			raw(KIND.wall, "shell", -4, 9, z0, 4, y1, z1)
			table.insert(plan.signs, { box = gate, face = "-z", text = "EXIT", tone = "green" })
			for _, s in { -1, 1 } do
				raw(KIND.wall, "shell", s * 22, y0, z0, s * 38, 1.5, z1)
				raw(KIND.wall, "glass", s * 22, 1.5, z0, s * 38, 9, z1)
				raw(KIND.wall, "shell", s * 22, 9, z0, s * 38, y1, z1)
			end
		else
			pair(KIND.wall, "shell", half, y0, -half, half + 1, y1, half)
			pair(KIND.wall, "shell", -half - 1, y0, -half - 1, half + 1, y1, -half)
		end
	end

	-- THE FLOORS above the ground: all of the storey but the atrium and the two stair cores
	local CORE0, CORE1 = 22, 30 -- a core's two strips lie between these |z|
	local RUN, STEPS = 21, 28 -- a flight: 21 studs along x, 28 steps of half a stud
	for level = 1, floors - 1 do
		local y = level * H
		local look = `floor{level}`
		pair(KIND.slab, look, -half, y - 1, -half, -atrium, y, half)
		pair(KIND.slab, look, -atrium, y - 1, -half, atrium, y, -CORE1)
		pair(KIND.slab, look, -atrium, y - 1, -CORE0, atrium, y, -atrium)
		-- the atrium's rails, with a gap to drop through on two sides of each storey
		local thick = 0.5
		if level % 2 == 1 then
			pair(KIND.rail, "rail", atrium, y, -atrium - thick, atrium + thick, y + RAIL, 8)
			pair(KIND.rail, "rail", atrium, y, 12, atrium + thick, y + RAIL, atrium + thick)
			pair(KIND.rail, "rail", -atrium, y, -atrium - thick, atrium, y + RAIL, -atrium)
		else
			pair(KIND.rail, "rail", atrium, y, -atrium - thick, atrium + thick, y + RAIL, atrium + thick)
			pair(KIND.rail, "rail", -atrium, y, -atrium - thick, 8, y + RAIL, -atrium)
			pair(KIND.rail, "rail", 12, y, -atrium - thick, atrium, y + RAIL, -atrium)
		end
	end

	-- THE STAIR CORES. Written for the north one (its twin is the south one). Flight f climbs from
	-- storey f to f + 1: even flights in the outer strip rising towards +x, odd ones in the inner
	-- strip rising towards -x, so each ends on the landing the next begins on.
	local END = (RUN / 2 + atrium) / 2 -- the middle of a landing, along x
	for f = 0, floors - 2 do
		local dir = if f % 2 == 0 then 1 else -1
		local za, zb = if f % 2 == 0 then -CORE1 else -CORE1 + 4, if f % 2 == 0 then -CORE1 + 4 else -CORE0
		local y0, y1 = f * H, (f + 1) * H
		table.insert(
			plan.ramps,
			{ minX = -RUN / 2, minZ = za, maxX = RUN / 2, maxZ = zb, y0 = y0, y1 = y1, axis = "x", dir = dir }
		)
		table.insert(
			plan.ramps,
			{ minX = -RUN / 2, minZ = -zb, maxX = RUN / 2, maxZ = -za, y0 = y0, y1 = y1, axis = "x", dir = -dir }
		)
		table.insert(plan.flights, { f = f, side = -1, dir = dir, z = (za + zb) / 2 })
		table.insert(plan.flights, { f = f, side = 1, dir = -dir, z = -(za + zb) / 2 })
		local run, rise = RUN / STEPS, H / STEPS
		for k = if f == 0 then 1 else 0, STEPS - 1 do
			-- step k from the low end: its top is the ramp's height where the step begins. The ground
			-- flight is solid down to the floor; the others are slabs in the air.
			local xa = -dir * RUN / 2 + dir * run * k
			local stepTop = y0 + k * rise
			pair(KIND.step, "step", xa, if f == 0 then 0 else stepTop - 1, za, xa + dir * run, stepTop, zb)
		end
		-- the landing at the head, across both strips: the foot of the next flight too
		pair(KIND.slab, "landing", dir * RUN / 2, y1 - 1, -CORE1, dir * atrium, y1, -CORE0)
	end
	for level = 0, floors - 1 do
		-- the end the storey's landing is at (the ground's "landing" is the foot of the first flight)
		local at = if level % 2 == 0 then -1 else 1
		local door = { at * END, 4 }
		if level == 0 then
			wall(0, "core", "x", -CORE1 - 0.5, -atrium - 1, atrium + 1, { door, { -at * END, 4 } })
		else
			wall(level, "core", "x", -CORE1 - 0.5, -atrium - 1, atrium + 1, { door })
			-- the end walls: a doorway to the concourse at the landing's end, solid at the other
			wall(level, "core", "z", at * (atrium + 0.5), -CORE1, -CORE0, { { -(CORE0 + CORE1) / 2, 4 } })
			wall(level, "core", "z", -at * (atrium + 0.5), -CORE1, -CORE0, nil)
			if level % 2 == 1 then
				wall(level, "core", "x", -CORE0 + 0.5, -atrium - 1, atrium + 1, { door })
			else
				-- a parapet towards the gallery, open at the landing
				local a, b = at * END - 2, at * END + 2
				on(level, KIND.rail, "parapet", -atrium - 1, -CORE0, a, -CORE0 + 1, 0, RAIL)
				on(level, KIND.rail, "parapet", b, -CORE0, atrium + 1, -CORE0 + 1, 0, RAIL)
				doorway(level, at * END, -CORE0 - 2.1, at * END, -CORE0 + 3.1)
			end
		end
	end

	-- pillars at the atrium's corners, every storey
	for level = 0, floors - 1 do
		on(level, KIND.pillar, "pillar", -20, -20, -18, -18, 0, ceiling(level))
		on(level, KIND.pillar, "pillar", 18, -20, 20, -18, 0, ceiling(level))
	end

	-- THE SPAWN ROOMS, on the middle storey: team 1's against the west wall, team 2's its twin. Air
	-- from x -60 to -44, z -12 to 12; a door in the north wall at its west end and one in the south
	-- wall at its east end; inside each door a baffle wall, so that whoever looks in sees a wall and
	-- whoever walks in turns along a corridor and comes into the room at the far end of the baffle.
	local roomY = Arena.SPAWN_FLOOR * H
	local wallTop = roomY + H - 1
	local doorTop = roomY + Arena.HEADROOM
	local function room(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number): Arena.Room
		return {
			minX = math.min(x0, x1),
			minY = math.min(y0, y1),
			minZ = math.min(z0, z1),
			maxX = math.max(x0, x1),
			maxY = math.max(y0, y1),
			maxZ = math.max(z0, z1),
		}
	end
	for team = 1, 2 do
		local s = if team == 1 then 1 else -1
		local look = `spawn{team}`
		raw(KIND.wall, look, s * -44, roomY, s * -13, s * -43, wallTop, s * 13) -- the wall towards the atrium
		raw(KIND.wall, look, s * -55, roomY, s * -13, s * -44, wallTop, s * -12) -- north wall (door: x -60..-55)
		raw(KIND.wall, look, s * -60, roomY, s * 12, s * -49, wallTop, s * 13) -- south wall (door: x -49..-44)
		raw(KIND.wall, look, s * -60, roomY, s * -7, s * -48, wallTop, s * -6) -- the baffle inside the north door
		raw(KIND.wall, look, s * -55, roomY, s * 6, s * -44, wallTop, s * 7) -- the baffle inside the south door
		raw(KIND.wall, look, s * -60, roomY + DOOR, s * -13, s * -55, wallTop, s * -12) -- the lintels
		raw(KIND.wall, look, s * -49, roomY + DOOR, s * 12, s * -44, wallTop, s * 13)
		plan.spawnRooms[team] = room(s * -60, roomY, s * -12, s * -44, doorTop, s * 12)
		plan.curtains[team] = {
			room(s * -60, roomY, s * -13, s * -55, doorTop, s * -12),
			room(s * -49, roomY, s * 12, s * -44, doorTop, s * 13),
		}
		local list: { Arena.Spawn } = {}
		for _, z in { -2.5, 2.5 } do
			-- each row looks towards the gap at the end of the baffle on its side
			local gx, gz = if z < 0 then -46 else -57.5, if z < 0 then -6.5 else 6.5
			for _, x in { -57, -53, -49.5, -46 } do
				local dx, dz = s * (gx - x), s * (gz - z)
				table.insert(list, { x = s * x, y = roomY, z = s * z, yaw = math.atan2(-dx, -dz) })
			end
		end
		plan.spawns[team] = list
	end

	-- FURNITURE, each piece and its twin
	local function low(
		level: number,
		look: string,
		x0: number,
		z0: number,
		x1: number,
		z1: number,
		look2: string?
	): (number, number)
		return on(level, KIND.cover, look, x0, z0, x1, z1, 0, RAIL, look2)
	end
	local function tall(
		level: number,
		look: string,
		x0: number,
		z0: number,
		x1: number,
		z1: number,
		h: number,
		look2: string?
	): (number, number)
		return on(level, KIND.prop, look, x0, z0, x1, z1, 0, h, look2)
	end
	-- two crates, one on the other
	local function stack(level: number, look: string, x0: number, z0: number, x1: number, z1: number)
		low(level, look, x0, z0, x1, z1)
		on(level, KIND.prop, look, x0 + 0.2, z0 + 0.2, x1 - 0.2, z1 - 0.2, RAIL, 2 * RAIL - 0.4)
	end
	-- a studio camera on its pedestal, looking along (lx, lz) (a unit axis)
	local function camera(level: number, x: number, z: number, lx: number, lz: number, base: number?)
		local b = base or 0
		on(level, KIND.prop, "camera_base", x - 0.9, z - 0.9, x + 0.9, z + 0.9, b, b + RAIL)
		local px, pz = math.abs(lz), math.abs(lx) -- across the look
		on(
			level,
			KIND.prop,
			"camera_head",
			x - 0.9 * px - 1.6 * math.abs(lx),
			z - 0.9 * pz - 1.6 * math.abs(lz),
			x + 0.9 * px + 1.6 * math.abs(lx),
			z + 0.9 * pz + 1.6 * math.abs(lz),
			b + RAIL,
			b + RAIL + 1.8
		)
		on(
			level,
			KIND.prop,
			"lens",
			x + lx * 1.6 - 0.5 * px - 0.01 * math.abs(lx) + math.min(0, lx) * 0.9,
			z + lz * 1.6 - 0.5 * pz - 0.01 * math.abs(lz) + math.min(0, lz) * 0.9,
			x + lx * 1.6 + 0.5 * px + 0.01 * math.abs(lx) + math.max(0, lx) * 0.9,
			z + lz * 1.6 + 0.5 * pz + 0.01 * math.abs(lz) + math.max(0, lz) * 0.9,
			b + RAIL + 0.4,
			b + RAIL + 1.4
		)
	end
	-- an old set on a cart: the cart is low cover, the set on it is a monitor facing `face`
	local function set(level: number, x: number, z: number, face: string)
		low(level, "cart", x - 1.5, z - 1.5, x + 1.5, z + 1.5)
		local a, b = on(level, KIND.prop, "monitor", x - 1.3, z - 1.3, x + 1.3, z + 1.3, RAIL, RAIL + 2.2)
		plan.monitors[a] = face
		plan.monitors[b] = opposite(face)
	end
	-- a light stand: a thin pole with a lamp head on it
	local function stand(level: number, x: number, z: number, base: number?)
		local b = base or 0
		on(level, KIND.prop, "stand", x - 0.3, z - 0.3, x + 0.3, z + 0.3, b, b + 8)
		local i, j = on(level, KIND.prop, "lamp", x - 0.9, z - 0.9, x + 0.9, z + 0.9, b + 8, b + 9.6)
		lamp(i, j, 26, 0.9, "warm")
	end
	-- a strip light on the ceiling (a box like any other: a ball stops on it)
	-- (one fitting in five is dead: the same ones on both teams' sides)
	local strips = 0
	local function strip(level: number, x0: number, z0: number, x1: number, z1: number, tone: string?)
		local c = ceiling(level)
		strips += 1
		if strips % 5 == 3 then
			on(level, KIND.prop, "ceiling_dead", x0, z0, x1, z1, c - 0.4, c)
			return
		end
		local i, j = on(level, KIND.prop, "ceiling_light", x0, z0, x1, z1, c - 0.4, c)
		lamp(i, j, 34, 1.1, tone or "cold")
	end
	-- a monitor hung from the ceiling on a drop pole, its screen looking `face`: the lowest of it is 8.6
	-- over the floor, above every head, so it is nobody's cover and in nobody's way
	local function hung(level: number, x: number, z: number, face: string)
		local alongX = face == "+z" or face == "-z"
		local wx, wz = if alongX then 1.9 else 0.5, if alongX then 0.5 else 1.9
		on(level, KIND.prop, "stand", x - 0.2, z - 0.2, x + 0.2, z + 0.2, 11, ceiling(level))
		local a, b = on(level, KIND.prop, "monitor", x - wx, z - wz, x + wx, z + wz, 8.6, 11)
		plan.monitors[a] = face
		plan.monitors[b] = opposite(face)
	end
	-- a cable tray under the ceiling
	local function tray(level: number, x0: number, z0: number, x1: number, z1: number)
		on(level, KIND.prop, "tray", x0, z0, x1, z1, 10.4, 10.9)
	end
	-- a lighting grid over a studio: pipes along x at each z of `rows`, cans hung under them
	local function grid(level: number, x0: number, x1: number, rows: { number }, cans: { number })
		for r, z in rows do
			on(level, KIND.prop, "truss", x0, z - 0.2, x1, z + 0.2, 12, 12.4)
			for c, x in cans do
				local shift = if (r + c) % 2 == 0 then 0 else 1.5
				local i, j = on(level, KIND.prop, "lamp", x + shift - 0.6, z - 0.6, x + shift + 0.6, z + 0.6, 10.6, 12)
				if (r + c) % 3 == 0 then
					lamp(i, j, 30, 1.0, "warm")
				end
			end
		end
	end
	-- a length of lighting truss lying along x on a storey's floor: four chords and square frames,
	-- open between them (a ball passes through the gaps, as drawn), with cans still clamped to it
	local function truss(level: number, x0: number, x1: number, zc: number, base: number)
		local w = 1.1
		for _, dz in { -w, w - 0.4 } do
			on(level, KIND.prop, "truss", x0, zc + dz, x1, zc + dz + 0.4, base, base + 0.4)
			on(level, KIND.prop, "truss", x0, zc + dz, x1, zc + dz + 0.4, base + RAIL - 0.4, base + RAIL)
		end
		local n = math.max(2, math.floor((x1 - x0) / 2.6 + 0.5))
		for k = 0, n do
			local x = x0 + (x1 - x0 - 0.4) * k / n
			on(level, KIND.prop, "truss", x, zc - w, x + 0.4, zc - w + 0.4, base + 0.4, base + RAIL - 0.4)
			on(level, KIND.prop, "truss", x, zc + w - 0.4, x + 0.4, zc + w, base + 0.4, base + RAIL - 0.4)
			on(level, KIND.prop, "truss", x, zc - w + 0.4, x + 0.4, zc + w - 0.4, base, base + 0.4)
			on(level, KIND.prop, "truss", x, zc - w + 0.4, x + 0.4, zc + w - 0.4, base + RAIL - 0.4, base + RAIL)
		end
	end

	-- the hall line (z = 30.5) on every storey: the halls' walls either side of the cores
	for level = 0, floors - 1 do
		local look = `wall{level}`
		local west = if level == 2 then -52 else -45
		wall(level, look, "x", -30.5, -half, -atrium - 1, { { west, 6 }, { -23, 8 } })
		wall(level, look, "x", -30.5, atrium + 1, half, { { 23, 8 }, { 45, 6 } })
		-- strip lights and cable trays along the concourse and the halls
		strip(level, -24, -12, -22, -4)
		strip(level, -24, 4, -22, 12)
		strip(level, -24, -50, -22, -42)
		strip(level, 22, -50, 24, -42)
		strip(level, -50, -24, -42, -22)
		strip(level, -50, 18, -42, 20)
		strip(level, -4, -46, 4, -44)
		tray(level, -27.5, -30, -26.5, 30)
		tray(level, -59, -34, -31, -33)
		-- the station's monitors over the concourse and the north gallery: the score, when it comes on air
		hung(level, -23, 0, if level % 2 == 0 then "-z" else "+z")
		hung(level, 0, -18.5, if level % 2 == 0 then "+x" else "-x")
	end

	-- STOREY 0: the loading dock and the workshop
	do
		local L, W = 0, "wall0"
		wall(L, W, "z", -30.5, -30, -9, { { -19.5, 6 } })
		wall(L, W, "z", -30.5, 9, 30, { { 19.5, 6 } })
		wall(L, W, "x", -8.5, -half, -30, { { -44, 6 } })
		wall(L, W, "x", 8.5, -half, -30, { { -36, 6 } })
		wall(L, W, "z", -30.5, -half, -31, { { -45, 6 } })
		wall(L, W, "z", 30.5, -half, -31, { { -45, 6 } })
		-- the atrium floor: the fallen lighting rig in two lengths, cans thrown off it, and crates
		truss(L, -13, 1, -8, 0)
		for _, x in { -11, -6.5, -1.5 } do
			on(L, KIND.prop, "lamp", x, -8.6, x + 1.2, -7.4, RAIL, RAIL + 1.3)
		end
		on(L, KIND.prop, "lamp", 2.6, -6.4, 3.8, -5.2, 0, 1.2)
		on(L, KIND.prop, "lamp", -9, -5.6, -7.8, -4.4, 0, 1.2)
		low(L, "case", 5, -4.6, 8.4, -1.4)
		stack(L, "crate", -13.4, 1.6, -10, 5)
		-- in the alcove under the first landing of each core, and in front of the stair
		low(L, "crate", 11, -25, 14.4, -22.4)
		-- the north hall, middle: the scenery store (its twin, the south hall, is reception)
		local f1, f2 = on(L, KIND.prop, "flat", -14, -41, -4, -40, 0, 10, "set_warm")
		sign(f1, f2, "+z", "SCENERY\nSTUDIO B", "stencil", "WBLW 7\nRECEPTION")
		on(L, KIND.prop, "flat", 4, -50, 14, -49, 0, 10, "set_warm")
		on(L, KIND.prop, "flat", 20, -54, 21, -44, 0, 10, "flat")
		on(L, KIND.prop, "flat", -22, -56, -21, -46, 0, 10, "flat")
		low(L, "crate", -10, -52, -6.6, -48.6, "sofa")
		stack(L, "crate", 8, -40.4, 11.4, -37)
		low(L, "drum", -3, -35.5, 0.4, -32.5, "planter")
		-- the alcove in the middle of the north wall, and its twin in the south: the way out
		on(L, KIND.wall, W, 3, -half, 4, -55, 0, ceiling(L))
		on(L, KIND.wall, W, -4, -half, -3, -55, 0, ceiling(L))
		local l1, l2 = on(L, KIND.wall, W, -3, -half, 3, -59, DOOR, ceiling(L))
		sign(l1, l2, "+z", "FIRE DOOR\nCHAINED", "stencil", "WAY OUT")
		table.insert(plan.exits, room(-3, 0, 55.5, 3, Arena.HEADROOM, half))
		-- the north-west room: racking
		tall(L, "shelf", -56, -53.2, -46, -51.6, 9)
		tall(L, "shelf", -56, -45.2, -46, -43.6, 9)
		low(L, "crate", -38, -56, -34.6, -52.6)
		-- the north-east room: cable drums and lockers (its twin: the mail room)
		low(L, "drum", 38, -50, 41.4, -46.6)
		low(L, "drum", 49, -39.4, 52.4, -36)
		tall(L, "locker", 57, -56, 59, -44, 7.5)
		stack(L, "crate", 34, -59, 37.4, -55.6)
		-- the west wing's north bay: the workshop
		low(L, "bench", -56, -24, -48, -21.5)
		low(L, "bench", -44, -16, -36, -13.5)
		tall(L, "locker", -59, -20, -57, -12, 7.5)
		stack(L, "crate", -36, -29, -32.6, -25.6)
		-- the wing's aisle: on the east side the outside-broadcast van, on the west its twin, a container
		on(L, KIND.prop, "chassis", -57.6, 1.9, -40.4, 7.1, 0, 1)
		local v1, v2 = on(L, KIND.prop, "container", -58, 1.5, -44, 7.5, 1, 8.5, "van")
		on(L, KIND.prop, "container", -44, 1.5, -40, 7.5, 1, 6.5, "van_cab")
		sign(v1, v2, "-z", "WBLW 7\nSCENERY", "stencil", "WBLW 7\nEYEWITNESS NEWS")
		low(L, "crate", -39, -6.5, -35.6, -3.1)
		-- the wing's south bay: stores
		low(L, "crate", -50, 14, -46.6, 17.4)
		stack(L, "crate", -56, 22, -52.6, 25.4)
		low(L, "drum", -40, 20, -36.6, 23.4)
		tall(L, "shelf", -59, 11, -57.4, 19, 9)
		-- the concourse
		low(L, "case", -25.5, -13.4, -22.5, -10)
		stack(L, "case", -28.6, 11, -25.6, 14.4)
		set(L, -27.5, -3.5, "+x")
	end

	-- STOREY 1: the newsroom
	do
		local L, W = 1, "wall1"
		wall(L, W, "z", -30.5, -half, -31, { { -45, 6 } })
		wall(L, W, "z", 30.5, -half, -31, { { -45, 6 } })
		-- the editor's office in the middle of the wing, behind windows
		wall(L, W, "x", -9.5, -half, -46, nil)
		wall(L, W, "x", 9.5, -half, -46, nil)
		wall(L, W, "z", -45.5, -10, 10, { { -6, 4, WINDOW }, { 0, 5 }, { 6, 4, WINDOW } })
		low(L, "sheet", -55, -1.5, -50, 1.5)
		tall(L, "cabinet", -59, -9, -54, -7.4, 7)
		-- cubicles: a cross of partitions with a desk in two of its corners
		local function cubicle(x: number, z: number)
			low(L, "cubicle", x - 4.5, z - 0.3, x + 4.5, z + 0.3)
			low(L, "cubicle", x - 0.3, z - 4.5, x + 0.3, z + 4.5)
			low(L, "desk", x - 4.2, z + 0.3, x - 0.3, z + 2.3)
			low(L, "desk", x + 0.3, z - 2.3, x + 4.2, z - 0.3)
			-- a dead terminal on each desk
			on(L, KIND.prop, "terminal", x - 3.3, z + 0.8, x - 1.5, z + 2, RAIL, RAIL + 1.4)
			on(L, KIND.prop, "terminal", x + 1.5, z - 2, x + 3.3, z - 0.8, RAIL, RAIL + 1.4)
		end
		cubicle(-52, -20)
		cubicle(-38.5, -21)
		cubicle(-52, 20)
		cubicle(-38.5, 19)
		low(L, "cabinet", -44, -12.5, -36, -11)
		tall(L, "cabinet", -50, 28.4, -44, 30, 7)
		-- the news set in the north hall: the desk on its riser, the wall behind it, three cameras
		on(L, KIND.slab, "riser", -10, -51, 10, -39, 0, 1)
		local d1, d2 = on(L, KIND.cover, "news_desk", -7, -47, 7, -45, 1, 1 + RAIL)
		sign(d1, d2, "+z", "WBLW 7 NEWS", "gold", "WBLW 7 SPORTS")
		on(L, KIND.cover, "news_desk", -7, -45, -5.5, -41.5, 1, 1 + RAIL)
		on(L, KIND.cover, "news_desk", 5.5, -45, 7, -41.5, 1, 1 + RAIL)
		local b1, b2 = on(L, KIND.prop, "set_blue", -12, -54.5, 12, -53.5, 0, 11, "set_warm")
		sign(b1, b2, "+z", "EYEWITNESS\nNEWS AT SIX", "white", "CHANNEL 7\nSPORTS DESK")
		camera(L, -10, -35, 0, -1)
		camera(L, 1.5, -34.5, 0, -1)
		camera(L, 12, -36, 0, -1)
		stand(L, -16, -42)
		stand(L, 16, -43)
		grid(L, -20, 20, { -50, -44, -38 }, { -15, -7, 1, 9 })
		-- the north-west rooms: edit suites
		wall(L, W, "x", -45.5, -half, -31, { { -52, 5 }, { -37, 5 } })
		low(L, "console", -59, -58.5, -53, -56)
		low(L, "console", -38, -58.5, -32, -56)
		low(L, "console", -59, -42, -56.5, -36)
		tall(L, "rack", -34, -44.5, -32, -40, 7)
		-- the north-east room: the weather wall
		local g1, g2 = on(L, KIND.prop, "green_screen", 38, -58.6, 56, -57.6, 0, 11, "set_blue")
		sign(g1, g2, "+z", "", "white", "TRAFFIC")
		camera(L, 47, -43, 0, -1)
		low(L, "desk", 34, -50, 37, -46)
		stand(L, 55, -47)
		-- the concourse
		low(L, "bench", -27, 8, -25, 14)
		low(L, "planter", -22, -22, -19, -19.6)
		set(L, -27.5, -15, "+x")
	end

	-- STOREY 2: the studios; the spawn rooms are in the wings
	do
		local L, W = 2, "wall2"
		wall(L, W, "z", -30.5, -30, 30, { { -22, 6 }, { 22, 6 } })
		wall(L, W, "x", -12.5, -43, -31, { { -37, 5 } })
		wall(L, W, "x", 12.5, -43, -31, { { -37, 5 } })
		wall(L, W, "z", -30.5, -half, -31, { { -45, 6 } })
		wall(L, W, "z", 30.5, -half, -31, { { -52, 6, WINDOW }, { -39, 6 } })
		-- make-up, outside the spawn room's north door (its twin: outside the east room's south door)
		low(L, "desk", -52, -23, -45, -20.5)
		low(L, "desk", -41, -28.5, -34, -26)
		tall(L, "locker", -42.5, -18.5, -40.5, -14, 7.5)
		-- the green room's lounge, between the spawn room and the concourse
		low(L, "sofa", -41, -3, -35, 0)
		set(L, -33.5, 6, "-x")
		-- wardrobe, outside the south door
		tall(L, "rack", -58, 20, -51, 21.5, 7)
		low(L, "case", -40, 24, -36, 27)
		low(L, "case", -52, 26.5, -48, 29)
		-- Studio A (its twin: Studio B): the stage, a set on it, cameras, the grid
		on(L, KIND.slab, "riser", -14, -58, 14, -46, 0, 1)
		local s1, s2 = on(L, KIND.prop, "set_warm", -12, -53, -4, -52, 1, 10, "set_blue")
		sign(s1, s2, "+z", "GOOD MORNING\nBELLWETHER", "white", "THE LATE\nMOVIE")
		on(L, KIND.prop, "set_warm", 4, -53, 12, -52, 1, 10, "set_blue")
		on(L, KIND.prop, "set_warm", -13, -52, -12, -47, 1, 10, "set_blue")
		on(L, KIND.cover, "sofa", -3, -51, 3, -49, 1, 1 + RAIL)
		camera(L, -10, -39, 0, -1)
		camera(L, 0, -37, 0, -1)
		camera(L, 11, -40, 0, -1)
		stand(L, -19, -44)
		stand(L, 19, -45)
		low(L, "case", -22, -37, -18, -34.5)
		low(L, "case", 21, -58, 25, -55.5)
		grid(L, -24, 24, { -55, -49, -43, -37 }, { -19, -11, -3, 5, 13 })
		local o1, o2 = on(L, KIND.prop, "on_air", -26, -31.4, -20, -31, DOOR + 0.6, DOOR + 2.6)
		sign(o1, o2, "+z", "ON AIR", "red")
		-- the north-west room: the prop store
		tall(L, "shelf", -57, -53.2, -47, -51.6, 9)
		tall(L, "shelf", -57, -45.2, -47, -43.6, 9)
		stack(L, "crate", -34.4, -60, -31, -56.6)
		low(L, "crate", -36, -40, -32.6, -36.6)
		-- the north-east room: Studio A's control booth, looking in through its window
		low(L, "console", 34, -55, 36.5, -49)
		tall(L, "rack", 57, -58, 59, -46, 7.5)
		low(L, "console", 44, -50, 52, -47.5)
		-- the concourse
		low(L, "bench", -27, -4, -25, 4)
		low(L, "planter", -22, 19.6, -19, 22)
	end

	-- STOREY 3: master control and the tape library
	do
		local L, W = 3, "wall3"
		wall(L, W, "z", -30.5, -30, 30, { { -20, 6 }, { -7, 8, WINDOW }, { 7, 8, WINDOW }, { 20, 6 } })
		wall(L, W, "z", -30.5, -half, -31, { { -45, 6 } })
		wall(L, W, "z", 30.5, -half, -31, { { -45, 6 } })
		-- master control: two rows of consoles facing the monitor wall on the west wall
		low(L, "console", -50, -20, -47.5, -4)
		low(L, "console", -50, 4, -47.5, 20)
		low(L, "console", -41, -12, -38.5, 12)
		for _, z in { -17, -9, 4, 12 } do
			local a, b = on(L, KIND.prop, "monitor", -59.6, z, -58.6, z + 5, 4, 8.4)
			plan.monitors[a] = "+x"
			plan.monitors[b] = "-x"
		end
		tall(L, "rack", -58, -29.5, -50, -27.5, 7.5)
		tall(L, "rack", -44, 27.5, -36, 29.5, 7.5)
		low(L, "cabinet", -36, -27, -32, -24.5)
		-- the tape library: shelving in rows with a break half way down each
		for _, x in { -20, -12, -4, 4, 12, 20 } do
			tall(L, "shelf", x - 0.75, -58, x + 0.75, -50, 9)
			tall(L, "shelf", x - 0.75, -46, x + 0.75, -38, 9)
		end
		-- the north-west room: telecine
		tall(L, "transmitter", -57, -57, -53, -54, 7)
		tall(L, "transmitter", -57, -46, -53, -43, 7)
		low(L, "console", -45, -50.5, -37, -48)
		low(L, "case", -38, -37, -34, -34)
		-- the north-east room: the audio booth
		low(L, "console", 40, -48, 52, -45.5)
		tall(L, "rack", 57.4, -57, 59.4, -51, 7)
		tall(L, "case", 34, -58.5, 37, -55.5, 6.8)
		low(L, "sheet", 50, -37, 56, -34.5)
		-- the concourse
		low(L, "bench", -22.5, -3, -20.5, 3)
		low(L, "planter", -27, 22, -24, 24.4)
		set(L, -18.5, -10, "-x")
	end

	-- STOREY 4: offices and the transmitter hall
	do
		local L, W = 4, "wall4"
		wall(L, W, "z", -43.5, -30, 30, { { -22, 5 }, { -7, 5 }, { 7, 5 }, { 22, 5 } })
		wall(L, W, "x", -15, -half, -44, nil)
		wall(L, W, "x", 0, -half, -44, nil)
		wall(L, W, "x", 15, -half, -44, nil)
		wall(L, W, "z", -30.5, -half, -31, { { -45, 6 } })
		wall(L, W, "z", 30.5, -half, -31, { { -45, 6 } })
		for _, z in { -22.5, -7.5, 7.5, 22.5 } do
			low(L, "desk", -55, z - 1.3, -49, z + 1.3)
			tall(L, "cabinet", -59.4, z + 3, -57.8, z + 6.5, 7)
		end
		-- planters between the offices' corridor and the concourse
		low(L, "planter", -31.5, -27, -29.5, -17)
		low(L, "planter", -31.5, -9, -29.5, 9)
		low(L, "planter", -31.5, 17, -29.5, 27)
		low(L, "sheet", -42, -2, -39.5, 4)
		-- the transmitter hall: cabinets in rows, a cable tray from each to the mast
		local t1, t2 = tall(L, "transmitter", -26, -53.5, -10, -50.5, 9)
		sign(t1, t2, "+z", "DANGER\nHIGH VOLTAGE", "yellow")
		tall(L, "transmitter", 10, -53.5, 26, -50.5, 9)
		tall(L, "transmitter", -18, -45.5, -2, -42.5, 9)
		tall(L, "transmitter", 4, -45.5, 20, -42.5, 9)
		tray(L, -6, -59, -5, -34)
		tray(L, 14, -59, 15, -34)
		low(L, "case", -27, -38, -23, -35)
		low(L, "drum", 24, -39.4, 27.4, -36)
		-- the north-west room: the boardroom
		low(L, "table", -54, -47, -38, -43.5)
		tall(L, "cabinet", -59.4, -58, -57.8, -50, 7)
		low(L, "sofa", -44, -58.5, -36, -56)
		-- the north-east room: the station manager's office
		low(L, "desk", 42, -52, 50, -49)
		low(L, "sheet", 34, -42, 36.5, -35)
		tall(L, "cabinet", 57.8, -58, 59.4, -52, 7)
		set(L, 54, -38, "-x")
		-- the concourse
		low(L, "bench", -22.5, 6, -20.5, 12)
		low(L, "case", -27, -14, -24, -11)
		-- the other half of the lighting rig, still hanging under the glass roof, and its chains
		on(L, KIND.prop, "truss", -13, -7, 9, -6.6, 9.2, 9.6)
		on(L, KIND.prop, "truss", -13, -5, 9, -4.6, 9.2, 9.6)
		for _, x in { -12, -5, 2, 8.6 } do
			on(L, KIND.prop, "truss", x, -6.6, x + 0.4, -5, 9.2, 9.6)
			on(L, KIND.prop, "cable", x + 0.1, -5.9, x + 0.3, -5.7, 9.6, H)
		end
		for _, x in { -10, -3, 5 } do
			local i, j = on(L, KIND.prop, "lamp", x, -6.4, x + 1.2, -5.2, 7.9, 9.2)
			lamp(i, j, 40, 1.2, "warm")
		end
	end

	-- cables hanging down the atrium's corners from the roof, storey after storey
	for level = 1, floors - 1 do
		on(level, KIND.prop, "cable", -14.6, -14.6, -14.2, -14.2, if level == 1 then 4 else 0, H)
		on(level, KIND.prop, "cable", 13.9, -14.4, 14.2, -14.1, if level == 2 then 6 else 0, H)
	end

	-- PAINT, last, when every wall it is on stands: each room's name over its doors, STAIRS over the cores'
	-- doors, the storey's number (1 to 5, as the station numbered them) on the four pillars at the
	-- atrium's corners, and the notices the last crew left. Written for the north and west; the twin of each
	-- is the south's and east's, with its own words where the rooms differ.
	type Names = { hall: { string }, nw: { string }, ne: { string }, notice: { string } }
	local NAMES: { Names } = {
		{
			hall = { "SCENERY STORE", "RECEPTION" },
			nw = { "RACKING", "STORES" },
			ne = { "CABLE STORE", "MAIL ROOM" },
			notice = { "DOCK STAFF\nONLY", "VISITORS REPORT\nTO RECEPTION" },
		},
		{
			hall = { "NEWS STUDIO", "SPORTS STUDIO" },
			nw = { "EDIT SUITES", "FILM EDITING" },
			ne = { "WEATHER", "TRAFFIC" },
			notice = { "QUIET PLEASE\nNEWS ON AIR", "DEADLINE\n5:45 SHARP" },
		},
		{
			hall = { "STUDIO A", "STUDIO B" },
			nw = { "PROP STORE", "PROP STORE" },
			ne = { "CONTROL A", "CONTROL B" },
			notice = { "NO ENTRY ON\nRED LIGHT", "NO ENTRY ON\nRED LIGHT" },
		},
		{
			hall = { "TAPE LIBRARY", "FILM VAULT" },
			nw = { "TELECINE", "DUBBING" },
			ne = { "AUDIO BOOTH", "VOICE BOOTH" },
			notice = { "SIGN OUT\nEVERY TAPE", "ENGINEERS\nONLY" },
		},
		{
			hall = { "TRANSMITTER", "TRANSMITTER" },
			nw = { "BOARDROOM", "CANTEEN" },
			ne = { "STATION MANAGER", "ACCOUNTS" },
			notice = { "DANGER\nRF RADIATION", "DANGER\nRF RADIATION" },
		},
	}
	for level = 0, floors - 1 do
		local n = NAMES[level + 1]
		local y = level * H
		-- the hall line, read from the building's middle; and the doors between the halls and the corner rooms
		local west = if level == 2 then -52 else -45
		over(level, -23, -30, "+z", 7, n.hall[1], n.hall[2])
		over(level, 23, -30, "+z", 7, n.hall[1], n.hall[2])
		over(level, west, -30, "+z", 5.4, n.nw[1], n.nw[2])
		over(level, 45, -30, "+z", 5.4, n.ne[1], n.ne[2])
		over(level, -30, -45, "+x", 5.4, n.nw[1], n.nw[2])
		over(level, -31, -45, "-x", 5.4, n.hall[1], n.hall[2])
		local east = if level == 2 then -39 else -45
		over(level, 30, east, "-x", 5.4, n.ne[1], n.ne[2])
		over(level, 31, east, "+x", 5.4, n.hall[1], n.hall[2])
		paint(-38.9, y + 6.3, -30, "+z", 6, 2.4, n.notice[1], "stencil", n.notice[2])
		-- the stairs
		local at = if level % 2 == 0 then -1 else 1
		over(level, at * END, -31, "-z", 3.6, "STAIRS")
		if level == 0 then
			over(level, -at * END, -31, "-z", 3.6, "STAIRS")
		else
			over(level, at * 16, -26, if at < 0 then "-x" else "+x", 3.6, "STAIRS")
			if level % 2 == 1 then
				over(level, at * END, -21, "+z", 3.6, "STAIRS")
			end
		end
		-- the storey's number, high on every face of the two northern pillars (and their twins)
		local digit = tostring(level + 1)
		for _, px in { -19, 19 } do
			paint(px, y + 8.5, -18, "+z", 1.8, 3, digit, "white", nil, "plate")
			paint(px, y + 8.5, -20, "-z", 1.8, 3, digit, "white", nil, "plate")
			paint(px + 1, y + 8.5, -19, "+x", 1.8, 3, digit, "white", nil, "plate")
			paint(px - 1, y + 8.5, -19, "-x", 1.8, 3, digit, "white", nil, "plate")
		end
	end
	-- the wings
	over(0, -30, -19.5, "+x", 5.4, "WORKSHOP", "GARAGE")
	over(0, -30, 19.5, "+x", 5.4, "STORES", "DOCK STORES")
	paint(60, 5, -25, "-x", 7, 3, "LOADING\nKEEP CLEAR", "yellow", "BAY 2\nSEALED")
	over(1, -45, 0, "+x", 4.4, "EDITOR", "SPORTS EDITOR")
	over(1, -52, -45, "+z", 4.4, "EDIT 1", "CUTTING 1")
	over(1, -37, -45, "+z", 4.4, "EDIT 2", "CUTTING 2")
	over(2, -30, -22, "+x", 5.4, "MAKE-UP", "MAKE-UP")
	over(2, -30, 22, "+x", 5.4, "WARDROBE", "WARDROBE")
	paint(-57.5, roomY + DOOR + 1.5, -13, "-z", 4.4, 1.7, "ORANGE TEAM", "white", "TEAL TEAM", "plate")
	paint(-46.5, roomY + DOOR + 1.5, 13, "+z", 4.4, 1.7, "ORANGE TEAM", "white", "TEAL TEAM", "plate")
	over(3, -30, -20, "+x", 5.4, "MASTER CONTROL", "CONTINUITY")
	over(3, -30, 20, "+x", 5.4, "MASTER CONTROL", "CONTINUITY")
	for i, z in { -22, -7, 7, 22 } do
		local west = ({ "SALES", "NEWS DIRECTOR", "PROGRAMMES", "ENGINEERING" })[i]
		local east = ({ "PERSONNEL", "LEGAL", "PROMOTIONS", "PAYROLL" })[i]
		over(4, -43, z, "+x", 4.4, west, east)
	end
	return plan
end

return Plan
