--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.Replay
-- The score of record (checklist PIN-P6). The player's own machine runs the model live so a flipper moves in
-- the frame the key goes down; what it sends the server is only its input log (InputLog). The server feeds
-- each segment to a Replay, which steps the very same Machine and so arrives at the very same game: the score
-- on the backglass, the result and the high-score table come from here, never from a number the client
-- claims. Everyone else who draws the game (watchers near the cabinet, the other players waiting for their
-- ball) keeps a Replay of their own and follows the segments the server has taken: the real ball, a little
-- behind.
-- TWO WAYS IN, because only the server can judge:
--   * feed() is the JUDGE's (the server's). A segment must come from the player whose ball it is, start where
--     the last one ended and pass InputLog.check; a thump on the glass may only appear where the server
--     granted one (an animal landed on the cabinet); it may not run ahead of the server's clock; and a score
--     that climbs faster than the table's maxScorePerSec marks the replay suspect (it cannot happen by play;
--     it would mean a fault in the model).
--   * follow() is a FOLLOWER's (a watcher's copy, another player's copy): the same segment, already taken by
--     the server, played with none of the judging. A follower was never given the thump grant and has no
--     clock of the server's, so it must not second-guess them: it only checks that the segment is the next.
-- TIME. A log is a list of ticks, and nothing in it says when they were played: slow motion (a ramp's window of
-- 8 ticks is 33 ms at full speed and 133 ms at a quarter) and a burst (thirty seconds of log in one message,
-- for the server to simulate at once) both look like play. So the server tells the replay the time:
-- clock(r, seconds) with its own clock (any origin, seconds, never running back), before every segment it
-- feeds and a few times a second besides. Time is measured hand by hand (the hand-over between two players'
-- machines costs a round trip each time, which must not add up; one player's balls in a row are one stretch of
-- their own clock): from the moment a ball comes up to a new pair of hands, its log may be at most
-- AHEAD_SECONDS ahead of the clock (feed refuses the segment "ahead" and plays none of it: the caller keeps it
-- and feeds it again when the clock has caught up) and at most BEHIND_SECONDS behind. BEHIND IS JUDGED ONLY ON
-- WHAT ARRIVES: a line that has gone quiet (a stall on wifi, a phone between two masts) is not slow play, and
-- the log that was held up arrives in a burst and catches up; a dead line is the turn clock's to deal with, not
-- this one's. So clock() gives its verdict only once the time has moved on since a segment was fed, and says
-- "behind" only when the log has stayed more than BEHIND_SECONDS behind for BEHIND_HOLD (a burst that comes in
-- over a few frames is not judged half way): the caller then takes the ball with lapse(), which plays it out
-- dead and marks that player late. Lateness and suspicion are the seat's, not the game's: fair(r, seat) is
-- false for a seat that was suspect or late, whose score stands but takes no place on the board; fair(r) asks
-- it of the whole game.
-- idle is how long the buttons in the log have not changed (a player who has walked off with the ball on the
-- plunger, or holds a cradle for ever while others wait).
-- A ball changing hands ends a segment early. Replay.live always cuts there, so only a late or faulty machine
-- sends a segment that runs on: the part up to the end of the ball is the game and is played, the rest is
-- dropped, and feed says so (true, "overrun", ticks played) and sets `drift`.
-- Two machines that run the same model on the same log cannot differ; all the same, sum() is one number of
-- the state for a client to send with its segment. feed() compares it and sets `drift` when they do not agree:
-- the server's game stands, and the player's machine is sent a clone() to carry on from. `epoch` counts the
-- times the server played by itself (skip, retire of the player up, lapse): every copy that was not told to do
-- the same at the same tick (the player's own machine, which is ahead of the server) needs a clone() after one.
-- Pure; Lune-tested (tests/unit/pinball_replay.spec.luau).
-- Interface: new(tableId, seed, players) -> State; clone(r) -> State;
--   feed(r, seat, segment, out?, sum?) -> (ok, why?, ticks played); follow(r, seat, segment, out?) -> (ok, why?,
--   ticks played); recorder(r) -> InputLog.Recorder and live(r, rec, buttons, out?) -> Segment? (the player's
--   side); skip(r, out?) (the ball in play is abandoned and played out dead); retire(r, seat, out?) -> bool (a player
--   has gone for good: their ball in play is played out dead, their later balls passed over, their score
--   kept); grantThump(r) -> boolean; clock(r, seconds) -> "ok" | "ahead" | "behind"; lapse(r, out?);
--   pace(r) -> ticks ahead of the clock on this ball; fair(r, seat?) -> boolean; idleSeconds(r) -> number;
--   sum(r) -> number; over(r) -> boolean; SEGMENT_TICKS, GUARD_MIN_SECONDS, AHEAD_SECONDS, BEHIND_SECONDS,
--   THUMP_TICKS; State { id, m, tick, own, idle, drift, suspect, late, epoch, ... }

local InputLog = require("./InputLog")
local Machine = require("./Machine")
local Physics = require("./Physics")
local Tables = require("./Tables")

local Replay = {}

Replay.GUARD_MIN_SECONDS = 5 -- the rate guard averages over at least this long
Replay.SEGMENT_TICKS = InputLog.WIRE_TICKS -- the player's machine sends its log ten times a second
Replay.AHEAD_SECONDS = 0.5 -- a ball's log may be this far ahead of the server's clock (jitter), no further
Replay.BEHIND_SECONDS = 2 -- and this far behind on what arrives (a hitch, a slow link); further is slow motion
Replay.BEHIND_HOLD = 0.5 -- seconds it must stay that far behind before the verdict (a burst after a stall catches up)
Replay.THUMP_TICKS = Machine.THUMP_COOL -- a granted thump is good for this long, and no second is granted inside it

export type State = {
	id: string,
	m: Machine.State,
	tick: number, -- ticks replayed
	own: number, -- of those, the ticks the server played by itself (a skipped or retired ball)
	idle: number, -- ticks since the buttons in the log last changed (0 at every new ball)
	drift: boolean, -- a segment came with a sum() that was not this replay's (the caller sends a clone and clears it)
	held: number, -- the buttons at the end of the last segment
	thumps: number, -- thumps the server has granted and the log has not yet used (0 or 1)
	thumpAt: number, -- the tick the last thump was granted at (-1: none yet)
	suspect: boolean, -- some seat's score climbed faster than play can (suspectSeats says whose)
	late: boolean, -- some seat's ball was taken because its log fell too far behind the clock (lateSeats: whose)
	suspectSeats: { boolean },
	lateSeats: { boolean },
	epoch: number, -- how many times the server has played by itself (skip, retire of the player up, lapse)
	now: number, -- the server's clock as last told, in seconds (-1: never told; then time is not judged)
	ballClock: number, -- that clock when the hands now on the buttons took the ball (clockTick: the tick then)
	clockTick: number,
	fresh: boolean, -- a segment has been fed since the clock last gave its verdict
	behindSince: number, -- the clock when the log was first seen too far behind (-1: it is not)
	ballScore: number, -- the score of the player up when this ball started
	ballTick: number,
}

local PLAY, OVER = Machine.PHASE.PLAY, Machine.PHASE.OVER
local THUMP = Machine.BTN.THUMP

function Replay.new(tableId: string, seed: number, players: number): State
	local tbl = Tables.need(tableId)
	return {
		id = tableId,
		m = Machine.new(tbl, seed, players),
		tick = 0,
		own = 0,
		idle = 0,
		drift = false,
		held = 0,
		thumps = 0,
		thumpAt = -1,
		suspect = false,
		late = false,
		suspectSeats = table.create(players, false),
		lateSeats = table.create(players, false),
		epoch = 0,
		now = -1,
		ballClock = 0,
		clockTick = 0,
		fresh = false,
		behindSince = -1,
		ballScore = 0,
		ballTick = 0,
	}
end

-- clone(r): the replay as it stands, a deep copy of plain data. It is what a watcher who walks up in the
-- middle of a game is sent: fed the segments that follow, the copy goes on exactly as the original does.
function Replay.clone(r: State): State
	local copy = table.clone(r)
	copy.m = Machine.clone(r.m)
	return copy
end

function Replay.over(r: State): boolean
	return r.m.phase == OVER
end

-- grantThump(r): the server lets one thump on the glass into the log (an animal has landed on the cabinet).
-- False when one was granted less than THUMP_TICKS ago: the same animal, the same thump.
function Replay.grantThump(r: State): boolean
	if r.m.phase == OVER or (r.thumpAt >= 0 and r.tick - r.thumpAt < Replay.THUMP_TICKS) then
		return false
	end
	r.thumps = 1
	r.thumpAt = r.tick
	return true
end

-- pace(r): how many ticks the log of the hands on the buttons is ahead of the clock as last told (negative:
-- behind). 0 until a clock has been told.
function Replay.pace(r: State): number
	if r.now < 0 then
		return 0
	end
	return (r.tick - r.clockTick) - (r.now - r.ballClock) * Physics.HZ
end

-- clock(r, seconds): tell the replay the time (the server's own clock; any origin; it never runs back), and
-- hear where the log of the ball in play stands against it: "ok", "ahead" (more than AHEAD_SECONDS: feed is
-- refusing segments until the clock catches up) or "behind" (the log that has ARRIVED has stayed more than
-- BEHIND_SECONDS behind for BEHIND_HOLD: slow motion; the caller takes the ball with lapse()). Nothing having
-- arrived is never "behind": the verdict is given only when the time has moved on since a segment was fed, so
-- a burst fed in one go is judged once, whole. The first call starts the time.
function Replay.clock(r: State, seconds: number): "ok" | "ahead" | "behind"
	if r.now < 0 then
		r.ballClock = seconds
		r.clockTick = r.tick
	end
	local moved = seconds > r.now
	if moved then
		r.now = seconds
	end
	if r.m.phase == OVER then
		return "ok"
	end
	local pace = Replay.pace(r)
	if pace > Replay.AHEAD_SECONDS * Physics.HZ then
		return "ahead"
	end
	if moved and r.fresh then
		r.fresh = false
		if pace < -Replay.BEHIND_SECONDS * Physics.HZ then
			if r.behindSince < 0 then
				r.behindSince = r.now
			end
			if r.now - r.behindSince >= Replay.BEHIND_HOLD then
				return "behind"
			end
		else
			r.behindSince = -1
		end
	end
	return "ok"
end

-- fair(r, seat?): the seat's balls (or, with no seat, every seat's) were played in time and at a rate play can
-- reach. Only a fair player's score takes a place on the machine's board of best scores (HighScores.add): one
-- player's slow line keeps nobody else off it.
function Replay.fair(r: State, seat: number?): boolean
	if seat == nil then
		return not r.suspect and not r.late
	end
	return not r.suspectSeats[seat] and not r.lateSeats[seat]
end

-- idleSeconds(r): how long the buttons in the log have not changed on this ball.
function Replay.idleSeconds(r: State): number
	return r.idle / Physics.HZ
end

-- sum(r): one whole number of the state as it stands (the tick, the scores, where every ball is to a millionth
-- of a stud). Two replays of the same log have the same sum; two that have come apart almost surely do not.
function Replay.sum(r: State): number
	local m = r.m
	local h = (r.tick * 31 + m.up * 7 + m.ball) % 2147483648
	for _, score in m.scores do
		h = (h * 33 + score) % 2147483648
	end
	for _, b in m.phys.balls do
		h = (h * 33 + math.floor(b.x * 1e6) + math.floor(b.y * 1e6) * 7 + b.mode) % 2147483648
	end
	return h
end

local function guard(r: State, tbl: Machine.Table)
	local m = r.m
	local seconds = math.max((r.tick - r.ballTick) / Physics.HZ, Replay.GUARD_MIN_SECONDS)
	if m.scores[m.up] - r.ballScore > tbl.sheet.maxScorePerSec * seconds then
		r.suspect = true
		r.suspectSeats[m.up] = true
	end
end

local scratch: { number } = {}

-- a new ball has come up at this tick (by the log, or by the server's own playing). `same`: the same player's
-- log carries straight on into it (their next ball, an extra ball): their clock runs on as one stretch. Any
-- other new ball starts its clock now: its player has yet to hear of it.
local function newBall(r: State, same: boolean?)
	r.ballScore = r.m.scores[r.m.up]
	r.ballTick = r.tick
	if not same then
		r.ballClock = r.now
		r.clockTick = r.tick
		r.fresh = false
		r.behindSince = -1
	end
	r.idle = 0
end

local function play(
	r: State,
	seat: number,
	seg: InputLog.Segment,
	out: { number }?,
	sum: number?,
	judge: boolean
): (boolean, string?, number?)
	local m = r.m
	if m.phase == OVER then
		return false, "the game is over"
	end
	if seat ~= m.up then
		return false, "not your ball"
	end
	local ok, why = InputLog.check(seg, r.tick)
	if not ok then
		return false, why
	end
	if judge then
		-- thumps on the glass are the server's to give, and a grant does not keep
		if r.thumps > 0 and seg[1] - r.thumpAt > Replay.THUMP_TICKS then
			r.thumps = 0
		end
		local held = r.held
		local thumps = 0
		for i = 4, #seg, 2 do
			local buttons = seg[i]
			if bit32.band(buttons, THUMP) ~= 0 and bit32.band(held, THUMP) == 0 then
				thumps += 1
			end
			held = buttons
		end
		if thumps > r.thumps then
			return false, "thump"
		end
		-- time is the server's to tell: no log runs ahead of it
		if r.now >= 0 then
			local ahead = (seg[2] - r.clockTick) - (r.now - r.ballClock) * Physics.HZ
			if ahead > Replay.AHEAD_SECONDS * Physics.HZ then
				return false, "ahead"
			end
		end
		r.thumps -= thumps
	end

	local tbl = Tables.need(r.id)
	local sink = out or scratch
	local up = m.up
	local from = r.tick
	local last = r.held
	local endHeld = InputLog.play(seg, r.held, function(buttons: number): boolean?
		Machine.step(tbl, m, buttons, sink)
		r.tick += 1
		if buttons ~= last then
			last = buttons
			r.idle = 0
		else
			r.idle += 1
		end
		if m.phase == PLAY and m.ballTicks == 0 then
			-- a new ball has just come up (this player's next, or the next player's)
			guard(r, tbl)
			newBall(r, m.up == up)
			return true
		end
		return m.phase == OVER or m.up ~= up
	end)
	r.held = if m.phase == PLAY and m.ballTicks == 0 or m.phase == OVER then 0 else endHeld
	guard(r, tbl)
	if judge then
		r.fresh = true
	end
	local played = r.tick - from
	local overrun = played < seg[2] - seg[1]
	if overrun or (sum ~= nil and sum ~= Replay.sum(r)) then
		r.drift = true
	end
	if out == nil then
		table.clear(scratch)
	end
	return true, if overrun then "overrun" else nil, played
end

-- feed(r, seat, segment, out, sum): the JUDGE's way in (the server's): replay one segment of the log of the
-- player in `seat`, with every guard. Cues go to out. sum, if the player's machine sent one, is its sum() at
-- the end of the segment. Returns ok, why and the ticks played: a refused segment plays none (r is untouched);
-- one that runs past the end of a ball is played to the end of the ball only (true, "overrun", ticks) and
-- sets drift, since its sender believes it is further on than the game is.
function Replay.feed(
	r: State,
	seat: number,
	seg: InputLog.Segment,
	out: { number }?,
	sum: number?
): (boolean, string?, number?)
	return play(r, seat, seg, out, sum, true)
end

-- follow(r, seat, segment, out): a FOLLOWER's way in (a watcher's copy, another player's copy): a segment the
-- server has already taken, played as it is. Thumps and time were the server's to judge and are not judged
-- again (a follower was never given the grant); only the order and the form are checked.
function Replay.follow(r: State, seat: number, seg: InputLog.Segment, out: { number }?): (boolean, string?, number?)
	return play(r, seat, seg, out, nil, false)
end

-- The player's side of the same thing. The player's machine is a Replay too (it has replayed every ball so
-- far, its own and the other players'); while its own ball is up it steps that machine live:
--   local rec = Replay.recorder(r)                       when the ball comes up
--   local seg = Replay.live(r, rec, buttons, out)        once a tick
-- live() steps the machine with the buttons held on this tick and records them; it returns a segment to
-- send whenever one is due (every SEGMENT_TICKS, and exactly where a ball ends, so no segment ever runs
-- across two balls). Feeding those segments to another Replay gives the same game, bit for bit. A segment
-- from live() always fits one message (InputLog.pack).
function Replay.recorder(r: State): InputLog.Recorder
	return InputLog.recorder(r.tick)
end

function Replay.live(r: State, rec: InputLog.Recorder, buttons: number, out: { number }?): InputLog.Segment?
	local m = r.m
	if m.phase == OVER then
		return nil
	end
	local tbl = Tables.need(r.id)
	local sink = out or scratch
	local up = m.up
	Machine.step(tbl, m, buttons, sink)
	r.tick += 1
	InputLog.push(rec, buttons)
	if out == nil then
		table.clear(scratch)
	end
	local handed = m.phase == OVER or m.up ~= up or (m.phase == PLAY and m.ballTicks == 0)
	if handed then
		local seg = InputLog.cut(rec)
		rec.held = 0
		r.held = 0
		newBall(r, m.up == up)
		return seg
	elseif rec.tick - rec.from >= Replay.SEGMENT_TICKS or #rec.pairs >= 2 * InputLog.WIRE_CHANGES then
		r.held = buttons
		return InputLog.cut(rec)
	end
	return nil
end

-- skip(r, out): the player whose ball it is has gone (an idle turn, a walk-away, a bite): the ball is played
-- out dead (flippers off, launched by the machine, left to drain) and its bonus counted, up to the moment
-- the next ball stands on the plunger. Every replay that is told to skip at the same tick does the same.
function Replay.skip(r: State, out: { number }?)
	local m = r.m
	if m.phase == OVER then
		return
	end
	local tbl = Tables.need(r.id)
	local sink = out or scratch
	if m.phase == PLAY then
		Machine.forfeit(tbl, m, sink)
	end
	local limit = Machine.FORFEIT_TICKS + 4000
	for _ = 1, limit do
		Machine.step(tbl, m, 0, sink)
		r.tick += 1
		r.own += 1
		if m.phase == OVER or (m.phase == PLAY and not m.forfeit) then
			break
		end
	end
	r.held = 0
	r.epoch += 1
	newBall(r)
	if out == nil then
		table.clear(scratch)
	end
end

-- lapse(r, out): the log of the ball in play has stayed more than BEHIND_SECONDS behind the clock (clock said
-- "behind"): the ball is taken (played out dead, as skip does) and its player is marked late: their score
-- stands, but it takes no place on the board (fair(r, seat)); the other players' do.
function Replay.lapse(r: State, out: { number }?)
	if r.m.phase == OVER then
		return
	end
	r.late = true
	r.lateSeats[r.m.up] = true
	Replay.skip(r, out)
end

-- retire(r, seat, out): the player in `seat` has gone for good. If their ball is in play it is played out dead
-- at once (as skip does: the epoch rises); their later balls are passed over; their score stands. A seat that
-- is not up changes nothing about the ball in play, only who is passed over at the next hand-over, so the epoch
-- does not rise: every copy may be told at any tick before that hand-over (the player whose ball it is, who is
-- ahead of the server, at once; a follower, who is behind it, when it reaches the server's tick) and comes to
-- the same game (sum() does not read who has gone). Returns true when the server played by itself (the ball
-- in play was taken, or nobody is left and the game is over).
function Replay.retire(r: State, seat: number, out: { number }?): boolean
	local m = r.m
	if m.phase == OVER or seat < 1 or seat > m.players or m.gone[seat] then
		return false
	end
	local tbl = Tables.need(r.id)
	local sink = out or scratch
	local mine = m.up == seat
	Machine.retire(tbl, m, seat, sink)
	local own = mine or m.phase == OVER
	if mine and m.phase ~= OVER then
		Replay.skip(r, sink)
	elseif own then
		r.epoch += 1
	end
	if out == nil then
		table.clear(scratch)
	end
	return own
end

return Replay
