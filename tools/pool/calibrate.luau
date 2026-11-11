--!strict
-- tools/pool/calibrate.luau: a developer's look at the cue-sport table model (Shared/Minigames/Pool) so its
-- constants are tuned from numbers, not guesses. Prints: how the cloth slows a ball; what a cushion gives
-- back and how side spin turns the angle; what follow, draw and stun do; how the pockets accept and refuse
-- by angle and speed (and how much tighter they play when hammered); the break (spread, pots, scratches, time to rest); bumper pool's cups against speed and
-- its posts; how each computer player does at both games; and what a step and a shot cost.
-- Usage, from the repo root: lune run tools/pool/calibrate.luau [breaks, default 200] [games, default 12]
-- Interface: a script (prints a report); nothing is written.

local process = require("@lune/process")
local BumperPool = require("../../src/shared/Minigames/Pool/BumperPool")
local Cloth = require("../../src/shared/Minigames/Pool/Cloth")
local Computer = require("../../src/shared/Minigames/Pool/Computer")
local Cue = require("../../src/shared/Minigames/Pool/Cue")
local EightBall = require("../../src/shared/Minigames/Pool/EightBall")
local Physics = require("../../src/shared/Minigames/Pool/Physics")
local Shot = require("../../src/shared/Minigames/Pool/Shot")
local Tables = require("../../src/shared/Minigames/Pool/Tables")

local BREAKS = tonumber(process.args[1]) or 200
local GAMES = tonumber(process.args[2]) or 12

local pool = Tables.eightBall()
local bumper = Tables.bumper()
local EV = Physics.EV

local function f(v: number, places: number?): string
	return string.format(`%.{places or 1}f`, v)
end

local function strike(id: number, vx: number, vz: number, roll: number, side: number): Shot.Strike
	-- roll: 1 a natural roll, 0 stun, -1 full draw
	return { id = id, vx = vx, vz = vz, qx = roll * vx, qz = roll * vz, s = side }
end

-- step the world until `events` contacts have been recorded (or everything has stopped)
local function untilEvents(w: Physics.World, events: number)
	while #w.events < events * Physics.EVENT_STRIDE do
		if not Physics.step(w) then
			break
		end
	end
end

local function restOf(script: Shot.Script, id: number): (number?, number?)
	for _, s in Shot.rest(script) do
		if s.id == id then
			return s.x, s.z
		end
	end
	return nil, nil
end

print("== the cloth (one ball, rolling from the head cushion up the table)")
for _, v in { 1.5, 3, 4.4, 6, 10, 20, 40, 60 } do
	local s = Shot.run(pool, { { id = 0, x = 0, z = -5 } }, { strike(0, 0, v, 1, 0) })
	local cushions = 0
	for e = 1, #s.events, Physics.EVENT_STRIDE do
		if s.events[e + 1] == EV.cushion then
			cushions += 1
		end
	end
	print(
		`  {f(v)} studs/s: at rest after {f(s.tEnd - Shot.REST_PAD, 2)} s, {cushions} cushions (alone it would roll {f(
			Cloth.rollDistance(v)
		)} studs)`
	)
end

print("== a cushion, square on (a rolling ball; speed back / speed in at the cushion, and once it rolls again)")
for _, v in { 2, 5, 10, 20, 35, 55 } do
	local hits = 0
	local w = Physics.world(pool, { { id = 0, x = 0, z = pool.halfL - pool.ballR - 0.05 } })
	Physics.strike(w, 0, 0, v, 0, v, 0)
	local vin, vout, vroll = 0, 0, 0
	while Physics.step(w) do
		local b = w.balls[1]
		if #w.events > 0 and vout == 0 then
			vin = w.events[5]
			vout = -b.vz
		end
		hits = #w.events / Physics.EVENT_STRIDE
		if hits > 1 or (vout ~= 0 and math.abs(b.vz - b.qz) < 1e-6) then
			vroll = -b.vz
			break
		end
	end
	local rolling = if hits > 1
		then "it reaches the far cushion still sliding"
		else `{f(100 * vroll / vin, 0)} % rolling`
	print(`  in {f(vin)}: back {f(100 * vout / vin, 0)} % at the cushion, {rolling}`)
end

print("== a cushion at 45 degrees (angle off the cushion as it leaves, then once it rolls again; 45 is a mirror)")
for _, v in { 6, 14, 30 } do
	local line = `  {f(v)} studs/s:`
	for _, side in { 0, 1, -1 } do
		-- going +x and +z into the foot cushion; running side for that is counter-clockwise (positive): the
		-- ball's face at the cushion moves back against its travel, so it rolls along the cushion
		local w = Physics.world(pool, { { id = 0, x = -2, z = pool.halfL - pool.ballR - 0.3 } })
		local c = v * 0.7071067811865476
		Physics.strike(w, 0, c, c, c, c, side * 0.8 * v)
		untilEvents(w, 1)
		local b = w.balls[1]
		local out = math.deg(math.atan2(-b.vz, b.vx))
		while #w.events == Physics.EVENT_STRIDE and math.abs(b.vz - b.qz) + math.abs(b.vx - b.qx) > 1e-6 do
			if not Physics.step(w) then
				break
			end
		end
		local name = if side == 0 then "no side" elseif side == 1 then "running" else "check"
		local settled = if #w.events == Physics.EVENT_STRIDE
			then f(math.deg(math.atan2(-b.vz, b.vx)))
			else "(still sliding at the next cushion)"
		line ..= ` {name} {f(out)} then {settled};`
	end
	print(line)
end

print("== ball on ball")
do
	for _, cut in { 15, 30, 45, 60 } do
		-- a stunned cue ball going +z; the object ball set so the line of centres is `cut` degrees off
		local a = math.rad(cut)
		local gx, gz = 0, 0
		local ox, oz = gx + 2 * pool.ballR * math.sin(a), gz + 2 * pool.ballR * math.cos(a)
		local w = Physics.world(pool, { { id = 0, x = 0, z = -0.01 }, { id = 1, x = ox, z = oz } })
		Physics.strike(w, 0, 0, 12, 0, 0, 0)
		untilEvents(w, 1)
		local c, o = w.balls[1], w.balls[2]
		local sep = math.deg(math.atan2(o.vx, o.vz) - math.atan2(c.vx, c.vz))
		local throw = cut - math.deg(math.atan2(o.vx, o.vz))
		print(`  stun, {cut} degree cut: the balls part at {f(math.abs(sep))} degrees; throw {f(throw, 2)} degrees`)
	end
	for _, row in { { "follow", 0.8 }, { "centre", 0 }, { "stop", -0.35 }, { "draw", -0.8 } } do
		local name, tipY = row[1] :: string, row[2] :: number
		-- close enough that the tip's spin is still on the ball when it arrives
		local spots = { { id = 0, x = 0, z = -5 }, { id = 1, x = 0, z = -4 } }
		local s = Shot.run(pool, spots, { Cue.strike(0, 0, 0.25, 0, tipY, nil) })
		local _, cz = restOf(s, 0)
		local past = (cz or 0) - (-4 - 2 * pool.ballR)
		print(
			`  {name} (tip {f(tipY, 2)}) at power 0.25 from 1 stud: the cue ball stops {f(past, 2)} studs past the contact`
		)
	end
end

-- Fire an object ball at a pocket from `dist` studs, `angle` degrees off the pocket's centre line, `off`
-- studs to one side of the perfect line. Returns "pot", "rattle" (touched a jaw and stayed up) or "miss".
local function atPocket(h: number, dist: number, angle: number, off: number, speed: number): string
	local hole = pool.holes[h]
	local a = math.rad(angle)
	local ca, sa = math.cos(a), math.sin(a)
	-- the direction of travel: the mouth direction turned by `angle`, reversed
	local dx, dz = -(hole.mx * ca - hole.mz * sa), -(hole.mx * sa + hole.mz * ca)
	local k = if hole.mz == 0 then 0.26 else 0.35
	local tx, tz = hole.x + hole.mx * k, hole.z + hole.mz * k
	local x, z = tx - dx * dist - dz * off, tz - dz * dist + dx * off
	if not Tables.onBed(pool, x, z, 0) then
		return "off"
	end
	local s = Shot.run(
		pool,
		{ { id = 1, x = x, z = z } },
		{ strike(1, dx * speed, dz * speed, 1, 0) },
		1.5 * dist / speed + 0.5
	)
	if #s.pots > 0 then
		return "pot"
	end
	for e = 1, #s.events, Physics.EVENT_STRIDE do
		if s.events[e + 1] == EV.jaw then
			return "rattle"
		end
	end
	return "miss"
end

print("== pockets: share potted across a sweep of lines (width of the window in ball widths), and rattles")
for _, row in { { "corner", 6 }, { "side", 4 } } do
	local name, h = row[1] :: string, row[2] :: number
	for _, angle in if name == "corner" then { 0, 20, 40 } else { 0, 25, 45, 60, 70 } do
		local line = `  {name}, {angle} degrees off its centre line:`
		for _, speed in { 3, 8, 18, 36 } do
			local pot, rattle, n = 0, 0, 0
			for i = -40, 40 do
				local r = atPocket(h, 2.2, angle, i * 0.0125, speed)
				if r ~= "off" then
					n += 1
					if r == "pot" then
						pot += 1
					elseif r == "rattle" then
						rattle += 1
					end
				end
			end
			line ..= ` at {speed}: window {f(pot * 0.0125 / (2 * pool.ballR), 2)} ({rattle} rattles)`
		end
		print(line)
	end
end

print("== pockets against speed: down the long cushion into a corner (P drops, r rattles and stays up, . misses)")
print("   each column is the gap between ball and cushion, 0 to 1.6 ball radii in tenths")
for _, speed in { 4, 8, 14, 22, 36, 55 } do
	local line = `  {speed} studs/s: `
	for g = 0, 16 do
		local from = { { id = 1, x = pool.halfW - pool.ballR - g * 0.1 * pool.ballR, z = 0.8 } }
		local s = Shot.run(pool, from, { strike(1, 0, speed, 1, 0) }, 6 / speed + 1.5)
		local jaws = 0
		for e = 1, #s.events, Physics.EVENT_STRIDE do
			if s.events[e + 1] == EV.jaw then
				jaws += 1
			end
		end
		line ..= if #s.pots > 0 then "P" elseif jaws > 0 then "r" else "."
	end
	print(line)
end
do
	-- balls left hanging: a sweep of soft shots dying at a corner's mouth
	local hole = pool.holes[6]
	local hung, n = 0, 0
	for i = 0, 40 do
		local v = Cloth.speedFor(2.2 - 0.3 + i * 0.015)
		local from = { { id = 1, x = hole.x + hole.mx * 2.75, z = hole.z + hole.mz * 2.75 } }
		local s = Shot.run(pool, from, { strike(1, -hole.mx * v, -hole.mz * v, 1, 0) })
		n += 1
		local x, z = restOf(s, 1)
		if x and z and (math.abs(x) > pool.halfW - pool.ballR or math.abs(z) > pool.halfL - pool.ballR) then
			hung += 1
		end
	end
	print(`  soft shots dying at a corner's mouth: {hung} of {n} speeds leave the ball hanging in the jaws`)
end

-- {label, power, tip height, how far along the head string the cue ball is set}
local BREAK_KINDS: { { any } } = {
	{ "full power, centre ball, from the head spot", 1, 0, 0 },
	{ "full power with follow, from the head spot", 1, 0.3, 0 },
	{ "full power, centre ball, from 1.2 studs along the head string", 1, 0, 1.2 },
	{ "nine tenths power (inside the sure band), centre ball, from the head spot", 0.9, 0, 0 },
}
for _, kind in BREAK_KINDS do
	print(`== the break ({BREAKS} racks: {kind[1]})`)
	local pots, scratches, dry, head, tSum, tMax, contacts, steps, knots, sizeSum, sizeMax =
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	local far = 0
	local same = 0
	local firstLayout = ""
	local started = os.clock()
	for seed = 1, BREAKS do
		local spots = Tables.rack(seed)
		spots[1].x = kind[4]
		local angle = Cue.angleOf(spots[2].x - spots[1].x, spots[2].z - spots[1].z)
		local s = Shot.run(pool, spots, { Cue.strike(0, angle, kind[2], 0, kind[3], seed) })
		local np = 0
		for _, p in Shot.pots(s) do
			if p.ball == 0 then
				scratches += 1
			else
				np += 1
			end
		end
		pots += np
		if np == 0 then
			dry += 1
		end
		local layout = ""
		for _, r in Shot.rest(s) do
			if r.id ~= 0 then
				if r.z < 0 then
					head += 1
				end
				local dx, dz = r.x, r.z - pool.footZ - 0.6
				if dx * dx + dz * dz > 4 then
					far += 1
				end
			end
			layout ..= string.format("%d:%.3f,%.3f;", r.id, r.x, r.z)
		end
		if seed == 1 then
			firstLayout = layout
		elseif layout == firstLayout then
			same += 1
		end
		tSum += s.tEnd
		tMax = math.max(tMax, s.tEnd)
		contacts += s.contacts
		steps += s.steps
		knots += s.knots
		local size = Shot.size(s)
		sizeSum += size
		sizeMax = math.max(sizeMax, size)
	end
	local el = os.clock() - started
	print(
		`  balls potted per break {f(pots / BREAKS, 2)}; nothing potted {f(100 * dry / BREAKS, 0)} %; scratch {f(
			100 * scratches / BREAKS,
			0
		)} %`
	)
	print(
		`  object balls ending in the head half {f(head / BREAKS)} of 15; more than 2 studs from the rack {f(
			far / BREAKS
		)}`
	)
	print(`  at rest after {f(tSum / BREAKS)} s on average, {f(tMax)} s at most; breaks identical to the first: {same}`)
	print(
		`  contacts {f(contacts / BREAKS, 0)} a break; knots {knots}; script {f(sizeSum / BREAKS, 0)} numbers on average, {sizeMax} at most`
	)
	print(
		`  cost: {f(el / steps * 1e6, 2)} microseconds a step ({Physics.DT * 1000} ms steps), {f(el / BREAKS * 1000)} ms a break`
	)
end

-- what a ball does at a cup on its first visit: "drop", "out" (over the rim and out again) or "miss"
local function atCup(tb: Tables.Table, cz: number, off: number, speed: number): string
	-- struck a stud short of the rim so that it arrives rolling at `speed`
	local v0 = math.sqrt(speed * speed + 2 * Cloth.A_ROLL * 1)
	local from = { { id = 1, x = off, z = cz - 1 - math.sqrt(math.max(Tables.CUP_R ^ 2 - off * off, 0)) } }
	local s = Shot.run(tb, from, { strike(1, 0, v0, 1, 0) }, 1.5 / speed + 0.4)
	local entered = false
	for e = 1, #s.events, Physics.EVENT_STRIDE do
		local kind = s.events[e + 1]
		if kind == EV.drop then
			return "drop"
		elseif kind == EV.rim then
			return "out"
		elseif kind == EV.enter then
			entered = true
		elseif kind == EV.post and not entered then
			return "miss"
		end
	end
	return "miss"
end

print("== bumper pool: a cup alone in the cloth, by the speed a ball reaches its rim (lines across the whole cup)")
do
	local lone = table.clone(bumper)
	lone.posts = {}
	lone.holes = { { x = 0, z = 0, r = Tables.CUP_R, mx = 0, mz = 0, cup = true, depth = Tables.CUP_DEPTH } }
	for _, speed in { 1, 2, 3, 4, 4.5, 5, 6, 8, 12 } do
		local drop, out, n = 0, 0, 0
		for i = -19, 19 do
			local r = atCup(lone, 0, i / 20 * Tables.CUP_R, speed)
			n += 1
			if r == "drop" then
				drop += 1
			elseif r == "out" then
				out += 1
			end
		end
		print(`  {speed} studs/s: drops {f(100 * drop / n, 0)} %, lips out or skips over {f(100 * out / n, 0)} %`)
	end
end

print("== bumper pool: the real cup from the front (the end cushion just behind it is a backboard)")
do
	local cz = bumper.holes[2].z
	for _, speed in { 2, 4, 6, 8, 10, 14, 20 } do
		local drop, out, n = 0, 0, 0
		for i = -12, 12 do
			-- the lines that clear the two bumpers beside the cup
			local r = atCup(bumper, cz, i * 0.0125, speed)
			n += 1
			if r == "drop" then
				drop += 1
			elseif r == "out" then
				out += 1
			end
		end
		print(`  {speed} studs/s: drops {f(100 * drop / n, 0)} %, comes back out {f(100 * out / n, 0)} %`)
	end
	local line = "  a post, square on: back"
	for _, v in { 3, 10, 25 } do
		local w = Physics.world(bumper, { { id = 1, x = 0, z = -0.44 - 0.4 } })
		Physics.strike(w, 1, 0, v, 0, v, 0)
		untilEvents(w, 1)
		line ..= ` {f(100 * -w.balls[1].vz / w.events[5], 0)} % at {v}`
	end
	print(line)
	local through, n = 0, 0
	for i = -10, 10 do
		-- along the diagonal between two of the cross's inner posts, a hair to either side
		local off = i * 0.004
		local d = 0.7071067811865476
		local from = { { id = 1, x = -0.8 + off * d, z = -0.8 - off * d } }
		local s = Shot.run(bumper, from, { strike(1, 6 * d, 6 * d, 1, 0) }, 8)
		local touched = false
		for e = 1, #s.events, Physics.EVENT_STRIDE do
			if s.events[e + 1] == EV.post and s.events[e] < 0.35 then
				touched = true
			end
		end
		n += 1
		if not touched then
			through += 1
		end
	end
	print(`  the gap in the cross: {through} of {n} lines within 0.04 studs of its middle pass without touching a post`)
end

print(`== computer players at eight-ball ({GAMES} games each pairing)`)
for _, pair in { { 1, 1 }, { 2, 2 }, { 3, 3 }, { 1, 2 }, { 2, 3 } } do
	local shots, visits, potting, fouls, wins1, finished, planMs, planMax, plans = 0, 0, 0, 0, 0, 0, 0, 0, 0
	local hows: { [string]: number } = {}
	local tMax = 0
	for seed = 1, GAMES do
		local s = EightBall.init(2, seed)
		local n = 0
		while not s.done and n < 500 do
			local seat = s.seat
			local c0 = os.clock()
			local inputs = Computer.eightBall(s, pair[seat], seed)
			local ms = (os.clock() - c0) * 1000
			planMs += ms
			planMax = math.max(planMax, ms)
			plans += 1
			for _, inp in inputs do
				EightBall.input(s, seat, inp.verb, inp.args)
			end
			n += 1
			local last = s.last
			if last and s.broken and not last.breakShot then
				visits += 1
				if last.event == "continue" or last.event == "win" then
					potting += 1
				elseif last.event == "foul" then
					fouls += 1
				end
			end
			if s.lastScript then
				tMax = math.max(tMax, s.lastScript.tEnd)
			end
		end
		shots += n
		if s.done then
			finished += 1
			hows[s.how or "?"] = (hows[s.how or "?"] or 0) + 1
			if s.winner == 1 then
				wins1 += 1
			end
		end
	end
	local names = `{Computer.POOL_PLAYERS[pair[1]].name} v {Computer.POOL_PLAYERS[pair[2]].name}`
	local ends = ""
	for k, v in hows do
		ends ..= ` {k} {v}`
	end
	print(
		`  {names}: finished {finished}/{GAMES}, {f(shots / GAMES, 0)} shots a game, a shot pots {f(
			100 * potting / visits,
			0
		)} %, fouls {f(100 * fouls / visits, 0)} %, first seat won {wins1}; longest shot {f(tMax)} s; thinking {f(
			planMs / plans
		)} ms (most {f(planMax)});{ends}`
	)
end

print(`== computer players at bumper pool ({GAMES} games each pairing)`)
for _, pair in { { 1, 1 }, { 2, 2 }, { 3, 3 }, { 1, 2 }, { 2, 3 } } do
	local shots, wins1, finished, planMs, planMax, plans, banks, sunk = 0, 0, 0, 0, 0, 0, 0, 0
	local tMax = 0
	for seed = 1, GAMES do
		local s = BumperPool.init(2, seed)
		local n = 0
		while not s.done and n < 500 do
			for _, seat in BumperPool.waiting(s) do
				local c0 = os.clock()
				local inputs = Computer.bumper(s, seat, pair[seat], seed)
				local ms = (os.clock() - c0) * 1000
				planMs += ms
				planMax = math.max(planMax, ms)
				plans += 1
				for _, inp in inputs do
					BumperPool.input(s, seat, inp.verb, inp.args)
				end
			end
			n += 1
			if s.lastScript then
				tMax = math.max(tMax, s.lastScript.tEnd)
			end
		end
		shots += s.shots[1] + s.shots[2]
		banks += s.banks[1] + s.banks[2]
		sunk += s.sunk[1] + s.sunk[2]
		if s.done then
			finished += 1
			if s.winner == 1 then
				wins1 += 1
			end
		end
	end
	local names = `{Computer.BUMPER_PLAYERS[pair[1]].name} v {Computer.BUMPER_PLAYERS[pair[2]].name}`
	print(
		`  {names}: finished {finished}/{GAMES}, {f(shots / GAMES, 0)} shots a game, {f(banks / GAMES)} banks made, first seat won {wins1}; longest shot {f(
			tMax
		)} s; thinking {f(planMs / plans)} ms (most {f(planMax)})`
	)
end

print("== cost of the aim preview (the same model, run to the first contact and a moment past it)")
do
	local spots = Tables.rack(1)
	local started = os.clock()
	local n = 0
	for k = 1, 400 do
		Cue.preview(pool, spots, 0, (k - 200) * 0.004, 0.2 + (k % 5) * 0.15, 0, 0.5)
		n += 1
	end
	print(`  {f((os.clock() - started) / n * 1000, 3)} ms a preview at the break position`)
end

print("== cost of ordinary shots (eight-ball, a game between the middle players)")
do
	local s = EightBall.init(2, 7)
	local steps, contacts, ms, n, size, sizeMax = 0, 0, 0, 0, 0, 0
	while not s.done and n < 300 do
		local inputs = Computer.eightBall(s, 2, 7)
		for _, inp in inputs do
			local c0 = os.clock()
			EightBall.input(s, s.seat, inp.verb, inp.args)
			if inp.verb == "shoot" then
				ms += (os.clock() - c0) * 1000
			end
		end
		n += 1
		local sc = s.lastScript
		if sc then
			steps += sc.steps
			contacts += sc.contacts
			size += Shot.size(sc)
			sizeMax = math.max(sizeMax, Shot.size(sc))
		end
	end
	print(
		`  {n} shots: {f(ms / n, 2)} ms a shot, {f(steps / n, 0)} steps, {f(ms / steps * 1000, 2)} microseconds a step, {f(
			contacts / n
		)} contacts; script {f(size / n, 0)} numbers a shot ({sizeMax} at most)`
	)
end
