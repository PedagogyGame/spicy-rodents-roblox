--!strict
-- ReplicatedStorage.Shared.Minigames.Pool.Words
-- What happened at a cue-sport table, in plain words (checklist POOL-S3: "the foul in plain words"; brief v2
-- §15: always say what you are looking at). The server says them in a banner when a shot is over, and the
-- client's status line and end card say them again; both read the same rules' view, so they cannot disagree.
-- The words for a foul and for how a game ended are the rules' own (EightBall.FOUL_TEXT / HOW_TEXT,
-- BumperPool.HOW_TEXT): nothing is reworded here, only put in a sentence with the players' names.
-- Pure; Lune-tested (tests/unit/pool_words.spec.luau).
-- Interface: balls(ids) -> "the 3 and the 5"; pocket(i) -> "the foot left corner"; eightBall(game view,
--   names, took?) -> string? (the last shot; took: the group the shooter has just been given); eightBallEnd(
--   game view, names) -> string (how the game ended); group(game view, seat) -> "solids" | "stripes" | "open
--   table"; bumper(game view, names) -> string?; bumperEnd(game view, names) -> string; refusal(why) -> words
--   for a rules' refusal

local BumperPool = require("./BumperPool")
local EightBall = require("./EightBall")
local Tables = require("./Tables")

local Words = {}

function Words.balls(ids: { number }): string
	local parts: { string } = {}
	for _, id in ids do
		if id ~= 0 then
			table.insert(parts, `the {id}`)
		end
	end
	if #parts == 0 then
		return "nothing"
	elseif #parts == 1 then
		return parts[1]
	end
	local last = table.remove(parts) :: string
	return `{table.concat(parts, ", ")} and {last}`
end

function Words.pocket(i: number): string
	local name = Tables.POCKET_NAMES[i]
	return if name then `the {name}{if i == 3 or i == 4 then " pocket" else ""}` else "no pocket"
end

local function nameOf(names: { string }, seat: number?): string
	return (seat and names[seat]) or "?"
end

function Words.group(g: { [string]: any }, seat: number): string
	local groups = g.groups
	local mine = groups and groups[seat]
	return if mine == "solids" or mine == "stripes" then mine else "open table"
end

-- The last shot at an eight-ball table.
function Words.eightBall(g: { [string]: any }, names: { string }, took: string?): string?
	local last = g.last
	if type(last) ~= "table" then
		return nil
	end
	local solo = #names < 2
	local shooter = nameOf(names, last.seat)
	local nextUp = nameOf(names, g.turn)
	local where = if g.inHand == "kitchen" then " behind the head string" else ""
	local event = last.event
	if event == "foul" then
		local hand = if solo then `Ball in hand{where}.` else `{nextUp} has the ball in hand{where}.`
		if last.foul == "idle" then
			return `{shooter} ran out of time. {hand}`
		end
		return `Foul: {EightBall.FOUL_TEXT[last.foul] or "a foul"}. {hand}`
	end
	local potted: { number } = {}
	local eight = false
	for _, id in last.pots or {} do
		if id == 8 then
			eight = true
		elseif id ~= 0 then
			table.insert(potted, id)
		end
	end
	if event == "win" then
		return `{shooter} {EightBall.HOW_TEXT.eight}!`
	elseif event == "lose" then
		return `{shooter} {EightBall.HOW_TEXT[g.how] or "lost on the 8"}.`
	end
	local spotted = if eight then " The 8 goes back on its spot." else ""
	if event == "continue" then
		local what = if #potted > 0 then Words.balls(potted) else "a ball"
		local tail = if took then ` and is on {took}` else ""
		if last.breakShot then
			return `{shooter} potted {what} on the break{tail}: still at the table.{spotted}`
		end
		return `{shooter} potted {what}{tail}: still at the table.{spotted}`
	end
	-- pass
	if solo then
		return if #potted > 0 then `{Words.balls(potted)} down.{spotted}` else `Nothing down.{spotted}`
	end
	if #potted > 0 then
		return `{shooter} potted {Words.balls(potted)} for {nextUp}: {nextUp}'s shot.{spotted}`
	end
	return `Nothing down: {nextUp}'s shot.{spotted}`
end

-- How a game of eight-ball ended.
function Words.eightBallEnd(g: { [string]: any }, names: { string }): string
	local last = g.last
	local shooter = nameOf(names, type(last) == "table" and last.seat or nil)
	local how = EightBall.HOW_TEXT[g.how] or "finished"
	if #names < 2 then
		return if g.how == "eight" then `{shooter} {how}: the table is cleared!` else `{shooter} {how}: game over.`
	end
	local winner = nameOf(names, g.winner)
	if g.how == "eight" then
		return `{winner} wins: {how}!`
	end
	return `{winner} wins: {shooter} {how}.`
end

-- The last shot at the bumper pool table.
function Words.bumper(g: { [string]: any }, names: { string }): string?
	local last = g.last
	if type(last) ~= "table" then
		return nil
	end
	local solo = #names < 2
	local shooters: { number } = last.shooters or {}
	local shooter = nameOf(names, shooters[1])
	local nextUp = nameOf(names, g.turn)
	local event = last.event
	local penalty = ""
	if last.awarded and last.awarded ~= 0 and #(last.dropped or {}) > 0 then
		local n = #last.dropped
		penalty = ` Penalty: {nameOf(names, last.awarded)} drops {if n == 1 then "a ball" else "two balls"} in.`
	end
	local back = ""
	if #(last.respotted or {}) > 0 then
		back = " That was the wrong cup: the ball is back on its spot."
	end
	if event == "win" or event == "lose" then
		return nil -- (the end banner says it)
	elseif event == "idle" then
		return if solo then `{shooter} ran out of time.` else `{shooter} ran out of time: {nextUp}'s shot.`
	elseif event == "opening" then
		local off = ""
		for _, seat in last.offside or {} do
			off ..= ` {nameOf(names, seat)} missed the right-hand cushion.`
		end
		if g.phase == "opening" then
			return `Both marked balls went down: open again.{off}`
		end
		return `The opening is played: {nextUp} shoots first.{off}{penalty}`
	elseif event == "continue" then
		return `{shooter} sank {if #(last.pots or {}) > 1 then "balls" else "a ball"}: another shot.{penalty}{back}`
	end
	if solo then
		return `No ball down.{back}`
	end
	return `{if #(last.pots or {}) > 0 then "A ball went down" else "No ball down"}: {nextUp}'s shot.{penalty}`
end

function Words.bumperEnd(g: { [string]: any }, names: { string }): string
	local how = BumperPool.HOW_TEXT[g.how] or "finished"
	if #names < 2 then
		return `All five are down: {how} in {(g.shots and g.shots[1]) or 0} shots.`
	end
	local winner = nameOf(names, g.winner)
	if g.how == "five" then
		return `{winner} wins: {how}!`
	end
	local loser = nameOf(names, if g.winner == 1 then 2 else 1)
	return `{winner} wins: {loser} {how}.`
end

local REFUSALS: { [string]: string } = {
	["cannot place there"] = "The cue ball cannot go there",
	["not in hand"] = "The cue ball is not in hand: play it where it lies",
	["call a pocket"] = "Call a pocket for the 8 first: click a pocket",
	["only the 8 is called"] = "Only the 8 needs a called pocket",
	["not your turn"] = "Not your turn yet",
	["not your ball"] = "That is not one of your balls",
	["already struck"] = "You have played your opening shot: wait for the other player",
	["the opening is played with the marked ball"] = "The opening is played with your marked ball",
	["game over"] = "The game is over",
	args = "That shot did not reach the table: try again",
	verb = "That does not work at this table",
}

-- A rules module's short reason, as words for the player.
function Words.refusal(why: string?): string
	return (why and REFUSALS[why]) or why or "That does not work at this table"
end

return Words
