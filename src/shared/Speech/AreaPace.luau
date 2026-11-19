--!strict
-- ReplicatedStorage.Shared.Speech.AreaPace
-- A cap on chatter by place, on top of Speech/SpeechRules' per-person cooldown and town-wide window: at most
-- `max` lines inside `radius` studs of each other in any `window` seconds, so one street corner is not a wall of
-- bubbles while the rest of town is quiet. A line that opens an exchange asks for room for its answer too (`need`).
-- Speech/SpeechRules keeps the town's one (a State built with `area`): every line said with a place counts, whoever
-- says it; the overhead watch's lines (Server/Stealth/OverheadService) are held back by it.
-- Interface: new(params?) -> State; allow(state, now, x, z, need?) -> boolean; note(state, now, x, z);
--   count(state, now, x, z) -> number; DEFAULTS
-- Pure: time is injected. No side effects on require.

local AreaPace = {}

export type Params = { radius: number, window: number, max: number }
export type State = { params: Params, said: { { number } } } -- { t, x, z }, oldest first

AreaPace.DEFAULTS = table.freeze({
	radius = 40, -- studs
	window = 10, -- seconds
	max = 3, -- lines
})

function AreaPace.new(params: Params?): State
	return { params = params or table.clone(AreaPace.DEFAULTS) :: any, said = {} }
end

local function prune(state: State, now: number)
	local said = state.said
	local w = state.params.window
	while #said > 0 and now - said[1][1] >= w do
		table.remove(said, 1)
	end
end

-- count(state, now, x, z): the lines said inside the radius of (x, z) in the window.
function AreaPace.count(state: State, now: number, x: number, z: number): number
	prune(state, now)
	local r2 = state.params.radius * state.params.radius
	local n = 0
	for _, s in state.said do
		if (s[2] - x) ^ 2 + (s[3] - z) ^ 2 <= r2 then
			n += 1
		end
	end
	return n
end

-- allow(state, now, x, z, need?): is there room for `need` (default 1) more lines here.
function AreaPace.allow(state: State, now: number, x: number, z: number, need: number?): boolean
	return AreaPace.count(state, now, x, z) + (need or 1) <= state.params.max
end

-- note(state, now, x, z): a line was said here.
function AreaPace.note(state: State, now: number, x: number, z: number)
	prune(state, now)
	table.insert(state.said, { now, x, z })
end

return AreaPace
