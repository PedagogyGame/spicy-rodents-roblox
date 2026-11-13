--!strict
-- ReplicatedStorage.Shared.Minigames.AirHockey.Replica
-- The referee's match as someone else holds it: the stream's messages (Wire's "air_hockey") queued as they
-- arrive and replayed tick by tick through the same simulation, so that what is held is exactly what the
-- server decided, at every tick and not only at the end of each message.
-- A seated player replays at once (step(r) to the newest tick): theirs is the state their own prediction is
-- checked against. A watcher replays a little behind the newest tick, at the pace of their own frames
-- (step(r, upToTick)), which is how the puck moves smoothly on a screen that is sent fifteen messages a second.
-- Anyone can start from any message: a message that does not carry on from what is held (the first one, another
-- match, a gap) is taken as it stands. If a replay ever ends somewhere other than the state its message carries,
-- the message wins (and `desyncs` counts it: the specs hold that at zero).
-- Pure. Interface: new() -> Replica; push(r, msg) -> bool (false: not a stream message); step(r, upTo?, onTick?)
--   -> ticks stepped (onTick(sim, tick, hit, goal) after each: hit / goal say the tick had a contact / a goal);
--   Replica.sim / .tick (the state held and its tick) / .head (the newest tick known) / .game / .t0 / .mode /
--   .jumps (times a message was taken as it stands) / .desyncs

local Sim = require("./Sim")
local Wire = require("./Wire")

local Replica = {}

export type Replica = {
	sim: Sim.State,
	tick: number,
	head: number,
	game: number?,
	t0: number,
	mode: string,
	queue: { any }, -- messages not yet replayed to their end
	events: { [number]: { [number]: any } }?, -- the front message's events, by side then tick
	jumps: number,
	desyncs: number,
}

function Replica.new(): Replica
	return {
		sim = Sim.new(),
		tick = 0,
		head = 0,
		game = nil,
		t0 = 0,
		mode = "",
		queue = {},
		events = nil,
		jumps = 0,
		desyncs = 0,
	}
end

local function sound(msg: any): boolean
	return type(msg) == "table"
		and type(msg.g) == "number"
		and type(msg.n0) == "number"
		and type(msg.n) == "number"
		and msg.n >= msg.n0
		and msg.n - msg.n0 <= 4 * Wire.MAX_SEGMENT
		and type(msg.m) == "string"
		and type(msg.a) == "string"
		and type(msg.b) == "string"
		and type(msg.t0) == "number"
		and type(msg.s) == "table"
end

function Replica.push(r: Replica, msg: any): boolean
	if not sound(msg) then
		return false
	end
	if msg.g ~= r.game or msg.n0 ~= r.head then
		-- not the next stretch of what is held: take it as it stands
		if not Wire.load(r.sim, msg.s) then
			return false
		end
		r.game = msg.g
		r.tick, r.head = msg.n, msg.n
		r.t0, r.mode = msg.t0, msg.m
		table.clear(r.queue)
		r.events = nil
		r.jumps += 1
		return true
	end
	r.t0 = msg.t0
	-- (a message of no ticks is the state as it stands at the head: who plays which end, or the computer's
	-- difficulty, changed there. It is taken in its turn, like any other)
	table.insert(r.queue, msg)
	r.head = msg.n
	return true
end

-- Messages of no ticks at the front of the queue, once the replay has reached them.
local function standing(r: Replica)
	local msg = r.queue[1]
	while msg ~= nil and msg.n == msg.n0 and msg.n == r.tick do
		Wire.load(r.sim, msg.s)
		r.mode = msg.m
		table.remove(r.queue, 1)
		r.events = nil
		msg = r.queue[1]
	end
end

function Replica.step(
	r: Replica,
	upTo: number?,
	onTick: ((sim: Sim.State, tick: number, hit: boolean, goal: boolean) -> ())?
): number
	local limit = math.min(upTo or r.head, r.head)
	local sim = r.sim
	local stepped = 0
	standing(r)
	while r.tick < limit do
		local msg = r.queue[1]
		if msg == nil then
			break
		end
		local events = r.events
		if events == nil then
			local a = Wire.unpack({ msg.a }, msg.n0, msg.n)
			local b = Wire.unpack({ msg.b }, msg.n0, msg.n)
			events = { [0] = a or {}, [1] = b or {} }
			r.events = events
			r.mode = msg.m
		end
		local human = if msg.m == "1" then 1 else 0
		local computer = msg.m ~= "2"
		local stop = math.min(limit, msg.n)
		while r.tick < stop do
			local tick = r.tick + 1
			for side = 0, 1 do
				local e = (events :: any)[side][tick]
				if e then
					if e[3] and sim.countdown > 0 then
						Sim.serve(sim)
					end
					if e[1] then
						local x, y = Wire.target(side, e[1], e[2])
						Sim.setTarget(sim, side, x, y)
					end
				end
			end
			local hits, goals = sim.hitSerial, sim.goalSerial
			Sim.play(sim, human, computer)
			r.tick = tick
			stepped += 1
			if onTick then
				onTick(sim, tick, sim.hitSerial ~= hits, sim.goalSerial ~= goals)
			end
		end
		if r.tick >= msg.n then
			if not Wire.same(sim, msg.s) then
				r.desyncs += 1
				Wire.load(sim, msg.s)
			end
			table.remove(r.queue, 1)
			r.events = nil
			standing(r)
		end
	end
	return stepped
end

return Replica
