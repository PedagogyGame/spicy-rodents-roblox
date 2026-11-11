--!strict
-- ServerStorage.EngineTests.BowlingFlow (CI place only; injected with --inject ci.project.json or a saved version)
-- The bowling flow on a server with no clients, as plain results (brief v2 §13a; BUILD_PLAN D28). Three
-- PlayerLike stubs take seats at two lanes of the real MinigameService and are fed throws; what comes back is
-- every bowler's sheet (the rolls, the ten running frame scores, the marks, the total) and whether each
-- session ended cleanly:
--   perfect  twelve strikes: every frame scores 30 more, 300 in all
--   mixed    X 7/ 9- X -8 8/ -6 X X X81: strikes, spares, open frames, a miss, three balls in the tenth: 167
--            (both bowled in turn on one lane, so the turn order by frame is checked too)
--   spares   5/ ten times and a 5: the tenth frame's spare earns one more ball: 150
--   real     a whole game of real throws through the input path (the server decides each one with the pure
--            models; no physics): every ball scored is exactly what its script knocked down
-- The scripted pinfalls go through MinigameService:debugRoll: the same scoring, pinsetter and ball-return
-- path as a thrown ball, with the count chosen. Endings checked: leaving from the end card one at a time (the
-- one who stays keeps their own sheet), the end card running out by itself, Play again, and leaving in the
-- middle of a game. After each, the lane is idle and whole (ten pins, the ball on its rack), nobody is still
-- held at it and nothing more is sent.
-- Nothing here needs a client: aiming, the power meter, the camera and the playback are client code, run under
-- Lune on the fake engine (tests/isolated) and checked by eye in a Play session.
-- play() takes any MinigameService, so the Lune suite runs this same flow on the fake engine
-- (tests/isolated/minigames_service.luau): the check is itself checked before a cloud run is spent on it.
-- Interface: run() -> Result (engine only: boots Server/Boot/Game); play(svc, deps, opts) -> Result { ok,
--   failures, numbers, games }; GAMES (the known sequences and their frame scores); POCKET

local BowlingFlow = {}

BowlingFlow.GAMES = {
	perfect = {
		rolls = { 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10 },
		frames = { 30, 60, 90, 120, 150, 180, 210, 240, 270, 300 },
		total = 300,
	},
	mixed = {
		rolls = { 10, 7, 3, 9, 0, 10, 0, 8, 8, 2, 0, 6, 10, 10, 10, 8, 1 },
		frames = { 20, 39, 48, 66, 74, 84, 90, 120, 148, 167 },
		total = 167,
	},
	spares = {
		rolls = { 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5 },
		frames = { 15, 30, 45, 60, 75, 90, 105, 120, 135, 150 },
		total = 150,
	},
}
-- who bowls each ball when seat 1 bowls `perfect` and seat 2 bowls `mixed` on one lane
BowlingFlow.TURN_ORDER = "12122122121221221221212111222"
BowlingFlow.POCKET = { 0.165, 0, 0.7, 0 } -- offset, angle, power, spin: a quarter stud right of the head pin

export type Deps = { Bowling: any, Session: any, Referee: any }
export type Opts = {
	players: { any }, -- three PlayerLike stubs { UserId, Name, events } who may play (people, near the lanes)
	laneA: string, -- station ids of two different lanes
	laneB: string,
	step: (seconds: number) -> (), -- move the server on
}

function BowlingFlow.play(svc: any, deps: Deps, opts: Opts): { [string]: any }
	local failures: { string } = {}
	local numbers: { [string]: any } = {}
	local games: { [string]: any } = {}
	local Bowling, Session, Referee = deps.Bowling, deps.Session, deps.Referee
	local function check(cond: any, msg: string): boolean
		if not cond then
			table.insert(failures, msg)
		end
		return cond == true or (cond ~= nil and cond ~= false)
	end
	local p1, p2, p3 = opts.players[1], opts.players[2], opts.players[3]
	local function input(p: any, id: string, verb: string, args: { any }?): (boolean, string?)
		return svc:input(p, { gameId = id, seat = 1, verb = verb, args = args or {} })
	end
	local function last(p: any, kind: string): any
		for i = #p.events, 1, -1 do
			if p.events[i].kind == kind then
				return p.events[i]
			end
		end
		return nil
	end
	local function overs(p: any, from: number): number
		local n = 0
		for i = from + 1, #p.events do
			local e = p.events[i]
			if e.kind == "event" and e.over == true then
				n += 1
			end
		end
		return n
	end
	local function waitReady(hw: any, limit: number): boolean
		local waited = 0
		while not hw:ready() and waited < limit do
			opts.step(0.1)
			waited += 0.1
		end
		return hw:ready()
	end

	-- one bowler's sheet as the scoreboard has it
	local function sheet(id: string, seat: number): { [string]: any }
		local s = svc:sessionOf(id)
		local view = Session.view(s, svc.clock)
		local g = view.game.seats[seat]
		local marks: { string } = {}
		for f, boxes in g.marks do
			marks[f] = table.concat(boxes, " ")
		end
		return {
			name = view.seats[seat].name,
			rolls = table.clone(s.game.state.rolls[seat]),
			frames = table.clone(g.totals),
			marks = marks,
			total = g.total,
		}
	end
	local function expect(label: string, got: { [string]: any }, want: { [string]: any })
		check(got.total == want.total, `{label}: total {got.total}, expected {want.total}`)
		check(#got.rolls == #want.rolls, `{label}: {#got.rolls} balls on the sheet, expected {#want.rolls}`)
		for f = 1, 10 do
			check(
				got.frames[f] == want.frames[f],
				`{label}: frame {f} shows {tostring(got.frames[f])}, expected {want.frames[f]}`
			)
		end
	end

	-- scripted pinfalls for whoever is up, each bowler from their own list, until the game ends
	local function feed(id: string, plan: { { number } }): string
		local st = svc.stations[id]
		local s, hw = st.session, st.hw
		local at: { [number]: number } = {}
		local order: { string } = {}
		local guard = 0
		while s.phase == "playing" and guard < 100 do
			guard += 1
			if not check(waitReady(hw, 30), `{id}: the lane was not ready within 30 s`) then
				break
			end
			opts.step(0.2)
			local seat = Session.turn(s)
			if s.phase ~= "playing" or seat == nil then
				break
			end
			at[seat] = (at[seat] or 0) + 1
			local pins = plan[seat] and plan[seat][at[seat]]
			if not check(pins ~= nil, `{id}: seat {seat} was asked for ball {at[seat]}, more than its list holds`) then
				break
			end
			local ok, why = svc:debugRoll(id, pins)
			if not check(ok, `{id}: ball {at[seat]} of seat {seat} was refused: {tostring(why)}`) then
				break
			end
			table.insert(order, tostring(seat))
		end
		opts.step(0.5) -- the end of the game is announced on the next step
		return table.concat(order)
	end

	-- the lane after a session: idle and whole, nobody held at it, and nothing more is sent
	local function endsClean(label: string, id: string, who: { any })
		local st = svc.stations[id]
		local s, hw = st.session, st.hw
		check(s.phase == "idle", `{label}: the session is "{s.phase}", not idle`)
		check(#s.seats == 0 and s.game == nil, `{label}: the session still holds {#s.seats} seats or a game`)
		for _, p in who do
			check(svc:stationOf(p) == nil, `{label}: {p.Name} is still held at {tostring(svc:stationOf(p))}`)
		end
		opts.step(0.5)
		check(hw:ready(), `{label}: the lane is not ready for the next game`)
		check(hw:standingCount() == 10, `{label}: {hw:standingCount()} pins stand`)
		local off = (hw.ball.CFrame.Position - hw.rackCF.Position).Magnitude
		check(off < 0.05, `{label}: the ball is {off} studs from its rack`)
		local before: { number } = {}
		for i, p in who do
			before[i] = #p.events
		end
		opts.step(3)
		for i, p in who do
			check(#p.events == before[i], `{label}: {#p.events - before[i]} more messages reached {p.Name} afterwards`)
		end
	end

	-- 1. two bowlers on one lane: twelve strikes against the mixed game ------------------------------------------
	local A = opts.laneA
	local sA = svc:sessionOf(A)
	check(svc:join(p1, A), "the first bowler could not join")
	check(svc:join(p2, A), "the second bowler could not join")
	check(sA.phase == "lobby", `after two joins the lane is "{sA.phase}", not in its lobby`)
	check(last(p1, "joined") ~= nil and last(p2, "joined") ~= nil, "a bowler was not told they are seated")
	check(input(p1, A, "start"), "Start now was refused")
	check(sA.phase == "playing", `after the start the lane is "{sA.phase}"`)
	local late, lateWhy = svc:join(p3, A)
	check(not late and lateWhy ~= nil, "a third player joined a game in progress")
	local from1, from2 = #p1.events, #p2.events
	numbers.turnOrder = feed(A, { BowlingFlow.GAMES.perfect.rolls, BowlingFlow.GAMES.mixed.rolls })
	check(sA.phase == "done", `after the last ball the lane is "{sA.phase}", not at its end card`)
	if sA.phase == "done" then
		games.perfect = sheet(A, 1)
		games.mixed = sheet(A, 2)
		expect("perfect", games.perfect, BowlingFlow.GAMES.perfect)
		expect("mixed", games.mixed, BowlingFlow.GAMES.mixed)
		-- frame by frame: one whole frame each in turn (one ball after a strike, else two), and each bowler's
		-- three balls of the tenth frame together
		check(
			numbers.turnOrder == BowlingFlow.TURN_ORDER,
			`turn order {numbers.turnOrder}, expected {BowlingFlow.TURN_ORDER}`
		)
		local r = sA.result
		check(r ~= nil and r.scores[1] == 300 and r.scores[2] == 167, "the result does not carry 300 and 167")
		check(r ~= nil and r.winner == 1, "the winner is not the first bowler")
		local summary = Referee.summary(Session.view(sA, svc.clock))
		numbers.endLine = summary.line
		check(summary.line == `{games.perfect.name} wins with 300!`, `the end card says "{summary.line}"`)
		check(overs(p1, from1) == 1 and overs(p2, from2) == 1, "the end of the game was not announced exactly once")
		local final = last(p2, "state")
		check(final ~= nil and final.view.phase == "done", "the last state sent is not the end card")
		-- the winner leaves the end card first: the one who stays still reads their own sheet
		check(input(p1, A, "leave"), "Leave on the end card was refused")
		opts.step(1.2)
		check(last(p1, "left") ~= nil and svc:stationOf(p1) == nil, "the leaver was not let go")
		local stay = last(p2, "state")
		check(
			stay ~= nil
				and stay.you == 2
				and stay.view.game.seats[2].total == 167
				and stay.view.seats[2].name == p2.Name,
			"after the winner left, the other bowler's sheet is no longer their own"
		)
		check(input(p2, A, "leave"), "the second Leave was refused")
	else
		svc:leave(p1, "left")
		svc:leave(p2, "left")
	end
	endsClean("two bowlers", A, { p1, p2 })

	-- 2. all spares, then the end card left to run out ------------------------------------------------------------
	check(svc:join(p3, A), "the third bowler could not join the emptied lane")
	check(input(p3, A, "start"), "the third bowler's start was refused")
	local from3 = #p3.events
	feed(A, { BowlingFlow.GAMES.spares.rolls })
	check(sA.phase == "done", `the spares game ended "{sA.phase}"`)
	if sA.phase == "done" then
		games.spares = sheet(A, 1)
		expect("spares", games.spares, BowlingFlow.GAMES.spares)
		check(overs(p3, from3) == 1, "the spares game's end was not announced exactly once")
		local card = (sA.opts.doneSeconds or Session.DEFAULTS.doneSeconds) :: number
		opts.step(card + 2)
		local left = last(p3, "left")
		check(left ~= nil and left.why == "finished", "the end card ran out without telling the bowler")
	else
		svc:leave(p3, "left")
	end
	endsClean("end card ran out", A, { p3 })

	-- 3. a whole game of real throws on another lane --------------------------------------------------------------
	local B = opts.laneB
	local stB = svc.stations[B]
	local sB, hwB = stB.session, stB.hw
	check(svc:join(p1, B), "the first bowler could not join the second lane")
	check(input(p1, B, "start"), "the start on the second lane was refused")
	local fell: { number } = {}
	local guard = 0
	while sB.phase == "playing" and guard < 40 do
		guard += 1
		if not check(waitReady(hwB, 30), "the second lane was not ready within 30 s") then
			break
		end
		opts.step(0.2)
		if sB.phase ~= "playing" then
			break
		end
		local ok, why = input(p1, B, "release", BowlingFlow.POCKET)
		if not check(ok, `a real throw was refused: {tostring(why)}`) then
			break
		end
		local roll = last(p1, "roll")
		check(roll ~= nil and roll.script ~= nil, "the throw's script did not reach the bowler")
		table.insert(fell, if roll and roll.script then roll.script.down else -1)
	end
	opts.step(0.5)
	check(sB.phase == "done", `the game of real throws ended "{sB.phase}"`)
	if sB.phase == "done" then
		games.real = sheet(B, 1)
		local real = games.real
		check(#real.rolls == #fell, `{#fell} balls were thrown and {#real.rolls} are on the sheet`)
		for i, n in fell do
			check(real.rolls[i] == n, `ball {i}: its script knocked down {n}, the sheet says {tostring(real.rolls[i])}`)
		end
		check(real.total == Bowling.total(real.rolls), "the total is not the rules' total of the rolls")
		check(real.frames[10] == real.total, "the tenth frame's running score is not the total")
		check(real.total >= 0 and real.total <= 300, `a total of {real.total}`)
		local over = nil
		for i = #p1.events, 1, -1 do
			local e = p1.events[i]
			if e.kind == "event" and e.over == true then
				over = e
				break
			end
		end
		check(over ~= nil and over.text == `Final score: {real.total}`, "the end banner does not carry the final score")
		-- Play again starts a fresh sheet for whoever stayed; leaving mid-game empties the lane
		check(input(p1, B, "again"), "Play again was refused")
		-- (the phase is read afresh: the input above changed it)
		local now: string = svc:sessionOf(B).phase
		check(now == "playing" and #sB.game.state.rolls[1] == 0, "Play again did not start a fresh sheet")
		if waitReady(hwB, 30) then
			opts.step(0.2)
			check(input(p1, B, "release", BowlingFlow.POCKET), "the first throw of the second game was refused")
			opts.step(1.5) -- the ball is on the lane
		end
	end
	check(input(p1, B, "leave"), "leaving in the middle of a game was refused")
	endsClean("left mid-game", B, { p1 })

	numbers.gameSeconds = svc.clock
	return { ok = #failures == 0, failures = failures, numbers = numbers, games = games }
end

-- run: boot the whole game with no players (frames stepped by hand), seat three stubs as townspeople at the
-- alley and play the flow on lanes 2 and 5.
function BowlingFlow.run(): { [string]: any }
	local ServerScriptService = game:GetService("ServerScriptService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local server = ServerScriptService:WaitForChild("Server")
	local Game = (require :: any)(server:WaitForChild("Boot"):WaitForChild("Game"))
	local Possession = (require :: any)(server:WaitForChild("Actors"):WaitForChild("Possession"))
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local minigames = Shared:WaitForChild("Minigames")
	local AlleyLayout = (require :: any)(Shared:WaitForChild("Attractions"):WaitForChild("AlleyLayout"))
	local deps: Deps = {
		Bowling = (require :: any)(minigames:WaitForChild("MinigameRules"):WaitForChild("Bowling")),
		Session = (require :: any)(minigames:WaitForChild("Session")),
		Referee = (require :: any)(minigames:WaitForChild("Bowling"):WaitForChild("Referee")),
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
			games = {},
		}
	end
	-- three townspeople standing on the approaches (the service takes anyone who wanders 70 studs off)
	local players: { any } = {}
	local setup: { string } = {}
	for i, name in { "Ann", "Bob", "Cat" } do
		local p = { UserId = 5200 + i, Name = name, Character = nil, attrs = {}, events = {} }
		G.stateOf(p).lastPick = -math.huge
		local ok, why = G.pick(p, "townsperson")
		if not ok then
			table.insert(setup, `{name} could not pick a townsperson: {tostring(why)}`)
		end
		local actor = G.runtime.possession:actorOf(p)
		local body = actor and actor.body
		if body then
			local x, y, z = AlleyLayout.toWorld(A.place, AlleyLayout.laneX(3) + (i - 2) * 3, 3.2, -9)
			body:PivotTo(CFrame.new(x, y, z))
		end
		players[i] = p
	end
	local result = BowlingFlow.play(A.minigames, deps, {
		players = players,
		laneA = "bowling_lane_2",
		laneB = "bowling_lane_5",
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

return BowlingFlow
