--!strict
-- ServerScriptService.Server.WorldGen.InteriorCheck
-- The interiors' exit check, on the bake plans alone (so Lune and the engine give the same verdict and
-- nothing here trusts the solver that laid the rooms out, Builders/Furnish). For every enterable lot
-- (the four FRB houses, the hospital, the police station) and every interior room:
--   1. furnished for its purpose: the pieces a room of its kind must hold are there (REQUIRED);
--   2. solid pieces stand inside their room, clear of the walls, the door leaves and each other, and
--      none stands in a room open to the street (the ambulance bay);
--   3. nothing floats and nothing is buried: every piece's lowest part rests on the floor (a rug on the
--      floor finish), or it is wall-mounted and hangs on a wall of its room; nothing pokes through the
--      ceiling;
--   4. doorways are clear (4 st in front of every door on both sides) and a body 1 st in radius can walk
--      from the room's first door to every other door, to the middle of the room and to every hide spot,
--      station and shelf (a flood fill on a 0.5 st grid, pieces and walls inflated by the radius);
--   5. there is light: at least one fixture with a PointLight per room, one per 2,500 st2 in a big room;
--   6. there is a ceiling over the room and a floor finish under it.
-- Interface: lot(plan) -> { rooms, lights, pieces, failures }; run(plans) -> the same, summed, failures
--   prefixed with the lot id; REQUIRED[roomKind] = { rule }
-- Pure.

local Geometry = require("./Geometry")
local Spec = require("./Spec")
local Yield = require("./Yield")

local InteriorCheck = {}

InteriorCheck.BODY = 1.0 -- studs: the radius of the body that must get through
InteriorCheck.CELL = 0.5

export type Rule = {
	kit: string?, -- a piece of this kind ...
	n: number?, -- ... at least this many (default 1)
	attr: string?, -- or: the sum of this attribute over the pieces of the kind ...
	min: number?, -- ... is at least this
	has: { string }?, -- every piece of the kind carries these attributes
	station: string?, -- a Station part of this kind
	anyOf: { string }?, -- one of these kinds
}

-- What a room of each kind must hold (the owner's list, 2026-11-10).
InteriorCheck.REQUIRED = {
	living = {
		{ kit = "sofa" },
		{ kit = "armchair" },
		{ kit = "coffee_table" },
		{ kit = "rug" },
		{ kit = "tv_stand" },
		{ kit = "bookshelf" },
		{ kit = "floor_lamp" },
	},
	kitchen = {
		{ kit = "counter_run", has = { "Sink", "Hob" } },
		{ kit = "fridge" },
		{ kit = "dining_set", attr = "Seats", min = 2 },
	},
	bedroom = { { kit = "bed" }, { kit = "nightstand" }, { kit = "wardrobe" }, { kit = "rug" } },
	bath = { { anyOf = { "bathtub", "shower" } }, { kit = "toilet" }, { kit = "basin" }, { kit = "mirror" } },
	hall = { { kit = "coat_hooks" }, { kit = "shoe_bench" } },
	dining = { { kit = "dining_set", attr = "Seats", min = 4 } },
	study = { { kit = "desk" }, { kit = "bookshelf" } },
	den = { { kit = "armchair" }, { kit = "bookshelf" } },
	pantry = { { kit = "pantry_shelf", n = 2 } },
	reception = { { station = "admit" }, { kit = "waiting_row", attr = "Seats", min = 8 } },
	triage = { { station = "triage" }, { kit = "treatment_bay", n = 2 }, { kit = "medicine_cabinet" } },
	pharmacy = { { station = "dispense" }, { kit = "medicine_cabinet", n = 2 } },
	ward = { { kit = "ward_bed", n = 6, has = { "Curtain" } }, { kit = "medicine_cabinet" } },
	isolation = { { kit = "ward_bed", n = 2, has = { "Curtain" } }, { kit = "medicine_cabinet" } },
	staff = { { kit = "counter_run" }, { kit = "dining_set", attr = "Seats", min = 4 } },
	supply = { { kit = "pantry_shelf", n = 4 }, { kit = "medicine_cabinet" } },
	lobby = { { station = "desk" }, { kit = "waiting_row", attr = "Seats", min = 8 } },
	briefing = { { station = "quest_board" }, { kit = "briefing_row", attr = "Seats", min = 8 } },
	dispatch = { { station = "drone_console" }, { kit = "desk" } },
	lockers = { { kit = "cell", has = { "Cell" } }, { kit = "locker_bank", attr = "Lockers", min = 6 } },
} :: { [string]: { Rule } }

local NO_RULES: { Rule } = table.freeze({})
local NO_ATTRIBUTES: { string } = table.freeze({})

type Box = { x0: number, x1: number, y0: number, y1: number, z0: number, z1: number }

local function boxOf(s: Spec.PartSpec): Box
	local x0, x1, y0, y1, z0, z1 = Geometry.aabb(s :: any)
	return { x0 = x0, x1 = x1, y0 = y0, y1 = y1, z0 = z0, z1 = z1 }
end

local function overlap(a: Box, b: Box, tol: number): boolean
	return math.min(a.x1, b.x1) - math.max(a.x0, b.x0) > tol
		and math.min(a.y1, b.y1) - math.max(a.y0, b.y0) > tol
		and math.min(a.z1, b.z1) - math.max(a.z0, b.z0) > tol
end

function InteriorCheck.lot(p: Spec.BuildPlan): { [string]: any }
	local failures: { string } = {}
	local function fail(msg: string)
		table.insert(failures, msg)
	end
	local BODY, CELL = InteriorCheck.BODY, InteriorCheck.CELL
	local byName: { [string]: Spec.PartSpec } = {}
	local floor: Spec.PartSpec? = nil
	local ceiling: Spec.PartSpec? = nil
	local nav: Spec.PartSpec? = nil
	local rooms: { { part: Spec.PartSpec, box: Box, id: string, kind: string } } = {}
	local walls: { Box } = {}
	local doors: { { part: Spec.PartSpec, box: Box } } = {}
	local cores: { { part: Spec.PartSpec, box: Box, piece: string } } = {}
	local roots: { Spec.PartSpec } = {}
	local lights: { Spec.PartSpec } = {}
	local finishes: { [string]: boolean } = {}
	for _, s in p.parts do
		byName[s.name] = s
		local a: any = s.attrs or {}
		if s.name == "Floor" then
			floor = s
		elseif s.role == "Ceiling" then
			ceiling = s
		elseif s.name == "Nav" then
			nav = s
		elseif s.role == "Room" then
			if a.Exterior ~= true then
				table.insert(rooms, { part = s, box = boxOf(s), id = a.RoomId, kind = a.RoomKind or "" })
			end
		elseif s.role == "Wall" and s.canCollide then
			table.insert(walls, boxOf(s))
		elseif s.role == "Door" then
			table.insert(doors, { part = s, box = boxOf(s) })
		elseif s.role == "Light" and a.Room then
			table.insert(lights, s)
		elseif string.sub(s.name, 1, 7) == "Finish_" then
			finishes[string.sub(s.name, 8)] = true
		end
		if (s.role == "Furniture" or s.role == "Station" or s.role == "Shelf") and s.canCollide then
			table.insert(cores, { part = s, box = boxOf(s), piece = a.Part or s.name })
		end
		if a.Kit or s.role == "Station" or s.role == "Shelf" then
			table.insert(roots, s)
		end
	end
	if not floor or not nav then
		return { rooms = 0, lights = 0, pieces = 0, failures = { "no Floor or Nav part" } }
	end
	local floorTop = floor.cy + floor.sy / 2
	if not ceiling then
		fail("no ceiling")
	end
	local ceilY = if ceiling then ceiling.cy - ceiling.sy / 2 else math.huge

	-- exterior rooms (open to the street): nothing solid stands there
	for _, s in p.parts do
		local a: any = s.attrs or {}
		if s.role == "Room" and a.Exterior == true then
			local b = boxOf(s)
			for _, c in cores do
				if c.box.x1 > b.x0 and c.box.x0 < b.x1 and c.box.z1 > b.z0 and c.box.z0 < b.z1 then
					fail(`{c.part.name} stands in the open room {a.RoomId}`)
				end
			end
		end
	end

	-- pieces: every root with all the parts named after it
	local groups: { [string]: Box } = {}
	for _, r in roots do
		local g = boxOf(r)
		local prefix = r.name .. "_"
		for _, s in p.parts do
			if string.sub(s.name, 1, #prefix) == prefix then
				local b = boxOf(s)
				g.x0, g.x1 = math.min(g.x0, b.x0), math.max(g.x1, b.x1)
				g.y0, g.y1 = math.min(g.y0, b.y0), math.max(g.y1, b.y1)
				g.z0, g.z1 = math.min(g.z0, b.z0), math.max(g.z1, b.z1)
			end
		end
		groups[r.name] = g
	end

	-- PointLights by host part
	local lit: { [string]: boolean } = {}
	for _, e in p.extras or Spec.NO_EXTRAS do
		if e.kind == "PointLight" then
			lit[e.part] = true
		end
	end
	-- nav extras (hide spots, stations, shelves) in world coordinates
	local frame = Geometry.frame(nav.cx, 0, nav.cz, nav.yaw)
	local spots: { { name: string, x: number, z: number } } = {}
	for _, e in p.extras or Spec.NO_EXTRAS do
		local a: any = e.attrs or {}
		if e.kind == "Attachment" and e.part == "Nav" and e.offset then
			if a.Kind == "hide" or a.Kind == "station" or a.Kind == "shelf" then
				local wx, _, wz = Geometry.point(frame, e.offset[1], 0, e.offset[3])
				table.insert(spots, { name = e.name, x = wx, z = wz })
			end
		end
	end

	local pieces = 0
	for _, room in rooms do
		local rb = room.box
		local tag = room.id
		local function inRoom(x: number, z: number): boolean
			return x > rb.x0 and x < rb.x1 and z > rb.z0 and z < rb.z1
		end
		-- 1. furnished for its purpose
		local mine: { Spec.PartSpec } = {}
		for _, r in roots do
			local a: any = r.attrs or {}
			if a.Room == room.id then
				table.insert(mine, r)
				pieces += 1
			end
		end
		local rules: { Rule }? = InteriorCheck.REQUIRED[room.kind]
		if not rules then
			fail(`{tag}: unknown room kind "{room.kind}"`)
		end
		for _, rule in rules or NO_RULES do
			if rule.station then
				local ok = false
				for _, r in mine do
					ok = ok or (r.role == "Station" and (r.attrs :: any).Station == rule.station)
				end
				if not ok then
					fail(`{tag} ({room.kind}): no {rule.station} station`)
				end
			else
				local kinds = rule.anyOf or { rule.kit :: string }
				local n, sum = 0, 0
				for _, r in mine do
					local a: any = r.attrs
					if table.find(kinds, a.Kit) then
						n += 1
						if rule.attr then
							sum += (a[rule.attr] or 0) :: number
						end
						for _, h in rule.has or NO_ATTRIBUTES do
							if a[h] ~= true then
								fail(`{tag}: {r.name} lacks {h}`)
							end
						end
					end
				end
				if n < (rule.n or 1) then
					fail(`{tag} ({room.kind}): {n} of {rule.n or 1} {table.concat(kinds, " or ")}`)
				elseif rule.attr and sum < (rule.min or 1) then
					fail(`{tag} ({room.kind}): {rule.attr} {sum} of {rule.min} over {table.concat(kinds, " or ")}`)
				end
			end
		end

		-- 2. solid pieces: inside the room, clear of walls, doors and each other
		local here: { { part: Spec.PartSpec, box: Box, piece: string } } = {}
		for _, c in cores do
			if inRoom((c.box.x0 + c.box.x1) / 2, (c.box.z0 + c.box.z1) / 2) then
				table.insert(here, c)
				local b = c.box
				if b.x0 < rb.x0 + 0.15 or b.x1 > rb.x1 - 0.15 or b.z0 < rb.z0 + 0.15 or b.z1 > rb.z1 - 0.15 then
					fail(`{tag}: {c.part.name} reaches out of the room`)
				end
				for _, w in walls do
					if overlap(b, w, 0.02) then
						fail(`{tag}: {c.part.name} stands in a wall`)
					end
				end
				for _, d in doors do
					if overlap(b, d.box, 0.02) then
						fail(`{tag}: {c.part.name} stands in the door {d.part.name}`)
					end
				end
			end
		end
		for i = 1, #here do
			for j = i + 1, #here do
				if here[i].piece ~= here[j].piece and overlap(here[i].box, here[j].box, 0.05) then
					fail(`{tag}: {here[i].part.name} and {here[j].part.name} overlap`)
				end
			end
		end

		-- 3. nothing floats, nothing is buried, nothing pokes through the ceiling
		for _, r in mine do
			local g = groups[r.name]
			local a: any = r.attrs
			if g.y1 > ceilY + 0.01 then
				fail(`{tag}: {r.name} pokes through the ceiling`)
			end
			if a.WallMounted then
				local gap = math.min(g.x0 - rb.x0, rb.x1 - g.x1, g.z0 - rb.z0, rb.z1 - g.z1)
				if gap > 0.9 or gap < 0 then
					fail(`{tag}: {r.name} hangs {string.format("%.2f", gap)} st from any wall`)
				end
				if g.y0 < floorTop + 1 then
					fail(`{tag}: {r.name} is wall-mounted but reaches the floor`)
				end
			else
				local lift = g.y0 - floorTop
				if lift > 0.07 then
					fail(`{tag}: {r.name} floats {string.format("%.2f", lift)} st over the floor`)
				elseif lift < -0.02 then
					fail(`{tag}: {r.name} is buried {string.format("%.2f", -lift)} st in the floor`)
				end
				if g.x0 < rb.x0 or g.x1 > rb.x1 or g.z0 < rb.z0 or g.z1 > rb.z1 then
					fail(`{tag}: {r.name} sticks out of the room`)
				end
			end
		end

		-- 4. doorways clear; a body can walk from the first door to everything
		local nx = math.max(1, math.ceil((rb.x1 - rb.x0) / CELL))
		local nz = math.max(1, math.ceil((rb.z1 - rb.z0) / CELL))
		local blocked: { boolean } = table.create(nx * nz, false)
		local function mark(b: Box, grow: number)
			local i0 = math.max(math.floor((b.x0 - grow - rb.x0) / CELL + 1e-6), 0)
			local i1 = math.min(math.ceil((b.x1 + grow - rb.x0) / CELL - 1e-6) - 1, nx - 1)
			local j0 = math.max(math.floor((b.z0 - grow - rb.z0) / CELL + 1e-6), 0)
			local j1 = math.min(math.ceil((b.z1 + grow - rb.z0) / CELL - 1e-6) - 1, nz - 1)
			for j = j0, j1 do
				for i = i0, i1 do
					blocked[j * nx + i + 1] = true
				end
			end
		end
		for _, w in walls do
			if
				w.x1 > rb.x0 - 1
				and w.x0 < rb.x1 + 1
				and w.z1 > rb.z0 - 1
				and w.z0 < rb.z1 + 1
				and w.y0 < floorTop + 5
			then
				mark(w, BODY)
			end
		end
		for _, c in here do
			mark(c.box, BODY)
		end
		local starts: { { name: string, x: number, z: number } } = {}
		for _, d in doors do
			local a: any = d.part.attrs or {}
			if a.RoomA == room.id or a.RoomB == room.id then
				local n = Geometry.rotate({ 0, 0, 1 }, d.part.yaw, 0, 0)
				for _, side in { -1, 1 } do
					local sx, sz = d.part.cx + n[1] * side * 1.7, d.part.cz + n[3] * side * 1.7
					if inRoom(sx, sz) then
						table.insert(starts, { name = d.part.name, x = sx, z = sz })
						-- the doorway: 4 st deep, the leaf's width
						local half = d.part.sx / 2
						local zone: Box
						if math.abs(n[3]) > 0.5 then
							local za, zb = d.part.cz + n[3] * side * 0.4, d.part.cz + n[3] * side * 4
							zone = {
								x0 = d.part.cx - half,
								x1 = d.part.cx + half,
								y0 = floorTop,
								y1 = floorTop + 8,
								z0 = math.min(za, zb),
								z1 = math.max(za, zb),
							}
						else
							local xa, xb = d.part.cx + n[1] * side * 0.4, d.part.cx + n[1] * side * 4
							zone = {
								x0 = math.min(xa, xb),
								x1 = math.max(xa, xb),
								y0 = floorTop,
								y1 = floorTop + 8,
								z0 = d.part.cz - half,
								z1 = d.part.cz + half,
							}
						end
						for _, c in here do
							if overlap(c.box, zone, 0.02) then
								fail(`{tag}: {c.part.name} stands in the doorway of {d.part.name}`)
							end
						end
					end
				end
			end
		end
		if #starts == 0 then
			fail(`{tag}: no door`)
		else
			local seen: { boolean } = table.create(nx * nz, false)
			local function cellOf(x: number, z: number): (number, number)
				return math.clamp(math.floor((x - rb.x0) / CELL), 0, nx - 1),
					math.clamp(math.floor((z - rb.z0) / CELL), 0, nz - 1)
			end
			local si, sj = cellOf(starts[1].x, starts[1].z)
			local queue = { sj * nx + si + 1 }
			seen[queue[1]] = true
			local head = 1
			while head <= #queue do
				local k = queue[head]
				head += 1
				local i, j = (k - 1) % nx, (k - 1) // nx
				for dj = -1, 1 do
					for di = -1, 1 do
						local ii, jj = i + di, j + dj
						if (di ~= 0 or dj ~= 0) and ii >= 0 and ii < nx and jj >= 0 and jj < nz then
							local kk = jj * nx + ii + 1
							if not seen[kk] and not blocked[kk] then
								seen[kk] = true
								table.insert(queue, kk)
							end
						end
					end
				end
			end
			local function reach(x: number, z: number, r: number): boolean
				local ci, cj = cellOf(x, z)
				local n = math.ceil(r / CELL)
				for j = math.max(cj - n, 0), math.min(cj + n, nz - 1) do
					for i = math.max(ci - n, 0), math.min(ci + n, nx - 1) do
						if
							seen[j * nx + i + 1]
							and (rb.x0 + (i + 0.5) * CELL - x) ^ 2 + (rb.z0 + (j + 0.5) * CELL - z) ^ 2 <= r * r
						then
							return true
						end
					end
				end
				return false
			end
			if blocked[sj * nx + si + 1] then
				fail(`{tag}: the way in at {starts[1].name} is blocked`)
			end
			for i = 2, #starts do
				if not reach(starts[i].x, starts[i].z, 1.0) then
					fail(`{tag}: no way from {starts[1].name} to {starts[i].name}`)
				end
			end
			if not reach((rb.x0 + rb.x1) / 2, (rb.z0 + rb.z1) / 2, 7) then
				fail(`{tag}: no way to the middle of the room`)
			end
			for _, s in spots do
				if inRoom(s.x, s.z) and not reach(s.x, s.z, 5.5) then
					fail(`{tag}: no way to {s.name}`)
				end
			end
		end

		-- 5. light
		local count = 0
		for _, l in lights do
			if (l.attrs :: any).Room == room.id then
				if lit[l.name] then
					count += 1
				else
					fail(`{tag}: {l.name} has no PointLight`)
				end
				if not inRoom(l.cx, l.cz) then
					fail(`{tag}: {l.name} hangs outside its room`)
				end
			end
		end
		local area = (rb.x1 - rb.x0) * (rb.z1 - rb.z0)
		local want = math.max(1, math.floor(area / 2500))
		if count < want then
			fail(`{tag}: {count} lights for {math.floor(area)} st2 (at least {want})`)
		end

		-- 6. a ceiling over it and a floor finish under it
		if ceiling then
			local cb = boxOf(ceiling)
			if cb.x0 > rb.x0 + 0.7 or cb.x1 < rb.x1 - 0.7 or cb.z0 > rb.z0 + 0.7 or cb.z1 < rb.z1 - 0.7 then
				fail(`{tag}: the ceiling does not cover the room`)
			end
		end
		if not finishes[room.id] then
			fail(`{tag}: no floor finish`)
		end
	end
	return { rooms = #rooms, lights = #lights, pieces = pieces, failures = failures }
end

-- Every enterable lot of the town.
function InteriorCheck.run(plans: { Spec.BuildPlan }): { [string]: any }
	local out = { lots = 0, rooms = 0, lights = 0, pieces = 0, failures = {} :: { string } }
	for _, p in plans do
		if p.kind == "lot" and p.attributes.Enterable == true then
			Yield.breathe()
			local r = InteriorCheck.lot(p)
			out.lots += 1
			out.rooms += r.rooms
			out.lights += r.lights
			out.pieces += r.pieces
			for _, f in r.failures do
				table.insert(out.failures, p.id .. ": " .. f)
			end
		end
	end
	return out
end

return InteriorCheck
