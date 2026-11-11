--!strict
-- ReplicatedStorage.Shared.Minigames.Labyrinth.InputLog
-- A run of the labyrinth IS its input log: one code a tick (Controls.code), from the first key to the finish.
-- The player's machine plays the model live from the keys, sends the log in pieces as it goes, and the server
-- (and every watcher) replays the same pieces through the same model (C1, LAB-P6, LAB-S4). Keys are held for
-- many ticks at a time, so the log is written as runs: a letter a..i for the code and how many ticks it was
-- held. "e30h4e12" is 30 ticks of nothing, 4 ticks of right-and-forward, 12 of nothing. A person's taps and
-- holds come to about a character for every three or four ticks: a minute of play is a kilobyte.
-- A piece (segment) names the tick it starts at, so a lost or doubled piece is noticed and never shifts the
-- replay; it is at most SEGMENT_TICKS long, so nobody can make the server replay minutes in one call, and at
-- most SEGMENT_CHARS characters (Net scalar strings are capped at 200).
-- Pure; Lune-tested (tests/unit/labyrinth_rules.spec.luau).
-- Interface: SEGMENT_TICKS, SEGMENT_CHARS, SEND_EVERY; encode(codes, first?, last?) -> string;
--   decode(text, maxTicks?) -> codes? (nil for anything that is not a log); ticks(text) -> count?;
--   segments(codes, every?) -> { { start = tick, data = string } }; writer() -> Writer with
--   push(writer, code) and take(writer) -> (start tick, data)? (the client's side: what to send next)

local Controls = require("./Controls")

local InputLog = {}

InputLog.SEGMENT_TICKS = 120 -- two seconds: the most one piece may carry
InputLog.SEGMENT_CHARS = 190
InputLog.SEND_EVERY = 12 -- ticks between pieces from a live player: five a second, a watcher is 0.2 s behind

local A = string.byte("a")

function InputLog.encode(codes: { number }, first: number?, last: number?): string
	local out: { string } = {}
	local i = first or 1
	local stop = last or #codes
	while i <= stop do
		local code = codes[i]
		local n = 1
		while i + n <= stop and codes[i + n] == code do
			n += 1
		end
		table.insert(out, string.char(A + code) .. tostring(n))
		i += n
	end
	return table.concat(out)
end

-- nil unless the text is exactly a log of at most maxTicks ticks (default SEGMENT_TICKS)
function InputLog.decode(text: any, maxTicks: number?): { number }?
	if type(text) ~= "string" or #text == 0 then
		return nil
	end
	local limit = maxTicks or InputLog.SEGMENT_TICKS
	local codes: { number } = {}
	local pos = 1
	while pos <= #text do
		local letter, count, nextPos = string.match(text, "^([a-i])([1-9]%d*)()", pos)
		if letter == nil or #(count :: string) > 6 then
			return nil
		end
		local n = tonumber(count) :: number
		if #codes + n > limit then
			return nil
		end
		local code = string.byte(letter :: string) - A
		for _ = 1, n do
			table.insert(codes, code)
		end
		pos = nextPos :: number
	end
	return codes
end

function InputLog.ticks(text: any): number?
	local codes = InputLog.decode(text, math.huge)
	return if codes then #codes else nil
end

-- A whole log cut into the pieces a client would have sent: each starts where the last ended.
function InputLog.segments(codes: { number }, every: number?): { { start: number, data: string } }
	local step = math.clamp(every or InputLog.SEND_EVERY, 1, InputLog.SEGMENT_TICKS)
	local out = {}
	local i = 1
	while i <= #codes do
		local last = math.min(#codes, i + step - 1)
		local data = InputLog.encode(codes, i, last)
		-- a piece of wild key-mashing could outgrow the character cap: send less of it
		while #data > InputLog.SEGMENT_CHARS do
			last = i + (last - i) // 2
			data = InputLog.encode(codes, i, last)
		end
		table.insert(out, { start = i - 1, data = data })
		i = last + 1
	end
	return out
end

export type Writer = {
	start: number, -- ticks already taken
	pending: { number },
}

function InputLog.writer(): Writer
	return { start = 0, pending = {} }
end

-- Call once for every tick played. Ticks before the first key are not part of a run (the clock has not
-- started, LAB-R4) and are not written.
function InputLog.push(w: Writer, code: number)
	if code == Controls.NEUTRAL and w.start == 0 and #w.pending == 0 then
		return
	end
	table.insert(w.pending, code)
end

-- The next piece to send (nil when nothing is waiting): the tick it starts at and its text.
function InputLog.take(w: Writer): (number?, string?)
	local n = #w.pending
	if n == 0 then
		return nil, nil
	end
	local last = math.min(n, InputLog.SEGMENT_TICKS)
	local data = InputLog.encode(w.pending, 1, last)
	while #data > InputLog.SEGMENT_CHARS do
		last = math.max(1, last // 2)
		data = InputLog.encode(w.pending, 1, last)
	end
	local start = w.start
	w.start += last
	local rest: { number } = table.create(n - last)
	table.move(w.pending, last + 1, n, 1, rest)
	w.pending = rest
	return start, data
end

return InputLog
