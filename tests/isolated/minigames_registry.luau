--!strict
-- tests/isolated/minigames_registry.luau: cases for tests/unit/minigames_registry.spec.luau, run in their own
-- Lune process (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- The minigame registry (Shared/Minigames/Games, Server/Minigames/ServerGames, Client/Minigames/ClientGames):
-- that the three lists line up and the framework's own files name no game; and that a game nobody under src/
-- has heard of (tests/lib/FakeGames, registered at run time) is a whole game: it stands at its station with its
-- prompt, seats whoever presses E, runs its controller, shows its card and reports a result, through the real
-- MinigameService and the real MinigameClient joined by a fake lagged network (tests/lib/MinigameRig).
-- One tiny game per KIND the registry carries: turns (test_coin), a real-time rally (test_rally), a continuous
-- single-player machine (test_machine), a team match (test_match), plus a game that is only a Spec and rules
-- (test_plain) and one that is not built yet (test_soon).
-- Interface: return function(t) (the spec shape)
-- (FakeGames first: it registers its games, and the wire's verb list is read from the registry when
-- Shared/Net/Schemas loads)
local FakeGames = require("@tests/lib/FakeGames")
local Data = require("@shared/Data")
local Games = require("@shared/Minigames/Games")
local Schema = require("@shared/Util/Schema")
local Schemas = require("@shared/Net/Schemas")
local Session = require("@shared/Minigames/Session")
local Sites = require("@shared/Minigames/Sites")
local AttractionService = require("@server/Attractions/AttractionService")
local MinigameService = require("@server/Minigames/MinigameService")
local ServerGames = require("@server/Minigames/ServerGames")
local ClientGames = require("@client/Minigames/ClientGames")
local MinigameSounds = require("@client/Minigames/MinigameSounds")
local FakeEngine = require("@tests/lib/FakeEngine")
local Rig = require("@tests/lib/MinigameRig")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local SITE, PLACE, S = FakeGames.SITE, FakeGames.PLACE, FakeGames.STATIONS
local Key = roblox.Enum.KeyCode

local function opts(more: { [string]: any }?): Rig.Opts
	local o: any = { sites = { [SITE] = PLACE }, furnish = FakeGames.furnish }
	for k, v in more or {} do
		o[k] = v
	end
	return o
end

local function real(spec: any): boolean
	return string.sub(spec.game, 1, 5) ~= "test_"
end

-- a source file with its comments taken out
local function code(path: string): string
	local out = {}
	for line in string.gmatch(fs.readFile(path), "[^\n]+") do
		table.insert(out, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(out, "\n")
end

-- the client sends a verb straight down its remote (a game whose controller binds no key for it)
local function fire(w: Rig.World, station: string, verb: string, args: { any }?)
	w.input:FireServer({ gameId = station, seat = 1, verb = verb, args = args or {} })
end

return function(t)
	t.test("one line per game in each registry: every Spec is sound and has its server and client line", function()
		local seen: { [string]: boolean } = {}
		local built = 0
		for _, spec in Games.ALL do
			local ok, err = Games.check(spec)
			t.truthy(ok, `{spec.game}: {tostring(err)}`)
			t.falsy(seen[spec.game], `{spec.game} is listed twice`)
			seen[spec.game] = true
			if real(spec) then
				local hasServer, hasClient = false, false
				for _, e in ServerGames.LIST do
					hasServer = hasServer or e.game == spec.game
				end
				for _, e in ClientGames.LIST do
					hasClient = hasClient or e.game == spec.game
				end
				t.truthy(hasServer, `{spec.game} has no line in Server/Minigames/ServerGames`)
				t.truthy(hasClient, `{spec.game} has no line in Client/Minigames/ClientGames`)
				-- (a game that is not built yet says `soon`: its stub lines exist all the same)
				if spec.soon == nil then
					built += 1
				end
			end
		end
		t.truthy(built >= 3, "bowling, darts and the fortune teller are built")
		for _, game in { "bowling", "darts", "fortune_machine" } do
			local spec = Games.get(game) :: any
			t.truthy(spec and spec.soon == nil and spec.rules.def.game == game, game)
			t.truthy(ServerGames.get(game) ~= nil, `{game}: server half`)
			t.truthy((ClientGames.get(game) :: any).help ~= nil, `{game}: client half`)
		end
		-- a line with no Spec is a mistake too
		for _, e in ServerGames.LIST do
			t.truthy(Games.get(e.game) ~= nil, `ServerGames lists {e.game}, which has no Spec`)
		end
		for _, e in ClientGames.LIST do
			t.truthy(Games.get(e.game) ~= nil, `ClientGames lists {e.game}, which has no Spec`)
		end
	end)

	t.test(
		"the framework's own files name no game: no game's id in their code, no require of a game's module",
		function()
			local files = {
				"src/server/Minigames/MinigameService.luau",
				"src/server/Minigames/ServerGame.luau",
				"src/client/Minigames/MinigameClient.luau",
				"src/client/Minigames/ClientGame.luau",
				"src/client/UI/MinigameUI.luau",
				"src/shared/Minigames/Session.luau",
				"src/shared/Minigames/Minigame.luau",
				"src/shared/Minigames/GameSpec.luau",
			}
			for _, path in files do
				local src = code(path)
				for _, spec in Games.ALL do
					t.eq(string.find(src, `"{spec.game}"`, 1, true), nil, `{path} names the game {spec.game}`)
				end
				for _, folder in { "Games/", "MinigameRules/", "Bowling", "Dartboard", "FortuneCabinet", "DartsClient" } do
					for line in string.gmatch(src, "[^\n]+") do
						if string.find(line, "require", 1, true) then
							t.eq(string.find(line, folder, 1, true), nil, `{path} requires a game's module: {line}`)
						end
					end
				end
			end
			-- and the fake games are nowhere under src/ at all, yet every case below plays them
			for _, path in files do
				t.eq(string.find(fs.readFile(path), "test_coin", 1, true), nil)
			end
		end
	)

	t.test("Games.check turns a bad Spec away with the reason; a game cannot be registered twice", function()
		local good = Games.get("test_coin") :: any
		local function with(change: { [string]: any }): any
			local spec = table.clone(good)
			for k, v in change do
				spec[k] = v
			end
			return spec
		end
		local function refused(spec: any, needle: string)
			local ok, err = Games.check(spec)
			t.falsy(ok, needle)
			t.truthy(string.find(tostring(err), needle, 1, true), `{needle}: {tostring(err)}`)
		end
		t.truthy(Games.check(good))
		refused(with({ flow = "sometimes" }), "flow")
		refused(with({ verbs = { "flip" } }), "server verb") -- only the table flips
		refused(with({ game = "test_other" }), "rules.def.game")
		refused(with({ rules = FakeGames.Rally }), "rules.def.game")
		refused(with({ soon = "" }), "soon")
		refused(with({ computers = { { skill = 1 } } }), "computers")
		refused(with({ prompt = {} }), "prompt")
		refused(with({ stations = false }), "stations")
		-- a turn-based game must say whose turn it is
		local noTurn = table.clone(FakeGames.Coin)
		noTurn.turn = nil :: any
		refused(with({ rules = noTurn }), "rules.turn")
		t.fails(function()
			Games.register(good)
		end, "already registered")
		t.fails(function()
			ServerGames.register({
				game = "test_coin",
				new = function(): any
					return {}
				end,
			})
		end, "already registered")
		-- a message kind belongs to one game, and never to the framework
		t.fails(function()
			ClientGames.register({ game = "test_thief", kinds = { "coin_flip" } })
		end, "belongs to")
		t.fails(function()
			ClientGames.register({ game = "test_thief2", kinds = { "state" } })
		end, "framework")
		t.eq(ClientGames.get("test_thief"), nil)
		t.eq((ClientGames.ownerOf("coin_flip") :: any).game, "test_coin")
		t.eq((ClientGames.ownerOf("roll") :: any).game, "bowling")
		t.eq(MinigameSounds.CUES["test_coin.flip"], "", "a game's sound cues are added as it registers")
	end)

	t.test(
		"a game's verbs reach the wire by being in its Spec; stations come from the Specs, in registry order",
		function()
			local verbs = Games.verbs()
			for i = 2, #verbs do
				t.truthy(verbs[i - 1] < verbs[i], "sorted, no duplicates")
			end
			for _, v in
				{ "leave", "start", "again", "addai", "mode", "release", "throw", "pull", "call", "hit", "fire" }
			do
				t.truthy(table.find(verbs, v), v)
			end
			t.eq(table.find(verbs, "log") ~= nil, true, "the machine's log is a client verb")
			t.eq(table.find(verbs, "flip"), nil, "the coin's flip is the table's own: never on the wire")
			t.eq(table.find(verbs, "machine_settle"), nil, "a server verb is never on the wire")
			local payload = Schemas.REMOTES["Minigame.Input"].payload :: any
			t.truthy(Schema.check(payload, { gameId = S.coin, seat = 1, verb = "call", args = { "heads" } }))
			t.falsy(Schema.check(payload, { gameId = S.coin, seat = 1, verb = "dance", args = {} }))
			-- the bowling alley alone: the fourteen stations it has always had, the built ones first and in the order
			-- their seeded streams were numbered in
			local alley = Sites.fromData(Data.default(), false)
			t.truthy(alley.bowling_alley ~= nil)
			local list = Games.stations(alley)
			local ids = {}
			for _, st in list do
				table.insert(ids, st.id)
				t.eq(st.site, "bowling_alley")
				t.eq((Games.get(st.game) :: any).game, st.game)
			end
			t.truthy(#list >= 14, `{#list} stations in the alley`)
			t.eq(
				table.concat(ids, " ", 1, 8),
				"bowling_lane_1 bowling_lane_2 bowling_lane_3 bowling_lane_4 bowling_lane_5 bowling_lane_6 darts_1 fortune_1"
			)
			t.eq((Games.station("darts_1", alley) :: any).label, "Dartboard")
			t.eq((Games.station(S.machine, { [SITE] = PLACE }) :: any).variant, "retro")
			t.eq(Games.station(S.machine, alley), nil, "a station is only on the site it stands on")
			t.eq(#Games.stations({}), 0, "no sites, no stations")
			-- every site there is: ids stay unique and every station stands on a site that exists
			local all = Sites.fromData(Data.default())
			for _, venue in { "f3_racquet_club", "f3_steakhouse", "f2_doctor", "f3_tv_station" } do
				t.truthy(all[venue] ~= nil and type(all[venue].yaw) == "number", `{venue} is a site`)
			end
			all[SITE] = PLACE
			local seen: { [string]: boolean } = {}
			for _, st in Games.stations(all) do
				t.falsy(seen[st.id], st.id)
				seen[st.id] = true
				t.truthy(all[st.site] ~= nil, `{st.id} stands on {st.site}`)
			end
			for _, id in S do
				t.truthy(seen[id], id)
			end
		end
	)

	t.test("the server takes its sites from the baked models: Site and the Origin attributes", function()
		FakeEngine.with(function()
			local folder = FakeEngine.new("Folder", "Attractions")
			local hall = FakeEngine.new("Model", "anything")
			hall:SetAttribute("Site", SITE)
			hall:SetAttribute("OriginX", PLACE.x)
			hall:SetAttribute("OriginZ", PLACE.z)
			hall:SetAttribute("FloorY", PLACE.floorY)
			hall:SetAttribute("Yaw", PLACE.yaw)
			hall.Parent = folder
			FakeEngine.new("Model", "NoOrigin").Parent = folder
			local sites = AttractionService.sites(folder)
			t.deepEq(sites[SITE].place, PLACE)
			t.truthy(sites[SITE].root == hall)
			local n = 0
			for _ in sites do
				n += 1
			end
			t.eq(n, 1, "a model with no origin is not a site")
			-- the service puts every registered game's stations on the sites it is handed, and only those
			local svc = MinigameService.new({ sites = sites, prompts = false })
			t.eq(#svc.order, 7, "six games, and the rally court's second way in")
			t.truthy(svc.stations[S.coin] ~= nil and svc.stations.bowling_lane_1 == nil)
			t.truthy(svc.stations[S.coin].tbl ~= nil and svc.stations[S.plain].tbl == nil)
			t.eq(svc:sessionOf(S.soon), nil)
		end)
	end)

	t.test(
		"turns: a game nobody under src/ has heard of stands at its station, seats a player, runs its controller and reports a result",
		function()
			Rig.play(function(w)
				local ID = S.coin
				local session = w.svc:sessionOf(ID)
				local tbl = FakeGames.tables[ID]
				local prompt = Rig.prompt(w, ID)
				-- the station: its prompt, in its site's own folder, with the Spec's words
				t.truthy(prompt.Parent.Parent == w.roots[SITE]:FindFirstChild("MinigamePrompts"))
				t.eq(prompt:GetAttribute("Minigame"), "test_coin")
				t.eq(prompt.ActionText, "Flip a coin")
				t.eq(prompt.ObjectText, "Coin table - open (alone, with friends, or against a computer)")
				t.truthy(w.svc.stations[ID].hw.coin ~= nil, "the Table found its hardware under the site's model")
				t.eq(tbl.hw.board:GetAttribute("Text"), "COIN TOSS", "the world scoreboard was drawn once at rest")
				-- E: seated, and the client opens the game from the registry
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				t.eq(w.client.active(), ID)
				t.eq(w.player:GetAttribute("InMinigame"), ID)
				local joined = Rig.last(w.got, "joined")
				t.eq(joined.site, SITE)
				t.deepEq(joined.place, PLACE)
				local all = Rig.texts(w.gui)
				t.truthy(Rig.has(all, "Coin toss - Coin table"), Rig.screen(w))
				t.truthy(Rig.has(all, "Z  heads"), "the help card lists the game's keys")
				t.truthy(Rig.has(w.toasts, "You joined Coin table"))
				t.eq(prompt.ActionText, "Join")
				t.eq(prompt.ObjectText, "Coin table - 1/2 joining, starting soon")
				local c = FakeGames.controllers.test_coin
				t.truthy(
					c ~= nil and c.ctx.station == ID and c.ctx.place ~= nil,
					"the controller was made with its Ctx"
				)
				-- the lobby: a computer from the Spec, then the start
				Rig.click(w, "Add a computer")
				Rig.run(w, 0.2)
				t.eq(session.names[2], "Heads-up Hal (computer)")
				Rig.click(w, "Start now")
				Rig.run(w, 0.3)
				t.eq(session.phase, "playing")
				t.truthy(Rig.last(w.got, "event", function(m)
					return m.text == "Game on!"
				end))
				t.eq(prompt.ActionText, "In use")
				t.eq(prompt.ObjectText, "Coin table - game on (2 playing): wait for the next toss")
				-- my call: the controller has the camera (inside CameraRig.hold) and the keys
				t.truthy(c.mine)
				t.truthy(w.held, "the game's shot is held")
				t.eq(workspace.CurrentCamera.CameraType, roblox.Enum.CameraType.Scriptable)
				t.eq(w.controls[#w.controls], false, "the player's legs were taken for the call")
				t.truthy(Rig.has(Rig.texts(w.gui), "Your call: Z heads, X tails"))
				t.truthy(Rig.button(w.gui, "Start now") == nil and Rig.button(w.gui, "Leave (Q)") ~= nil)
				Rig.key(Key.Z, true)
				Rig.key(Key.Z, false)
				Rig.run(w, 0.3)
				local call = Rig.last(w.sent, "call")
				t.deepEq(call.args, { "heads" })
				t.eq(call.gameId, ID)
				-- the server decided the flip and told everyone; the watch hook saw it; so did the controller
				local flip = Rig.last(w.got, "coin_flip")
				t.truthy(flip and flip.station == ID and flip.site == SITE and flip.seat == 1 and flip.n == 1)
				t.truthy(flip.side == "heads" or flip.side == "tails")
				local saw = FakeGames.seen[#FakeGames.seen]
				t.truthy(saw.game == "test_coin" and saw.msg.n == 1)
				t.deepEq(saw.place, PLACE)
				local heard = Rig.last(c.messages, "coin_flip")
				t.deepEq(heard.watched, { flip = 1 }, "what watch returned reaches the seated controller")
				t.truthy((MinigameSounds.counts()["test_coin.flip"] or 0) >= 1, "the game's cue was asked for")
				t.eq(tbl.hw.coin:GetAttribute("Side"), flip.side, "the hardware was posed")
				local mine = if flip.side == "heads" then 1 else 0
				t.eq(session.game.state.score[1], mine)
				t.truthy(
					Rig.has(Rig.texts(w.gui:FindFirstChild("Scorecard")), `Ann (you): {mine} right`),
					Rig.screen(w)
				)
				t.truthy(string.find(tbl.hw.board:GetAttribute("Text"), `Ann {mine} - Heads-up Hal`, 1, true))
				-- not my turn now: the camera and my legs are back, and an input out of turn is refused with words
				t.falsy(c.mine)
				t.falsy(w.held)
				t.eq(w.controls[#w.controls], true)
				fire(w, ID, "call", { "tails" })
				Rig.run(w, 0.2)
				t.truthy(Rig.has(w.toasts, "Not your turn yet"))
				t.eq(c.refused, 1)
				-- the computer takes its go (the Spec's `bias` rode on its key), then it is mine again
				t.truthy(
					Rig.untilTrue(w, 6, function()
						return c.mine
					end),
					"the turn came back"
				)
				local theirs = Rig.last(w.got, "coin_flip")
				t.truthy(theirs.seat == 2 and theirs.call == "heads" and theirs.n == 2)
				Rig.key(Key.X, true)
				Rig.key(Key.X, false)
				t.truthy(
					Rig.untilTrue(w, 6, function()
						return session.phase == "done"
					end),
					"the game ends after two calls each"
				)
				Rig.run(w, 0.3)
				-- the result: the rules', announced once, on the end card, and the table free for the next
				local r = session.result
				t.truthy(r.done and #r.scores == 2)
				local over = Rig.last(w.got, "event", function(m)
					return m.over == true
				end)
				t.eq(over.text, if r.winner then `{session.names[r.winner]} wins!` else "Game over!")
				local card = w.gui:FindFirstChild("Summary")
				t.truthy(card.Visible, "the end card is up")
				t.truthy(Rig.has(Rig.texts(card), "COIN TOSS"))
				t.truthy(Rig.has(Rig.texts(card), if r.winner then "called it best" else "All square"))
				t.eq(prompt.ActionText, "Flip a coin")
				t.eq(Rig.count(w.got, "event") >= 2, true)
				-- play again, then leave in the middle: everything is handed back, the table comes to rest
				Rig.click(w, "Play again")
				Rig.run(w, 0.3)
				t.eq(session.phase, "playing")
				t.truthy(c.mine and w.held)
				local flushed = w.flushed
				Rig.key(Key.Q, true)
				Rig.run(w, 0.3)
				t.eq(w.client.active(), nil)
				t.eq(w.gui.Enabled, false)
				t.eq(w.player:GetAttribute("InMinigame"), nil)
				t.truthy(c.stopped, "the controller was stopped")
				t.falsy(w.held)
				t.eq(w.controls[#w.controls], true)
				t.truthy(w.flushed > flushed, "pending input was flushed at the hand-over")
				t.truthy(Rig.has(w.toasts, "You left the game"))
				t.eq(session.phase, "idle", "only the computer was left: the table reset")
				t.truthy(table.find(tbl.events, "left") and tbl.events[#tbl.events] == "reset")
				t.eq(tbl.hw.coin:GetAttribute("Side"), nil)
				t.eq(prompt.ActionText, "Flip a coin")
			end, opts())
		end
	)

	t.test(
		"turns: a watcher sees the same flip; a scripted outcome goes through the game's own path; a station's reach",
		function()
			Rig.play(function(w)
				local ID = S.coin
				local bob, cy = Rig.stub("Bob"), Rig.stub("Cy")
				t.truthy(w.svc:join(bob, ID))
				t.truthy(w.svc:join(cy, ID))
				local full, why = w.svc:join(Rig.stub("Di"), ID)
				t.falsy(full)
				t.eq(why, "the table is full")
				t.truthy(Rig.input(w, bob, ID, "start"))
				local before = #FakeGames.seen
				t.truthy(Rig.input(w, bob, ID, "call", { "tails" }))
				Rig.run(w, 0.2)
				-- the player never joined: no game is open, yet the game's `watch` was handed the flip and where
				-- the site stands (read from the baked model)
				t.eq(w.client.active(), nil)
				t.eq(w.gui.Enabled, false)
				t.eq(#FakeGames.seen, before + 1)
				local saw = FakeGames.seen[#FakeGames.seen]
				t.truthy(saw.msg.kind == "coin_flip" and saw.msg.seat == 1 and saw.msg.call == "tails")
				t.deepEq(saw.place, PLACE)
				t.truthy(Rig.last(bob.events, "coin_flip") and Rig.last(cy.events, "coin_flip"), "the seated stubs too")
				-- out of turn, a wrong argument, a verb of another game: refused, each with words
				local ok, words = Rig.input(w, bob, ID, "call", { "tails" })
				t.truthy(not ok and words == "Not your turn yet")
				ok, words = Rig.input(w, cy, ID, "call", { "edge" })
				t.truthy(not ok and words == "Call heads or tails")
				ok, words = Rig.input(w, cy, ID, "hit")
				t.truthy(not ok and words == "That does not work at this game")
				ok, words = Rig.input(w, cy, ID, "flip", { "heads", "heads" })
				t.truthy(not ok, "a server verb cannot be sent by a player")
				-- the engine checks script an outcome through the game's own Table
				t.truthy(w.svc:debug(ID, "heads"))
				t.eq(w.svc:sessionOf(ID).game.state.score[2], 1, "seat 2 called heads and heads it was")
				local no, whyNot = w.svc:debug(S.plain)
				t.truthy(not no and whyNot == "nothing can be scripted there")
				-- an idle turn is played out, in the game's own word for it
				Rig.run(w, 10.5)
				t.truthy(Rig.last(bob.events, "event", function(m)
					return m.text == "Bob took too long: that call is skipped"
				end))
				Rig.input(w, bob, ID, "leave")
				Rig.input(w, cy, ID, "leave")
				-- the station's own reach (12 studs here, not the service's 70): walk off and you are taken out
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				t.eq(w.client.active(), ID)
				Rig.walkTo(w, SITE, 10, 3, 0)
				Rig.run(w, 0.2)
				t.eq(w.client.active(), ID, "ten studs is still at the table")
				Rig.walkTo(w, SITE, 15, 3, 0)
				Rig.run(w, 0.2)
				t.eq(w.client.active(), nil)
				t.truthy(Rig.has(w.toasts, "You walked away from the game"))
				-- an animal is turned away at any station, with words
				w.species = "squirrel"
				Rig.walkTo(w, SITE, 0, 3, 0)
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				t.eq(w.client.active(), nil)
				t.truthy(Rig.has(w.toasts, "Only people can play here"))
			end, opts())
		end
	)

	t.test(
		"live: the rules move the ball between inputs, either seat hits at any moment, each hit is one message, a seat can be faulted",
		function()
			Rig.play(function(w)
				local ID = S.rally
				local session = w.svc:sessionOf(ID)
				local tbl = FakeGames.tables[ID]
				local bob = Rig.stub("Bob")
				local rest = tbl.hw.ball.CFrame
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				t.truthy(w.svc:join(bob, ID))
				Rig.run(w, 0.2)
				-- (no buttons of its own: the framework's lobby bar, with a computer on offer because the Spec has one)
				t.truthy(Rig.button(w.gui, "Start now") and Rig.button(w.gui, "Add a computer"))
				Rig.key(Key.Space, true)
				Rig.run(w, 0.2)
				t.eq(session.phase, "playing")
				t.eq(Session.turn(session), nil, "nobody's turn")
				local c = FakeGames.controllers.test_rally
				local state = session.game.state
				t.truthy(state.pos > 5 and state.dir == 1, "the ball is already flying: rules.step moved it")
				-- too early for either seat: refused with the game's words, never with "not your turn"
				Rig.key(Key.F, true)
				Rig.run(w, 0.2)
				t.eq(c.refused[1], "The ball is going away from you")
				local ok, why = Rig.input(w, bob, ID, "hit")
				t.truthy(not ok and why == "Too early: wait for the ball")
				-- Bob hits when it reaches him; the one message of that hit reaches my controller
				t.truthy(Rig.untilTrue(w, 3, function()
					return state.pos >= 7.5
				end))
				t.truthy(Rig.input(w, bob, ID, "hit"))
				Rig.run(w, 0.2)
				t.eq(#c.legs, 1)
				t.truthy(c.legs[1].seat == 2 and c.legs[1].dir == -1 and c.legs[1].from >= 7.5)
				-- and I hit it back, with my own key, while keeping my own legs and camera
				t.truthy(Rig.untilTrue(w, 4, function()
					return state.pos <= 2.5
				end))
				Rig.key(Key.F, true)
				Rig.run(w, 0.2)
				t.eq(state.hits, 2)
				t.eq(state.dir, 1)
				t.eq(#c.legs, 2)
				t.eq(#w.controls, 0, "a rally never takes the player's legs")
				t.eq(#w.holds, 0, "nor the camera")
				t.truthy(tbl.hw.ball.CFrame ~= rest, "the Table moved its ball")
				-- nobody hits: it passes Bob's end, a point to me, and the next ball is on its way
				t.truthy(Rig.untilTrue(w, 5, function()
					return state.score[1] == 1
				end))
				t.truthy(
					Rig.untilTrue(w, 2, function()
						return Rig.has(Rig.texts(w.gui), "1 - 0")
					end),
					Rig.screen(w)
				)
				-- a server verb for a named seat (there is no turn to say whose it is): Bob is faulted twice
				t.truthy(w.svc:debug(ID, "fault", 2))
				t.truthy(w.svc:debug(ID, "fault", 2))
				Rig.run(w, 0.3)
				t.eq(session.phase, "done")
				t.eq(session.result.winner, 1)
				t.deepEq(session.result.scores, { 3, 0 })
				t.truthy(Rig.last(w.got, "event", function(m)
					return m.over == true and m.text == "Ann wins!"
				end))
				t.truthy(Rig.button(w.gui, "Play again") ~= nil)
			end, opts())
		end
	)

	t.test(
		"live: a computer opponent plays in real time; a seat that stands idle is taken off, and the rules hear it",
		function()
			Rig.play(function(w)
				local ID = S.rally
				local session = w.svc:sessionOf(ID)
				local tbl = FakeGames.tables[ID]
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				Rig.click(w, "Add a computer")
				Rig.run(w, 0.1)
				Rig.click(w, "Start now")
				Rig.run(w, 0.3)
				t.eq(session.phase, "playing")
				local state = session.game.state
				-- I never touch a key. The computer returns the first ball without anyone handing it a turn
				t.truthy(
					Rig.untilTrue(w, 3, function()
						return tbl.legs >= 1
					end),
					"the computer hit the ball"
				)
				t.eq(state.hits, 1)
				-- six seconds without an input: off the court, told why in the game's words
				t.truthy(Rig.untilTrue(w, 8, function()
					return w.client.active() == nil
				end))
				local left = Rig.last(w.got, "left")
				t.eq(left.why, "idle")
				t.truthy(Rig.has(w.toasts, "You were taken off the court: you stood still too long"))
				t.truthy(w.frames > 6 * 60 and w.frames < 7 * 60, `after the idle time, not before ({w.frames} frames)`)
				t.eq(state.forfeit, 1, "rules.gone was told which seat went")
				t.eq(session.phase, "idle", "only the computer was left: the court reset")
			end, opts())
		end
	)

	t.test(
		"solo: the client steps the machine at once and logs its inputs; the server replays each segment of the log to the tick it declares and settles the same score",
		function()
			Rig.play(function(w)
				local ID = S.machine
				local session = w.svc:sessionOf(ID)
				local tbl = FakeGames.tables[ID]
				local prompt = Rig.prompt(w, ID)
				t.eq(prompt.ActionText, "Play")
				t.eq(prompt.ObjectText, "The machine", "a fixed second line, whatever the machine is doing")
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				-- one seat: no lobby, no "Game on!"; the station's index and variant reached the client
				t.eq(session.phase, "playing")
				t.truthy(Rig.has(Rig.texts(w.gui), "Machine 2 (retro)"), Rig.screen(w))
				t.eq(Rig.last(w.got, "event"), nil)
				local c = FakeGames.controllers.test_machine
				t.truthy(c.ctx.index == 2 and c.ctx.variant == "retro")
				-- launch: the ball is in play on this screen in the same frame; the server's copy follows
				Rig.key(Key.Space, true)
				t.truthy(c.sim ~= nil and tbl.sim == nil)
				t.eq(w.controls[#w.controls], false, "the machine reads the keys itself")
				Rig.run(w, 0.1)
				t.truthy(tbl.sim ~= nil and session.game.state.launched)
				t.truthy(Rig.untilTrue(w, 2, function()
					return tbl.sim.tick >= 6
				end))
				t.truthy(
					tbl.sim.tick < c.sim.tick,
					"the server's replay follows the log: it is never ahead of the screen"
				)
				-- what the server will not take: a segment that does not start where the last one ended, one that
				-- claims more of the game than the time since the launch allows, one that cannot be read. Each is
				-- refused with words and changes nothing
				local at = tbl.sim.tick
				local ok, why = Rig.input(w, w.player, ID, "log", { at + 3, at + 9, "" })
				t.truthy(not ok and why == "That part of the game arrived out of order", tostring(why))
				ok, why = Rig.input(w, w.player, ID, "log", { at, at + 100, "" })
				t.truthy(not ok and why == "That part of the game is ahead of the clock", tostring(why))
				ok, why = Rig.input(w, w.player, ID, "log", { at, at + 2, "5" })
				t.truthy(not ok and why == "That part of the game could not be read", tostring(why))
				t.eq(tbl.sim.tick, at)
				-- two good flips, each felt at once here; the server replays it when its segment arrives
				for n = 1, 2 do
					t.truthy(Rig.untilTrue(w, 3, function()
						return c.sim.y <= 2.5 and c.sim.vy < 0
					end))
					local sent = #w.sent
					Rig.key(Key.F, true)
					t.eq(#w.sent, sent, "a flip is not a message: it goes into the log")
					Rig.frame(w)
					t.eq(c.sim.score, n * 10, "the flip landed on this screen in the next frame")
					t.eq(tbl.sim.score, (n - 1) * 10, "the server has not replayed that tick yet")
					t.truthy(tbl.sim.tick < c.sim.tick)
					if n == 1 then
						-- one long frame: this screen loses half a second (its step is clamped) and from here on
						-- runs that far behind the server's own count of the time. Nothing it does is refused for it
						c.acc -= 0.5
					end
				end
				t.eq(
					#c.refused,
					0,
					"nothing was refused: the server replays to the tick it is told, not to its own clock"
				)
				-- no more flips: the ball drains here first, then the server's replay reaches the same end
				t.truthy(Rig.untilTrue(w, 6, function()
					return c.sim.over
				end))
				t.eq(session.phase, "playing", "the server has not settled yet")
				t.truthy(Rig.untilTrue(w, 2, function()
					return session.phase == "done"
				end))
				Rig.run(w, 0.2)
				t.eq(session.result.scores[1], 20)
				t.eq(session.result.scores[1], c.sim.score, "the server's replay and the screen agree on the score")
				t.eq(session.result.ticks, c.sim.tick, "and on the tick the ball was lost")
				t.eq(c.final, 20)
				-- the whole game went up as segments of the log: about ten messages a second, every one accepted
				local logs = Rig.count(w.sent, "log")
				t.eq(logs, tbl.segments, "every segment sent was replayed")
				t.truthy(
					logs >= c.sim.tick / 8 and logs <= c.sim.tick / 6 + 1,
					`{logs} segments for {c.sim.tick} ticks`
				)
				local flipsSent = 0
				for _, m in w.sent do
					if m.verb == "log" and m.args[3] ~= "" then
						flipsSent += 1
						t.truthy(
							type(m.args[3]) == "string" and #m.args[3] <= 200,
							"the flips travel packed in one string"
						)
					end
				end
				t.eq(flipsSent, 2)
				t.truthy(
					Rig.last(w.got, "event", function(m)
						return m.over == true and m.text == "Ball lost: 20 points"
					end),
					"the Table's own end banner"
				)
				-- watchers were sent the pose a few times a second, not every tick
				t.truthy(c.poses >= 4 and c.poses == tbl.sent and tbl.sent <= c.sim.tick / 15)
				t.truthy(FakeGames.seen[#FakeGames.seen].game == "test_machine")
			end, opts())
		end
	)

	t.test("solo: a machine nobody plays lets its player go after the idle time", function()
		Rig.play(function(w)
			local ID = S.machine
			Rig.press(w, ID)
			Rig.run(w, 2.9)
			t.eq(w.client.active(), ID)
			Rig.run(w, 0.4)
			t.eq(w.client.active(), nil)
			t.eq(Rig.last(w.got, "left").why, "idle")
			t.truthy(Rig.has(w.toasts, "The machine timed out"))
			t.eq(w.svc:sessionOf(ID).phase, "idle")
			t.eq(w.controls[#w.controls], nil, "the legs were never taken, so there was nothing to give back")
		end, opts())
	end)

	t.test(
		"match: computers fill the sides, a player joins while it is on, the arena replaces the walk-away radius, a side wins",
		function()
			Rig.play(function(w)
				local ID = S.match
				local session = w.svc:sessionOf(ID)
				local prompt = Rig.prompt(w, ID)
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				t.eq(session.phase, "lobby")
				Rig.click(w, "Start now")
				Rig.run(w, 0.3)
				-- the start: one person and three computers (the Spec's `fill`), odd seats red, even seats blue
				t.eq(session.phase, "playing")
				t.eq(#session.seats, 4)
				t.eq(session.names[1], "Ann")
				t.truthy(string.find(session.names[4], "(computer)", 1, true))
				t.eq(session.game.seats, 4)
				t.eq(prompt.ActionText, "Join")
				t.eq(prompt.ObjectText, "Tag arena - game on (4 playing): join in")
				local c = FakeGames.controllers.test_match
				-- my input goes to the Table, which applies the rules' server verb for my seat
				fire(w, ID, "fire", { 2 })
				fire(w, ID, "fire", { 3 })
				Rig.run(w, 0.3)
				t.eq(session.game.state.tags.red, 1)
				t.truthy(Rig.has(w.toasts, "That is your own side"))
				-- Bob walks up while the match is on and is given a seat (on the red side: seat 5)
				local bob = Rig.stub("Bob")
				t.truthy(w.svc:join(bob, ID))
				t.eq(Session.seatOf(session, bob), 5)
				t.eq(Rig.last(bob.events, "joined").seat, 5)
				t.eq(session.game.state.n, 5, "rules.join was told")
				Rig.run(w, 0.2)
				t.eq(#c.view.seats, 5)
				-- the arena is the Table's to judge: a hundred studs from the prompt is still in the match ...
				Rig.walkTo(w, SITE, 100, 3, 400)
				Rig.run(w, 0.3)
				t.eq(w.client.active(), ID)
				t.truthy(100 > MinigameService.WANDER)
				-- ... and outside it is out: Bob is told, the rules hear he has gone, and his seat can be retaken
				bob.body = FakeEngine.model("Bob", roblox.CFrame.new(0, 0, 0), nil)
				bob.body.PrimaryPart = FakeEngine.part("HumanoidRootPart", roblox.CFrame.new(0, 0, 0), bob.body)
				bob.body:PivotTo(roblox.CFrame.new(PLACE.x + 9000, 0, PLACE.z))
				Rig.run(w, 0.1)
				t.eq(Rig.last(bob.events, "left").why, "too far")
				t.truthy(session.game.state.out[5])
				local cy = Rig.stub("Cy")
				t.truthy(w.svc:join(cy, ID))
				t.eq(Session.seatOf(session, cy), 5, "the vacated seat first")
				t.falsy(session.game.state.out[5])
				-- the red bot tags once a second; nobody on the blue side does: red wins on the clock
				t.truthy(Rig.untilTrue(w, 10, function()
					return session.phase == "done"
				end))
				Rig.run(w, 0.3)
				local r = session.result
				t.eq(r.side, "red")
				t.deepEq(r.winners, { 1, 3, 5 })
				t.truthy(r.scores[1] >= 5 and r.scores[2] == 0)
				t.truthy(c.tags >= 5, "the Table's own messages reached the controller")
				local over = Rig.last(w.got, "event", function(m)
					return m.over == true
				end)
				t.eq(over.text, r.text)
				t.truthy(string.find(over.text, "The red side wins", 1, true))
				-- the end card: the game's own columns and foot line
				local card = w.gui:FindFirstChild("Summary")
				local words = Rig.texts(card)
				t.truthy(
					card.Visible and Rig.has(words, "FULL TIME") and Rig.has(words, "SIDE"),
					table.concat(words, " | ")
				)
				t.truthy(Rig.has(words, "RED") and Rig.has(words, "BLUE") and Rig.has(words, "The arena reopens in"))
				-- nobody presses anything: the card runs out, the arena resets, everyone is told
				Rig.run(w, 6.5)
				t.eq(session.phase, "idle")
				t.eq(w.client.active(), nil)
				t.eq(Rig.last(w.got, "left").why, "finished")
				t.eq(Rig.last(cy.events, "left").why, "finished")
				t.eq(prompt.ActionText, "Join the match")
			end, opts({ stand = { site = SITE, x = 0, y = 3, d = 400 } }))
		end
	)

	t.test(
		"a Spec and rules are a whole game: no server half, no client half; a Spec that says soon turns people away",
		function()
			Rig.play(function(w)
				local ID = S.plain
				local session = w.svc:sessionOf(ID)
				t.eq(ServerGames.get("test_plain"), nil)
				t.eq(ClientGames.get("test_plain"), nil)
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				t.eq(w.client.active(), ID)
				t.eq(session.phase, "playing")
				t.truthy(Rig.has(Rig.texts(w.gui), "Tilt box"), Rig.screen(w))
				t.truthy(Rig.button(w.gui, "Leave (Q)") ~= nil)
				-- its verb goes straight to its rules
				for _ = 1, 3 do
					fire(w, ID, "tilt", { 0.5 })
				end
				fire(w, ID, "pull")
				Rig.run(w, 0.3)
				t.eq(session.phase, "done")
				t.deepEq(session.result.scores, { 3 })
				t.truthy(
					Rig.has(w.toasts, "The game is over: Play again or Leave (Q)"),
					"the fourth input came after the end"
				)
				t.truthy(Rig.last(w.got, "event", function(m)
					return m.over == true and m.text == "Game over!"
				end))
				Rig.click(w, "Play again")
				Rig.run(w, 0.2)
				t.eq(session.phase, "playing")
				fire(w, ID, "pull")
				Rig.run(w, 0.2)
				t.truthy(Rig.has(w.toasts, "That does not work at this game"))
				Rig.key(Key.Q, true)
				Rig.run(w, 0.2)
				t.eq(w.client.active(), nil)
				-- not built yet: the prompt says so, and so is whoever presses it; nothing is seated
				local soon = Rig.prompt(w, S.soon)
				t.eq(soon.ActionText, "Play (soon)")
				t.eq(soon.ObjectText, "Covered table")
				Rig.press(w, S.soon)
				Rig.run(w, 0.2)
				t.eq(w.client.active(), nil)
				t.truthy(Rig.has(w.toasts, "This one opens in a later build. Try the coin table!"))
				t.eq(w.svc:stationOf(w.player), nil)
			end, opts({ stand = { site = SITE, x = 90, y = 3, d = 0 } }))
		end
	)
end
