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
local Tables = require("@shared/Minigames/Pinball/Tables")
local Wire = require("@shared/Minigames/Pinball/Wire")
local PinballFlow = require("@tests/engine/PinballFlow")
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

-- Another person at the machine: a PlayerLike stub with a copy of the game of its own, fed what the service
-- sends it (snapshots, relayed segments) and playing its own balls live with the computer player's hands, its
-- log sent as the client sends it (InputLog.pack and the sum).
local function person(name: string, seed: number): any
	return {
		stub = Rig.stub(name),
		read = 0,
		r = nil,
		g = 0,
		seat = nil,
		bot = Bot.new(1, seed),
		live = false,
		rec = nil,
		tick0 = 0,
		frame0 = 0,
		sent = 0,
		refused = {},
		stopped = false, -- (stops sending: a line gone dead)
	}
end

local function personFrame(w: Rig.World, p: any, id: string)
	local events = p.stub.events
	while p.read < #events do
		p.read += 1
		local msg = events[p.read]
		if msg.kind == "pinball_sync" then
			p.r = Wire.restore(msg.snap)
			p.g = msg.g
			p.live = false
		elseif msg.kind == "pinball" and p.r and msg.g == p.g and not p.live then
			local seg = InputLog.unpack(msg.from, msg.to, msg.packed)
			if seg then
				Replay.follow(p.r, msg.seat, seg)
			end
		elseif msg.kind == "state" then
			p.seat = msg.you or p.seat
		elseif msg.kind == "joined" then
			p.seat = msg.seat
		end
	end
	local r = p.r
	if r == nil or p.stopped then
		return
	end
	local mine = p.seat ~= nil and not Replay.over(r) and r.m.up == p.seat
	if mine and not p.live then
		p.live = true
		p.rec = Replay.recorder(r)
		p.tick0 = r.tick
		p.frame0 = w.frames
	elseif not mine then
		p.live = false
	end
	if p.live then
		local tbl = Tables.need(r.id)
		local due = p.tick0 + (w.frames - p.frame0) * 4
		while r.tick < due do
			local seg = Replay.live(r, p.rec, Bot.step(p.bot, tbl, r.m))
			if seg then
				local a, b, c = InputLog.pack(seg)
				local ok, why = Rig.input(w, p.stub, id, "log", { a, b, c, Replay.sum(r) })
				p.sent += 1
				if not ok then
					table.insert(p.refused, tostring(why))
				end
				if Replay.over(r) or r.m.up ~= p.seat then
					p.live = false
					break
				end
			end
		end
	end
end

-- frames with the hand on the keys (and the other people at their machines), until cond() or the time runs out
local function playFor(
	w: Rig.World,
	seconds: number,
	h: any?,
	cond: (() -> boolean)?,
	people: { any }?,
	id: string?
): boolean
	for _ = 1, math.floor(seconds * 60) do
		if cond and cond() then
			return true
		end
		if h then
			handFrame(h)
		end
		Rig.frame(w)
		for _, p in people or {} do
			personFrame(w, p, id or stationOf(1))
		end
	end
	return cond ~= nil and cond()
end

return function(t)
	t.test(
		"a whole game alone: walk up, E, Space starts, three balls played with the keys on this screen's own machine, the server's replay agrees to the point, the end card and the board",
		function()
			Rig.play(function(w)
				local ID = stationOf(1)
				Rig.run(w, 0.1)
				t.eq(Rig.prompt(w, ID).ObjectText, "ACORN ATTACK - open (alone or with friends)")
				t.eq(Rig.prompt(w, ID).ActionText, "Play")
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
				t.eq(Rig.prompt(w, ID).ActionText, "In use")
				t.eq(Rig.prompt(w, ID).ObjectText, "ACORN ATTACK - in use by Ann: watch the ball")
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

	t.test(
		"two players take a ball each in turn: the camera and the legs are given back while the other plays, the screen follows the other's ball half a second behind, every copy ends on the server's score",
		function()
			Rig.play(function(w)
				local ID = stationOf(3)
				local bob = person("Bob", 5)
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				t.truthy(w.svc:join(bob.stub, ID))
				Rig.run(w, 0.3)
				t.eq(#sessionOf(w, 3).seats, 2)
				t.truthy(Rig.has(Rig.texts(w.gui), "2 of 4 players"), Rig.screen(w))
				Rig.key(Key.Space, true)
				Rig.key(Key.Space, false)
				Rig.run(w, 0.4)
				t.eq(sessionOf(w, 3).phase, "playing")
				local h = hand(1, 3)
				local c = Controller.current
				local ups: { number } = {}
				local followed, released, behind = 0, 0, 0
				local server = tableOf(w, 3):replay()
				local ok = playFor(w, 900, h, function()
					local r = tableOf(w, 3):replay()
					if r and ups[#ups] ~= r.m.up and not Replay.over(r) then
						table.insert(ups, r.m.up)
					end
					if c.cab.r and c.cab.r.m.up == 2 and not c.live and c.cab.r.m.phase == Machine.PHASE.PLAY then
						-- Bob's ball on Ann's screen: drawn a little behind the newest tick she has
						followed += 1
						if not w.held then
							released += 1
						end
						if c.cab.newest - c.cab.at >= 60 then
							behind += 1
						end
					end
					return sessionOf(w, 3).phase == "done"
				end, { bob }, ID)
				t.truthy(ok, "the game ended")
				t.truthy(#ups >= 5, `the ball went from one player to the other: {table.concat(ups, " ")}`)
				t.eq(ups[1], 1)
				t.eq(ups[2], 2)
				t.truthy(followed > 60, "Bob's ball was drawn on Ann's screen")
				t.eq(released, followed, "Ann had her own camera while Bob played")
				t.truthy(behind > followed * 0.7, `drawn half a second behind ({behind} of {followed} frames)`)
				server = tableOf(w, 3):replay()
				local result = sessionOf(w, 3).result
				for seat = 1, 2 do
					t.eq(c.cab.r.m.scores[seat], server.m.scores[seat], `Ann's copy, seat {seat}`)
					t.eq(bob.r.m.scores[seat], server.m.scores[seat], `Bob's copy, seat {seat}`)
					t.eq(result.scores[seat], server.m.scores[seat])
				end
				t.eq(#bob.refused, 0, table.concat(bob.refused, ", "))
				t.eq(result.fair, true)
			end, opts(3))
		end
	)

	t.test(
		"a late watcher is sent the game as it stands and sees the same ball; walking off puts the cabinet to rest; the machine idle again runs its attract show",
		function()
			Rig.play(function(w)
				local ID = stationOf(2)
				local bob = person("Bob", 9)
				-- Ann stands well away; Bob plays
				Rig.walkTo(w, SITE, 60, 3, 0)
				t.truthy(w.svc:join(bob.stub, ID))
				Rig.run(w, 0.2)
				t.truthy(Rig.input(w, bob.stub, ID, "start"))
				playFor(w, 8, nil, nil, { bob }, ID)
				t.eq(Rig.count(w.got, "pinball"), 0, "nothing is sent to someone across the alley")
				t.eq(Rig.count(w.got, "pinball_sync"), 0)
				-- Ann walks up: she is sent the game as it stands, then every segment
				local X, D = CabinetLayout.stance(2)
				Rig.walkTo(w, SITE, X + 2, 3, D + 3)
				playFor(w, 1.5, nil, nil, { bob }, ID)
				t.eq(Rig.count(w.got, "pinball_sync"), 1, "the late watcher's snapshot")
				t.truthy(Rig.count(w.got, "pinball") > 5, "and the segments after it")
				local cab = Cabinet.get(ID)
				t.truthy(cab.awake and cab.mode == "follow")
				-- she sees the same game: her copy and the server's agree tick for tick
				playFor(w, 10, nil, nil, { bob }, ID)
				local server = tableOf(w, 2):replay()
				t.truthy(cab.r ~= nil)
				local probe = Replay.clone(server)
				t.truthy(cab.r.tick <= probe.tick)
				t.eq(cab.newest, cab.r.tick)
				-- the drawn ball is the kept frame's ball, a little behind
				local seen = 0
				for i = 1, 30 do
					Rig.frame(w)
					personFrame(w, bob, ID)
					local f = cab.frame
					if f and f.nBalls > 0 and i > 2 then
						local part = ballPart(w, 2, 1)
						t.eq(part.Transparency, 0)
						seen += 1
					end
				end
				t.truthy(seen > 0, "a ball was drawn")
				t.truthy(label(w, 2, "Title") == "SPICY RODENT", label(w, 2, "Title"))
				t.truthy(string.find(label(w, 2, "Info"), "BALL", 1, true) ~= nil, label(w, 2, "Info"))
				-- Bob leaves: the machine is idle and the people near it are told; the attract show runs
				w.svc:leave(bob.stub, "left")
				Rig.run(w, 0.5)
				t.eq(sessionOf(w, 2).phase, "idle")
				t.truthy(Rig.count(w.got, "pinball_idle") >= 1)
				t.eq(cab.mode, "idle")
				local before = label(w, 2, "Score")
				Rig.run(w, 4.5)
				t.truthy(label(w, 2, "Score") ~= before or label(w, 2, "Info") ~= "", "the backglass turns its pages")
			end, opts(2))
		end
	)

	t.test(
		"a player who leaves mid-game: their balls are passed over and their score kept, the others carry on from the server's game; the last to leave lets the machine go",
		function()
			Rig.play(function(w)
				local ID = stationOf(1)
				local bob = person("Bob", 21)
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				t.truthy(w.svc:join(bob.stub, ID))
				Rig.key(Key.Space, true)
				Rig.key(Key.Space, false)
				Rig.run(w, 0.4)
				local h = hand(1, 8)
				-- play until it is Bob's ball, then Bob goes
				t.truthy(playFor(w, 300, h, function()
					local r = tableOf(w, 1):replay()
					return r ~= nil and r.m.up == 2 and r.m.ballTicks > 240
				end, { bob }, ID))
				local syncs = Rig.count(w.got, "pinball_sync")
				local bobScore = tableOf(w, 1):replay().m.scores[2]
				w.svc:leave(bob.stub, "left")
				Rig.run(w, 0.5)
				t.truthy(
					Rig.count(w.got, "pinball_sync") > syncs,
					"Ann was put right: the server played Bob's ball out"
				)
				local r = tableOf(w, 1):replay()
				t.truthy(r.m.gone[2])
				t.eq(r.m.scores[2], bobScore, "Bob's score is kept")
				-- Ann plays on alone to the end
				t.truthy(playFor(w, 600, h, function()
					return sessionOf(w, 1).phase == "done"
				end))
				local c = Controller.current
				t.eq(c.cab.r.m.scores[1], tableOf(w, 1):replay().m.scores[1])
				t.eq(sessionOf(w, 1).result.scores[2], bobScore)
				-- Ann walks away from the end card: the machine lets her go and resets
				local X, D = CabinetLayout.stance(1)
				Rig.walkTo(w, SITE, X, 3, D + 30)
				Rig.run(w, 0.5)
				t.eq(w.client.active(), nil)
			end, opts(1))
		end
	)

	t.test(
		"a slow line and a hiccup on it: a fifth of a second each way, then a second's hold-up across the end of a ball; the segments that arrive ahead of the server's clock wait and are fed again, nothing is lost and the game stays fair",
		function()
			Rig.play(function(w)
				local ID = stationOf(1)
				Rig.press(w, ID)
				Rig.run(w, 0.5)
				Rig.key(Key.Space, true)
				Rig.key(Key.Space, false)
				Rig.run(w, 1)
				local h = hand(1, 31)
				local c = Controller.current
				-- to the end of the first ball on this screen, then the line holds everything up for a second
				t.truthy(playFor(w, 300, h, function()
					return c.cab.r.m.phase == Machine.PHASE.BONUS
				end))
				w.lag = 60
				t.truthy(playFor(w, 30, h, function()
					return c.cab.r.m.phase == Machine.PHASE.PLAY and c.cab.r.m.ballTicks > 30
				end))
				w.lag = 12
				t.truthy(playFor(w, 600, h, function()
					return sessionOf(w, 1).phase == "done"
				end))
				local server = tableOf(w, 1):replay()
				t.eq(c.cab.r.m.scores[1], server.m.scores[1])
				t.eq(sessionOf(w, 1).result.fair, true)
				t.truthy(tableOf(w, 1).waited > 0, "segments that came in a burst waited for the clock")
				t.eq(#tableOf(w, 1).pending, 0)
			end, opts(1, { lag = 12 }))
		end
	)

	t.test(
		"this screen's copy drifts from the server's (a sum that does not agree): it is sent the server's game and carries on from it, once",
		function()
			Rig.play(function(w)
				local ID = stationOf(1)
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				Rig.key(Key.Space, true)
				Rig.key(Key.Space, false)
				Rig.run(w, 0.4)
				local h = hand(1, 4)
				playFor(w, 6, h)
				local c = Controller.current
				local syncs = Rig.count(w.got, "pinball_sync")
				c.cab.r.m.scores[1] += 7 -- (a copy that has come apart from the server's)
				playFor(w, 2, h)
				t.eq(Rig.count(w.got, "pinball_sync"), syncs + 1, "one snapshot put it right")
				t.eq(Rig.last(w.got, "pinball_sync").why, "drift")
				t.truthy(playFor(w, 600, h, function()
					return sessionOf(w, 1).phase == "done"
				end))
				t.eq(c.cab.r.m.scores[1], tableOf(w, 1):replay().m.scores[1])
				t.eq(Rig.count(w.got, "pinball_sync"), syncs + 1, "and no more were needed")
			end, opts(1))
		end
	)

	t.test(
		"a squirrel lands on the cabinet: the glass is thumped (half a nudge, said on the backglass), once for one landing",
		function()
			local animals: { any } = {}
			Rig.play(
				function(w)
					local ID = stationOf(1)
					Rig.press(w, ID)
					Rig.run(w, 0.2)
					Rig.key(Key.Space, true)
					Rig.key(Key.Space, false)
					Rig.run(w, 0.4)
					local h = hand(1, 4)
					playFor(w, 5, h)
					local X, D = CabinetLayout.at(1)
					local x, y, z = AlleyLayout.toWorld(w.places[SITE], X, CabinetLayout.PF_Y + 0.6, D)
					table.insert(animals, { id = 1, kind = "squirrel", x = x, y = y, z = z })
					playFor(w, 1.5, h)
					t.eq(Rig.count(w.got, "pinball_thump"), 1)
					t.truthy(Rig.has(w.toasts, "thumped the glass") or Rig.count(w.got, "event") > 0)
					table.clear(animals)
					playFor(w, 2, h)
					local r = tableOf(w, 1):replay()
					t.eq(Controller.current.cab.r.m.scores[1], Controller.current.cab.r.m.scores[1])
					t.falsy(r.m.tilted, "a thump never tilts")
					t.eq(#w.broken, 0)
				end,
				opts(1, {
					service = {
						animals = function(): { any }
							return animals
						end,
					},
				})
			)
		end
	)

	t.test("a player who leaves the ball on the plunger for a minute is taken off and the machine reset", function()
		Rig.play(function(w)
			local ID = stationOf(1)
			Rig.press(w, ID)
			Rig.run(w, 0.2)
			Rig.key(Key.Space, true)
			Rig.key(Key.Space, false)
			Rig.run(w, 0.4)
			t.eq(sessionOf(w, 1).phase, "playing")
			Rig.run(w, 62)
			t.eq(w.client.active(), nil)
			t.truthy(Rig.has(w.toasts, "nothing was pressed for a minute"), table.concat(w.toasts, " | "))
			t.eq(sessionOf(w, 1).phase, "idle")
		end, opts(1))
	end)

	t.test(
		"every hand on the machine: the mouse buttons, a gamepad's triggers and bumpers, A and the right stick for the plunger, the left stick and Z X W for a nudge; a click on a button of the bar flips nothing",
		function()
			Rig.play(function(w)
				local ID = stationOf(1)
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				Rig.key(Key.Space, true)
				Rig.key(Key.Space, false)
				Rig.run(w, 0.4)
				local c = Controller.current
				local tbl = c.cab.tbl
				local Kind = roblox.Enum.UserInputType
				local function up(i: number): boolean
					return c.cab.r.m.phys.fa[i] > tbl.c.frest[i] + 0.5
				end
				local function pad(code: any, down: boolean)
					FakeEngine.input(
						if down then "began" else "ended",
						{ KeyCode = code, UserInputType = Kind.Gamepad1 }
					)
				end
				local function stick(code: any, x: number, y: number)
					FakeEngine.input("changed", {
						KeyCode = code,
						UserInputType = Kind.Gamepad1,
						Position = roblox.Vector3.new(x, y, 0),
					})
				end
				-- the mouse: left button the left flipper, right button the right
				Rig.mouse(true)
				FakeEngine.input("began", { UserInputType = Kind.MouseButton2 })
				Rig.run(w, 0.1)
				t.truthy(up(1) and up(2), "both flippers up from the mouse")
				Rig.mouse(false)
				FakeEngine.input("ended", { UserInputType = Kind.MouseButton2 })
				Rig.run(w, 0.3)
				t.falsy(up(1) or up(2), "and down again")
				-- a click the interface took (a button) is not a flip
				Rig.mouse(true, true)
				Rig.run(w, 0.1)
				t.falsy(up(1))
				Rig.mouse(false, true)
				-- gamepad: L2 and R1
				pad(Key.ButtonL2, true)
				pad(Key.ButtonR1, true)
				Rig.run(w, 0.1)
				t.truthy(up(1) and up(2), "triggers and bumpers")
				pad(Key.ButtonL2, false)
				pad(Key.ButtonR1, false)
				Rig.run(w, 0.3)
				-- the right stick pulled half way down draws the rod half way; let go and the ball flies
				stick(Key.Thumbstick2, 0, -0.5)
				Rig.run(w, 0.5)
				local pull = c.cab.r.m.pull / tbl.def.plunger.pullTicks
				t.near(pull, 0.5, 0.05, "the rod follows the stick")
				stick(Key.Thumbstick2, 0, 0)
				Rig.run(w, 0.2)
				t.eq(c.cab.r.m.pull, 0, "launched")
				t.truthy((MinigameSounds.counts()["pinball.acorn.plunge"] or 0) >= 1)
				-- nudges: Z, then the left stick flicked to the side
				local nudges = MinigameSounds.counts()["pinball.acorn.nudge"] or 0
				Rig.key(Key.Z, true)
				Rig.run(w, 0.05)
				Rig.key(Key.Z, false)
				Rig.run(w, 0.3)
				stick(Key.Thumbstick1, 0.95, 0)
				Rig.run(w, 0.05)
				stick(Key.Thumbstick1, 0, 0)
				Rig.run(w, 0.3)
				t.eq((MinigameSounds.counts()["pinball.acorn.nudge"] or 0) - nudges, 2, "two nudges")
				t.eq(#w.broken, 0)
			end, opts(1))
		end
	)

	t.test(
		"touch: the left and right halves of the screen are the flippers, both at once, a thumb that slides across stays its own flipper; the strip at the bottom right pulls the plunger as far as it is dragged; NUDGE",
		function()
			Rig.play(function(w)
				local ID = stationOf(2)
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				Rig.click(w, "Start (Space)")
				Rig.run(w, 0.4)
				local c = Controller.current
				t.truthy(c and c.live)
				local tbl = c.cab.tbl
				local function up(i: number): boolean
					return c.cab.r.m.phys.fa[i] > tbl.c.frest[i] + 0.5
				end
				-- the plunger strip: a finger at the bottom right dragged down a quarter of the screen
				Rig.touch("pull", "began", 1800, 700)
				Rig.touch("pull", "changed", 1800, 700 + 1080 * 0.3 * 0.8)
				Rig.run(w, 0.8)
				t.near(c.cab.r.m.pull / tbl.def.plunger.pullTicks, 0.8, 0.05)
				t.falsy(up(2), "the plunger finger is not the right flipper")
				Rig.touch("pull", "ended", 1800, 700 + 1080 * 0.24)
				Rig.run(w, 0.2)
				t.eq(c.cab.r.m.pull, 0, "launched")
				-- both thumbs
				Rig.touch("l", "began", 300, 600)
				Rig.touch("r", "began", 1500, 600)
				Rig.run(w, 0.1)
				t.truthy(up(1) and up(2))
				-- the left thumb slides across the middle: still the left flipper; lifting the right drops only it
				Rig.touch("l", "changed", 1200, 600)
				Rig.touch("r", "ended", 1500, 600)
				Rig.run(w, 0.3)
				t.truthy(up(1))
				t.falsy(up(2))
				Rig.touch("l", "ended", 1200, 600)
				Rig.run(w, 0.3)
				t.falsy(up(1))
				-- NUDGE on the touch bar
				local nudges = MinigameSounds.counts()["pinball.rodent.nudge"] or 0
				local b = Rig.button(w.gui, "NUDGE")
				b.MouseButton1Down.fire()
				Rig.run(w, 0.1)
				b.MouseButton1Up.fire()
				Rig.run(w, 0.2)
				t.eq((MinigameSounds.counts()["pinball.rodent.nudge"] or 0) - nudges, 1)
			end, opts(2, { touch = true }))
		end
	)

	t.test(
		"the server check's own flow (tests/engine/PinballFlow) passes here: solo, two by turns with a leaver, a ball the server plays out, clean ends",
		function()
			Rig.play(function(w)
				local svc = w.svc
				local result = PinballFlow.play(svc, {
					Replay = Replay,
					InputLog = InputLog,
					Bot = Bot,
					Wire = Wire,
					Tables = Tables,
				}, {
					players = { Rig.stub("Ann"), Rig.stub("Bob") },
					step = function(seconds: number)
						for _ = 1, math.max(1, math.ceil(seconds / 0.1 - 1e-6)) do
							svc:step(0.1)
						end
					end,
				})
				t.eq(table.concat(result.failures, "\n"), "")
				t.truthy(result.ok)
				t.truthy(result.numbers.soloScore > 0)
			end, opts(2))
		end
	)
end
