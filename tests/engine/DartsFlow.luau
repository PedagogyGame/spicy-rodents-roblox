--!strict
-- ServerStorage.EngineTests.DartsFlow (CI place only; injected with --inject ci.project.json or a saved version)
-- The darts flow on a server with no clients, as plain results (brief v2 §13a; BUILD_PLAN §3.16 darts). Three
-- PlayerLike stubs take seats at the dartboard of the real MinigameService and are fed darts; what comes back
-- is what every dart left on the thrower's line and whether each session ended cleanly:
--   nine     the nine-dart leg (seven treble 20s, treble 19, double 12) against a second thrower: 441 381 321
--            261 201 141 81 24 0, the other left on 340; three darts a turn, in turn
--   busts    one thrower down to 141, then every way to go bust (too many, zero without a double, one left)
--            and the double 6 that finishes: 16 darts
--   cricket  marks, closing, the mark over three that scores on what the rival has open, the win: 20 to 0
--   real     real throws through the input path (the server's own seeded scatter): each is scored where it
--            landed
-- The scripted darts go through MinigameService:debugDart (the rules' server verb "land"): the same scoring,
-- board and announcements as a thrown dart, with the landing point chosen. Endings checked: leaving from the
-- end of a game one at a time (the one who stays keeps their own line), the end running out by itself, Play
-- again (the same game), and leaving in the middle. After each, the board is idle with no dart in it, its
-- waiting darts are back, nobody is still held at it and nothing more is sent.
-- Nothing here needs a client: aiming, the meter, the camera and the screen are client code, run under Lune on
-- the fake engine (tests/isolated/darts_client.luau) and checked by eye in a Play session.
-- play() takes any MinigameService, so the Lune suite runs this same flow on the fake engine first: the check
-- is itself checked before a cloud run is spent on it.
-- Interface: run() -> Result (engine only: boots Server/Boot/Game); play(svc, deps, opts) -> Result { ok,
--   failures, numbers, legs }; LEGS (the known legs: darts, what each leaves, the events); point(Darts, label)
--   -> (xmm, ymm) (the middle of "T20", "D12", "5", "BULL", "25", or a "MISS")

local DartsFlow = {}

DartsFlow.LEGS = {
	-- seat 1 throws `darts`, seat 2 `rival`, three each in turn; `left` is seat 1's score after each dart
	nine = {
		darts = { "T20", "T20", "T20", "T20", "T20", "T20", "T20", "T19", "D12" },
		rival = { "20", "1", "5", "T20", "BULL", "25" },
		left = { 441, 381, 321, 261, 201, 141, 81, 24, 0 },
		scores = { 0, 340 },
	},
	-- alone. events: s scored, b bust, c checkout. A bust ends the turn and puts the score back.
	busts = {
		darts = {
			"T20",
			"T20",
			"T20",
			"T20",
			"T20",
			"T20",
			"T20", -- 81
			"T20", -- 21
			"T20", -- too many: back to 141
			"T20",
			"T19", -- 24
			"12", -- 12
			"12", -- zero, but not on a double: back to 12
			"D5", -- 2
			"1", -- one left cannot be finished: back to 12
			"D6",
		},
		left = { 441, 381, 321, 261, 201, 141, 81, 21, 141, 81, 24, 12, 12, 2, 12, 0 },
		events = "ssssssssbsssbsbc",
	},
	-- seat 1 against a rival who misses every dart
	cricket = {
		darts = { "20", "T20", "T19", "T18", "T17", "T16", "T15", "5", "BULL", "25" },
		points = { 0, 20, 20, 20, 20, 20, 20, 20, 20, 20 }, -- seat 1's points after each dart
		scores = { 20, 0 },
	},
}

export type Deps = { Darts: any, Session: any }
export type Opts = {
	players: { any }, -- three PlayerLike stubs { UserId, Name, events } who may play (people, near the board)
	board: string, -- the dartboard's station id
	step: (seconds: number) -> (), -- move the server on
}

-- The middle of a scoring area by its label (board millimetres from the bull).
function DartsFlow.point(Darts: any, label: string): (number, number)
	if label == "MISS" then
		return 250, 250
	elseif label == "BULL" then
		return 0, 0
	elseif label == "25" then
		return 10, 0
	end
	local ring, digits = string.match(label, "^([TD]?)(%d+)$")
	local n = tonumber(digits or "")
	local idx = n and table.find(Darts.ORDER, n)
	if idx == nil then
		error(`DartsFlow.point: "{label}" is not on the board`)
	end
	local r = if ring == "T" then 103 elseif ring == "D" then 166 else 134
	local a = math.rad((idx - 1) * 18)
	return r * math.sin(a), r * math.cos(a)
end

function DartsFlow.play(svc: any, deps: Deps, opts: Opts): { [string]: any }
	local failures: { string } = {}
	local numbers: { [string]: any } = {}
	local legs: { [string]: any } = {}
	local Darts, Session = deps.Darts, deps.Session
	local function check(cond: any, msg: string): boolean
		if not cond then
			table.insert(failures, msg)
		end
		return cond == true or (cond ~= nil and cond ~= false)
	end
	local p1, p2, p3 = opts.players[1], opts.players[2], opts.players[3]
	local id = opts.board
	local st = svc.stations[id]
	local s, hw = st.session, st.hw
	local function input(p: any, verb: string, args: { any }?): (boolean, string?)
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
	local function heard(p: any): number
		local n = 0
		for _, e in p.events do
			if e.station == id then
				n += 1
			end
		end
		return n
	end
	local function inBoard(): number
		return if hw then #hw.darts else 0
	end

	-- one scripted dart for whoever is up: lands where asked, is scored as that, is announced, and is drawn
	local function dart(label: string, want: string, tell: any): any
		local x, y = DartsFlow.point(Darts, want)
		local seat = Session.turn(s)
		local nth = s.game.state.dart
		local ok, why = svc:debugDart(id, x, y)
		if not check(ok, `{label}: a {want} was refused: {tostring(why)}`) then
			return nil
		end
		local hit = s.game.state.lastHit
		check(hit.label == want, `{label}: a dart in the middle of {want} was scored as {tostring(hit.label)}`)
		check(
			hit.seat == seat,
			`{label}: the dart went onto seat {tostring(hit.seat)}'s line, not seat {tostring(seat)}'s`
		)
		local told = last(tell, "dart")
		check(
			told ~= nil and told.label == hit.label and told.seat == seat and type(told.text) == "string",
			`{label}: the {want} was not announced`
		)
		if hw then
			check(inBoard() == nth, `{label}: {inBoard()} darts are in the board after dart {nth} of the turn`)
		end
		opts.step(0.5) -- it flies and lands
		check(hw == nil or not hw:busy(), `{label}: the dart had not landed after half a second`)
		return hit
	end

	-- the board after a session: idle and empty, nobody held at it, and nothing more is sent
	local function endsClean(label: string, who: { any })
		check(s.phase == "idle", `{label}: the session is "{s.phase}", not idle`)
		check(#s.seats == 0 and s.game == nil, `{label}: the session still holds {#s.seats} seats or a game`)
		for _, p in who do
			check(svc:stationOf(p) == nil, `{label}: {p.Name} is still held at {tostring(svc:stationOf(p))}`)
		end
		opts.step(0.5)
		if hw then
			check(not hw:busy(), `{label}: a dart is still in the air`)
			check(inBoard() == 0, `{label}: {inBoard()} thrown darts are still in the board`)
			local idle = hw.model and hw.model:FindFirstChild("IdleDarts")
			if idle then
				for _, p in idle:GetChildren() do
					if p:IsA("BasePart") then
						check(p.Transparency == 0, `{label}: the board's waiting darts are not shown`)
					end
				end
			end
		end
		local before: { number } = {}
		for i, p in who do
			before[i] = heard(p)
		end
		opts.step(3)
		for i, p in who do
			local more = heard(p) - before[i]
			check(more == 0, `{label}: {more} more messages about the board reached {p.Name} afterwards`)
		end
	end

	-- 1. two throwers: the nine-dart leg against a steady scorer -------------------------------------------------
	local nine = DartsFlow.LEGS.nine
	check(svc:join(p1, id), "the first thrower could not join")
	check(svc:join(p2, id), "the second thrower could not join")
	check(s.phase == "lobby", `after two joins the board is "{s.phase}", not in its lobby`)
	check(last(p1, "joined") ~= nil and last(p2, "joined") ~= nil, "a thrower was not told they are seated")
	check(input(p1, "start"), "Start was refused")
	check(s.phase == "playing", `after the start the board is "{s.phase}"`)
	local late, lateWhy = svc:join(p3, id)
	check(not late and lateWhy ~= nil, "a third player joined a game in progress")
	local wrong, wrongWhy = input(p2, "throw", { 0, 0, 0.5 })
	check(not wrong and wrongWhy ~= nil, "the second thrower threw out of turn")
	local from1, from2 = #p1.events, #p2.events
	local got: { [string]: any } = { darts = {}, left = {}, order = {} }
	if s.phase == "playing" then
		opts.step(0.2)
		local at = { 0, 0 }
		local plan = { nine.darts, nine.rival }
		local guard = 0
		while s.phase == "playing" and guard < 40 do
			guard += 1
			local seat = Session.turn(s) :: number
			at[seat] += 1
			local want = plan[seat][at[seat]]
			if not check(want ~= nil, `nine: seat {seat} was asked for dart {at[seat]}, more than its list holds`) then
				break
			end
			local hit = dart("nine", want, p2)
			if hit == nil then
				break
			end
			table.insert(got.order, tostring(seat))
			if seat == 1 then
				local left = s.game.state.players[1].score
				table.insert(got.darts, hit.label)
				table.insert(got.left, left)
				check(
					left == nine.left[at[1]],
					`nine: after dart {at[1]} {nine.left[at[1]]} was expected to be left, and {left} is`
				)
			end
		end
		opts.step(0.5) -- the end of the game is announced on the next step
	end
	numbers.turnOrder = table.concat(got.order)
	check(numbers.turnOrder == "111222111222111", `turn order {numbers.turnOrder}: not three darts each in turn`)
	check(s.phase == "done", `after the double the board is "{s.phase}", not showing the end of the game`)
	if s.phase == "done" then
		local r = s.result
		got.scores = { r.scores[1], r.scores[2] }
		got.winner = r.winner
		check(r.scores[1] == nine.scores[1] and r.scores[2] == nine.scores[2], "the result does not carry 0 and 340")
		check(r.winner == 1, "the winner is not the thrower who checked out")
		check(s.game.state.lastHit.event == "checkout", "the last dart was not called a checkout")
		check(overs(p1, from1) == 1 and overs(p2, from2) == 1, "the end of the game was not announced exactly once")
		local over = nil
		for i = #p2.events, 1, -1 do
			local e = p2.events[i]
			if e.kind == "event" and e.over == true then
				over = e
				break
			end
		end
		numbers.endLine = over and over.text
		check(over ~= nil and over.text == `{p1.Name} wins!`, `the end was announced as "{tostring(numbers.endLine)}"`)
		local final = last(p2, "state")
		check(final ~= nil and final.view.phase == "done", "the last state sent is not the end of the game")
		opts.step(4)
		check(inBoard() == 0, `{inBoard()} darts are still in the board four seconds after the end`)
		-- the winner leaves first: the one who stays still reads their own line
		check(input(p1, "leave"), "Leave at the end was refused")
		opts.step(1.2)
		check(last(p1, "left") ~= nil and svc:stationOf(p1) == nil, "the leaver was not let go")
		local stay = last(p2, "state")
		check(
			stay ~= nil
				and stay.you == 2
				and stay.view.game.seats[2].score == nine.scores[2]
				and stay.view.seats[2].name == p2.Name,
			"after the winner left, the other thrower's line is no longer their own"
		)
		check(input(p2, "leave"), "the second Leave was refused")
	else
		svc:leave(p1, "left")
		svc:leave(p2, "left")
	end
	legs.nine = got
	endsClean("two throwers", { p1, p2 })

	-- 2. every way to go bust, then the end left to run out -----------------------------------------------------
	local busts = DartsFlow.LEGS.busts
	check(svc:join(p3, id), "the third thrower could not join the emptied board")
	check(input(p3, "start"), "the third thrower's start was refused")
	local from3 = #p3.events
	got = { darts = {}, left = {}, events = "" }
	opts.step(0.2)
	for i, want in busts.darts do
		if s.phase ~= "playing" then
			check(false, `busts: the game ended before dart {i}`)
			break
		end
		local hit = dart("busts", want, p3)
		if hit == nil then
			break
		end
		local left = s.game.state.players[1].score
		table.insert(got.darts, hit.label)
		table.insert(got.left, left)
		got.events ..= string.sub(hit.event, 1, 1)
		check(
			left == busts.left[i],
			`busts: after dart {i} ({want}) {busts.left[i]} was expected to be left, and {left} is`
		)
	end
	check(got.events == busts.events, `busts: the darts were called {got.events}, expected {busts.events}`)
	opts.step(0.5)
	legs.busts = got
	check(s.phase == "done", `the busts leg ended "{s.phase}"`)
	if s.phase == "done" then
		got.history = table.clone(s.game.state.players[1].history)
		check(overs(p3, from3) == 1, "the busts leg's end was not announced exactly once")
		local wait = (s.opts.doneSeconds or Session.DEFAULTS.doneSeconds) :: number
		opts.step(wait + 2)
		local left = last(p3, "left")
		check(left ~= nil and left.why == "finished", "the end ran out without telling the thrower")
	else
		svc:leave(p3, "left")
	end
	endsClean("the end ran out", { p3 })

	-- 3. cricket, Play again, and leaving in the middle ------------------------------------------------------------
	local cricket = DartsFlow.LEGS.cricket
	check(svc:join(p1, id), "the first thrower could not join for cricket")
	check(svc:join(p2, id), "the second thrower could not join for cricket")
	check(input(p2, "mode", { "cricket" }), "picking Cricket in the lobby was refused")
	check(input(p1, "start"), "the cricket start was refused")
	check(s.phase == "playing" and s.game.state.mode == "cricket", "the game that started is not cricket")
	got = { darts = {}, points = {} }
	if s.phase == "playing" then
		opts.step(0.2)
		local at = 0
		local guard = 0
		while s.phase == "playing" and guard < 40 do
			guard += 1
			if Session.turn(s) == 1 then
				at += 1
				local want = cricket.darts[at]
				if not check(want ~= nil, `cricket: dart {at} was asked for, more than the list holds`) then
					break
				end
				local hit = dart("cricket", want, p2)
				if hit == nil then
					break
				end
				local points = s.game.state.players[1].score
				table.insert(got.darts, hit.label)
				table.insert(got.points, points)
				check(
					points == cricket.points[at],
					`cricket: after dart {at} ({want}) {cricket.points[at]} points were expected, and there are {points}`
				)
			elseif dart("cricket", "MISS", p1) == nil then
				break
			end
		end
		opts.step(0.5)
	end
	legs.cricket = got
	check(s.phase == "done", `the cricket game ended "{s.phase}"`)
	if s.phase == "done" then
		local r = s.result
		got.scores = { r.scores[1], r.scores[2] }
		got.winner = r.winner
		got.marks = {}
		for _, n in Darts.CRICKET do
			local m = s.game.state.players[1].marks[n]
			got.marks[tostring(n)] = m
			check(m >= 3, `cricket: {n} is not closed ({m} marks)`)
		end
		check(
			r.winner == 1 and r.scores[1] == cricket.scores[1] and r.scores[2] == cricket.scores[2],
			"cricket: not 20 to 0"
		)
		check(s.game.state.lastHit.event == "win", "cricket: the last dart was not called the win")
		-- Play again: the same two, the same game, clean lines
		check(input(p2, "again"), "Play again was refused")
		-- (the phase is read afresh: the input above changed it)
		local now: string = svc:sessionOf(id).phase
		check(now == "playing" and s.game.state.mode == "cricket", "Play again did not start another game of cricket")
		check(#s.seats == 2 and s.game.state.players[1].marks[20] == 0, "Play again did not start clean lines")
		opts.step(0.2)
		dart("again", "T20", p2)
	end
	-- seat 1 leaves in the middle of their turn with a dart in the board: it is seat 2's throw, on a clean board
	check(input(p1, "leave"), "leaving in the middle of a game was refused")
	opts.step(0.3)
	if s.phase == "playing" then
		check(Session.turnKey(s) == p2, "after the thrower left it is not the other player's turn")
		check(inBoard() == 0, `the leaver's dart is still in the board ({inBoard()})`)
	end
	check(input(p2, "leave"), "the last player could not leave")
	endsClean("left mid-game", { p1, p2 })

	-- 4. real throws through the input path ---------------------------------------------------------------------
	check(svc:join(p1, id), "the first thrower could not join for the real throws")
	check(input(p1, "start"), "the start for the real throws was refused")
	got = { darts = 0, labels = {}, left = {} }
	opts.step(0.2)
	local tx, ty = DartsFlow.point(Darts, "T20")
	local total = 0
	for i = 1, 3 do
		if s.phase ~= "playing" then
			break
		end
		local ok, why = input(p1, "throw", { tx, ty, 0.5 })
		if not check(ok, `real throw {i} was refused: {tostring(why)}`) then
			break
		end
		local told = last(p1, "dart")
		if
			check(
				told ~= nil and type(told.x) == "number" and type(told.y) == "number",
				`real throw {i} was not announced`
			)
		then
			local hit = Darts.scoreAt(told.x, told.y)
			check(
				told.label == Darts.label(hit),
				`real throw {i} landed on {Darts.label(hit)} and was called {told.label}`
			)
			check(told.points == hit.points, `real throw {i} was given {told.points} points for {Darts.label(hit)}`)
			local off = math.sqrt((told.x - tx) ^ 2 + (told.y - ty) ^ 2)
			check(off < 40, `real throw {i}, let go in the green, landed {off} mm from its aim`)
			total += hit.points
			got.darts += 1
			table.insert(got.labels, told.label)
			table.insert(got.left, s.game.state.players[1].score)
		end
		local busy, busyWhy = input(p1, "throw", { tx, ty, 0.5 })
		check(not busy and busyWhy ~= nil, "a second dart was thrown while the first was in the air")
		opts.step(0.5)
	end
	if s.phase == "playing" then
		check(s.game.state.players[1].score == 501 - total, "the three real darts do not add up on the thrower's line")
	end
	legs.real = got
	check(input(p1, "leave"), "leaving after the real throws was refused")
	endsClean("real throws", { p1 })

	numbers.gameSeconds = svc.clock
	return { ok = #failures == 0, failures = failures, numbers = numbers, legs = legs }
end

-- run: boot the whole game with no players (frames stepped by hand), stand three stubs as townspeople behind the
-- oche and play the flow at the dartboard.
function DartsFlow.run(): { [string]: any }
	local ServerScriptService = game:GetService("ServerScriptService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local server = ServerScriptService:WaitForChild("Server")
	local Game = (require :: any)(server:WaitForChild("Boot"):WaitForChild("Game"))
	local Possession = (require :: any)(server:WaitForChild("Actors"):WaitForChild("Possession"))
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local minigames = Shared:WaitForChild("Minigames")
	local AlleyLayout = (require :: any)(Shared:WaitForChild("Attractions"):WaitForChild("AlleyLayout"))
	local deps: Deps = {
		Darts = (require :: any)(minigames:WaitForChild("MinigameRules"):WaitForChild("Darts")),
		Session = (require :: any)(minigames:WaitForChild("Session")),
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
			legs = {},
		}
	end
	-- three townspeople standing behind the oche (the service takes anyone who wanders 70 studs off)
	local b = AlleyLayout.board()
	local players: { any } = {}
	local setup: { string } = {}
	for i, name in { "Ann", "Bob", "Cat" } do
		local p = { UserId = 5300 + i, Name = name, Character = nil, attrs = {}, events = {} }
		G.stateOf(p).lastPick = -math.huge
		local ok, why = G.pick(p, "townsperson")
		if not ok then
			table.insert(setup, `{name} could not pick a townsperson: {tostring(why)}`)
		end
		local actor = G.runtime.possession:actorOf(p)
		local body = actor and actor.body
		if body then
			local x, y, z = AlleyLayout.toWorld(A.place, b.ocheX - 1 - i, 3.2, b.d + (i - 2) * 2)
			body:PivotTo(CFrame.new(x, y, z))
		end
		players[i] = p
	end
	local result = DartsFlow.play(A.minigames, deps, {
		players = players,
		board = "darts_1",
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

return DartsFlow
