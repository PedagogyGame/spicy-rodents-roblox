--!strict
-- ReplicatedStorage.Shared.Minigames.AirHockey.Wire
-- What air hockey puts on the wire, and nothing else knows the format.
-- UP (Minigame.Input, verb "log"): a player's hand is a LOG BY TICK, never a message per frame. A segment covers
-- the ticks (from, to]; its events are the inputs applied just before a tick runs: a new target for the mallet,
-- or a serve (Space / a tap while the countdown runs). Each event is six characters: the tick counted from the
-- segment's first (two base-64 digits) and the target's x and y (two digits each, 4096 steps across the reach of
-- that side's mallet: a quarter of a millimetre); a serve is "!" and the tick. A hand is QUANTISED to those steps
-- before the player's own simulation sees it, so the client and the server step the same numbers. Events travel
-- as strings of at most 198 characters (33 events), up to six of them after from and to: the wire's limits are
-- eight arguments of 200 characters.
-- DOWN (Minigame.State, kind "air_hockey"): the referee's stream. One message per stretch of ticks it decided:
-- { g (which match), n0, n (the ticks (n0, n]), m (who is a person: "0" Glacier against the computer, "1" Ember
-- against the computer, "2" both), a, b (the events each person's side was given, as one string each), s (the
-- whole state at tick n, STATE order), t0 (when tick 0 was, on the shared clock) }. Anyone can start from any
-- message (s is everything), and whoever holds the state at n0 gets the state at n by replaying the events.
-- Pure. Interface: SEGMENT_SOLO, SEGMENT_DUO, MAX_SEGMENT, SLACK, MAX_BEHIND, STRING, EVENT; quantise(side, x,
--   y) -> (qx, qy); target(side, qx, qy) -> (x, y); snap(side, x, y) -> (x, y); pack(events, from) -> { string };
--   unpack(strings, from, to) -> events? ; join(events, from) -> string; state(sim) -> { number };
--   load(sim, list) -> bool; same(sim, list) -> bool; STATE
-- An events table is { [tick] = { qx, qy } | { qx, qy, true } | { false, false, true } } (the third entry: a
-- serve on that tick; qx false: no new target).

local Sim = require("./Sim")

local Wire = {}

Wire.SEGMENT_SOLO = 24 -- ticks a segment of the log covers against the computer: ten messages a second
Wire.SEGMENT_DUO = 16 -- and against a person: fifteen a second (the other player waits on it)
Wire.MAX_SEGMENT = 1440 -- the longest stretch one message may cover (a client coming back from a long frame)
Wire.SLACK = 72 -- ticks a client may be ahead of the server's reading of the shared clock (0.3 s)
Wire.MAX_BEHIND = 96 -- with two people: the referee waits this long (0.4 s) for a hand, then plays on without it
Wire.STRING = 198 -- characters in one argument (33 events)
Wire.EVENT = 6
Wire.STEPS = 4095

local DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+-"
local VALUE: { [number]: number } = {}
for i = 1, #DIGITS do
	VALUE[string.byte(DIGITS, i)] = i - 1
end
local SERVE = string.byte("!")

-- the reach of a mallet's target (Sim.setTarget's own clamp)
local X0, X_SPAN = -0.556, 1.112
local Y_NEAR, Y_SPAN = 0.064, 1.042

function Wire.quantise(side: number, x: number, y: number): (number, number)
	local qx = math.floor((x - X0) / X_SPAN * Wire.STEPS + 0.5)
	local along = if side ~= 0 then y - Y_NEAR else -Y_NEAR - y -- distance from the centre line's limit
	local qy = math.floor(along / Y_SPAN * Wire.STEPS + 0.5)
	return math.clamp(qx, 0, Wire.STEPS), math.clamp(qy, 0, Wire.STEPS)
end

function Wire.target(side: number, qx: number, qy: number): (number, number)
	local x = X0 + qx * (X_SPAN / Wire.STEPS)
	local along = Y_NEAR + qy * (Y_SPAN / Wire.STEPS)
	return x, if side ~= 0 then along else -along
end

-- A hand's target as the simulation will be given it.
function Wire.snap(side: number, x: number, y: number): (number, number)
	return Wire.target(side, Wire.quantise(side, x, y))
end

local function digits(n: number): string
	return string.sub(DIGITS, n // 64 + 1, n // 64 + 1) .. string.sub(DIGITS, n % 64 + 1, n % 64 + 1)
end

-- Every event of a segment as one string, in tick order.
function Wire.join(events: { [number]: any }, from: number): string
	local ticks = {}
	for tick in events do
		table.insert(ticks, tick)
	end
	table.sort(ticks)
	local out = {}
	for _, tick in ticks do
		local e = events[tick]
		local off = digits(tick - from)
		if e[3] then
			table.insert(out, "!" .. off .. "!!!")
		end
		if e[1] then
			table.insert(out, off .. digits(e[1]) .. digits(e[2]))
		end
	end
	return table.concat(out)
end

-- The same, cut into arguments for the wire (whole events in each).
function Wire.pack(events: { [number]: any }, from: number): { string }
	local all = Wire.join(events, from)
	local out = {}
	for i = 1, #all, Wire.STRING do
		table.insert(out, string.sub(all, i, i + Wire.STRING - 1))
	end
	return out
end

-- The events of the ticks (from, to] from their strings, or nil if they are not a segment: every event whole, in
-- tick order, inside the segment, at most one target and one serve a tick.
function Wire.unpack(strings: { any }, from: number, to: number): { [number]: any }?
	local events: { [number]: any } = {}
	local last, lastServe = 0, 0
	for _, text in strings do
		if type(text) ~= "string" or #text % Wire.EVENT ~= 0 or #text > 4 * Wire.MAX_SEGMENT * Wire.EVENT then
			return nil
		end
		for i = 1, #text, Wire.EVENT do
			local b1, b2, b3, b4, b5, b6 = string.byte(text, i, i + 5)
			if b1 == SERVE then
				local hi, lo = VALUE[b2], VALUE[b3]
				if hi == nil or lo == nil or b4 ~= SERVE or b5 ~= SERVE or b6 ~= SERVE then
					return nil
				end
				local off = hi * 64 + lo
				if off < 1 or off < last or off <= lastServe or from + off > to then
					return nil
				end
				lastServe = off
				local e = events[from + off]
				if e then
					e[3] = true
				else
					events[from + off] = { false, false, true }
				end
			else
				local hi, lo, x1, x2, y1, y2 = VALUE[b1], VALUE[b2], VALUE[b3], VALUE[b4], VALUE[b5], VALUE[b6]
				if hi == nil or lo == nil or x1 == nil or x2 == nil or y1 == nil or y2 == nil then
					return nil
				end
				local off = hi * 64 + lo
				if off < 1 or off <= last or off < lastServe or from + off > to then
					return nil
				end
				last = off
				local e = events[from + off]
				if e then
					e[1], e[2] = x1 * 64 + x2, y1 * 64 + y2
				else
					events[from + off] = { x1 * 64 + x2, y1 * 64 + y2 }
				end
			end
		end
	end
	return events
end

-- The whole state, as a list (what a match is at one tick: enough to carry on from).
Wire.STATE = {
	"px",
	"py",
	"vx",
	"vy",
	"p0x",
	"p0y",
	"t0x",
	"t0y",
	"p1x",
	"p1y",
	"t1x",
	"t1y",
	"score0",
	"score1",
	"countdown",
	"difficulty",
	"winner",
	"serveSide",
	"lastGoal",
	"hitSerial",
	"goalSerial",
}

function Wire.state(sim: Sim.State): { number }
	local s = sim :: any
	local out = table.create(#Wire.STATE)
	for i, k in Wire.STATE do
		out[i] = s[k]
	end
	return out
end

-- Take a state from the wire (false: not one; the simulation is left as it was).
function Wire.load(sim: Sim.State, list: any): boolean
	if type(list) ~= "table" or #list ~= #Wire.STATE then
		return false
	end
	for _, v in list do
		if type(v) ~= "number" or v ~= v or math.abs(v) == math.huge then
			return false
		end
	end
	local s = sim :: any
	for i, k in Wire.STATE do
		s[k] = list[i]
	end
	s.v0x, s.v0y, s.v1x, s.v1y = 0, 0, 0, 0
	return true
end

function Wire.same(sim: Sim.State, list: { number }): boolean
	local s = sim :: any
	for i, k in Wire.STATE do
		if s[k] ~= list[i] then
			return false
		end
	end
	return true
end

return Wire
