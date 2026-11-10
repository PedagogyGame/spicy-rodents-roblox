--!strict
-- ReplicatedStorage.Shared.Minigames.Bowling.PinModel
-- What the pins do when the ball arrives: the SERVER decides it here, with no Roblox physics (nothing settles,
-- nothing differs between machines, and the cloud checks can see a thrown ball knock pins down). A top-down
-- model on the lane's real dimensions: the ball and the pins are discs; the ball is 4.6 times a pin's weight so
-- it ploughs on and is deflected a little by every pin it meets; a pin that is hit hard enough topples and
-- slides, and a toppled pin lying on its side reaches further than a standing one (its "tumbling reach"), which
-- is what carries a pocket hit through the whole rack; pins bounce off the kickback walls and fall into the pit.
-- A soft nudge leaves a pin standing. Seeded: the pins' exact spots and the bounciness vary a hair per throw,
-- so the same line gives a realistic spread (the pocket strikes most of the time, a dead-centre hit often
-- leaves a split, a thin hit never strikes).
-- The result also carries every piece's motion as key points (time, position, velocity, recorded only when a
-- velocity changes): between key points a pin slides to rest under constant friction and the ball moves
-- straight, so the lane hardware and every client can draw exactly the roll the server decided.
-- Lane frame: x across from the lane centre (bowler's right +), d down-lane from the foul line.
-- Pure; Lune-tested (tests/unit/bowling_pinmodel.spec.luau).
-- Interface: constants; fullRack() -> { boolean }; spot(n) -> (x, d); roll(entry { x, vx, vd }, mask, seed) ->
--   Result { standing, down, ball = flat { t, x, d, vx, vd, ... }, pins[n] = flat key points ({} if it never
--   moved), hitT[n] (-1 = never), pitT[n] (-1 = stayed on the deck), firstHit?, firstPin?, hitX?, ballEnd,
--   tEnd }; segAt(keys, t, friction) -> (x, d, moving); isSplit(mask) -> (boolean, name?); count(mask) -> n

local AlleyLayout = require("../../Attractions/AlleyLayout")
local Rng = require("../../Util/Rng")

local PinModel = {}

PinModel.DT = 1 / 480
PinModel.BALL_R = AlleyLayout.BALL_D / 2
PinModel.PIN_R = 0.23 -- a standing pin's belly
PinModel.REACH = 0.38 -- a toppled pin's reach (it lies on its side and tumbles)
PinModel.GROW = 1.2 -- studs/s: how fast a hit pin's reach opens out as it falls
PinModel.MASS_BALL = 4.6 -- in pins
PinModel.E_BALL = 0.6 -- restitution ball to pin
PinModel.E_PIN = 0.55 -- pin to pin
PinModel.E_JITTER = 0.05 -- per throw, either way
PinModel.E_WALL = 0.45 -- kickbacks
PinModel.FRICTION = 14 -- studs/s^2: a sliding pin
PinModel.TOPPLE = 1.4 -- studs/s of impulse a standing pin shrugs off
PinModel.SPOT_JITTER = 0.03 -- studs: no rack is set perfectly
PinModel.WALL_X = AlleyLayout.LANE_W / 2 + AlleyLayout.GUTTER_W -- kickback faces
PinModel.DECK_START = AlleyLayout.DECK_START
PinModel.DECK_END = AlleyLayout.DECK_END
PinModel.MAX_T = 4

export type Entry = { x: number, vx: number, vd: number }
export type Result = {
	standing: { boolean },
	down: number,
	ball: { number },
	pins: { { number } },
	hitT: { number },
	pitT: { number },
	firstHit: number?,
	firstPin: number?,
	hitX: number?,
	ballEnd: number,
	tEnd: number,
}

local SPOTS = AlleyLayout.pinSpots()

function PinModel.spot(n: number): (number, number)
	local s = SPOTS[n]
	return s[1], AlleyLayout.HEAD_D + s[2]
end

function PinModel.fullRack(): { boolean }
	return table.create(10, true)
end

function PinModel.count(mask: { boolean }): number
	local n = 0
	for i = 1, 10 do
		if mask[i] then
			n += 1
		end
	end
	return n
end

-- The seven columns of a rack as the bowler sees them, left to right: 7 | 4 | 2 8 | 1 5 | 3 9 | 6 | 10.
local COLUMN = { 4, 3, 5, 2, 4, 6, 1, 3, 5, 7 }

-- A split: the head pin is down and the pins left standing have an empty column between them (7-10, 4-6,
-- 3-10, 5-7 ...). A pin hiding straight behind another (2-8) is not one. Returns the leave's name too.
function PinModel.isSplit(mask: { boolean }): (boolean, string?)
	if mask[1] then
		return false, nil
	end
	local cols: { [number]: boolean } = {}
	local names: { string } = {}
	local lo, hi = 8, 0
	for n = 1, 10 do
		if mask[n] then
			cols[COLUMN[n]] = true
			lo = math.min(lo, COLUMN[n])
			hi = math.max(hi, COLUMN[n])
			table.insert(names, tostring(n))
		end
	end
	if #names < 2 then
		return false, nil
	end
	for c = lo + 1, hi - 1 do
		if not cols[c] then
			return true, table.concat(names, "-")
		end
	end
	return false, nil
end

local function round3(v: number): number
	return math.floor(v * 1000 + 0.5) / 1000
end

-- times keep five places: at 30 studs a second a millisecond is already a visible 0.03 studs
local function roundT(v: number): number
	return math.floor(v * 100000 + 0.5) / 100000
end

type Pin = {
	x: number,
	d: number,
	vx: number,
	vd: number,
	up: boolean, -- still standing
	live: boolean, -- on the deck (standing or sliding); false once in the pit or never there
	r: number,
	dirty: boolean,
	keys: { number },
}

local function key(keys: { number }, t: number, x: number, d: number, vx: number, vd: number)
	table.insert(keys, roundT(t))
	table.insert(keys, round3(x))
	table.insert(keys, round3(d))
	table.insert(keys, round3(vx))
	table.insert(keys, round3(vd))
end

-- A sliding pin's key point: the velocity is shaved by half a step of friction so the closed form drawn from
-- it lands exactly where the stepped simulation does.
local function pinKey(p: Pin, t: number)
	local sp = math.sqrt(p.vx * p.vx + p.vd * p.vd)
	local k = if sp > 1e-9 then math.max(0, sp - 0.5 * PinModel.FRICTION * PinModel.DT) / sp else 0
	key(p.keys, t, p.x, p.d, p.vx * k, p.vd * k)
end

function PinModel.roll(entry: Entry, mask: { boolean }, seed: number): Result
	local rng = Rng.new(seed)
	local jitter = PinModel.SPOT_JITTER
	local pins: { Pin } = {}
	for n = 1, 10 do
		local sx, sd = PinModel.spot(n)
		-- the jitter is always drawn so a pin's spot does not depend on which other pins stand
		local jx, jd = (rng.next() * 2 - 1) * jitter, (rng.next() * 2 - 1) * jitter
		local there = mask[n] == true
		pins[n] = {
			x = sx + jx,
			d = sd + jd,
			vx = 0,
			vd = 0,
			up = there,
			live = there,
			r = PinModel.PIN_R,
			dirty = false,
			keys = {},
		}
	end
	local eBall = PinModel.E_BALL + (rng.next() * 2 - 1) * PinModel.E_JITTER
	local ePin = PinModel.E_PIN + (rng.next() * 2 - 1) * PinModel.E_JITTER
	local dt = PinModel.DT
	local R = PinModel.BALL_R
	local M = PinModel.MASS_BALL
	local wall = PinModel.WALL_X
	local hitT = table.create(10, -1)
	local pitT = table.create(10, -1)
	local ball: { number } = {}
	local bx, bd, bvx, bvd = entry.x, PinModel.DECK_START, entry.vx, entry.vd
	local ballLive, ballDirty = true, false
	local ballEnd = 0
	local firstHit: number?, firstPin: number?, hitX: number? = nil, nil, nil
	key(ball, 0, bx, bd, bvx, bvd)
	local t = 0
	while t < PinModel.MAX_T do
		t += dt
		local moving = false
		if ballLive then
			bx += bvx * dt
			bd += bvd * dt
			moving = true
			if math.abs(bx) > wall - R then
				bx = math.clamp(bx, -(wall - R), wall - R)
				bvx = -bvx * 0.3
				ballDirty = true
			end
			if bd > PinModel.DECK_END + R or bd < PinModel.DECK_START - 2 then
				ballLive = false
				ballEnd = t
				key(ball, t, bx, bd, bvx, bvd)
			end
		end
		for n = 1, 10 do
			local p = pins[n]
			if p.live and not p.up then
				local sp = math.sqrt(p.vx * p.vx + p.vd * p.vd)
				if sp > 1e-6 then
					local ns = math.max(0, sp - PinModel.FRICTION * dt)
					p.vx *= ns / sp
					p.vd *= ns / sp
					p.x += p.vx * dt
					p.d += p.vd * dt
					if ns > 0.05 then
						moving = true
					end
					if math.abs(p.x) > wall - p.r then
						p.x = math.clamp(p.x, -(wall - p.r), wall - p.r)
						p.vx = -p.vx * PinModel.E_WALL
						p.dirty = true
					end
					if p.d > PinModel.DECK_END + 0.3 then
						p.live = false -- over the edge into the pit
						pitT[n] = roundT(t)
						p.dirty = true
					elseif p.d < PinModel.DECK_START - 3 and p.vd < 0 then
						p.vd = -p.vd * 0.2 -- a pin skidding back up the lane dies there
						p.dirty = true
					end
				end
				if p.r < PinModel.REACH then
					p.r = math.min(PinModel.REACH, p.r + PinModel.GROW * dt)
				end
			end
		end
		-- ball against pins
		if ballLive then
			for n = 1, 10 do
				local p = pins[n]
				if p.live then
					local dx, dd = p.x - bx, p.d - bd
					local rr = R + p.r
					local dist2 = dx * dx + dd * dd
					if dist2 < rr * rr and dist2 > 1e-9 then
						local dist = math.sqrt(dist2)
						local nx, nd = dx / dist, dd / dist
						local rv = (p.vx - bvx) * nx + (p.vd - bvd) * nd
						if rv < 0 then
							local j = -(1 + eBall) * rv / (1 / M + 1)
							bvx -= j / M * nx
							bvd -= j / M * nd
							p.vx += j * nx
							p.vd += j * nd
							p.up = false
							p.dirty = true
							ballDirty = true
							if hitT[n] < 0 then
								hitT[n] = roundT(t)
							end
							if firstHit == nil then
								firstHit, firstPin, hitX = roundT(t), n, round3(bx - p.x)
							end
						end
					end
				end
			end
		end
		-- pins against pins
		for i = 1, 9 do
			local p = pins[i]
			if p.live then
				for k = i + 1, 10 do
					local q = pins[k]
					if q.live and not (p.up and q.up) then
						local dx, dd = q.x - p.x, q.d - p.d
						local rr = p.r + q.r
						local dist2 = dx * dx + dd * dd
						if dist2 < rr * rr and dist2 > 1e-9 then
							local dist = math.sqrt(dist2)
							local nx, nd = dx / dist, dd / dist
							local rv = (q.vx - p.vx) * nx + (q.vd - p.vd) * nd
							if rv < 0 then
								local j = -(1 + ePin) * rv / 2
								if (p.up or q.up) and j < PinModel.TOPPLE then
									-- too soft to topple the standing pin: the sliding one bounces off it
									if p.up then
										q.vx -= (1 + ePin) * rv * nx
										q.vd -= (1 + ePin) * rv * nd
										q.dirty = true
									else
										p.vx += (1 + ePin) * rv * nx
										p.vd += (1 + ePin) * rv * nd
										p.dirty = true
									end
								else
									p.vx -= j * nx
									p.vd -= j * nd
									q.vx += j * nx
									q.vd += j * nd
									if p.up then
										p.up = false
										hitT[i] = roundT(t)
									end
									if q.up then
										q.up = false
										hitT[k] = roundT(t)
									end
									p.dirty = true
									q.dirty = true
								end
							end
						end
					end
				end
			end
		end
		for n = 1, 10 do
			local p = pins[n]
			if p.dirty then
				p.dirty = false
				pinKey(p, t)
			end
		end
		if ballDirty then
			ballDirty = false
			if ballLive then
				key(ball, t, bx, bd, bvx, bvd)
			end
		end
		if not moving then
			break
		end
	end
	if ballLive then
		ballEnd = t
		key(ball, t, bx, bd, bvx, bvd)
	end
	local standing: { boolean } = {}
	local keysOut: { { number } } = {}
	local down = 0
	for n = 1, 10 do
		local p = pins[n]
		standing[n] = p.up
		if mask[n] == true and not p.up then
			down += 1
			if p.live then
				-- where it came to rest (in case the clock ran out with it still creeping)
				key(p.keys, t, p.x, p.d, 0, 0)
			end
		end
		keysOut[n] = p.keys
	end
	return {
		standing = standing,
		down = down,
		ball = ball,
		pins = keysOut,
		hitT = hitT,
		pitT = pitT,
		firstHit = firstHit,
		firstPin = firstPin,
		hitX = hitX,
		ballEnd = roundT(ballEnd),
		tEnd = roundT(t),
	}
end

-- A piece's place at time t from its key points: straight from the last key point at or before t, slowing by
-- `friction` (0 for the ball) until it stops. Before the first key point it is where that point says.
function PinModel.segAt(keys: { number }, t: number, friction: number): (number, number, boolean)
	local n = #keys // 5
	if n == 0 then
		return 0, 0, false
	end
	local i = 1
	while i < n and keys[5 * i + 1] <= t do
		i += 1
	end
	local o = 5 * (i - 1)
	local t0, x, d, vx, vd = keys[o + 1], keys[o + 2], keys[o + 3], keys[o + 4], keys[o + 5]
	local tau = t - t0
	if tau <= 0 then
		return x, d, false
	end
	local sp = math.sqrt(vx * vx + vd * vd)
	if sp < 1e-9 then
		return x, d, false
	end
	if friction <= 0 then
		return x + vx * tau, d + vd * tau, true
	end
	local stop = sp / friction
	local moving = tau < stop
	if not moving then
		tau = stop
	end
	local dist = sp * tau - 0.5 * friction * tau * tau
	return x + vx / sp * dist, d + vd / sp * dist, moving
end

return PinModel
