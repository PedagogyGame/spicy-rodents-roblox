--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.InputLog
-- What the player did, tick by tick, small enough to send (checklist PIN-P6). The machine runs live on the
-- player's own computer; the buttons held on each tick (Machine.BTN bits) are recorded here and sent to the
-- server in segments of a second or so. The server replays the same model from the log (Replay) and that
-- replay is the score of record; watchers are drawn from the same log, a little behind.
-- A segment is a flat list of numbers: { from, to, offset, buttons, offset, buttons, ... }. It covers the ticks
-- from + 1 .. to; each pair says "from tick from + offset on, these buttons are held". Buttons carry over
-- from the segment before, so a second of holding one flipper is four numbers.
-- check() is the guard on what a client may send: whole numbers in range, offsets rising, no more ticks and no
-- more changes than a segment may hold.
-- On the wire (Minigames/Games rule 1: a message's arguments are at most 8 numbers, booleans or strings of 200
-- characters, and a stream of input is one segment about ten times a second) a segment is three arguments:
-- fromTick, toTick and its changes packed in one string, four characters a change (pack / unpack). 200
-- characters hold WIRE_CHANGES changes, more than a segment of WIRE_TICKS ticks can have, so a segment the
-- player's machine cuts always fits one message.
-- Pure; Lune-tested (tests/unit/pinball_replay.spec.luau).
-- Interface: MAX_TICKS, MAX_CHANGES, WIRE_TICKS, WIRE_CHANGES, WIRE_CHARS; recorder(tick) -> Recorder;
--   push(rec, buttons); cut(rec) -> Segment; check(segment, from) -> (ok, why?); play(segment, held, each) ->
--   held; changes(segment) -> number; pack(segment) -> (from, to, packed); unpack(from, to, packed) -> Segment?

local InputLog = {}

InputLog.MAX_TICKS = 720 -- three seconds a segment at most
InputLog.MAX_CHANGES = 160 -- a person cannot change the buttons more often than this in one segment (a plunger pulled by a stick changes at every step of its travel)
InputLog.BUTTONS_MAX = 4095 -- Machine.BUTTONS_MAX: seven button bits and an analogue plunger of 0..31 above them
InputLog.WIRE_CHARS = 200 -- the longest string a message may carry
InputLog.WIRE_CHANGES = 50 -- four characters a change
InputLog.WIRE_TICKS = 24 -- the player's machine cuts a segment this often: ten messages a second

export type Segment = { number }
export type Recorder = {
	from: number, -- the tick the next segment starts after
	tick: number, -- the last tick pushed
	held: number, -- the buttons on that tick
	pairs: { number }, -- (offset, buttons) so far
}

function InputLog.recorder(tick: number): Recorder
	return { from = tick, tick = tick, held = 0, pairs = {} }
end

-- push(rec, buttons): the buttons held for the next tick.
function InputLog.push(rec: Recorder, buttons: number)
	rec.tick += 1
	if buttons ~= rec.held then
		rec.held = buttons
		table.insert(rec.pairs, rec.tick - rec.from)
		table.insert(rec.pairs, buttons)
	end
end

-- cut(rec): everything pushed since the last cut, as one segment.
function InputLog.cut(rec: Recorder): Segment
	local seg: Segment = { rec.from, rec.tick }
	for _, v in rec.pairs do
		table.insert(seg, v)
	end
	rec.from = rec.tick
	table.clear(rec.pairs)
	return seg
end

function InputLog.changes(seg: Segment): number
	return (#seg - 2) // 2
end

local function whole(v: any): boolean
	return type(v) == "number" and v == v and v % 1 == 0
end

-- check(segment, from): is this a segment a client may send, starting where the last one ended?
function InputLog.check(seg: any, from: number): (boolean, string?)
	if type(seg) ~= "table" then
		return false, "not a segment"
	end
	local n = #seg
	if n < 2 or n % 2 ~= 0 then
		return false, "length"
	end
	if n > 2 + 2 * InputLog.MAX_CHANGES then
		return false, "too many changes"
	end
	local a, b = seg[1], seg[2]
	if not whole(a) or not whole(b) then
		return false, "ticks"
	end
	if a ~= from then
		return false, "out of order"
	end
	if b <= a or b - a > InputLog.MAX_TICKS then
		return false, "span"
	end
	local last = 0
	for i = 3, n, 2 do
		local offset, buttons = seg[i], seg[i + 1]
		if not whole(offset) or not whole(buttons) then
			return false, "numbers"
		end
		if offset <= last or offset > b - a then
			return false, "offsets"
		end
		if buttons < 0 or buttons > InputLog.BUTTONS_MAX then
			return false, "buttons"
		end
		last = offset
	end
	return true
end

-- The wire's alphabet: 64 characters that pass through any text channel unchanged. A change is 22 bits (the
-- offset, 1..1023, above the 12 bits of buttons) in four characters, most significant first.
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local VALUE: { [number]: number } = {}
for i = 1, #ALPHABET do
	VALUE[string.byte(ALPHABET, i)] = i - 1
end

-- pack(segment): a segment as the three arguments of one message: fromTick, toTick, the changes in a string.
-- (A segment cut by Replay.live always fits; one with more than WIRE_CHANGES changes is an error.)
function InputLog.pack(seg: Segment): (number, number, string)
	local n = InputLog.changes(seg)
	assert(n <= InputLog.WIRE_CHANGES, "too many changes for one message")
	local bytes = table.create(n * 4)
	for i = 3, #seg, 2 do
		local v = seg[i] * 4096 + seg[i + 1]
		table.insert(bytes, string.byte(ALPHABET, v // 262144 + 1))
		table.insert(bytes, string.byte(ALPHABET, v // 4096 % 64 + 1))
		table.insert(bytes, string.byte(ALPHABET, v // 64 % 64 + 1))
		table.insert(bytes, string.byte(ALPHABET, v % 64 + 1))
	end
	return seg[1], seg[2], string.char(table.unpack(bytes))
end

-- unpack(from, to, packed): the segment those three arguments stand for, or nil if they are not a packed
-- segment at all (the wrong types, a string too long or of the wrong alphabet). What comes back still has to
-- pass check(): unpack only reads, check() judges.
function InputLog.unpack(from: any, to: any, packed: any): Segment?
	if type(from) ~= "number" or type(to) ~= "number" or type(packed) ~= "string" then
		return nil
	end
	local len = #packed
	if len > InputLog.WIRE_CHARS or len % 4 ~= 0 then
		return nil
	end
	local seg: Segment = { from, to }
	for i = 1, len, 4 do
		local a, b, c, d =
			VALUE[string.byte(packed, i)],
			VALUE[string.byte(packed, i + 1)],
			VALUE[string.byte(packed, i + 2)],
			VALUE[string.byte(packed, i + 3)]
		if a == nil or b == nil or c == nil or d == nil or a > 15 then
			return nil
		end
		local v = ((a * 64 + b) * 64 + c) * 64 + d
		table.insert(seg, v // 4096)
		table.insert(seg, v % 4096)
	end
	return seg
end

-- play(segment, held, each): call each(buttons) once for every tick of a checked segment, starting from the
-- buttons held before it. each may return true to stop early (the ball changed hands). Returns the buttons
-- held at the end (or at the stop) and the number of ticks played.
function InputLog.play(seg: Segment, held: number, each: (buttons: number) -> boolean?): (number, number)
	local span = seg[2] - seg[1]
	local i = 3
	local n = #seg
	for offset = 1, span do
		if i < n and seg[i] == offset then
			held = seg[i + 1]
			i += 2
		end
		if each(held) then
			return held, offset
		end
	end
	return held, span
end

return InputLog
