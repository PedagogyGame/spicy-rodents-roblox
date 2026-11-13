--!strict
-- tests/lib/MinigameRig.luau: a whole minigame on the fake engine, for any game in the registry. The real
-- Server/Minigames/MinigameService and the real Client/Minigames/MinigameClient (with MinigameUI and the game's
-- own halves from the registries) are joined by a fake network that carries each side's messages to the other
-- a few frames late, as plain copies, with everything the client sends put through the real Shared/Net first:
-- its schema and its rate limit (Minigame.Input: 20 a second, 40 at once), on the rig's own clock. The
-- player is the fake engine's LocalPlayer with a body; other people are PlayerLike stubs (stub()).
-- A case: MinigameRig.play(function(w) ... end, opts). The world is built fresh; however the case ends the main
-- client's hooks are put back, and a case never passes with a warning logged (the client swallows its own
-- errors into warnings) or a rule broken on the way: the camera moved while CameraRig was not held, hold called
-- twice in a row, a payload the Net schema refuses, a message the Net's rate limit would have dropped (on a real
-- server it vanishes without a word, so a controller that sends one a frame fails here), a game using a remote
-- other than Minigame.Input / Minigame.State.
-- Two clocks, as in the game: the service's own (ctx.now(): seconds of stepping, from 0) and the shared one
-- (workspace:GetServerTimeNow, which ctx.stamp() reads on both sides: 1000 + frames / 60 here). A game that
-- mixes them is wrong by a thousand seconds on the rig, as it would be wrong by the server's uptime in the game.
-- ONLY IN AN ISOLATED RUN (tests/lib/Isolated; cases under tests/isolated/): it installs FakeEngine.
-- opts: sites = { [siteId]: Place } (default: the bowling alley where the compiled data puts it); furnish(roots)
--   builds what the game's hardware looks for under each site's Model (roots[siteId], already under
--   Workspace.Attractions with the bake's Site / Origin attributes); stand = { site, x, y, d } where the
--   player's body starts (default: the first site's origin, 3 up); service = extra MinigameService opts; lag
--   (frames each way, default 3); seed; touch (a touch device). The service's opts.games.people lists the
--   player and whoever a case adds to w.people ({ key, name, x, y, z }); body / best are the service's own
--   stand-ins unless opts.service.games says otherwise. charge is the REAL wallet (w.wallet: a
--   Server/Economy/Credits of the rig's own, wired as Boot/Game wires the town's), so every game played on
--   the rig is played with real money behind ctx.town.charge: the player has the game's pocket money
--   (S$3.00), and anyone else a game charges is joined first, as everyone in the game has been.
-- Interface: play(fn, opts?); frame(w); run(w, seconds); untilTrue(w, limit, cond) -> bool; press(w, stationId)
--   (the station's prompt is triggered by the player); prompt(w, stationId) -> ProximityPrompt; walkTo(w, site,
--   x, y, d); texts(root) -> { string } (every word drawn, nothing hidden); has(list, needle); screen(w) ->
--   string; button(root, text); click(w, text); key(code, down, processed?); mouse(down, processed?);
--   touch(id, kind "began" | "changed" | "ended", x, y, processed?) (a finger: one InputObject from began to
--   ended, as the engine gives); last(list, kind, pred?) -> message?; count(list, kind) -> number; stub(name) ->
--   PlayerLike; SERVER_TIME (what the shared clock reads at frame 0);
--   input(w, player, stationId, verb, args?) -> (ok, why?) (a stub's input, straight into the service);
--   wire(value, path) -> a copy as a RemoteEvent would carry it (errors on what one cannot); DT
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Data = require("@shared/Data")
local Schema = require("@shared/Util/Schema")
local Sites = require("@shared/Minigames/Sites")
local Credits = require("@server/Economy/Credits")
local MinigameService = require("@server/Minigames/MinigameService")
local CameraRig = require("@client/Camera/CameraRig")
local InputMap = require("@client/Input/InputMap")
local MinigameClient = require("@client/Minigames/MinigameClient")
local FakeEngine = require("@tests/lib/FakeEngine")
local roblox = require("@lune/roblox")

local MinigameRig = {}

MinigameRig.DT = 1 / 60
MinigameRig.SERVER_TIME = 1000
local Kind = roblox.Enum.UserInputType

export type Place = AlleyLayout.Place
export type Opts = {
	sites: { [string]: Place }?,
	furnish: ((roots: { [string]: any }, places: { [string]: Place }) -> ())?,
	stand: { site: string, x: number, y: number, d: number }?,
	service: { [string]: any }?,
	lag: number?,
	seed: number?,
	touch: boolean?,
}
export type World = {
	svc: any,
	client: any,
	places: { [string]: Place },
	roots: { [string]: any }, -- each site's Model under Workspace.Attractions
	player: any,
	wallet: Credits.Wallet, -- the money behind ctx.town.charge (the player has joined: pocket money)
	body: any,
	gui: any, -- PlayerGui.MinigameUI
	input: any, -- the Minigame.Input remote
	state: any, -- the Minigame.State remote
	handler: ((player: any, payload: any) -> ())?,
	heartbeat: any,
	handlers: { [string]: (player: any, payload: any) -> () }, -- what the service asked the net for, by remote
	people: { any }, -- others in the town with a body, for opts.games.people (the player is always listed)
	lag: number,
	up: { any },
	down: { any },
	sent: { any }, -- every payload the client sent, in order
	got: { any }, -- every payload the client was sent, in order
	frames: number,
	toasts: { string },
	warnings: { string },
	broken: { string }, -- rules broken on the way (checked when the case ends)
	camWas: any,
	refreshed: number,
	flushed: number,
	species: string, -- "human"; anything else and canPlay refuses the player
	held: boolean, -- CameraRig.hold as the game last set it
	holds: { boolean },
	cursors: { [string]: boolean }, -- who has asked CameraRig for the cursor
	controls: { boolean }, -- every hand-over of the player's legs (false = taken)
}

-- A message as it would arrive over a RemoteEvent: a copy, and only what a remote carries faithfully (plain
-- values; tables that are either lists or string-keyed records).
function MinigameRig.wire(v: any, path: string): any
	local kind = type(v)
	if kind == "table" then
		assert(getmetatable(v) == nil, `{path}: an object, not plain data`)
		local n = #v
		local out = {}
		for k, item in v do
			if type(k) == "number" then
				assert(k >= 1 and k <= n and k % 1 == 0, `{path}: a list with a gap or a stray index ({k})`)
			else
				assert(type(k) == "string" and n == 0, `{path}: a table that mixes a list with named keys ({k})`)
			end
			out[k] = MinigameRig.wire(item, `{path}.{k}`)
		end
		return out
	end
	assert(kind == "number" or kind == "string" or kind == "boolean" or kind == "nil", `{path}: a {kind}`)
	return v
end

local function build(opts: Opts?): World
	local o: Opts = opts or {}
	local places: { [string]: Place } = {}
	local order: { string } = {}
	if o.sites then
		for id, place in o.sites do
			places[id] = place
			table.insert(order, id)
		end
		table.sort(order)
	else
		places.bowling_alley = Sites.fromData(Data.default(), false).bowling_alley
		order = { "bowling_alley" }
	end
	-- Workspace.Attractions.<site>, as the bake leaves it
	local folder = FakeEngine.new("Folder", "Attractions")
	folder.Parent = workspace
	local roots: { [string]: any } = {}
	local sites: { [string]: any } = {}
	for _, id in order do
		local place = places[id]
		local root = FakeEngine.new("Model", if id == "bowling_alley" then "BowlingAlley" else id)
		root:SetAttribute("AttractionId", id)
		root:SetAttribute("Site", id)
		root:SetAttribute("OriginX", place.x)
		root:SetAttribute("OriginZ", place.z)
		root:SetAttribute("FloorY", place.floorY)
		root:SetAttribute("Yaw", place.yaw)
		root.Parent = folder
		roots[id] = root
		sites[id] = { root = root, place = place }
	end
	if o.furnish then
		o.furnish(roots, places)
	end
	-- the remotes
	local rs = (game :: any):GetService("ReplicatedStorage")
	local net = FakeEngine.new("Folder", "Net")
	net.Parent = rs
	local input = FakeEngine.new("RemoteEvent", "Minigame.Input")
	input.Parent = net
	local state = FakeEngine.new("RemoteEvent", "Minigame.State")
	state.Parent = net
	-- the player: a person
	local player = (game :: any):GetService("Players").LocalPlayer
	rawset(player, "DisplayName", "Ann")
	local stand = o.stand or { site = order[1], x = 0, y = 3, d = 0 }
	local at = roblox.CFrame.new(AlleyLayout.toWorld(places[stand.site], stand.x, stand.y, stand.d))
	local body = FakeEngine.model("Ann", at, nil)
	body.PrimaryPart = FakeEngine.part("HumanoidRootPart", at, body)
	if o.touch then
		local uis = FakeEngine.uis()
		uis.TouchEnabled, uis.MouseEnabled, uis.KeyboardEnabled = true, false, false
	end

	local w: World = {
		svc = nil,
		client = nil,
		places = places,
		roots = roots,
		player = player,
		wallet = nil :: any,
		body = body,
		gui = nil,
		input = input,
		state = state,
		handler = nil,
		heartbeat = (game :: any):GetService("RunService").Heartbeat,
		handlers = {},
		people = {},
		lag = o.lag or 3,
		up = {},
		down = {},
		sent = {},
		got = {},
		frames = 0,
		toasts = {},
		warnings = {},
		broken = {},
		camWas = workspace.CurrentCamera.CFrame,
		refreshed = 0,
		flushed = 0,
		species = "human",
		held = false,
		holds = {},
		cursors = {},
		controls = {},
	}
	-- the town's wallet, on a game clock that runs with the rig's frames (it opens on day 9, as the game does)
	w.wallet = Credits.new({
		gameSeconds = function(): number
			return 9 * 720 + w.frames / 60
		end,
		daySeconds = 720,
		log = function() end,
	})
	w.wallet.join(player)
	-- the clock both sides share (ctx.stamp on the server, Ctx.stamp on the client): never the service's own
	rawset(workspace, "GetServerTimeNow", function(_self: any): number
		return MinigameRig.SERVER_TIME + w.frames / 60
	end)
	-- what the client fires arrives at the server a few frames later, if the real Net lets it through: its schema
	-- and its rate limit. (Both are read here, not as this file loads: a spec that registers a game of its own
	-- first finds that game's verbs on the wire.)
	local Schemas = (require :: any)("@shared/Net/Schemas")
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
	rawset(input, "FireServer", function(_self: any, payload: any)
		local ok, why = Schema.check(Schemas.REMOTES["Minigame.Input"].payload :: any, payload)
		if not ok then
			table.insert(w.broken, `the client sent a payload the Net schema refuses: {tostring(why)}`)
			return
		end
		local passed, reason = gate:receive(player, "Minigame.Input", payload)
		if not passed then
			if #w.broken < 5 then
				table.insert(
					w.broken,
					`frame {w.frames}: the Net dropped the client's "{tostring(payload.verb)}" ({tostring(reason)}): `
						.. "Minigame.Input carries 20 messages a second (40 at once) and a dropped one is never "
						.. "answered. Send a stream as segments, about ten a second"
				)
			end
			return
		end
		local copy = MinigameRig.wire(payload, "Minigame.Input")
		table.insert(w.sent, copy)
		table.insert(w.up, { at = w.frames + w.lag, payload = copy })
	end)
	local function toClient(payload: any)
		table.insert(w.down, { at = w.frames + w.lag, payload = MinigameRig.wire(payload, "Minigame.State") })
	end
	local serviceOpts: { [string]: any } = {
		sites = sites,
		seed = o.seed or 7,
		net = {
			-- (by remote: only Minigame.Input and Minigame.State are carried. A game speaks through its verbs and
			-- through ctx.send / broadcast / everyone; a remote of its own could not be played here)
			on = function(_self: any, name: string, fn: (player: any, payload: any) -> ())
				w.handlers[name] = fn
				if name == "Minigame.Input" then
					w.handler = fn
				else
					table.insert(w.broken, `the server listened on {name}: the rig carries Minigame.Input only`)
				end
			end,
			fire = function(_self: any, to: any, name: string, payload: any)
				if name ~= "Minigame.State" then
					table.insert(w.broken, `the server fired {name}: the rig carries Minigame.State only`)
				elseif to == player then
					toClient(payload)
				end
			end,
			fireAll = function(_self: any, name: string, payload: any)
				if name ~= "Minigame.State" then
					table.insert(w.broken, `the server fired {name}: the rig carries Minigame.State only`)
				else
					toClient(payload)
				end
			end,
		},
		games = {
			-- Boot/Game's line (and, as there, whoever is charged has an account: everyone in the game joined)
			charge = function(p: any, cents: number, why: string): (boolean, string?)
				w.wallet.join(p)
				return w.wallet.spend(p, cents, why)
			end,
			people = function(): { any }
				local q = w.body.PrimaryPart.Position
				local out: { any } = { { key = player, name = "Ann", species = w.species, x = q.X, y = q.Y, z = q.Z } }
				for _, other in w.people do
					table.insert(out, other)
				end
				return out
			end,
		},
		canPlay = function(p: any): (boolean, string?)
			if (p == player and w.species ~= "human") or (type(p) == "table" and p.animal) then
				return false, "Only people can play here"
			end
			return true
		end,
		bodyOf = function(p: any): any
			if p == player then
				return w.body
			end
			return if type(p) == "table" then p.body else nil
		end,
	}
	for k, v in o.service or {} do
		if k == "games" then
			-- (a case's own town: its members replace the rig's, the rest stay)
			for name, fn in v do
				serviceOpts.games[name] = fn
			end
		else
			serviceOpts[k] = v
		end
	end
	w.svc = MinigameService.new(serviceOpts)
	w.client = MinigameClient.start({
		state = function()
			return { species = w.species, device = nil }
		end,
		current = function(): any
			return w.body
		end,
		toast = function(text: string)
			table.insert(w.toasts, text)
		end,
		refreshCamera = function()
			w.refreshed += 1
			workspace.CurrentCamera.CameraType = roblox.Enum.CameraType.Custom
		end,
		flushInput = function()
			w.flushed += 1
		end,
	})
	w.gui = player:FindFirstChild("PlayerGui"):FindFirstChild("MinigameUI")
	return w
end

function MinigameRig.play(fn: (w: World) -> (), opts: Opts?)
	FakeEngine.with(function()
		-- selene: allow(deprecated)
		local env = getfenv(0) :: any
		local realWarn = env.warn
		local realHold, realCursor, realControls = CameraRig.hold, CameraRig.wantCursor, InputMap.setCharacterControls
		local w: World? = nil
		-- (warnings are caught from before the world is built: a Table that cannot be built says so there)
		local warnings: { string } = {}
		local ok, err = xpcall(function()
			env.warn = function(...: any)
				local parts = {}
				for _, p in { ... } do
					table.insert(parts, tostring(p))
				end
				table.insert(warnings, table.concat(parts, " "))
			end
			local world = build(opts)
			world.warnings = warnings
			w = world
			CameraRig.hold = function(on: boolean)
				world.held = on
				table.insert(world.holds, on)
				realHold(on)
			end
			CameraRig.wantCursor = function(who: string, on: boolean)
				(world.cursors :: { [string]: boolean? })[who] = if on then true else nil
				realCursor(who, on)
			end
			(InputMap :: any).setCharacterControls = function(on: boolean)
				table.insert(world.controls, on)
			end
			fn(world)
		end, function(e)
			return debug.traceback(tostring(e), 2)
		end)
		env.warn = realWarn
		CameraRig.hold, CameraRig.wantCursor = realHold, realCursor;
		(InputMap :: any).setCharacterControls = realControls
		if not ok then
			local logged = if #warnings > 0
				then `\nwarnings logged before that:\n{table.concat(warnings, "\n")}`
				else ""
			error(tostring(err) .. logged, 0)
		end
		local world = w :: World
		if #world.broken > 0 then
			error(`rules were broken:\n{table.concat(world.broken, "\n")}`, 0)
		end
		if #world.warnings > 0 then
			error(`warnings were logged:\n{table.concat(world.warnings, "\n")}`, 0)
		end
		for i = 2, #world.holds do
			if world.holds[i] == world.holds[i - 1] then
				error(`CameraRig.hold({tostring(world.holds[i])}) was called twice in a row`, 0)
			end
		end
	end)
end

-- One frame of the whole game: the client's messages arrive, the server steps, its messages arrive, the client
-- draws. Rule one is watched here: nothing may move the camera unless the game holds it.
function MinigameRig.frame(w: World)
	w.frames += 1
	while w.up[1] and w.up[1].at <= w.frames do
		local m = table.remove(w.up, 1)
		assert(w.handler, "the service never asked the net for Minigame.Input")(w.player, m.payload)
	end
	w.svc:step(MinigameRig.DT)
	while w.down[1] and w.down[1].at <= w.frames do
		local m = table.remove(w.down, 1)
		table.insert(w.got, m.payload)
		w.state.OnClientEvent.fire(m.payload)
	end
	w.heartbeat.fire(MinigameRig.DT)
	FakeEngine.renderStep(MinigameRig.DT)
	local cf = workspace.CurrentCamera.CFrame
	if cf ~= w.camWas and not w.held and #w.broken < 5 then
		table.insert(w.broken, `frame {w.frames}: the camera was moved while CameraRig was not held`)
	end
	w.camWas = cf
end

function MinigameRig.run(w: World, seconds: number)
	for _ = 1, math.max(1, math.floor(seconds * 60 + 0.5)) do
		MinigameRig.frame(w)
	end
end

function MinigameRig.untilTrue(w: World, limit: number, cond: () -> boolean): boolean
	for _ = 1, math.floor(limit * 60) do
		if cond() then
			return true
		end
		MinigameRig.frame(w)
	end
	return cond()
end

function MinigameRig.prompt(w: World, stationId: string): any
	local st = w.svc.stations[stationId]
	return st and st.prompt
end

-- The player walks up and presses E: the station's own ProximityPrompt is triggered.
function MinigameRig.press(w: World, stationId: string)
	local prompt = MinigameRig.prompt(w, stationId)
	assert(prompt, `no prompt for {stationId}`)
	prompt.Triggered.fire(w.player)
end

function MinigameRig.walkTo(w: World, site: string, x: number, y: number, d: number)
	w.body:PivotTo(roblox.CFrame.new(AlleyLayout.toWorld(w.places[site], x, y, d)))
end

-- every word drawn under root (nothing inside a hidden frame)
function MinigameRig.texts(root: any, out: { string }?): { string }
	local list = out or {}
	for _, c in root:GetChildren() do
		if c.Visible == false or c.Enabled == false then
			continue
		end
		if
			(c.ClassName == "TextLabel" or c.ClassName == "TextButton")
			and type(c.Text) == "string"
			and c.Text ~= ""
		then
			table.insert(list, c.Text)
		end
		MinigameRig.texts(c, list)
	end
	return list
end

function MinigameRig.has(list: { string }, needle: string): boolean
	for _, s in list do
		if string.find(s, needle, 1, true) then
			return true
		end
	end
	return false
end

function MinigameRig.screen(w: World): string
	if w.gui.Enabled == false then
		return ""
	end
	return table.concat(MinigameRig.texts(w.gui), " | ")
end

function MinigameRig.button(root: any, text: string): any
	for _, d in root:GetDescendants() do
		if d.ClassName == "TextButton" and d.Text == text then
			return d
		end
	end
	return nil
end

function MinigameRig.click(w: World, text: string)
	local b = MinigameRig.button(w.gui, text)
	assert(b, `no button "{text}" on screen: {MinigameRig.screen(w)}`)
	b.Activated.fire()
end

function MinigameRig.key(code: any, down: boolean, processed: boolean?)
	FakeEngine.input(if down then "began" else "ended", { KeyCode = code, UserInputType = Kind.Keyboard }, processed)
end

function MinigameRig.mouse(down: boolean, processed: boolean?)
	FakeEngine.input(if down then "began" else "ended", { UserInputType = Kind.MouseButton1 }, processed)
end

-- A finger on the screen. `id` names the finger: every event of one touch, from "began" to "ended", is handed to
-- the listeners as the SAME InputObject, as the engine does. A controller that follows two fingers at once (a
-- flipper under each thumb, a slider and a stick) must tell them apart by that object, never by where they are.
function MinigameRig.touch(id: any, kind: string, x: number, y: number, processed: boolean?)
	FakeEngine.input(kind, { id = id, UserInputType = Kind.Touch, Position = roblox.Vector3.new(x, y, 0) }, processed)
end

-- the last message of a kind in a list of payloads (w.got, w.sent by verb, a stub's events)
function MinigameRig.last(list: { any }, kind: string, pred: ((m: any) -> boolean)?): any
	for i = #list, 1, -1 do
		local m = list[i]
		if (m.kind == kind or m.verb == kind) and (pred == nil or pred(m)) then
			return m
		end
	end
	return nil
end

function MinigameRig.count(list: { any }, kind: string): number
	local n = 0
	for _, m in list do
		if m.kind == kind or m.verb == kind then
			n += 1
		end
	end
	return n
end

-- Another person at the table: a PlayerLike stub (the service puts what it would send them in stub.events).
function MinigameRig.stub(name: string): any
	return { Name = name, UserId = 9000 + #name, events = {} }
end

function MinigameRig.input(w: World, player: any, stationId: string, verb: string, args: { any }?): (boolean, string?)
	return w.svc:input(player, { gameId = stationId, seat = 1, verb = verb, args = args or {} })
end

return MinigameRig
