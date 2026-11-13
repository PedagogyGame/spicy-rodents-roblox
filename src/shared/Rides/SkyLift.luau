--!strict
-- ReplicatedStorage.Shared.Rides.SkyLift
-- The sky lift's one source of truth (brief v2 line 250 "A sky lift up a slight hill to a hilltop restaurant";
-- §15 "no controls, no score, you get on and it happens"; §14 first person on boarding). Pure: no Instances, no
-- engine calls, no side effects on require. Geometry comes from data/expansion.json (rides.sky_lift, compiled to
-- Generated/Expansion); everything else here is a constant. Every bake, the server and the client read the lift
-- from this module and from nothing else.
--
-- THE CONTRACT (agreed before the builders fan out; change it only with every lane's spec green)
--
-- Units, frames, clock
--   * Studs, seconds, radians. World frame: +Y up; yaw is Roblox's: CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
--     looks along (-sin yaw, 0, -cos yaw) and its RightVector is (cos yaw, 0, -sin yaw).
--   * `t` is the lift's clock: t = workspace:GetServerTimeNow() - ReplicatedStorage:GetAttribute(EPOCH_ATTRIBUTE).
--     The server writes the epoch once at boot (keep an existing one); every client draws the cabins from the same
--     clock, so no cabin pose is ever sent over the network. Every function below accepts any real t (periodic).
--
-- The line (data: rides.sky_lift.points, bullwheel to bullwheel)
--   points[1] base bullwheel centre (f4_lift_base/cable_out), points[2] base station mouth (the building's face),
--   points[3..11] the nine tower heads, points[12] the summit mouth (the front of the Lookout's lift hall),
--   points[13] summit bullwheel centre (f3_hilltop/cable_in). The cable is straight between points; where the line
--   turns in plan (29 degrees at the summit mouth, 1 degree at the base mouth) it follows a FILLET_RADIUS arc.
--   Two strands run STRAND either side of that centre line at the same height, UP on the right of the base->summit
--   direction, DOWN on the right of summit->base; at each end a level half circle of radius STRAND (the bullwheel)
--   joins them. In both stations the cable is level at floor + 12, so a cabin floor (HANG below the cable) is at
--   floor + PLATFORM_HEIGHT, the platforms' height.
--
-- The loop and the timetable
--   * Loop distance s runs 0..length: s = 0 where the UP strand leaves the base bullwheel; then the up strand, the
--     summit bullwheel, the down strand, the base bullwheel.
--   * Speed along the loop: LINE_SPEED on the line; inside each station a constant-acceleration ramp from the mouth
--     to CREEP_RUN from the bullwheel, then CREEP_SPEED for CREEP_RUN, round the bullwheel and CREEP_RUN out again,
--     then a ramp back up to the mouth. Doors are open exactly while a cabin creeps (doorsOpen; at least 6 s).
--   * Cabin i (1..CABINS) is at the same place as cabin 1 was (i - 1) * period() / CABINS seconds earlier: equal
--     headway in time everywhere, at most one cabin in a station at a time.
--   * Riders get out at the station's `alight` point on the arriving strand (BOARD_RUN before the bullwheel) and get
--     in at its `board` point on the departing strand (BOARD_RUN after it); both are inside the open-door stretch.
--
-- Cabin model frame (CabinTemplate, lane 2; the client places it, lane 5)
--   Origin = the centre of the floor's top surface; -Z forward (the way it travels), +X right (the door side: the
--   platforms are always on a cabin's right), +Y up. Outer box: X +-CABIN_WIDTH/2, Z +-CABIN_LENGTH/2,
--   Y -CABIN_BELOW .. CABIN_HEIGHT - CABIN_BELOW. The grip is HANG straight above the origin; the hanger arm is the
--   column X, Z within +-HANGER_HALF from the roof to GRIP_ABOVE over the cable. Seats: SEAT_LOCAL[k] = { x, y, z,
--   facing } in this frame (y = the seat's top surface; facing 0 = looking forward (-Z), pi = looking back); the
--   eye (EyeSocket) is EYE_ABOVE_SEAT straight above the seat's top. Seats 1, 2 face forward on the rear bench,
--   3, 4 face back on the front bench; odd seats on the left.
--
-- Interface (all pure; tables returned are frozen and shared: do not mutate)
--   CONSTANTS: CABINS 6, SEATS 4, LINE_SPEED 15, CREEP_SPEED 2.5, CREEP_RUN 14, BOARD_RUN 7, STRAND 5, HANG 10.5,
--     PLATFORM_HEIGHT 1.5, PLATFORM_OFFSET 4.5, CABIN_LENGTH 8, CABIN_WIDTH 6, CABIN_HEIGHT 8, CABIN_BELOW 0.5,
--     HANGER_HALF 0.6, GRIP_ABOVE 0.6, SEAT_HEIGHT 1.5, EYE_ABOVE_SEAT 3, SEAT_LOCAL, DOOR_SECS 1, FILLET_RADIUS 20,
--     EPOCH_ATTRIBUTE "SkyLiftEpoch", RIDE_ID "sky_lift", STATIONS { "base", "summit" }
--   period() -> seconds for one cabin to go round once (all cabins: one every period() / CABINS)
--   loop() -> { length, points: { Vec } (closed: points[#points] == points[1]; every straight span one segment,
--     arcs in pieces of <= 1 st), dist: { number } (loop distance at each point) }: the two strands and both
--     bullwheels at cable height, for drawing the cable
--   at(s) -> x, y, z, yaw: the grip on the cable at loop distance s, facing the way of travel
--   speedAt(s) -> studs per second along the loop
--   sAt(sigma) -> s: loop distance at sigma seconds into a lap (sigma in [0, period()))
--   cabin(i, t) -> x, y, z, yaw, phase, doorsOpen, s: cabin i's floor origin and yaw (frame above); phase is "base"
--     or "summit" while its doors are open there, else "up" or "down" (the strand it is on); s its loop distance
--   doorFrac(i, t) -> 0..1 how open cabin i's doors are (DOOR_SECS to open, DOOR_SECS to close, inside doorsOpen)
--   seat(i, k, t) -> x, y, z, yaw: the top of seat k of cabin i in the world and the way its sitter faces
--   eye(i, k, t) -> x, y, z, yaw: that sitter's eye (EyeSocket)
--   nextDeparture(station, t) -> cabin, boardAt, arriveAt: the first cabin to pass `station`'s board point at or
--     after t, the time it does (seat the rider then), and the time it passes the other station's alight point
--     (put the rider on that platform then)
--   stations() -> { base: Station, summit: Station } (type below): venue ids, floor and platform heights, the
--     bullwheel and mouth, the board and alight stand points with the yaw that faces the cabin door, and the
--     open-door window in lap seconds
--   towers() -> { Tower }: the nine tower heads in order from the base: centre-line point (cable height), the yaw
--     of the line there, and the two strand points (the crossarm carries the sheaves there)
--   sweptClear(x, y, z, margin?) -> boolean: true when the point is outside every place a cabin and its hanger
--     ever occupy (grown by margin); bakes keep every part's corners and centre clear
--   rideTime(station) -> seconds from boarding at `station` to alighting at the other one
--   clock(serverNow, epoch) -> t
--   build(ride, baseVenue, summitVenue) -> Model and use(Model?): specs only (edited data); nil restores the
--     compiled data. The model is built on the first call, from Data.default():module("Expansion").
--
-- Numbers on the compiled data (rides_skylift.spec): loop 1,802 st; lap 153.6 s; a cabin every 25.6 s; doors open
-- 17.5 s per station; a ride 65 s either way; tower heads 26 st over the ground (32 at the first and last);
-- cabin undersides at least 8.7 st over the ground outside 30 st of the stations, 3.1 st inside that apron.
-- Up close (venue-local, measured with sweptClear): in the Lookout's lift hall the cabins sweep X -44..-26.5,
-- D -25..20.5 (platforms: X -50..-44 to board going down, X -26.5..-20 to alight); they leave the hall's front
-- through X -44..-27.3 and cross the terrace strip (D -47..-25) at deck height at X below -27.5, so the terrace
-- stays at X -24 and up. In the base station they sweep X -20.5..25, D -6.5..10.5 (board from the front platform,
-- D -15..-6.5; alight on the back one, D 10.5..15) and leave through its +X face.
--
-- Lane notes: the bakes (lanes 2, 3, 7) never put anything inside sweptClear; the server (lane 4) seats at
-- nextDeparture's boardAt and alights at arriveAt; the client (lane 5) calls cabin() each frame for six local
-- clones and seat()/eye() for riders. Nothing here knows about players.

local Data = require("../Data")

local SkyLift = {}

export type Vec = { x: number, y: number, z: number }
export type Station = {
	id: string, -- "base" | "summit"
	venue: string, -- f4_lift_base | f3_hilltop
	floorY: number, -- the venue's finished floor
	platformY: number, -- floorY + PLATFORM_HEIGHT: the platforms and every cabin floor in the station
	wheel: Vec, -- bullwheel centre at cable height
	mouth: Vec, -- where the centre line crosses the building's face, at cable height
	inwardYaw: number, -- yaw of the station's axis, pointing from the mouth to the bullwheel
	departing: string, -- strand a rider leaves on: "up" at the base, "down" at the summit
	arriving: string,
	board: Vec, -- stand point on the departing platform beside the cabin door (y = platformY)
	boardYaw: number, -- facing the door
	alight: Vec, -- stand point on the arriving platform
	alightYaw: number,
	boardS: number, -- loop distance of the cabin origin when its rider boards
	alightS: number,
	boardSigma: number, -- lap seconds at which a cabin passes the board point
	alightSigma: number,
	doorsOpenSigma: number, -- lap seconds at which the doors open here
	doorsCloseSigma: number, -- ... and close (may be less than doorsOpenSigma: the window wraps the lap)
	dwell: number, -- seconds the doors are open
}
export type Tower = { index: number, x: number, y: number, z: number, yaw: number, up: Vec, down: Vec }
export type Loop = { length: number, points: { Vec }, dist: { number } }

SkyLift.RIDE_ID = "sky_lift"
SkyLift.EPOCH_ATTRIBUTE = "SkyLiftEpoch"
SkyLift.STATIONS = table.freeze({ "base", "summit" })
SkyLift.CABINS = 6
SkyLift.SEATS = 4
SkyLift.LINE_SPEED = 15 -- studs a second on the line (brief: a sightseeing ride; BATCH2 item 36)
SkyLift.CREEP_SPEED = 2.5 -- through the stations, doors open
SkyLift.CREEP_RUN = 14 -- studs of strand at creep speed either side of each bullwheel
SkyLift.BOARD_RUN = 7 -- board and alight points: this far along the strand from the bullwheel
SkyLift.STRAND = 5 -- half the gauge; also the bullwheel radius
SkyLift.HANG = 10.5 -- cable down to the cabin floor's top
SkyLift.PLATFORM_HEIGHT = 1.5 -- platforms above the station floor (= cabin floor in the station)
SkyLift.PLATFORM_OFFSET = 4.5 -- strand to the stand point beside the door, horizontally
SkyLift.CABIN_LENGTH = 8
SkyLift.CABIN_WIDTH = 6
SkyLift.CABIN_HEIGHT = 8
SkyLift.CABIN_BELOW = 0.5 -- the cabin's underside below the floor's top
SkyLift.HANGER_HALF = 0.6
SkyLift.GRIP_ABOVE = 0.6
SkyLift.SEAT_HEIGHT = 1.5
SkyLift.EYE_ABOVE_SEAT = 3
SkyLift.SEAT_LOCAL = table.freeze({
	table.freeze({ -1.4, 1.5, 2.9, 0 }), -- rear bench, left, facing forward
	table.freeze({ 1.4, 1.5, 2.9, 0 }), -- rear bench, right
	table.freeze({ -1.4, 1.5, -2.9, math.pi }), -- front bench, left (of the cabin), facing back
	table.freeze({ 1.4, 1.5, -2.9, math.pi }), -- front bench, right
})
SkyLift.DOOR_SECS = 1
SkyLift.FILLET_RADIUS = 20
local FILLET_MIN_TURN = math.rad(0.25) -- smaller plan turns (rounding at the towers) are mitred, not filleted
local SWEEP_STEP = 0.5 -- swept-volume samples along the loop
local CELL = 16 -- swept-volume hash cell (XZ)

-- one piece of the loop: a straight span or a level-in-plan arc (y varies linearly along both)
type Piece = {
	arc: boolean,
	s0: number,
	len: number,
	ax: number,
	az: number,
	bx: number,
	bz: number,
	cx: number,
	cz: number,
	r: number,
	a0: number,
	sweep: number,
	y0: number,
	y1: number,
	h0: number, -- centre-line horizontal distance from the base bullwheel at the piece's start and end
	h1: number,
	strand: string, -- "up" | "down" | "summit" | "base" (the last two: the bullwheels)
}
type Seg = { s0: number, s1: number, v0: number, v1: number, t0: number, dur: number }
type Model = {
	pieces: { Piece },
	length: number,
	segs: { Seg },
	period: number,
	stations: { base: Station, summit: Station },
	towers: { Tower },
	loop: Loop,
	totalH: number,
	baseOpen: number,
	baseClose: number,
	summitOpen: number,
	summitClose: number,
	summitWheelS: number, -- loop distance where the summit bullwheel starts (end of the up strand)
	downEndS: number, -- ... where the base bullwheel starts (end of the down strand)
}

local function yawOf(dx: number, dz: number): number
	return math.atan2(-dx, -dz)
end

local function vec(x: number, y: number, z: number): Vec
	return table.freeze({ x = x, y = y, z = z })
end

local function pieceAt(p: Piece, u: number): (number, number, number, number, number)
	local f = if p.len > 0 then math.clamp(u / p.len, 0, 1) else 0
	local y = p.y0 + (p.y1 - p.y0) * f
	if p.arc then
		local th = p.a0 + p.sweep * f
		local c, s = math.cos(th), math.sin(th)
		local sg = if p.sweep >= 0 then 1 else -1
		return p.cx + p.r * c, y, p.cz + p.r * s, -s * sg, c * sg
	end
	local dx, dz = p.bx - p.ax, p.bz - p.az
	local l = math.sqrt(dx * dx + dz * dz)
	return p.ax + dx * f, y, p.az + dz * f, dx / l, dz / l
end

local function flip(p: Piece): Piece
	local q = table.clone(p)
	if p.arc then
		q.a0 = p.a0 + p.sweep
		q.sweep = -p.sweep
	else
		q.ax, q.az, q.bx, q.bz = p.bx, p.bz, p.ax, p.az
	end
	q.y0, q.y1 = p.y1, p.y0
	q.h0, q.h1 = p.h1, p.h0
	return q
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- Build everything from the compiled ride record and its two venues. Exposed for specs that pass edited data.
function SkyLift.build(ride: any, baseVenue: any, summitVenue: any): Model
	local P = ride.points :: { { number } }
	local n = #P
	assert(n >= 5, "sky_lift: bullwheel, mouth, towers, mouth, bullwheel")
	-- plan directions, horizontal lengths and cumulative h
	local dirs: { { number } } = {}
	local hl: { number } = {}
	local hAt: { number } = { 0 }
	for k = 1, n - 1 do
		local dx, dz = P[k + 1][1] - P[k][1], P[k + 1][3] - P[k][3]
		local l = math.sqrt(dx * dx + dz * dz)
		dirs[k] = { dx / l, dz / l }
		hl[k] = l
		hAt[k + 1] = hAt[k] + l
	end
	local totalH = hAt[n]
	local function yAt(h: number): number
		if h <= 0 then
			return P[1][2]
		end
		for k = 1, n - 1 do
			if h <= hAt[k + 1] then
				local f = (h - hAt[k]) / hl[k]
				return P[k][2] + (P[k + 1][2] - P[k][2]) * f
			end
		end
		return P[n][2]
	end
	local function right(k: number): (number, number)
		return -dirs[k][2], dirs[k][1]
	end
	-- fillets at plan turns
	local turn: { number } = {}
	local tan: { number } = {}
	for k = 2, n - 1 do
		local a, b = dirs[k - 1], dirs[k]
		local cross = a[1] * b[2] - a[2] * b[1]
		local dot = a[1] * b[1] + a[2] * b[2]
		local ang = math.atan2(cross, dot) -- > 0: a turn toward the right (right = (-dz, dx))
		turn[k] = ang
		tan[k] = if math.abs(ang) > FILLET_MIN_TURN then SkyLift.FILLET_RADIUS * math.tan(math.abs(ang) / 2) else 0
		assert(tan[k] < hl[k - 1] / 2 and tan[k] < hl[k] / 2, "sky_lift: a fillet longer than its spans")
	end
	tan[1], tan[n] = 0, 0
	-- the strand offset `o` (right of the base->summit direction) as pieces in base->summit order
	local function strandPieces(o: number, name: string): { Piece }
		local out: { Piece } = {}
		local function vertexOffset(k: number): (number, number)
			if k == 1 then
				local rx, rz = right(1)
				return P[1][1] + rx * o, P[1][3] + rz * o
			elseif k == n then
				local rx, rz = right(n - 1)
				return P[n][1] + rx * o, P[n][3] + rz * o
			end
			-- mitred (no fillet at this vertex)
			local ax, az = right(k - 1)
			local bx, bz = right(k)
			local mx, mz = ax + bx, az + bz
			local ml = math.sqrt(mx * mx + mz * mz)
			local c = math.cos(turn[k] / 2)
			return P[k][1] + mx / ml * o / c, P[k][3] + mz / ml * o / c
		end
		for k = 1, n - 1 do
			local d = dirs[k]
			local rx, rz = right(k)
			local h0, h1 = hAt[k] + tan[k], hAt[k + 1] - tan[k + 1]
			local ax, az, bx, bz
			if tan[k] > 0 then
				ax, az = P[k][1] + d[1] * tan[k] + rx * o, P[k][3] + d[2] * tan[k] + rz * o
			else
				ax, az = vertexOffset(k)
			end
			if tan[k + 1] > 0 then
				bx, bz = P[k + 1][1] - d[1] * tan[k + 1] + rx * o, P[k + 1][3] - d[2] * tan[k + 1] + rz * o
			else
				bx, bz = vertexOffset(k + 1)
			end
			table.insert(out, {
				arc = false,
				s0 = 0,
				len = 0,
				ax = ax,
				az = az,
				bx = bx,
				bz = bz,
				cx = 0,
				cz = 0,
				r = 0,
				a0 = 0,
				sweep = 0,
				y0 = yAt(h0),
				y1 = yAt(h1),
				h0 = h0,
				h1 = h1,
				strand = name,
			})
			local v = k + 1
			if v < n and tan[v] > 0 then
				-- the fillet at vertex v: centre on the inside of the turn, radius R -+ o
				local din, dout = dirs[v - 1], dirs[v]
				local irx, irz = right(v - 1)
				local orx, orz = right(v)
				local side = if turn[v] > 0 then 1 else -1
				local R = SkyLift.FILLET_RADIUS
				local tx, tz = P[v][1] - din[1] * tan[v], P[v][3] - din[2] * tan[v]
				local cx, cz = tx + irx * R * side, tz + irz * R * side
				local sx, sz = tx + irx * o, tz + irz * o
				local ex, ez = P[v][1] + dout[1] * tan[v] + orx * o, P[v][3] + dout[2] * tan[v] + orz * o
				local a0 = math.atan2(sz - cz, sx - cx)
				local a1 = math.atan2(ez - cz, ex - cx)
				local r = math.sqrt((sx - cx) ^ 2 + (sz - cz) ^ 2)
				assert(r > 1, "sky_lift: the fillet radius must exceed the strand offset")
				table.insert(out, {
					arc = true,
					s0 = 0,
					len = 0,
					ax = 0,
					az = 0,
					bx = 0,
					bz = 0,
					cx = cx,
					cz = cz,
					r = r,
					a0 = a0,
					sweep = wrapAngle(a1 - a0),
					y0 = yAt(hAt[v] - tan[v]),
					y1 = yAt(hAt[v] + tan[v]),
					h0 = hAt[v] - tan[v],
					h1 = hAt[v] + tan[v],
					strand = name,
				})
			end
		end
		return out
	end
	local S = SkyLift.STRAND
	local pieces: { Piece } = {}
	for _, p in strandPieces(S, "up") do
		table.insert(pieces, p)
	end
	local function wheel(k: number, segIdx: number, startSign: number, name: string): Piece
		local rx, rz = right(segIdx)
		return {
			arc = true,
			s0 = 0,
			len = 0,
			ax = 0,
			az = 0,
			bx = 0,
			bz = 0,
			cx = P[k][1],
			cz = P[k][3],
			r = S,
			a0 = math.atan2(rz * startSign, rx * startSign),
			sweep = -math.pi, -- round the far side (past the end of the line)
			y0 = P[k][2],
			y1 = P[k][2],
			h0 = hAt[k],
			h1 = hAt[k],
			strand = name,
		}
	end
	table.insert(pieces, wheel(n, n - 1, 1, "summit"))
	local down = strandPieces(-S, "down")
	for i = #down, 1, -1 do
		table.insert(pieces, flip(down[i]))
	end
	table.insert(pieces, wheel(1, 1, -1, "base"))
	-- lengths and loop distances
	local s = 0
	for _, p in pieces do
		local horiz = if p.arc then p.r * math.abs(p.sweep) else math.sqrt((p.bx - p.ax) ^ 2 + (p.bz - p.az) ^ 2)
		p.len = math.sqrt(horiz * horiz + (p.y1 - p.y0) ^ 2)
		p.s0 = s
		s += p.len
	end
	local length = s
	local summitWheelS, downEndS = 0, 0
	for _, p in pieces do
		if p.strand == "summit" then
			summitWheelS = p.s0
		elseif p.strand == "base" then
			downEndS = p.s0
		end
	end
	-- loop distance on a strand at centre-line h
	local function sOn(strand: string, h: number): number
		for _, p in pieces do
			if p.strand == strand then
				local lo, hi = math.min(p.h0, p.h1), math.max(p.h0, p.h1)
				if h >= lo - 1e-9 and h <= hi + 1e-9 and hi > lo then
					return p.s0 + p.len * (h - p.h0) / (p.h1 - p.h0)
				end
			end
		end
		error(`sky_lift: no {strand} strand at h {h}`)
	end
	local mouthBase, mouthSummit = hAt[2], hAt[n - 1]
	local CR, VL, VC = SkyLift.CREEP_RUN, SkyLift.LINE_SPEED, SkyLift.CREEP_SPEED
	assert(mouthBase > CR and totalH - mouthSummit > CR, "sky_lift: a station shorter than its creep run")
	local marks = {
		{ 0, VC },
		{ sOn("up", CR), VC },
		{ sOn("up", mouthBase), VL },
		{ sOn("up", mouthSummit), VL },
		{ sOn("up", totalH - CR), VC },
		{ sOn("down", totalH - CR), VC },
		{ sOn("down", mouthSummit), VL },
		{ sOn("down", mouthBase), VL },
		{ sOn("down", CR), VC },
		{ length, VC },
	}
	local segs: { Seg } = {}
	local t = 0
	for i = 1, #marks - 1 do
		local a, b = marks[i], marks[i + 1]
		local d = b[1] - a[1]
		assert(d > 0, "sky_lift: station zones overlap")
		local dur = 2 * d / (a[2] + b[2])
		table.insert(segs, { s0 = a[1], s1 = b[1], v0 = a[2], v1 = b[2], t0 = t, dur = dur })
		t += dur
	end
	local period = t
	local function sigmaOf(sv: number): number
		for _, g in segs do
			if sv <= g.s1 then
				local ds = sv - g.s0
				if g.v0 == g.v1 then
					return g.t0 + ds / g.v0
				end
				local acc = (g.v1 - g.v0) / g.dur
				return g.t0 + (-g.v0 + math.sqrt(math.max(0, g.v0 * g.v0 + 2 * acc * ds))) / acc
			end
		end
		return period
	end
	local model: Model = {
		pieces = pieces,
		length = length,
		segs = segs,
		period = period,
		stations = nil :: any,
		towers = {},
		loop = nil :: any,
		totalH = totalH,
		baseOpen = sigmaOf(marks[9][1]),
		baseClose = sigmaOf(marks[2][1]),
		summitOpen = sigmaOf(marks[5][1]),
		summitClose = sigmaOf(marks[6][1]),
		summitWheelS = summitWheelS,
		downEndS = downEndS,
	}
	local function posOf(sv: number): (number, number, number, number, number)
		local u = sv % length
		local lo, hi = 1, #pieces
		while lo < hi do
			local mid = (lo + hi + 1) // 2
			if pieces[mid].s0 <= u then
				lo = mid
			else
				hi = mid - 1
			end
		end
		local p = pieces[lo]
		return pieceAt(p, u - p.s0)
	end
	-- stations
	local function station(id: string, venue: any, wheelK: number, mouthK: number): Station
		local departing = if id == "base" then "up" else "down"
		local arriving = if id == "base" then "down" else "up"
		local hBoard = if id == "base" then SkyLift.BOARD_RUN else totalH - SkyLift.BOARD_RUN
		local function stand(strand: string): (Vec, number, number)
			local sv = sOn(strand, hBoard)
			local x, y, z, dx, dz = posOf(sv)
			local rx, rz = -dz, dx
			local o = SkyLift.PLATFORM_OFFSET
			return vec(x + rx * o, y - SkyLift.HANG, z + rz * o), yawOf(-rx, -rz), sv
		end
		local board, boardYaw, boardS = stand(departing)
		local alight, alightYaw, alightS = stand(arriving)
		local open = if id == "base" then model.baseOpen else model.summitOpen
		local close = if id == "base" then model.baseClose else model.summitClose
		local wx, wz = P[wheelK][1], P[wheelK][3]
		local mx, mz = P[mouthK][1], P[mouthK][3]
		return table.freeze({
			id = id,
			venue = venue.id,
			floorY = venue.floorY,
			platformY = venue.floorY + SkyLift.PLATFORM_HEIGHT,
			wheel = vec(wx, P[wheelK][2], wz),
			mouth = vec(mx, P[mouthK][2], mz),
			inwardYaw = yawOf(wx - mx, wz - mz),
			departing = departing,
			arriving = arriving,
			board = board,
			boardYaw = boardYaw,
			alight = alight,
			alightYaw = alightYaw,
			boardS = boardS,
			alightS = alightS,
			boardSigma = sigmaOf(boardS),
			alightSigma = sigmaOf(alightS),
			doorsOpenSigma = open,
			doorsCloseSigma = close,
			dwell = (close - open) % period,
		})
	end
	model.stations = table.freeze({
		base = station("base", baseVenue, 1, 2),
		summit = station("summit", summitVenue, n, n - 1),
	})
	-- towers
	local towers: { Tower } = {}
	for k = 3, n - 2 do
		local d = dirs[k]
		-- the strands' mitre at this head (the line is straight in plan here to within rounding)
		local ax, az = right(k - 1)
		local bx, bz = right(k)
		local ml = math.sqrt((ax + bx) ^ 2 + (az + bz) ^ 2)
		local mc = math.cos(turn[k] / 2)
		local rx, rz = (ax + bx) / ml / mc, (az + bz) / ml / mc
		local p = P[k]
		assert(tan[k] == 0, "sky_lift: a tower stands where the line is straight in plan")
		table.insert(
			towers,
			table.freeze({
				index = k - 2,
				x = p[1],
				y = p[2],
				z = p[3],
				yaw = yawOf(d[1], d[2]),
				up = vec(p[1] + rx * S, p[2], p[3] + rz * S),
				down = vec(p[1] - rx * S, p[2], p[3] - rz * S),
			})
		)
	end
	model.towers = table.freeze(towers)
	-- the loop for drawing
	local pts: { Vec } = {}
	local dist: { number } = {}
	for _, p in pieces do
		local steps = if p.arc then math.max(2, math.ceil(p.len / 1)) else 1
		for k = 0, steps - 1 do
			local u = p.len * k / steps
			local x, y, z = pieceAt(p, u)
			table.insert(pts, vec(x, y, z))
			table.insert(dist, p.s0 + u)
		end
	end
	table.insert(pts, pts[1])
	table.insert(dist, length)
	model.loop = table.freeze({ length = length, points = table.freeze(pts), dist = table.freeze(dist) })
	return model
end

local defaultModel: Model? = nil
local function M(): Model
	if defaultModel == nil then
		local exp = Data.default():module("Expansion") :: any
		local ride, venues = nil, {}
		for _, r in exp.rides or {} do
			if r.id == SkyLift.RIDE_ID then
				ride = r
			end
		end
		assert(ride ~= nil, "sky_lift: no ride in Generated/Expansion")
		for _, v in exp.venues do
			venues[v.id] = v
		end
		local function venueOf(ref: string): any
			local id = string.sub(ref, 1, (string.find(ref, "/", 1, true) or 0) - 1)
			return assert(venues[id], "sky_lift: no venue " .. id)
		end
		defaultModel = SkyLift.build(ride, venueOf(ride.from), venueOf(ride.to))
	end
	return defaultModel :: Model
end

-- Use a model built from other data (specs); nil goes back to the compiled data.
function SkyLift.use(model: Model?)
	defaultModel = model
	SkyLift._swept = nil
end

function SkyLift.period(): number
	return M().period
end

function SkyLift.loop(): Loop
	return M().loop
end

function SkyLift.at(s: number): (number, number, number, number)
	local m = M()
	local u = s % m.length
	local pieces = m.pieces
	local lo, hi = 1, #pieces
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if pieces[mid].s0 <= u then
			lo = mid
		else
			hi = mid - 1
		end
	end
	local p = pieces[lo]
	local x, y, z, dx, dz = pieceAt(p, u - p.s0)
	return x, y, z, yawOf(dx, dz)
end

local function segOfSigma(m: Model, sigma: number): Seg
	local segs = m.segs
	local lo, hi = 1, #segs
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if segs[mid].t0 <= sigma then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return segs[lo]
end

function SkyLift.sAt(sigma: number): number
	local m = M()
	local sg = sigma % m.period
	local g = segOfSigma(m, sg)
	local tau = math.clamp(sg - g.t0, 0, g.dur)
	local acc = (g.v1 - g.v0) / g.dur
	return math.min(g.s0 + g.v0 * tau + 0.5 * acc * tau * tau, g.s1)
end

function SkyLift.speedAt(s: number): number
	local m = M()
	local u = s % m.length
	for _, g in m.segs do
		if u <= g.s1 then
			if g.v0 == g.v1 then
				return g.v0
			end
			local f = (u - g.s0) / (g.s1 - g.s0)
			return math.sqrt(g.v0 * g.v0 + (g.v1 * g.v1 - g.v0 * g.v0) * f)
		end
	end
	return SkyLift.CREEP_SPEED
end

local function sigmaOf(i: number, t: number): number
	local m = M()
	return (t - (i - 1) * m.period / SkyLift.CABINS) % m.period
end

local function within(sg: number, open: number, close: number): boolean
	if open <= close then
		return sg >= open and sg <= close
	end
	return sg >= open or sg <= close
end

function SkyLift.cabin(i: number, t: number): (number, number, number, number, string, boolean, number)
	local m = M()
	local sg = sigmaOf(i, t)
	local s = SkyLift.sAt(sg)
	local x, y, z, yaw = SkyLift.at(s)
	local phase
	local open = true
	if within(sg, m.baseOpen, m.baseClose) then
		phase = "base"
	elseif within(sg, m.summitOpen, m.summitClose) then
		phase = "summit"
	else
		open = false
		phase = if s < m.summitWheelS + math.pi * SkyLift.STRAND / 2 then "up" else "down"
	end
	return x, y - SkyLift.HANG, z, yaw, phase, open, s
end

function SkyLift.doorFrac(i: number, t: number): number
	local m = M()
	local sg = sigmaOf(i, t)
	local P = m.period
	for _, w in { { m.baseOpen, m.baseClose }, { m.summitOpen, m.summitClose } } do
		if within(sg, w[1], w[2]) then
			local since = (sg - w[1]) % P
			local left = (w[2] - sg) % P
			return math.clamp(math.min(since, left) / SkyLift.DOOR_SECS, 0, 1)
		end
	end
	return 0
end

function SkyLift.seat(i: number, k: number, t: number): (number, number, number, number)
	local x, y, z, yaw = SkyLift.cabin(i, t)
	local L = SkyLift.SEAT_LOCAL[k]
	assert(L ~= nil, "sky_lift: seat 1..4")
	-- local (lx, ly, lz) -> world under CFrame.Angles(0, yaw, 0)
	local c, s = math.cos(yaw), math.sin(yaw)
	return x + L[1] * c + L[3] * s, y + L[2], z - L[1] * s + L[3] * c, yaw + L[4]
end

function SkyLift.eye(i: number, k: number, t: number): (number, number, number, number)
	local x, y, z, yaw = SkyLift.seat(i, k, t)
	return x, y + SkyLift.EYE_ABOVE_SEAT, z, yaw
end

function SkyLift.stations(): { base: Station, summit: Station }
	return M().stations
end

function SkyLift.towers(): { Tower }
	return M().towers
end

function SkyLift.nextDeparture(station: string, t: number): (number, number, number)
	local m = M()
	local st = (m.stations :: any)[station] :: Station
	assert(st ~= nil, "sky_lift: station is base or summit")
	local other = if station == "base" then m.stations.summit else m.stations.base
	local head = m.period / SkyLift.CABINS
	local j = math.ceil((t - st.boardSigma) / head - 1e-9)
	local boardAt = st.boardSigma + j * head
	local cabin = (j % SkyLift.CABINS) + 1
	return cabin, boardAt, boardAt + (other.alightSigma - st.boardSigma) % m.period
end

function SkyLift.rideTime(station: string): number
	local _, b, a = SkyLift.nextDeparture(station, 0)
	return a - b
end

function SkyLift.clock(serverNow: number, epoch: number): number
	return serverNow - epoch
end

-- swept volume: cabin poses every SWEEP_STEP along the loop, hashed by XZ cell
SkyLift._swept = nil :: { [number]: { { number } } }?
local function sweptCells(): { [number]: { { number } } }
	if SkyLift._swept then
		return SkyLift._swept
	end
	local m = M()
	local cells: { [number]: { { number } } } = {}
	local count = math.ceil(m.length / SWEEP_STEP)
	for k = 0, count - 1 do
		local x, y, z, yaw = SkyLift.at(m.length * k / count)
		local key = math.floor(x / CELL) * 65536 + math.floor(z / CELL)
		local list = cells[key]
		if list == nil then
			list = {}
			cells[key] = list
		end
		table.insert(list, { x, y - SkyLift.HANG, z, math.cos(yaw), math.sin(yaw) })
	end
	SkyLift._swept = cells
	return cells
end

function SkyLift.sweptClear(x: number, y: number, z: number, margin: number?): boolean
	local g = margin or 0
	local cells = sweptCells()
	local reach = math.sqrt((SkyLift.CABIN_LENGTH / 2) ^ 2 + (SkyLift.CABIN_WIDTH / 2) ^ 2) + g + SWEEP_STEP
	local cx0, cx1 = math.floor((x - reach) / CELL), math.floor((x + reach) / CELL)
	local cz0, cz1 = math.floor((z - reach) / CELL), math.floor((z + reach) / CELL)
	local hw, hl = SkyLift.CABIN_WIDTH / 2 + g, SkyLift.CABIN_LENGTH / 2 + g
	local hh = SkyLift.HANGER_HALF + g
	for cx = cx0, cx1 do
		for cz = cz0, cz1 do
			local list: { { number } } = cells[cx * 65536 + cz] or {}
			for _, p in list do
				local dx, dz = x - p[1], z - p[3]
				local r = dx * p[4] - dz * p[5]
				local f = -(dx * p[5] + dz * p[4])
				local dy = y - p[2]
				if
					math.abs(r) <= hw
					and math.abs(f) <= hl
					and dy >= -SkyLift.CABIN_BELOW - g
					and dy <= SkyLift.CABIN_HEIGHT - SkyLift.CABIN_BELOW + g
				then
					return false
				end
				if
					math.abs(r) <= hh
					and math.abs(f) <= hh
					and dy >= 0
					and dy <= SkyLift.HANG + SkyLift.GRIP_ABOVE + g
				then
					return false
				end
			end
		end
	end
	return true
end

return SkyLift
