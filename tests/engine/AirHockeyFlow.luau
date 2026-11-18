--!strict
-- ServerStorage.EngineTests.AirHockeyFlow (CI place only; injected with --inject ci.project.json or a saved version)
-- The air hockey flow on a server with no clients, as plain results. PlayerLike stubs take the ends of the real
-- MinigameService's table; each stub's hand is a Seat (Shared/Minigames/AirHockey/Seat: the same prediction and
-- log a client runs) driven here, so the logs that reach the referee are real ones, on the real shared clock.
--   solo     one person against the computer for a few seconds: the referee steps from the log, the stream
--            comes back and matches the stub's own prediction to the last bit (no correction, no desync), the
--            server's puck leaves its spot
--   seven    the score is scripted to 6-2 and a goal for Glacier is stood in front of the goal
--            (MinigameService:debug): the simulation scores it, the rules have 7-2, the match is over once,
--            the board on the wall says so
--   again    Play again; a second person takes the computer's end in mid-match and plays; leaves, and the
--            computer has the end back; the first leaves and the table is at rest with nothing more sent
-- Nothing here needs a client: the mouse, the camera, the drawing and the screen are client code, run under
-- Lune on the fake engine (tests/isolated/air_hockey_client.luau) and checked by eye in a Play session.
-- play() takes any MinigameService, so the Lune suite runs this same flow on the fake engine first.
-- Interface: run() -> Result (engine only: boots Server/Boot/Game); play(svc, deps, opts) -> Result { ok,
--   failures, numbers }; deps = { Seat, Sim, Layout } (the shared modules); opts = { players = { stub, stub },
--   step = (seconds) -> () (lets that much time pass on the service AND on the shared clock), stamp = () ->
--   number (the shared clock) }

local AirHockeyFlow = {}

type Deps = { Seat: any, Sim: any, Layout: any }
type Opts = { players: { any }, step: (seconds: number) -> (), stamp: () -> number }

function AirHockeyFlow.play(svc: any, deps: Deps, opts: Opts): { [string]: any }
	local Seat, Sim, Layout = deps.Seat, deps.Sim, deps.Layout
	local ID, EMBER = Layout.STATION, Layout.STATION_EMBER
	local failures: { string } = {}
	local numbers: { [string]: number } = {}
	local function check(cond: any, what: string)
		if not cond then
			table.insert(failures, what)
		end
	end
	local station = svc.stations[ID]
	if station == nil or station.tbl == nil then
		return { ok = false, failures = { "there is no air hockey table at " .. ID }, numbers = numbers }
	end
	local tbl = station.tbl
	local session = svc:sessionOf(ID)
	local ann, bob = opts.players[1], opts.players[2]

	-- a stub's hand: the computer's own plan played by a person (behind the puck, then through it)
	local scratch = Sim.new()
	local hands: { [any]: any } = {}
	local function hand(player: any): any
		local h = hands[player]
		if h == nil then
			h = { seat = nil, read = 0, refused = {} }
			hands[player] = h
		end
		return h
	end
	local function frame()
		for player, h in hands do
			local events = player.events
			while h.read < #events do
				h.read += 1
				local msg = events[h.read]
				if msg.kind == "air_hockey_seat" then
					h.seat = Seat.new(msg.side)
					Seat.begin(h.seat, msg.g, msg.from)
				elseif msg.kind == "air_hockey" and h.seat then
					Seat.push(h.seat, msg)
				elseif msg.kind == "left" then
					h.seat = nil
				end
			end
			local seat = h.seat
			if seat and seat.replica.game ~= nil then
				if seat.ready then
					Sim.copy(scratch, seat.pred)
					Sim.ai(scratch, seat.side)
					if seat.side == 0 then
						Seat.aim(seat, scratch.t0x, scratch.t0y)
					else
						Seat.aim(seat, scratch.t1x, scratch.t1y)
					end
				end
				Seat.step(
					seat,
					(opts.stamp() - seat.replica.t0) / Sim.STEP,
					function(from: number, to: number, strings: { string })
						local args: { any } = { from, to }
						for _, s in strings do
							table.insert(args, s)
						end
						local ok, why = svc:input(player, { gameId = ID, seat = 1, verb = "log", args = args })
						if not ok then
							table.insert(h.refused, tostring(why))
						end
					end
				)
			end
		end
	end
	local function run(seconds: number)
		for _ = 1, math.ceil(seconds * 30) do
			opts.step(1 / 30)
			frame()
		end
	end
	local function last(player: any, kind: string): any
		for i = #player.events, 1, -1 do
			if player.events[i].kind == kind then
				return player.events[i]
			end
		end
		return nil
	end

	-- solo -------------------------------------------------------------------------------------------------------
	local home = if tbl.hw then tbl.hw.puck:GetPivot().Position else nil
	hand(ann)
	local ok, why = svc:join(ann, ID)
	check(ok, `Ann could not join: {tostring(why)}`)
	check(session.phase == "lobby", `the lobby is open (phase {session.phase})`)
	ok, why = svc:input(ann, { gameId = ID, seat = 1, verb = "mode", args = { "hard" } })
	check(ok, `the lobby takes a difficulty: {tostring(why)}`)
	ok, why = svc:input(ann, { gameId = ID, seat = 1, verb = "start", args = {} })
	check(ok, `Start: {tostring(why)}`)
	run(0.3)
	local ref = tbl.ref
	check(session.phase == "playing" and ref ~= nil, "a match is on")
	if ref == nil then
		return { ok = false, failures = failures, numbers = numbers }
	end
	check(#svc:_seated(station) == 2, "the computer took the other end")
	check(ref.sim.difficulty == Sim.DIFFICULTY.hard, "the hard computer, as the lobby chose")
	check(tbl.sideOf[ann] == 0, "the Glacier prompt is the Glacier end")
	local seatMsg = last(ann, "air_hockey_seat")
	check(seatMsg ~= nil and seatMsg.side == 0 and seatMsg.from == 0, "Ann was told her end and where her log starts")
	run(6)
	local seat = hands[ann].seat
	check(ref.n > 240 * 4, `the referee stepped from the log ({ref.n} ticks in 6 s)`)
	check(#hands[ann].refused == 0, `no segment was refused ({hands[ann].refused[1]})`)
	check(seat ~= nil and seat.replica.desyncs == 0, "the stream replayed to the referee's state every time")
	check(seat ~= nil and seat.resims == 0, "against the computer nothing is ever corrected")
	check(ref.sim.hitSerial > 0, "the puck was played")
	if tbl.hw and home then
		local moved = (tbl.hw.puck:GetPivot().Position - home).Magnitude
		check(moved > 0.01 or ref.sim.countdown > 0, "the server's own puck moves with the match")
		numbers.hardware = 1
	else
		numbers.hardware = 0
	end
	numbers.ticks = ref.n
	numbers.contacts = ref.sim.hitSerial
	local streamed = 0
	for _, e in ann.events do
		if e.kind == "air_hockey" then
			streamed += 1
		end
	end
	numbers.messages = streamed
	check(streamed > 30 and streamed < 100, `the stream is about ten messages a second ({streamed} in 6 s)`)

	-- seven ------------------------------------------------------------------------------------------------------
	ok, why = svc:debug(ID, "score", 6, 2)
	check(ok, `a scripted score: {tostring(why)}`)
	ok, why = svc:debug(ID, "goal", 0)
	check(ok, `a scripted goal: {tostring(why)}`)
	run(1.5)
	check(session.phase == "done", `the seventh goal ends the match (phase {session.phase})`)
	local r = session.result
	check(r ~= nil and r.score[1] == 7 and r.score[2] == 2, "the rules have the referee's score, 7-2")
	check(r ~= nil and r.winner == 1, "Ann's seat won")
	numbers.winner = if r and r.side ~= nil then r.side else -1
	local overs = 0
	for _, e in ann.events do
		if e.kind == "event" and e.over then
			overs += 1
			check(e.text == "Ann wins 7-2", `the end is said in words ("{tostring(e.text)}")`)
		end
	end
	check(overs == 1, `the end of the match is announced once ({overs})`)
	if tbl.hw and tbl.hw.labels[1] then
		check(tbl.hw.labels[1].Text == "GLACIER  7  :  2  EMBER", `the board on the wall ("{tbl.hw.labels[1].Text}")`)
	end
	if tbl.hw and tbl.hw.prints[0] and tbl.hw.prints[1] then
		check(
			tbl.hw.prints[0].Text == "7 : 2" and tbl.hw.prints[1].Text == "2 : 7",
			`each end's score in the bed, its own goals first ("{tbl.hw.prints[0].Text}", "{tbl.hw.prints[1].Text}")`
		)
	end
	check(seat ~= nil and seat.replica.desyncs == 0, "a scripted goal is still the same match on every screen")

	-- again, a second person, and everybody leaving ----------------------------------------------------------------
	ok, why = svc:input(ann, { gameId = ID, seat = 1, verb = "again", args = {} })
	check(ok, `Play again: {tostring(why)}`)
	run(2)
	ref = tbl.ref
	check(session.phase == "playing" and ref ~= nil and ref.sim.score0 == 0, "a new match")
	hand(bob)
	ok, why = svc:join(bob, EMBER)
	check(ok, `Bob takes the computer's end: {tostring(why)}`)
	check(tbl.sideOf[bob] == 1, "the Ember end")
	local before = ref.n
	run(4)
	check(ref.n > before + 240 * 2.5, `two hands, and the match goes on ({ref.n - before} ticks in 4 s)`)
	check(#hands[bob].refused == 0 and #hands[ann].refused == 0, "no segment of either hand was refused")
	check(hands[bob].seat ~= nil and hands[bob].seat.replica.desyncs == 0, "Bob holds the referee's match")
	numbers.cuts = ref.cuts
	svc:leave(bob, "left")
	run(1)
	local computers = 0
	for _, key in svc:_seated(station) do
		if type(key) == "table" and key.ai then
			computers += 1
		end
	end
	check(computers == 1 and session.phase == "playing", "Bob left: the computer has his end and the match goes on")
	svc:leave(ann, "left")
	run(0.5)
	check(session.phase == "idle" and tbl.ref == nil, "Ann left: the table is at rest")
	if tbl.hw and home then
		check((tbl.hw.puck:GetPivot().Position - home).Magnitude < 0.01, "the puck is back on its spot")
	end
	local count = #ann.events + #bob.events
	run(1.5)
	check(#ann.events + #bob.events == count, "nothing more is sent to anyone")
	check(svc:stationOf(ann) == nil and svc:stationOf(bob) == nil, "nobody is still held at the table")

	return { ok = #failures == 0, failures = failures, numbers = numbers }
end

function AirHockeyFlow.run(): { [string]: any }
	local ServerScriptService = game:GetService("ServerScriptService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local server = ServerScriptService:WaitForChild("Server")
	local Game = (require :: any)(server:WaitForChild("Boot"):WaitForChild("Game"))
	local Possession = (require :: any)(server:WaitForChild("Actors"):WaitForChild("Possession"))
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local airHockey = Shared:WaitForChild("Minigames"):WaitForChild("AirHockey")
	local AlleyLayout = (require :: any)(Shared:WaitForChild("Attractions"):WaitForChild("AlleyLayout"))
	local deps: Deps = {
		Seat = (require :: any)(airHockey:WaitForChild("Seat")),
		Sim = (require :: any)(airHockey:WaitForChild("Sim")),
		Layout = (require :: any)(airHockey:WaitForChild("Layout")),
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
	-- two townspeople, one at each end of the table
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
			local X, D = deps.Layout.stance(i - 1)
			local x, y, z = AlleyLayout.toWorld(A.place, X, 3.2, D)
			body:PivotTo(CFrame.new(x, y, z))
		end
		players[i] = p
	end
	local result = AirHockeyFlow.play(A.minigames, deps, {
		players = players,
		-- the logs are judged against the shared clock, which only real time moves: the service is stepped by
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

return AirHockeyFlow
