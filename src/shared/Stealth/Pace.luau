--!strict
-- ReplicatedStorage.Shared.Stealth.Pace
-- How fast a body the server cannot steer is really going, read from where it is frame by frame (a held squirrel's
-- motor runs on its player's computer: the server sees only the body). Between two of a watcher's ticks the body is
-- sampled every frame; the fastest it went over any C.window seconds since the last tick is the tick's speed. The
-- fastest stretch, not the tick's average: tapping W (the walk in bursts, 7.5 studs/s on average) is walking, and
-- C.window is long enough that positions arriving in bunches do not make a creep read fast. Used by the alley's
-- rafters (Stealth/RafterSense) and the town's overhead watch (Server/Stealth/OverheadService).
-- Interface: C; new() -> State; sample(state, id, x, y, z, dt); take(state, id) -> number? (the fastest stretch since
--   the last take, nil when none was a whole window long); forget(state, id)
-- Pure. Any frame (studs).

local Pace = {}

Pace.C = {
	window = 0.1, -- seconds: the shortest stretch a sampled speed is measured over (six frames at 60 Hz)
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

return Pace
