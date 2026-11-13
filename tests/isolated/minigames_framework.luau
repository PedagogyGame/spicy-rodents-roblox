--!strict
-- tests/isolated/minigames_framework.luau: cases for tests/unit/minigames_framework.spec.luau, run in their own
-- Lune process (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- What a review of the minigame framework found, each finding pinned by a case, on the real MinigameService and
-- the real MinigameClient (tests/lib/MinigameRig) with the games that exist only in specs (tests/lib/FakeGames)
-- and, where the finding was about one, the real fortune teller:
--   the paper card never outlives its game, and a reveal belongs to the pull that started it;
--   a linger timer closes only the game that started it;
--   a game's own keys are read before the framework's (Q, gamepad B, Space), "" swallows one, a game sets the
--     walking pace and the framework puts it back, and F is not a kick while a game is open;
--   the rig's network is the real Net: a controller that sends a message a frame is caught, and only
--     Minigame.Input / Minigame.State are carried;
--   what a Table may ask of the rest of the town (ctx.town), with a stand-in behind every member;
--   a second prompt that joins another station's game;
--   computer players by name, per table, removed to make room, and a game started again by its Table;
--   one game's Table cannot take the others down (new() or step() that throws; a site without its furniture);
--   the two clocks (the service's own and the shared one) and a finger that stays one InputObject.
-- Interface: return function(t) (the spec shape)
-- (FakeGames first: it registers its games, and the wire's verb list is read from the registry when
-- Shared/Net/Schemas loads)
local FakeGames = require("@tests/lib/FakeGames")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Data = require("@shared/Data")
local Games = require("@shared/Minigames/Games")
local Session = require("@shared/Minigames/Session")
local Sites = require("@shared/Minigames/Sites")
local AttractionService = require("@server/Attractions/AttractionService")
local MinigameService = require("@server/Minigames/MinigameService")
local ServerGames = require("@server/Minigames/ServerGames")
local Human = require("@client/Controllers/Human")
local InputMap = require("@client/Input/InputMap")
local FakeEngine = require("@tests/lib/FakeEngine")
local Rig = require("@tests/lib/MinigameRig")
local roblox = require("@lune/roblox")

local SITE, PLACE, S = FakeGames.SITE, FakeGames.PLACE, FakeGames.STATIONS
local Key = roblox.Enum.KeyCode
local F = AlleyLayout.FORTUNE
local CABINET = "fortune_1"
local AT_CABINET = { site = "bowling_alley", x = F.x - 1.6, y = 3, d = F.d - 1.6 }

local function hall(more: { [string]: any }?): Rig.Opts
	local o: any = { sites = { [SITE] = PLACE }, furnish = FakeGames.furnish }
	for k, v in more or {} do
		o[k] = v
	end
	return o
end

local function fire(w: Rig.World, station: string, verb: string, args: { any }?)
	w.input:FireServer({ gameId = station, seat = 1, verb = verb, args = args or {} })
end

-- the reveals (2.6 s) but not the lingers (5 s)
local function reveals()
	FakeEngine.runDelayed(function(seconds: number): boolean
		return seconds < 4
	end)
end

local function walkToStation(w: Rig.World, id: string)
	local def = w.svc.stations[id].def
	Rig.walkTo(w, def.site, def.x, def.y, def.d)
end

-- a case that is expected to break a rule of the rig: what the rig said
local function broken(fn: (w: Rig.World) -> (), opts: Rig.Opts?): string
	local ok, err = pcall(Rig.play, fn, opts)
	assert(not ok, "the rig let that through")
	return tostring(err)
end

return function(t)
	t.test(
		"the fortune card never outlives its game: gone when the lever is pulled again, never on top of another game, and a reveal walked away from never shows",
		function()
			Rig.play(function(w)
				local paper = w.gui:FindFirstChild("Paper")
				local OTHER = "darts_1"
				-- (1) pull, read the card, pull again: the old card is not left under the spinning reels
				Rig.press(w, CABINET)
				Rig.run(w, 0.3)
				t.eq(w.client.active(), CABINET)
				t.truthy(Rig.has(Rig.texts(w.gui), "The reels are spinning..."), Rig.screen(w))
				t.falsy(paper.Visible)
				reveals()
				t.truthy(paper.Visible, "the card is dealt")
				t.truthy(Rig.has(Rig.texts(w.gui), "Pull again (E) or walk away (Q)"))
				Rig.run(w, 3.2) -- (the cabinet is free again; the card is still up)
				t.truthy(paper.Visible)
				Rig.key(Key.E, true)
				Rig.run(w, 0.3)
				t.eq(Rig.count(w.got, "fortune"), 2, "the second pull went in")
				t.truthy(Rig.has(Rig.texts(w.gui), "The reels are spinning..."))
				t.falsy(paper.Visible, "the first card is gone while the reels spin")
				reveals()
				t.truthy(paper.Visible)
				-- (2) the cabinet frees itself and the card lingers; the player walks to another game and presses E:
				-- the card does not sit on top of it
				t.truthy(Rig.untilTrue(w, 6, function()
					return w.client.active() == nil
				end))
				t.truthy(w.gui.Enabled and paper.Visible, "the card lingers after the cabinet has let go")
				walkToStation(w, OTHER)
				Rig.press(w, OTHER)
				Rig.run(w, 0.3)
				t.eq(w.client.active(), OTHER)
				t.falsy(paper.Visible, "no fortune card over the other game")
				t.falsy(Rig.has(Rig.texts(w.gui), "Pull again (E) or walk away (Q)"))
				Rig.key(Key.Q, true)
				Rig.run(w, 0.3)
				t.eq(w.client.active(), nil)
				-- (3) pull, walk away before the reveal, sit down at another game: the pending reveal is dropped
				Rig.walkTo(w, AT_CABINET.site, AT_CABINET.x, AT_CABINET.y, AT_CABINET.d)
				Rig.run(w, 4)
				Rig.press(w, CABINET)
				Rig.run(w, 0.3)
				t.eq(Rig.count(w.got, "fortune"), 3)
				t.truthy(w.held, "the camera is on the cabinet")
				Rig.key(Key.Q, true)
				Rig.run(w, 0.3)
				t.eq(w.client.active(), nil)
				t.falsy(w.held)
				walkToStation(w, OTHER)
				Rig.press(w, OTHER)
				Rig.run(w, 0.3)
				t.eq(w.client.active(), OTHER)
				local screen, holds = Rig.screen(w), #w.holds
				reveals() -- (the first pull's 2.6 s are up now)
				t.falsy(paper.Visible, "a reveal whose pull was walked away from never shows")
				t.eq(Rig.screen(w), screen, "the other game's screen is untouched")
				t.eq(#w.holds, holds, "and so is its camera")
				Rig.key(Key.Q, true)
				Rig.run(w, 0.3)
				FakeEngine.runDelayed()
			end, { stand = AT_CABINET })
		end
	)

	t.test(
		"a quick second pull keeps its card: the first pull's linger timer closes nothing but its own game",
		function()
			Rig.play(function(w)
				local paper = w.gui:FindFirstChild("Paper")
				local function lingers(limit: number?)
					FakeEngine.runDelayed(function(seconds: number): boolean
						return seconds >= 4
					end, limit)
				end
				-- the first pull; four seconds on the cabinet lets the player go and the card lingers (timer one)
				Rig.press(w, CABINET)
				Rig.run(w, 0.3)
				reveals()
				t.truthy(Rig.untilTrue(w, 6, function()
					return w.client.active() == nil
				end))
				t.truthy(w.gui.Enabled and paper.Visible)
				t.eq(FakeEngine.delayedCount(), 1, "the first linger is running")
				-- E at the cabinet again before that timer is up: the second pull, its card, and its own linger
				Rig.press(w, CABINET)
				Rig.run(w, 0.3)
				t.eq(w.client.active(), CABINET)
				reveals()
				t.truthy(paper.Visible)
				t.truthy(Rig.untilTrue(w, 6, function()
					return w.client.active() == nil
				end))
				t.eq(FakeEngine.delayedCount(), 2, "two lingers are running: the first pull's and the second's")
				-- the FIRST timer fires. It used to close the screen here, two seconds into the second card
				lingers(1)
				t.truthy(w.gui.Enabled, "the second card is still on screen")
				t.truthy(paper.Visible)
				-- the second pull's own timer closes it
				lingers()
				t.falsy(w.gui.Enabled)
				t.eq(FakeEngine.delayedCount(), 0)
			end, { stand = AT_CABINET })
		end
	)

	t.test(
		"a game's keys come before the framework's: gamepad B and Q do not leave, a crouch slows the walk and the pace is put back, F is no kick while a game is open",
		function()
			Rig.play(function(w)
				local ID = S.match
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				Rig.click(w, "Start now")
				Rig.run(w, 0.3)
				local c = FakeGames.controllers.test_match
				t.eq(w.client.active(), ID)
				t.falsy(Rig.has(w.toasts, "Q leaves"), "a game that keeps Q does not promise that Q leaves")
				-- gamepad B is the game's crouch: nothing is sent, least of all "leave"
				local sent = #w.sent
				Rig.key(Key.ButtonB, true)
				Rig.run(w, 0.2)
				t.eq(#w.sent, sent, 'a key mapped to "" is swallowed')
				t.eq(w.client.active(), ID)
				t.truthy(c.crouched)
				-- the pace: attributes on the body, which Controllers/Human turns into the walking speed each frame
				t.eq(w.body:GetAttribute("MoveScale"), 0.5)
				t.eq(w.body:GetAttribute("NoSprint"), true)
				local scale, noSprint = w.body:GetAttribute("MoveScale"), w.body:GetAttribute("NoSprint")
				t.eq(Human.speed(false, scale, noSprint), Human.WALK / 2)
				t.eq(Human.speed(true, scale, noSprint), Human.WALK / 2, "no sprint while crouched")
				Rig.key(Key.ButtonB, false)
				t.eq(w.body:GetAttribute("MoveScale"), nil)
				t.eq(w.body:GetAttribute("NoSprint"), nil)
				-- Q is the game's too (leaving a match is the button's job)
				Rig.key(Key.Q, true)
				Rig.run(w, 0.2)
				t.eq(#w.sent, sent)
				t.eq(w.client.active(), ID)
				-- F and gamepad X belong to the game while it is open: the main client asks InputMap before it kicks
				local inGame = w.player:GetAttribute("InMinigame")
				t.eq(inGame, ID)
				t.falsy(InputMap.kicks("F", inGame))
				t.falsy(InputMap.kicks("ButtonX", inGame))
				-- crouched when the game closes: the framework puts the pace back, whatever the controller left
				Rig.key(Key.C, true)
				t.eq(w.body:GetAttribute("MoveScale"), 0.5)
				Rig.click(w, "Leave the match")
				Rig.run(w, 0.3)
				t.eq(w.client.active(), nil)
				t.eq(w.body:GetAttribute("MoveScale"), nil, "the pace was put back as the game closed")
				t.eq(w.body:GetAttribute("NoSprint"), nil)
				t.truthy(InputMap.kicks("F", w.player:GetAttribute("InMinigame")), "F kicks again")
				t.truthy(InputMap.kicks("ButtonX", nil))
				t.falsy(InputMap.kicks("E", nil))
				-- a game with no keys of its own: Q still leaves (and Space still starts its lobby)
				Rig.walkTo(w, SITE, 30, 3, 0)
				Rig.press(w, S.rally)
				Rig.run(w, 0.2)
				t.truthy(Rig.has(w.toasts, "You joined Rally court. Q leaves."))
				Rig.key(Key.Space, true)
				Rig.run(w, 0.2)
				t.eq(w.svc:sessionOf(S.rally).phase, "playing")
				Rig.key(Key.Q, true)
				Rig.run(w, 0.2)
				t.eq(w.client.active(), nil)
				-- the speed itself: Shift sprints, the scale multiplies, and an attribute is whatever somebody wrote
				t.eq(Human.speed(false, nil, nil), Human.WALK)
				t.eq(Human.speed(true, nil, nil), Human.SPRINT)
				t.eq(Human.speed(true, nil, true), Human.WALK)
				t.eq(Human.speed(true, 1.25, nil), Human.SPRINT * 1.25)
				t.eq(Human.speed(false, 99, nil), Human.WALK * Human.MAX_SCALE)
				t.eq(Human.speed(false, -3, nil), 0)
				t.eq(Human.speed(false, "fast", nil), Human.WALK)
				t.eq(Human.speed(false, 0 / 0, nil), Human.WALK)
			end, hall({ stand = { site = SITE, x = 0, y = 3, d = 400 } }))
		end
	)

	t.test(
		"the rig's network is the real Net: a message a frame is dropped and the case fails; a remote of a game's own is not carried",
		function()
			-- sixty a second: on a real server the Net drops what its rate limit will not carry, without a word
			local said = broken(function(w)
				Rig.press(w, S.plain)
				Rig.run(w, 0.2)
				for _ = 1, 120 do
					fire(w, S.plain, "leave")
					Rig.frame(w)
				end
			end, hall({ stand = { site = SITE, x = 90, y = 3, d = 0 } }))
			t.truthy(string.find(said, 'the Net dropped the client\'s "leave" (rate)', 1, true), said)
			t.truthy(string.find(said, "about ten a second", 1, true), said)
			-- twenty a second for five seconds is carried whole
			Rig.play(function(w)
				Rig.press(w, S.rally)
				Rig.run(w, 0.2)
				local before = #w.toasts
				for i = 1, 300 do
					if i % 3 == 0 then
						fire(w, S.rally, "hit")
					end
					Rig.frame(w)
				end
				Rig.run(w, 0.3)
				t.eq(Rig.count(w.sent, "hit"), 100)
				t.eq(#w.toasts - before, 100, "every one reached the service and was answered (refused: no game is on)")
			end, hall({ stand = { site = SITE, x = 30, y = 3, d = 0 } }))
			-- a game's Table that listens on, or fires, a remote of its own: nothing of that could be played here
			said = broken(function(w)
				w.svc.net:on("Paintball.Fire", function() end)
				w.svc.net:fire(w.player, "Paintball.State", {})
				-- (and the service's own handler is still the one that hears the client)
				Rig.press(w, S.plain)
				Rig.run(w, 0.2)
				fire(w, S.plain, "tilt", { 0.5 })
				Rig.run(w, 0.2)
				assert(w.svc:sessionOf(S.plain).game.state.tilts == 1, "Minigame.Input was taken from the service")
			end, hall({ stand = { site = SITE, x = 90, y = 3, d = 0 } }))
			t.truthy(string.find(said, "the server listened on Paintball.Fire", 1, true), said)
			t.truthy(string.find(said, "the server fired Paintball.State", 1, true), said)
			t.falsy(string.find(said, "was taken from the service", 1, true), said)
		end
	)

	t.test(
		"ctx.town: who is in town, a body to borrow, money and personal bests, each with a stand-in until the town supplies it",
		function()
			-- on the rig: the player and whoever the case adds are in town; nothing else is supplied
			Rig.play(function(w)
				local town = FakeGames.tables[S.coin].ctx.town
				t.truthy(town == FakeGames.tables[S.rally].ctx.town, "one town for every Table")
				local people = town.people()
				t.eq(#people, 1)
				local q = w.body.PrimaryPart.Position
				t.truthy(people[1].key == w.player and people[1].name == "Ann")
				t.truthy(people[1].x == q.X and people[1].y == q.Y and people[1].z == q.Z)
				table.insert(w.people, { key = Rig.stub("Bob"), name = "Bob", x = 1, y = 2, z = 3 })
				t.eq(#town.people(), 2)
				-- nobody to lend yet: a computer player has no body, and handing one back is harmless
				t.eq(town.body("Wall", roblox.CFrame.new(0, 0, 0)), nil)
				town.release(w.body)
				-- the rig's town has the real wallet (Server/Economy/Credits), as the game's has: money is taken,
				-- with words to show, and a price above the balance is refused in words
				t.eq(w.wallet.balance(w.player), 300)
				t.deepEq(
					{ town.charge(w.player, 20, "a paintball pass") },
					{ true, "Paid 20c for a paintball pass. You have S$2.80." }
				)
				t.deepEq({ town.charge(w.player, 500, "the arena") }, { false, "You need S$5.00; you have S$2.80." })
				t.eq(w.wallet.balance(w.player), 280)
				-- no profile yet: a best is kept for as long as the server runs, per person and per key
				t.eq(town.best(w.player, "machine"), nil)
				t.eq(town.best(w.player, "machine", 50), 50)
				t.eq(town.best(w.player, "machine", 40), 50, "more is better unless told otherwise")
				t.eq(town.best(w.player, "machine", 60), 60)
				t.eq(town.best(w.player, "maze", 30, true), 30)
				t.eq(town.best(w.player, "maze", 40, true), 30, "less is better here")
				t.eq(town.best(w.player, "maze", 20, true), 20)
				t.eq(town.best(w.player, "maze"), 20)
				t.eq(town.best(w.player, "machine", 0 / 0), 60, "not a number: not a best")
				local bob = Rig.stub("Bob")
				t.eq(town.best(bob, "machine"), nil)
				t.eq(town.best(bob, "machine", 5), 5)
				t.eq(town.best(w.player, "machine"), 60)
			end, hall())
			-- what the town does supply is what a Table gets
			local charged, lent, handedBack = {}, 0, 0
			Rig.play(
				function(w)
					-- (a charge with no pass: the service keeps a stand-in pass and says so in the server's log)
					t.deepEq(w.warnings, { MinigameService.NO_PASS_WARNING })
					table.clear(w.warnings)
					local town = FakeGames.tables[S.match].ctx.town
					local ok, words = town.charge(w.player, 20, "a paintball pass")
					t.truthy(not ok and words == "You need 20 cents for a pass")
					t.deepEq(charged, { { cents = 20, why = "a paintball pass" } })
					local body = town.body("Bot A", roblox.CFrame.new(1, 2, 3))
					t.truthy(body ~= nil and body.Name == "Bot A" and lent == 1)
					town.release(body)
					t.eq(handedBack, 1)
					t.eq(town.best(w.player, "machine", 7), 1000, "the profile's answer")
					t.eq(#town.people(), 1, "what the case did not replace is still the rig's")
				end,
				hall({
					service = {
						games = {
							charge = function(_player: any, cents: number, why: string): (boolean, string?)
								table.insert(charged, { cents = cents, why = why })
								return false, `You need {cents} cents for a pass`
							end,
							body = function(name: string, cframe: any): any
								lent += 1
								return FakeEngine.model(name, cframe, nil)
							end,
							release = function(_model: any)
								handedBack += 1
							end,
							best = function(): number?
								return 1000
							end,
						},
					},
				})
			)
			-- a bare service (no town at all): the only people known are the ones at the tables
			FakeEngine.with(function()
				local svc = MinigameService.new({ sites = { [SITE] = { place = PLACE } }, prompts = false })
				t.eq(#svc.town.people(), 0)
				t.truthy(svc.town.charge({ UserId = 1 }, 5, "x"))
				-- and the attraction service hands the town's `games` through as it is
				local folder = FakeEngine.new("Folder", "Attractions")
				folder.Parent = workspace
				local alley = FakeEngine.new("Model", "BowlingAlley")
				alley:SetAttribute("OriginX", 0)
				alley:SetAttribute("OriginZ", 0)
				alley:SetAttribute("FloorY", 0)
				alley:SetAttribute("Yaw", 0)
				alley.Parent = folder
				local A = AttractionService.start({
					terrain = false,
					heartbeat = false,
					prompts = false,
					games = {
						charge = function(): (boolean, string?)
							return false, "the town's own wallet"
						end,
						pass = svc.town.pass, -- (the town hands in its pass with its charge: no warning)
					},
				})
				t.truthy(A.minigames.town.pass == svc.town.pass, "the pass handed through as it is")
				t.truthy(A ~= nil, "the attraction service started on a bare alley")
				local ok, words = A.minigames.town.charge({ UserId = 1 }, 5, "x")
				t.truthy(not ok and words == "the town's own wallet")
				A.stop()
			end)
		end
	)

	t.test(
		"a second prompt joins the same game: the far end of the court seats you at the court, and its Table hears which prompt was pressed",
		function()
			Rig.play(function(w)
				local session = w.svc:sessionOf(S.rally)
				local tbl = FakeGames.tables[S.rally]
				local near, far = Rig.prompt(w, S.rally), Rig.prompt(w, S.rallyFar)
				-- a prompt of its own, in the site's folder like every station's, saying what the court is doing
				t.truthy(far ~= nil and far ~= near)
				t.truthy(far.Parent.Parent == w.roots[SITE]:FindFirstChild("MinigamePrompts"))
				t.eq(far:GetAttribute("Station"), S.rallyFar)
				t.eq(far.ActionText, "Play a rally")
				t.eq(far.ObjectText, "Rally court (far end) - open (alone, with friends, or against a computer)")
				t.eq(near.ObjectText, "Rally court - open (alone, with friends, or against a computer)")
				t.truthy(w.svc:sessionOf(S.rallyFar) == session, "one Session for both ends")
				t.eq(FakeGames.tables[S.rallyFar], nil, "and one Table")
				-- E at the far end: seated at the court
				Rig.press(w, S.rallyFar)
				Rig.run(w, 0.2)
				t.eq(w.client.active(), S.rally)
				t.eq(w.svc:stationOf(w.player), S.rally)
				local joined = Rig.last(w.got, "joined")
				t.truthy(joined.station == S.rally and joined.via == S.rallyFar and joined.label == "Rally court")
				t.eq(tbl.via[w.player], S.rallyFar, "the Table was told which prompt")
				t.eq(Session.seatOf(session, w.player), 1)
				t.eq(far.ActionText, "Join")
				t.eq(far.ObjectText, "Rally court (far end) - 1/2 joining, starting soon")
				t.eq(near.ObjectText, "Rally court - 1/2 joining, starting soon")
				-- Bob comes in by the court's own prompt: the same game
				local bob = Rig.stub("Bob")
				t.truthy(w.svc:join(bob, S.rally))
				t.eq(tbl.via[bob], S.rally)
				t.eq(Rig.last(bob.events, "joined").via, nil)
				t.eq(Session.seatOf(session, bob), 2)
				Rig.key(Key.Space, true)
				Rig.run(w, 0.2)
				t.eq(session.phase, "playing")
				t.eq(far.ActionText, "In use")
				-- every station has its prompt and every prompt its station (the engine smoke counts them)
				local stations, prompts = 0, 0
				for _ in w.svc.stations do
					stations += 1
				end
				for _, p in w.roots[SITE]:FindFirstChild("MinigamePrompts"):GetChildren() do
					if p:FindFirstChildOfClass("ProximityPrompt") then
						prompts += 1
					end
				end
				t.eq(stations, #Games.stations({ [SITE] = PLACE }))
				t.eq(prompts, stations)
			end, hall({ stand = { site = SITE, x = 30, y = 3, d = 5 } }))
			-- where a second prompt may lead is checked as the stations are read
			-- (a third prompt on the rally court, leading somewhere it may not: what Games.stations says of it)
			local spec = Games.get("test_rally") :: any
			local honest = spec.stations
			local function refusal(joins: string): string
				spec.stations = function(sites: any): { any }
					local list = honest(sites)
					local door: any = { id = "test_rally_door", game = "test_rally", label = "Door", site = SITE }
					door.x, door.y, door.d, door.joins = 0, 0, 0, joins
					table.insert(list, door)
					return list
				end
				local ok, err = pcall(Games.stations, { [SITE] = PLACE })
				spec.stations = honest
				return if ok then "" else tostring(err)
			end
			local nowhere, other, chained = refusal("nowhere"), refusal(S.coin), refusal(S.rallyFar)
			t.truthy(string.find(nowhere, "test_rally_door joins nowhere, which is not a station", 1, true), nowhere)
			t.truthy(string.find(other, "a station of test_coin", 1, true), other)
			t.truthy(string.find(chained, "which itself joins another", 1, true), chained)
			t.eq(refusal(S.rally), "", "a third way in to the court itself is fine")
			t.eq(#Games.stations({ [SITE] = PLACE }), 7)
		end
	)

	t.test(
		"computer players: asked for by name from a button, picked per table, never twice, and only in the lobby unless the game takes late seats",
		function()
			Rig.play(function(w)
				local coin, rally = w.svc:sessionOf(S.coin), w.svc:sessionOf(S.rally)
				-- another table adds its computer first: that used to move the coin table one down its own list
				local bob = Rig.stub("Bob")
				t.truthy(w.svc:join(bob, S.rally))
				t.truthy(Rig.input(w, bob, S.rally, "addai"))
				t.eq(rally.names[2], "Wall (computer)")
				local cy = Rig.stub("Cy")
				t.truthy(w.svc:join(cy, S.coin))
				t.truthy(Rig.input(w, cy, S.coin, "addai"))
				t.eq(coin.names[2], "Heads-up Hal (computer)", "the first on the coin table's own list")
				Rig.input(w, cy, S.coin, "leave")
				Rig.run(w, 0.1)
				t.eq(coin.phase, "idle")
				-- the button "Add Tails Tina": the verb with her name
				Rig.press(w, S.coin)
				Rig.run(w, 0.2)
				Rig.click(w, "Add Tails Tina")
				Rig.run(w, 0.2)
				t.deepEq(Rig.last(w.sent, "addai").args, { "Tails Tina" })
				t.eq(coin.names[2], "Tails Tina (computer)")
				t.eq(coin.seats[2].bias, "tails", "what the Spec says of her rides on her key")
				-- not twice, not a stranger, and each refusal has words
				Rig.input(w, w.player, S.coin, "leave")
				Rig.run(w, 0.2)
				t.eq(coin.phase, "idle", "only the computer was left")
				local di = Rig.stub("Di")
				t.truthy(w.svc:join(di, S.match))
				t.truthy(Rig.input(w, di, S.match, "addai", { "Bot B" }))
				local ok, why = Rig.input(w, di, S.match, "addai", { "Bot B" })
				t.truthy(not ok and why == "Bot B is already at the table", tostring(why))
				ok, why = Rig.input(w, di, S.match, "addai", { "HAL 9000" })
				t.truthy(not ok and why == "There is no computer player of that name here", tostring(why))
				-- with no name: the next on the list who is not at this table
				t.truthy(Rig.input(w, di, S.match, "addai"))
				t.truthy(Rig.input(w, di, S.match, "addai"))
				local match = w.svc:sessionOf(S.match)
				t.deepEq(match.names, { "Di", "Bot B (computer)", "Bot A (computer)", "Bot C (computer)" })
				-- a Table may seat one itself, by name, and is handed its key
				local tbl = FakeGames.tables[S.coin]
				t.truthy(w.svc:join(cy, S.coin))
				local seated, _, key = tbl.ctx.addComputer("Tails Tina")
				t.truthy(seated and key.name == "Tails Tina" and key.ai == true)
				t.eq(Session.seatOf(coin, key), 2)
				-- after the start: only a game whose rules take late seats (def.lateJoin) can be given one
				t.truthy(Rig.input(w, cy, S.coin, "start"))
				ok, why = tbl.ctx.addComputer()
				t.truthy(not ok and why == "Computers join in the lobby, before the game starts", tostring(why))
				t.truthy(Rig.input(w, di, S.match, "start"))
				local late, _, bot = FakeGames.tables[S.match].ctx.addComputer("Bot A")
				t.falsy(late, "Bot A is already there")
				t.truthy(FakeGames.tables[S.match].ctx.removeComputer(match.seats[3]))
				late, _, bot = FakeGames.tables[S.match].ctx.addComputer("Bot A")
				t.truthy(late and bot.name == "Bot A")
				t.eq(Session.seatOf(match, bot), 3, "the seat a computer left is the next one given")
			end, hall())
		end
	)

	t.test(
		"a match makes room and rolls on: a computer leaves for a person at a full arena, and the Table starts the next match from the end card",
		function()
			Rig.play(function(w)
				local ID = S.match
				local session = w.svc:sessionOf(ID)
				local tbl = FakeGames.tables[ID]
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				Rig.click(w, "Start now")
				Rig.run(w, 0.3)
				t.eq(#w.svc:_seated(w.svc.stations[ID]), 4, "Ann and three computers")
				local bob, cy, di = Rig.stub("Bob"), Rig.stub("Cy"), Rig.stub("Di")
				t.truthy(w.svc:join(bob, ID))
				t.truthy(w.svc:join(cy, ID))
				t.eq(Session.seatOf(session, cy), 6)
				t.eq(#w.svc:_seated(w.svc.stations[ID]), 6, "the arena is full")
				-- Di walks up: the Table takes a computer off (the rules hear the seat has gone), and the service
				-- gives her that seat, so the sides stay as they were
				local gone = session.seats[2]
				t.truthy(gone.ai)
				t.truthy(w.svc:join(di, ID))
				t.eq(Session.seatOf(session, di), 2)
				t.eq(Session.seatOf(session, gone), nil)
				t.eq(session.game.state.out[2], nil, "rules.gone, then rules.join")
				t.eq(#w.svc:_seated(w.svc.stations[ID]), 6)
				t.falsy(tbl.ctx.removeComputer(di), "a person is never removed that way")
				t.falsy(tbl.ctx.removeComputer(gone), "nor a computer that is not seated")
				-- three more people: the last two computers go, then the arena really is full
				local extra = { Rig.stub("Ed"), Rig.stub("Flo") }
				t.truthy(w.svc:join(extra[1], ID))
				t.truthy(w.svc:join(extra[2], ID))
				local ok, why = w.svc:join(Rig.stub("Gus"), ID)
				t.truthy(not ok and why == "The arena is full of people: wait for the next match", tostring(why))
				-- the arena rolls into its next match: no reset, nobody told to leave, the same seats, a new game
				tbl.rollOn = true
				t.truthy(Rig.untilTrue(w, 10, function()
					return session.phase == "done"
				end))
				t.eq(session.games, 1)
				local again, whyNot = tbl.ctx.again()
				t.truthy(again, tostring(whyNot))
				t.eq(session.phase, "playing")
				t.eq(session.games, 2)
				t.truthy(Rig.untilTrue(w, 10, function()
					return session.phase == "done"
				end))
				-- (and by itself, two seconds into the end card)
				t.truthy(Rig.untilTrue(w, 3, function()
					return session.phase == "playing"
				end))
				t.eq(session.games, 3)
				Rig.run(w, 0.3)
				t.eq(w.client.active(), ID)
				t.eq(Rig.last(w.got, "left"), nil, "nobody was ever told the arena had reset")
				t.eq(Session.seatOf(session, w.player), 1)
				t.eq(Session.seatOf(session, di), 2)
				-- (each next match began as any game does: its Table heard "start", the players read "Game on!")
				local began = 0
				for _, m in w.got do
					if m.kind == "event" and m.text == "Game on!" then
						began += 1
					end
				end
				t.eq(began, 3)
				-- outside the end card there is nothing to start again
				ok, why = tbl.ctx.again()
				t.truthy(not ok and why == "not finished")
			end, hall({ stand = { site = SITE, x = 0, y = 3, d = 400 } }))
		end
	)

	t.test(
		"one game cannot take the others down: a Table that will not build, a step that throws, each put out of order alone",
		function()
			-- (1) new() throws: that station says so; every other station is open
			local entry = ServerGames.get("test_coin") :: any
			local honest = entry.new
			entry.new = function(_ctx: any): any
				error("the coin rolled under the bar")
			end
			local ok, err = pcall(Rig.play, function(w)
				t.eq(#w.warnings, 1)
				t.truthy(string.find(w.warnings[1], "test_coin_1 is out of order", 1, true), w.warnings[1])
				t.truthy(string.find(w.warnings[1], "the coin rolled under the bar", 1, true), w.warnings[1])
				table.clear(w.warnings)
				local prompt = Rig.prompt(w, S.coin)
				t.eq(prompt.ActionText, "Out of order")
				t.eq(prompt.ObjectText, "Coin table")
				Rig.press(w, S.coin)
				Rig.run(w, 0.2)
				t.eq(w.client.active(), nil)
				t.truthy(Rig.has(w.toasts, "Coin table is out of order. Sorry!"))
				local refused, why = Rig.input(w, Rig.stub("Bob"), S.coin, "start")
				t.truthy(not refused and why == "There is no game there")
				Rig.walkTo(w, SITE, 30, 3, 0)
				Rig.press(w, S.rally)
				Rig.run(w, 0.2)
				t.eq(w.client.active(), S.rally, "the court next to it is open")
			end, hall())
			entry.new = honest
			assert(ok, err)
			-- (2) step() throws while people are playing: they are let go with words, the table is reset and may
			-- try again; the third time it is out of order for good. Every other station steps in the same frames
			Rig.play(function(w)
				local rally, coin = w.svc:sessionOf(S.rally), w.svc:sessionOf(S.coin)
				local tbl = FakeGames.tables[S.rally]
				local prompt = Rig.prompt(w, S.rally)
				local bob = Rig.stub("Bob")
				t.truthy(w.svc:join(bob, S.coin)) -- (a six-second lobby on the table next door)
				Rig.press(w, S.rally)
				Rig.run(w, 0.2)
				Rig.key(Key.Space, true)
				Rig.run(w, 0.2)
				t.eq(rally.phase, "playing")
				local step = tbl.step
				local throws = 1
				tbl.step = function(self: any, dt: number)
					if throws > 0 then
						throws -= 1
						error("the ball fell through the floor")
					end
					step(self, dt)
				end
				Rig.run(w, 0.2)
				t.eq(#w.warnings, 1)
				t.truthy(string.find(w.warnings[1], "test_rally_1 failed in its step (1 of 3)", 1, true), w.warnings[1])
				t.truthy(string.find(w.warnings[1], "the ball fell through the floor", 1, true))
				t.eq(w.client.active(), nil)
				t.truthy(
					Rig.has(
						w.toasts,
						"Something went wrong at Rally court: the game was reset. Press E there to play again."
					),
					table.concat(w.toasts, " | ")
				)
				t.eq(rally.phase, "idle")
				t.eq(w.svc:stationOf(w.player), nil)
				t.eq(prompt.ActionText, "Play a rally", "the court is open again")
				-- it works again
				Rig.press(w, S.rally)
				Rig.run(w, 0.2)
				t.eq(w.client.active(), S.rally)
				-- now it throws every frame: two more and it is out of order, with no more than three warnings ever
				throws = 1000
				Rig.run(w, 1)
				t.eq(#w.warnings, 3)
				t.truthy(string.find(w.warnings[3], "(3 of 3: out of order)", 1, true), w.warnings[3])
				t.eq(prompt.ActionText, "Out of order")
				t.eq(Rig.prompt(w, S.rallyFar).ActionText, "Out of order", "its second prompt says so too")
				t.eq(w.client.active(), nil)
				Rig.press(w, S.rallyFar)
				Rig.run(w, 0.2)
				t.eq(w.client.active(), nil)
				t.truthy(Rig.has(w.toasts, "Rally court is out of order. Sorry!"))
				-- meanwhile the coin table's lobby ran its six seconds and started: nothing else missed a frame
				t.truthy(Rig.untilTrue(w, 6, function()
					return coin.phase == "playing"
				end))
				t.truthy(w.frames < 8 * 60)
				table.clear(w.warnings)
			end, hall({ stand = { site = SITE, x = 30, y = 3, d = 0 } }))
		end
	)

	t.test(
		"every game's Table on sites that lack its furniture: it builds, steps and says nothing to people who are not playing",
		function()
			-- every site there is (the alley and the venues), each an empty model: what another game's test, or a
			-- half-baked place, looks like to your Table. No error, no warning, and not one message to a client
			-- that never sat down
			local all = Sites.fromData(Data.default())
			all[SITE] = PLACE
			Rig.play(function(w)
				local built = 0
				for _, st in w.svc.stations do
					t.falsy(st.broken, `{st.id} could not be built on a bare site`)
					if st.tbl then
						built += 1
					end
				end
				t.truthy(built >= 8 + 4, `{built} Tables were built`)
				Rig.run(w, 3)
				for _, st in w.svc.stations do
					t.eq(st.strikes, 0, `{st.id} threw in its step on a bare site`)
				end
				t.eq(
					#w.got,
					0,
					`a Table spoke to someone who is not playing: {if w.got[1] then tostring(w.got[1].kind) else ""}`
				)
			end, { sites = all, stand = { site = SITE, x = 5000, y = 3, d = 5000 } })
		end
	)

	t.test(
		"two clocks: a message is stamped on the one both sides share, never on the service's own; a finger is one InputObject from began to ended",
		function()
			Rig.play(function(w)
				local ID = S.rally
				local session = w.svc:sessionOf(ID)
				local tbl = FakeGames.tables[ID]
				local bob = Rig.stub("Bob")
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				t.truthy(w.svc:join(bob, ID))
				Rig.key(Key.Space, true)
				Rig.run(w, 0.2)
				local c = FakeGames.controllers.test_rally
				-- the service's clock counts its own steps from nothing; the shared clock is another thing entirely,
				-- and it is the same on both sides
				t.truthy(tbl.ctx.now() < 5)
				t.truthy(tbl.ctx.stamp() >= Rig.SERVER_TIME)
				t.eq(c.ctx.stamp(), tbl.ctx.stamp())
				t.eq(workspace:GetServerTimeNow(), tbl.ctx.stamp())
				-- Bob hits; the one message of that hit carries its stamp; a second later the controller still
				-- knows where the ball is, from that stamp and the shared clock alone
				local state = session.game.state
				t.truthy(Rig.untilTrue(w, 3, function()
					return state.pos >= 7.5
				end))
				t.truthy(Rig.input(w, bob, ID, "hit"))
				Rig.run(w, 1)
				t.eq(#c.legs, 1)
				t.truthy(c.legs[1].at >= Rig.SERVER_TIME, "stamped on the shared clock")
				t.near(c:ballNow(), state.pos, 0.1, "the ball on this screen is where the server has it")
				-- (stamped with ctx.now() instead, the same sum is off by the shared clock's head start)
				local wrong = c.legs[1].from + c.legs[1].dir * FakeGames.Rally.SPEED * (c.ctx.stamp() - tbl.ctx.now())
				t.truthy(math.abs(wrong - state.pos) > 1000)
			end, hall({ stand = { site = SITE, x = 30, y = 3, d = 0 } }))
			-- two thumbs: the left one slides across the middle of the screen while the right one is down
			FakeEngine.with(function()
				local uis = FakeEngine.uis()
				local seen: { { kind: string, io: any, x: number } } = {}
				for kind, signal in { began = uis.InputBegan, changed = uis.InputChanged, ended = uis.InputEnded } do
					signal:Connect(function(io: any, _processed: boolean)
						table.insert(seen, { kind = kind, io = io, x = io.Position.X })
					end)
				end
				Rig.touch("left", "began", 200, 900)
				Rig.touch("right", "began", 1700, 900)
				Rig.touch("left", "changed", 1200, 900) -- (now on the right half: only the object says whose it is)
				Rig.touch("right", "ended", 1700, 900)
				Rig.touch("left", "ended", 1250, 900)
				t.eq(#seen, 5)
				local left, right = seen[1].io, seen[2].io
				t.truthy(left ~= right, "two fingers, two objects")
				t.truthy(seen[3].io == left and seen[5].io == left, "the sliding thumb is the same object all the way")
				t.truthy(seen[4].io == right)
				t.eq(seen[3].x, 1200)
				t.eq(left.UserInputType, roblox.Enum.UserInputType.Touch)
				-- the next touch of that thumb is a new object
				Rig.touch("left", "began", 200, 900)
				t.truthy(seen[6].io ~= left)
				-- (without an id, as before: a new table every time)
				Rig.key(Key.F, true)
				Rig.key(Key.F, false)
				t.truthy(seen[7].io ~= seen[8].io)
			end)
		end
	)
end
