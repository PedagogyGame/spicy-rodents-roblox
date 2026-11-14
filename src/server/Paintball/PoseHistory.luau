--!strict
-- ServerScriptService.Server.Paintball.PoseHistory
-- Lag-compensation pose history (D29: 1 s per body, rewound to the shooter's timestamp; spike S18;
-- checklist PB-3): a fixed ring of (time, x, y, z, crouch) samples per body in flat arrays, sampled at
-- any time inside the window by linear interpolation (held at the oldest and at the newest sample).
-- The crouch fraction rides in the same ring with the same interpolation, so a body that was crouched
-- on the shooter's screen is judged crouched (Shared/Minigames/Paintball/Wire.between is the same
-- arithmetic on the client: the contract's keystone). No allocation after new().
-- In a match the paintball service pushes one sample per snapshot tick, exactly the quantised pose the
-- snapshot carries (Shared/Minigames/Paintball/Clock: "the history is the snapshot stream"); the S18
-- harness pushes every frame.
-- Interface: new(seconds, hz) -> History; push(h, t, x, y, z, crouch?); sample(h, t) -> (x, y, z,
--   crouch); newest(h) -> (t, x, y, z, crouch); span(h); clear(h)

export type History = {
	cap: number,
	count: number,
	head: number, -- index of the newest sample (1-based)
	ts: { number },
	xs: { number },
	ys: { number },
	zs: { number },
	cs: { number }, -- the crouch fraction, 0..1
}

local PoseHistory = {}

function PoseHistory.new(seconds: number, hz: number): History
	local cap = math.ceil(seconds * hz) + 2
	return {
		cap = cap,
		count = 0,
		head = 0,
		ts = table.create(cap, 0),
		xs = table.create(cap, 0),
		ys = table.create(cap, 0),
		zs = table.create(cap, 0),
		cs = table.create(cap, 0),
	}
end

function PoseHistory.push(h: History, t: number, x: number, y: number, z: number, crouch: number?)
	local i = h.head % h.cap + 1
	h.head = i
	h.ts[i], h.xs[i], h.ys[i], h.zs[i], h.cs[i] = t, x, y, z, crouch or 0
	if h.count < h.cap then
		h.count += 1
	end
end

-- Forget everything (a body that was put somewhere else begins a new life: nothing of the old one
-- may be rewound to).
function PoseHistory.clear(h: History)
	h.count, h.head = 0, 0
end

-- seconds covered by the samples held
function PoseHistory.span(h: History): number
	if h.count < 2 then
		return 0
	end
	local oldest = (h.head - h.count) % h.cap + 1
	return h.ts[h.head] - h.ts[oldest]
end

-- The newest sample: its time and pose (zeros when there is none).
function PoseHistory.newest(h: History): (number, number, number, number, number)
	local i = h.head
	if h.count == 0 then
		return 0, 0, 0, 0, 0
	end
	return h.ts[i], h.xs[i], h.ys[i], h.zs[i], h.cs[i]
end

function PoseHistory.sample(h: History, t: number): (number, number, number, number)
	local cap, ts = h.cap, h.ts
	local i = h.head
	if h.count == 0 then
		return 0, 0, 0, 0
	end
	if t >= ts[i] then
		return h.xs[i], h.ys[i], h.zs[i], h.cs[i]
	end
	-- walk back from the newest: a rewind is a few samples, so this is short
	for _ = 2, h.count do
		local j = if i == 1 then cap else i - 1
		local tj = ts[j]
		if t >= tj then
			local a = (t - tj) / (ts[i] - tj)
			return h.xs[j] + (h.xs[i] - h.xs[j]) * a,
				h.ys[j] + (h.ys[i] - h.ys[j]) * a,
				h.zs[j] + (h.zs[i] - h.zs[j]) * a,
				h.cs[j] + (h.cs[i] - h.cs[j]) * a
		end
		i = j
	end
	return h.xs[i], h.ys[i], h.zs[i], h.cs[i] -- older than the window: the oldest sample
end

return PoseHistory
