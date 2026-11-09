--!strict
-- ReplicatedStorage.Shared.Net.Net
-- The single remote registry (BUILD_PLAN §1.6): only names declared in Net/Schemas exist; every inbound
-- payload is schema-checked and rate-limited by a per-player token bucket; a rejected packet is logged
-- (rate-limited) and dropped, never erroring the server; handler errors are caught. The transport is
-- injected: the engine binder (Net.engineTransport) maps names to RemoteEvent / UnreliableRemoteEvent
-- instances; Lune tests use a loopback. No side effects on require.
-- Interface: new(transport, opts?) -> Net; Net:on(name, fn(player, payload)); Net:receive(player, name,
--            payload, now?) -> (ok, reason?) (transport inbound hook); Net:fire(player, name, payload);
--            Net:fireAll(name, payload); Net:fireNear(x, z, radius, name, payload); Net:stream(player?,
--            name, records) (buffer remotes); Net:stats()

local Log = require("../Util/Log")
local Schema = require("../Util/Schema")
local BufferCodec = require("../Util/BufferCodec")
local Schemas = require("./Schemas")

export type Transport = {
	send: (player: any?, name: string, payload: any) -> (), -- player nil = everyone
	players: () -> { any },
	positionOf: ((player: any) -> (number?, number?))?, -- x, z of the player's body (fireNear)
	isDev: ((player: any) -> boolean)?,
}

export type Stats = { received: number, rejected: { [string]: number }, sent: number, bytes: number }

export type Net = {
	transport: Transport,
	clock: () -> number,
	handlers: { [string]: (player: any, payload: any) -> () },
	buckets: { [any]: { [string]: { tokens: number, at: number } } },
	log: Log.Logger,
	_stats: Stats,
	on: (self: Net, name: string, fn: (player: any, payload: any) -> ()) -> (),
	receive: (self: Net, player: any, name: string, payload: any, now: number?) -> (boolean, string?),
	fire: (self: Net, player: any, name: string, payload: any) -> (),
	fireAll: (self: Net, name: string, payload: any) -> (),
	fireNear: (self: Net, x: number, z: number, radius: number, name: string, payload: any) -> number,
	stream: (self: Net, player: any?, name: string, records: { { [string]: number } }) -> buffer,
	forget: (self: Net, player: any) -> (),
	stats: (self: Net) -> Stats,
}

local Net = {}

local function def(name: string): Schemas.Def
	local d = Schemas.REMOTES[name]
	if not d then
		error(`Net: undeclared remote '{name}' (declare it in Net/Schemas)`, 3)
	end
	return d
end

-- Decodes a buffer payload of `layout`-sized records.
function Net.decodeStream(layout: BufferCodec.Layout, b: buffer): { { [string]: number } }
	local n = buffer.len(b) // layout.size
	local out = {}
	for i = 0, n - 1 do
		out[i + 1] = BufferCodec.decode(layout, b, i * layout.size)
	end
	return out
end

function Net.new(transport: Transport, opts: { clock: (() -> number)? }?): Net
	local o = (opts or {}) :: { clock: (() -> number)? }
	local net = {
		transport = transport,
		clock = o.clock or os.clock,
		handlers = {},
		buckets = {},
		log = Log.new("Net"),
		_stats = { received = 0, rejected = {}, sent = 0, bytes = 0 },
	} :: Net

	local function reject(self: Net, player: any, name: string, reason: string): (boolean, string?)
		self._stats.rejected[reason] = (self._stats.rejected[reason] or 0) + 1
		local who = if type(player) == "table" or typeof(player) == "Instance" then tostring(player.UserId) else "?"
		self.log:every(`{who}:{name}:{reason}`, 5, "warn", `dropped {name} from {who}: {reason}`)
		return false, reason
	end

	function net.on(self: Net, name: string, fn: (player: any, payload: any) -> ())
		local d = def(name)
		assert(d.dir == "c2s", `Net.on: {name} is server-to-client`)
		self.handlers[name] = fn
	end

	function net.receive(self: Net, player: any, name: string, payload: any, now: number?): (boolean, string?)
		local d = Schemas.REMOTES[name]
		if not d or d.dir ~= "c2s" then
			return reject(self, player, tostring(name), "unknown remote")
		end
		if d.devOnly and not (self.transport.isDev and self.transport.isDev(player)) then
			return reject(self, player, name, "dev only")
		end
		-- token bucket
		local t = now or self.clock()
		local rate = d.rate or 10
		local burst = d.burst or math.max(2, rate * 2)
		local perPlayer = self.buckets[player]
		if not perPlayer then
			perPlayer = {}
			self.buckets[player] = perPlayer
		end
		local b = perPlayer[name]
		if not b then
			b = { tokens = burst, at = t }
			perPlayer[name] = b
		end
		b.tokens = math.min(burst, b.tokens + (t - b.at) * rate)
		b.at = t
		if b.tokens < 1 then
			return reject(self, player, name, "rate")
		end
		b.tokens -= 1
		-- shape
		local value = payload
		if d.layout then
			if typeof(payload) ~= "buffer" or buffer.len(payload) ~= d.layout.size then
				return reject(self, player, name, "bad buffer")
			end
			value = BufferCodec.decode(d.layout, payload)
			for _, v in value do
				if v ~= v or v == math.huge or v == -math.huge then
					return reject(self, player, name, "non-finite")
				end
			end
		elseif d.payload then
			local ok = Schema.check(d.payload, payload)
			if not ok then
				return reject(self, player, name, "schema")
			end
		end
		self._stats.received += 1
		local handler = self.handlers[name]
		if handler then
			local ok, err = pcall(handler :: any, player, value)
			if not ok then
				self.log:every(`handler:{name}`, 5, "error", `handler {name} errored: {err}`)
				return false, "handler error"
			end
		end
		return true
	end

	local function send(self: Net, player: any?, name: string, payload: any)
		local d = def(name)
		assert(d.dir == "s2c", `Net: {name} is client-to-server`)
		self._stats.sent += 1
		if typeof(payload) == "buffer" then
			self._stats.bytes += buffer.len(payload)
		end
		self.transport.send(player, name, payload)
	end

	function net.fire(self: Net, player: any, name: string, payload: any)
		send(self, player, name, payload)
	end

	function net.fireAll(self: Net, name: string, payload: any)
		send(self, nil, name, payload)
	end

	function net.fireNear(self: Net, x: number, z: number, radius: number, name: string, payload: any): number
		def(name)
		local posOf = self.transport.positionOf
		assert(posOf, "Net.fireNear: transport has no positionOf")
		local n, r2 = 0, radius * radius
		for _, p in self.transport.players() do
			local px, pz = posOf(p)
			if px and pz and (px - x) ^ 2 + (pz - z) ^ 2 <= r2 then
				send(self, p, name, payload)
				n += 1
			end
		end
		return n
	end

	function net.stream(self: Net, player: any?, name: string, records: { { [string]: number } }): buffer
		local d = def(name)
		local layout = d.layout or (if name == "VehiclePoses" then Schemas.VehiclePose else nil)
		assert(layout, `Net.stream: {name} has no buffer layout`)
		local b = buffer.create(layout.size * #records)
		for i, rec in records do
			BufferCodec.encode(layout, rec, b, (i - 1) * layout.size)
		end
		send(self, player, name, b)
		return b
	end

	function net.forget(self: Net, player: any)
		self.buckets[player] = nil
	end

	function net.stats(self: Net): Stats
		return self._stats
	end

	return net
end

-- Engine binder (server side): one folder ReplicatedStorage.Net with a RemoteEvent or
-- UnreliableRemoteEvent per declared remote; inbound OnServerEvent feeds net:receive. Called by the
-- server's init, never on require.
function Net.engineServer(isDev: ((player: any) -> boolean)?, positionOf: ((player: any) -> (number?, number?))?): Net
	local Players = game:GetService("Players")
	local folder = Instance.new("Folder")
	folder.Name = "Net"
	local remotes: { [string]: Instance } = {}
	local names: { string } = {}
	for name in Schemas.REMOTES do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local d = Schemas.REMOTES[name]
		local r = Instance.new(if d.reliable then "RemoteEvent" else "UnreliableRemoteEvent")
		r.Name = name
		r.Parent = folder
		remotes[name] = r
	end
	local transport: Transport = {
		send = function(player: any?, name: string, payload: any)
			local r = remotes[name] :: any
			if player then
				r:FireClient(player, payload)
			else
				r:FireAllClients(payload)
			end
		end,
		players = function()
			return Players:GetPlayers()
		end,
		positionOf = positionOf,
		isDev = isDev,
	}
	local net = Net.new(transport)
	for _, name in names do
		if Schemas.REMOTES[name].dir == "c2s" then
			(remotes[name] :: any).OnServerEvent:Connect(function(player: Player, payload: any)
				net:receive(player, name, payload)
			end)
		end
	end
	folder.Parent = game:GetService("ReplicatedStorage")
	Players.PlayerRemoving:Connect(function(player: Player)
		net:forget(player)
	end)
	return net
end

return Net
