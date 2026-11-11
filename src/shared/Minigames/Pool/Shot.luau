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
-- Times are seconds from the strike. Pure; Lune-tested (tests/unit/pool_shot.spec.luau).
-- Interface: run(table, spots, strikes, maxT?) -> Script; pose(script, i, t) -> (x, z, y, mode, vx, vz, qx,
--   qz, s) for the i-th ball (script.ids[i] is its id); indexOf(script, id) -> i?; rest(script) -> { Spot }
--   (the balls left on the table, where they stopped); pots(script) -> { { ball, hole, t, cushions } } in the
--   order they dropped; firstHit(script, id) -> ball id (0: it touched no ball); cues(script) -> { { t, name,
--   volume } }; firstNear(script, x, z, r) -> (t?, ball id?) (the first ball to come within r of a point: the
--   animal rule); check(any) -> (Script?, why?); size(script) -> how many numbers it carries; VERSION, MAX_T,
--   REST_PAD, SINK

local Cloth = require("./Cloth")
local Physics = require("./Physics")
local Tables = require("./Tables")

local Shot = {}

Shot.VERSION = 1
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
	pots: { number }, -- flat ball, hole, t, cushions (cushions it touched before it dropped), in drop order
	first: { number }, -- for each strike, the first ball the struck ball touched (0: none)
	firstT: number, -- when a struck ball first touched another ball (-1: never)
	railAfter: boolean, -- after that first touch some ball reached a cushion (a pot also satisfies the rules)
	rails: { number }, -- per ball: cushions touched this shot
	rest: { number }, -- flat id, x, z for every ball still on the table, where it stopped
	tEnd: number,
	capped: boolean, -- the shot ran into MAX_T and was stopped where it was (never seen in the specs)
	contacts: number,
	steps: number,
}

local KS = Physics.KEY_STRIDE
local ES = Physics.EVENT_STRIDE
local EV = Physics.EV

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
	local firstT = -1
	local rails: { number } = table.create(#spots, 0)
	local pots: { number } = {}
	local railAfter = false
	local ev = w.events
	for e = 1, #ev, ES do
		local t, kind, a, b = ev[e], ev[e + 1], ev[e + 2], ev[e + 3]
		if kind == EV.ball then
			local ka, kb = struck[a], struck[b]
			if ka and first[ka] == 0 then
				first[ka] = b
				firstT = if firstT < 0 then t else firstT
			end
			if kb and first[kb] == 0 then
				first[kb] = a
				firstT = if firstT < 0 then t else firstT
			end
		elseif kind == EV.cushion or kind == EV.jaw then
			if kind == EV.cushion then
				rails[idx[a]] += 1
			end
			if firstT >= 0 then
				railAfter = true
			end
		elseif kind == EV.drop then
			table.move({ a, b, t, rails[idx[a]] }, 1, 4, #pots + 1, pots)
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
		firstT = firstT,
		railAfter = railAfter,
		rails = rails,
		rest = rest,
		tEnd = tStop + Shot.REST_PAD,
		capped = capped,
		contacts = w.contacts,
		steps = w.steps,
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

export type Pot = { ball: number, hole: number, t: number, cushions: number }

function Shot.pots(script: Script): { Pot }
	local out: { Pot } = {}
	local p = script.pots
	for i = 1, #p, 4 do
		table.insert(out, { ball = p[i], hole = p[i + 1], t = p[i + 2], cushions = p[i + 3] })
	end
	return out
end

-- The first ball the struck ball `id` touched (0: none, or `id` was not struck).
function Shot.firstHit(script: Script, id: number): number
	local s = script.strikes
	for k = 1, #s / 6 do
		if s[(k - 1) * 6 + 1] == id then
			return script.first[k]
		end
	end
	return 0
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

-- The first moment any moving ball comes within r of the point (x, z): where an animal on the felt is
-- knocked off (the model itself never sees it). Sampled at 60 per second.
function Shot.firstNear(script: Script, x: number, z: number, r: number): (number?, number?)
	local lim = r + Tables.byId(script.table).ballR
	local t = 0
	while t <= script.tEnd do
		for i = 1, #script.ids do
			if #script.tracks[i] > 0 then
				local bx, bz, _, mode = Shot.pose(script, i, t)
				if mode == 1 and (bx - x) * (bx - x) + (bz - z) * (bz - z) <= lim * lim then
					return t, script.ids[i]
				end
			end
		end
		t += 1 / 60
	end
	return nil, nil
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
	if not isNumbers(v.strikes, 6) or not isNumbers(v.events, ES) or not isNumbers(v.pots, 4) then
		return nil, "lists"
	end
	if not isNumbers(v.rest, 3) or not isNumbers(v.rails, 1) or not isNumbers(v.first, 1) then
		return nil, "lists"
	end
	if type(v.tEnd) ~= "number" or v.tEnd ~= v.tEnd or v.tEnd < 0 or type(v.firstT) ~= "number" then
		return nil, "times"
	end
	return v :: Script, nil
end

function Shot.size(script: Script): number
	local n = #script.ids + #script.start + #script.strikes + #script.events + #script.pots
	n += #script.first + #script.rails + #script.rest + 2
	for _, k in script.tracks do
		n += #k
	end
	return n
end

return Shot
