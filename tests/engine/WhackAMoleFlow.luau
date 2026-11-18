--!strict
-- ServerStorage.EngineTests.WhackAMoleFlow (CI place only; injected with --inject ci.project.json or a saved version)
-- The whack-a-mole flow on a server with no clients, as plain results. Two PlayerLike stubs at the real
-- MinigameService's cabinet (whack_a_mole_1): the player strikes from what it is sent (the stream of moles) with
-- stamps on the real shared clock, the other stands beside the cabinet and watches.
--   early    a strike in the count-in is refused with words and scores nothing
--   round    every mole the stream brings is struck 0.15 s into its rise for a few seconds: each is a hit, +10,
--            and the watcher is sent the same moles and hits; a scripted miss (MinigameService:debug) costs 2
--   busy     the watcher cannot take the cabinet while the round is on
--   end      the round runs out by itself: whack_over once, its score the last strike's, the board on the cabinet
--            (attribute "Best") has the player on it
--   again    Play again starts round 2; the player walks off in the middle (leaves): the cabinet is idle, the
--            watcher hears it is free, and nothing more is sent to the player
-- Nothing here needs a client: the moles' drawing, the camera and the screen are client code, run under Lune on
-- the fake engine (tests/isolated/whack_a_mole_client.luau) and checked by eye in a Play session.
-- play() takes any MinigameService, so the Lune suite runs this same flow on the fake engine first.
-- Interface: run() -> Result (engine only: boots Server/Boot/Game); play(svc, deps, opts) -> Result { ok,
--   failures, numbers }; STATION; opts = { players = { player, watcher }, step = (seconds) -> () (lets that much
--   time pass on the service AND on the shared clock), stamp = () -> number (the shared clock) }

local WhackAMoleFlow = {}

WhackAMoleFlow.STATION = "whack_a_mole_1"
WhackAMoleFlow.READY = 3 -- (Round.READY: the count-in)
WhackAMoleFlow.SECONDS = 45 -- (Round.SECONDS)

type Opts = { players: { any }, step: (seconds: number) -> (), stamp: () -> number }

function WhackAMoleFlow.play(svc: any, _deps: any, opts: Opts): { [string]: any }
	local ID = WhackAMoleFlow.STATION
	local failures: { string } = {}
	local numbers: { [string]: number } = {}
	local function check(cond: any, what: string)
		if not cond then
			table.insert(failures, what)
		end
	end
	local st = svc.stations[ID]
	if st == nil or st.tbl == nil then
		return { ok = false, failures = { "there is no whack-a-mole cabinet at " .. ID }, numbers = numbers }
	end
	local player, watcher = opts.players[1], opts.players[2]
	local function input(p: any, verb: string, args: { any }?): (boolean, string?)
		return svc:input(p, { gameId = ID, seat = 1, verb = verb, args = args or {} })
	end
	local function last(p: any, kind: string): any
		for i = #p.events, 1, -1 do
			if p.events[i].kind == kind then
				return p.events[i]
			end
		end
		return nil
	end
	local function count(p: any, kind: string, g: number?): number
		local n = 0
		for _, e in p.events do
			if e.kind == kind and (g == nil or e.g == g) then
				n += 1
			end
		end
		return n
	end
	local function phase(): string
		return st.session.phase
	end

	-- early: the round starts on the press; a strike in the count-in is refused
	local ok, why = svc:join(player, ID)
	check(ok, `the player could not take the cabinet: {tostring(why)}`)
	local round = last(player, "whack_round")
	check(round ~= nil and type(round.start) == "number", "the player was sent the round with its GO")
	if round == nil then
		return { ok = false, failures = failures, numbers = numbers }
	end
	local start: number = round.start
	local g: number = round.g
	ok, why = input(player, "whack", { 1, opts.stamp() })
	check(not ok and why == "Wait for GO!", `a strike in the count-in: {tostring(ok)} {tostring(why)}`)

	-- round: strike every mole the stream brings, 0.15 s into its rise, for a few seconds
	opts.step(WhackAMoleFlow.READY + 0.2)
	local struck: { [number]: boolean } = {}
	local hits, made = 0, 0
	local swung = -math.huge
	-- strike every mole of round `which` the stream has brought that has been up 0.15 s (one mallet: a strike at
	-- most every 0.12 s, the rest wait for the next step); returns the strikes made and how many were hits
	local function swing(which: number, from: number): (number, number)
		local n, h = 0, 0
		local now = opts.stamp() - from
		for _, e in player.events do
			if
				e.kind == "whack_rise"
				and e.g == which
				and not struck[e.id + which * 10000]
				and now >= e.at + 0.15
				and opts.stamp() - swung >= 0.12
			then
				struck[e.id + which * 10000] = true
				swung = opts.stamp()
				n += 1
				local took, said = input(player, "whack", { e.hole, opts.stamp() })
				check(took, `a strike on mole {e.id} was refused: {tostring(said)}`)
				local hit = last(player, "whack_hit")
				if hit and hit.id == e.id and hit.result == "hit" then
					h += 1
				end
			end
		end
		return n, h
	end
	local t0 = opts.stamp()
	while opts.stamp() - t0 < 6 do
		opts.step(0.05)
		local n, h = swing(g, start)
		made += n
		hits += h
	end
	numbers.struck = made
	numbers.hits = hits
	check(made >= 4, `only {made} moles came in six seconds`)
	check(hits == made, `{hits} of {made} strikes were hits`)
	local score = (last(player, "whack_hit") or {}).score
	check(score == hits * 10, `the score is {tostring(score)} after {hits} hits`)
	check(count(watcher, "whack_rise", g) > 0, "the watcher was sent the moles")
	check(count(watcher, "whack_hit", g) == hits, "the watcher was sent every strike")
	local before = score or 0
	ok, why = svc:debug(ID, "miss")
	check(ok, `a scripted miss: {tostring(why)}`)
	check((last(player, "whack_hit") or {}).score == math.max(0, before - 2), "a miss costs 2")

	-- busy: the cabinet is the player's
	ok = svc:join(watcher, ID)
	check(not ok, "the watcher took the cabinet in the middle of a round")

	-- end: the round runs out by itself (the player keeps playing: one who strikes nothing for a while is taken off)
	local guard = 0
	while last(player, "whack_over") == nil and guard < 1200 do
		guard += 1
		opts.step(0.05)
		if phase() == "playing" then
			swing(g, start)
		end
	end
	local over = last(player, "whack_over")
	check(over ~= nil, "the round never ended")
	numbers.score = over and over.score or -1
	check(count(player, "whack_over") == 1, "the end was said once")
	check(over and over.score == (last(player, "whack_hit") or {}).score, "the end's score is the last strike's")
	check(over and over.place and over.place >= 1, "the player's round is on the board")
	check(phase() == "done", `the cabinet is {phase()} at the end`)
	local hw = st.tbl.hw
	if hw then
		local best = hw.model:GetAttribute("Best")
		check(type(best) == "string" and string.find(best, player.Name, 1, true) ~= nil, "the board on the cabinet")
	end

	-- again, then the player walks off in the middle
	ok, why = input(player, "again")
	check(ok, `Play again: {tostring(why)}`)
	local second = last(player, "whack_round")
	check(second and second.g == g + 1, "a second round")
	opts.step(WhackAMoleFlow.READY + 2)
	local idleBefore = count(watcher, "whack_idle")
	ok = input(player, "leave")
	check(ok, "leaving")
	opts.step(0.5)
	check(phase() == "idle", `the cabinet is {phase()} after the player left`)
	check(count(watcher, "whack_idle") > idleBefore, "the watcher heard the cabinet is free")
	local heard = #player.events
	opts.step(2)
	check(#player.events == heard, `{#player.events - heard} messages to a player who has gone`)
	numbers.rounds = st.tbl.games
	return { ok = #failures == 0, failures = failures, numbers = numbers }
end

function WhackAMoleFlow.run(): { [string]: any }
	local ServerScriptService = game:GetService("ServerScriptService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local server = ServerScriptService:WaitForChild("Server")
	local Game = (require :: any)(server:WaitForChild("Boot"):WaitForChild("Game"))
	local Possession = (require :: any)(server:WaitForChild("Actors"):WaitForChild("Possession"))
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local AlleyLayout = (require :: any)(Shared:WaitForChild("Attractions"):WaitForChild("AlleyLayout"))
	local Layout = (require :: any)(Shared:WaitForChild("Minigames"):WaitForChild("WhackAMole"):WaitForChild("Layout"))

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
	-- two townspeople: one at the cabinet's front, one a few studs to its side
	local players: { any } = {}
	local setup: { string } = {}
	for i, name in { "Ann", "Bob" } do
		local p = { UserId = 5500 + i, Name = name, Character = nil, attrs = {}, events = {} }
		G.stateOf(p).lastPick = -math.huge
		local okPick, why = G.pick(p, "townsperson")
		if not okPick then
			table.insert(setup, `{name} could not pick a townsperson: {tostring(why)}`)
		end
		local actor = G.runtime.possession:actorOf(p)
		local body = actor and actor.body
		if body then
			local X, Y, D = Layout.toSite(Layout.STAND.u + (i - 1) * 4, 3.2, Layout.STAND.w)
			local x, y, z = AlleyLayout.toWorld(A.place, X, Y, D)
			body:PivotTo(CFrame.new(x, y, z))
		end
		players[i] = p
	end
	local result = WhackAMoleFlow.play(A.minigames, {}, {
		players = players,
		-- strikes are judged against the shared clock, which only real time moves: the service is stepped by
		-- the time that really passed
		step = function(seconds: number)
			local left = seconds
			while left > 0 do
				local dt = RunService.Heartbeat:Wait()
				A.step(dt)
				left -= dt
			end
		end,
		stamp = function(): number
			return workspace:GetServerTimeNow()
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

return WhackAMoleFlow
