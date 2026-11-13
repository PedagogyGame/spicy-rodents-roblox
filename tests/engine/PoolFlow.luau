--!strict
-- ServerStorage.EngineTests.PoolFlow (CI place only; injected with --inject ci.project.json or a saved version)
-- The eight-ball flow on a server with no clients, as plain results (brief v2 §13a). PlayerLike stubs take
-- seats at pool table 1 of the real MinigameService and play what Pool/Computer would play, through the same
-- input path as a person's mouse; what comes back is what the table did:
--   practice  one person alone: the cue ball set down in the kitchen and the break; one script to everyone
--             ("pool_shot", Wire text that decodes), nothing judged while the balls roll (busy), then the
--             rules' state with the rack broken and the server's ball Models where the rules lay them
--   eight     a scripted table (MinigameService:debug "layout"): solids cleared, the 8 in front of the head
--             left corner, called and potted: the game is won, "potted the 8 in the called pocket"
--   computer  a whole game against Chalky (easy): the computer thinks, its cue comes back for a second
--             (lead), it plays; to the end card, then Play again with the winner breaking
--   leave     two people; the second leaves mid-game and forfeits: the first wins, "left the table"; the
--             first leaves too, and the table is idle and racked, nothing more sent to anyone
-- Nothing here needs a client: aiming, the camera, the drawing and the screen are client code, run under Lune on
-- the fake engine (tests/isolated/pool_game.luau, pool_people.luau) and checked by eye in a Play session.
-- play() takes any MinigameService, so the Lune suite runs this same flow on the fake engine first.
-- Interface: run() -> Result (engine only: boots Server/Boot/Game); play(svc, deps, opts) -> Result { ok,
--   failures, numbers }; deps = { EightBall, Computer, Tables, Cue, Wire, Furniture } (the shared modules); opts = {
--   players = { stub, stub }, step = (seconds) -> () }

local PoolFlow = {}

PoolFlow.STATION = "pool_1"

type Deps = { EightBall: any, Computer: any, Tables: any, Cue: any, Wire: any, Furniture: any }
type Opts = { players: { any }, step: (seconds: number) -> () }

function PoolFlow.play(svc: any, deps: Deps, opts: Opts): { [string]: any }
	local EightBall, Computer, Tables, Cue, Wire = deps.EightBall, deps.Computer, deps.Tables, deps.Cue, deps.Wire
	local ID = PoolFlow.STATION
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
		return { ok = false, failures = { "there is no pool table at " .. ID }, numbers = numbers }
	end
	local tbl = station.tbl
	local ann, bob = opts.players[1], opts.players[2]
	local TABLE = Tables.eightBall()
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
	-- run the table until no shot is in flight (and at least a step)
	local function settle(limit: number): boolean
		local t = 0
		repeat
			opts.step(0.1)
			t += 0.1
		until tbl.pending == nil or t > limit
		return tbl.pending == nil
	end
	-- a person's turn, as Pool/Computer would play it
	local function turn(p: any, level: number, seed: number): boolean
		local st = state()
		local ok = true
		for _, inp in Computer.eightBall(st, level, seed) do
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
		local st = state()
		local worst = 0
		for _, s in st.spots do
			local at = hw:position(s.id)
			if check(at, `{label}: ball {s.id} has no Model`) then
				local x, _, z = deps.Furniture.fromWorld(tbl.ctx.place, tbl.ctx.station, at.X, at.Y, at.Z)
				local off = math.max(math.abs(x - s.x), math.abs(z - s.z))
				if off > worst then
					worst = off
					numbers.worstBall = s.id
				end
			end
		end
		check(worst < 1e-3, `{label}: a ball Model is {worst} studs from where the rules have it`)
		return 1
	end

	-- practice: alone, the cue ball set down and the break
	check(svc:join(ann, ID), "Ann could not sit at the table")
	check(input(ann, "start"), "Ann could not start")
	opts.step(0.2)
	local s = session()
	check(s.phase == "playing", `practice: the phase is {s.phase}`)
	local st = state()
	if st then
		check(st.seats == 1, "practice is one seat")
		check(st.inHand == "kitchen", "the break is from the kitchen")
		check(input(ann, "place", { 0.4, TABLE.headZ - 0.2 }), "the cue ball could not be set down in the kitchen")
		local refused = input(ann, "place", { 0, 0 })
		check(not refused, "the cue ball was set down past the head string for the break")
		local apex: any = nil
		for _, b in st.spots do
			if b.id == 1 then
				apex = b
			end
		end
		local shots = count(ann, "pool_shot")
		check(
			input(ann, "shoot", { Cue.angleOf(apex.x - 0.4, apex.z - (TABLE.headZ - 0.2)), 0.95, 0, 0 }),
			"the break was refused"
		)
		opts.step(0.2)
		check(count(ann, "pool_shot") == shots + 1, "the break's script was not sent")
		local msg = last(ann, "pool_shot")
		local script = msg and Wire.decode(msg.text)
		check(script ~= nil, "the break's script does not decode")
		check(tbl.pending ~= nil and st.shotNo == 0, "the break was judged while the balls rolled")
		check(tbl:busy(), "the turn clock does not wait for the balls")
		check(settle(30), "the break never finished")
		check(st.shotNo == 1 and st.broken, "the break did not break the rack")
		numbers.breakSeconds = if script then script.tEnd else -1
		numbers.breakDown = #st.down
		-- (a moment for a watching client's playback, a few frames behind, to finish on the same balls)
		opts.step(1)
		numbers.hardware = laidOut("after the break")

		-- the 8: a scripted table, a called pocket, the win
		local hole = TABLE.holes[1]
		local cx, cz = hole.x + 1.6, hole.z + 1.6
		check(
			svc:debug(ID, "layout", {
				{ id = 0, x = cx, z = cz },
				{ id = 8, x = hole.x + 0.75, z = hole.z + 0.75 },
				{ id = 11, x = 1.5, z = 3.5 },
			}, { broken = true, group = { "solids" }, inHand = "none", seat = 1 }),
			"the scripted layout was refused"
		)
		opts.step(0.2)
		check(EightBall.onEight(st, 1), "the scripted table is not on the 8")
		local early = input(ann, "shoot", { Cue.angleOf(-1, -1), 0.3, 0, 0 })
		check(not early, "a shot at the 8 with no pocket called was taken")
		check(input(ann, "call", { 1 }), "the pocket could not be called")
		check(input(ann, "shoot", { Cue.angleOf(-1, -1), 0.3, 0, 0 }), "the shot at the 8 was refused")
		check(settle(20), "the shot at the 8 never finished")
		opts.step(0.3)
		check(s.phase == "done", `the 8 in the called pocket did not end the game ({s.phase})`)
		check(st.how == "eight", `the game ended by {tostring(st.how)}`)
		opts.step(0.3)
		local again = last(ann, "pool_shot")
		check(again and again.replay == true and again.speed < 1, "the winning 8 is not played again slowly")
		check(input(ann, "leave"), "Ann could not leave")
		opts.step(0.2)
		check(s.phase == "idle", "the table is not idle after practice")
	end

	-- a whole game against the computer (Ann plays the best computer player's shots)
	check(svc:join(ann, ID), "Ann could not sit down again")
	check(input(ann, "addai", { "Chalky" }), "Chalky could not be added")
	check(input(ann, "start"), "the game against Chalky did not start")
	opts.step(0.2)
	s = session()
	st = state()
	local guard, mine, theirs = 0, 0, 0
	local lead = 0
	while s.phase == "playing" and guard < 300 do
		guard += 1
		settle(30)
		if s.phase ~= "playing" then
			break
		end
		local seat = EightBall.turn(st)
		local before = count(ann, "pool_shot")
		if seat == 1 then
			turn(ann, 3, 1000 + guard)
			mine += 1
		else
			local waited = 0
			while count(ann, "pool_shot") == before and s.phase == "playing" and waited < 20 do
				opts.step(0.1)
				waited += 0.1
			end
			check(waited < 20, "the computer never played")
			local m = last(ann, "pool_shot")
			if m and m.seat == 2 then
				lead = m.lead
			end
			theirs += 1
		end
	end
	check(s.phase == "done", `the game against Chalky did not end in {guard} turns`)
	check(lead >= 0.9, "the computer's cue is not drawn back before it strikes")
	numbers.gameShots = mine + theirs
	numbers.computerShots = theirs
	numbers.winner = st.winner or 0
	local winner = st.winner
	check(input(ann, "again"), "Play again was refused")
	opts.step(0.3)
	local fresh = state()
	check(s.phase == "playing" and fresh ~= st, "Play again did not rack a new game")
	if fresh and winner then
		check(EightBall.turn(fresh) == winner, "the winner does not break the next game")
	end
	check(input(ann, "leave"), "Ann could not leave the second game")
	opts.step(0.3)
	check(s.phase == "idle", "the table is not idle after the game against the computer")

	-- two people; Bob leaves mid-game and forfeits
	check(svc:join(ann, ID), "Ann could not sit down for the third time")
	check(svc:join(bob, ID), "Bob could not join")
	check(input(ann, "start"), "the two-person game did not start")
	opts.step(0.2)
	s = session()
	st = state()
	check(s.names[2] == bob.Name, "Bob is not in the second seat")
	turn(ann, 3, 77)
	settle(30)
	if EightBall.turn(st) == 2 then
		turn(bob, 1, 78)
		settle(30)
	end
	local sentBefore = #ann.events
	check(input(bob, "leave"), "Bob could not leave")
	opts.step(0.3)
	check(s.phase == "done", `Bob's leaving did not end the game ({s.phase})`)
	check(st.winner == 1 and st.how == "left", "Bob's leaving was not a forfeit to Ann")
	check(#ann.events > sentBefore, "Ann was told nothing")
	check(input(ann, "leave"), "Ann could not leave the last game")
	opts.step(0.5)
	check(s.phase == "idle", "the table is not idle at the end")
	check(tbl.pending == nil, "a shot is still in flight at an idle table")
	local quietA, quietB = #ann.events, #bob.events
	opts.step(3)
	check(#ann.events == quietA and #bob.events == quietB, "an idle table still sends")
	check(tbl.laid ~= nil and #tbl.laid.spots == 16, "the idle table is not racked")
	return { ok = #failures == 0, failures = failures, numbers = numbers }
end

function PoolFlow.run(): { [string]: any }
	local ServerScriptService = game:GetService("ServerScriptService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local server = ServerScriptService:WaitForChild("Server")
	local Game = (require :: any)(server:WaitForChild("Boot"):WaitForChild("Game"))
	local Possession = (require :: any)(server:WaitForChild("Actors"):WaitForChild("Possession"))
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local pool = Shared:WaitForChild("Minigames"):WaitForChild("Pool")
	local deps: Deps = {
		EightBall = (require :: any)(pool:WaitForChild("EightBall")),
		Computer = (require :: any)(pool:WaitForChild("Computer")),
		Tables = (require :: any)(pool:WaitForChild("Tables")),
		Cue = (require :: any)(pool:WaitForChild("Cue")),
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
	-- two townspeople beside table 1's long rail (the service takes anyone who wanders off)
	local at = AlleyLayout.POOL_TABLES[1]
	local players: { any } = {}
	local setup: { string } = {}
	for i, name in { "Ann", "Bob" } do
		local p = { UserId = 5600 + i, Name = name, Character = nil, attrs = {}, events = {} }
		G.stateOf(p).lastPick = -math.huge
		local ok, why = G.pick(p, "townsperson")
		if not ok then
			table.insert(setup, `{name} could not pick a townsperson: {tostring(why)}`)
		end
		local actor = G.runtime.possession:actorOf(p)
		local body = actor and actor.body
		if body then
			local x, y, z = AlleyLayout.toWorld(A.place, at.x - 6, 3.2, at.d + (i - 1.5) * 3)
			body:PivotTo(CFrame.new(x, y, z))
		end
		players[i] = p
	end
	-- the service is stepped as fast as it will go: pool judges nothing by the shared clock
	local result = PoolFlow.play(A.minigames, deps, {
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

return PoolFlow
