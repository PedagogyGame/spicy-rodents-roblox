--!strict
-- Minigames/Pinball/Attract and HighScores: what an idle machine shows (PIN-R5 "an idle machine runs an attract
-- mode", PIN-S1 "attract lights and high scores on the backglass") and the per-machine table of best scores
-- for this server (PIN-R4: a place on the board is the whole reward; nothing is won). Also a demonstration
-- ball: a machine played by the NOVICE or the REGULAR computer player needs no practice first, so it can
-- start on the frame it is asked for.
local Attract = require("@shared/Minigames/Pinball/Attract")
local Bot = require("@shared/Minigames/Pinball/Bot")
local HighScores = require("@shared/Minigames/Pinball/HighScores")
local Machine = require("@shared/Minigames/Pinball/Machine")
local Stream = require("@shared/Minigames/Pinball/Stream")
local Tables = require("@shared/Minigames/Pinball/Tables")
local Test = require("../lib/Test")

return function(t: Test.T)
	t.test("PIN-S1: the attract lamp show is a pure function of the tick: the same on every screen", function()
		for _, id in Tables.IDS do
			local tbl = Tables.need(id)
			local n = #tbl.def.lamps
			local a, b = {}, {}
			for _, tick in { 0, 37, 1440, 2000, 3111, 4321, 5760, 99999 } do
				Attract.lamps(tbl, tick, a)
				Attract.lamps(tbl, tick, b)
				t.deepEq(a, b)
				t.eq(#a, n, "one state for every lamp on the playfield")
				for i = 1, n do
					t.truthy(a[i] == 0 or a[i] == 1)
				end
			end
		end
	end)

	t.test(
		"PIN-S1: the show is alive: four figures in turn, every lamp lit some of the time and dark some of it",
		function()
			for _, id in Tables.IDS do
				local tbl = Tables.need(id)
				local n = #tbl.def.lamps
				local lamps: { number } = {}
				local lit: { number } = table.create(n, 0)
				local frames = 0
				local perFigure: { number } = { 0, 0, 0, 0 }
				for tick = 0, Attract.FIGURE_TICKS * 4 - 1, 4 do
					Attract.lamps(tbl, tick, lamps)
					frames += 1
					local figure = tick // Attract.FIGURE_TICKS + 1
					for i = 1, n do
						lit[i] += lamps[i]
						perFigure[figure] += lamps[i]
					end
				end
				for i = 1, n do
					local share = lit[i] / frames
					t.truthy(share > 0.03, `{id}: lamp {tbl.def.lamps[i].id} is lit some of the time ({share})`)
					t.truthy(share < 0.8, `{id}: and dark some of it ({share})`)
				end
				for figure = 1, 4 do
					t.truthy(perFigure[figure] > 0, `{id}: figure {figure} lights lamps`)
				end
			end
		end
	)

	t.test(
		"PIN-S1, PIN-R4: the display turns its pages: the name and FREE PLAY, the best scores, how to play",
		function()
			for _, id in Tables.IDS do
				local tbl = Tables.need(id)
				local board = HighScores.new(id)
				local first = Attract.page(tbl, 0, board)
				t.eq(first.title, tbl.title)
				t.eq(first.lines[1], "FREE PLAY")
				local scores = Attract.page(tbl, Attract.PAGE_TICKS, board)
				t.eq(scores.title, "BEST SCORES")
				t.eq(#scores.lines, HighScores.SIZE)
				local how = Attract.page(tbl, Attract.PAGE_TICKS * 2, board)
				t.truthy(#how.lines[1] > 10, "the rule sheet's own opening line")
				local scale = Attract.page(tbl, Attract.PAGE_TICKS * 3, board)
				t.truthy(#scale.lines[1] > 10)
				t.deepEq(Attract.page(tbl, Attract.PAGE_TICKS * Attract.PAGES, board), first, "and round again")
				-- nothing on any page speaks of money
				for page = 0, Attract.PAGES - 1 do
					local p = Attract.page(tbl, Attract.PAGE_TICKS * page, board)
					for _, line in p.lines do
						for _, word in { "CREDIT", "COIN", "REPLAY", "MATCH", "PRIZE", "WIN A" } do
							t.eq(string.find(line, word, 1, true), nil, `{id}: "{line}"`)
						end
					end
				end
			end
		end
	)

	t.test("a demonstration ball needs no practice: the NOVICE starts at once, and a frame can be drawn", function()
		-- (the NOVICE uses neither the shot book nor the plunger lesson, so nothing is measured before its
		-- first frame; the REGULAR and the WIZARD aim by the book, a fifth of a second of work, once)
		local tbl = Tables.need("pinball_space")
		t.falsy(Bot.LEVELS[1].learnt, "no lesson")
		t.eq(Bot.LEVELS[1].book, 0, "no shot book")
		local m = Machine.new(tbl, 3, 1)
		local bot = Bot.new(1, 3)
		local out: { number } = {}
		local started = os.clock()
		local launched = false
		for _ = 1, 240 * 20 do
			Machine.step(tbl, m, Bot.step(bot, tbl, m), out)
			launched = launched or m.launched
		end
		t.truthy(os.clock() - started < 0.5, "twenty seconds of demonstration in well under half a second")
		local frame = Stream.read(tbl, m)
		t.eq(#frame.lamps, #tbl.def.lamps)
		t.truthy(launched, "it plunged by itself")
	end)

	t.test("the best scores: five places, best first, the house's own until somebody beats them", function()
		for _, id in Tables.IDS do
			local board = HighScores.new(id)
			t.eq(board.id, id)
			t.eq(#board.entries, HighScores.SIZE)
			for i = 2, #board.entries do
				t.truthy(board.entries[i].score < board.entries[i - 1].score, "best first")
				t.truthy(board.entries[i].house)
			end
		end
		local board = HighScores.new("pinball_acorn")
		local low = board.entries[HighScores.SIZE].score
		local top = board.entries[1].score
		t.eq(HighScores.place(board, low), nil, "equalling the last place does not take it")
		t.eq(HighScores.place(board, 0), nil)
		t.eq(HighScores.place(board, low + 10), HighScores.SIZE)
		t.eq(HighScores.add(board, "Ada", low + 10), HighScores.SIZE)
		t.eq(#board.entries, HighScores.SIZE, "the board stays five long")
		t.eq(board.entries[HighScores.SIZE].name, "Ada")
		t.falsy(board.entries[HighScores.SIZE].house)
		t.eq(HighScores.add(board, "Brook", top + 1), 1, "a new best")
		t.eq(board.entries[1].name, "Brook")
		t.eq(board.entries[2].score, top)
		t.eq(HighScores.add(board, "Cy", top + 1), 2, "the first to make a score keeps the place above")
		t.eq(HighScores.add(board, "Dee", 1), nil, "too low: not entered")
		-- a game the replay did not call fair (suspect, or out of pace) takes no place, whatever its score
		local before = #board.entries
		t.eq(HighScores.add(board, "Mallory", top * 10, false), nil, "not a fair game: not entered")
		t.eq(#board.entries, before)
		t.eq(board.entries[1].name, "Brook")
		for i = 2, #board.entries do
			t.truthy(board.entries[i].score <= board.entries[i - 1].score)
		end
		-- a long name is cut to fit the display
		local at = HighScores.add(board, string.rep("x", 60), top * 2)
		t.eq(at, 1)
		t.eq(#board.entries[1].name, HighScores.NAME_MAX)
	end)

	t.test("the board reads as the backglass shows it, and each machine's house scores sit on its own scale", function()
		t.eq(HighScores.commas(0), "0")
		t.eq(HighScores.commas(999), "999")
		t.eq(HighScores.commas(1000), "1,000")
		t.eq(HighScores.commas(12345678), "12,345,678")
		local board = HighScores.new("pinball_rodent")
		local lines = HighScores.lines(board)
		t.eq(lines[1], "1. THE RODENT  900,000")
		t.eq(#lines, HighScores.SIZE)
		-- the three machines' boards are far apart, as their scores are (PIN-R6)
		local a = HighScores.new("pinball_acorn").entries[1].score
		local r = HighScores.new("pinball_rodent").entries[1].score
		local s = HighScores.new("pinball_space").entries[1].score
		t.truthy(r >= a * 10 and s >= r * 10)
		-- an unknown machine has an empty board that fills from the top
		local fresh = HighScores.new("pinball_none")
		t.eq(#fresh.entries, 0)
		t.eq(HighScores.add(fresh, "Eve", 10), 1)
	end)
end
