--!strict
-- tools/jenga/calibrate.luau: a developer's look at the giant Jenga model (Shared/Minigames/Jenga) so its
-- constants are tuned from numbers, not guesses. Prints: how loose, snug and tight a fresh tower's blocks are;
-- what drawing each kind of block does to a part-played tower at a crawl, at an ordinary pace and at a yank,
-- straight and wandering, dragged and pushed; whole solo games by each computer player (moves before it falls,
-- how tall it got, how long a game lasts); who loses when they play each other; and what it costs to run.
-- Usage, from the repo root: lune run tools/jenga/calibrate.luau [games per player, default 30]
-- Interface: a script (prints a report); nothing is written.

local process = require("@lune/process")
local Bots = require("../../src/shared/Minigames/Jenga/Bots")
local Fall = require("../../src/shared/Minigames/Jenga/Fall")
local Physics = require("../../src/shared/Minigames/Jenga/Physics")
local Rules = require("../../src/shared/Minigames/Jenga/Rules")
local Stability = require("../../src/shared/Minigames/Jenga/Stability")
local Tower = require("../../src/shared/Minigames/Jenga/Tower")

local N = tonumber(process.args[1]) or 30

local function fmt(v: number, places: number?): string
	return string.format(`%.{places or 1}f`, v)
end

-- 1. a fresh tower ------------------------------------------------------------------------------------------------
print(`== fresh towers ({N} seeds): the 51 blocks that may be taken`)
do
	local loose, snug, tight, stuck = 0, 0, 0, 0
	local margin, lean = 0, 0
	for seed = 1, N do
		local tw = Tower.new(seed)
		for level = 1, 17 do
			for slot = 1, 3 do
				local f = Physics.feel(tw, level, slot) :: Physics.Feel
				if f.kind == "loose" then
					loose += 1
				elseif f.kind == "snug" then
					snug += 1
				else
					tight += 1
				end
				if f.stuck then
					stuck += 1
				end
			end
		end
		margin += Stability.margin(tw)
		local p = Stability.poses(tw)
		local o = (54 - 1) * 6
		lean += math.sqrt(p[o + 5] ^ 2 + p[o + 6] ^ 2)
	end
	print(
		`loose {fmt(loose / N)}  snug {fmt(snug / N)}  tight {fmt(tight / N)} (of which too tight to start {fmt(
			stuck / N
		)})  smallest margin {fmt(margin / N, 3)} st  lean at the top {fmt(math.deg(lean / N), 2)} deg`
	)
end

-- 2. drawing a block ----------------------------------------------------------------------------------------------
-- A tower part-way through a careful game: `moves` loose blocks drawn slowly and set down square.
local function played(seed: number, moves: number): Tower.Tower
	local tw = Tower.new(seed)
	for _ = 1, moves do
		local an = Stability.ensure(tw)
		local best, bestScore = nil :: { number }?, math.huge
		for level = 1, Tower.highestComplete(tw) - 1 do
			for slot = 1, 3 do
				local b = Tower.blockAt(tw, level, slot)
				if b then
					local m = Bots.judge(tw, level, slot)
					local score = an.load[b.id] / 37.3 + (if m <= 0 then 1000 else 0.6 / (m + 0.03))
					if score < bestScore then
						best, bestScore = { level, slot }, score
					end
				end
			end
		end
		if not best then
			break
		end
		Physics.grab(tw, best[1], best[2], best[2] == 2)
		local goal, guard = 0, 0
		while tw.held ~= 0 and not tw.fallen and guard < 3600 do
			guard += 1
			goal += 0.8 * Physics.DT
			Physics.drag(tw, goal, 0)
			Physics.step(tw)
		end
		if tw.fallen or tw.inHand == 0 then
			break
		end
		local _, free = Tower.building(tw)
		Physics.place(tw, free[1], 0, 0, 0)
		Physics.settle(tw, 5)
	end
	Tower.drain(tw)
	return tw
end

type Draw = { fell: boolean, peak: number, seconds: number, creaks: number, out: boolean }

local function drawBlock(
	tw: Tower.Tower,
	level: number,
	slot: number,
	speed: number,
	wobble: number,
	push: boolean
): Draw
	Physics.grab(tw, level, slot, push)
	local goal, t, peak, creaks = 0, 0, 0, 0
	while tw.held ~= 0 and not tw.fallen and t < 40 do
		goal += speed * Physics.DT
		local b = tw.blocks[tw.held]
		goal = math.min(goal, b.along + 0.4)
		Physics.drag(tw, goal, wobble * math.sin(t * 7))
		Physics.step(tw)
		t += Physics.DT
		peak = math.max(peak, Physics.danger(tw))
	end
	local out = tw.inHand ~= 0
	if not tw.fallen then
		local steps = 0
		while steps < 300 and not tw.fallen do
			Physics.step(tw)
			steps += 1
			peak = math.max(peak, Physics.danger(tw))
		end
	end
	for _, e in Tower.drain(tw) do
		if e.kind == "creak" then
			creaks += 1
		end
	end
	return { fell = tw.fallen ~= nil, peak = peak, seconds = t, creaks = creaks, out = out }
end

print(`== drawing one block from a tower 14 careful moves in ({N} towers; the loosest and the tightest legal block)`)
for _, kind in { "loosest", "snug", "middling", "tightest" } do
	for _, c in
		{
			{ "crawl 0.4 st/s, straight, dragged", 0.4, 0, false },
			{ "steady 1.2 st/s, straight, dragged", 1.2, 0, false },
			{ "steady 1.2 st/s, wandering 0.15, dragged", 1.2, 0.15, false },
			{ "steady 1.2 st/s, wandering 0.15, pushed", 1.2, 0.15, true },
			{ "yank 6 st/s, straight, dragged", 6, 0, false },
			{ "yank 6 st/s, wandering 0.15, dragged", 6, 0.15, false },
		}
	do
		local fell, peak, secs, creaks, load, count = 0, 0, 0, 0, 0, 0
		for seed = 1, N do
			local tw = played(seed, 14)
			if not tw.fallen then
				local an = Stability.ensure(tw)
				local list = {}
				for level = 1, Tower.highestComplete(tw) - 1 do
					for slot = 1, 3 do
						local b = Tower.blockAt(tw, level, slot)
						if b and Bots.judge(tw, level, slot) > 0 then
							table.insert(list, { level, slot, an.load[b.id] / 37.3 })
						end
					end
				end
				table.sort(list, function(a, b)
					return a[3] < b[3]
				end)
				local pick = list[#list]
				if kind == "loosest" then
					pick = list[1]
				elseif kind == "snug" then
					-- the first block that carries between two and six blocks' weight
					pick = nil
					for _, c2 in list do
						if c2[3] >= 2 and c2[3] <= 6 then
							pick = c2
							break
						end
					end
				elseif kind == "middling" then
					pick = list[math.ceil(#list * 0.7)]
				end
				if pick then
					local r = drawBlock(tw, pick[1], pick[2], c[2] :: number, c[3] :: number, c[4] :: boolean)
					count += 1
					load += pick[3]
					fell += if r.fell then 1 else 0
					peak += r.peak
					secs += r.seconds
					creaks += r.creaks
				end
			end
		end
		count = math.max(count, 1)
		print(
			`{kind} (load {fmt(load / count)} blocks), {c[1]}: fell {fmt(fell / count * 100, 0)}%  danger {fmt(
				peak / count,
				2
			)}  took {fmt(secs / count)} s  creaks {fmt(creaks / count)}`
		)
	end
end

-- 3. whole games ---------------------------------------------------------------------------------------------------
type Game = { moves: number, levels: number, seconds: number, loser: number?, why: string, fallSeconds: number }

local function game(skills: { string }, seed: number): Game
	local state = Rules.init(#skills, seed)
	for seat, skill in skills do
		Rules.setComputer(state, seat, skill)
	end
	local guard = 0
	while not state.done and guard < 60 * 3600 do
		guard += 1
		Rules.advance(state, 1 / 60)
	end
	local res = Rules.result(state) :: { [string]: any }
	local f = state.tower.fallen
	return {
		moves = res.moved,
		levels = res.tallest,
		seconds = state.time,
		loser = res.loser,
		why = if f then f.why else "none",
		fallSeconds = if state.fall then state.fall.tEnd else 0,
	}
end

print(`== solo games by each computer player ({N} seeded games each)`)
for _, skill in { "easy", "normal", "sharp", "idle" } do
	local moves, lo, hi, levels, secs, top = 0, math.huge, 0, 0, 0, 0
	local why: { [string]: number } = {}
	for g = 1, N do
		local r = game({ skill }, g * 31)
		moves += r.moves
		lo = math.min(lo, r.moves)
		hi = math.max(hi, r.moves)
		levels += r.levels
		top = math.max(top, r.levels)
		secs += r.seconds
		why[r.why] = (why[r.why] or 0) + 1
	end
	local whys = {}
	for k, v in why do
		table.insert(whys, `{k} x{v}`)
	end
	table.sort(whys)
	print(
		`{skill}: moves {fmt(moves / N)} ({lo} .. {hi})  levels {fmt(levels / N)} (best {top})  a game lasts {fmt(
			secs / N / 60
		)} min, {fmt(secs / math.max(moves, 1))} s a move  | fell by {table.concat(whys, ", ")}`
	)
end

print(`== who knocks it over ({N} seeded games each pairing; the seat order is swapped every other game)`)
for _, pair in { { "easy", "sharp" }, { "easy", "normal" }, { "normal", "sharp" } } do
	local lost = { 0, 0 }
	local moves = 0
	for g = 1, N do
		local swap = g % 2 == 0
		local r = game(if swap then { pair[2], pair[1] } else { pair[1], pair[2] }, g * 57 + 3)
		moves += r.moves
		if r.loser then
			local who = if swap then 3 - r.loser else r.loser
			lost[who] += 1
		end
	end
	print(
		`{pair[1]} v {pair[2]}: {pair[1]} knocks it over {fmt(lost[1] / N * 100, 0)}%, {pair[2]} {fmt(
			lost[2] / N * 100,
			0
		)}%  ({fmt(moves / N)} moves a game)`
	)
end

-- 4. cost ----------------------------------------------------------------------------------------------------------
print("== cost")
do
	local tw = Tower.new(3)
	local started = os.clock()
	for _ = 1, 200000 do
		Physics.step(tw)
	end
	print(`a step with nothing moving: {fmt((os.clock() - started) / 200000 * 1e6, 2)} us`)

	tw = played(3, 14)
	local list = {}
	for level = 1, Tower.highestComplete(tw) - 1 do
		for slot = 1, 3 do
			if Tower.blockAt(tw, level, slot) then
				table.insert(list, { level, slot })
			end
		end
	end
	local steps, total = 0, 0
	for _, pick in list do
		local c = Tower.clone(tw)
		Physics.grab(c, pick[1], pick[2], false)
		local goal = 0
		local t0 = os.clock()
		local k = 0
		while c.held ~= 0 and not c.fallen and k < 600 do
			k += 1
			goal += 1.2 * Physics.DT
			Physics.drag(c, goal, 0.05)
			Physics.step(c)
		end
		total += os.clock() - t0
		steps += k
	end
	print(
		`a step while a block is being drawn and the tower rocks: {fmt(total / steps * 1e6, 1)} us ({steps} steps; the game needs {Physics.RATE} a second)`
	)

	started = os.clock()
	for _ = 1, 2000 do
		Stability.analyse(tw)
	end
	print(`one stability judgement of the whole tower: {fmt((os.clock() - started) / 2000 * 1e6, 1)} us`)

	local buildMs, size, secs, count = 0, 0, 0, 0
	for seed = 1, 10 do
		local state = Rules.init(1, seed)
		Rules.setComputer(state, 1, "easy")
		local guard = 0
		while not state.done and guard < 60 * 3600 do
			guard += 1
			Rules.advance(state, 1 / 60)
		end
		if state.tower.fallen then
			local t0 = os.clock()
			local sc = Fall.build(state.tower, seed)
			buildMs += (os.clock() - t0) * 1000
			size += Fall.size(sc)
			secs += sc.tEnd
			count += 1
		end
	end
	count = math.max(count, 1)
	print(
		`a collapse script: {fmt(buildMs / count, 1)} ms to build, {fmt(size / count, 0)} numbers, plays for {fmt(
			secs / count
		)} s`
	)
end
