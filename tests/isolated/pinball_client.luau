--!strict
-- tests/isolated/pinball_client.luau: cases for tests/unit/pinball_client.spec.luau, run in their own Lune
-- process (tests/lib/Isolated) because they install the fake engine.
-- Pinball played through all of its glue at once on tests/lib/MinigameRig: the real MinigameService with the
-- game's Table (Server/Minigames/Games/Pinball) and the model's rules and replay, the real MinigameClient with
-- MinigameUI, the game's Controller, Hands and Cabinet, the fake lagged network with the real Net's schema and
-- rate limit between them, and the three cabinets' moving parts as fake parts under the names the bake gives
-- them (tests/unit/pinball_bake.spec.luau holds the bake to the same names). The player's hands are real key,
-- mouse, gamepad and touch events; in the whole games they are driven by the model's own computer player
-- (Pinball/Bot, NOVICE) reading what this screen shows, so a whole game goes keys -> the player's own machine
-- -> the log -> the server's replay -> the score of record.
-- Other people are PlayerLike stubs who play their balls with a Replay of their own (stubPlay()).
-- Interface: return function(t) (the spec shape)
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Bot = require("@shared/Minigames/Pinball/Bot")
local CabinetLayout = require("@shared/Minigames/Pinball/Cabinet")
local InputLog = require("@shared/Minigames/Pinball/InputLog")
local Machine = require("@shared/Minigames/Pinball/Machine")
local Replay = require("@shared/Minigames/Pinball/Replay")
local Stream = require("@shared/Minigames/Pinball/Stream")
local Tables = require("@shared/Minigames/Pinball/Tables")
local Wire = require("@shared/Minigames/Pinball/Wire")
local Cabinet = require("@client/Minigames/Pinball/Cabinet")
local Controller = require("@client/Minigames/Pinball/Controller")
local MinigameSounds = require("@client/Minigames/MinigameSounds")
local FakeEngine = require("@tests/lib/FakeEngine")
local Rig = require("@tests/lib/MinigameRig")
local roblox = require("@lune/roblox")

local SITE = "bowling_alley"
local Key = roblox.Enum.KeyCode
local BTN = Machine.BTN

local function stationOf(index: number): string
	return `pinball_{index}`
end

-- What the bake leaves in the games room, as far as the game looks for it: each machine's moving parts by name.
local function furnish(roots: { [string]: any }, places: { [string]: any })
	Cabinet.reset()
	Controller.current = nil
	table.clear(MinigameSounds.counts())
	local place = places[SITE]
	local room = FakeEngine.new("Folder", "GamesRoom")
	room.Parent = roots[SITE]
	local N = CabinetLayout.NAMES
	for index, p in AlleyLayout.PINBALLS do
		local tbl = Tables.need(Tables.forVariant(p.theme) :: string)
		local function at(X: number, Y: number, D: number): any
			return roblox.CFrame.new(AlleyLayout.toWorld(place, X, Y, D))
		end
		local X, D = CabinetLayout.at(index)
		local model = FakeEngine.model(CabinetLayout.model(index), at(X, CabinetLayout.PF_Y, D), room)
		local function part(name: string): any
			local q = FakeEngine.part(name, at(X, CabinetLayout.PF_Y, D), model)
			q.Color = roblox.Color3.fromRGB(200, 120, 40)
			return q
		end
		for i = 1, CabinetLayout.BALLS do
			part(`{N.ball}{i}`)
		end
		for i = 1, #tbl.def.flippers do
			local f = FakeEngine.model(`{N.flipper}{i}`, at(X, CabinetLayout.PF_Y, D), model)
			f.PrimaryPart = FakeEngine.part("Hub", at(X, CabinetLayout.PF_Y, D), f)
		end
		for i, t in tbl.def.targets do
			if t.kind == "drop" then
				part(`{N.drop}{i}`)
			end
		end
		for k = 1, #tbl.c.spinners do
			part(`{N.spinner}{k}`)
		end
		for i = 1, #tbl.def.lamps do
			part(`{N.lamp}{i}`)
		end
		for i = 1, #tbl.def.bumpers do
			part(`{N.bumper}{i}`)
		end
		for i = 1, #tbl.def.slings do
			part(`{N.sling}{i}`)
		end
		local plunger = FakeEngine.model(N.plunger, at(X, CabinetLayout.PF_Y, D + 2.6), model)
		plunger.PrimaryPart = FakeEngine.part("Rod", at(X, CabinetLayout.PF_Y, D + 2.6), plunger)
		local glass = part(N.backglass)
		local gui = FakeEngine.new("SurfaceGui", "Display")
		gui.Parent = glass
		for _, name in { "Title", "Score", "Info", "Say", "Best" } do
			local label = FakeEngine.new("TextLabel", name)
			label.Text = ""
			label.Parent = gui
		end
	end
end

local function opts(index: number, more: { [string]: any }?): Rig.Opts
	local X, D = CabinetLayout.stance(index)
	local o: any = { furnish = furnish, stand = { site = SITE, x = X, y = 3, d = D } }
	for k, v in more or {} do
		o[k] = v
	end
	return o
end

local function tableOf(w: Rig.World, index: number): any
	return w.svc.stations[stationOf(index)].tbl
end

local function sessionOf(w: Rig.World, index: number): any
	return w.svc:sessionOf(stationOf(index))
end

local function label(w: Rig.World, index: number, name: string): string
	local model = w.roots[SITE]:FindFirstChild("GamesRoom"):FindFirstChild(CabinetLayout.model(index))
	return model:FindFirstChild(CabinetLayout.NAMES.backglass):FindFirstChild("Display"):FindFirstChild(name).Text
end

local function ballPart(w: Rig.World, index: number, i: number): any
	local model = w.roots[SITE]:FindFirstChild("GamesRoom"):FindFirstChild(CabinetLayout.model(index))
	return model:FindFirstChild(`{CabinetLayout.NAMES.ball}{i}`)
end

-- The player's hands driven by the model's computer player, through real key presses: each frame it looks at
-- the game this screen is playing and holds the keys it wants (Left Shift, Right Shift, Space).
local KEYS = { [BTN.LEFT] = Key.LeftShift, [BTN.RIGHT] = Key.RightShift, [BTN.PLUNGE] = Key.Space }
local function hand(level: number, seed: number): any
	return { bot = Bot.new(level, seed), down = {} }
end
local function handFrame(h: any)
	local c = Controller.current
	local want = 0
	if c and c.live and c.cab.r then
		want = Bot.step(h.bot, c.cab.tbl, c.cab.r.m)
	end
	for b, code in KEYS do
		local on = bit32.band(want, b) ~= 0
		if on ~= (h.down[b] == true) then
			h.down[b] = on
			Rig.key(code, on)
		end
	end
end

-- frames with the hand on the keys, until cond() or the time runs out
local function playFor(w: Rig.World, seconds: number, h: any?, cond: (() -> boolean)?): boolean
	for _ = 1, math.floor(seconds * 60) do
		if cond and cond() then
			return true
		end
		if h then
			handFrame(h)
		end
		Rig.frame(w)
	end
	return cond ~= nil and cond()
end

return function(t)
	t.test(
		"a whole game alone: walk up, E, Space starts, three balls played with the keys on this screen's own machine, the server's replay agrees to the point, the end card and the board",
		function()
			Rig.play(function(w)
				local ID = stationOf(1)
				Rig.press(w, ID)
				Rig.run(w, 0.3)
				t.eq(w.client.active(), ID)
				t.truthy(Rig.has(Rig.texts(w.gui), "ACORN ATTACK"), Rig.screen(w))
				t.eq(sessionOf(w, 1).phase, "lobby")
				-- Space starts at once (the controller sends it, once)
				Rig.key(Key.Space, true)
				Rig.key(Key.Space, false)
				Rig.run(w, 0.4)
				t.eq(sessionOf(w, 1).phase, "playing")
				t.eq(Rig.count(w.sent, "start"), 1)
				local c = Controller.current
				t.truthy(c and c.live, "this player's ball is played here")
				t.truthy(w.held, "the camera is on the playfield")
				t.eq(w.controls[#w.controls], false, "the legs are the machine's")
				-- the whole game, the hand on the keys
				local h = hand(1, 11)
				local ended = playFor(w, 600, h, function()
					return sessionOf(w, 1).phase == "done"
				end)
				t.truthy(ended, "the game ended")
				local view = w.svc:sessionOf(ID)
				local result = view.result
				t.truthy(result ~= nil)
				-- the score of record is the server's replay; this screen's copy came to the same game
				local server = tableOf(w, 1):replay()
				t.truthy(server ~= nil and Replay.over(server))
				local mine = c.cab.r
				t.eq(mine.m.scores[1], server.m.scores[1], "this screen and the server agree to the point")
				t.eq(result.scores[1], server.m.scores[1])
				t.truthy(result.scores[1] > 0, `a game scores something ({result.scores[1]})`)
				t.eq(result.fair, true, "played in time: the game may take a place on the board")
				-- ten messages a second at most, never a message a frame
				local logs = Rig.count(w.sent, "log")
				local seconds = server.tick / 240
				t.truthy(logs <= seconds * 11.5 + 5, `{logs} log messages in {seconds} s of play`)
				t.truthy(logs >= seconds * 5, `{logs} log messages in {seconds} s of play`)
				-- the end card, the camera and the legs back, the board on the cabinet
				Rig.run(w, 0.3)
				t.truthy(Rig.has(Rig.texts(w.gui), "Play again"), Rig.screen(w))
				t.falsy(w.held, "the camera is the player's again")
				local best = w.roots[SITE]:FindFirstChild("GamesRoom"):FindFirstChild("Pinball1"):GetAttribute("Best")
				t.truthy(type(best) == "string" and string.find(best, "OLD OAK", 1, true) ~= nil, tostring(best))
				-- sounds were asked for by name, the machine's own set
				local counts = MinigameSounds.counts()
				t.truthy((counts["pinball.acorn.flip_up"] or 0) > 0, "flipper sounds")
				t.truthy((counts["pinball.acorn.drain"] or 0) > 0, "drain sounds")
				Rig.key(Key.Q, true)
				Rig.run(w, 0.3)
				t.eq(w.client.active(), nil)
			end, opts(1))
		end
	)
end
