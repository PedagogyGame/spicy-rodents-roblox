--!strict
-- ReplicatedStorage.Shared.Minigames.Labyrinth.Clipboard
-- "Labyrinth: best times today": the clipboard on the waiting-room wall. The labyrinth is played alone, so this
-- is how players meet: the five best times on each board, one line a player (their best), the fastest first;
-- equal times go to fewer marbles dropped, then to whoever set it first. Only finished, fair runs go on it
-- (Rules marks a run that did not keep pace with the server's clock as not fair). The best run on each board
-- keeps its input log, so the day's record can be shown as a faint ghost marble (Stream replays it).
-- The server owns one Clipboard for the day and wipes it at the day's turn; lifetime bests are the profile's.
-- Pure; Lune-tested (tests/unit/labyrinth_rules.spec.luau).
-- Interface: PLACES; new() -> Clipboard; add(clipboard, boardId, entry) -> place? (1..PLACES when the run made
--   the board; nil when it did not); list(clipboard, boardId) -> { Entry }; ghost(clipboard, boardId) ->
--   { hold = number, log = string }?; lines(clipboard, boardId, clockText) -> { string } (what the board says)

local Clipboard = {}

Clipboard.PLACES = 5

export type Entry = {
	name: string,
	tenths: number,
	drops: number,
	hold: number?, -- with log: enough to replay the run as a ghost
	log: string?,
}
export type Clipboard = { boards: { [string]: { Entry } }, count: number }

function Clipboard.new(): Clipboard
	return { boards = {}, count = 0 }
end

local function better(a: Entry, b: Entry): boolean
	if a.tenths ~= b.tenths then
		return a.tenths < b.tenths
	end
	return a.drops < b.drops
end

function Clipboard.add(c: Clipboard, boardId: string, entry: Entry): number?
	local list = c.boards[boardId]
	if list == nil then
		list = {}
		c.boards[boardId] = list
	end
	-- one line a player: a run that does not beat their own line changes nothing
	for i, old in list do
		if old.name == entry.name then
			if not better(entry, old) then
				return nil
			end
			table.remove(list, i)
			break
		end
	end
	local place = #list + 1
	for i, old in list do
		if better(entry, old) then
			place = i
			break
		end
	end
	if place > Clipboard.PLACES then
		return nil
	end
	table.insert(list, place, {
		name = entry.name,
		tenths = entry.tenths,
		drops = entry.drops,
		hold = entry.hold,
		log = entry.log,
	})
	while #list > Clipboard.PLACES do
		table.remove(list)
	end
	-- only the record keeps its log
	for i = 2, #list do
		list[i].log = nil
		list[i].hold = nil
	end
	c.count += 1
	return place
end

function Clipboard.list(c: Clipboard, boardId: string): { Entry }
	return c.boards[boardId] or {}
end

function Clipboard.ghost(c: Clipboard, boardId: string): { hold: number, log: string }?
	local first = Clipboard.list(c, boardId)[1]
	if first and first.log and first.hold then
		return { hold = first.hold, log = first.log }
	end
	return nil
end

-- The clipboard's text for one board: a heading and up to five lines.
function Clipboard.lines(c: Clipboard, boardId: string, clockText: (tenths: number) -> string): { string }
	local out = { "Labyrinth: best times today" }
	local list = Clipboard.list(c, boardId)
	if #list == 0 then
		table.insert(out, "Nobody yet. Dr. Maple will see you eventually.")
	end
	for i, e in list do
		local dropped = if e.drops == 0 then "clean" elseif e.drops == 1 then "1 drop" else `{e.drops} drops`
		table.insert(out, `{i}. {e.name}  {clockText(e.tenths)}  ({dropped})`)
	end
	return out
end

return Clipboard
