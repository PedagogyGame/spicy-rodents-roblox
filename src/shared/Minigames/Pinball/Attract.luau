--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.Attract
-- What an idle pinball machine does (checklist PIN-R5 "an idle machine runs an attract mode", PIN-S1 "attract
-- lights and high scores on the backglass"). Two things, both a pure function of a tick count, so every
-- client that looks at the same machine with the same clock sees the same show and nothing has to be sent:
--   * lamps(): the lamp show. The playfield's own lamps (the table's layout) run through four figures in
--     turn: a wave up the table, a sweep across it, a ring spreading from the middle, and a sparkle.
--   * page(): what the display says, turning a page every PAGE_TICKS: the machine's name and FREE PLAY, its
--     best scores, what the game is about (the rule sheet's opening status line), the score scale.
-- A demonstration ball is a third thing and not in here: start a Machine and let Bot (level 1, which needs no
-- practice; or a better one, after asking for Shots.book and Bot.learn before the first frame) hold the
-- buttons; Stream.read gives the frames. The show below costs nothing and needs no machine at all.
-- Pure; Lune-tested (tests/unit/pinball_attract.spec.luau).
-- Interface: FIGURE_TICKS, PAGE_TICKS, PAGES; lamps(table, tick, into) -> into (0 dark, 1 lit);
--   page(table, tick, board?) -> Page { title, lines }

local HighScores = require("./HighScores")
local Layout = require("./Layout")
local Machine = require("./Machine")

local Attract = {}

Attract.FIGURE_TICKS = 1440 -- six seconds a figure
Attract.PAGE_TICKS = 960 -- four seconds a page
Attract.PAGES = 4

export type Page = { title: string, lines: { string } }

-- each table's opening status line, worked out once (a pure function of the table)
local PITCH: { [string]: string } = {}

-- a whole number scrambled from two (for the sparkle): the same everywhere, built from + * % only
local function hash(a: number, b: number): number
	local h = (a * 7919 + b * 104729 + 12345) % 65521
	h = (h * 75 + 74) % 65537
	return h
end

-- lamps(table, tick, into): the attract show at this tick: per lamp 0 dark or 1 lit.
function Attract.lamps(tbl: Machine.Table, tick: number, into: { number }): { number }
	local lamps = tbl.def.lamps
	local figure = (tick // Attract.FIGURE_TICKS) % 4
	local t = tick % Attract.FIGURE_TICKS
	for i, l in lamps do
		local lit
		if figure == 0 then
			-- a wave up the table: a band a fifth of the table deep, once a second
			local at = (t % 240) / 240 * (Layout.LENGTH + 1)
			lit = l.y > at - 1 and l.y <= at
		elseif figure == 1 then
			-- a sweep across and back
			local phase = (t % 360) / 180
			local at = (if phase < 1 then phase else 2 - phase) * Layout.FIELD_X1
			lit = l.x > at - 0.35 and l.x < at + 0.35
		elseif figure == 2 then
			-- a ring spreading from the middle of the playfield
			local dx, dy = l.x - Layout.XC, l.y - Layout.LENGTH / 2
			local d2 = dx * dx + dy * dy
			local r = (t % 288) / 288 * 3
			local inner = r - 0.6
			lit = d2 <= r * r and (inner <= 0 or d2 > inner * inner)
		else
			-- a sparkle: each lamp on for about a third of the eighths of a second, each its own
			lit = hash(i, t // 30) % 3 == 0
		end
		into[i] = if lit then 1 else 0
	end
	for i = #into, #lamps + 1, -1 do
		into[i] = nil
	end
	return into
end

-- page(table, tick, board): what the display shows at this tick.
function Attract.page(tbl: Machine.Table, tick: number, board: HighScores.Board?): Page
	local n = (tick // Attract.PAGE_TICKS) % Attract.PAGES
	if n == 0 then
		return { title = tbl.title, lines = { Machine.TEXT[Machine.SAY.FREE_PLAY], "1 TO 4 PLAYERS" } }
	elseif n == 1 then
		return { title = "BEST SCORES", lines = HighScores.lines(board or HighScores.new(tbl.id)) }
	elseif n == 2 then
		-- what a fresh game asks of the player: the rule sheet's own first line
		local line = PITCH[tbl.id]
		if line == nil then
			local m = Machine.new(tbl, 1, 1)
			line = tbl.sheet.status(m, m.sheets[1])
			PITCH[tbl.id] = line
		end
		return { title = "HOW TO PLAY", lines = { line, "THREE BALLS A GAME" } }
	end
	return { title = tbl.title, lines = { string.upper(tbl.sheet.scoreScale) } }
end

return Attract
