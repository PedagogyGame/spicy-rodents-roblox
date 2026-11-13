--!strict
-- ReplicatedStorage.Shared.Minigames.Pool.Shot
-- One whole shot as plain data: the SERVER runs the table model (Physics) to rest the moment the cue strikes,
-- judges the shot from what happened, and sends this same table to every client, which only plays it back
-- (the pattern of bowling's RollScript). Nobody simulates anything twice, so every screen shows exactly the
-- shot that was scored.
-- A script holds, for every ball on the table, where it started and a KEY POINT for each moment something
-- changed its motion (the strike, a ball, a cushion, a jaw, a post, a hole's rim): time, place, velocity,
-- roll, side spin, drop and mode. Between key points a ball moves by Cloth.advance alone, which is exact for
-- any time step, so pose() gives the same place the server's model had at any instant and a client can draw
-- at its own frame rate. A plain pot is three or four key points for each ball; a break is a few hundred in
-- all. The events (who hit what, how hard) ride along for the sounds and for the rules.
-- Times are seconds from the strike. On the wire a script travels as a buffer (pack / unpack): times, rest
-- places and small whole numbers exact, everything else as 32-bit floats, and only the parts of a key point
-- that are not zero: a break is about 6 KB where the plain table of numbers was 16 to 35 KB.
-- Pure; Lune-tested (tests/unit/pool_shot.spec.luau).
-- Interface: run(table, spots, strikes, maxT?) -> Script; pose(script, i, t) -> (x, z, y, mode, vx, vz, qx,
--   qz, s) for the i-th ball (script.ids[i] is its id); indexOf(script, id) -> i?; rest(script) -> { Spot }
--   (the balls left on the table, where they stopped); pots(script) -> { { ball, hole, t, cushions, by } } in
--   the order they dropped (cushions: those it touched before it first crossed that hole's rim; by: the
--   strikes whose chain of contacts reached it, as bits); firstHit(script, id) -> ball id (0: it touched no
--   ball); firstHits(script, id) -> { every ball it touched at that first instant }; firstTouch(script, id)
--   -> (kind, what) (the first ball, cushion, jaw or post the struck ball met: Physics.EV kind, and the ball
--   id or segment or post index; 0, 0: nothing); cues(script) -> { { t, name, volume } }; firstNear(script,
--   x, z, r) -> (t?, ball id?) (the first ball to come within r of a point: the animal rule); pack(script)
--   -> buffer; unpack(buffer) -> (Script?, why?); check(any) -> (Script?, why?); size(script) -> how many
--   numbers it carries; VERSION, MAX_T, REST_PAD, SINK

local Cloth = require("./Cloth")
local Physics = require("./Physics")
local Tables = require("./Tables")

local Shot = {}

Shot.VERSION = 2 -- 2: a pot carries whose strike reached it; firstAll and touch; the wire format
Shot.MAX_T = 40 -- seconds: no shot on these tables runs this long (the longest break is about a third of it)
Shot.REST_PAD = 0.35 -- seconds after the last ball stops before the shot is over
Shot.SINK = 0.5 -- studs below the cloth at which a pocketed ball is out of sight
Shot.CLICK_MERGE = 0.03 -- seconds: ball clicks closer than this are one sound (the break is a crack, not a buzz)

export type Strike = { id: number, vx: number, vz: number, qx: number, qz: number, s: number }

export type Script = {
	v: number,
	table: string,
	ids: { number },
	start: { number }, -- flat x, z for each ball, in ids order
	strikes: { number }, -- flat id, vx, vz, qx, qz, s
	tracks: { { number } }, -- per ball: flat key points (Physics.KEY_STRIDE numbers each); {} if nothing moved it
	events: { number }, -- flat t, kind, a, b, speed (Physics.EV)
	-- flat ball, hole, t, cushions, by, in drop order. cushions: those the ball touched before it first crossed
	-- the rim of the hole it went down in (the cushion behind a cup is not a bank). by: the strikes whose chain
	-- of contacts had reached the ball when it dropped, as bits (1: the first strike, 2: the second, 3: both)
	pots: { number },
	first: { number }, -- for each strike, the first ball the struck ball touched (0: none)
	-- for each strike, every ball the struck ball touched at that first instant (two balls lying together are
	-- hit as one: which of them is listed first is the table's own order, and means nothing)
	firstAll: { { number } },
	touch: { number }, -- for each strike, flat kind, what: the first ball, cushion, jaw or post it met (0, 0: none)
	firstT: number, -- when a struck ball first touched another ball (-1: never)
	railAfter: boolean, -- after that first touch some ball reached a cushion (a pot also satisfies the rules)
	rails: { number }, -- per ball: cushions touched this shot
	rest: { number }, -- flat id, x, z for every ball still on the table, where it stopped
	tEnd: number,
	capped: boolean, -- the shot ran into MAX_T and was stopped where it was (never seen in the specs)
	contacts: number,
	steps: number,
	knots: number, -- steps the model gave up with contacts unsettled (0 in every spec)
}

local KS = Physics.KEY_STRIDE
local ES = Physics.EVENT_STRIDE
local EV = Physics.EV
local PS = 5 -- numbers for each pot

function Shot.run(tb: Tables.Table, spots: { Tables.Spot }, strikes: { Strike }, maxT: number?): Script
	local w = Physics.world(tb, spots)
	local ids: { number } = table.create(#spots, 0)
	local start: { number } = table.create(#spots * 2, 0)
	local idx: { [number]: number } = {}
	for i, s in spots do
		ids[i] = s.id
		start[i * 2 - 1] = s.x
		start[i * 2] = s.z
		idx[s.id] = i
	end
	local flatStrikes: { number } = {}
	local struck: { [number]: number } = {}
	for k, st in strikes do
		Physics.strike(w, st.id, st.vx, st.vz, st.qx, st.qz, st.s)
		table.move({ st.id, st.vx, st.vz, st.qx, st.qz, st.s }, 1, 6, #flatStrikes + 1, flatStrikes)
		struck[st.id] = k
	end
	local limit = maxT or Shot.MAX_T
	local capped = false
	while Physics.step(w) do
		if w.t >= limit then
			capped = true
			break
		end
	end
	local tStop = w.t
	if capped then
		-- stop everything where it is (a key point each, so playback agrees)
		for i, b in w.balls do
			if b.mode == 1 or b.mode == 2 then
				b.vx, b.vz, b.qx, b.qz, b.s, b.y = 0, 0, 0, 0, 0, 0
				b.mode = 0
				local k = w.keys[i]
				table.move({ tStop, b.x, b.z, 0, 0, 0, 0, 0, 0, 0 }, 1, KS, #k + 1, k)
			end
		end
	end
	-- what the rules need, read off the events
	local first: { number } = table.create(#strikes, 0)
	local firstAt: { number } = table.create(#strikes, -1)
	local firstAll: { { number } } = {}
	local touch: { number } = table.create(#strikes * 2, 0)
	local reach: { [number]: number } = {} -- ball id -> the strikes whose chain of contacts has reached it
	for k, st in strikes do
		firstAll[k] = {}
		reach[st.id] = bit32.lshift(1, k - 1)
	end
	local firstT = -1
	local rails: { number } = table.create(#spots, 0)
	local atRim: { [number]: number } = {} -- ball * 8 + hole -> its cushions when it first crossed that rim
	local pots: { number } = {}
	local railAfter = false
	local ev = w.events
	local function met(k: number, other: number, t: number)
		if firstAt[k] < 0 then
			firstAt[k] = t
			first[k] = other
			firstT = if firstT < 0 then t else firstT
		end
		if firstAt[k] == t then
			table.insert(firstAll[k], other)
		end
		if touch[k * 2 - 1] == 0 then
			touch[k * 2 - 1], touch[k * 2] = EV.ball, other
		end
	end
	for e = 1, #ev, ES do
		local t, kind, a, b = ev[e], ev[e + 1], ev[e + 2], ev[e + 3]
		if kind == EV.ball then
			local ka, kb = struck[a], struck[b]
			if ka then
				met(ka, b, t)
			end
			if kb then
				met(kb, a, t)
			end
			local both = bit32.bor(reach[a] or 0, reach[b] or 0)
			reach[a], reach[b] = both, both
		elseif kind == EV.cushion or kind == EV.jaw or kind == EV.post then
			local k = struck[a]
			if k and touch[k * 2 - 1] == 0 then
				touch[k * 2 - 1], touch[k * 2] = kind, b
			end
			if kind == EV.cushion then
				rails[idx[a]] += 1
			end
			if kind ~= EV.post and firstT >= 0 then
				railAfter = true
			end
		elseif kind == EV.enter then
			if atRim[a * 8 + b] == nil then
				atRim[a * 8 + b] = rails[idx[a]]
			end
		elseif kind == EV.drop then
			table.move({ a, b, t, atRim[a * 8 + b] or rails[idx[a]], reach[a] or 0 }, 1, PS, #pots + 1, pots)
		end
	end
	local rest: { number } = {}
	for _, b in w.balls do
		if b.mode == 0 then
			table.move({ b.id, b.x, b.z }, 1, 3, #rest + 1, rest)
		end
	end
	return {
		v = Shot.VERSION,
		table = tb.id,
		ids = ids,
		start = start,
		strikes = flatStrikes,
		tracks = w.keys,
		events = ev,
		pots = pots,
		first = first,
		firstAll = firstAll,
		touch = touch,
		firstT = firstT,
		railAfter = railAfter,
		rails = rails,
		rest = rest,
		tEnd = tStop + Shot.REST_PAD,
		capped = capped,
		contacts = w.contacts,
		steps = w.steps,
		knots = w.knots,
	}
end

function Shot.indexOf(script: Script, id: number): number?
	return table.find(script.ids, id)
end

local scratch = Cloth.new(0, 0, 0)

-- Where the i-th ball is t seconds after the strike, and how it is moving and spinning.
function Shot.pose(
	script: Script,
	i: number,
	t: number
): (number, number, number, number, number, number, number, number, number)
	local k = script.tracks[i]
	local n = #k
	if n == 0 or t < k[1] then
		return script.start[i * 2 - 1], script.start[i * 2], 0, 0, 0, 0, 0, 0, 0
	end
	-- the last key point at or before t
	local lo, hi = 0, n / KS - 1
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if k[mid * KS + 1] <= t then
			lo = mid
		else
			hi = mid - 1
		end
	end
	local o = lo * KS
	local b = scratch
	b.x, b.z, b.vx, b.vz = k[o + 2], k[o + 3], k[o + 4], k[o + 5]
	b.qx, b.qz, b.s, b.y, b.mode = k[o + 6], k[o + 7], k[o + 8], k[o + 9], k[o + 10]
	local dt = t - k[o + 1]
	if b.mode == 3 then
		-- down the hole: keep falling until it is out of sight
		local vy = math.sqrt(-2 * Cloth.G * b.y)
		local y = b.y - vy * dt - 0.5 * Cloth.G * dt * dt
		return b.x, b.z, if y < -Shot.SINK then -Shot.SINK else y, 3, 0, 0, 0, 0, 0
	end
	Cloth.advance(b, dt)
	return b.x, b.z, b.y, b.mode, b.vx, b.vz, b.qx, b.qz, b.s
end

function Shot.rest(script: Script): { Tables.Spot }
	local out: { Tables.Spot } = {}
	local r = script.rest
	for i = 1, #r, 3 do
		table.insert(out, { id = r[i], x = r[i + 1], z = r[i + 2] })
	end
	return out
end

export type Pot = { ball: number, hole: number, t: number, cushions: number, by: number }

function Shot.pots(script: Script): { Pot }
	local out: { Pot } = {}
	local p = script.pots
	for i = 1, #p, PS do
		table.insert(out, { ball = p[i], hole = p[i + 1], t = p[i + 2], cushions = p[i + 3], by = p[i + 4] })
	end
	return out
end

local function strikeOf(script: Script, id: number): number
	local s = script.strikes
	for k = 1, #s / 6 do
		if s[(k - 1) * 6 + 1] == id then
			return k
		end
	end
	return 0
end

-- The first ball the struck ball `id` touched (0: none, or `id` was not struck).
function Shot.firstHit(script: Script, id: number): number
	local k = strikeOf(script, id)
	return if k > 0 then script.first[k] else 0
end

-- Every ball the struck ball `id` touched at the instant of its first contact. Usually one; two when it met
-- two balls lying together, which no referee could separate: the rules take whichever suits the shooter.
function Shot.firstHits(script: Script, id: number): { number }
	local k = strikeOf(script, id)
	return if k > 0 then table.clone(script.firstAll[k]) else {}
end

-- The first thing the struck ball `id` met: (Physics.EV.ball, ball id), (EV.cushion or EV.jaw, segment
-- index), (EV.post, post index), or (0, 0) if it met nothing.
function Shot.firstTouch(script: Script, id: number): (number, number)
	local k = strikeOf(script, id)
	if k == 0 then
		return 0, 0
	end
	return script.touch[k * 2 - 1], script.touch[k * 2]
end

export type Cue = { t: number, name: string, volume: number }

local function loud(speed: number, full: number): number
	return math.clamp(speed / full, 0.05, 1)
end

-- Sound cue points, in time order: "strike" (the tip), "click" (ball on ball; a burst of clicks is merged
-- into its loudest, and the burst that opens a full rack is "crack"), "cushion", "jaw" (a rattle in a
-- pocket), "post" (bumper pool's rubber), "drop" (into a pocket or a cup), "rim" (a lip-out). Volume 0..1
-- comes from the speed of the contact.
function Shot.cues(script: Script): { Cue }
	local out: { Cue } = {}
	local s = script.strikes
	for k = 1, #s, 6 do
		local speed = math.sqrt(s[k + 1] * s[k + 1] + s[k + 2] * s[k + 2])
		table.insert(out, { t = 0, name = "strike", volume = loud(speed, 30) })
	end
	local ev = script.events
	local lastClick: Cue? = nil
	local clicks = 0
	for e = 1, #ev, ES do
		local t, kind, speed = ev[e], ev[e + 1], ev[e + 4]
		if kind == EV.ball then
			local vol = loud(speed, 20)
			if lastClick and t - lastClick.t < Shot.CLICK_MERGE then
				clicks += 1
				lastClick.volume = math.max(lastClick.volume, vol)
				if clicks >= 4 and lastClick.volume > 0.5 then
					lastClick.name = "crack"
				end
			else
				local c = { t = t, name = "click", volume = vol }
				table.insert(out, c)
				lastClick, clicks = c, 1
			end
		elseif kind == EV.cushion then
			table.insert(out, { t = t, name = "cushion", volume = loud(speed, 18) })
		elseif kind == EV.jaw then
			table.insert(out, { t = t, name = "jaw", volume = loud(speed, 14) })
		elseif kind == EV.post then
			table.insert(out, { t = t, name = "post", volume = loud(speed, 14) })
		elseif kind == EV.drop then
			table.insert(out, { t = t, name = "drop", volume = loud(speed + 4, 14) })
		elseif kind == EV.rim then
			table.insert(out, { t = t, name = "rim", volume = loud(speed, 10) })
		end
	end
	table.sort(out, function(a, b)
		return a.t < b.t
	end)
	return out
end

local walker = Cloth.new(0, 0, 0)

-- The first moment any moving ball comes within r of the point (x, z): where an animal on the felt is
-- knocked off (the model itself never sees it). Every ball is walked along its own path from key point to
-- key point in steps no longer than a part of the distance that counts (a full-power ball covers a stud in a
-- sixtieth of a second, four times an animal's size), and each step is tested as a line, so the moment is
-- found on the pass that made it, to within a thousandth of a second, whatever the speed.
function Shot.firstNear(script: Script, x: number, z: number, r: number): (number?, number?)
	local lim = r + Tables.byId(script.table).ballR
	local lim2 = lim * lim
	local bestT: number? = nil
	local bestId: number? = nil
	local b = walker
	for i = 1, #script.ids do
		local k = script.tracks[i]
		for o = 0, #k - KS, KS do
			local t = k[o + 1]
			if bestT ~= nil and t >= bestT then
				break
			end
			if k[o + 10] == 1 then
				local tStop = if o + KS < #k then k[o + KS + 1] else script.tEnd
				b.x, b.z, b.vx, b.vz = k[o + 2], k[o + 3], k[o + 4], k[o + 5]
				b.qx, b.qz, b.s, b.y, b.mode = k[o + 6], k[o + 7], k[o + 8], 0, 1
				while t < tStop and b.mode == 1 and (bestT == nil or t < bestT) do
					local px, pz = b.x, b.z
					-- a sliding ball can gain a little speed from its spin, never a tenth
					local speed = 1.1 * math.sqrt(b.vx * b.vx + b.vz * b.vz)
					local dt = 1 / 60
					if speed * dt > 0.4 * lim then
						dt = 0.4 * lim / speed
					end
					if t + dt > tStop then
						dt = tStop - t
					end
					Cloth.advance(b, dt)
					-- the first place on the line from (px, pz) to where it is now that is within lim of the point
					local dx, dz = b.x - px, b.z - pz
					local ex, ez = px - x, pz - z
					local c = ex * ex + ez * ez - lim2
					local f: number? = nil
					if c <= 0 then
						f = 0
					else
						local aa = dx * dx + dz * dz
						local bd = -(ex * dx + ez * dz)
						if aa > 0 and bd > 0 then
							local disc = bd * bd - aa * c
							if disc >= 0 then
								local root = (bd - math.sqrt(disc)) / aa
								if root <= 1 then
									f = root
								end
							end
						end
					end
					if f ~= nil then
						local when = t + f * dt
						if bestT == nil or when < bestT then
							bestT, bestId = when, script.ids[i]
						end
						break
					end
					t += dt
				end
			end
		end
	end
	return bestT, bestId
end

-- THE WIRE. A script as a buffer, little-endian:
--   u8 version, u8 table (1 eight-ball, 2 bumper pool), u8 balls, u8 strikes, u8 flags (1 capped, 2 a cushion
--   after the first contact), f64 tEnd, f64 firstT, u32 contacts, u32 steps, u32 knots
--   for each ball: u8 id, f32 x, f32 z (where it started), u16 cushions touched
--   for each strike: u8 id, f32 vx, vz, qx, qz, s, u8 first ball, u8 first touch kind, u8 what, u8 n, n x u8
--     (the balls met at the first instant)
--   u16 events, each: f64 t, u8 kind, u8 a, u8 b, f32 speed
--   u8 pots, each: u8 ball, u8 hole, f64 t, u16 cushions, u8 by
--   u8 balls at rest, each: u8 id, f64 x, f64 z
--   for each ball: u16 key points, each: f64 t, u8 bits, f32 x, f32 z, then only what the bits say is there:
--     bits 1 2 4: the mode; 8: f32 vx, vz follow (else it is not moving); 16: its roll is its velocity (a
--     rolling ball, exactly); 32: f32 qx, qz follow (else, without 16, no roll); 64: f32 s follows; 128: f32 y
-- Times, modes and rest places are exact; a place or a speed is out by less than a millionth of a stud.
local TABLE_CODES = { eightball = 1, bumper = 2 } :: { [string]: number }
local TABLE_IDS = { "eightball", "bumper" }

function Shot.pack(script: Script): buffer
	local n = #script.ids
	local nStrikes = #script.strikes // 6
	local size = 5 + 16 + 12 + n * 11
	for k = 1, nStrikes do
		size += 25 + #script.firstAll[k]
	end
	size += 2 + (#script.events // ES) * 15
	size += 1 + (#script.pots // PS) * 13
	size += 1 + (#script.rest // 3) * 17
	for i = 1, n do
		size += 2 + (#script.tracks[i] // KS) * 41
	end
	local b = buffer.create(size)
	local at = 0
	local function u8(v: number)
		buffer.writeu8(b, at, v)
		at += 1
	end
	local function u16(v: number)
		buffer.writeu16(b, at, v)
		at += 2
	end
	local function u32(v: number)
		buffer.writeu32(b, at, v)
		at += 4
	end
	local function f32(v: number)
		buffer.writef32(b, at, v)
		at += 4
	end
	local function f64(v: number)
		buffer.writef64(b, at, v)
		at += 8
	end
	u8(script.v)
	u8(TABLE_CODES[script.table] or 0)
	u8(n)
	u8(nStrikes)
	u8((if script.capped then 1 else 0) + (if script.railAfter then 2 else 0))
	f64(script.tEnd)
	f64(script.firstT)
	u32(script.contacts)
	u32(script.steps)
	u32(script.knots)
	for i = 1, n do
		u8(script.ids[i])
		f32(script.start[i * 2 - 1])
		f32(script.start[i * 2])
		u16(math.min(script.rails[i], 65535))
	end
	local st = script.strikes
	for k = 1, nStrikes do
		local o = (k - 1) * 6
		u8(st[o + 1])
		for j = 2, 6 do
			f32(st[o + j])
		end
		u8(script.first[k])
		u8(script.touch[k * 2 - 1])
		u8(script.touch[k * 2])
		local all = script.firstAll[k]
		u8(#all)
		for _, id in all do
			u8(id)
		end
	end
	local ev = script.events
	u16(#ev // ES)
	for e = 1, #ev, ES do
		f64(ev[e])
		u8(ev[e + 1])
		u8(ev[e + 2])
		u8(ev[e + 3])
		f32(ev[e + 4])
	end
	local p = script.pots
	u8(#p // PS)
	for i = 1, #p, PS do
		u8(p[i])
		u8(p[i + 1])
		f64(p[i + 2])
		u16(math.min(p[i + 3], 65535))
		u8(p[i + 4])
	end
	local r = script.rest
	u8(#r // 3)
	for i = 1, #r, 3 do
		u8(r[i])
		f64(r[i + 1])
		f64(r[i + 2])
	end
	for i = 1, n do
		local k = script.tracks[i]
		u16(#k // KS)
		for o = 0, #k - KS, KS do
			local vx, vz, qx, qz, s, y = k[o + 4], k[o + 5], k[o + 6], k[o + 7], k[o + 8], k[o + 9]
			local moving = vx ~= 0 or vz ~= 0
			local rolling = moving and qx == vx and qz == vz
			local spun = not rolling and (qx ~= 0 or qz ~= 0)
			local bits = k[o + 10]
				+ (if moving then 8 else 0)
				+ (if rolling then 16 else 0)
				+ (if spun then 32 else 0)
				+ (if s ~= 0 then 64 else 0)
				+ (if y ~= 0 then 128 else 0)
			f64(k[o + 1])
			u8(bits)
			f32(k[o + 2])
			f32(k[o + 3])
			if moving then
				f32(vx)
				f32(vz)
			end
			if spun then
				f32(qx)
				f32(qz)
			end
			if s ~= 0 then
				f32(s)
			end
			if y ~= 0 then
				f32(y)
			end
		end
	end
	local out = buffer.create(at)
	buffer.copy(out, 0, b, 0, at)
	return out
end

local function decode(b: buffer): Script
	local at = 0
	local function u8(): number
		at += 1
		return buffer.readu8(b, at - 1)
	end
	local function u16(): number
		at += 2
		return buffer.readu16(b, at - 2)
	end
	local function u32(): number
		at += 4
		return buffer.readu32(b, at - 4)
	end
	local function f32(): number
		at += 4
		return buffer.readf32(b, at - 4)
	end
	local function f64(): number
		at += 8
		return buffer.readf64(b, at - 8)
	end
	local v = u8()
	local tableId = TABLE_IDS[u8()] or ""
	local n = u8()
	local nStrikes = u8()
	local flags = u8()
	local tEnd, firstT = f64(), f64()
	local contacts, steps, knots = u32(), u32(), u32()
	local ids: { number }, start: { number }, rails: { number } = {}, {}, {}
	for i = 1, n do
		ids[i] = u8()
		start[i * 2 - 1] = f32()
		start[i * 2] = f32()
		rails[i] = u16()
	end
	local strikes: { number }, first: { number }, touch: { number } = {}, {}, {}
	local firstAll: { { number } } = {}
	for k = 1, nStrikes do
		table.insert(strikes, u8())
		for _ = 2, 6 do
			table.insert(strikes, f32())
		end
		first[k] = u8()
		touch[k * 2 - 1] = u8()
		touch[k * 2] = u8()
		local all: { number } = {}
		for j = 1, u8() do
			all[j] = u8()
		end
		firstAll[k] = all
	end
	local events: { number } = {}
	for _ = 1, u16() do
		table.insert(events, f64())
		table.insert(events, u8())
		table.insert(events, u8())
		table.insert(events, u8())
		table.insert(events, f32())
	end
	local pots: { number } = {}
	for _ = 1, u8() do
		table.insert(pots, u8())
		table.insert(pots, u8())
		table.insert(pots, f64())
		table.insert(pots, u16())
		table.insert(pots, u8())
	end
	local rest: { number } = {}
	for _ = 1, u8() do
		table.insert(rest, u8())
		table.insert(rest, f64())
		table.insert(rest, f64())
	end
	local tracks: { { number } } = {}
	for i = 1, n do
		local k: { number } = {}
		for _ = 1, u16() do
			local t = f64()
			local bits = u8()
			local x, z = f32(), f32()
			local vx, vz, qx, qz, s, y = 0, 0, 0, 0, 0, 0
			if bit32.band(bits, 8) ~= 0 then
				vx, vz = f32(), f32()
			end
			if bit32.band(bits, 16) ~= 0 then
				qx, qz = vx, vz
			elseif bit32.band(bits, 32) ~= 0 then
				qx, qz = f32(), f32()
			end
			if bit32.band(bits, 64) ~= 0 then
				s = f32()
			end
			if bit32.band(bits, 128) ~= 0 then
				y = f32()
			end
			table.move({ t, x, z, vx, vz, qx, qz, s, y, bit32.band(bits, 7) }, 1, KS, #k + 1, k)
		end
		tracks[i] = k
	end
	if at ~= buffer.len(b) then
		error("length")
	end
	return {
		v = v,
		table = tableId,
		ids = ids,
		start = start,
		strikes = strikes,
		tracks = tracks,
		events = events,
		pots = pots,
		first = first,
		firstAll = firstAll,
		touch = touch,
		firstT = firstT,
		railAfter = bit32.band(flags, 2) ~= 0,
		rails = rails,
		rest = rest,
		tEnd = tEnd,
		capped = bit32.band(flags, 1) ~= 0,
		contacts = contacts,
		steps = steps,
		knots = knots,
	}
end

-- A script off the wire: read (a buffer that is cut short or padded is refused) and then checked like any other.
function Shot.unpack(b: any): (Script?, string?)
	if type(b) ~= "buffer" then
		return nil, "not a buffer"
	end
	local ok, script = pcall(decode, b)
	if not ok then
		return nil, "malformed"
	end
	return Shot.check(script)
end

local function isNumbers(v: any, stride: number): boolean
	if type(v) ~= "table" or #v % stride ~= 0 then
		return false
	end
	for _, x in v do
		if type(x) ~= "number" or x ~= x then
			return false
		end
	end
	return true
end

-- A table off the wire is checked before anything plays it. There is no limit on how long a shot may be.
function Shot.check(v: any): (Script?, string?)
	if type(v) ~= "table" then
		return nil, "not a table"
	end
	if v.v ~= Shot.VERSION then
		return nil, "version"
	end
	if v.table ~= "eightball" and v.table ~= "bumper" then
		return nil, "table"
	end
	if not isNumbers(v.ids, 1) or #v.ids < 1 or #v.ids > 16 then
		return nil, "ids"
	end
	local n = #v.ids
	if not isNumbers(v.start, 2) or #v.start ~= n * 2 then
		return nil, "start"
	end
	if type(v.tracks) ~= "table" or #v.tracks ~= n then
		return nil, "tracks"
	end
	for i = 1, n do
		local k = v.tracks[i]
		if not isNumbers(k, KS) then
			return nil, "track"
		end
		for o = KS + 1, #k, KS do
			if k[o] < k[o - KS] then
				return nil, "track order"
			end
		end
	end
	if not isNumbers(v.strikes, 6) or not isNumbers(v.events, ES) or not isNumbers(v.pots, PS) then
		return nil, "lists"
	end
	if not isNumbers(v.rest, 3) or not isNumbers(v.rails, 1) or not isNumbers(v.first, 1) then
		return nil, "lists"
	end
	local nStrikes = #v.strikes / 6
	if #v.rails ~= n or #v.first ~= nStrikes or not isNumbers(v.touch, 2) or #v.touch ~= nStrikes * 2 then
		return nil, "lists"
	end
	if type(v.firstAll) ~= "table" or #v.firstAll ~= nStrikes then
		return nil, "first"
	end
	for k = 1, nStrikes do
		if not isNumbers(v.firstAll[k], 1) then
			return nil, "first"
		end
	end
	if type(v.tEnd) ~= "number" or v.tEnd ~= v.tEnd or v.tEnd < 0 or type(v.firstT) ~= "number" then
		return nil, "times"
	end
	return v :: Script, nil
end

function Shot.size(script: Script): number
	local n = #script.ids + #script.start + #script.strikes + #script.events + #script.pots
	n += #script.first + #script.touch + #script.rails + #script.rest + 2
	for _, all in script.firstAll do
		n += #all
	end
	for _, k in script.tracks do
		n += #k
	end
	return n
end

return Shot
