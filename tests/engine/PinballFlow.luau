--!strict
-- ServerStorage.EngineTests.PinballFlow (CI place only; injected with --inject ci.project.json or a saved version)
-- The pinball flow on a server with no clients, as plain results. PlayerLike stubs take the machines of the real
-- MinigameService; each stub's machine is a Replay of its own (Shared/Minigames/Pinball/Replay: the same live
-- play and log a client runs, its hands the model's computer player, Pinball/Bot NOVICE), fed the snapshots and
-- relayed segments the service sends it, so the logs that reach the server are real ones:
--   solo     one player, a whole game of three balls on ACORN ATTACK: the server's replay ends on the stub's own
--            score to the point, the game is fair, the end card's result is that score, the board on the cabinet
--            (attribute "Best") is written
--   two      two players on SPICY RODENT taking a ball each in turn (the ball goes 1, 2, 1, ...); the second
--            leaves in the middle of the game: the first is sent the server's game (a snapshot), the leaver's
--            score is kept and their balls passed over, and the first plays on to the end
--   drain    SPACE SQUIRREL: the ball in play is played out dead by the server (MinigameService:debug "drain",
--            as the turn clock does): the player is sent the server's game and carries on from it
--   ends     everyone leaves: each machine is idle with nobody held at it and nothing more sent
-- Nothing here needs a client: the keys, the camera and the drawing are client code, run under Lune on the fake
-- engine (tests/isolated/pinball_client.luau) and checked by eye in a Play session.
-- play() takes any MinigameService, so the Lune suite runs this same flow on the fake engine first.
-- Interface: run() -> Result (engine only: boots Server/Boot/Game); play(svc, deps, opts) -> Result { ok,
--   failures, numbers }; deps = { Replay, InputLog, Bot, Wire, Tables } (the shared modules); opts = { players
--   = { stub, stub }, step = (seconds) -> () }

local PinballFlow = {}

export type Deps = { Replay: any, InputLog: any, Bot: any, Wire: any, Tables: any }
export type Opts = { players: { any }, step: (seconds: number) -> () }

PinballFlow.STEP = 0.1 -- seconds a step of the flow (the stub plays 24 ticks of its ball in each)

function PinballFlow.play(svc: any, deps: Deps, opts: Opts): { [string]: any }
	local Replay, InputLog, Bot, Wire, Tables = deps.Replay, deps.InputLog, deps.Bot, deps.Wire, deps.Tables
	local failures: { string } = {}
	local numbers: { [string]: any } = {}
	local function check(cond: any, what: string)
		if not cond then
			table.insert(failures, what)
		end
	end
	local p1, p2 = opts.players[1], opts.players[2]

	-- a stub's machine
	type Hand = {
		p: any,
		id: string,
		read: number,
		r: any,
		g: number,
		seat: number?,
		bot: any,
		live: boolean,
		rec: any,
		syncs: number,
		refused: { string },
	}
	local function hand(p: any, id: string, seed: number): Hand
		return {
			p = p,
			id = id,
			read = #p.events,
			r = nil,
			g = 0,
			seat = nil,
			bot = Bot.new(1, seed),
			live = false,
			rec = nil,
			syncs = 0,
			refused = {},
		}
	end
	local function frame(h: Hand)
		local events = h.p.events
		while h.read < #events do
			h.read += 1
			local msg = events[h.read]
			if msg.station == h.id then
				if msg.kind == "pinball_sync" then
					h.r = Wire.restore(msg.snap)
					h.g = msg.g
					h.live = false
					h.syncs += 1
				elseif msg.kind == "pinball" and h.r and msg.g == h.g and not h.live then
					local seg = InputLog.unpack(msg.from, msg.to, msg.packed)
					if seg then
						Replay.follow(h.r, msg.seat, seg)
					end
				elseif msg.kind == "state" then
					h.seat = msg.you or h.seat
				elseif msg.kind == "joined" then
					h.seat = msg.seat
				end
			end
		end
		local r = h.r
		if r == nil then
			return
		end
		local mine = h.seat ~= nil and not Replay.over(r) and r.m.up == h.seat
		if mine and not h.live then
			h.live = true
			h.rec = Replay.recorder(r)
		elseif not mine then
			h.live = false
		end
		if not h.live then
			return
		end
		local tbl = Tables.need(r.id)
		for _ = 1, math.floor(PinballFlow.STEP * 240 + 0.5) do
			local seg = Replay.live(r, h.rec, Bot.step(h.bot, tbl, r.m))
			if seg then
				local a, b, c = InputLog.pack(seg)
				local ok, why =
					svc:input(h.p, { gameId = h.id, seat = 1, verb = "log", args = { a, b, c, Replay.sum(r) } })
				if not ok then
					table.insert(h.refused, tostring(why))
				end
				if Replay.over(r) or r.m.up ~= h.seat then
					h.live = false
					return
				end
			end
		end
	end
	local function run(hands: { Hand }, seconds: number, cond: () -> boolean): boolean
		for _ = 1, math.ceil(seconds / PinballFlow.STEP) do
			if cond() then
				return true
			end
			for _, h in hands do
				frame(h)
			end
			opts.step(PinballFlow.STEP)
		end
		return cond()
	end
	local function input(p: any, id: string, verb: string): (boolean, string?)
		return svc:input(p, { gameId = id, seat = 1, verb = verb, args = {} })
	end
	local function replayOf(id: string): any
		local st = svc.stations[id]
		return st and st.tbl and st.tbl:replay()
	end
	for _, id in { "pinball_1", "pinball_2", "pinball_3" } do
		if svc.stations[id] == nil or svc.stations[id].tbl == nil then
			return { ok = false, failures = { `there is no pinball machine at {id}` }, numbers = numbers }
		end
	end

	-- solo: a whole game on ACORN ATTACK
	do
		local id = "pinball_1"
		local s = svc:sessionOf(id)
		check(svc:join(p1, id), "solo: the player could not take the machine")
		local h = hand(p1, id, 3)
		input(p1, id, "start")
		check(s.phase == "playing", `solo: the game did not start ({s.phase})`)
		local ended = run({ h }, 900, function()
			return s.phase == "done"
		end)
		check(ended, "solo: the game did not end in fifteen minutes")
		local r = replayOf(id)
		local result = s.result
		if r and result and h.r then
			numbers.soloScore = r.m.scores[1]
			numbers.soloSeconds = r.tick / 240
			check(
				h.r.m.scores[1] == r.m.scores[1],
				`solo: the player's machine has {h.r.m.scores[1]}, the server {r.m.scores[1]}`
			)
			check(result.scores[1] == r.m.scores[1], "solo: the result is not the replay's score")
			check(result.fair == true, "solo: the game was not fair (out of pace)")
			check(#h.refused == 0, `solo: segments refused: {table.concat(h.refused, ", ")}`)
			local hw = svc.stations[id].hw
			if hw then
				check(type(hw.model:GetAttribute("Best")) == "string", "solo: no board on the cabinet")
			end
		else
			check(false, "solo: no result")
		end
		input(p1, id, "leave")
		opts.step(0.2)
		check(s.phase == "idle" or s.phase == "done", `solo: the machine is {s.phase} after the player left`)
	end

	-- two: SPICY RODENT, a ball each in turn; the second player leaves in the middle
	do
		local id = "pinball_2"
		local s = svc:sessionOf(id)
		check(svc:join(p1, id), "two: the first player could not take the machine")
		check(svc:join(p2, id), "two: the second player could not join")
		local h1, h2 = hand(p1, id, 5), hand(p2, id, 6)
		input(p1, id, "start")
		local ups: { number } = {}
		run({ h1, h2 }, 400, function()
			local r = replayOf(id)
			if r and ups[#ups] ~= r.m.up then
				table.insert(ups, r.m.up)
			end
			return #ups >= 4 or s.phase ~= "playing"
		end)
		numbers.twoTurns = table.concat(ups, " ")
		check(ups[1] == 1 and ups[2] == 2 and ups[3] == 1, `two: the balls did not alternate ({numbers.twoTurns})`)
		local r = replayOf(id)
		local kept = r and r.m.scores[2]
		local syncs = h1.syncs
		input(p2, id, "leave")
		opts.step(0.2)
		frame(h1)
		check(h1.syncs > syncs, "two: the one who stayed was not sent the server's game")
		local ended = run({ h1 }, 900, function()
			return s.phase == "done"
		end)
		check(ended, "two: the game did not end")
		r = replayOf(id)
		if r and s.result and h1.r then
			check(s.result.scores[2] == kept, "two: the leaver's score was not kept")
			check(h1.r.m.scores[1] == r.m.scores[1], "two: the player's machine and the server differ")
			numbers.twoScores = `{r.m.scores[1]} {r.m.scores[2]}`
		end
		input(p1, id, "leave")
		opts.step(0.2)
	end

	-- drain: the server plays the ball out by itself; the player carries on from its game
	do
		local id = "pinball_3"
		local s = svc:sessionOf(id)
		check(svc:join(p1, id), "drain: the player could not take the machine")
		local h = hand(p1, id, 9)
		input(p1, id, "start")
		run({ h }, 6, function()
			return false
		end)
		local before = h.syncs
		local ok, why = svc:debug(id, "drain")
		check(ok, `drain: {tostring(why)}`)
		opts.step(0.1)
		frame(h)
		check(h.syncs > before, "drain: the player was not sent the server's game")
		local r = replayOf(id)
		check(r and h.r and h.r.tick == r.tick, "drain: the player's machine is not on the server's tick")
		run({ h }, 10, function()
			return false
		end)
		r = replayOf(id)
		check(r and h.r and h.r.m.scores[1] >= r.m.scores[1], "drain: the game did not go on")
		input(p1, id, "leave")
		opts.step(0.3)
		check(s.phase == "idle", `drain: the machine is {s.phase} after the player left`)
	end

	-- ends: nobody is held at any machine, and nothing more is sent
	for _, id in { "pinball_1", "pinball_2", "pinball_3" } do
		local s = svc:sessionOf(id)
		if s.phase == "done" then
			opts.step(30)
		end
		check(s.phase == "idle", `ends: {id} is {s.phase}`)
		check(svc:stationOf(p1) == nil and svc:stationOf(p2) == nil, "ends: a player is still held")
	end
	local sent = #p1.events + #p2.events
	opts.step(2)
	check(#p1.events + #p2.events == sent, "ends: messages were sent to people who left")
	return { ok = #failures == 0, failures = failures, numbers = numbers }
end

-- run: boot the whole game with no players (frames stepped by hand), stand two stubs as townspeople in front of
-- the machines and play the flow.
function PinballFlow.run(): { [string]: any }
	local ServerScriptService = game:GetService("ServerScriptService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local server = ServerScriptService:WaitForChild("Server")
	local Game = (require :: any)(server:WaitForChild("Boot"):WaitForChild("Game"))
	local Possession = (require :: any)(server:WaitForChild("Actors"):WaitForChild("Possession"))
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local pinball = Shared:WaitForChild("Minigames"):WaitForChild("Pinball")
	local AlleyLayout = (require :: any)(Shared:WaitForChild("Attractions"):WaitForChild("AlleyLayout"))
	local Cabinet = (require :: any)(pinball:WaitForChild("Cabinet"))
	local deps: Deps = {
		Replay = (require :: any)(pinball:WaitForChild("Replay")),
		InputLog = (require :: any)(pinball:WaitForChild("InputLog")),
		Bot = (require :: any)(pinball:WaitForChild("Bot")),
		Wire = (require :: any)(pinball:WaitForChild("Wire")),
		Tables = (require :: any)(pinball:WaitForChild("Tables")),
	}
	local engine = Possession.engine()
	engine.streamAround = function() end
	engine.setOwner = function(_root: any, _player: any?) end
	engine.setCharacter = function(player: any, model: any?)
		player.Character = model
	end
	local t0 = os.clock()
	local G = Game.start({ players = false, engine = engine, heartbeat = false })
	local bootSeconds = os.clock() - t0
	local A = G.attractions
	if A == nil then
		G.stop()
		return {
			ok = false,
			failures = { "Game.attractions is missing (is Workspace.Attractions in the place?)" },
			numbers = { bootSeconds = bootSeconds },
		}
	end
	local players: { any } = {}
	local setup: { string } = {}
	for i, name in { "Ann", "Bob" } do
		local p = { UserId = 5400 + i, Name = name, Character = nil, attrs = {}, events = {} }
		G.stateOf(p).lastPick = -math.huge
		local ok, why = G.pick(p, "townsperson")
		if not ok then
			table.insert(setup, `{name} could not pick a townsperson: {tostring(why)}`)
		end
		local actor = G.runtime.possession:actorOf(p)
		local body = actor and actor.body
		if body then
			-- in front of the middle machine (each machine's stance is a few studs from the next)
			local X, D = Cabinet.stance(2)
			local x, y, z = AlleyLayout.toWorld(A.place, X + (i - 1.5) * 2, 3.2, D + 0.5)
			body:PivotTo(CFrame.new(x, y, z))
		end
		players[i] = p
	end
	local result = PinballFlow.play(A.minigames, deps, {
		players = players,
		step = function(seconds: number)
			for _ = 1, math.max(1, math.ceil(seconds / 0.1 - 1e-6)) do
				A.step(0.1)
			end
		end,
	})
	for _, f in setup do
		table.insert(result.failures, 1, f)
	end
	result.ok = #result.failures == 0
	result.numbers.bootSeconds = bootSeconds
	G.stop()
	return result
end

return PinballFlow
