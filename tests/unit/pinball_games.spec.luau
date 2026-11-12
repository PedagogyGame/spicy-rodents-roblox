--!strict
-- Minigames/Pinball: whole games, played to the end by the computer players through the buttons a person has,
-- on all three tables and several seeds. Every tick of every game is checked: no ball is ever outside the
-- cabinet or faster than the cap, no score ever falls, every game ends by itself (C3: a computer player can
-- always finish). Then the same games through the player's side and the server's side (PIN-P6: the replay of
-- the input log is the same game, bit for bit, analogue plunger and all), four players at one machine (PIN-R5),
-- a player retired in mid-game (C13: bitten or gone, the score so far kept), and the analogue plunger a stick
-- or a touch strip drives (PIN-C2, PIN-C3).
local Bot = require("@shared/Minigames/Pinball/Bot")
local Layout = require("@shared/Minigames/Pinball/Layout")
local Machine = require("@shared/Minigames/Pinball/Machine")
local Physics = require("@shared/Minigames/Pinball/Physics")
local Replay = require("@shared/Minigames/Pinball/Replay")
local Rules = require("@shared/Minigames/Pinball/Rules")
local Tables = require("@shared/Minigames/Pinball/Tables")
local Test = require("../lib/Test")

local BTN, CUE, PHASE = Machine.BTN, Machine.CUE, Machine.PHASE
local HOUR = 240 * 3600

local function count(out: { number }, cue: number): number
	local n = 0
	for i = 1, #out, 3 do
		if out[i] == cue then
			n += 1
		end
	end
	return n
end

-- a plain-data fingerprint of a machine: every number in it, in a fixed order
local function print(v: any, into: { string })
	if type(v) == "table" then
		local keys = {}
		for k in v do
			table.insert(keys, k)
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		for _, k in keys do
			table.insert(into, tostring(k))
			print(v[k], into)
		end
	else
		table.insert(into, tostring(v))
	end
end
local function fingerprint(m: Machine.State): string
	local parts: { string } = {}
	print(m, parts)
	return table.concat(parts, " ")
end

return function(t: Test.T)
	t.test(
		"every table, every level, three seeds: the game is played to its end and nothing ever leaves the cabinet",
		function()
			local cap2 = (Physics.MAX_SPEED + 1e-6) * (Physics.MAX_SPEED + 1e-6)
			for _, id in Tables.IDS do
				local tbl = Tables.need(id)
				for level = 1, #Bot.LEVELS do
					for seed = 1, 3 do
						local m = Machine.new(tbl, seed, 1)
						local bot = Bot.new(level, seed + 100 * level)
						local out: { number } = {}
						local ticks, score = 0, 0
						local over, balls = 0, 0
						while m.phase ~= PHASE.OVER and ticks < HOUR do
							Machine.step(tbl, m, Bot.step(bot, tbl, m), out)
							ticks += 1
							for _, b in m.phys.balls do
								if
									b.x ~= b.x
									or b.x < -0.01
									or b.x > Layout.WIDTH + 0.01
									or b.y > Layout.LENGTH + 0.01
									or b.vx * b.vx + b.vy * b.vy > cap2
								then
									error(`{id} level {level} seed {seed} tick {ticks}: ball at {b.x}, {b.y}`)
								end
							end
							if m.scores[1] < score then
								error(`{id} level {level} seed {seed}: the score fell`)
							end
							score = m.scores[1]
							over += count(out, CUE.GAME_OVER)
							balls += count(out, CUE.BALL_END)
							table.clear(out)
						end
						local what = `{id} {Bot.NAMES[level]} seed {seed}`
						t.eq(m.phase, PHASE.OVER, `{what}: the game ended ({ticks} ticks)`)
						t.eq(over, 1, `{what}: and was called over exactly once`)
						t.eq(balls, Machine.BALLS + m.stats[1].extraBalls, `{what}: three balls and any extra one`)
						t.truthy(m.stats[1].extraBalls <= 1, "one extra ball at most (PIN-R4)")
						t.truthy(m.scores[1] > 0, `{what}: it scored`)
						t.eq(#m.phys.balls, 0, "no ball is left on a finished table")
						t.truthy(ticks > 240 * 10, `{what}: a game is more than a moment`)
					end
				end
			end
		end
	)

	t.test("the same seed and the same player give the same game, tick for tick; another seed, another game", function()
		for _, id in Tables.IDS do
			local tbl = Tables.need(id)
			local function play(seed: number): (string, number)
				local m = Machine.new(tbl, seed, 1)
				local bot = Bot.new(2, 77)
				local out: { number } = {}
				local ticks = 0
				while m.phase ~= PHASE.OVER and ticks < HOUR do
					Machine.step(tbl, m, Bot.step(bot, tbl, m), out)
					table.clear(out)
					ticks += 1
				end
				return fingerprint(m), ticks
			end
			local a, ta = play(5)
			local b, tb = play(5)
			t.eq(ta, tb)
			t.eq(a, b, `{id}: the same bytes`)
			local c = play(6)
			t.neq(a, c, `{id}: seed 6 is another game`)
		end
	end)

	t.test(
		"PIN-P6: a whole game on the player's machine and the server's replay of its log agree bit for bit",
		function()
			for n, id in Tables.IDS do
				local tbl = Tables.need(id)
				local mine = Replay.new(id, 40 + n, 1)
				local server = Replay.new(id, 40 + n, 1)
				local bot = Bot.new(3, 9 + n)
				local rec = Replay.recorder(mine)
				local segments, numbers, ticks = 0, 0, 0
				while not Replay.over(mine) and ticks < HOUR do
					local seg = Replay.live(mine, rec, Bot.step(bot, tbl, mine.m))
					ticks += 1
					if seg then
						segments += 1
						numbers += #seg
						local ok, why = Replay.feed(server, 1, seg)
						if not ok then
							error(`{id}: segment {segments} refused: {why}`)
						end
					end
				end
				t.truthy(Replay.over(mine), `{id}: the game ended`)
				t.truthy(Replay.over(server), "and so did the replay")
				t.eq(server.tick, mine.tick)
				t.eq(server.m.scores[1], mine.m.scores[1], `{id}: the same score`)
				t.eq(fingerprint(server.m), fingerprint(mine.m), `{id}: the same machine, number for number`)
				t.falsy(server.suspect, `{id}: a played game is never suspect`)
				-- the log is small: a few numbers a second
				t.truthy(numbers / (ticks / 240) < 40, `{id}: {numbers / (ticks / 240)} numbers a second of log`)
			end
		end
	)

	t.test("PIN-R5: four players at one machine alternate ball by ball to the end, each on their own sheet", function()
		local id = "pinball_rodent"
		local tbl = Tables.need(id)
		local m = Machine.new(tbl, 12, 4)
		local bots = { Bot.new(1, 1), Bot.new(2, 2), Bot.new(3, 3), Bot.new(2, 4) }
		local out: { number } = {}
		local order: { number } = {}
		local ticks = 0
		while m.phase ~= PHASE.OVER and ticks < HOUR do
			local up = m.up
			Machine.step(tbl, m, Bot.step(bots[up], tbl, m), out)
			for i = 1, #out, 3 do
				if out[i] == CUE.BALL_START then
					table.insert(order, out[i + 1])
				end
			end
			table.clear(out)
			ticks += 1
		end
		t.eq(m.phase, PHASE.OVER)
		-- the first ball (started by Machine.new) is player 1's; from then on 2, 3, 4, 1, ... save for an extra
		-- ball, which is the same player again
		local last = 1
		for _, up in order do
			t.truthy(up == last or up == last % 4 + 1, `after player {last} came {up}`)
			last = up
		end
		for seat = 1, 4 do
			t.truthy(m.scores[seat] > 0, `player {seat} scored`)
			t.eq(m.stats[seat].balls, Machine.BALLS + m.stats[seat].extraBalls)
		end
		local rules = Rules.forTable(id)
		t.eq(rules.def.seats, 4)
	end)

	t.test(
		"C13: a player retired in mid-game keeps the score so far; their ball is played out dead, their later balls are passed over",
		function()
			local tbl = Tables.need("pinball_acorn")
			local m = Machine.new(tbl, 3, 3)
			local bot = Bot.new(2, 5)
			local out: { number } = {}
			-- play until player 2 has a ball well under way
			local ticks = 0
			while not (m.up == 2 and m.phase == PHASE.PLAY and m.ballTicks > 1200) and ticks < HOUR do
				Machine.step(tbl, m, Bot.step(bot, tbl, m), out)
				ticks += 1
			end
			t.eq(m.up, 2)
			local kept = m.scores[2]
			Machine.retire(tbl, m, 2, out)
			t.truthy(m.gone[2])
			t.truthy(m.forfeit, "the ball in play is played out dead")
			table.clear(out)
			local starts: { number } = {}
			while m.phase ~= PHASE.OVER and ticks < HOUR do
				Machine.step(tbl, m, Bot.step(bot, tbl, m), out)
				for i = 1, #out, 3 do
					if out[i] == CUE.BALL_START then
						table.insert(starts, out[i + 1])
					end
				end
				table.clear(out)
				ticks += 1
			end
			t.eq(m.phase, PHASE.OVER, "the others finished their game")
			t.truthy(m.scores[2] >= kept, "the score so far is kept")
			t.eq(table.find(starts, 2), nil, "no later ball was player 2's")
			t.eq(m.stats[1].balls, Machine.BALLS + m.stats[1].extraBalls)
			t.eq(m.stats[3].balls, Machine.BALLS + m.stats[3].extraBalls)
			-- retiring twice, or a seat that is not there, does nothing; the last player retiring ends the game
			local solo = Machine.new(tbl, 3, 2)
			Machine.retire(tbl, solo, 5, out)
			Machine.retire(tbl, solo, 2, out)
			Machine.retire(tbl, solo, 2, out)
			t.eq(solo.phase, PHASE.PLAY)
			t.eq(solo.up, 1)
			table.clear(out)
			Machine.retire(tbl, solo, 1, out)
			t.eq(solo.phase, PHASE.OVER, "nobody is left")
			t.eq(count(out, CUE.GAME_OVER), 1)
		end
	)

	t.test(
		"C13: through the rules: the server retires a seat, the turn moves on, the result still has every score",
		function()
			local rules = Rules.forTable("pinball_space")
			t.truthy(rules.serverVerbs and rules.serverVerbs.retire, "retire is the server's verb")
			local state = rules.init(2, 8)
			t.eq((rules.turn :: any)(state), 1)
			local ok = rules.input(state, 1, "retire")
			t.truthy(ok)
			t.eq((rules.turn :: any)(state), 2, "player 2's ball is up")
			local view = (rules.view :: any)(state)
			t.truthy(view.players[1].gone)
			t.falsy(view.players[2].gone)
			ok = rules.input(state, 2, "retire")
			t.truthy(ok)
			local result = rules.result(state)
			assert(result, "the game is over when nobody is left")
			t.truthy(result.done)
			t.eq(result.scores[1], 0)
			t.eq(result.scores[2], 0)
			local again, why = rules.input(state, 1, "retire")
			t.falsy(again)
			t.eq(why, "the game is over")
		end
	)

	t.test(
		"PIN-C2, PIN-C3: an analogue plunger (a stick, a touch strip) sends how far it is pulled; the rod follows the hand",
		function()
			local tbl = Tables.need("pinball_acorn")
			local p = tbl.def.plunger
			t.eq(Machine.buttons(BTN.LEFT, 0), BTN.LEFT)
			t.eq(Machine.pullOf(Machine.buttons(BTN.LEFT, 1)), Machine.PULL_LEVELS)
			t.eq(Machine.pullOf(Machine.buttons(0, 0.5)), 16)
			t.eq(Machine.pullOf(Machine.buttons(0, 0.001)), 1, "the lightest touch is still a pull")
			t.truthy(Machine.buttons(BTN.LEFT + BTN.RIGHT, 1) <= Machine.BUTTONS_MAX)
			-- pulled right back at once: the rod takes ROD_TICKS to get there, not the keyboard's whole second
			local function launchAt(pull: number, holdTicks: number): (number, number)
				local m = Machine.new(tbl, 1, 1)
				local out: { number } = {}
				for _ = 1, holdTicks do
					Machine.step(tbl, m, Machine.buttons(0, pull), out)
				end
				local rod = m.pull / p.pullTicks
				Machine.step(tbl, m, 0, out)
				local strength = -1
				for i = 1, #out, 3 do
					if out[i] == CUE.PLUNGE then
						strength = out[i + 2]
					end
				end
				return strength, rod
			end
			local full = launchAt(1, Machine.ROD_TICKS + 2)
			t.near(full, 1, 1e-9, "a full pull")
			local half, rod = launchAt(0.5, Machine.ROD_TICKS + 2)
			t.near(half, 16 / 31, 1e-9, "half a pull is half a launch")
			t.near(rod, half, 1e-9, "the launch is the rod's place when the hand lets go")
			local quick = launchAt(1, Machine.ROD_TICKS // 2)
			t.truthy(quick > 0.4 and quick < 0.6, `let go half way through the rod's travel: {quick}`)
			-- the hand can ease the rod forward again before letting go: a soft plunge
			local m = Machine.new(tbl, 1, 1)
			local out: { number } = {}
			for _ = 1, 60 do
				Machine.step(tbl, m, Machine.buttons(0, 1), out)
			end
			for _ = 1, 60 do
				Machine.step(tbl, m, Machine.buttons(0, 0.2), out)
			end
			t.near(m.pull / p.pullTicks, 6 / 31, 1e-9, "eased forward")
			table.clear(out)
			Machine.step(tbl, m, 0, out)
			t.eq(count(out, CUE.PLUNGE), 1)
			t.truthy(m.phys.balls[1].vy > p.vMin and m.phys.balls[1].vy < (p.vMin + p.vMax) / 2, "a soft launch")
			-- and the flippers work while the plunger is held this way
			local m2 = Machine.new(tbl, 1, 1)
			Machine.step(tbl, m2, Machine.buttons(BTN.LEFT, 0.7), out)
			t.truthy(m2.phys.fa[1] > tbl.c.frest[1], "the left flipper moved")
			-- the keyboard's plunger is unchanged: hold to pull at a steady rate
			local m3 = Machine.new(tbl, 1, 1)
			for _ = 1, p.pullTicks // 2 do
				Machine.step(tbl, m3, BTN.PLUNGE, out)
			end
			t.near(m3.pull / p.pullTicks, 0.5, 0.01)
		end
	)

	t.test("PIN-P6: a log with an analogue plunger in it replays to the same game", function()
		local id = "pinball_space"
		local mine = Replay.new(id, 4, 1)
		local server = Replay.new(id, 4, 1)
		local rec = Replay.recorder(mine)
		local function live(buttons: number, ticks: number)
			for _ = 1, ticks do
				local seg = Replay.live(mine, rec, buttons)
				if seg then
					local ok, why = Replay.feed(server, 1, seg)
					t.truthy(ok, why)
				end
			end
		end
		-- a stick pulled down in steps, held, eased and let go; then the flippers
		for level = 1, 31 do
			live(level * Machine.PULL_UNIT, 2)
		end
		live(31 * Machine.PULL_UNIT, 30)
		live(20 * Machine.PULL_UNIT, 20)
		live(0, 400)
		live(BTN.LEFT, 60)
		live(BTN.RIGHT, 60)
		live(0, 47)
		-- flush what is left of the last segment by playing on to a segment boundary
		while server.tick < mine.tick do
			live(0, 1)
		end
		t.eq(server.tick, mine.tick)
		t.eq(fingerprint(server.m), fingerprint(mine.m))
		t.truthy(mine.m.launched, "the ball was plunged")
	end)

	t.test("the result of a game: every score, the winner, and the statistics the end card shows", function()
		local id = "pinball_acorn"
		local tbl = Tables.need(id)
		local rules = Rules.forTable(id)
		local state = rules.init(2, 21)
		local r = state :: Replay.State
		local bots = { Bot.new(3, 1), Bot.new(1, 2) }
		local ticks = 0
		t.eq(rules.result(state), nil, "no result while the game is on")
		while not Replay.over(r) and ticks < HOUR do
			local up = r.m.up
			local rec = Replay.recorder(r)
			-- (the server's own state is stepped here as the player's machine would step its copy)
			Replay.live(r, rec, Bot.step(bots[up], tbl, r.m))
			ticks += 1
		end
		local result = rules.result(state)
		assert(result, "a result")
		t.truthy(result.done)
		t.eq(result.scores[1], r.m.scores[1])
		t.eq(result.scores[2], r.m.scores[2])
		if result.scores[1] ~= result.scores[2] then
			t.eq(result.winner, if result.scores[1] > result.scores[2] then 1 else 2)
		end
		for seat = 1, 2 do
			local stats = result.stats[seat]
			for _, key in { "bumpers", "ramps", "targets", "bestBonus", "balls", "extraBalls" } do
				t.isType(stats[key], "number", `player {seat} has {key}`)
			end
			t.truthy(stats.balls >= Machine.BALLS)
		end
		t.falsy(result.suspect)
	end)
end
