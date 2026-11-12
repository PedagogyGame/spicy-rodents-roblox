--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.Replay
-- The score of record (checklist PIN-P6). The player's own machine runs the model live so a flipper moves in
-- the frame the key goes down; what it sends the server is only its input log (InputLog). The server feeds
-- each segment to a Replay, which steps the very same Machine and so arrives at the very same game: the score
-- on the backglass, the result and the high-score table come from here, never from a number the client
-- claims. Watchers near the cabinet feed the same segments to a Replay of their own and draw the real ball
-- from it, a little behind.
-- The guards: a segment must come from the player whose ball it is, start where the last one ended and pass
-- InputLog.check; a thump on the glass may only appear where the server granted one (an animal landed on the
-- cabinet); the ball changing hands ends a segment early; and a score that climbs faster than the table's
-- maxScorePerSec marks the replay suspect (it cannot happen by play; it would mean a fault in the model).
-- Time is the caller's to police: pace() says how far the replay is ahead of a clock, so a server can refuse
-- a log that runs faster than real time and close a ball whose log has stopped coming.
-- Pure; Lune-tested (tests/unit/pinball_replay.spec.luau).
-- Interface: new(tableId, seed, players) -> State; clone(r) -> State; feed(r, seat, segment, out?) -> (ok, why?);
--   recorder(r) -> InputLog.Recorder and live(r, rec, buttons, out?) -> Segment? (the player's side);
--   skip(r, out?) (the ball in play is abandoned and played out dead); retire(r, seat, out?) (a player has
--   gone for good: their ball in play is played out dead, their later balls passed over, their score kept);
--   grantThump(r); pace(r, seconds) -> ticks
--   ahead; over(r) -> boolean; SEGMENT_TICKS, GUARD_MIN_SECONDS

local InputLog = require("./InputLog")
local Machine = require("./Machine")
local Physics = require("./Physics")
local Tables = require("./Tables")

local Replay = {}

Replay.GUARD_MIN_SECONDS = 5 -- the rate guard averages over at least this long
Replay.SEGMENT_TICKS = InputLog.WIRE_TICKS -- the player's machine sends its log ten times a second

export type State = {
	id: string,
	m: Machine.State,
	tick: number, -- ticks replayed
	held: number, -- the buttons at the end of the last segment
	thumps: number, -- thumps the server has granted and the log has not yet used
	suspect: boolean,
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
		held = 0,
		thumps = 0,
		suspect = false,
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

function Replay.grantThump(r: State)
	r.thumps += 1
end

-- pace(r, seconds): how many ticks the replay is ahead of a clock that has run for `seconds` since the game
-- started ticking (negative: behind).
function Replay.pace(r: State, seconds: number): number
	return r.tick - seconds * Physics.HZ
end

local function guard(r: State, tbl: Machine.Table)
	local m = r.m
	local seconds = math.max((r.tick - r.ballTick) / Physics.HZ, Replay.GUARD_MIN_SECONDS)
	if m.scores[m.up] - r.ballScore > tbl.sheet.maxScorePerSec * seconds then
		r.suspect = true
	end
end

local scratch: { number } = {}

-- feed(r, seat, segment, out): replay one segment of the log of the player in `seat`. Cues go to out.
function Replay.feed(r: State, seat: number, seg: InputLog.Segment, out: { number }?): (boolean, string?)
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
	-- thumps on the glass are the server's to give
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
	r.thumps -= thumps

	local tbl = Tables.need(r.id)
	local sink = out or scratch
	local up = m.up
	local endHeld = InputLog.play(seg, r.held, function(buttons: number): boolean?
		Machine.step(tbl, m, buttons, sink)
		r.tick += 1
		if m.phase == PLAY and m.ballTicks == 0 then
			-- a new ball has just come up (this player's next, or the next player's)
			guard(r, tbl)
			r.ballScore = m.scores[m.up]
			r.ballTick = r.tick
			return true
		end
		return m.phase == OVER or m.up ~= up
	end)
	r.held = if m.phase == PLAY and m.ballTicks == 0 or m.phase == OVER then 0 else endHeld
	guard(r, tbl)
	if out == nil then
		table.clear(scratch)
	end
	return true
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
		r.ballScore = m.scores[m.up]
		r.ballTick = r.tick
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
		if m.phase == OVER or (m.phase == PLAY and not m.forfeit) then
			break
		end
	end
	r.held = 0
	r.ballScore = m.scores[m.up]
	r.ballTick = r.tick
	if out == nil then
		table.clear(scratch)
	end
end

-- retire(r, seat, out): the player in `seat` has gone for good. If their ball is in play it is played out dead
-- at once (as skip does); their later balls are passed over; their score stands. Every replay that is told
-- to retire the same seat at the same tick does the same.
function Replay.retire(r: State, seat: number, out: { number }?)
	local m = r.m
	if m.phase == OVER or seat < 1 or seat > m.players or m.gone[seat] then
		return
	end
	local tbl = Tables.need(r.id)
	local sink = out or scratch
	local mine = m.up == seat
	Machine.retire(tbl, m, seat, sink)
	if mine and m.phase ~= OVER then
		Replay.skip(r, sink)
	end
	if out == nil then
		table.clear(scratch)
	end
end

return Replay
