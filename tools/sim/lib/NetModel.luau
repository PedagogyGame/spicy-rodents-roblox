--!strict
-- tools/sim/lib/NetModel: the seeded models between the server's send and the client's frame.
--   * the network: every VehiclePoses send gets a one-way delay (or is lost) from a profile:
--     base latency, jitter, independent loss, loss / delay bursts, reordering, duplicates
--   * the pacers: the length of every server frame (Heartbeat) and client frame (RenderStepped):
--     a frame rate, jitter, short spikes, long stalls / hitches
-- Everything is a setting; `NET`, `SERVER` and `CLIENT` hold the named profiles the command line offers.
-- Each model draws from its own seeded stream (Util/Rng, mulberry32), so a run repeats exactly and a
-- change to one model's settings never shifts another model's draws.
-- Interface: NET, SERVER, CLIENT (profiles); network(profile, seed) -> Network; Network:send(at) ->
--            { arrival... } (zero, one or two arrival times); pacer(profile, seed) -> Pacer; Pacer:next() -> dt
-- Pure. Times in seconds.

local Rng = require("@shared/Util/Rng")

local NetModel = {}

export type NetProfile = {
	latency: number, -- base one-way delay every packet has
	jitter: number, -- extra delay per packet: exponential with this mean, capped at 5 x
	loss: number, -- probability a packet is lost on its own
	burstEvery: number, -- mean seconds between bursts (0 = never); exponential gaps
	burstLength: number, -- seconds a burst lasts
	burstLoss: number, -- probability a packet sent in a burst is lost
	burstDelay: number, -- extra delay a packet sent in a burst gets (a stall, then they arrive bunched)
	reorder: number, -- probability a packet is held back by reorderDelay (it lands after later ones)
	reorderDelay: number,
	duplicate: number, -- probability a packet arrives twice (the copy 5 to 30 ms later)
}

-- stylua: ignore
NetModel.NET = {
	-- nothing between the server and the client: every incident is the game's own doing
	ideal   = { latency = 0,     jitter = 0,     loss = 0,    burstEvery = 0,  burstLength = 0,    burstLoss = 0,   burstDelay = 0,    reorder = 0,     reorderDelay = 0.1, duplicate = 0 },
	-- a good home connection
	good    = { latency = 0.030, jitter = 0.005, loss = 0.002, burstEvery = 0, burstLength = 0,    burstLoss = 0,   burstDelay = 0,    reorder = 0,     reorderDelay = 0.1, duplicate = 0 },
	-- the baseline "typical" player: 60 ms away, 20 ms of jitter, one packet in a hundred lost
	typical = { latency = 0.060, jitter = 0.020, loss = 0.01, burstEvery = 0,  burstLength = 0,    burstLoss = 0,   burstDelay = 0,    reorder = 0,     reorderDelay = 0.1, duplicate = 0 },
	-- wifi with a microwave on: short stalls where almost everything is lost, a little reordering
	wifi    = { latency = 0.045, jitter = 0.025, loss = 0.02, burstEvery = 20, burstLength = 0.30, burstLoss = 0.9, burstDelay = 0.05, reorder = 0.005, reorderDelay = 0.1, duplicate = 0 },
	-- a phone on a weak signal: far, noisy, lossy, bursts that delay rather than drop
	mobile  = { latency = 0.120, jitter = 0.060, loss = 0.04, burstEvery = 12, burstLength = 0.50, burstLoss = 0.5, burstDelay = 0.25, reorder = 0.02,  reorderDelay = 0.12, duplicate = 0.002 },
} :: { [string]: NetProfile }

export type PaceProfile = {
	hz: number, -- frames a second
	jitter: number, -- every frame is longer or shorter by up to this (uniform)
	spike: number, -- probability a frame is a spike
	spikeMin: number, -- a spike adds between these (seconds)
	spikeMax: number,
	stallEvery: number, -- mean seconds between long stalls (0 = never); exponential gaps
	stallMin: number, -- a stall adds between these (seconds)
	stallMax: number,
}

-- stylua: ignore
NetModel.SERVER = {
	-- an exact 60 Hz Heartbeat
	steady = { hz = 60, jitter = 0,      spike = 0,     spikeMin = 0,     spikeMax = 0,     stallEvery = 0,  stallMin = 0,    stallMax = 0 },
	-- a healthy live server: frames wander by 1.5 ms, now and then one takes 10 to 40 ms longer, and
	-- about once a minute something (a join, a save, a collection) holds the frame for 0.12 to 0.4 s
	live   = { hz = 60, jitter = 0.0015, spike = 0.004, spikeMin = 0.010, spikeMax = 0.040, stallEvery = 60, stallMin = 0.12, stallMax = 0.40 },
	-- a server that cannot hold 60: 40 Hz with wide jitter and frequent stalls
	strained = { hz = 40, jitter = 0.006, spike = 0.02, spikeMin = 0.015, spikeMax = 0.060, stallEvery = 15, stallMin = 0.15, stallMax = 0.60 },
} :: { [string]: PaceProfile }

-- stylua: ignore
NetModel.CLIENT = {
	-- exact frames at the chosen rate (--fps sets hz)
	steady = { hz = 60, jitter = 0,      spike = 0,     spikeMin = 0,     spikeMax = 0,     stallEvery = 0,  stallMin = 0,    stallMax = 0 },
	-- a real device: frames wander by 1 ms, an occasional dropped frame, a hitch every half minute
	live   = { hz = 60, jitter = 0.001,  spike = 0.005, spikeMin = 0.008, spikeMax = 0.034, stallEvery = 30, stallMin = 0.08, stallMax = 0.25 },
} :: { [string]: PaceProfile }

export type Network = {
	profile: NetProfile,
	stats: { sent: number, lost: number, burstLost: number, reordered: number, duplicated: number, bursts: number },
	send: (self: Network, at: number) -> { number },
}

local function expGap(rng: Rng.Rng, mean: number): number
	return -mean * math.log(1 - rng.next())
end

-- network(profile, seed): `send(at)` returns the arrival times of a packet sent at `at`: none (lost),
-- one, or two (duplicated). Call it in send order.
function NetModel.network(profile: NetProfile, seed: number): Network
	local rng = Rng.new(seed * 7919 + 101)
	local burstRng = Rng.new(seed * 7919 + 202)
	local burstFrom, burstTo = math.huge, math.huge
	local counted = -math.huge
	if profile.burstEvery > 0 then
		burstFrom = expGap(burstRng, profile.burstEvery)
		burstTo = burstFrom + profile.burstLength
	end
	local self: Network
	self = {
		profile = profile,
		stats = { sent = 0, lost = 0, burstLost = 0, reordered = 0, duplicated = 0, bursts = 0 },
		send = function(_self: Network, at: number): { number }
			local stats = self.stats
			stats.sent += 1
			-- the draws are made in a fixed order whatever happens, so one setting never shifts the rest
			local uLoss, uJitter, uBurst, uReorder, uDup, uDupDelay =
				rng.next(), rng.next(), rng.next(), rng.next(), rng.next(), rng.next()
			while at >= burstTo do
				burstFrom = burstTo + expGap(burstRng, profile.burstEvery)
				burstTo = burstFrom + profile.burstLength
			end
			local inBurst = at >= burstFrom
			if inBurst and counted ~= burstFrom then
				counted = burstFrom
				stats.bursts += 1
			end
			if uLoss < profile.loss then
				stats.lost += 1
				return {}
			end
			if inBurst and uBurst < profile.burstLoss then
				stats.lost += 1
				stats.burstLost += 1
				return {}
			end
			local delay = profile.latency + profile.jitter * math.min(5, -math.log(1 - uJitter))
			if inBurst then
				delay += profile.burstDelay
			end
			if uReorder < profile.reorder then
				delay += profile.reorderDelay
				stats.reordered += 1
			end
			local out = { at + delay }
			if uDup < profile.duplicate then
				stats.duplicated += 1
				table.insert(out, at + delay + 0.005 + 0.025 * uDupDelay)
			end
			return out
		end,
	}
	return self
end

export type Pacer = {
	profile: PaceProfile,
	stats: { frames: number, spikes: number, stalls: number, longest: number },
	next: (self: Pacer) -> number,
}

-- pacer(profile, seed): `next()` is the length of the next frame.
function NetModel.pacer(profile: PaceProfile, seed: number): Pacer
	local rng = Rng.new(seed * 104729 + 303)
	local stallRng = Rng.new(seed * 104729 + 404)
	local base = 1 / profile.hz
	local elapsed = 0
	local nextStall = if profile.stallEvery > 0 then expGap(stallRng, profile.stallEvery) else math.huge
	local self: Pacer
	self = {
		profile = profile,
		stats = { frames = 0, spikes = 0, stalls = 0, longest = 0 },
		next = function(_self: Pacer): number
			local stats = self.stats
			local uJitter, uSpike, uSize = rng.next(), rng.next(), rng.next()
			local dt = base + profile.jitter * (2 * uJitter - 1)
			if uSpike < profile.spike then
				dt += profile.spikeMin + (profile.spikeMax - profile.spikeMin) * uSize
				stats.spikes += 1
			end
			if elapsed >= nextStall then
				dt += profile.stallMin + (profile.stallMax - profile.stallMin) * stallRng.next()
				nextStall = elapsed + expGap(stallRng, profile.stallEvery)
				stats.stalls += 1
			end
			dt = math.max(dt, 0.001)
			elapsed += dt
			stats.frames += 1
			stats.longest = math.max(stats.longest, dt)
			return dt
		end,
	}
	return self
end

return NetModel
