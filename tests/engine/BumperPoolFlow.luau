--!strict
-- ServerStorage.EngineTests.BumperPoolFlow (CI place only; injected with --inject ci.project.json or a saved
-- version)
-- The bumper pool flow on a server with no clients, as plain results (brief v2 §13a). PlayerLike stubs take
-- seats at the bumper pool table of the real MinigameService and play what Pool/Computer would play, through
-- the same input path as a person's mouse; what comes back is what the table did:
--   practice  one person alone: a strike at the marked ball; one script to everyone ("bumper_pool_shot", Wire
--             text that decodes), nothing judged while the balls roll (busy), then the server's ball Models
--             where the rules lay them and the other side's five out of sight
--   computer  a whole game against Bumper Bob (easy): the opening (the person's strike waits for the
--             computer's, and one script carries both), then turn by turn to the end card
--   leave     two people open together; the second leaves and forfeits: the first wins, "left the table"; the
--             first leaves too, and the table is idle with every ball on its spot, nothing more sent
-- Nothing here needs a client: aiming, the camera, the drawing and the screen are client code, run under Lune on
-- the fake engine (tests/isolated/bumper_pool_game.luau) and checked by eye in a Play session.
-- play() takes any MinigameService, so the Lune suite runs this same flow on the fake engine first.
-- Interface: run() -> Result (engine only: boots Server/Boot/Game); play(svc, deps, opts) -> Result { ok,
--   failures, numbers }; deps = { BumperPool, Computer, Tables, Wire, Furniture } (the shared modules); opts =
--   { players = { stub, stub }, step = (seconds) -> () }

local BumperPoolFlow = {}

BumperPoolFlow.STATION = "bumper_pool_1"

type Deps = { BumperPool: any, Computer: any, Tables: any, Wire: any, Furniture: any }
type Opts = { players: { any }, step: (seconds: number) -> () }

function BumperPoolFlow.play(svc: any, deps: Deps, opts: Opts): { [string]: any }
	local BumperPool, Computer, Tables, Wire = deps.BumperPool, deps.Computer, deps.Tables, deps.Wire
	local ID = BumperPoolFlow.STATION
	local failures: { string } = {}
	local numbers: { [string]: number } = {}
	local function check(cond: any, what: string): boolean
		if not cond then
			table.insert(failures, what)
		end
		return cond == true or (cond ~= nil and cond ~= false)
	end
	local station = svc.stations[ID]
	if station == nil or station.tbl == nil then
		return { ok = false, failures = { "there is no bumper pool table at " .. ID }, numbers = numbers }
	end
	local tbl = station.tbl
	local ann, bob = opts.players[1], opts.players[2]
	local TABLE = Tables.bumper()
	local function input(p: any, verb: string, args: { any }?): (boolean, string?)
		return svc:input(p, { gameId = ID, seat = 1, verb = verb, args = args or {} })
	end
	local function session(): any
		return svc:sessionOf(ID)
	end
	local function state(): any
		local s = session()
		return s and s.game and s.game.state
	end
	local function count(p: any, kind: string): number
		local n = 0
		for _, e in p.events do
			if e.kind == kind then
				n += 1
			end
		end
		return n
	end
	local function last(p: any, kind: string): any
		for i = #p.events, 1, -1 do
			if p.events[i].kind == kind then
				return p.events[i]
			end
		end
		return nil
	end
	local function settle(limit: number): boolean
		local t = 0
		repeat
			opts.step(0.1)
			t += 0.1
		until tbl.pending == nil or t > limit
		return tbl.pending == nil
	end
	local function turn(p: any, seat: number, level: number, seed: number): boolean
		local ok = true
		for _, inp in Computer.bumper(state(), seat, level, seed) do
			local done, why = input(p, inp.verb, inp.args)
			ok = check(done, `{p.Name}'s {inp.verb} was refused: {tostring(why)}`) and ok
		end
		return ok
	end
	-- every ball Model where the rules have it (the table's frame), if the table is built here
	local function laidOut(label: string): number
		local hw = tbl.hw
		if hw == nil then
			return 0
		end
		local worst = 0
		for _, s in state().spots do
			local at = hw:position(s.id)
			if check(at, `{label}: ball {s.id} has no Model`) then
				local x, y, z = deps.Furniture.fromWorld(tbl.ctx.place, tbl.ctx.station, at.X, at.Y, at.Z)
				worst = math.max(worst, math.abs(x - s.x), math.abs(z - s.z), math.abs(y - TABLE.ballR))
			end
		end
		check(worst < 1e-3, `{label}: a ball Model is {worst} studs from where the rules have it`)
		return 1
	end

	-- practice: alone, a strike at the marked ball
	check(svc:join(ann, ID), "Ann could not sit at the table")
	check(input(ann, "start"), "Ann could not start")
	opts.step(0.2)
	local s = session()
	local st = state()
	check(s.phase == "playing", `practice: the phase is {s.phase}`)
	if st then
		check(st.seats == 1 and st.phase == "play", "practice is one seat and no opening")
		check(not input(ann, "shoot", { 6, 0, 0.5 }), "a ball of the other side was struck in practice")
		local shots = count(ann, "bumper_pool_shot")
		turn(ann, 1, 3, 11)
		opts.step(0.2)
		check(count(ann, "bumper_pool_shot") == shots + 1, "the strike's script was not sent")
		local msg = last(ann, "bumper_pool_shot")
		check(msg and Wire.decode(msg.text) ~= nil, "the strike's script does not decode")
		check(tbl.pending ~= nil and st.shotNo == 0, "the shot was judged while the balls rolled")
		check(tbl:busy(), "the turn clock does not wait for the balls")
		check(settle(30), "the shot never finished")
		check(st.shotNo == 1, "the shot was not judged")
		-- (a moment for a watching client's playback, a few frames behind, to finish on the same balls)
		opts.step(1)
		numbers.hardware = laidOut("after the practice shot")
		if tbl.hw then
			local at = tbl.hw:position(8)
			local _, y = deps.Furniture.fromWorld(tbl.ctx.place, tbl.ctx.station, at.X, at.Y, at.Z)
			check(y < -0.5, "the other side's balls are not out of sight in practice")
		end
		check(input(ann, "leave"), "Ann could not leave practice")
		opts.step(0.2)
	end

	-- a whole game against the computer
	check(svc:join(ann, ID), "Ann could not sit down again")
	check(input(ann, "addai", { "Bumper Bob" }), "Bumper Bob could not be added")
	check(input(ann, "start"), "the game against Bumper Bob did not start")
	opts.step(0.2)
	s = session()
	st = state()
	check(st and st.phase == "opening", "the game did not open with both marked balls")
	local before = count(ann, "bumper_pool_shot")
	turn(ann, 1, 3, 21)
	opts.step(0.2)
	check(count(ann, "bumper_pool_shot") == before, "the opening played before the computer struck")
	local waited = 0
	while count(ann, "bumper_pool_shot") == before and waited < 20 do
		opts.step(0.1)
		waited += 0.1
	end
	local opening = last(ann, "bumper_pool_shot")
	local script = opening and Wire.decode(opening.text)
	check(script and #script.strikes == 12, "the opening is not one script with both strikes")
	local guard, mine, theirs = 0, 1, 1
	while s.phase == "playing" and guard < 300 do
		guard += 1
		settle(30)
		if s.phase ~= "playing" then
			break
		end
		local seat = BumperPool.turn(st)
		if seat == 1 then
			turn(ann, 1, 3, 100 + guard)
			mine += 1
		else
			local n = count(ann, "bumper_pool_shot")
			local w = 0
			while count(ann, "bumper_pool_shot") == n and s.phase == "playing" and w < 20 do
				opts.step(0.1)
				w += 0.1
			end
			check(w < 20, "the computer never played")
			theirs += 1
		end
	end
	check(s.phase == "done", `the game against Bumper Bob did not end in {guard} turns`)
	numbers.gameShots = mine + theirs
	numbers.winner = st.winner or 0
	check(input(ann, "leave"), "Ann could not leave the game against the computer")
	opts.step(0.3)
	check(s.phase == "idle", "the table is not idle after the game against the computer")

	-- two people open together; Bob leaves and forfeits
	check(svc:join(ann, ID), "Ann could not sit down for the third time")
	check(svc:join(bob, ID), "Bob could not join")
	check(input(ann, "start"), "the two-person game did not start")
	opts.step(0.2)
	st = state()
	turn(ann, 1, 1, 32)
	opts.step(0.2)
	check(tbl.pending == nil, "the opening played before the second strike")
	turn(bob, 2, 1, 31)
	check(settle(30), "the opening between two people never finished")
	check(st.phase == "play", "the opening was not played")
	local sentBefore = #ann.events
	check(input(bob, "leave"), "Bob could not leave")
	opts.step(0.3)
	check(s.phase == "done", `Bob's leaving did not end the game ({s.phase})`)
	check(st.winner == 1 and st.how == "left", "Bob's leaving was not a forfeit to Ann")
	check(#ann.events > sentBefore, "Ann was told nothing")
	check(input(ann, "leave"), "Ann could not leave the last game")
	opts.step(0.5)
	check(s.phase == "idle", "the table is not idle at the end")
	check(tbl.laid ~= nil and #tbl.laid.spots == 10, "the idle table's balls are not on their spots")
	local quietA, quietB = #ann.events, #bob.events
	opts.step(3)
	check(#ann.events == quietA and #bob.events == quietB, "an idle table still sends")
	return { ok = #failures == 0, failures = failures, numbers = numbers }
end

function BumperPoolFlow.run(): { [string]: any }
	local ServerScriptService = game:GetService("ServerScriptService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local server = ServerScriptService:WaitForChild("Server")
	local Game = (require :: any)(server:WaitForChild("Boot"):WaitForChild("Game"))
	local Possession = (require :: any)(server:WaitForChild("Actors"):WaitForChild("Possession"))
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local pool = Shared:WaitForChild("Minigames"):WaitForChild("Pool")
	local deps: Deps = {
		BumperPool = (require :: any)(pool:WaitForChild("BumperPool")),
		Computer = (require :: any)(pool:WaitForChild("Computer")),
		Tables = (require :: any)(pool:WaitForChild("Tables")),
		Wire = (require :: any)(pool:WaitForChild("Wire")),
		Furniture = (require :: any)(pool:WaitForChild("Furniture")),
	}
	local AlleyLayout = (require :: any)(Shared:WaitForChild("Attractions"):WaitForChild("AlleyLayout"))
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
	-- two townspeople beside the table's long rail (the service takes anyone who wanders off)
	local at = AlleyLayout.BUMPER_POOL
	local players: { any } = {}
	local setup: { string } = {}
	for i, name in { "Ann", "Bob" } do
		local p = { UserId = 5700 + i, Name = name, Character = nil, attrs = {}, events = {} }
		G.stateOf(p).lastPick = -math.huge
		local ok, why = G.pick(p, "townsperson")
		if not ok then
			table.insert(setup, `{name} could not pick a townsperson: {tostring(why)}`)
		end
		local actor = G.runtime.possession:actorOf(p)
		local body = actor and actor.body
		if body then
			local x, y, z = AlleyLayout.toWorld(A.place, at.x - 4, 3.2, at.d + (i - 1.5) * 3)
			body:PivotTo(CFrame.new(x, y, z))
		end
		players[i] = p
	end
	-- the service is stepped as fast as it will go: bumper pool judges nothing by the shared clock
	local result = BumperPoolFlow.play(A.minigames, deps, {
		players = players,
		step = function(seconds: number)
			local left = seconds
			while left > 1e-9 do
				local dt = math.min(left, 1 / 30)
				A.step(dt)
				left -= dt
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

return BumperPoolFlow
