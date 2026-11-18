--!strict
-- tools/games/pinball/inplay.luau: the review scene with a game in play on each of the three pinball machines,
-- for the offline renders (tools/review/render.py). The baked machines stand at rest (one ball on the plunger,
-- the flippers down, every lamp in its own colour); this plays each table with the model's own computer player
-- (Pinball/Bot) and poses the machine from the model's frame (Pinball/Stream) at a moment chosen from that game:
-- "top" (a ball up among the bumpers and top lanes) or "low" (a ball coming down to a flipper held up). The
-- balls, the flippers, the drop targets and the lamps (lit or dark, as the client draws them: an unlit lamp at
-- 30 % of its colour, a lit one Neon) are moved in the scene exactly as Client/Minigames/Pinball/Cabinet moves
-- the parts; nothing else is touched. Positions come from Shared/Minigames/Pinball/Cabinet.point (the bake's own).
-- Run (repo root, after tools/bake/attractions.luau and tools/review/export.luau):
--   lune run tools/games/pinball/inplay.luau [top|low] [in, default build/review/scene.json]
--     [out, default build/review/pinball_<moment>.json]
--   python -I tools/review/render.py --scene build/review/pinball_top.json \
--     --views build/review/pinball_views.json --out build/review/pinball_top
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")
local Bot = require("../../../src/shared/Minigames/Pinball/Bot")
local Cabinet = require("../../../src/shared/Minigames/Pinball/Cabinet")
local Layout = require("../../../src/shared/Minigames/Pinball/Layout")
local Machine = require("../../../src/shared/Minigames/Pinball/Machine")
local Stream = require("../../../src/shared/Minigames/Pinball/Stream")
local Tables = require("../../../src/shared/Minigames/Pinball/Tables")

local moment = process.args[1] or "top"
assert(moment == "top" or moment == "low", "the moment is top or low")
local input = process.args[2] or "build/review/scene.json"
local out = process.args[3] or `build/review/pinball_{moment}.json`

local doc = serde.decode("json", fs.readFile("data/attractions.json"))
local place: AlleyLayout.Place? = nil
for _, a in doc.attractions do
	if a.id == "bowling_alley" then
		place = { x = a.place.x, z = a.place.z, floorY = a.place.floorY, yaw = a.place.yaw }
	end
end
assert(place, "the bowling alley is not in data/attractions.json")
local scene = serde.decode("json", fs.readFile(input))

local function world(index: number, x: number, y: number, h: number): { number }
	local X, Y, D = Cabinet.point(index, x, y, h)
	local wx, wy, wz = AlleyLayout.toWorld(place :: any, X, Y, D)
	return { wx, wy, wz }
end
local function sub(a: { number }, b: { number }): { number }
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end
local function r4(n: number): number
	return math.floor(n * 1e4 + 0.5) / 1e4
end
-- the turn by `angle` about the unit axis n (right-handed), row-major 3x3
local function about(n: { number }, angle: number): { number }
	local c, s = math.cos(angle), math.sin(angle)
	local x, y, z = n[1], n[2], n[3]
	local t = 1 - c
	return {
		t * x * x + c,
		t * x * y - s * z,
		t * x * z + s * y,
		t * x * y + s * z,
		t * y * y + c,
		t * y * z - s * x,
		t * x * z - s * y,
		t * y * z + s * x,
		t * z * z + c,
	}
end
local function mul(a: { number }, b: { number }): { number }
	local o = {}
	for r = 0, 2 do
		for col = 0, 2 do
			o[r * 3 + col + 1] = a[r * 3 + 1] * b[col + 1]
				+ a[r * 3 + 2] * b[3 + col + 1]
				+ a[r * 3 + 3] * b[6 + col + 1]
		end
	end
	return o
end
local function apply(m: { number }, v: { number }): { number }
	return {
		m[1] * v[1] + m[2] * v[2] + m[3] * v[3],
		m[4] * v[1] + m[5] * v[2] + m[6] * v[3],
		m[7] * v[1] + m[8] * v[2] + m[9] * v[3],
	}
end

-- A game on the table, played by the computer until the moment wanted: the frame then.
local function play(tbl: any, seed: number): any
	local m = Machine.new(tbl, seed, 1)
	local bot = Bot.new(3, seed)
	local cues = {}
	local top = Layout.LENGTH * 0.66
	local c = tbl.c
	for _ = 1, 240 * 240 do
		Machine.step(tbl, m, Bot.step(bot, tbl, m), cues)
		table.clear(cues)
		if m.phase == Machine.PHASE.OVER then
			break
		end
		local f = Stream.read(tbl, m)
		local lane = f.nBalls >= 1 and math.abs(f.balls[1] - tbl.def.plunger.x) < 0.2 -- (still in the shooter lane)
		if f.nBalls >= 1 and m.phys.tick > 240 * 12 and f.scores[1] > 0 and not lane then
			local x, y = f.balls[1], f.balls[2]
			if moment == "top" and y > top and y < Layout.LENGTH - 0.4 then
				return f
			end
			if moment == "low" then
				for i = 1, c.nFlip do
					local stroke = c.fup[i] - c.frest[i]
					local raised = (f.flippers[i] - c.frest[i]) / stroke > 0.9
					local near = (x - c.fpx[i]) ^ 2 + (y - c.fpy[i]) ^ 2 < (c.flen[i] * 1.1) ^ 2
					if raised and near and y > c.fpy[i] + 0.05 then
						return f
					end
				end
			end
		end
	end
	error(`no {moment} moment in a game on {tbl.title}`)
end

local parts = scene.parts
local byPath: { [string]: any } = {}
for _, p in parts do
	byPath[p.p] = p
end
local prefix = "Attractions.BowlingAlley.GamesRoom."
local N = Cabinet.NAMES

for index, p in AlleyLayout.PINBALLS do
	local tbl = Tables.need(Tables.forVariant(p.theme) :: string)
	local f = play(tbl, 20 + index)
	local c = tbl.c
	local root = prefix .. Cabinet.model(index) .. "."
	local normal = sub(world(index, 0, 0, 1), world(index, 0, 0, 0))
	-- the balls (the baked one moved; any more in play are copies of it)
	local ball = byPath[root .. N.ball .. "1"]
	assert(ball, `{root}Ball1 is not in the scene`)
	for i = 1, f.nBalls do
		local k = (i - 1) * 3
		local b = if i == 1 then ball else table.clone(ball)
		if i > 1 then
			b.p = `{root}{N.ball}{i}`
			table.insert(parts, b)
		end
		local w = world(index, f.balls[k + 1], f.balls[k + 2], f.balls[k + 3] + Layout.BALL_R)
		b.pos = { r4(w[1]), r4(w[2]), r4(w[3]) }
	end
	-- the flippers: every part of Flipper<i> turned about the pin, along the playfield's normal
	for i = 1, c.nFlip do
		local rest, now = c.frest[i], f.flippers[i]
		local turn = Cabinet.turnOf(c.fmir[i] * math.cos(now), math.sin(now))
			- Cabinet.turnOf(c.fmir[i] * math.cos(rest), math.sin(rest))
		local R = about(normal, turn)
		local pivot = world(index, c.fpx[i], c.fpy[i], 0)
		local head = `{root}{N.flipper}{i}.`
		for path, q in byPath do
			if string.sub(path, 1, #head) == head then
				local d = apply(R, sub(q.pos, pivot))
				q.pos = { r4(pivot[1] + d[1]), r4(pivot[2] + d[2]), r4(pivot[3] + d[3]) }
				local rot = mul(R, q.rot)
				for j = 1, 9 do
					rot[j] = r4(rot[j])
				end
				q.rot = rot
			end
		end
		-- (checked: the tip is where the model has it)
		local tip = byPath[head .. "Tip"]
		if tip then
			local want =
				world(index, c.fpx[i] + c.fmir[i] * math.cos(now) * c.flen[i], c.fpy[i] + math.sin(now) * c.flen[i], 0)
			local d = sub(tip.pos, want)
			local flat = d[1] * d[1]
				+ d[2] * d[2]
				+ d[3] * d[3]
				- (d[1] * normal[1] + d[2] * normal[2] + d[3] * normal[3]) ^ 2
			assert(flat < 1e-4, `flipper {i} of machine {index} is not where the model has it`)
		end
	end
	-- the drop targets that are down
	for i = 1, #tbl.def.targets do
		local q = byPath[`{root}{N.drop}{i}`]
		if q and f.drops[i] then
			for j = 1, 3 do
				q.pos[j] = r4(q.pos[j] - normal[j] * Cabinet.DROP_SINK)
			end
		end
	end
	-- the lamps: lit ones glow, the others dark
	local lit = 0
	for i = 1, #tbl.def.lamps do
		local q = byPath[`{root}{N.lamp}{i}`]
		if q then
			local v = f.lamps[i] or 0
			if v == 1 or v == 2 then
				q.m = "Neon"
				lit += 1
			else
				q.c = { math.floor(q.c[1] * 0.3), math.floor(q.c[2] * 0.3), math.floor(q.c[3] * 0.3) }
			end
		end
	end
	print(
		`pinball {index} ({tbl.title}): {moment} at tick {f.tick}, ball {f.ball}, score {f.scores[1]}, {f.nBalls} ball(s), {lit} lamps lit`
	)
end

fs.writeFile(out, serde.encode("json", scene))
print(`-> {out}`)
