--!strict
-- ServerScriptService.Server.Paintball.PoseHistory
-- Lag-compensation pose history (D29: 1 s per body, rewound to the shooter's timestamp; spike S18):
-- a fixed ring of (time, x, y, z) samples per body in flat arrays, pushed every server frame and
-- sampled at any time inside the window by linear interpolation (clamped to the oldest and newest
-- sample). No allocation after new().
-- Interface: new(seconds, hz) -> History; push(h, t, x, y, z); sample(h, t) -> (x, y, z); span(h)

export type History = {
	cap: number,
	count: number,
	head: number, -- index of the newest sample (1-based)
	ts: { number },
	xs: { number },
	ys: { number },
	zs: { number },
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
	}
end

function PoseHistory.push(h: History, t: number, x: number, y: number, z: number)
	local i = h.head % h.cap + 1
	h.head = i
	h.ts[i], h.xs[i], h.ys[i], h.zs[i] = t, x, y, z
	if h.count < h.cap then
		h.count += 1
	end
end

-- seconds covered by the samples held
function PoseHistory.span(h: History): number
	if h.count < 2 then
		return 0
	end
	local oldest = (h.head - h.count) % h.cap + 1
	return h.ts[h.head] - h.ts[oldest]
end

function PoseHistory.sample(h: History, t: number): (number, number, number)
	local cap, ts = h.cap, h.ts
	local i = h.head
	if h.count == 0 then
		return 0, 0, 0
	end
	if t >= ts[i] then
		return h.xs[i], h.ys[i], h.zs[i]
	end
	-- walk back from the newest: a rewind is a few frames, so this is short
	for _ = 2, h.count do
		local j = if i == 1 then cap else i - 1
		local tj = ts[j]
		if t >= tj then
			local a = (t - tj) / (ts[i] - tj)
			return h.xs[j] + (h.xs[i] - h.xs[j]) * a,
				h.ys[j] + (h.ys[i] - h.ys[j]) * a,
				h.zs[j] + (h.zs[i] - h.zs[j]) * a
		end
		i = j
	end
	return h.xs[i], h.ys[i], h.zs[i] -- older than the window: the oldest sample
end

return PoseHistory
