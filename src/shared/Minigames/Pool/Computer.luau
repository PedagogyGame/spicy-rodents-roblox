--!strict
-- ReplicatedStorage.Shared.Minigames.Pool.Computer
-- The computer players for eight-ball and bumper pool: three skill levels each, with names that belong to the
-- games. A computer player plays through the SAME inputs a person gives (set the cue ball down, call a pocket,
-- strike with an angle, a power and a tip position): it returns the list of inputs for its turn and the rules
-- module does the rest, so it cannot do anything a person could not.
--   Eight-ball: it looks for ghost-ball shots (the place the cue ball must be to send a legal ball at a
--   pocket) with a clear line for both balls, ranks them by how forgiving they are (cut, distances, the
--   pocket's angle), picks the speed that gets the object ball home, and then misses by its level: an aim
--   error and a power error. The two better players try their pick through the table model first (a few
--   shots: a touch of aim for the throw, another tip if the cue ball would follow the object ball in) the
--   way a good player sees a shot before playing it. With nothing on, it plays a legal hit; on the 8 it
--   calls the pocket; with the ball in hand it sets the cue ball down for its easiest shot; it breaks from
--   the head spot.
--   Bumper pool: it finds its shot by trying candidates through the model (straight at the cup, off each
--   side cushion, off the end, and a fan of angles round each), scores what each leaves (down in the right
--   cup, down in the wrong one, or how near), and plays the best with its level's error. The marked ball
--   first, always.
-- Pure and seeded: the same state, level and seed give the same inputs. Lune-tested
-- (tests/unit/pool_games.spec.luau: whole games to the end on several seeds).
-- Thinking costs model runs (the best bumper pool player tries up to 144 shots, some tens of milliseconds in
-- all), so both entry points take an optional `breathe` function that is called after every model run: the
-- server passes one that yields when its frame budget is spent (the computer player has two seconds before
-- it must strike), and the answer is the same with or without it.
-- Interface: POOL_PLAYERS, BUMPER_PLAYERS ({ name, level }); LEVELS; eightBall(state, level, seed,
--   breathe?) -> { Input }; bumper(state, seat, level, seed, breathe?) -> { Input }; Input = { verb, args }

local BumperPool = require("./BumperPool")
local Cloth = require("./Cloth")
local Cue = require("./Cue")
local EightBall = require("./EightBall")
local Rng = require("../../Util/Rng")
local Shot = require("./Shot")
local Tables = require("./Tables")

local Computer = {}

export type Input = { verb: string, args: { any } }
export type Level = {
	aim: number, -- radians: the usual miss of the aim
	power: number, -- share of the power it is out by
	sims: number, -- shots it may try through the model before playing (0: it plays what it sees)
	breakPower: number,
	choices: number, -- it picks among this many of the easiest shots
	fan: { number }, -- bumper pool: the angles (degrees) it tries round each line
	balls: number, -- bumper pool: how many of its balls it considers
	bank: number, -- bumper pool: radians, the usual miss of the aim (banks are harder to judge than pots)
	touch: number, -- bumper pool: share of the power it is out by
}

Computer.LEVELS = {
	{
		aim = math.rad(1.7),
		power = 0.16,
		sims = 0,
		breakPower = 0.8,
		choices = 3,
		fan = { 0, -3, 3 },
		balls = 1,
		bank = math.rad(3.6),
		touch = 0.26,
	},
	{
		aim = math.rad(0.38),
		power = 0.08,
		sims = 6,
		breakPower = 0.92,
		choices = 2,
		fan = { 0, -1.5, 1.5, -3.5, 3.5 },
		balls = 2,
		bank = math.rad(1.7),
		touch = 0.13,
	},
	{
		aim = math.rad(0.1),
		power = 0.03,
		sims = 18,
		breakPower = 1,
		choices = 1,
		fan = { 0, -0.8, 0.8, -1.8, 1.8, -3, 3, -4.5, 4.5 },
		balls = 2,
		bank = math.rad(0.55),
		touch = 0.05,
	},
} :: { Level }

Computer.POOL_PLAYERS = {
	{ name = "Chalky", level = 1 },
	{ name = "Side-Pocket Sal", level = 2 },
	{ name = "Eight-Ball Edna", level = 3 },
}
Computer.BUMPER_PLAYERS = {
	{ name = "Bumper Bob", level = 1 },
	{ name = "Bank-Shot Betty", level = 2 },
	{ name = "Cushion Carl", level = 3 },
}

local function levelOf(level: number): Level
	return Computer.LEVELS[math.clamp(math.floor(level), 1, #Computer.LEVELS)]
end

-- an error with standard deviation `sigma` (three draws: mostly small, now and then a real miss)
local function wobble(rng: Rng.Rng, sigma: number): number
	return sigma * (rng.range(-1, 1) + rng.range(-1, 1) + rng.range(-1, 1))
end

local function spotOf(spots: { Tables.Spot }, id: number): Tables.Spot?
	for _, s in spots do
		if s.id == id then
			return s
		end
	end
	return nil
end

-- Is the straight line between two points clear of every ball (but the two named) by `width`?
local function clearPath(
	spots: { Tables.Spot },
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	skipA: number,
	skipB: number,
	width: number
): boolean
	local dx, dz = x2 - x1, z2 - z1
	local len2 = dx * dx + dz * dz
	local w2 = width * width
	for _, s in spots do
		if s.id ~= skipA and s.id ~= skipB then
			local t = if len2 > 0 then ((s.x - x1) * dx + (s.z - z1) * dz) / len2 else 0
			t = math.clamp(t, 0, 1)
			local px, pz = x1 + dx * t - s.x, z1 + dz * t - s.z
			if px * px + pz * pz < w2 then
				return false
			end
		end
	end
	return true
end

type Option = {
	ball: number,
	hole: number,
	angle: number,
	cut: number, -- cosine of the cut angle (1: straight in)
	d1: number, -- cue ball to the ghost ball
	d2: number, -- object ball to the pocket
	ease: number,
}

-- where to send a ball so that it drops: a little inside the mouth, on the pocket's centre line
local function pocketAim(hole: Tables.Hole): (number, number, boolean)
	local side = hole.mz == 0
	local k = if side then 0.26 else 0.35
	return hole.x + hole.mx * k, hole.z + hole.mz * k, side
end

-- Every ghost-ball shot from a cue ball at (cx, cz): a legal ball, a pocket, clear lines for both.
local function options(tb: Tables.Table, spots: { Tables.Spot }, cx: number, cz: number, legal: { number }): { Option }
	local out: { Option } = {}
	local R = tb.ballR
	local width = 2 * R - 0.004
	for _, id in legal do
		local b = spotOf(spots, id)
		if b == nil then
			continue
		end
		for h, hole in tb.holes do
			local tx, tz, side = pocketAim(hole)
			local dx, dz = tx - b.x, tz - b.z
			local d2 = math.sqrt(dx * dx + dz * dz)
			if d2 < 1e-6 then
				continue
			end
			dx, dz = dx / d2, dz / d2
			-- how square the ball comes at the pocket (a side pocket turns away a ball from along the cushion)
			local approach = -(dx * hole.mx + dz * hole.mz)
			if approach < (if side then 0.6 else 0.3) then
				continue
			end
			local gx, gz = b.x - 2 * R * dx, b.z - 2 * R * dz
			local ax, az = gx - cx, gz - cz
			local d1 = math.sqrt(ax * ax + az * az)
			if d1 < 1e-6 or not Tables.onBed(tb, gx, gz, -0.002) then
				continue
			end
			local cut = (ax * dx + az * dz) / d1
			if cut < 0.34 then
				continue
			end
			if
				not clearPath(spots, cx, cz, gx, gz, 0, id, width)
				or not clearPath(spots, b.x, b.z, tx, tz, 0, id, width)
			then
				continue
			end
			table.insert(out, {
				ball = id,
				hole = h,
				angle = Cue.angleOf(ax, az),
				cut = cut,
				d1 = d1,
				d2 = d2,
				ease = cut * cut * approach / (math.max(d1, 0.5) * math.max(d2, 0.5)),
			})
		end
	end
	table.sort(out, function(a, b)
		if a.ease ~= b.ease then
			return a.ease > b.ease
		end
		if a.ball ~= b.ball then
			return a.ball < b.ball
		end
		return a.hole < b.hole
	end)
	return out
end

-- the power that carries the object ball to the pocket with a little to spare
local function powerFor(o: Option): number
	local vo = 1.4 * math.sqrt(2 * Cloth.A_ROLL * (o.d2 + 2.5))
	local vc = vo / (o.cut * 0.97)
	local v = math.sqrt(vc * vc + 3 * Cloth.A_ROLL * o.d1)
	return Cue.powerFor(math.clamp(v, 3, Cue.speed(0.8)))
end

-- Where to set the cue ball down when it is in hand: behind the easiest ball, or the best place in the kitchen.
local function placement(state: EightBall.State, legal: { number }): (number, number)
	local tb = Tables.eightBall()
	local spots = state.spots
	local cue = spotOf(spots, 0)
	local bx, bz = if cue then cue.x else 0, if cue then cue.z else tb.headZ
	local best = -1
	local function consider(x: number, z: number)
		if not EightBall.canPlace(state, x, z) then
			return
		end
		local opts = options(tb, spots, x, z, legal)
		if #opts > 0 and opts[1].ease > best then
			best = opts[1].ease
			bx, bz = x, z
		end
	end
	if state.inHand == "kitchen" then
		for i = -5, 5 do
			for j = 0, 5 do
				consider(i * 0.44, tb.headZ - j * 0.45)
			end
		end
	else
		local R = tb.ballR
		for _, id in legal do
			local b = spotOf(spots, id)
			if b then
				for _, hole in tb.holes do
					local tx, tz = pocketAim(hole)
					local dx, dz = tx - b.x, tz - b.z
					local d = math.sqrt(dx * dx + dz * dz)
					if d > 1e-6 then
						dx, dz = dx / d, dz / d
						for _, back in { 1.4, 0.9, 0.5 } do
							consider(b.x - (2 * R + back) * dx, b.z - (2 * R + back) * dz)
						end
					end
				end
			end
		end
	end
	return bx, bz
end

-- Would this shot do what was meant? (the better players' look ahead)
local function works(
	tb: Tables.Table,
	spots: { Tables.Spot },
	o: Option,
	angle: number,
	power: number,
	tipY: number
): boolean
	local script = Shot.run(tb, spots, { Cue.strike(0, angle, power, 0, tipY, nil) })
	if script.first[1] ~= o.ball then
		return false
	end
	local potted = false
	for _, p in Shot.pots(script) do
		if p.ball == 0 then
			return false
		elseif p.ball == o.ball then
			potted = o.ball ~= 8 or p.hole == o.hole
		elseif p.ball == 8 then
			return false
		end
	end
	return potted
end

-- A legal hit when nothing is on: the nearest legal ball in plain view, hit full; failing that, whatever
-- the table model says reaches a legal ball off a cushion.
local function legalHit(
	state: EightBall.State,
	legal: { number },
	cx: number,
	cz: number,
	rng: Rng.Rng,
	tries: number,
	breathe: (() -> ())?
): (number, number)
	local tb = Tables.eightBall()
	local spots = state.spots
	local width = 2 * tb.ballR - 0.004
	local bestD, bestAngle = math.huge, 0
	local anyD, anyAngle = math.huge, 0
	for _, id in legal do
		local b = spotOf(spots, id)
		if b then
			local dx, dz = b.x - cx, b.z - cz
			local d = math.sqrt(dx * dx + dz * dz)
			if d < anyD then
				anyD, anyAngle = d, Cue.angleOf(dx, dz)
			end
			if d < bestD and clearPath(spots, cx, cz, b.x, b.z, 0, id, width) then
				bestD, bestAngle = d, Cue.angleOf(dx, dz)
			end
		end
	end
	if bestD < math.huge then
		return bestAngle, Cue.powerFor(math.sqrt(2 * Cloth.A_ROLL * (bestD + 7)))
	end
	local isLegal: { [number]: boolean } = {}
	for _, id in legal do
		isLegal[id] = true
	end
	local turn = rng.range(0, 2 * math.pi)
	for k = 0, tries - 1 do
		local angle = turn + 2 * math.pi * k / tries
		local script = Shot.run(tb, spots, { Cue.strike(0, angle, 0.34, 0, 0.8, nil) })
		if breathe then
			breathe()
		end
		if isLegal[script.first[1]] and script.railAfter then
			local bad = false
			for _, p in Shot.pots(script) do
				if p.ball == 0 or p.ball == 8 then
					bad = true
				end
			end
			if not bad then
				return angle, 0.34
			end
		end
	end
	return anyAngle, 0.3
end

-- The inputs for the computer player's turn at eight-ball (the seat to play is state.seat).
function Computer.eightBall(state: EightBall.State, level: number, seed: number, breathe: (() -> ())?): { Input }
	local L = levelOf(level)
	local rng = Rng.new(seed * 31 + state.shotNo * 977 + 5)
	local tb = Tables.eightBall()
	local out: { Input } = {}
	if state.done then
		return out
	end
	local seat = state.seat
	local legal = EightBall.legal(state, seat)
	local cue = spotOf(state.spots, 0)
	local cx, cz = if cue then cue.x else 0, if cue then cue.z else tb.headZ
	if not state.broken then
		-- the break, square into the front ball: the beginner from about the head spot with follow (the cue
		-- ball goes looking for a pocket), the better players centre ball, the best from out by the side
		-- cushion, where the rack opens best
		local apex: Tables.Spot? = nil
		for _, s in state.spots do
			if s.id ~= 0 and (apex == nil or s.z < apex.z) then
				apex = s
			end
		end
		local lvl = math.clamp(math.floor(level), 1, 3)
		local px = rng.range(-0.25, 0.25)
		if lvl == 2 then
			px = rng.range(-0.7, 0.7)
		elseif lvl == 3 then
			px = (if rng.next() < 0.5 then -1.2 else 1.2) + rng.range(-0.1, 0.1)
		end
		if EightBall.canPlace(state, px, tb.headZ) then
			table.insert(out, { verb = "place", args = { px, tb.headZ } })
			cx, cz = px, tb.headZ
		end
		local ax, az = if apex then apex.x else 0, if apex then apex.z else tb.footZ
		local angle = Cue.angleOf(ax - cx, az - cz) + wobble(rng, L.aim * 0.5)
		table.insert(out, { verb = "shoot", args = { angle, L.breakPower, 0, if lvl == 1 then 0.3 else 0 } })
		return out
	end
	if state.inHand ~= "none" then
		local x, z = placement(state, legal)
		if x ~= cx or z ~= cz then
			table.insert(out, { verb = "place", args = { x, z } })
			cx, cz = x, z
		end
	end
	-- the look ahead must see the cue ball where it will be played from
	local spots = state.spots
	if cue and (cue.x ~= cx or cue.z ~= cz) then
		spots = table.clone(state.spots)
		for i, s in spots do
			if s.id == 0 then
				spots[i] = { id = 0, x = cx, z = cz }
			end
		end
	end
	local opts = options(tb, spots, cx, cz, legal)
	local angle: number, power: number
	local tipY = 0.8
	local pick: Option? = nil
	if #opts > 0 then
		local chosen = opts[1 + math.floor(rng.next() * math.min(L.choices, #opts))]
		pick = chosen
		angle, power = chosen.angle, powerFor(chosen)
		if L.sims > 0 then
			-- look ahead: the easiest shots first, each with a touch of aim either way and three tips
			local left = L.sims
			local found = false
			for k = 1, math.min(#opts, 3) do
				local o = opts[k]
				local p = powerFor(o)
				for _, ty in { 0.8, -0.3, -0.9 } do
					for _, off in { 0, 0.25, -0.25, 0.55, -0.55 } do
						if left <= 0 or found then
							break
						end
						left -= 1
						local a = o.angle + math.rad(off)
						if works(tb, spots, o, a, p, ty) then
							found = true
							pick, angle, power, tipY = o, a, p, ty
						end
						if breathe then
							breathe()
						end
					end
				end
				if found or left <= 0 then
					break
				end
			end
		end
		angle += wobble(rng, L.aim)
		power = math.clamp(power * (1 + wobble(rng, L.power)), 0.03, 0.88)
	else
		angle, power = legalHit(state, legal, cx, cz, rng, 12 + 12 * math.clamp(math.floor(level), 1, 3), breathe)
		angle += wobble(rng, L.aim)
	end
	if EightBall.onEight(state, seat) then
		-- the 8 is called: the pocket it is aimed at, or the nearest one to it
		local hole = 1
		if pick then
			hole = pick.hole
		else
			local eight = spotOf(spots, 8)
			local nearest = math.huge
			for h, ho in tb.holes do
				local d = if eight then (ho.x - eight.x) ^ 2 + (ho.z - eight.z) ^ 2 else 0
				if d < nearest then
					nearest, hole = d, h
				end
			end
		end
		table.insert(out, { verb = "call", args = { hole } })
	end
	table.insert(out, { verb = "shoot", args = { angle, power, 0, tipY } })
	return out
end

-- What a tried bumper pool shot is worth to `seat`.
local function bumperScore(state: BumperPool.State, seat: number, ball: number, script: Shot.Script): number
	local tb = Tables.bumper()
	local score = 0
	local marked = BumperPool.markedOf(seat)
	local markedDown = state.markedDown[seat]
	local sunk = state.sunk[seat]
	for _, p in Shot.pots(script) do
		local owner = BumperPool.sideOf(p.ball)
		if owner ~= seat then
			score -= 35 -- it counts for them
		elseif p.hole == BumperPool.cupOf(seat) or state.seats < 2 then
			sunk += 1
			if p.ball == marked then
				markedDown = true
				score += 100
			elseif markedDown then
				score += 100
			else
				score -= 120 -- before the marked ball: they would drop two
			end
		else
			sunk += 1
			score -= if sunk >= 5 then 1000 else 150
		end
	end
	local cup = tb.holes[BumperPool.cupOf(seat)]
	local r = script.rest
	for i = 1, #r, 3 do
		if r[i] == ball then
			local dx, dz = r[i + 1] - cup.x, r[i + 2] - cup.z
			score -= 4 * math.sqrt(dx * dx + dz * dz)
		end
	end
	return score
end

-- The inputs for `seat`'s turn at bumper pool (in the opening, its strike of the marked ball).
function Computer.bumper(
	state: BumperPool.State,
	seat: number,
	level: number,
	seed: number,
	breathe: (() -> ())?
): { Input }
	local L = levelOf(level)
	local rng = Rng.new(seed * 31 + state.shotNo * 977 + seat * 13)
	local tb = Tables.bumper()
	if state.done then
		return {}
	end
	local cup = tb.holes[BumperPool.cupOf(seat)]
	local marked = BumperPool.markedOf(seat)
	local own = BumperPool.mine(state, seat)
	if #own == 0 then
		return {}
	end
	local balls: { number } = {}
	if state.phase == "opening" then
		balls = { state.openers[seat] }
	elseif not state.markedDown[seat] and table.find(own, marked) then
		balls = { marked }
	else
		-- the ones lying nearest the cup
		local dist: { [number]: number } = {}
		for _, id in own do
			local s = spotOf(state.spots, id) :: Tables.Spot
			dist[id] = (s.x - cup.x) ^ 2 + (s.z - cup.z) ^ 2
		end
		table.sort(own, function(a, b)
			if dist[a] ~= dist[b] then
				return dist[a] < dist[b]
			end
			return a < b
		end)
		for k = 1, math.min(L.balls, #own) do
			balls[k] = own[k]
		end
	end
	local wallX = tb.halfW - tb.ballR
	local wallZ = tb.halfL - tb.ballR
	local bestScore, bestBall, bestAngle, bestPower = -math.huge, balls[1], 0, 0.2
	for _, id in balls do
		local s = spotOf(state.spots, id)
		if s == nil then
			continue
		end
		-- the lines: straight at the cup, off either side cushion, off the cushion behind the cup
		local sz = if cup.z > 0 then 1 else -1
		local lines = {
			{ cup.x - s.x, cup.z - s.z },
			{ 2 * wallX - cup.x - s.x, cup.z - s.z },
			{ -2 * wallX - cup.x - s.x, cup.z - s.z },
			{ cup.x - s.x, 2 * sz * wallZ - cup.z - s.z },
		}
		for _, ln in lines do
			local len = math.sqrt(ln[1] * ln[1] + ln[2] * ln[2])
			if len < 1e-6 then
				continue
			end
			local base = Cue.angleOf(ln[1], ln[2])
			-- arrive slowly enough to drop: a cup takes a ball by its speed
			local p0 = Cue.powerFor(math.sqrt(3.2 * 3.2 + 2 * Cloth.A_ROLL * len * 1.35))
			for _, off in L.fan do
				for pk = 1, if L.sims > 0 then 2 else 1 do
					local angle = base + math.rad(off)
					local power = math.clamp(p0 * (if pk == 1 then 1 else 1.3), 0.03, 0.9)
					local script = Shot.run(tb, state.spots, { Cue.strike(id, angle, power, 0, 0.8, nil) })
					local score = bumperScore(state, seat, id, script)
					if breathe then
						breathe()
					end
					if score > bestScore then
						bestScore, bestBall, bestAngle, bestPower = score, id, angle, power
					end
				end
			end
		end
	end
	local angle = bestAngle + wobble(rng, L.bank)
	local power = math.clamp(bestPower * (1 + wobble(rng, L.touch)), 0.03, 0.9)
	return { { verb = "shoot", args = { bestBall, angle, power, 0, 0.8 } } }
end

return Computer
