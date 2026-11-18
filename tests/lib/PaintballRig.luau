--!strict
-- tests/lib/PaintballRig.luau: paintball's five remotes beside tests/lib/MinigameRig. Part of the paintball
-- contract (src/shared/Minigames/Paintball/Contract): FROZEN, so that the server lane's cases and the client
-- lane's cases put the same wire between a client and a service, and the two halves meet on it unchanged.
-- MinigameRig carries Minigame.Input and Minigame.State and fails a case whose game touches any other remote
-- through the service's net. Paintball's stream does not go through the service's net: the service is handed a
-- Port (PaintballService.Port, as the MinigameService option `paintball`), and this is one. Each way a message
-- is a copy that arrives `lag` frames later:
--   up    the client fires the fake RemoteEvents this makes under ReplicatedStorage.Net ("Paintball.Move",
--         "Paintball.Fire"); every buffer goes through the REAL Shared/Net first (its layout, its finite check
--         and its rate limit, on the rig's clock) and reaches the handler the service gave the Port as a
--         decoded record. A message Net refuses breaks the case, as MinigameRig does for Minigame.Input.
--   down  what the service fires at the rig's player ("Paintball.Snap", "Paintball.Shot", "Splat") arrives
--         on that remote's OnClientEvent; an unreliable one may be lost first (opts.lose). What it fires at
--         a PlayerLike stub is kept in stub.streams[remote].
-- A case: local wires = PaintballRig.new(); MinigameRig.play(function(w) PaintballRig.attach(wires, w) ...
-- PaintballRig.run(wires, w, 2) ... end, PaintballRig.opts(wires)). Step the world with PaintballRig.frame /
-- run / untilTrue, never MinigameRig's own, or the stream stands still.
-- ONLY IN AN ISOLATED RUN (tests/lib/Isolated; cases under tests/isolated/).
-- Interface: new(opts?) -> Wires (opts: lag frames each way, default 3; lose(remote, n) -> boolean for the nth
--   unreliable message down); opts(wires, more?) -> MinigameRig.Opts (the TV station as the one site, the arena's
--   model on it, the player standing at the arena door, the Port as the service's `paintball` option; `more`
--   overrides any of it, and its `paintball` table is merged under the Port); furnish(roots) (the arena's model:
--   what opts passes as `furnish`); attach(wires, w) (the remotes; call first in the case); frame(wires, w);
--   run(wires, w, seconds); untilTrue(wires, w, limit, cond) -> boolean; send(wires, player, remote, record) ->
--   (ok, reason?) (a stub's Move or Fire, straight through Net); table(w) -> paintball's Table at the arena's
--   station (its .service is the PaintballService); PLACE; SITE; wires.got[remote] = every payload the rig's
--   player was sent; wires.heard[remote] = every record the service was handed
local Arena = require("@shared/Minigames/Paintball/Arena")
local Contract = require("@shared/Minigames/Paintball/Contract")
local BufferCodec = require("@shared/Util/BufferCodec")
local FakeEngine = require("@tests/lib/FakeEngine")
local Rig = require("@tests/lib/MinigameRig")
local roblox = require("@lune/roblox")

local PaintballRig = {}

PaintballRig.SITE = Contract.SITE
-- the TV station where the data has it (generated/Expansion: centre 2080, -890, floor 8.6, yaw 0)
PaintballRig.PLACE = { x = 2080, z = -890, floorY = 8.6, yaw = 0 } :: Rig.Place

local UP = { "Paintball.Move", "Paintball.Fire" }
local DOWN = { "Paintball.Snap", "Paintball.Shot", "Splat" }

export type Port = {
	on: (remote: string, fn: (player: any, record: { [string]: number }) -> ()) -> (),
	fire: (player: any, remote: string, payload: buffer) -> (),
}
export type Opts = { lag: number?, lose: ((remote: string, n: number) -> boolean)? }
export type Wires = {
	port: Port,
	lag: number,
	lose: ((remote: string, n: number) -> boolean)?,
	world: Rig.World?,
	gate: any?, -- the real Shared/Net the client's messages go through
	handlers: { [string]: (player: any, record: { [string]: number }) -> () },
	remotes: { [string]: any },
	up: { { at: number, remote: string, payload: buffer } },
	down: { { at: number, remote: string, payload: buffer } },
	sentDown: { [string]: number },
	got: { [string]: { buffer } },
	heard: { [string]: { { [string]: number } } },
}

local function copy(b: buffer): buffer
	local out = buffer.create(buffer.len(b))
	buffer.copy(out, 0, b)
	return out
end

function PaintballRig.new(opts: Opts?): Wires
	local o: Opts = opts or {}
	local wires: Wires
	local port: Port = {
		on = function(remote: string, fn: (player: any, record: { [string]: number }) -> ())
			assert(table.find(UP, remote), `PaintballRig: the service listened on {remote}`)
			wires.handlers[remote] = fn
		end,
		fire = function(player: any, remote: string, payload: buffer)
			assert(table.find(DOWN, remote), `PaintballRig: the service fired {remote}`)
			assert(typeof(payload) == "buffer", `PaintballRig: {remote} carries buffers`)
			local w = wires.world
			if w == nil or player ~= w.player then
				if type(player) == "table" then
					player.streams = player.streams or {}
					player.streams[remote] = player.streams[remote] or {}
					table.insert(player.streams[remote], copy(payload))
				end
				return
			end
			local n = (wires.sentDown[remote] or 0) + 1
			wires.sentDown[remote] = n
			local reliable = remote == "Splat"
			if not reliable and wires.lose and wires.lose(remote, n) then
				return
			end
			if not reliable and buffer.len(payload) > 900 and #w.broken < 5 then
				table.insert(w.broken, `{remote}: {buffer.len(payload)} bytes in one unreliable message`)
			end
			table.insert(wires.down, { at = w.frames + wires.lag, remote = remote, payload = copy(payload) })
		end,
	}
	wires = {
		port = port,
		lag = o.lag or 3,
		lose = o.lose,
		world = nil,
		gate = nil,
		handlers = {},
		remotes = {},
		up = {},
		down = {},
		sentDown = {},
		got = {},
		heard = {},
	}
	return wires
end

-- The arena's "furniture": the model the bake leaves under the site's Model.
function PaintballRig.furnish(roots: { [string]: any })
	local root = roots[PaintballRig.SITE]
	if root then
		local at = roblox.CFrame.new(Arena.toWorld(Arena.placeOf(PaintballRig.PLACE), 0, 0, 0))
		FakeEngine.model(Arena.MODEL, at, root)
	end
end

function PaintballRig.opts(wires: Wires, more: { [string]: any }?): Rig.Opts
	local gx, gy, gd = Arena.toSite(Arena.GATE.x, Arena.GATE.y + 3, Arena.GATE.z + 4)
	local o: { [string]: any } = {
		sites = { [PaintballRig.SITE] = PaintballRig.PLACE },
		furnish = PaintballRig.furnish,
		stand = { site = PaintballRig.SITE, x = gx, y = gy, d = gd },
		service = {},
	}
	for k, v in more or {} do
		o[k] = v
	end
	local service: { [string]: any } = table.clone(o.service or {})
	local paintball: { [string]: any } = table.clone(service.paintball or {})
	paintball.port = wires.port
	service.paintball = paintball
	o.service = service
	return o :: any
end

-- Make the remotes and join them to the world. Call first in the case (the service was built before it, and
-- has already given the Port its handlers).
function PaintballRig.attach(wires: Wires, w: Rig.World)
	wires.world = w
	local Net = (require :: any)("@shared/Net/Net")
	local gate = Net.new({
		send = function() end,
		players = function(): { any }
			return {}
		end,
	}, {
		clock = function(): number
			return w.frames / 60
		end,
	})
	wires.gate = gate
	for _, remote in UP do
		gate:on(remote, function(player: any, record: { [string]: number })
			wires.heard[remote] = wires.heard[remote] or {}
			table.insert(wires.heard[remote], record)
			local handler = wires.handlers[remote]
			if handler then
				handler(player, record)
			end
		end)
	end
	local folder = (game :: any):GetService("ReplicatedStorage"):FindFirstChild("Net")
	for _, remote in UP do
		local r = FakeEngine.new(if remote == "Paintball.Move" then "UnreliableRemoteEvent" else "RemoteEvent", remote)
		r.Parent = folder
		wires.remotes[remote] = r
		rawset(r, "FireServer", function(_self: any, payload: any)
			if typeof(payload) ~= "buffer" then
				table.insert(w.broken, `the client sent {remote} something that is not a buffer`)
				return
			end
			table.insert(wires.up, { at = w.frames + wires.lag, remote = remote, payload = copy(payload) })
		end)
	end
	for _, remote in DOWN do
		local r = FakeEngine.new(if remote == "Splat" then "RemoteEvent" else "UnreliableRemoteEvent", remote)
		r.Parent = folder
		wires.remotes[remote] = r
	end
end

local function deliver(wires: Wires, w: Rig.World)
	while wires.up[1] and wires.up[1].at <= w.frames + 1 do
		local m = table.remove(wires.up, 1) :: { at: number, remote: string, payload: buffer }
		local ok, reason = (wires.gate :: any):receive(w.player, m.remote, m.payload)
		if not ok and #w.broken < 5 then
			table.insert(w.broken, `frame {w.frames}: Net dropped the client's {m.remote} ({tostring(reason)})`)
		end
	end
end

local function arrive(wires: Wires, w: Rig.World)
	while wires.down[1] and wires.down[1].at <= w.frames + 1 do
		local m = table.remove(wires.down, 1) :: { at: number, remote: string, payload: buffer }
		wires.got[m.remote] = wires.got[m.remote] or {}
		table.insert(wires.got[m.remote], m.payload)
		wires.remotes[m.remote].OnClientEvent.fire(m.payload)
	end
end

-- One frame of the whole game with the stream: what the client fired `lag` frames ago reaches the service
-- before it steps, and what the service fired `lag` frames ago reaches the client before it draws.
function PaintballRig.frame(wires: Wires, w: Rig.World)
	assert(wires.world == w, "PaintballRig.attach(wires, w) first")
	deliver(wires, w)
	arrive(wires, w)
	Rig.frame(w)
end

function PaintballRig.run(wires: Wires, w: Rig.World, seconds: number)
	for _ = 1, math.max(1, math.floor(seconds * 60 + 0.5)) do
		PaintballRig.frame(wires, w)
	end
end

function PaintballRig.untilTrue(wires: Wires, w: Rig.World, limit: number, cond: () -> boolean): boolean
	for _ = 1, math.floor(limit * 60) do
		if cond() then
			return true
		end
		PaintballRig.frame(wires, w)
	end
	return cond()
end

-- A stub's Move or Fire record, encoded with its layout and put straight through Net to the service.
function PaintballRig.send(wires: Wires, player: any, remote: string, record: { [string]: number }): (boolean, string?)
	local Schemas = (require :: any)("@shared/Net/Schemas")
	local layout = Schemas.REMOTES[remote].layout
	return (wires.gate :: any):receive(player, remote, BufferCodec.encode(layout, record))
end

-- Paintball's Table at the arena's station (its `service` is the PaintballService).
function PaintballRig.table(w: Rig.World): any
	local st = w.svc.stations[Contract.STATION]
	return st and st.tbl
end

return PaintballRig
