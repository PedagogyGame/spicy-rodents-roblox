--!strict
-- tools/bowling/calibrate.luau: a developer's look at the bowling models (Shared/Minigames/Bowling/BallPath and
-- PinModel) so their constants are tuned from numbers, not guesses. Prints, for a spread of lines into the pins,
-- the strike rate, the mean count, how often a split is left and the commonest leaves; then what each kind of
-- throw (straight, hooked, soft, hard) does at the deck; then full games by each computer player.
-- Usage, from the repo root: lune run tools/bowling/calibrate.luau [rolls per line, default 300]
-- Interface: a script (prints a report); nothing is written.

local process = require("@lune/process")
local BallPath = require("../../src/shared/Minigames/Bowling/BallPath")
local PinModel = require("../../src/shared/Minigames/Bowling/PinModel")

local N = tonumber(process.args[1]) or 300

local function fmt(v: number, places: number?): string
	return string.format(`%.{places or 1}f`, v)
end

local function entryOf(x: number, degrees: number, speed: number): PinModel.Entry
	local a = math.rad(degrees)
	return { x = x, vx = speed * math.sin(a), vd = speed * math.cos(a) }
end

local function leaveName(standing: { boolean }): string
	local out = {}
	for n = 1, 10 do
		if standing[n] then
			table.insert(out, tostring(n))
		end
	end
	return if #out == 0 then "X" else table.concat(out, "-")
end

local function line(label: string, entry: PinModel.Entry, mask: { boolean }?)
	local strikes, total, splits = 0, 0, 0
	local leaves: { [string]: number } = {}
	local started = os.clock()
	for seed = 1, N do
		local r = PinModel.roll(entry, mask or PinModel.fullRack(), seed)
		total += r.down
		if PinModel.count(r.standing) == 0 then
			strikes += 1
		end
		if PinModel.isSplit(r.standing) then
			splits += 1
		end
		local name = leaveName(r.standing)
		leaves[name] = (leaves[name] or 0) + 1
	end
	local ms = (os.clock() - started) / N * 1000
	local names = {}
	for name in leaves do
		table.insert(names, name)
	end
	table.sort(names, function(a, b)
		return leaves[a] > leaves[b]
	end)
	local top = {}
	for i = 1, math.min(4, #names) do
		table.insert(top, `{names[i]} x{leaves[names[i]]}`)
	end
	print(
		`{label}  strike {fmt(strikes / N * 100)}%  mean {fmt(total / N, 2)}  split {fmt(splits / N * 100)}%  {fmt(
			ms,
			2
		)} ms  | {table.concat(top, ", ")}`
	)
end

print(`== lines into a full rack ({N} seeded rolls each; x = ball centre at the deck, degrees + = moving right)`)
for _, speed in { 18, 25, 32 } do
	print(`-- speed {speed}`)
	for _, c in
		{
			{ 0, 0 },
			{ 0.12, 0 },
			{ 0.25, 0 },
			{ 0.25, -3 },
			{ 0.3, -5 },
			{ -0.25, 3 },
			{ 0.4, 0 },
			{ 0.4, -3 },
			{ 0.55, 0 },
			{ 0.75, 0 },
			{ 1.0, 0 },
			{ 1.5, 0 },
			{ 2.2, 0 },
		}
	do
		line(`x {fmt(c[1], 2)} @ {c[2]} deg`, entryOf(c[1], c[2], speed))
	end
end

print("== throws (what the deck sees)")
for _, c in
	{
		{ "straight centre, sweet power", { offset = 0, angle = 0, power = 0.7, spin = 0 } },
		{ "full hook left from the right", { offset = 0.6, angle = 0.01, power = 0.7, spin = -1 } },
		{ "full hook left, soft", { offset = 0.6, angle = 0.01, power = 0.2, spin = -1 } },
		{ "full hook left, hard", { offset = 0.6, angle = 0.01, power = 1, spin = -1 } },
		{ "half hook", { offset = 0.4, angle = 0, power = 0.7, spin = -0.5 } },
		{ "edge and out", { offset = 1, angle = 0.1, power = 0.7, spin = 0 } },
	}
do
	local path = BallPath.trace(c[2] :: any)
	local e = path.entry
	if e then
		print(
			`{c[1]}: enters at x {fmt(e.x, 2)}, {fmt(math.deg(math.atan2(e.vx, e.vd)), 1)} deg, {fmt(
				math.sqrt(e.vx * e.vx + e.vd * e.vd),
				1
			)} st/s, after {fmt(e.t, 2)} s`
		)
	else
		print(`{c[1]}: gutter at d {fmt(path.gutterD or 0, 1)} after {fmt(path.gutterT or 0, 2)} s`)
	end
end

local okRef, Referee = pcall(require, "../../src/shared/Minigames/Bowling/Referee")
if okRef and type(Referee) == "table" and Referee.playGame then
	print("== computer players (30 seeded games each)")
	for _, skill in { "easy", "normal", "sharp" } do
		local sum, lo, hi = 0, 301, -1
		for g = 1, 30 do
			local score = Referee.playGame(skill, g * 31)
			sum += score
			lo = math.min(lo, score)
			hi = math.max(hi, score)
		end
		print(`{skill}: mean {fmt(sum / 30, 1)}  ({lo} .. {hi})`)
	end
end
