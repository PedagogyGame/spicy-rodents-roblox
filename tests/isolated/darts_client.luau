--!strict
-- tests/isolated/darts_client.luau: cases for tests/unit/darts_client.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Darts played from start to finish through all of its glue at once: the real Server/Minigames/MinigameService
-- with its Dartboard, and the real Client/Minigames/MinigameClient with MinigameUI and DartsClient, joined by
-- a fake network that carries each side's messages to the other a few frames late (as plain copies, checked
-- against the Net schema on the way up). The player is the fake engine's LocalPlayer with a body; other
-- people are PlayerLike stubs. The mouse is moved in pixels and the fake camera turns a pixel into a ray, so a
-- throw goes mouse -> aim -> meter -> "throw" -> the server's scatter -> the score -> the screen.
-- Most cases play with a steady hand (the hand's wobble and the server's scatter set to nothing, the meter let
-- go in the green) so that a dart lands exactly where the mouse points and whole legs can be played to a known
-- score; one case plays with the real wobble and scatter.
-- Covered: walking up and the prompt; the lobby and 501 / Cricket; three-dart turns; busts and a double-out;
-- a whole game of cricket against another person; the end of a game (Play again, Leave, the card running
-- out); leaving in the middle and every other way off the board; a computer player that takes its turns and
-- finishes a leg; and the three rules of the main client (Client/Minigames/MinigameClient's header): shots
-- inside CameraRig.hold, the cursor asked for through CameraRig.wantCursor, input flushed at each hand-over.
-- Interface: return function(t) (the spec shape)
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Darts = require("@shared/Minigames/MinigameRules/Darts")
local Data = require("@shared/Data")
local Schema = require("@shared/Util/Schema")
local Schemas = require("@shared/Net/Schemas")
local Session = require("@shared/Minigames/Session")
local MinigameService = require("@server/Minigames/MinigameService")
local CameraRig = require("@client/Camera/CameraRig")
local DartsClient = require("@client/Minigames/DartsClient")
local InputMap = require("@client/Input/InputMap")
local MinigameClient = require("@client/Minigames/MinigameClient")
local DartsFlow = require("@tests/engine/DartsFlow")
local FakeEngine = require("@tests/lib/FakeEngine")
local roblox = require("@lune/roblox")

local DARTS = "darts_1"
local DT = 1 / 60
local Key = roblox.Enum.KeyCode
local Kind = roblox.Enum.UserInputType

type World = {
	svc: any,
	hw: any, -- the server's Dartboard
	session: any,
	client: any,
	place: AlleyLayout.Place,
	player: any,
	body: any,
	board: any, -- GamesRoom.Dartboard
	prompt: any, -- the dartboard's ProximityPrompt
	gui: any,
	input: any, -- the Minigame.Input remote
	state: any, -- the Minigame.State remote
	handler: ((player: any, payload: any) -> ())?,
	heartbeat: any,
	lag: number, -- frames a message takes each way
	up: { any },
	down: { any },
	sent: { any }, -- every payload the client sent, in order
	got: { any }, -- every payload the client was sent, in order
	gotAt: { number }, -- and the frame each arrived on
	frames: number,
	toasts: { string },
	warnings: { string },
	broken: { string }, -- rules broken on the way (checked when the case ends)
	camWas: any,
	refreshed: number,
	flushed: number,
	species: string,
	held: boolean, -- CameraRig.hold as the game last set it
	holds: { boolean },
	cursors: { [string]: boolean }, -- who has asked CameraRig for the cursor
	controls: { boolean }, -- every hand-over of the player's legs (false = taken)
}

-- A message as it would arrive over a RemoteEvent: a copy, and only what a remote carries faithfully (plain
-- values; tables that are either lists or string-keyed records).
local function wire(v: any, path: string): any
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
			out[k] = wire(item, `{path}.{k}`)
		end
		return out
	end
	assert(kind == "number" or kind == "string" or kind == "boolean" or kind == "nil", `{path}: a {kind}`)
	return v
end

local function build(opts: { lag: number?, seed: number?, touch: boolean? }?): World
	local o: { lag: number?, seed: number?, touch: boolean? } = opts or {}
	local attractions = Data.default():module("Attractions") :: any
	local pl = attractions.attractions[1].place -- (the client reads its place from the same data)
	local place: AlleyLayout.Place = { x = pl.x, z = pl.z, floorY = pl.floorY, yaw = pl.yaw }
	local b = AlleyLayout.board()
	local function at(X: number, Y: number, D: number): any
		return roblox.CFrame.new(AlleyLayout.toWorld(place, X, Y, D))
	end
	-- the alley as far as darts needs it: Workspace.Attractions.BowlingAlley.GamesRoom.Dartboard
	local folder = FakeEngine.new("Folder", "Attractions")
	folder.Parent = workspace
	local root = FakeEngine.new("Model", "BowlingAlley")
	root.Parent = folder
	local games = FakeEngine.new("Folder", "GamesRoom")
	games.Parent = root
	local board = FakeEngine.model("Dartboard", at(b.x, b.y, b.d), games)
	FakeEngine.part("BoardFace", at(b.x, b.y, b.d), board)
	local chalkboard = FakeEngine.part("ScoreBoard", at(b.x, b.y, b.d - 4.8), board)
	FakeEngine.new("SurfaceGui", "Score").Parent = chalkboard
	local idle = FakeEngine.new("Folder", "IdleDarts")
	idle.Parent = board
	for k = 0, 2 do
		local _, Y, D = AlleyLayout.boardPoint(-30 + k * 25, 60 - k * 20)
		FakeEngine.part("IdleDart", at(b.x - 0.3, Y, D), idle)
	end
	-- the remotes
	local rs = (game :: any):GetService("ReplicatedStorage")
	local net = FakeEngine.new("Folder", "Net")
	net.Parent = rs
	local input = FakeEngine.new("RemoteEvent", "Minigame.Input")
	input.Parent = net
	local state = FakeEngine.new("RemoteEvent", "Minigame.State")
	state.Parent = net
	-- the player: a person standing a couple of steps behind the oche
	local player = (game :: any):GetService("Players").LocalPlayer
	rawset(player, "DisplayName", "Ann")
	local body = FakeEngine.model("Ann", at(b.ocheX - 2, 3, b.d + 1), nil)
	body.PrimaryPart = FakeEngine.part("HumanoidRootPart", at(b.ocheX - 2, 3, b.d + 1), body)
	FakeEngine.part("RightHand", at(b.ocheX - 1.5, 3.4, b.d + 0.4), body)
	if o.touch then
		local uis = FakeEngine.uis()
		uis.TouchEnabled, uis.MouseEnabled, uis.KeyboardEnabled = true, false, false
	end

	local w: World = {
		svc = nil,
		hw = nil,
		session = nil,
		client = nil,
		place = place,
		player = player,
		body = body,
		board = board,
		prompt = nil,
		gui = nil,
		input = input,
		state = state,
		handler = nil,
		heartbeat = (game :: any):GetService("RunService").Heartbeat,
		lag = o.lag or 3,
		up = {},
		down = {},
		sent = {},
		got = {},
		gotAt = {},
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
	-- what the client fires arrives at the server a few frames later, if the Net schema lets it through
	rawset(input, "FireServer", function(_self: any, payload: any)
		local ok, why = Schema.check(Schemas.REMOTES["Minigame.Input"].payload :: any, payload)
		if not ok then
			table.insert(w.broken, `the client sent a payload the Net schema refuses: {tostring(why)}`)
			return
		end
		local copy = wire(payload, "Minigame.Input")
		table.insert(w.sent, copy)
		table.insert(w.up, { at = w.frames + w.lag, payload = copy })
	end)
	local function toClient(payload: any)
		table.insert(w.down, { at = w.frames + w.lag, payload = wire(payload, "Minigame.State") })
	end
	w.svc = MinigameService.new({
		root = root,
		place = place,
		seed = o.seed or 7,
		net = {
			on = function(_self: any, _name: string, fn: (player: any, payload: any) -> ())
				w.handler = fn
			end,
			fire = function(_self: any, to: any, _name: string, payload: any)
				if to == player then
					toClient(payload)
				end
			end,
			fireAll = function(_self: any, _name: string, payload: any)
				toClient(payload)
			end,
		},
		canPlay = function(p: any): (boolean, string?)
			if p == player and w.species ~= "human" then
				return false, "Only people can play here"
			end
			return true
		end,
		bodyOf = function(p: any): any
			return if p == player then w.body else nil
		end,
	})
	w.hw = w.svc.stations[DARTS].hw
	w.session = w.svc:sessionOf(DARTS)
	w.prompt = root:FindFirstChild("MinigamePrompts"):FindFirstChild(DARTS):FindFirstChildOfClass("ProximityPrompt")
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

-- One case: a fresh world, with the main client's hooks listened in on. However the case ends, the hooks and
-- the rules' constants are put back; and a case never passes with a warning logged (the client swallows its
-- own errors into warnings) or a rule broken along the way.
local function play(fn: (w: World) -> (), opts: { lag: number?, seed: number?, touch: boolean?, steady: boolean? }?)
	FakeEngine.with(function()
		-- selene: allow(deprecated)
		local env = getfenv(0) :: any
		local realWarn = env.warn
		local realHold, realCursor, realControls = CameraRig.hold, CameraRig.wantCursor, InputMap.setCharacterControls
		local wobble, sigma = Darts.WOBBLE_MM, Darts.BASE_SIGMA
		local w: World? = nil
		local ok, err = xpcall(function()
			local world = build(opts)
			w = world
			env.warn = function(...: any)
				local parts = {}
				for _, p in { ... } do
					table.insert(parts, tostring(p))
				end
				table.insert(world.warnings, table.concat(parts, " "))
			end
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
			if opts == nil or opts.steady ~= false then
				Darts.WOBBLE_MM, Darts.BASE_SIGMA = 0, 0
			end
			fn(world)
		end, function(e)
			return debug.traceback(tostring(e), 2)
		end)
		env.warn = realWarn
		CameraRig.hold, CameraRig.wantCursor = realHold, realCursor;
		(InputMap :: any).setCharacterControls = realControls
		Darts.WOBBLE_MM, Darts.BASE_SIGMA = wobble, sigma
		if not ok then
			local logged = if w and #w.warnings > 0
				then `\nwarnings logged before that:\n{table.concat(w.warnings, "\n")}`
				else ""
			error(tostring(err) .. logged, 0)
		end
		local world = w :: World
		if #world.warnings > 0 then
			error(`warnings were logged:\n{table.concat(world.warnings, "\n")}`, 0)
		end
		if #world.broken > 0 then
			error(`rules were broken:\n{table.concat(world.broken, "\n")}`, 0)
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
local function frame(w: World)
	w.frames += 1
	while w.up[1] and w.up[1].at <= w.frames do
		local m = table.remove(w.up, 1)
		assert(w.handler, "the service never asked the net for Minigame.Input")(w.player, m.payload)
	end
	w.svc:step(DT)
	while w.down[1] and w.down[1].at <= w.frames do
		local m = table.remove(w.down, 1)
		table.insert(w.got, m.payload)
		table.insert(w.gotAt, w.frames)
		w.state.OnClientEvent.fire(m.payload)
	end
	w.heartbeat.fire(DT)
	FakeEngine.renderStep(DT)
	local cf = workspace.CurrentCamera.CFrame
	if cf ~= w.camWas and not w.held and #w.broken < 5 then
		table.insert(w.broken, `frame {w.frames}: the camera was moved while CameraRig was not held`)
	end
	w.camWas = cf
end

local function run(w: World, seconds: number)
	for _ = 1, math.max(1, math.floor(seconds * 60 + 0.5)) do
		frame(w)
	end
end

-- every word drawn under root (nothing inside a hidden frame)
local function texts(root: any, out: { string }?): { string }
	local list = out or {}
	for _, d in root:GetChildren() do
		if d.Visible ~= false then
			if
				(d.ClassName == "TextLabel" or d.ClassName == "TextButton")
				and type(d.Text) == "string"
				and d.Text ~= ""
			then
				table.insert(list, d.Text)
			end
			texts(d, list)
		end
	end
	return list
end

local function has(list: { string }, needle: string): boolean
	for _, s in list do
		if string.find(s, needle, 1, true) then
			return true
		end
	end
	return false
end

-- (what the screen says, for a failing check's message)
local function screen(w: World): string
	local short = {}
	for _, s in texts(w.gui) do
		table.insert(short, if #s > 160 then string.sub(s, 1, 40) .. "..." else s)
	end
	return table.concat(short, " | ")
end

local function button(root: any, text: string): any
	for _, d in root:GetDescendants() do
		if d.ClassName == "TextButton" and d.Text == text then
			return d
		end
	end
	return nil
end

local function click(w: World, text: string)
	local b = button(w.gui, text)
	assert(b, `no "{text}" button on screen: {screen(w)}`)
	b.Activated.fire()
end

local function card(w: World): { string }
	return texts(w.gui:FindFirstChild("Scorecard"))
end

local function chalk(w: World): { string }
	return texts(w.board:FindFirstChild("ScoreBoard"))
end

local function key(code: any, down: boolean, processed: boolean?)
	FakeEngine.input(if down then "began" else "ended", { KeyCode = code, UserInputType = Kind.Keyboard }, processed)
end

local function mouse(down: boolean, processed: boolean?)
	FakeEngine.input(if down then "began" else "ended", { UserInputType = Kind.MouseButton1 }, processed)
end

local function last(list: { any }, kind: string, pred: ((m: any) -> boolean)?): any
	for i = #list, 1, -1 do
		local m = list[i]
		if (m.kind == kind or m.verb == kind) and (pred == nil or pred(m)) then
			return m
		end
	end
	return nil
end

local function count(list: { any }, kind: string): number
	local n = 0
	for _, m in list do
		if m.kind == kind or m.verb == kind then
			n += 1
		end
	end
	return n
end

-- a point (mm) in the middle of a ring of segment n: radius 103 the treble, 166 the double, 134 the fat single
local function at(n: number, r: number): (number, number)
	local idx = table.find(Darts.ORDER, n) :: number
	local a = math.rad((idx - 1) * 18)
	return r * math.sin(a), r * math.cos(a)
end
local TREBLE, DOUBLE, SINGLE = 103, 166, 134

-- the world point of board millimetres, on the plane the thrower's aim is measured on
local function boardWorld(w: World, xmm: number, ymm: number): any
	local X, Y, D = AlleyLayout.boardPoint(xmm, ymm)
	return roblox.Vector3.new(AlleyLayout.toWorld(w.place, X - 0.075, Y, D))
end

-- and back: the board millimetres of a world point
local function boardMm(w: World, p: any): (number, number)
	local _, Y, D = AlleyLayout.toLocal(w.place, p.X, p.Y, p.Z)
	return AlleyLayout.boardFromLocal(Y, D)
end

-- put the mouse on the pixel that shows a board point through the camera as it is now
local function mouseAt(w: World, xmm: number, ymm: number)
	local v = workspace.CurrentCamera:WorldToViewportPoint(boardWorld(w, xmm, ymm))
	FakeEngine.uis().mouse = roblox.Vector2.new(v.X, v.Y)
end

local function marker(name: string): any
	return workspace.CurrentCamera:FindFirstChild(name)
end

-- it is my throw as the screen has it: the aim dot is drawn
local function aiming(): boolean
	local dot = marker("DartAim")
	return dot ~= nil and dot.Transparency < 1
end

-- the timing meter: shown?, its value, its green band
local function meter(w: World): (boolean, number, number, number)
	local m = w.gui:FindFirstChild("Meter")
	local bars = {}
	for _, c in m:GetChildren() do
		if c.ClassName == "Frame" then
			table.insert(bars, c)
		end
	end
	local sweet, fill = bars[1], bars[2]
	if not m.Visible or sweet.Position == nil then
		return m.Visible, 0, 0, 0
	end
	return true, fill.Size.X.Scale, sweet.Position.X.Scale, sweet.Position.X.Scale + sweet.Size.X.Scale
end

-- the darts standing in the board now, as board millimetres of each point
local function stuck(w: World): { { x: number, y: number } }
	local out = {}
	for _, d in w.board:FindFirstChild("ThrownDarts"):GetChildren() do
		local x, y = boardMm(w, d:FindFirstChild("Point").CFrame.Position)
		table.insert(out, { x = x, y = y })
	end
	return out
end

local function idleShown(w: World): number
	local n = 0
	for _, p in w.board:FindFirstChild("IdleDarts"):GetChildren() do
		if p.Transparency == 0 then
			n += 1
		end
	end
	return n
end

-- Throw one dart as a player does: point the mouse, hold the button while the meter runs, let go. hold is how
-- long the button is held (0.65 s is the middle of the green band). Returns what the server said of it.
local function throw(w: World, xmm: number, ymm: number, hold: number?): any
	assert(aiming(), `throw: it is not my throw. The screen: {screen(w)}`)
	local before = #w.got
	mouseAt(w, xmm, ymm)
	frame(w)
	mouse(true)
	for _ = 1, math.floor((hold or 0.65) * 60 + 0.5) do
		mouseAt(w, xmm, ymm)
		frame(w)
	end
	mouse(false)
	-- the dart flies and lands; by then the next one may be thrown
	run(w, 0.75)
	for i = before + 1, #w.got do
		if w.got[i].kind == "dart" then
			return w.got[i]
		end
	end
	return nil
end

local function untilTrue(w: World, limit: number, cond: () -> boolean): boolean
	local n = 0
	while not cond() and n < limit * 60 do
		frame(w)
		n += 1
	end
	return cond()
end

local function stub(name: string): any
	return { Name = name, UserId = #name, events = {} }
end

-- walk up and press E; optionally bring a friend, pick a game, and start it
local function seat(w: World, with: { any }?, mode: string?)
	w.prompt.Triggered.fire(w.player)
	for _, p in with or {} do
		assert(w.svc:join(p, DARTS))
	end
	run(w, 0.3)
	if mode then
		click(w, if mode == "cricket" then "Cricket" else "501")
		run(w, 0.3)
	end
end

local function start(w: World)
	click(w, "Start")
	assert(untilTrue(w, 2, aiming), `the game did not come round to my throw: {screen(w)}`)
	run(w, 1.2) -- the camera settles on the board
end

-- another person's turn: three darts put exactly where they are wanted (the server's own "land")
local function theirTurn(w: World, darts: { { number } })
	for _, d in darts do
		assert(w.svc:debugDart(DARTS, d[1], d[2]))
		run(w, 0.5)
	end
end

local MISS = { 250, 250 }

return function(t)
	t.test(
		"walking up: the board's prompt says what it is and is for people only; E seats you and the lobby opens",
		function()
			play(function(w)
				local b = AlleyLayout.board()
				local prompt = w.prompt
				t.eq(prompt.ActionText, "Play darts")
				t.truthy(string.find(prompt.ObjectText, "Dartboard - open", 1, true) ~= nil, prompt.ObjectText)
				t.eq(prompt.KeyboardKeyCode, Key.E)
				-- the prompt is in reach of the oche, where the last game's thrower is left standing
				local oche = roblox.Vector3.new(AlleyLayout.toWorld(w.place, b.ocheX - 0.7, 3, b.d + 0.4))
				t.truthy((prompt.Parent.CFrame.Position - oche).Magnitude < prompt.MaxActivationDistance - 2)
				-- nobody playing: three darts wait in the board and the chalkboard invites
				t.eq(idleShown(w), 3)
				t.truthy(has(chalk(w), "walk up and press E"))
				run(w, 0.5)
				t.eq(prompt.Enabled, true, "a person sees the prompt")
				w.species = "squirrel"
				run(w, 0.5)
				t.eq(prompt.Enabled, false, "an animal does not")
				-- and the server refuses an animal in words if its prompt fires all the same
				prompt.Triggered.fire(w.player)
				run(w, 0.3)
				t.truthy(has(w.toasts, "Only people can play here"))
				t.eq(w.gui.Enabled, false)
				t.eq(w.session.phase, "idle")
				w.species = "human"
				run(w, 0.5)
				t.eq(prompt.Enabled, true)
				t.eq(w.flushed, 0)
				-- E
				prompt.Triggered.fire(w.player)
				run(w, 0.3)
				t.eq(w.session.phase, "lobby")
				t.eq(w.gui.Enabled, true)
				t.eq(w.client.active(), DARTS)
				t.eq(w.player:GetAttribute("InMinigame"), DARTS)
				t.truthy(has(w.toasts, "You joined Dartboard"))
				t.eq(w.flushed, 1, "the keys change hands when the game opens")
				local all = texts(w.gui)
				t.truthy(has(all, "Darts"))
				t.truthy(has(all, "501: start on 501"), "the help card says how each game is played")
				t.truthy(has(all, "Cricket: hit 15 to 20"))
				t.truthy(has(all, "Q  leave the board"), "and lists the controls")
				for _, text in { "501", "Cricket", "+ Computer", "Start", "Leave (Q)" } do
					t.truthy(button(w.gui, text) ~= nil, `the lobby has a "{text}" button`)
				end
				t.truthy(has(all, "Starting in 8"), screen(w))
				t.truthy(has(all, "game: 501"))
				t.truthy(has(card(w), "501  (finish on a double)"))
				t.truthy(has(card(w), "Ann (you)"))
				t.truthy(has(chalk(w), "starting in"))
				t.truthy(has(chalk(w), "Ann"))
				-- the lobby needs the cursor for its buttons; no shot is up, so the camera is still the player's
				t.eq(w.cursors.minigame, true)
				t.eq(w.held, false)
				t.falsy(aiming())
				-- the prompt now invites a friend, and is off on this screen while I am seated
				t.eq(prompt.ActionText, "Join")
				t.truthy(string.find(prompt.ObjectText, "1/4 joining", 1, true) ~= nil, prompt.ObjectText)
				run(w, 0.5)
				t.eq(prompt.Enabled, false)
				-- the countdown runs on screen
				run(w, 1)
				t.truthy(has(texts(w.gui), "Starting in 7"), screen(w))
			end)
		end
	)

	t.test(
		"the lobby: 501 or Cricket is picked with a button, shown on the card and the chalkboard, and is the game that starts",
		function()
			play(function(w)
				seat(w)
				click(w, "Cricket")
				t.eq(last(w.sent, "mode").args[1], "cricket")
				run(w, 0.3)
				t.truthy(has(texts(w.gui), "game: cricket"), screen(w))
				t.truthy(has(card(w), "CRICKET") and has(card(w), "BULL"))
				run(w, 1) -- (the chalkboard on the wall follows within the second)
				t.truthy(has(chalk(w), "CRICKET"), table.concat(chalk(w), " | "))
				click(w, "501")
				run(w, 0.3)
				t.truthy(has(texts(w.gui), "game: 501"), screen(w))
				t.truthy(has(card(w), "501  (finish on a double)"))
				run(w, 1)
				t.truthy(has(chalk(w), "501"), table.concat(chalk(w), " | "))
				click(w, "Cricket")
				run(w, 0.3)
				-- Space starts it now; the same press must not also be a throw (the meter stays away)
				key(Key.Space, true)
				t.eq(last(w.sent, "start").gameId, DARTS)
				run(w, 0.5)
				t.eq(w.session.phase, "playing")
				t.eq(w.session.game.state.mode, "cricket")
				t.truthy(count(w.got, "event") >= 2, "Game on! and Your turn! were announced")
				t.truthy(last(w.got, "event", function(m)
					return m.text == "Game on!"
				end) ~= nil)
				t.truthy(has(texts(w.gui), "Your turn!"), screen(w))
				t.eq((meter(w)), false)
				key(Key.Space, false)
				run(w, 0.3)
				t.eq(count(w.sent, "throw"), 0, "the Space that started the game threw nothing")
				-- in play: the idle darts are out of the board, only Leave is on the bar, the prompt says in use
				t.eq(idleShown(w), 0)
				t.truthy(button(w.gui, "Leave (Q)") ~= nil)
				t.eq(button(w.gui, "Start"), nil)
				t.eq(button(w.gui, "Cricket"), nil)
				t.eq(w.prompt.ActionText, "In use")
				t.truthy(string.find(w.prompt.ObjectText, "game on (1 playing)", 1, true) ~= nil)
				t.falsy(string.find(w.prompt.ObjectText, "try another", 1, true) ~= nil, "there is only the one board")
				t.truthy(has(card(w), "CRICKET"))
				-- a latecomer is refused in words
				local cat = stub("Cat")
				local ok, why = w.svc:join(cat, DARTS)
				t.falsy(ok)
				t.truthy(string.find(why :: string, "in progress", 1, true) ~= nil)
				t.eq(last(cat.events, "refused").text, why)
			end)
			-- a lobby nobody starts runs out by itself, into the game it shows (501 unless another was picked)
			play(function(w)
				seat(w)
				run(w, 7)
				t.eq(w.session.phase, "lobby")
				run(w, 1.5)
				t.eq(w.session.phase, "playing")
				t.eq(w.session.game.state.mode, "501")
				t.truthy(aiming(), "and it is my throw")
			end)
		end
	)

	t.test(
		"a turn in 501: the mouse aims, the meter runs, three darts go out one at a time and are scored; then a clean board",
		function()
			play(function(w)
				seat(w)
				start(w)
				-- my throw: my legs are the board's, the shot of the board is up and held
				t.deepEq(w.controls, { false })
				t.eq(w.held, true)
				t.eq(workspace.CurrentCamera.CameraType, roblox.Enum.CameraType.Scriptable)
				t.near(workspace.CurrentCamera.FieldOfView, 20, 0.01)
				local b = AlleyLayout.board()
				local stand = roblox.Vector3.new(AlleyLayout.toWorld(w.place, b.ocheX - 0.7, 3, b.d + 0.4))
				t.truthy((w.body.PrimaryPart.CFrame.Position - stand).Magnitude < 0.01, "I stand at the oche")
				-- the mouse on the treble 20: the ring is under the mouse, and the words say what it points at
				local tx, ty = at(20, TREBLE)
				mouseAt(w, tx, ty)
				run(w, 0.1)
				local ring, dot = marker("DartMouse"), marker("DartAim")
				t.truthy(
					(ring.CFrame.Position - boardWorld(w, tx, ty)).Magnitude < 0.002,
					"the ring is under the mouse"
				)
				t.truthy((dot.CFrame.Position - boardWorld(w, tx, ty)).Magnitude < 0.02, "so is the dot (steady hand)")
				-- the dot is drawn a hair proud of the disc (two faces in one plane would flicker)
				local nx, nz = AlleyLayout.dirToWorld(w.place, -1, 0)
				local proud = (dot.CFrame.Position - ring.CFrame.Position):Dot(roblox.Vector3.new(nx, 0, nz))
				t.truthy(proud > 0.005 and proud < 0.03, `the dot is {proud} studs nearer the thrower than the disc`)
				t.truthy(has(texts(w.gui), "Your throw"), screen(w))
				t.truthy(has(texts(w.gui), "dart 1 of 3"), screen(w))
				t.truthy(has(texts(w.gui), "501 left"), screen(w))
				t.truthy(has(texts(w.gui), "iming at T20"), screen(w))
				local dx, dy = at(16, DOUBLE)
				mouseAt(w, dx, dy)
				run(w, 0.1)
				t.truthy(has(texts(w.gui), "iming at D16"), screen(w))
				mouseAt(w, 0, 0)
				run(w, 0.1)
				t.truthy(has(texts(w.gui), "iming at BULL"), screen(w))
				mouseAt(w, 0, 200)
				run(w, 0.1)
				t.truthy(has(texts(w.gui), "iming at MISS"), screen(w))
				-- the turn clock is on screen
				t.truthy(w.gui:FindFirstChild("Clock").Visible, "the turn clock shows")
				-- hold the button: the meter with its green band and its words; nothing is sent yet
				mouseAt(w, tx, ty)
				frame(w)
				mouse(true)
				for _ = 1, 39 do
					mouseAt(w, tx, ty)
					frame(w)
				end
				local shown, value, lo, hi = meter(w)
				t.eq(shown, true)
				t.near(value, 0.5, 0.01)
				t.near(lo, Darts.SWEET - Darts.SWEET_HALF, 1e-6)
				t.near(hi, Darts.SWEET + Darts.SWEET_HALF, 1e-6)
				t.truthy(has(texts(w.gui), "let go in the green"))
				t.eq(count(w.sent, "throw"), 0)
				mouse(false)
				t.eq(count(w.sent, "throw"), 1, "letting go throws, once")
				local sent = last(w.sent, "throw")
				t.eq(sent.gameId, DARTS)
				t.near(sent.args[1], tx, 0.05)
				t.near(sent.args[2], ty, 0.05)
				t.near(sent.args[3], 0.5, 0.01)
				frame(w)
				t.eq((meter(w)), false, "the meter goes away")
				-- pressing again at once does nothing: the dart is still in the air
				mouse(true)
				run(w, 0.2)
				t.eq((meter(w)), false)
				mouse(false)
				t.eq(count(w.sent, "throw"), 1)
				-- the server: one dart flies from my hand and sticks where I aimed; scored; said on screen
				t.truthy(untilTrue(w, 1, function()
					return last(w.got, "dart") ~= nil
				end))
				local said = last(w.got, "dart")
				t.eq(said.label, "T20")
				t.eq(said.points, 60)
				t.eq(said.text, "T20  (+60)")
				run(w, 0.6)
				t.falsy(w.hw:busy(), "the dart has landed")
				local darts = stuck(w)
				t.eq(#darts, 1)
				t.truthy(
					math.abs(darts[1].x - tx) < 40 and math.abs(darts[1].y - ty) < 40,
					"its point is at the treble 20"
				)
				t.truthy(has(texts(w.gui), "T20  (+60)"), screen(w))
				t.truthy(has(card(w), "441"))
				t.truthy(has(card(w), "T20"))
				t.truthy(has(chalk(w), "441"))
				t.truthy(has(texts(w.gui), "dart 2 of 3"), screen(w))
				t.truthy(has(texts(w.gui), "441 left"), screen(w))
				-- two more: a single 5 and the bull
				local fx, fy = at(5, SINGLE)
				t.eq(throw(w, fx, fy).text, "5  (+5)")
				t.truthy(has(texts(w.gui), "dart 3 of 3"), screen(w))
				t.eq(#stuck(w), 2)
				t.eq(throw(w, 0, 0).text, "BULL  (+50)")
				t.eq(w.session.game.state.players[1].score, 501 - 60 - 5 - 50)
				t.deepEq(w.session.game.state.players[1].history, { 115 })
				t.truthy(has(card(w), "386"))
				-- alone, the next turn is mine again: the shot never left, my legs were not handed back and forth
				t.truthy(aiming())
				t.eq(w.held, true)
				t.deepEq(w.controls, { false })
				t.deepEq(w.holds, { true })
				t.truthy(has(texts(w.gui), "dart 1 of 3"), screen(w))
				-- the turn's three darts are pulled out, and a dart of the next turn thrown before that stays in
				t.eq(#stuck(w), 3)
				t.eq(throw(w, tx, ty).text, "T20  (+60)")
				run(w, 2)
				local left = stuck(w)
				t.eq(#left, 1, "only the new turn's dart is in the board")
				t.truthy(math.abs(left[1].y - ty) < 40)
				t.truthy(has(card(w), "326"))
			end)
		end
	)

	t.test(
		"501 to the finish: a bust puts the score back and ends the turn, zero needs a double, the double checks out; then Leave",
		function()
			play(function(w)
				seat(w)
				start(w)
				local t20x, t20y = at(20, TREBLE)
				local t19x, t19y = at(19, TREBLE)
				local s12x, s12y = at(12, SINGLE)
				local d6x, d6y = at(6, DOUBLE)
				local function score(): number
					return w.session.game.state.players[1].score
				end
				for _ = 1, 6 do
					throw(w, t20x, t20y)
				end
				t.eq(score(), 141)
				-- 141: T20, T19 leave 24; a third treble 20 is too many
				throw(w, t20x, t20y)
				throw(w, t19x, t19y)
				t.eq(score(), 24)
				local bust = throw(w, t20x, t20y)
				t.eq(bust.event, "bust")
				t.eq(bust.text, "BUST! (T20)")
				t.eq(score(), 141, "the score is back where the turn started")
				t.truthy(has(texts(w.gui), "BUST! (T20)"), screen(w))
				t.truthy(has(card(w), "141"))
				t.truthy(has(texts(w.gui), "dart 1 of 3"), "and the turn is over: a new one starts")
				-- again, down to 12
				throw(w, t20x, t20y)
				throw(w, t19x, t19y)
				t.eq(throw(w, s12x, s12y).text, "12  (+12)")
				t.eq(score(), 12)
				-- a single 12 would reach zero, but not on a double: bust
				local single = throw(w, s12x, s12y)
				t.eq(single.event, "bust")
				t.eq(score(), 12)
				t.eq(w.session.phase, "playing")
				-- double 6
				local out = throw(w, d6x, d6y)
				t.eq(out.event, "checkout")
				t.eq(out.text, "CHECKOUT! D6")
				t.eq(w.session.phase, "done")
				t.eq(w.session.result.winner, 1)
				t.eq(w.session.result.scores[1], 0)
				-- the end of the game on screen: who won and what to press, with the reset counting down
				run(w, 1.5)
				local all = texts(w.gui)
				t.truthy(has(all, "checked out"), screen(w))
				t.truthy(has(all, "Play again"), screen(w))
				t.truthy(has(all, "The board resets in"), screen(w))
				t.truthy(button(w.gui, "Play again") ~= nil and button(w.gui, "Leave (Q)") ~= nil)
				t.truthy(has(card(w), "0"))
				t.truthy(has(chalk(w), "Ann wins!"))
				local a = last(w.got, "state").view.doneLeft
				run(w, 2)
				t.truthy(last(w.got, "state").view.doneLeft < a, "the countdown runs")
				-- everything of my turn is handed back
				t.falsy(aiming())
				t.eq(w.held, false)
				t.eq(w.controls[#w.controls], true)
				t.eq((meter(w)), false)
				t.eq(w.gui:FindFirstChild("Clock").Visible, false)
				t.eq(w.cursors.minigame, true, "the end's buttons keep the cursor")
				-- the darts come out of the board
				run(w, 1.5)
				t.eq(#stuck(w), 0)
				-- a throw now is refused in words, not swallowed
				local handler = w.handler :: (player: any, payload: any) -> ()
				handler(w.player, { gameId = DARTS, seat = 1, verb = "throw", args = { 0, 0, 0.5 } })
				run(w, 0.2)
				t.truthy(has(w.toasts, "The game is over"))
				-- Q at the end: off the board, with words; the board is as it was found
				key(Key.Q, true)
				t.eq(last(w.sent, "leave").gameId, DARTS)
				run(w, 0.3)
				t.eq(w.gui.Enabled, false)
				t.eq(w.client.active(), nil)
				t.eq(w.player:GetAttribute("InMinigame"), nil)
				t.truthy(has(w.toasts, "You left the game"))
				t.eq(w.flushed, 2, "the keys change hands again when the game closes")
				t.eq(next(w.cursors), nil, "the mouse goes back to the camera")
				t.eq(marker("DartAim"), nil)
				t.eq(marker("DartMouse"), nil)
				t.eq(FakeEngine.bound(), 0)
				t.eq(w.session.phase, "idle")
				t.eq(w.svc:stationOf(w.player), nil)
				t.eq(idleShown(w), 3)
				t.eq(w.prompt.ActionText, "Play darts")
				t.truthy(has(chalk(w), "walk up and press E"))
				run(w, 0.5)
				t.eq(w.prompt.Enabled, true)
				local heard = #w.got
				run(w, 3)
				t.eq(#w.got, heard, "nothing more is sent about a board I have left")
			end)
		end
	)

	t.test(
		"a whole game of cricket against a friend: marks, closing, points on what they have open, the win; Play again keeps the game",
		function()
			play(function(w)
				local bob = stub("Bob")
				seat(w, { bob }, "cricket")
				t.truthy(has(card(w), "Bob"))
				run(w, 8.5) -- nobody presses Start: the lobby runs out
				t.eq(w.session.phase, "playing")
				t.eq(w.session.game.state.mode, "cricket")
				t.truthy(untilTrue(w, 1, aiming))
				run(w, 1.2)
				local me = w.session.game.state.players[1]
				local s20x, s20y = at(20, SINGLE)
				local function treble(n: number): any
					local x, y = at(n, TREBLE)
					return throw(w, x, y)
				end
				-- a single 20 is one mark and no points (whatever the wedge is worth on the board)
				t.eq(throw(w, s20x, s20y).text, "20")
				t.eq(me.marks[20], 1)
				t.eq(me.score, 0)
				t.truthy(has(card(w), "/"), "one mark is drawn as a stroke")
				-- a treble on top closes it, and the mark over three scores while Bob has 20 open
				t.eq(treble(20).text, "T20 - closed  (+20)")
				t.eq(me.score, 20)
				t.truthy(has(card(w), "(X)"))
				t.eq(treble(19).text, "T19 - closed")
				-- Bob's turn: my own camera and legs come back once my last dart has landed
				t.truthy(untilTrue(w, 2, function()
					return not w.held
				end))
				t.falsy(aiming())
				t.deepEq(w.controls, { false, true })
				t.eq(w.refreshed, 1)
				t.truthy(has(texts(w.gui), "Bob is throwing (dart 1 of 3)"), screen(w))
				t.eq(w.cursors.minigame, true, "Leave (Q) is still on screen")
				t.eq(last(bob.events, "event").text, "Your turn!")
				theirTurn(w, { MISS, MISS, { at(5, SINGLE) } })
				t.eq(
					last(w.got, "dart").text,
					"5 - no score",
					"a number that is not in the game is said to score nothing"
				)
				t.eq(last(w.got, "dart").seat, 2)
				-- mine again
				t.truthy(untilTrue(w, 2, aiming))
				t.truthy(has(texts(w.gui), "Your turn!"), screen(w))
				t.eq(w.held, true)
				t.deepEq(w.controls, { false, true, false })
				run(w, 1.2)
				t.eq(#stuck(w), 0, "Bob's darts are out of the board")
				t.eq(treble(18).event, "closed")
				t.eq(treble(17).event, "closed")
				t.eq(treble(16).event, "closed")
				untilTrue(w, 2, function()
					return not w.held
				end)
				theirTurn(w, { MISS, MISS, MISS })
				t.truthy(untilTrue(w, 2, aiming))
				run(w, 1.2)
				t.eq(treble(15).event, "closed")
				local fx, fy = at(5, SINGLE)
				t.eq(throw(w, fx, fy).text, "5 - no score")
				t.eq(throw(w, 0, 0).text, "BULL")
				t.eq(me.marks[25], 2)
				untilTrue(w, 2, function()
					return not w.held
				end)
				theirTurn(w, { MISS, MISS, MISS })
				t.truthy(untilTrue(w, 2, aiming))
				run(w, 1.2)
				-- the outer bull is the last mark: everything closed and ahead on points
				local win = throw(w, 10, 0)
				t.eq(win.event, "win")
				t.eq(win.text, "25 - closes it out!")
				t.eq(w.session.phase, "done")
				t.eq(w.session.result.winner, 1)
				t.deepEq(w.session.result.scores, { 20, 0 })
				run(w, 1.5)
				t.truthy(has(texts(w.gui), "You win!"), screen(w))
				t.truthy(has(chalk(w), "Ann wins!"))
				t.eq(
					last(bob.events, "event", function(m)
						return m.over == true
					end).text,
					"Ann wins!"
				)
				t.eq(w.held, false)
				-- Play again: the same two, the same game, a clean card
				click(w, "Play again")
				t.eq(last(w.sent, "again").gameId, DARTS)
				t.truthy(untilTrue(w, 2, aiming))
				t.eq(w.session.phase, "playing")
				t.eq(w.session.game.state.mode, "cricket")
				t.eq(#w.session.seats, 2)
				t.eq(w.session.game.state.players[1].marks[20], 0)
				t.falsy(has(card(w), "(X)"), "no marks on the new card")
				t.truthy(has(card(w), "CRICKET"))
			end)
		end
	)

	t.test(
		"against a computer: it throws its three darts in its turn, shown and scored like anyone's, and can finish a leg",
		function()
			play(function(w)
				seat(w)
				click(w, "+ Computer")
				t.eq(last(w.sent, "addai").gameId, DARTS)
				run(w, 0.3)
				t.eq(#w.session.seats, 2)
				local name = w.session.names[2]
				t.truthy(string.find(name, "(computer)", 1, true) ~= nil, name)
				t.falsy(string.find(name, "Bowl", 1, true) ~= nil, `a darts player, not "{name}"`)
				t.truthy(has(card(w), name))
				t.truthy(string.find(w.prompt.ObjectText, "2/4 joining", 1, true) ~= nil)
				start(w)
				-- a computer cannot be added once the game is on, and the refusal has words
				local handler = w.handler :: (player: any, payload: any) -> ()
				handler(w.player, { gameId = DARTS, seat = 1, verb = "addai", args = {} })
				run(w, 0.2)
				t.truthy(has(w.toasts, "Computers join in the lobby"))
				local g = w.session.game.state
				for _ = 1, 3 do
					t.eq(throw(w, MISS[1], MISS[2]).text, "MISS")
				end
				-- its turn: my camera and legs back, the words say who is throwing
				t.truthy(untilTrue(w, 2, function()
					return not w.held
				end))
				t.eq(g.seat, 2)
				t.truthy(has(texts(w.gui), `{name} is throwing`), screen(w))
				local mine = #w.got
				while w.got[mine].kind ~= "dart" do
					mine -= 1
				end
				local most = 0
				local frames = 0
				local over = 0
				while over < 12 and frames < 600 do
					frame(w)
					frames += 1
					-- (until its turn has passed, and the few frames its last words take to arrive)
					over += if g.seat == 2 then 0 else 1
					most = math.max(most, #stuck(w))
				end
				local saw: { number } = {}
				for i = mine + 1, #w.got do
					if w.got[i].kind == "dart" then
						t.eq(w.got[i].seat, 2)
						table.insert(saw, w.gotAt[i])
					end
				end
				t.eq(#saw, 3, "three darts, each announced")
				t.truthy((saw[1] - w.gotAt[mine]) * DT > 2, "it takes a moment to step up")
				t.truthy((saw[2] - saw[1]) * DT > 1 and (saw[3] - saw[2]) * DT > 1, "and throws one dart at a time")
				t.eq(most, 3, "each one is drawn in the board")
				t.truthy(g.players[2].score < 501, `the computer scored: {g.players[2].score} left`)
				t.truthy(has(card(w), tostring(g.players[2].score)))
				-- mine again
				t.truthy(untilTrue(w, 2, aiming))
				t.eq(w.held, true)
				t.truthy(has(texts(w.gui), "Your turn!"), screen(w))
				-- I keep missing: the computer plays the leg out and checks out on a double
				local rounds = 0
				while w.session.phase == "playing" and rounds < 25 do
					rounds += 1
					if
						untilTrue(w, 12, function()
							return aiming() or w.session.phase ~= "playing"
						end) and w.session.phase == "playing"
					then
						run(w, 0.3)
						for _ = 1, 3 do
							throw(w, MISS[1], MISS[2])
						end
					end
				end
				t.eq(w.session.phase, "done")
				t.eq(w.session.result.winner, 2, "the computer won the leg")
				t.eq(w.session.result.scores[2], 0)
				t.truthy(g.round <= 15, `it took the computer {g.round} rounds`)
				run(w, 1.5)
				local out = last(w.got, "dart")
				t.eq(out.event, "checkout")
				t.eq(out.seat, 2)
				t.truthy(string.sub(out.label, 1, 1) == "D" or out.label == "BULL", `it finished on {out.label}`)
				t.truthy(has(texts(w.gui), `{name} wins`), screen(w))
				t.truthy(has(chalk(w), `{name} wins!`))
				-- nobody presses anything: the end runs out, I am told and let go, the board is open again
				run(w, 26)
				t.eq(w.gui.Enabled, false)
				local told = w.toasts[#w.toasts]
				t.truthy(string.find(told, "dartboard", 1, true) ~= nil, told)
				t.falsy(string.find(told, "lane", 1, true) ~= nil, told)
				t.eq(w.session.phase, "idle")
				t.eq(idleShown(w), 3)
				t.eq(#stuck(w), 0)
				t.eq(FakeEngine.bound(), 0)
			end)
		end
	)

	t.test("cricket against a computer: it works down the numbers and closes them, not just the 20", function()
		play(function(w)
			seat(w, nil, "cricket")
			click(w, "+ Computer")
			run(w, 0.3)
			start(w)
			local g = w.session.game.state
			local rounds = 0
			while w.session.phase == "playing" and rounds < 25 do
				rounds += 1
				if
					untilTrue(w, 12, function()
						return aiming() or w.session.phase ~= "playing"
					end) and w.session.phase == "playing"
				then
					run(w, 0.3)
					for _ = 1, 3 do
						throw(w, MISS[1], MISS[2])
					end
				end
			end
			t.eq(w.session.phase, "done")
			t.eq(w.session.result.winner, 2)
			for _, n in Darts.CRICKET do
				t.truthy(g.players[2].marks[n] >= 3, `the computer closed {n}`)
			end
			t.truthy(g.round <= 15, `it took the computer {g.round} rounds`)
			-- I leave at the end: a table of only computers resets
			click(w, "Leave (Q)")
			run(w, 0.5)
			t.eq(w.session.phase, "idle")
			t.eq(w.gui.Enabled, false)
		end)
	end)

	t.test(
		"leaving in the middle: Q mid-throw hands everything back at once; a friend's game goes on with a clean board",
		function()
			play(function(w)
				seat(w)
				start(w)
				local tx, ty = at(20, TREBLE)
				throw(w, tx, ty)
				-- the meter is running when I press Q
				mouse(true)
				run(w, 0.3)
				t.eq((meter(w)), true)
				key(Key.Q, true)
				key(Key.Q, false)
				t.eq(last(w.sent, "leave").gameId, DARTS)
				run(w, 0.3)
				t.eq(w.gui.Enabled, false)
				t.truthy(has(w.toasts, "You left the game"))
				t.eq(w.held, false, "the orbit camera is released")
				t.eq(w.refreshed, 1)
				t.deepEq(w.controls, { false, true })
				t.eq(next(w.cursors), nil)
				t.eq((meter(w)), false)
				t.eq(marker("DartAim"), nil)
				t.eq(FakeEngine.bound(), 0)
				t.eq(w.flushed, 2)
				mouse(false)
				run(w, 0.3)
				t.eq(count(w.sent, "throw"), 1, "letting the button go after leaving throws nothing")
				t.eq(w.session.phase, "idle")
				t.eq(#stuck(w), 0, "my dart is out of the board")
				t.eq(idleShown(w), 3)
				-- with a friend: I leave on my turn with a dart in the board; it is Bob's throw on a clean board
				local bob = stub("Bob")
				seat(w, { bob })
				start(w)
				throw(w, tx, ty)
				t.eq(#stuck(w), 1)
				click(w, "Leave (Q)")
				run(w, 0.5)
				t.eq(w.gui.Enabled, false)
				t.eq(w.session.phase, "playing")
				t.eq(Session.turnKey(w.session), bob)
				t.eq(#stuck(w), 0, "the leaver's dart was pulled")
				t.eq(w.session.game.state.players[1].score, 441, "what I scored stays on my line")
				t.eq(last(bob.events, "event").text, "Your turn!")
				local bx, by = at(20, TREBLE)
				t.truthy(w.svc:debugDart(DARTS, bx, by))
				t.eq(w.session.game.state.players[2].score, 441)
				t.eq(last(bob.events, "state").view.seats[1].gone, true)
				w.svc:leave(bob, "left")
				run(w, 0.3)
				t.eq(w.session.phase, "idle")
			end)
		end
	)

	t.test(
		"every other way off the board says why: walking away, no longer a person, two turns left unplayed",
		function()
			play(function(w)
				-- walking away while a friend throws
				local bob = stub("Bob")
				seat(w, { bob })
				start(w)
				for _ = 1, 3 do
					throw(w, MISS[1], MISS[2])
				end
				untilTrue(w, 2, function()
					return not w.held
				end)
				local away = w.body.PrimaryPart.CFrame + roblox.Vector3.new(0, 0, MinigameService.WANDER + 20)
				rawset(w.body.PrimaryPart, "CFrame", away)
				run(w, 0.3)
				t.eq(w.gui.Enabled, false)
				t.truthy(has(w.toasts, "You walked away from the game"))
				t.eq(w.svc:stationOf(w.player), nil)
				w.svc:leave(bob, "left")
				rawset(w.body.PrimaryPart, "CFrame", away - roblox.Vector3.new(0, 0, MinigameService.WANDER + 20))
				run(w, 0.3)
				-- turning into a squirrel on my own turn
				seat(w)
				start(w)
				t.eq(w.held, true)
				w.species = "squirrel"
				run(w, 0.5)
				t.eq(w.gui.Enabled, false)
				t.truthy(has(w.toasts, "You were taken out of the game"))
				t.eq(w.held, false)
				t.eq(w.controls[#w.controls], true)
				t.eq(FakeEngine.bound(), 0)
				t.eq(w.session.phase, "idle")
				w.species = "human"
				run(w, 0.5)
			end)
			play(function(w)
				-- a turn left unplayed: the clock warns, the turn is skipped in words; twice and I am let go
				seat(w)
				start(w)
				local tx, ty = at(20, TREBLE)
				throw(w, tx, ty)
				t.eq(#stuck(w), 1)
				local clock = w.gui:FindFirstChild("Clock")
				local warning = w.gui:FindFirstChild("ClockWarning")
				t.eq(clock.Visible, true)
				t.eq(warning.Visible, false)
				run(w, 36)
				t.eq(warning.Visible, true, "under ten seconds the clock warns")
				t.truthy(string.find(warning.Text, "or your turn is skipped", 1, true) ~= nil, warning.Text)
				t.truthy(string.find(warning.Text, "Throw within", 1, true) ~= nil, warning.Text)
				run(w, 10)
				local told = last(w.got, "event", function(m)
					return string.find(m.text, "took too long", 1, true) ~= nil
				end)
				t.truthy(told ~= nil, "the skip is announced")
				t.truthy(string.find(told.text, "turn is skipped", 1, true) ~= nil, told.text)
				t.falsy(string.find(told.text, "frame", 1, true) ~= nil, told.text)
				t.eq(w.session.game.state.players[1].score, 441, "the dart I did throw still counts")
				t.eq(#stuck(w), 0, "and is pulled out with the turn")
				t.eq(w.session.phase, "playing")
				run(w, 46)
				t.eq(w.gui.Enabled, false)
				local why = w.toasts[#w.toasts]
				t.truthy(string.find(why, "two turns in a row", 1, true) ~= nil, why)
				t.truthy(string.find(why, "dartboard", 1, true) ~= nil, why)
				t.eq(w.session.phase, "idle")
				t.eq(w.held, false)
				t.eq(w.controls[#w.controls], true)
				t.eq(w.gui:FindFirstChild("Clock").Visible, false)
				t.eq(idleShown(w), 3)
			end)
		end
	)

	t.test(
		"rule one, the camera: the shot of the board sits inside CameraRig.hold, stays while my last dart lands, and is always given back",
		function()
			play(function(w)
				local bob = stub("Bob")
				seat(w, { bob })
				t.eq(#w.holds, 0, "the lobby has no shot: the orbit camera is the player's")
				start(w)
				t.deepEq(w.holds, { true })
				local shot = workspace.CurrentCamera.CFrame
				-- the shot looks at the bull from behind the oche
				local b = AlleyLayout.board()
				local eye = roblox.Vector3.new(AlleyLayout.toWorld(w.place, b.ocheX - 0.2, 5.1, b.d + 0.25))
				t.truthy((shot.Position - eye).Magnitude < 0.01)
				local toBull = (boardWorld(w, 0, 0) - shot.Position).Unit
				t.truthy((shot.LookVector - toBull).Magnitude < 1e-3)
				local tx, ty = at(20, TREBLE)
				throw(w, tx, ty)
				throw(w, tx, ty)
				-- the third dart: the turn passes at once on the server, but the shot stays on the board until
				-- the dart has landed (flight time and the trip there and back), then my own camera returns
				mouseAt(w, tx, ty)
				frame(w)
				mouse(true)
				run(w, 0.65)
				mouse(false)
				local sentAt = w.frames
				t.truthy(untilTrue(w, 1, function()
					return w.session.game.state.seat == 2
				end))
				run(w, 0.2)
				t.eq(w.held, true, "still on the board while the dart is in the air")
				t.falsy(aiming(), "but the aim is gone: it is not my throw")
				t.truthy(has(texts(w.gui), "Bob is throwing"), screen(w))
				t.truthy(untilTrue(w, 3, function()
					return not w.held
				end))
				local lingered = (w.frames - sentAt) * DT
				t.truthy(lingered >= 1 and lingered <= 2, `the shot stayed {lingered} s after the last dart`)
				t.truthy(lingered > 0.32 + 2 * w.lag * DT, "longer than the dart's flight")
				t.deepEq(w.holds, { true, false })
				t.eq(w.refreshed, 1)
				t.deepEq(w.controls, { false, true })
				t.eq(FakeEngine.bound(), 0)
				-- while Bob throws nothing touches the camera (the frame check would say so)
				theirTurn(w, { MISS, MISS, MISS })
				t.truthy(untilTrue(w, 2, aiming))
				t.deepEq(w.holds, { true, false, true })
				-- taken off the board in the middle of a throw: given back at once
				mouse(true)
				run(w, 0.2)
				w.svc:leave(w.player, "left")
				run(w, 0.3)
				t.deepEq(w.holds, { true, false, true, false })
				t.eq(w.refreshed, 2)
				t.eq(FakeEngine.bound(), 0)
				mouse(false)
				-- and if my turn comes straight back (Bob has gone), the shot simply stays: no hand-back between
				w.svc:leave(bob, "left")
				run(w, 0.3)
				seat(w, { bob })
				start(w)
				local n = #w.holds
				throw(w, tx, ty)
				throw(w, tx, ty)
				w.svc:leave(bob, "left")
				throw(w, tx, ty)
				t.eq(w.session.game.state.players[1].score, 501 - 180)
				t.eq(w.session.game.state.seat, 1, "Bob's turn was played out as misses on the spot")
				t.eq(#stuck(w), 3, "and my third dart was not snatched out of the air with it")
				run(w, 2)
				t.eq(#stuck(w), 0, "my three come out a beat later, as after any turn")
				t.truthy(aiming(), "my turn again")
				t.eq(#w.holds, n, "the shot was never dropped")
			end)
		end
	)

	t.test(
		"rule two, the cursor: asked for through CameraRig.wantCursor whenever the game is open, and given back when it closes",
		function()
			play(function(w)
				local bob = stub("Bob")
				t.eq(next(w.cursors), nil)
				seat(w, { bob })
				t.eq(w.cursors.minigame, true, "the lobby")
				start(w)
				-- my throw is aimed with the mouse: the cursor must be free (asked for, and the shot is held, which
				-- frees it too), never locked to the middle of the screen
				t.eq(w.cursors.minigame, true, "my throw")
				t.eq(w.held, true)
				for _ = 1, 3 do
					throw(w, MISS[1], MISS[2])
				end
				untilTrue(w, 2, function()
					return not w.held
				end)
				t.eq(w.cursors.minigame, true, "a friend's throw: Leave (Q) is on screen")
				for who in w.cursors do
					t.eq(who, "minigame", "nothing asks for the cursor on its own account")
				end
				click(w, "Leave (Q)")
				run(w, 0.3)
				t.eq(next(w.cursors), nil, "closed: the mouse is the camera's again")
				w.svc:leave(bob, "left")
			end)
		end
	)

	t.test(
		"rule three, the keys: flushed when the game opens and closes; a press from before my turn, in chat or on a button is no throw",
		function()
			play(function(w)
				local bob = stub("Bob")
				t.eq(w.flushed, 0)
				seat(w, { bob })
				t.eq(w.flushed, 1)
				click(w, "Start")
				t.truthy(untilTrue(w, 2, aiming))
				run(w, 1.2)
				for _ = 1, 3 do
					throw(w, MISS[1], MISS[2])
				end
				untilTrue(w, 2, function()
					return not w.held
				end)
				local thrown = count(w.sent, "throw")
				-- Bob is throwing; I hold Space and the mouse button (walking about, jumping)
				key(Key.Space, true, true)
				mouse(true)
				theirTurn(w, { MISS, MISS, MISS })
				-- my turn begins with both still down: no meter, and letting go throws nothing
				t.truthy(untilTrue(w, 2, aiming))
				run(w, 0.5)
				t.eq((meter(w)), false, "a press from before my turn does not run the meter")
				mouse(false)
				key(Key.Space, false)
				run(w, 0.2)
				t.eq(count(w.sent, "throw"), thrown, "and letting it go threw nothing")
				-- pressed again it works (Space is as good as the mouse button)
				key(Key.Space, true, true) -- (the control module marks Space processed: a key still counts)
				run(w, 0.65)
				t.eq((meter(w)), true)
				key(Key.Space, false)
				run(w, 0.75)
				t.eq(count(w.sent, "throw"), thrown + 1)
				-- typing in chat: Space is a letter there, not a throw
				FakeEngine.uis().focused = {}
				key(Key.Space, true, true)
				run(w, 0.5)
				t.eq((meter(w)), false, "typing does not run the meter")
				key(Key.Space, false, true)
				FakeEngine.uis().focused = nil
				run(w, 0.2)
				t.eq(count(w.sent, "throw"), thrown + 1)
				-- the Roblox menu is open
				rawset((game :: any):GetService("GuiService"), "MenuIsOpen", true)
				mouse(true)
				run(w, 0.5)
				t.eq((meter(w)), false)
				mouse(false)
				rawset((game :: any):GetService("GuiService"), "MenuIsOpen", false)
				-- a click the interface took (the Leave button) is the button's
				mouse(true, true)
				run(w, 0.5)
				t.eq((meter(w)), false)
				mouse(false, true)
				run(w, 0.2)
				t.eq(count(w.sent, "throw"), thrown + 1)
				-- a meter still running when the turn is taken away is not the next turn's throw
				throw(w, MISS[1], MISS[2])
				mouse(true)
				run(w, 0.3)
				t.eq((meter(w)), true)
				local before = count(w.sent, "throw")
				assert(w.svc:debugDart(DARTS, MISS[1], MISS[2])) -- (my third dart lands by other means)
				run(w, 0.5)
				t.eq(w.session.game.state.seat, 2)
				t.eq((meter(w)), false, "the meter is off the screen")
				theirTurn(w, { MISS, MISS, MISS })
				t.truthy(untilTrue(w, 2, aiming))
				run(w, 0.5)
				t.eq((meter(w)), false)
				mouse(false)
				run(w, 0.2)
				t.eq(count(w.sent, "throw"), before)
				click(w, "Leave (Q)")
				run(w, 0.3)
				t.eq(w.flushed, 2)
				w.svc:leave(bob, "left")
			end)
		end
	)

	t.test(
		"a real hand: the aim wobbles about the mouse, the throw is where the dot was, the server scatters it; letting go early drops it",
		function()
			play(function(w)
				seat(w)
				start(w)
				local tx, ty = at(20, TREBLE)
				mouseAt(w, tx, ty)
				local ring, dot = marker("DartMouse"), marker("DartAim")
				local far, moved = 0, 0
				local was = dot.CFrame.Position
				for _ = 1, 240 do
					frame(w)
					local rx, ry = boardMm(w, ring.CFrame.Position)
					t.truthy(math.abs(rx - tx) < 0.1 and math.abs(ry - ty) < 0.1, "the ring stays under the mouse")
					local x, y = boardMm(w, dot.CFrame.Position)
					far = math.max(far, math.sqrt((x - tx) ^ 2 + (y - ty) ^ 2))
					moved += (dot.CFrame.Position - was).Magnitude
					was = dot.CFrame.Position
				end
				t.truthy(far > 4 and far <= Darts.WOBBLE_MM * 1.5, `the dot strays up to {far} mm from the mouse`)
				t.truthy(moved > 0.05, "and never stands still")
				-- hold, let go in the green: what is sent is where the dot was, not where the mouse was
				mouse(true)
				for _ = 1, 39 do
					frame(w)
				end
				local ax, ay = boardMm(w, dot.CFrame.Position)
				mouse(false)
				local sent = last(w.sent, "throw")
				t.near(sent.args[1], ax, 0.7)
				t.near(sent.args[2], ay, 0.7)
				t.near(sent.args[3], 0.5, 0.01)
				t.truthy(math.abs(sent.args[1] - tx) > 0.5 or math.abs(sent.args[2] - ty) > 0.5, "the wobble is in it")
				run(w, 0.75)
				local said = last(w.got, "dart")
				local off = math.sqrt((said.x - sent.args[1]) ^ 2 + (said.y - sent.args[2]) ^ 2)
				t.truthy(off > 0 and off < 6 * Darts.BASE_SIGMA, `a good throw lands {off} mm from the dot`)
				local hit = Darts.scoreAt(said.x, said.y)
				t.eq(said.label, Darts.label(hit), "and is scored where it landed")
				t.eq(said.points, hit.points)
				t.eq(w.session.game.state.players[1].score, 501 - hit.points)
				-- let go early (the meter a quarter of the way up): the dart drops low
				mouseAt(w, tx, ty)
				frame(w)
				mouse(true)
				for _ = 1, 20 do
					frame(w)
				end
				local _, value = meter(w)
				mouse(false)
				sent = last(w.sent, "throw")
				t.near(sent.args[3], value, 0.02, "the timing sent is what the meter showed")
				t.truthy(sent.args[3] < 0.3)
				run(w, 0.75)
				said = last(w.got, "dart")
				t.truthy(said.y < sent.args[2] - 5, `a soft throw landed {sent.args[2] - said.y} mm low`)
			end, { steady = false })
		end
	)

	t.test(
		"touch: a finger dragged on the screen moves the aim, the HOLD TO THROW button throws and does not drag the aim to itself",
		function()
			play(function(w)
				seat(w)
				t.truthy(button(w.gui, "HOLD TO THROW") ~= nil, "a touch player gets a throw button")
				start(w)
				t.truthy(has(texts(w.gui), "Drag"), screen(w))
				local uis = FakeEngine.uis()
				local ring = marker("DartMouse")
				local x0, y0 = boardMm(w, ring.CFrame.Position)
				t.near(x0, 0, 0.5, "the aim starts on the bull")
				t.near(y0, 0, 0.5)
				-- a finger goes down on the board and drags right and up: the aim goes with it, as far on screen
				local finger = {
					KeyCode = { Name = "Unknown" },
					UserInputType = Kind.Touch,
					Position = roblox.Vector3.new(600, 700, 0),
					Delta = roblox.Vector3.new(0, 0, 0),
				}
				uis.InputBegan.fire(finger, false)
				frame(w)
				local x1, y1 = boardMm(w, ring.CFrame.Position)
				t.near(x1, 0, 0.5, "touching down does not move the aim")
				finger.Position = roblox.Vector3.new(700, 580, 0)
				uis.InputChanged.fire(finger, false)
				frame(w)
				local x2, y2 = boardMm(w, ring.CFrame.Position)
				t.truthy(x2 > 20 and y2 > 20, `the aim moved to {x2}, {y2}`)
				local a = workspace.CurrentCamera:WorldToViewportPoint(boardWorld(w, x1, y1))
				local bpx = workspace.CurrentCamera:WorldToViewportPoint(boardWorld(w, x2, y2))
				t.near(bpx.X - a.X, 100, 2, "as far across the screen as the finger went")
				t.near(bpx.Y - a.Y, -120, 2)
				-- the other thumb holds the throw button (another touch, on a button): the aim stays where it is
				local thumb = {
					KeyCode = { Name = "Unknown" },
					UserInputType = Kind.Touch,
					Position = roblox.Vector3.new(120, 1000, 0),
					Delta = roblox.Vector3.new(0, 0, 0),
				}
				uis.InputBegan.fire(thumb, true)
				button(w.gui, "HOLD TO THROW").MouseButton1Down.fire()
				thumb.Position = roblox.Vector3.new(124, 1003, 0)
				uis.InputChanged.fire(thumb, true)
				run(w, 0.65)
				t.eq((meter(w)), true)
				local x3, y3 = boardMm(w, ring.CFrame.Position)
				t.near(x3, x2, 0.01, "the throw button does not move the aim")
				t.near(y3, y2, 0.01)
				button(w.gui, "HOLD TO THROW").MouseButton1Up.fire()
				uis.InputEnded.fire(thumb, true)
				local sent = last(w.sent, "throw")
				t.near(sent.args[1], x2, 0.05)
				t.near(sent.args[2], y2, 0.05)
				t.near(sent.args[3], 0.5, 0.02)
				-- lifting the aiming finger leaves the aim; a new touch drags from there
				uis.InputEnded.fire(finger, false)
				run(w, 0.75)
				local again = {
					KeyCode = { Name = "Unknown" },
					UserInputType = Kind.Touch,
					Position = roblox.Vector3.new(300, 300, 0),
					Delta = roblox.Vector3.new(0, 0, 0),
				}
				uis.InputBegan.fire(again, false)
				frame(w)
				local x4, y4 = boardMm(w, ring.CFrame.Position)
				t.near(x4, x2, 0.01)
				t.near(y4, y2, 0.01)
				-- and it cannot be dragged off the board's surround
				again.Position = roblox.Vector3.new(5000, 300, 0)
				uis.InputChanged.fire(again, false)
				frame(w)
				local x5 = boardMm(w, ring.CFrame.Position)
				t.near(x5, Darts.MAX_AIM, 0.01)
			end, { touch = true })
		end
	)

	t.test("a wild dart sticks in the cabinet, never in thin air beyond it", function()
		play(function(w)
			local bob = stub("Bob")
			assert(w.svc:join(bob, DARTS))
			assert(w.svc:input(bob, { gameId = DARTS, seat = 1, verb = "start", args = {} }))
			run(w, 0.2)
			assert(w.svc:debugDart(DARTS, 999, -999))
			run(w, 0.5)
			local d = stuck(w)[1]
			-- (the cabinet behind the board is 1.3 studs from the bull each way)
			local edge = 1.3 / AlleyLayout.DART_MM
			t.truthy(math.abs(d.x) < edge and math.abs(d.y) < edge, `a dart thrown wild is drawn at {d.x}, {d.y}`)
			t.truthy(d.x > 250 and d.y < -250, "at the corner it flew toward")
			t.eq(w.session.game.state.lastHit.label, "MISS")
			w.svc:leave(bob, "left")
		end)
	end)

	t.test(
		"the engine check's own flow (tests/engine/DartsFlow) passes here: a nine-dart leg, busts, cricket, clean ends",
		function()
			play(function(w)
				-- the cloud check cannot be run from this machine; its flow takes any MinigameService, so it is run on
				-- this one first. What a server run adds is the real engine and the booted game.
				local function flow(svc: any): any
					return DartsFlow.play(svc, { Darts = Darts, Session = Session }, {
						players = { stub("Ann"), stub("Bob"), stub("Cat") },
						board = DARTS,
						step = function(seconds: number)
							for _ = 1, math.max(1, math.ceil(seconds / 0.1 - 1e-6)) do
								svc:step(0.1)
							end
						end,
					})
				end
				local result = flow(w.svc)
				t.eq(table.concat(result.failures, "\n"), "")
				t.truthy(result.ok)
				local legs = result.legs
				t.deepEq(legs.nine.left, { 441, 381, 321, 261, 201, 141, 81, 24, 0 })
				t.deepEq(legs.nine.scores, { 0, 340 })
				t.eq(legs.nine.winner, 1)
				t.eq(legs.nine.darts[9], "D12")
				t.deepEq(legs.busts.left, DartsFlow.LEGS.busts.left)
				t.eq(legs.busts.events, "ssssssssbsssbsbc")
				t.eq(legs.cricket.winner, 1)
				t.deepEq(legs.cricket.scores, { 20, 0 })
				t.truthy(legs.real.darts >= 3)
				t.eq(result.numbers.endLine, "Ann wins!")
				-- the check has teeth: on a service whose board scores a treble as a single it reports failures
				local honest = w.svc.debugDart
				w.svc.debugDart = function(self: any, id: string, x: number, y: number): (boolean, string?)
					local r = math.sqrt(x * x + y * y)
					if r > 99 and r < 107 then
						x, y = x * 134 / r, y * 134 / r
					end
					return honest(self, id, x, y)
				end
				local bad = flow(w.svc)
				t.falsy(bad.ok)
				t.truthy(
					string.find(
						table.concat(bad.failures, "\n"),
						"nine: a dart in the middle of T20 was scored as 20",
						1,
						true
					) ~= nil,
					table.concat(bad.failures, "\n")
				)
			end)
		end
	)

	-- (kept last: it only reads the module)
	t.test("the help card tells both games and every control, touch included", function()
		local how = table.concat(DartsClient.HELP.how, "\n")
		local keys = table.concat(DartsClient.HELP.keys, "\n")
		t.truthy(string.find(how, "501", 1, true) ~= nil and string.find(how, "Cricket", 1, true) ~= nil)
		t.truthy(string.find(how, "double", 1, true) ~= nil)
		t.truthy(string.find(keys, "Mouse", 1, true) ~= nil and string.find(keys, "Space", 1, true) ~= nil)
		t.truthy(string.find(keys, "Touch", 1, true) ~= nil, "a touch player is told how to aim")
		t.truthy(string.find(keys, "Q", 1, true) ~= nil)
	end)
end
