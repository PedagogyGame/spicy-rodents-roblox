--!strict
-- ReplicatedStorage.Shared.Minigames.Bowling.RollScript
-- One whole throw as plain data: the SERVER builds it the moment the ball is let go (BallPath for the run down
-- the lane, PinModel for the pins), scores from it, and sends the same table to every client, which only plays
-- it back. Nobody simulates anything twice, so what every screen shows is exactly what was scored, and the
-- client can draw it at its own frame rate (anchored parts moved by the server alone would stutter).
-- Times are seconds from the release. The ball runs its path to the deck (or down the gutter), crosses the deck
-- on the pin model's key points, then drops into the pit. A pin stands on its spot until it is hit, then tips
-- over the way it was pushed while it slides, drops into the gutter beside the deck if it is knocked that far,
-- and falls out of sight if it goes over the back edge. Sound cue points come with it (placeholders: the client
-- has no audio yet).
-- Lane frame: x across from the lane centre (bowler's right +), d down-lane from the foul line, y up from the
-- floor (the ball's y is its centre; a pin's y is how far its pivot has dropped from standing).
-- Pure; Lune-tested (tests/unit/bowling_rollscript.spec.luau).
-- Interface: build(params, mask, seed) -> Script; fake(mask, n) -> Script (n pins tip over where they stand:
--   the engine smoke's scripted pinfall); ball(script, t) -> (x, y, d, turn, where "hand" | "lane" | "pit")?;
--   pin(script, n, t) -> (x, y, d, tilt, yaw, hidden); cues(script) -> { { t, name, volume } };
--   check(any) -> (Script?, why?) (a table off the wire is validated before anything plays it); size(script)
--   -> how many numbers it carries; FALL_TIME, PIT_HIDE

local AlleyLayout = require("../../Attractions/AlleyLayout")
local Rng = require("../../Util/Rng")
local BallPath = require("./BallPath")
local PinModel = require("./PinModel")

local RollScript = {}

RollScript.VERSION = 1
RollScript.FALL_TIME = 0.35 -- seconds for a hit pin to go from standing to lying
RollScript.LIE_DROP = 0.22 -- a lying pin's pivot is this much lower than a standing one's
RollScript.PIT_HIDE = 0.3 -- seconds after going over the edge before a pin is out of sight
RollScript.GRAVITY = 80 -- studs/s^2 for things dropping into the pit (looks right at this scale)
RollScript.REST = 0.4 -- seconds after the last movement before the throw is over

export type Flags = {
	gutter: boolean,
	first: boolean, -- thrown at a full rack
	pocket: string?, -- "1-3" | "1-2"
	headOn: boolean,
	split: boolean,
	splitName: string?,
}

export type Script = {
	v: number,
	params: BallPath.Params,
	mask: { boolean },
	standing: { boolean },
	down: number,
	path: BallPath.Path?,
	deck: PinModel.Result?,
	tEntry: number, -- when the ball reaches the deck (-1: it never does)
	tImpact: number, -- first pin contact, or when the ball passes the head pin's row
	tBallEnd: number, -- when the ball goes over the back edge
	tEnd: number,
	flags: Flags,
}

local function copyMask(mask: { boolean }): { boolean }
	local out = table.create(10, false)
	for n = 1, 10 do
		out[n] = mask[n] == true
	end
	return out
end

local function flagsOf(mask: { boolean }, standing: { boolean }, gutter: boolean, deck: PinModel.Result?): Flags
	local first = PinModel.count(mask) == 10
	local pocket: string? = nil
	local headOn = false
	if deck and deck.firstPin == 1 and deck.hitX then
		local hx = deck.hitX
		if math.abs(hx) < 0.12 then
			headOn = true
		elseif hx >= 0.12 and hx <= 0.42 then
			pocket = "1-3"
		elseif hx <= -0.12 and hx >= -0.42 then
			pocket = "1-2"
		end
	end
	local split, splitName = false, nil :: string?
	if first then
		split, splitName = PinModel.isSplit(standing)
	end
	return { gutter = gutter, first = first, pocket = pocket, headOn = headOn, split = split, splitName = splitName }
end

-- The throw, start to finish. The release error (BallPath.noise) and the pins' variation both come from seed.
function RollScript.build(params: any, mask: { boolean }, seed: number): Script
	local rng = Rng.new(seed)
	local p = BallPath.noise(rng, BallPath.clamp(params))
	local m = copyMask(mask)
	local path = BallPath.trace(p)
	local entry = path.entry
	if entry == nil then
		-- gutter: no pin is touched
		local tImpact = path.tEnd
		local s = path.samples
		for i = 1, #s, 3 do
			if s[i + 2] >= AlleyLayout.HEAD_D then
				tImpact = s[i]
				break
			end
		end
		return {
			v = RollScript.VERSION,
			params = p,
			mask = m,
			standing = copyMask(m),
			down = 0,
			path = path,
			deck = nil,
			tEntry = -1,
			tImpact = tImpact,
			tBallEnd = path.tEnd,
			tEnd = path.tEnd + RollScript.REST,
			flags = flagsOf(m, m, true, nil),
		}
	end
	local deck = PinModel.roll({ x = entry.x, vx = entry.vx, vd = entry.vd }, m, (seed * 31 + 7) % 4294967296)
	local tImpact = entry.t + (deck.firstHit or ((AlleyLayout.HEAD_D - AlleyLayout.DECK_START) / entry.vd))
	local tBallEnd = entry.t + deck.ballEnd
	return {
		v = RollScript.VERSION,
		params = p,
		mask = m,
		standing = copyMask(deck.standing),
		down = deck.down,
		path = path,
		deck = deck,
		tEntry = entry.t,
		tImpact = tImpact,
		tBallEnd = tBallEnd,
		tEnd = math.max(entry.t + deck.tEnd, tBallEnd) + RollScript.REST,
		flags = flagsOf(m, deck.standing, false, deck),
	}
end

-- A scripted pinfall with no ball: the first n standing pins tip over where they stand (engine smoke, tests).
function RollScript.fake(mask: { boolean }, n: number): Script
	local m = copyMask(mask)
	local standing = copyMask(m)
	local pins: { { number } } = {}
	local hitT, pitT = table.create(10, -1), table.create(10, -1)
	local down = 0
	for i = 1, 10 do
		pins[i] = {}
		if m[i] and down < n then
			down += 1
			standing[i] = false
			hitT[i] = 0
			local x, d = PinModel.spot(i)
			pins[i] = { 0, x, d, 0, 0 }
		end
	end
	local deck: PinModel.Result = {
		standing = copyMask(standing),
		down = down,
		ball = {},
		pins = pins,
		hitT = hitT,
		pitT = pitT,
		firstHit = nil,
		firstPin = nil,
		hitX = nil,
		ballEnd = 0,
		tEnd = RollScript.FALL_TIME,
	}
	return {
		v = RollScript.VERSION,
		params = BallPath.clamp(nil),
		mask = m,
		standing = standing,
		down = down,
		path = nil,
		deck = deck,
		tEntry = 0,
		tImpact = 0,
		tBallEnd = 0,
		tEnd = RollScript.FALL_TIME + 0.05,
		flags = flagsOf(m, standing, false, nil),
	}
end

local function smooth(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

-- The ball at time t: x, y (centre), d, how far it has turned, and where it is. nil for a script with no ball.
function RollScript.ball(script: Script, t: number): (number?, number, number, number, string)
	local path = script.path
	if path == nil then
		return nil, 0, 0, 0, "hand"
	end
	if t <= 0 then
		local x, y, d, turn = BallPath.at(path, 0)
		return x, y, d, turn, "hand"
	end
	local deck = script.deck
	local x, y, d, turn
	local vx, vd = 0, 0
	if deck == nil or t <= script.tEntry then
		if t <= path.tEnd then
			x, y, d, turn = BallPath.at(path, t)
			return x, y, d, turn, "lane"
		end
		-- the end of a gutter ball: off the end of the channel
		x, y, d, turn = BallPath.at(path, path.tEnd)
		local s = path.samples
		local n = #s
		local span = math.max(1e-3, s[n - 2] - s[n - 5])
		vx, vd = 0, (s[n] - s[n - 3]) / span
	else
		local keys = deck.ball
		local tau = math.min(t, script.tBallEnd) - script.tEntry
		x, d = PinModel.segAt(keys, tau, 0)
		y = BallPath.BALL_Y
		turn = (d - BallPath.RELEASE_D) / (AlleyLayout.BALL_D / 2)
		if t <= script.tBallEnd then
			return x, y, d, turn, "lane"
		end
		vx, vd = keys[#keys - 1], keys[#keys]
	end
	-- over the back edge into the pit: it drops, carries on a moment and lies still (after the script's end
	-- nothing about the throw changes any more, so the last pose drawn anywhere is the same pose)
	local tau = math.min(t - script.tBallEnd, RollScript.REST)
	local R = AlleyLayout.BALL_D / 2
	local wall = PinModel.WALL_X - R
	local px = math.clamp(x + vx * tau, -wall, wall)
	local pd = math.min(d + math.max(vd, 4) * tau, AlleyLayout.CUSHION_D - 0.8)
	local py = math.max(AlleyLayout.PIT_Y + R, y - 0.5 * RollScript.GRAVITY * tau * tau)
	return px, py, pd, turn + tau * 6, "pit"
end

-- Pin n at time t: x, y (how far its pivot has dropped), d, tilt (radians, 0 standing .. pi/2 lying), yaw (the
-- way it fell: radians from down-lane toward the bowler's right) and whether it is out of sight.
function RollScript.pin(script: Script, n: number, t: number): (number, number, number, number, number, boolean)
	local sx, sd = PinModel.spot(n)
	if not script.mask[n] then
		return sx, 0, sd, 0, 0, true
	end
	local deck = script.deck
	if deck == nil then
		return sx, 0, sd, 0, 0, false
	end
	local hit = deck.hitT[n]
	local tau = t - script.tEntry
	if hit < 0 or tau < hit then
		return sx, 0, sd, 0, 0, false
	end
	local keys = deck.pins[n]
	local pit = deck.pitT[n]
	-- a pin that went over the back edge stops where it is once it is out of sight
	local slideT = if pit >= 0 then math.min(tau, pit + RollScript.PIT_HIDE) else tau
	local x, d = PinModel.segAt(keys, slideT, PinModel.FRICTION)
	local fall = smooth((tau - hit) / RollScript.FALL_TIME)
	local tilt = fall * math.pi / 2
	local vx, vd = keys[4], keys[5]
	local yaw = if vx == 0 and vd == 0 then 0 else math.atan2(vx, vd)
	local y = -RollScript.LIE_DROP * fall
	-- knocked off the side of the deck: down into the gutter
	local over = math.abs(x) - AlleyLayout.LANE_W / 2
	if over > 0 then
		y -= AlleyLayout.GUTTER_DEPTH * smooth(over / 0.3)
	end
	local hidden = false
	if pit >= 0 and tau > pit then
		local f = tau - pit
		y = math.max(AlleyLayout.PIT_Y, y - 0.5 * RollScript.GRAVITY * f * f)
		hidden = f > RollScript.PIT_HIDE
	end
	return x, y, d, tilt, yaw, hidden
end

-- Placeholder sound cue points for a throw, in time order: { t, name, volume 0..1 }.
function RollScript.cues(script: Script): { { any } }
	local out: { { any } } = {}
	local function cue(t: number, name: string, volume: number)
		local c: { any } = { t, name, volume }
		table.insert(out, c)
	end
	local path = script.path
	if path == nil then
		return out
	end
	local power = script.params.power
	cue(0, "release", 0.6)
	cue(0.05, "roll", 0.4 + 0.5 * power)
	if path.gutterT then
		cue(path.gutterT, "gutter", 0.8)
	end
	local deck = script.deck
	if deck then
		local hits: { number } = {}
		for n = 1, 10 do
			if deck.hitT[n] >= 0 then
				table.insert(hits, deck.hitT[n])
			end
		end
		table.sort(hits)
		local last = -1
		for _, h in hits do
			-- pins that go within a few hundredths of each other are one clatter
			if h - last >= 0.04 then
				cue(script.tEntry + h, "pin", math.clamp(0.5 + 0.05 * #hits, 0, 1))
				last = h
			end
		end
	end
	cue(script.tBallEnd, "pit", 0.5)
	table.sort(out, function(a, b)
		return a[1] < b[1]
	end)
	return out
end

-- How many numbers the script carries (what it costs on the wire).
function RollScript.size(script: Script): number
	local n = 12
	if script.path then
		n += #script.path.samples + 6
	end
	local deck = script.deck
	if deck then
		n += #deck.ball + 24
		for i = 1, 10 do
			n += #deck.pins[i]
		end
	end
	return n
end

-- Validation ---------------------------------------------------------------------------------------------------
local function num(v: any, lo: number, hi: number): boolean
	return type(v) == "number" and v == v and v >= lo and v <= hi
end

local function bools10(v: any): boolean
	if type(v) ~= "table" or #v ~= 10 then
		return false
	end
	for i = 1, 10 do
		if type(v[i]) ~= "boolean" then
			return false
		end
	end
	return true
end

local function nums10(v: any, lo: number, hi: number): boolean
	if type(v) ~= "table" or #v ~= 10 then
		return false
	end
	for i = 1, 10 do
		if not num(v[i], lo, hi) then
			return false
		end
	end
	return true
end

-- key points: flat { t, x, d, vx, vd }, time never going back
local function keysOk(v: any, maxPoints: number, tMax: number): boolean
	if type(v) ~= "table" or #v % 5 ~= 0 or #v > 5 * maxPoints then
		return false
	end
	local last = 0
	for i = 1, #v, 5 do
		if
			not num(v[i], last, tMax)
			or not num(v[i + 1], -4, 4)
			or not num(v[i + 2], 40, 75)
			or not num(v[i + 3], -120, 120)
			or not num(v[i + 4], -120, 120)
		then
			return false
		end
		last = v[i]
	end
	return true
end

-- check: a table that came off the wire is a playable script, or it is refused with the reason. Nothing that
-- fails here is ever played (a malformed table must not throw inside a render step).
function RollScript.check(w: any): (Script?, string?)
	if type(w) ~= "table" then
		return nil, "not a table"
	end
	if w.v ~= RollScript.VERSION then
		return nil, "version"
	end
	if not bools10(w.mask) or not bools10(w.standing) then
		return nil, "masks"
	end
	local down = 0
	for n = 1, 10 do
		if w.standing[n] and not w.mask[n] then
			return nil, "a pin stood up"
		end
		if w.mask[n] and not w.standing[n] then
			down += 1
		end
	end
	if w.down ~= down then
		return nil, "count"
	end
	local p = w.params
	if
		type(p) ~= "table"
		or not num(p.offset, -1, 1)
		or not num(p.angle, -0.2, 0.2)
		or not num(p.power, 0, 1)
		or not num(p.spin, -1, 1)
	then
		return nil, "params"
	end
	if
		not num(w.tEntry, -1, 20)
		or not num(w.tImpact, 0, 20)
		or not num(w.tBallEnd, 0, 20)
		or not num(w.tEnd, 0, 25)
	then
		return nil, "times"
	end
	if type(w.flags) ~= "table" or type(w.flags.gutter) ~= "boolean" then
		return nil, "flags"
	end
	local path = w.path
	if path ~= nil then
		local s = if type(path) == "table" then path.samples else nil
		if type(s) ~= "table" or #s % 3 ~= 0 or #s < 6 or #s > 3 * 130 then
			return nil, "path"
		end
		local last = 0
		for i = 1, #s, 3 do
			if not num(s[i], last, 20) or not num(s[i + 1], -3.2, 3.2) or not num(s[i + 2], -2, 75) then
				return nil, "path sample"
			end
			last = s[i]
		end
		if not num(path.tEnd, 0, 20) or (path.gutterT ~= nil and not num(path.gutterT, 0, 20)) then
			return nil, "path times"
		end
	end
	local deck = w.deck
	if deck ~= nil then
		if type(deck) ~= "table" or type(deck.pins) ~= "table" or #deck.pins ~= 10 then
			return nil, "deck"
		end
		-- as many key points as the model can ever write (PinModel.MAX_KEYS): a smaller limit here once refused
		-- slow balls that had pushed a pin along, although the server had scored them
		if not keysOk(deck.ball, PinModel.MAX_KEYS, 10) or (path ~= nil and #deck.ball < 10) then
			return nil, "deck ball"
		end
		if not nums10(deck.hitT, -1, 10) or not nums10(deck.pitT, -1, 10) then
			return nil, "deck times"
		end
		for n = 1, 10 do
			if not keysOk(deck.pins[n], PinModel.MAX_KEYS, 10) then
				return nil, "deck pin"
			end
			-- a pin that was hit must have somewhere to go; one that stands must not
			if (deck.hitT[n] >= 0) ~= (#deck.pins[n] > 0) then
				return nil, "deck pin motion"
			end
			if deck.hitT[n] >= 0 and not w.mask[n] then
				return nil, "a pin that was not there moved"
			end
		end
		if not num(deck.ballEnd, 0, 10) or not num(deck.tEnd, 0, 10) then
			return nil, "deck end"
		end
	elseif path == nil then
		return nil, "nothing to play"
	end
	if path ~= nil and deck ~= nil and w.tEntry < 0 then
		return nil, "entry"
	end
	return w :: Script, nil
end

return RollScript
