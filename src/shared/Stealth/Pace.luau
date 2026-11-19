--!strict
-- ReplicatedStorage.Shared.Stealth.Pace
-- How fast a body the server cannot steer is really going, read from where it is frame by frame (a held squirrel's
-- motor runs on its player's computer: the server sees only the body). Between two of a watcher's ticks the body is
-- sampled every frame; the fastest it went over any C.window seconds since the last tick is the tick's speed. The
-- fastest stretch, not the tick's average: tapping W (the walk in bursts, 7.5 studs/s on average) is walking, and
-- C.window is long enough that positions arriving in bunches do not make a creep read fast. Used by the alley's
-- rafters (Stealth/RafterSense) and the town's overhead watch (Server/Stealth/OverheadService).
-- The duel's ear (Server/Combat/CombatService; review of the overhead watch, M2) reads a body's pace from where it was
-- on the server's clock (the held squirrel's accepted motor packets, Movement/MovementService:paceOf; else its root at
-- the duel's steps): `stretch`, the fastest flat pace it KEPT UP over the last C.hold seconds: the pace of a move over
-- C.span seconds, at its lowest over C.confirm seconds of such moves. One position that arrives late, or two that
-- arrive together (a phone's frame hitch), makes a move or two read fast, never C.confirm's worth, so a creep reads as
-- a creep; tapping W still shows its bursts (a walk of 18 for a fifth of a second in every two fifths reads 10, though
-- it averages under 8).
-- Interface: C; new() -> State; sample(state, id, x, y, z, dt); take(state, id) -> number? (the fastest stretch since
--   the last take, nil when none was a whole window long); forget(state, id); stretch(at, newest, oldest, span?,
--   hold?) -> number?; along(track, t) -> (x, z)
-- Pure. Any frame (studs).

local Pace = {}

Pace.C = {
	window = 0.1, -- seconds: the shortest stretch a sampled speed is measured over (six frames at 60 Hz)
	span = 0.3, -- seconds: the duel's ear measures a move over this long (stretch) ...
	confirm = 0.15, -- ... takes the lowest of the moves ending over this long ...
	hold = 0.6, -- ... and the fastest of those over the last this many seconds
	stride = 0.05, -- seconds between the moves it measures (the motor packets' own rate)
}
local C = Pace.C

-- a body's frames since the last take: its clock, the positions of the last C.window seconds (and the one before),
-- and the fastest stretch of C.window
type Frames = { clock: number, at: { { number } }, peak: number? }
export type State = { [any]: Frames }

function Pace.new(): State
	return {}
end

function Pace.forget(state: State, id: any)
	state[id] = nil
end

-- sample(state, id, x, y, z, dt): one frame of a body (any point that moves with it).
function Pace.sample(state: State, id: any, x: number, y: number, z: number, dt: number)
	local f = state[id]
	if f == nil then
		f = { clock = 0, at = {} }
		state[id] = f
	end
	f.clock += dt
	local at = f.at
	table.insert(at, { f.clock, x, y, z })
	-- keep the newest position at least C.window old, and everything after it
	while #at >= 2 and at[2][1] <= f.clock - C.window do
		table.remove(at, 1)
	end
	local o = at[1]
	local span = f.clock - o[1]
	if span >= C.window - 1e-9 then
		local v = math.sqrt((x - o[2]) ^ 2 + (y - o[3]) ^ 2 + (z - o[4]) ^ 2) / span
		f.peak = math.max(f.peak or 0, v)
	end
end

-- take(state, id): the fastest stretch since the last take (and starts the next), nil when there was none.
function Pace.take(state: State, id: any): number?
	local f = state[id]
	if f == nil then
		return nil
	end
	local peak = f.peak
	f.peak = nil
	return peak
end

-- One sample of a body's track: where it was (flat) at time t.
export type Point = { t: number, x: number, z: number }

-- stretch(at, newest, oldest, span?, hold?): the fastest flat pace (studs/s) the body kept up over the last `hold`
-- (C.hold) seconds up to `newest`: each move over `span` (C.span) seconds, at its lowest over the C.confirm seconds of
-- moves ending then, and the fastest of those. `at(t)` says where the body was at time t (between `oldest` and
-- `newest`, on one clock). Nil when what is known does not cover one whole span.
function Pace.stretch(
	at: (t: number) -> (number, number),
	newest: number,
	oldest: number,
	span: number?,
	hold: number?
): number?
	local sp = span or C.span
	local from = math.max(newest - (hold or C.hold), oldest)
	if newest - from < sp - 1e-9 then
		return nil
	end
	local keep = math.max(1, math.floor(C.confirm / C.stride + 0.5) + 1) -- the moves a pace must hold over
	local recent = table.create(keep, 0) :: { number } -- the last `keep` moves' paces (a ring)
	local n = 0
	local best = 0
	local t = newest
	while t - sp >= from - 1e-9 do
		local x1, z1 = at(t)
		local x0, z0 = at(t - sp)
		n += 1
		recent[(n - 1) % keep + 1] = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2) / sp
		local low = math.huge
		for i = 1, math.min(n, keep) do
			low = math.min(low, recent[i])
		end
		if n >= keep or t - C.stride - sp < from - 1e-9 then
			best = math.max(best, low)
		end
		t -= C.stride
	end
	return best
end

-- along(track, t): where a track (oldest first) had the body at time t, between its samples (held at either end).
function Pace.along(track: { Point }, t: number): (number, number)
	local n = #track
	if n == 0 then
		return 0, 0
	end
	if t >= track[n].t then
		return track[n].x, track[n].z
	end
	for i = n - 1, 1, -1 do
		local a = track[i]
		if t >= a.t then
			local b = track[i + 1]
			local k = if b.t > a.t then (t - a.t) / (b.t - a.t) else 1
			return a.x + (b.x - a.x) * k, a.z + (b.z - a.z) * k
		end
	end
	return track[1].x, track[1].z
end

return Pace
