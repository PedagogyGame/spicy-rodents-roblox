--!strict
-- ServerStorage.EngineTests.Minigames (CI place only; injected with --inject ci.project.json or a saved version)
-- The bowling alley and the minigame framework in the real engine (brief v2 §13a; BUILD_PLAN D28): Server/Boot/Game
-- boots the whole game with Workspace.Attractions (build/Attractions.rbxm) and PlayerLike stubs. Luau Execution has
-- no Heartbeat and no players, so frames are stepped by hand. Bowling needs no physics (the server decides every
-- throw with the pure models in Shared/Minigames/Bowling), so REAL throws run here through the input path; a
-- lane's pinfall is also scripted with MinigameService:debugRoll where a known score is wanted (the same scoring,
-- pinsetter and ball-return path), and darts with debugDart (the rules' server verb "land"). Checks: the alley is
-- there with its stations, prompts, pins, balls, doors and the carved tunnels; the six tunnel routes are in the
-- Routes registry and the vent's foot stands on the alley paving; two players bowl a full game in turn (a perfect
-- 300 against 9-0 frames = 90; turn order by frame; the overhead monitor shows 300); a third player is turned
-- away mid-game, an animal is turned away, a player who walks off mid-game has the rest of their frames played
-- out; real throws: a pocket ball knocks down seven or more and the pins left on the deck are the count, a
-- gutter ball scores nothing and is called one, the throw's script reaches the bowler, the ball runs home through
-- the return duct, a thrower who leaves mid-roll is never scored against the next bowler, a squirrel on the lane
-- is knocked into the gutter and told so while the throw counts, and a computer opponent finishes a game with a
-- real score; darts: three darts a turn, the turn passes,
-- a checkout on a double wins 501, cricket mode from the lobby; the fortune machine pulls a card with no money;
-- pool and pinball say "soon".
-- Interface: run(opts?) -> Result (JSON-friendly)

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local server = ServerScriptService:WaitForChild("Server")
local Game = (require :: any)(server:WaitForChild("Boot"):WaitForChild("Game"))
local Possession = (require :: any)(server:WaitForChild("Actors"):WaitForChild("Possession"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AlleyLayout = (require :: any)(Shared:WaitForChild("Attractions"):WaitForChild("AlleyLayout"))
local Bowling = (require :: any)(Shared:WaitForChild("Minigames"):WaitForChild("MinigameRules"):WaitForChild("Bowling"))

local Minigames = {}

function Minigames.run(_opts: { [string]: any }?): { [string]: any }
	local failures: { string } = {}
	local numbers: { [string]: any } = {}
	local function check(cond: any, msg: string)
		if not cond then
			table.insert(failures, msg)
		end
	end
	local engine = Possession.engine()
	engine.streamAround = function() end
	engine.setOwner = function(_root: any, _player: any?) end
	engine.setCharacter = function(player: any, model: any?)
		player.Character = model
	end

	local t0 = os.clock()
	local G = Game.start({ players = false, engine = engine, heartbeat = false })
	numbers.bootSeconds = os.clock() - t0
	local A = G.attractions
	check(A ~= nil, "Game.attractions missing (Workspace.Attractions not in the place?)")
	if A == nil then
		return { ok = false, failures = failures, numbers = numbers }
	end
	local svc = A.minigames
	local place = A.place

	-- the alley -----------------------------------------------------------------------------------------------
	local alley = workspace:FindFirstChild("Attractions") and workspace.Attractions:FindFirstChild("BowlingAlley")
	check(alley ~= nil, "Workspace.Attractions.BowlingAlley missing")
	local parts = 0
	if alley then
		for _, d in alley:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
	end
	numbers.alleyParts = parts
	check(parts > 1500, `alley has {parts} parts`)
	numbers.carved = A.carved
	check((A.carved or 0) >= 3, `terrain carves {A.carved}`)
	local stationCount = 0
	for _ in svc.stations do
		stationCount += 1
	end
	numbers.stations = stationCount
	check(stationCount == 14, `stations {stationCount} (6 lanes, darts, fortune, 2 pool, bumper pool, 3 pinball)`)
	local prompts = alley and alley:FindFirstChild("MinigamePrompts")
	local promptCount = 0
	if prompts then
		for _, p in prompts:GetChildren() do
			if p:FindFirstChildOfClass("ProximityPrompt") then
				promptCount += 1
			end
		end
	end
	check(promptCount == 14, `{promptCount} minigame prompts`)
	for lane = 1, 6 do
		local lm = alley and alley.Lanes:FindFirstChild(`Lane{lane}`)
		local pins = lm and lm:FindFirstChild("Pins")
		check(pins and #pins:GetChildren() == 10, `lane {lane}: 10 pins`)
		check(lm and lm:FindFirstChild("Ball"), `lane {lane}: ball`)
		local sb = alley and alley.Scoreboards:FindFirstChild(`Lane{lane}`)
		check(sb and sb:FindFirstChild("Screen") and sb.Screen:FindFirstChild("Score"), `lane {lane}: scoreboard gui`)
	end
	local doors = alley and alley:FindFirstChild("Doors")
	local doorPrompts = 0
	if doors then
		for _, d in doors:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				doorPrompts += 1
			end
		end
	end
	check(doorPrompts == 2, `{doorPrompts} push-bar door prompts`)
	-- the tunnels: routes in the registry; the vent's foot stands on the alley paving; the duct is air
	local data = (require :: any)(Shared:WaitForChild("Data")).default()
	local reg = data:routes()
	for id = 9001, 9006 do
		check(reg:get(id) ~= nil, `route {id} missing from the registry`)
	end
	local vent = reg:get(9003)
	if vent then
		local foot = reg:foot(vent)
		local hit = workspace:Raycast(Vector3.new(foot.x, foot.y + 2, foot.z), Vector3.new(0, -4, 0))
		numbers.ventFootHit = if hit then hit.Instance:GetFullName() else "nothing"
		check(hit and hit.Instance:IsDescendantOf(alley :: Instance), "the vent's foot is not on the alley paving")
		if hit then
			check(math.abs(hit.Position.Y - foot.y) < 0.15, `vent foot {foot.y} vs paving {hit.Position.Y}`)
		end
	end
	-- along the lanes 3-4 duct at squirrel height: no terrain (the boot terrain was carved out of it)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local x0, y0, z0 = AlleyLayout.toWorld(place, 0, -1.7, 2)
	local x1, y1, z1 = AlleyLayout.toWorld(place, 0, -1.7, 78)
	local through = workspace:Raycast(Vector3.new(x0, y0, z0), Vector3.new(x1 - x0, y1 - y0, z1 - z0), params)
	numbers.tunnelTerrainHit = if through then tostring(through.Position) else "clear"
	check(through == nil, `terrain inside the lanes 3-4 tunnel at {numbers.tunnelTerrainHit}`)

	-- players ---------------------------------------------------------------------------------------------------
	local function stub(id: number, name: string): { [string]: any }
		return { UserId = id, Name = name, Character = nil, attrs = {}, events = {} }
	end
	local p1, p2, p3, sq = stub(5101, "Ann"), stub(5102, "Bob"), stub(5103, "Cat"), stub(5104, "Nut")
	for _, p in { p1, p2, p3 } do
		G.stateOf(p).lastPick = -math.huge
		local ok, why = G.pick(p, "townsperson")
		check(ok, `pick townsperson: {why}`)
	end
	G.stateOf(sq).lastPick = -math.huge
	G.pick(sq, "squirrel")
	-- stand them at the alley (the service takes players who wander 70 studs off the table)
	local function standAt(p: any, X: number, D: number)
		local actor = G.runtime.possession:actorOf(p)
		local body = actor and actor.body
		if body then
			local x, y, z = AlleyLayout.toWorld(place, X, 3.2, D)
			body:PivotTo(CFrame.new(x, y, z))
		end
	end
	standAt(p1, AlleyLayout.laneX(3), -9)
	standAt(p2, AlleyLayout.laneX(3) + 2, -12)
	standAt(p3, AlleyLayout.laneX(3) - 2, -12)
	local function step(seconds: number)
		local n = math.ceil(seconds / 0.1)
		for _ = 1, n do
			A.step(0.1)
		end
	end
	local function lastEvent(p: any, kind: string): any
		for i = #p.events, 1, -1 do
			if p.events[i].kind == kind then
				return p.events[i]
			end
		end
		return nil
	end
	local function input(p: any, id: string, verb: string, args: { any }?): (boolean, string?)
		return svc:input(p, { gameId = id, seat = 1, verb = verb, args = args or {} })
	end

	-- animals and soon-games are turned away
	local ok, why = svc:join(sq, "bowling_lane_3")
	check(not ok and why and string.find(why, "people", 1, true), `squirrel joined a lane: {why}`)
	ok, why = svc:join(p1, "pool_1")
	check(not ok and why and string.find(why, "next build", 1, true), `pool said: {why}`)
	ok, why = svc:join(p1, "pinball_2")
	check(not ok and why and string.find(why, "out of order", 1, true), `pinball said: {why}`)

	-- bowling: two players, a full game ---------------------------------------------------------------------------
	local LANE = "bowling_lane_3"
	check(svc:join(p1, LANE), "p1 join lane 3")
	check(svc:join(p2, LANE), "p2 join lane 3")
	check(lastEvent(p1, "joined") ~= nil, "p1 got joined")
	local s = svc:sessionOf(LANE)
	check(s.phase == "lobby", `phase {s.phase} after joins (lobby)`)
	check(input(p1, LANE, "start"), "start")
	check(s.phase == "playing", `phase {s.phase} after start`)
	ok, why = svc:join(p3, LANE)
	check(not ok and why and string.find(why, "in progress", 1, true), `late joiner: {why}`)
	-- p1 strikes every ball, p2 bowls 9 then 0 every frame
	local order: { string } = {}
	local balls = 0
	local guard = 0
	while s.phase == "playing" and guard < 2000 do
		guard += 1
		step(0.2)
		local lane = svc.stations[LANE].hw
		if s.phase == "playing" and lane:ready() then
			local key = s.seats[(s.game :: any).rules.turn((s.game :: any).state)]
			local st = (s.game :: any).state
			local pins = if key == p1 then 10 elseif st.ballOf[2] == 1 then 9 else 0
			local good, err = svc:debugRoll(LANE, pins)
			check(good, `debugRoll: {err}`)
			table.insert(order, if key == p1 then "A" else "B")
			balls += 1
			step(0.2)
		end
	end
	numbers.balls = balls
	numbers.turnOrder = table.concat(order)
	check(s.phase == "done", `bowling phase {s.phase} after {balls} balls`)
	check(balls == 12 + 20, `{balls} balls (12 strikes + 20 for 9-0 frames)`)
	check(string.sub(numbers.turnOrder, 1, 7) == "ABBABBA", `turn order {numbers.turnOrder}`)
	local result = s.result
	check(
		result and result.scores[1] == 300 and result.scores[2] == 90,
		`scores {result and result.scores[1]} / {result and result.scores[2]}`
	)
	check(result and result.winner == 1, "winner seat 1")
	-- the monitor shows the total, and the player saw the strike banner
	local screen = alley.Scoreboards.Lane3.Screen.Score
	local seen300 = false
	for _, d in screen:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == "300" then
			seen300 = true
		end
	end
	check(seen300, "lane 3 monitor shows 300")
	local sawStrike = false
	for _, e in p1.events do
		if e.kind == "event" and e.text == "STRIKE!" then
			sawStrike = true
		end
	end
	check(sawStrike, "p1 saw STRIKE!")
	local lastState = lastEvent(p2, "state")
	check(lastState and lastState.view.phase == "done", "p2 got the final state")
	-- the ball came home to the rack and all ten pins stand for the next game
	local laneHw = svc.stations[LANE].hw
	step(5)
	local rx, ry, rd = AlleyLayout.rackSlot(3)
	local wx, wy, wz = AlleyLayout.toWorld(place, rx, ry, rd)
	numbers.ballHome = (laneHw.ball.Position - Vector3.new(wx, wy, wz)).Magnitude
	check(numbers.ballHome < 0.5, `ball {numbers.ballHome} studs from its rack slot`)
	-- play again, then p2 walks off mid-game: their frames are played out and p1 finishes alone
	check(input(p1, LANE, "again"), "play again")
	check(s.phase == "playing", "again -> playing")
	step(1)
	svc:debugRoll(LANE, 10)
	step(5)
	svc:leave(p2, "walked off")
	check(lastEvent(p2, "left") ~= nil, "p2 told they left")
	guard = 0
	while s.phase == "playing" and guard < 1500 do
		guard += 1
		step(0.2)
		if s.phase == "playing" and laneHw:ready() then
			svc:debugRoll(LANE, 4)
			step(0.2)
		end
	end
	check(s.phase == "done", `second game phase {s.phase}`)
	local r2 = s.result
	check(r2 and r2.scores[2] == 0, `walked-off player's score {r2 and r2.scores[2]}`)
	check(
		r2 and r2.scores[1] == Bowling.total({ 10, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4 }),
		`p1 second game {r2 and r2.scores[1]}`
	)
	svc:leave(p1, "done")
	step(1)
	check(s.phase == "idle", `lane idle after everyone left ({s.phase})`)

	-- real throws through the input path (the server decides each one; nothing here is physics) --------------------
	standAt(p1, AlleyLayout.laneX(3), -9)
	standAt(p2, AlleyLayout.laneX(3) + 2, -12)
	local POCKET = { 0.165, 0, 0.7, 0 } -- offset, angle, power, spin: a quarter stud right of the head pin
	local function untilReady(limit: number)
		local waited = 0
		while not laneHw:ready() and waited < limit do
			step(0.1)
			waited += 0.1
		end
	end
	local function visiblePins(): number
		local n = 0
		for _, pm in alley.Lanes.Lane3.Pins:GetChildren() do
			local body = pm:FindFirstChild("Body")
			if body and body.Transparency < 1 then
				n += 1
			end
		end
		return n
	end
	check(svc:join(p1, LANE), "p1 joins for real throws")
	check(svc:join(p2, LANE), "p2 joins for real throws")
	check(input(p1, LANE, "start"), "start (real throws)")
	step(0.3)
	-- a squirrel (a player's) sits right in the ball's way on lane 3
	do
		local actor = G.runtime.possession:actorOf(sq)
		local body = actor and actor.body
		if body then
			local x, y, z = AlleyLayout.toWorld(place, AlleyLayout.laneX(3) + 0.3, 0.6, 30)
			body:PivotTo(CFrame.new(x, y, z))
		end
	end
	ok, why = input(p1, LANE, "release", POCKET)
	check(ok, `pocket release: {why}`)
	local sent = lastEvent(p1, "roll")
	check(sent ~= nil and type(sent.script) == "table" and sent.seat == 1, "the thrower was sent the throw's script")
	check(lastEvent(p2, "roll") ~= nil, "the other bowler was sent it too")
	ok, why = input(p1, LANE, "release", POCKET)
	check(not ok and why and string.find(why, "pinsetter", 1, true), `a second release mid-roll said: {why}`)
	-- mid-roll the ball is out on the lane
	step(1.0)
	do
		local bp = laneHw.ball.Position
		local _, _, D = AlleyLayout.toLocal(place, bp.X, bp.Y, bp.Z)
		numbers.ballMidRollD = D
		check(D > 8 and D < 56, `one second into a throw the ball is {D} studs down the lane`)
	end
	untilReady(15)
	local realState = (s.game :: any).state
	local first = realState.rolls[1][1]
	numbers.pocketBall = first
	check(first ~= nil and first >= 7, `a pocket ball knocked down {first}`)
	if first ~= nil and first < 10 then
		check(laneHw:standingCount() == 10 - first, `{laneHw:standingCount()} pins stand after {first} fell`)
		check(visiblePins() == 10 - first, `{visiblePins()} pins are on the deck after {first} fell`)
	end
	local banner = nil
	for i = #p1.events, 1, -1 do
		local e = p1.events[i]
		if e.kind == "event" and e.pins ~= nil then
			banner = e
			break
		end
	end
	check(banner and banner.pins == first and type(banner.text) == "string", "the throw's banner carries its count")
	-- the ball ran home through the duct to the rack
	numbers.ballHomeAfterThrow = (laneHw.ball.Position - Vector3.new(wx, wy, wz)).Magnitude
	check(
		numbers.ballHomeAfterThrow < 0.5,
		`after a real throw the ball is {numbers.ballHomeAfterThrow} from its rack slot`
	)
	-- the squirrel was bowled into the gutter and told; the bowlers were told; the throw counted
	do
		local actor = G.runtime.possession:actorOf(sq)
		local root = actor and actor.body and actor.body.PrimaryPart
		if root then
			local X, _, D = AlleyLayout.toLocal(place, root.Position.X, root.Position.Y, root.Position.Z)
			numbers.squirrelAfter = `{X - AlleyLayout.laneX(3)}, {D}`
			check(
				math.abs(math.abs(X - AlleyLayout.laneX(3)) - 2.45) < 0.2,
				`the squirrel is {X - AlleyLayout.laneX(3)} across the lane`
			)
			check(D < 30, `the squirrel was knocked back to {D}`)
		end
		local told = false
		for _, e in sq.events do
			if e.kind == "notice" and string.find(tostring(e.text), "bowling ball", 1, true) then
				told = true
			end
		end
		check(told, "the squirrel's player was told what hit it")
		local bowlersTold = false
		for _, e in p1.events do
			if e.kind == "event" and e.intruder and string.find(tostring(e.text), "The throw counts", 1, true) then
				bowlersTold = true
			end
		end
		check(bowlersTold, "the bowlers were told the squirrel was knocked clear and the throw counts")
	end
	-- a gutter ball (or, after a strike, Bob's): nothing falls, and it is called a gutter ball
	local thrower = if (s.game :: any).rules.turn(realState) == 1 then p1 else p2
	local throwerSeat = if thrower == p1 then 1 else 2
	local before = #realState.rolls[throwerSeat]
	ok, why = input(thrower, LANE, "release", { 1, 0.1, 0.7, 0 })
	check(ok, `gutter release: {why}`)
	untilReady(15)
	check(
		realState.rolls[throwerSeat][before + 1] == 0,
		`a gutter ball scored {realState.rolls[throwerSeat][before + 1]}`
	)
	local sawGutter = false
	for _, e in thrower.events do
		if e.kind == "event" and e.text == "Gutter ball" then
			sawGutter = true
		end
	end
	check(sawGutter, "the gutter ball was called a gutter ball")
	-- whoever is up lets go and walks off while the ball rolls: nothing lands on the other bowler's sheet
	local up = (s.game :: any).rules.turn(realState)
	local leaver, stayer = if up == 1 then p1 else p2, if up == 1 then p2 else p1
	local stayerSeat = if up == 1 then 2 else 1
	local stayerBalls = #realState.rolls[stayerSeat]
	if not laneHw:ready() then
		untilReady(15)
	end
	ok, why = input(leaver, LANE, "release", POCKET)
	check(ok, `release before walking off: {why}`)
	step(0.5)
	svc:leave(leaver, "walked off")
	untilReady(15)
	check(
		#realState.rolls[stayerSeat] == stayerBalls,
		"the ball of a bowler who left was not scored against the next one"
	)
	check(laneHw:standingCount() == 10, `the next bowler has {laneHw:standingCount()} pins`)
	svc:leave(stayer, "done")
	step(1)
	check(s.phase == "idle", `lane idle after the real throws ({s.phase})`)

	-- a computer fills the second seat: it takes its own turns with real throws of its own skill
	standAt(p1, AlleyLayout.laneX(3), -9)
	check(svc:join(p1, LANE), "p1 joins for the computer game")
	ok, why = input(p1, LANE, "addai")
	check(ok, `add a computer: {why}`)
	check(#s.seats == 2 and type(s.seats[2]) == "table" and s.seats[2].ai, "computer seated")
	check(input(p1, LANE, "start"), "start vs computer")
	guard = 0
	while s.phase == "playing" and guard < 3000 do
		guard += 1
		step(0.2)
		local seat = (s.game :: any).rules.turn((s.game :: any).state)
		if s.phase == "playing" and seat == 1 and laneHw:ready() then
			svc:debugRoll(LANE, 10)
			step(0.2)
		end
	end
	check(s.phase == "done", `vs computer phase {s.phase}`)
	check(s.result and s.result.scores[1] == 300, `vs computer: human {s.result and s.result.scores[1]}`)
	check(#(s.game :: any).state.rolls[2] >= 11, "the computer bowled its frames")
	numbers.computerRolls = #(s.game :: any).state.rolls[2]
	numbers.computerScore = s.result and s.result.scores[2]
	check(
		s.result and s.result.scores[2] > 20 and s.result.scores[2] < 300,
		`the computer scored {numbers.computerScore}`
	)
	svc:leave(p1, "done")
	step(1)
	check(s.phase == "idle", `lane idle after the human left the computer ({s.phase})`)

	-- darts --------------------------------------------------------------------------------------------------------
	local DARTS = "darts_1"
	local b = AlleyLayout.board()
	standAt(p1, b.ocheX - 1, b.d)
	standAt(p2, b.ocheX - 3, b.d + 2)
	check(svc:join(p1, DARTS), "p1 join darts")
	check(svc:join(p2, DARTS), "p2 join darts")
	local ds = svc:sessionOf(DARTS)
	check(input(p1, DARTS, "start"), "darts start")
	local g = ds.game.state
	-- p1: T20, T20, T20 -> 321 and the turn passes; the board shows three darts
	local function at(n: number, r: number): (number, number)
		local Darts = (require :: any)(Shared.Minigames.MinigameRules.Darts)
		local idx = table.find(Darts.ORDER, n) :: number
		local a = math.rad((idx - 1) * 18)
		return r * math.sin(a), r * math.cos(a)
	end
	local tx, ty = at(20, 103)
	for _ = 1, 3 do
		check(svc:debugDart(DARTS, tx, ty), "debugDart")
		step(0.5)
	end
	check(g.players[1].score == 321, `p1 after 180: {g.players[1].score}`)
	check(g.seat == 2, `darts turn {g.seat} after three darts`)
	local thrown = alley.GamesRoom.Dartboard:FindFirstChild("ThrownDarts")
	numbers.dartsOnBoard = thrown and #thrown:GetChildren() or 0
	-- p2 throws a real (resolved) dart through the input path
	ok, why = input(p2, DARTS, "throw", { 0, 0, 0.5 })
	check(ok, `p2 throw: {why}`)
	check(lastEvent(p2, "dart") ~= nil, "p2 got the dart event")
	ok = input(p1, DARTS, "throw", { 0, 0, 0.5 })
	check(not ok, "p1 threw out of turn")
	step(1)
	svc:debugDart(DARTS, 999, 999)
	svc:debugDart(DARTS, 999, 999)
	step(2)
	-- p1 checks out: 321 -> leave 40 by hand, then D20
	g.players[1].score = 40
	g.players[1].turnStart = 40
	local dx, dy = at(20, 166)
	check(svc:debugDart(DARTS, dx, dy), "checkout dart")
	step(0.5)
	check(ds.phase == "done", `darts phase {ds.phase} after the checkout`)
	check(ds.result and ds.result.winner == 1, "darts winner seat 1")
	local chalk = alley.GamesRoom.Dartboard.ScoreBoard.Score
	local wins = false
	for _, d in chalk:GetDescendants() do
		if d:IsA("TextLabel") and string.find(d.Text, "wins", 1, true) then
			wins = true
		end
	end
	check(wins, "the chalkboard says who won")
	-- cricket from the lobby
	svc:leave(p1, "x")
	svc:leave(p2, "x")
	step(1)
	check(svc:join(p1, DARTS), "p1 rejoin darts")
	check(input(p1, DARTS, "mode", { "cricket" }), "mode cricket")
	check(input(p1, DARTS, "start"), "cricket start")
	check(ds.game.state.mode == "cricket", `mode {ds.game.state.mode}`)
	svc:leave(p1, "x")

	-- the fortune teller ----------------------------------------------------------------------------------------
	local f = AlleyLayout.FORTUNE
	standAt(p3, f.x - 3, f.d - 3)
	check(svc:join(p3, "fortune_1"), "fortune pull")
	local card = lastEvent(p3, "fortune")
	check(card and type(card.line) == "string" and #card.line > 0, "fortune card line")
	check(card and card.reels and #card.reels == 3, "three reels")
	local fs = svc:sessionOf("fortune_1")
	check(fs.result and fs.result.cents == 0, "no money from the fortune machine")
	step(3)
	local reel = alley.GamesRoom.Fortune:FindFirstChild("Reel1")
	local label = reel and reel.Face:FindFirstChildOfClass("TextLabel")
	numbers.reel1 = label and label.Text
	check(label and label.Text ~= "?", "reel 1 stopped on a symbol")
	step(10)
	check(lastEvent(p3, "left") ~= nil, "fortune session released the player")

	numbers.events = #p1.events + #p2.events + #p3.events
	G.stop()
	return { ok = #failures == 0, failures = failures, numbers = numbers }
end

return Minigames
