--!strict
-- ServerScriptService.Server.Actors.Perception
-- Spatial-grid threat queries and the v5.4 `spotted` predicate ported with its concealment terms
-- (humans_actors §5.3, L7027-7051; hedgePatches L3573-3579; GARDEN_X/Z L3590-3591; BUILD_PLAN §1.4,
-- D4). Golden-tested against tests/golden/spotted.json (3,010 vectors) in tests/unit/perception.
-- Interface: newGrid(cellStuds) -> Grid (set/remove/query), spotted(observer, target, ctx) -> boolean,
-- spottedDetailed(...) -> Details, defaultConcealment() (the v5.4 volumes until town/concealment.json).
-- Pure. Studs everywhere; every HTML constant goes through Config/Units once, at module load.
-- Height: the port measures the target's height ABOVE LOCAL GROUND (target.groundY), as the spec's
-- porting note demands [humans_actors §15]; with groundY = 0 it reproduces the HTML's absolute-Y test.

local Units = require("../../shared/Config/Units")

export type Observer = {
	x: number,
	y: number,
	z: number,
	facing: number, -- HTML yaw: towards = (sin f, 0, cos f)
	witnessUntil: number?, -- crime-scene memory (time); nil = 0
}

export type Target = {
	x: number,
	y: number,
	z: number,
	groundY: number?, -- local ground height under the target (nil = 0: absolute Y, as v5.4)
	moveSpeed: number, -- studs/s
	focus: boolean, -- stalking (first person)
	inInterior: boolean, -- inside a house interior: never visible, only audible
}

export type Concealment = {
	-- gardens: |x - cx| < halfX, |z - cz| < halfZ while height < maxH
	gardens: { { cx: number, cz: number, halfX: number, halfZ: number, maxH: number } },
	-- hedges: |x - cx| < len/2 + pad, |z - cz| < h + padZ while height < maxH (v5.4's 4th value is the
	-- bush height AND the z half-extent, humans_actors §5.3)
	hedges: { { cx: number, cz: number, len: number, h: number } },
	hedgeMaxH: number,
	hedgePadX: number,
	hedgePadZ: number,
}

export type Ctx = {
	time: number,
	hotHere: boolean, -- the observer stands inside a live crime-scene radius
	concealment: Concealment?,
}

export type Details = {
	dist2: number,
	isVisible: boolean,
	inView: boolean,
	noise: boolean,
	gardenBlind: boolean,
	hedgeBlind: boolean,
	concealed: boolean,
	hotHere: boolean,
	remembered: boolean,
	radar: number,
	spotted: boolean,
}

local Perception = {}

-- v5.4 constants, HTML units -> studs (speeds in u/s -> studs/s). Cited to L7027-7051.
local C = {
	lowY = Units.st(4), -- isVisible: pY < 4
	nearY = Units.st(4.7), -- ... or dist < 4.7
	inViewDot = 0.28, -- unitless (about +/-74 degrees)
	noiseSpeedFocus = Units.st(2.5),
	noiseSpeedWalk = Units.st(4.7),
	noiseDist = Units.st(8.6),
	noiseMaxAbove = Units.st(22),
	gardenMaxH = Units.st(2.4),
	hedgeMaxH = Units.st(2.8),
	hedgePadX = Units.st(1.8),
	hedgePadZ = Units.st(1.1),
	stillSpeed = Units.st(3.4), -- concealed needs moveSpeed < 3.4
	sightCap = Units.st(20),
	sight = Units.st(14.5),
	peripheral = Units.st(6.8),
	canopyY = Units.st(5.2), -- never seen at or above 5.2
	hearCap = Units.st(16),
	hear = Units.st(10.3),
	radarHot = 3,
}
Perception.constants = C

-- The v5.4 concealment volumes (Tabasco garden plot and the 5 hedge patches) in studs. W1 replaces
-- this with data/town/concealment.json [wildlife_foraging verifier 1].
function Perception.defaultConcealment(): Concealment
	local st = Units.st
	return {
		gardens = { { cx = st(115), cz = st(341), halfX = st(27), halfZ = st(15), maxH = C.gardenMaxH } },
		hedges = {
			{ cx = st(125), cz = st(303), len = st(14), h = st(2.3) },
			{ cx = st(118), cz = st(372), len = st(11), h = st(3) },
			{ cx = st(-104), cz = st(305), len = st(18), h = st(2.4) },
			{ cx = st(290), cz = st(306), len = st(22), h = st(2.6) },
			{ cx = st(613), cz = st(421), len = st(15), h = st(2.2) },
		},
		hedgeMaxH = C.hedgeMaxH,
		hedgePadX = C.hedgePadX,
		hedgePadZ = C.hedgePadZ,
	}
end

-- Build a Concealment from HTML-unit tables (the golden file's own hedgePatches / garden).
function Perception.concealmentFromHtml(hedgePatches: { { number } }, garden: { x: number, z: number }): Concealment
	local out = Perception.defaultConcealment()
	out.gardens = {
		{
			cx = Units.st(garden.x),
			cz = Units.st(garden.z),
			halfX = Units.st(27),
			halfZ = Units.st(15),
			maxH = C.gardenMaxH,
		},
	}
	out.hedges = {}
	for _, hp in hedgePatches do
		table.insert(
			out.hedges,
			{ cx = Units.st(hp[1]), cz = Units.st(hp[2]), len = Units.st(hp[3]), h = Units.st(hp[4]) }
		)
	end
	return out
end

local function concealedAt(conc: Concealment?, x: number, z: number, height: number): (boolean, boolean)
	if not conc then
		return false, false
	end
	local gardenBlind = false
	for _, g in conc.gardens do
		if height < g.maxH and math.abs(x - g.cx) < g.halfX and math.abs(z - g.cz) < g.halfZ then
			gardenBlind = true
			break
		end
	end
	local hedgeBlind = false
	if height < conc.hedgeMaxH then
		for _, hp in conc.hedges do
			if math.abs(x - hp.cx) < hp.len / 2 + conc.hedgePadX and math.abs(z - hp.cz) < hp.h + conc.hedgePadZ then
				hedgeBlind = true
				break
			end
		end
	end
	return gardenBlind, hedgeBlind
end

-- The predicate, verbatim in structure (L7027-7051), returning every intermediate.
function Perception.spottedDetailed(observer: Observer, target: Target, ctx: Ctx): Details
	local dx, dz = target.x - observer.x, target.z - observer.z
	local dist2 = math.sqrt(dx * dx + dz * dz)
	local groundY = target.groundY or 0
	local height = target.y - groundY
	local isVisible = not target.inInterior and (height < C.lowY or (height > C.lowY and dist2 < C.nearY))
	-- towards = (sin f, cos f); inView = normalize(diff.xz) . towards > 0.28 (a zero diff normalises to 0 in three.js)
	local inView = false
	if dist2 > 0 then
		local dot = (dx / dist2) * math.sin(observer.facing) + (dz / dist2) * math.cos(observer.facing)
		inView = dot > C.inViewDot
	end
	local noiseSpeed = if target.focus then C.noiseSpeedFocus else C.noiseSpeedWalk
	local noise = target.moveSpeed > noiseSpeed and dist2 < C.noiseDist and (target.y - observer.y) < C.noiseMaxAbove
	local gardenBlind, hedgeBlind = concealedAt(ctx.concealment, target.x, target.z, height)
	local concealed = (gardenBlind or hedgeBlind) and target.moveSpeed < C.stillSpeed
	local remembered = (observer.witnessUntil or 0) > ctx.time
	local radar = if ctx.hotHere or remembered then C.radarHot else 1
	local spotted = not concealed
		and (
			(
				isVisible
				and dist2 < math.min(C.sightCap, C.sight * radar)
				and (inView or dist2 < C.peripheral)
				and height < C.canopyY
			) or (noise and dist2 < math.min(C.hearCap, C.hear * radar))
		)
	return {
		dist2 = dist2,
		isVisible = isVisible,
		inView = inView,
		noise = noise,
		gardenBlind = gardenBlind,
		hedgeBlind = hedgeBlind,
		concealed = concealed,
		hotHere = ctx.hotHere,
		remembered = remembered,
		radar = radar,
		spotted = spotted,
	}
end

-- Hot path: the same logic without the details table.
function Perception.spotted(observer: Observer, target: Target, ctx: Ctx): boolean
	local dx, dz = target.x - observer.x, target.z - observer.z
	local dist2 = math.sqrt(dx * dx + dz * dz)
	local remembered = (observer.witnessUntil or 0) > ctx.time
	local radar = if ctx.hotHere or remembered then C.radarHot else 1
	-- early out: beyond every range nothing can be spotted
	if dist2 >= math.min(C.sightCap, C.sight * radar) and dist2 >= math.min(C.hearCap, C.hear * radar) then
		return false
	end
	local height = target.y - (target.groundY or 0)
	local gardenBlind, hedgeBlind = concealedAt(ctx.concealment, target.x, target.z, height)
	if (gardenBlind or hedgeBlind) and target.moveSpeed < C.stillSpeed then
		return false
	end
	local isVisible = not target.inInterior and (height < C.lowY or (height > C.lowY and dist2 < C.nearY))
	if isVisible and dist2 < math.min(C.sightCap, C.sight * radar) and height < C.canopyY then
		local inView = false
		if dist2 > 0 then
			local dot = (dx / dist2) * math.sin(observer.facing) + (dz / dist2) * math.cos(observer.facing)
			inView = dot > C.inViewDot
		end
		if inView or dist2 < C.peripheral then
			return true
		end
	end
	local noiseSpeed = if target.focus then C.noiseSpeedFocus else C.noiseSpeedWalk
	local noise = target.moveSpeed > noiseSpeed and dist2 < C.noiseDist and (target.y - observer.y) < C.noiseMaxAbove
	return noise and dist2 < math.min(C.hearCap, C.hear * radar)
end

-- ---------------------------------------------------------------- grid

export type Grid = {
	cell: number,
	cells: { [number]: { number } },
	where: { [number]: number }, -- id -> cell key
	xs: { [number]: number },
	zs: { [number]: number },
	count: number,
	set: (self: Grid, id: number, x: number, z: number) -> (),
	remove: (self: Grid, id: number) -> (),
	query: (self: Grid, x: number, z: number, r: number, out: { number }) -> number,
}

local KEY_OFFSET = 32768
local KEY_STRIDE = 65536

local function cellKey(cx: number, cz: number): number
	return (cx + KEY_OFFSET) * KEY_STRIDE + (cz + KEY_OFFSET)
end

local GridMethods = {}
GridMethods.__index = GridMethods

function GridMethods.set(self: Grid, id: number, x: number, z: number)
	local cx, cz = math.floor(x / self.cell), math.floor(z / self.cell)
	local key = cellKey(cx, cz)
	local old = self.where[id]
	if old ~= key then
		if old then
			local list = self.cells[old]
			local n = #list
			for i = 1, n do
				if list[i] == id then
					list[i] = list[n]
					list[n] = nil
					break
				end
			end
		else
			self.count += 1
		end
		local list = self.cells[key]
		if not list then
			list = {}
			self.cells[key] = list
		end
		table.insert(list, id)
		self.where[id] = key
	end
	self.xs[id] = x
	self.zs[id] = z
end

function GridMethods.remove(self: Grid, id: number)
	local key = self.where[id]
	if not key then
		return
	end
	local list = self.cells[key]
	local n = #list
	for i = 1, n do
		if list[i] == id then
			list[i] = list[n]
			list[n] = nil
			break
		end
	end
	self.where[id] = nil
	self.xs[id] = nil
	self.zs[id] = nil
	self.count -= 1
end

-- Ids within radius r of (x, z), appended to out (cleared first). Returns the count.
function GridMethods.query(self: Grid, x: number, z: number, r: number, out: { number }): number
	table.clear(out)
	local cell = self.cell
	local cx0, cx1 = math.floor((x - r) / cell), math.floor((x + r) / cell)
	local cz0, cz1 = math.floor((z - r) / cell), math.floor((z + r) / cell)
	local r2 = r * r
	local n = 0
	for cx = cx0, cx1 do
		for cz = cz0, cz1 do
			local list = self.cells[cellKey(cx, cz)]
			if list then
				for _, id in list do
					local dx, dz = self.xs[id] - x, self.zs[id] - z
					if dx * dx + dz * dz <= r2 then
						n += 1
						out[n] = id
					end
				end
			end
		end
	end
	return n
end

-- A grid with cells of `cellStuds` (the spec suggests about 16 u = 40 st [humans_actors §15]).
function Perception.newGrid(cellStuds: number?): Grid
	local grid = setmetatable({
		cell = cellStuds or Units.st(16),
		cells = {},
		where = {},
		xs = {},
		zs = {},
		count = 0,
	}, GridMethods)
	return (grid :: any) :: Grid
end

return Perception
