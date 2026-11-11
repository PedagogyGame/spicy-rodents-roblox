--!strict
-- Minigames/Labyrinth: the owner's fixed controls (LAB-C1..C5), the input log, the rules of a run (LAB-R1..R4)
-- as the Minigame.Rules module the server drives, and the clipboard of best times. Line by line against the
-- checklist.
local Boards = require("@shared/Minigames/Labyrinth/Boards")
local Clipboard = require("@shared/Minigames/Labyrinth/Clipboard")
local Controls = require("@shared/Minigames/Labyrinth/Controls")
local InputLog = require("@shared/Minigames/Labyrinth/InputLog")
local InputMap = require("@client/Input/InputMap")
local Minigame = require("@shared/Minigames/Minigame")
local Physics = require("@shared/Minigames/Labyrinth/Physics")
local Pilot = require("@shared/Minigames/Labyrinth/Pilot")
local Rules = require("@shared/Minigames/Labyrinth/Rules")
local Run = require("@shared/Minigames/Labyrinth/Run")

local NEUTRAL = Controls.NEUTRAL
local RIGHT, LEFT = Controls.code(1, 0), Controls.code(-1, 0)
local FORWARD, BACK = Controls.code(0, 1), Controls.code(0, -1)

local function repeated(code: number, n: number): { number }
	return table.create(n, code)
end

-- send a whole log to the rules the way a client would: in pieces, each naming its first tick
local function send(state: Rules.State, codes: { number }, every: number?): (boolean, string?)
	for _, piece in InputLog.segments(codes, every) do
		if Rules.result(state) ~= nil then
			break
		end
		local ok, why = Rules.input(state, 1, "tilt", { "seg", piece.start, piece.data })
		if not ok then
			return false, why
		end
	end
	return true
end

return function(t)
	t.test("LAB-C1: the owner's keys, exactly: W forward, S back, Up arrow RIGHT, Down arrow LEFT", function()
		local keys = Controls.KEYS
		local count = 0
		for _ in keys do
			count += 1
		end
		t.eq(count, 4, "four keys tilt the board and no others")
		t.deepEq(keys.W, { axis = "forward", sign = 1 })
		t.deepEq(keys.S, { axis = "forward", sign = -1 })
		t.deepEq(keys.Up, { axis = "right", sign = 1 }, "the Up arrow is RIGHT")
		t.deepEq(keys.Down, { axis = "right", sign = -1 }, "the Down arrow is LEFT")
		-- the same map the input layer records as fixed
		t.eq(InputMap.LABYRINTH.forward, "W")
		t.eq(InputMap.LABYRINTH.back, "S")
		t.eq(InputMap.LABYRINTH.right, "Up")
		t.eq(InputMap.LABYRINTH.left, "Down")
		for action, key in InputMap.LABYRINTH :: { [string]: string } do
			local binding = keys[key]
			t.truthy(binding ~= nil, `{key} is bound`)
			local means = if binding.axis == "forward"
				then (if binding.sign > 0 then "forward" else "back")
				else (if binding.sign > 0 then "right" else "left")
			t.eq(means, action, `{key} tilts {action}`)
		end
		t.fails(function()
			(Controls.KEYS :: any).A = { axis = "right", sign = -1 }
		end)
		t.eq(Controls.fromKeys({ W = true }), FORWARD)
		t.eq(Controls.fromKeys({ S = true }), BACK)
		t.eq(Controls.fromKeys({ Up = true }), RIGHT)
		t.eq(Controls.fromKeys({ Down = true }), LEFT)
		t.eq(Controls.fromKeys({ W = true, Up = true }), Controls.code(1, 1), "one hand on each knob")
		t.eq(Controls.fromKeys({ W = true, S = true }), NEUTRAL, "opposite keys cancel")
		t.eq(Controls.fromKeys({ Up = true, Down = true, S = true }), BACK)
		t.eq(Controls.fromKeys({}), NEUTRAL)
		t.eq(Controls.fromKeys({ W = false, Up = false }), NEUTRAL)
	end)

	t.test("LAB-C1: nothing else tilts: A, D, Left and Right do nothing at all", function()
		t.deepEq(Controls.DEAD_KEYS, { "A", "D", "Left", "Right" })
		for _, key in Controls.DEAD_KEYS do
			t.eq(Controls.KEYS[key], nil)
			t.eq(Controls.fromKeys({ [key] = true }), NEUTRAL, `{key} alone is no input`)
			t.eq(Controls.fromKeys({ [key] = true, W = true }), FORWARD, `{key} does not change another key`)
		end
		t.eq(Controls.fromKeys({ A = true, D = true, Left = true, Right = true, Space = true, E = true }), NEUTRAL)
		-- and with no input the run does not even start
		local board = Boards.ALL[1]
		local s = Run.new(board)
		for _ = 1, 120 do
			Run.step(board, s, Controls.fromKeys({ A = true, Right = true }))
		end
		t.eq(s.phase, Run.PHASE.READY)
		t.eq(s.m.x, board.start.x)
	end)

	t.test("LAB-C1 / C3: each key rolls the marble the way it says (forward is away from the seat)", function()
		local board = Boards.ALL[1]
		local cx, cy = Boards.cellCentre(board, board.cols + 5) -- an open stretch of the near lane
		for _, case in
			{
				{ key = "W", dx = 0, dy = 1 },
				{ key = "S", dx = 0, dy = -1 },
				{ key = "Up", dx = 1, dy = 0 },
				{ key = "Down", dx = -1, dy = 0 },
			}
		do
			local m = Physics.new(cx + board.pitch / 2, cy - board.pitch / 2)
			local right, forward = Controls.axes(Controls.fromKeys({ [case.key] = true }))
			for _ = 1, 20 do
				Physics.step(board, m, right, forward, Physics.HOLD_STAY)
			end
			local dx, dy = m.x - (cx + board.pitch / 2), m.y - (cy - board.pitch / 2)
			t.truthy(dx * case.dx + dy * case.dy > 0.02, `{case.key} rolls the marble its way`)
			t.near(dx * case.dy - dy * case.dx, 0, 1e-12, `{case.key} rolls it no other way`)
		end
	end)

	t.test("LAB-C2: the help card says exactly what the owner wrote", function()
		t.eq(Controls.HELP_LINE, "W tilt forward. S tilt back. Up arrow tilt right. Down arrow tilt left.")
		t.eq(
			table.concat({ Controls.HELP[1], Controls.HELP[2], Controls.HELP[3], Controls.HELP[4] }, " "),
			Controls.HELP_LINE
		)
		t.eq(Controls.HELP[5], "Q leaves. H hides this card.")
		t.eq(Controls.QUIT_KEY, "Q")
		t.eq(Controls.HIDE_KEY, "H")
	end)

	t.test("LAB-C4: two knobs, one per hand: the left turns with W/S, the right with Up/Down", function()
		local left, right = Controls.knobs(0, 3)
		t.truthy(left > 0, "forward tilt turns the left-hand knob")
		t.eq(right, 0)
		left, right = Controls.knobs(-2, 0)
		t.eq(left, 0)
		t.truthy(right < 0, "left tilt turns the right-hand knob back")
		left = Controls.knobs(0, Physics.TILT_MAX)
		t.truthy(left >= 90 and left <= 180, "full tilt is a plain turn of the knob, well short of a full circle")
	end)

	t.test("LAB-C5: gamepad sticks and touch sliders are the same two knobs", function()
		t.eq(Controls.fromGamepad({ leftY = 1 }), FORWARD, "left stick up is W")
		t.eq(Controls.fromGamepad({ leftY = -1 }), BACK)
		t.eq(Controls.fromGamepad({ rightY = 1 }), RIGHT, "right stick UP is RIGHT")
		t.eq(Controls.fromGamepad({ rightY = -1 }), LEFT, "right stick down is left")
		t.eq(Controls.fromGamepad({ leftY = 0.2, rightY = -0.2 }), NEUTRAL, "inside the dead zone")
		t.eq(Controls.fromGamepad({ dpadUp = true }), FORWARD, "the D-pad mirrors the left stick")
		t.eq(Controls.fromGamepad({ dpadDown = true }), BACK)
		t.eq(Controls.fromGamepad({ y = true }), RIGHT, "Y and A mirror the right stick")
		t.eq(Controls.fromGamepad({ a = true }), LEFT)
		t.eq(Controls.fromGamepad({ leftY = 1, y = true }), Controls.code(1, 1))
		t.eq(Controls.fromGamepad({}), NEUTRAL)
		t.eq(Controls.fromTouch(1, 0), FORWARD, "left thumb up is forward")
		t.eq(Controls.fromTouch(-1, 0), BACK)
		t.eq(Controls.fromTouch(0, 1), RIGHT, "right thumb UP is RIGHT")
		t.eq(Controls.fromTouch(0, -1), LEFT)
		t.eq(Controls.fromTouch(0, 0), NEUTRAL)
		for code = 0, 8 do
			t.eq(Controls.code(Controls.axes(code)), code, "codes and axes go both ways")
			t.truthy(Controls.valid(code))
		end
		t.falsy(Controls.valid(9))
		t.falsy(Controls.valid(1.5))
		t.falsy(Controls.valid("4"))
	end)

	t.test("the input log: runs of held keys, written and read back exactly; junk is not a log", function()
		local codes = { 4, 4, 4, 7, 7, 1, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 8 }
		local text = InputLog.encode(codes)
		t.eq(text, "e3h2b1e10i1")
		t.deepEq(InputLog.decode(text), codes)
		t.eq(InputLog.ticks(text), #codes)
		t.eq(InputLog.encode(codes, 4, 6), "h2b1")
		t.eq(InputLog.encode({}), "")
		for _, junk in { "", "e", "3", "e0", "e-1", "j3", "E3", "e3 ", "e3,h2", "e03", "e1.5", "e9999999" } do
			t.eq(InputLog.decode(junk), nil, `"{junk}" is not a log`)
		end
		t.eq(InputLog.decode(42 :: any), nil)
		t.eq(InputLog.decode(nil :: any), nil)
		t.eq(InputLog.decode("e121"), nil, "longer than a piece may be")
		t.truthy(InputLog.decode("e120") ~= nil)
		t.truthy(InputLog.decode("e500", 600) ~= nil, "a whole log is read with its own limit")
	end)

	t.test("the input log goes out in pieces that join end to end, however wild the keys", function()
		local long: { number } = {}
		for i = 1, 1000 do
			long[i] = (i * 7 + i // 13) % 9 -- a different key every tick: the worst case
		end
		for i = 1001, 1400 do
			long[i] = NEUTRAL
		end
		for _, every in { 12, 30, 120 } do
			local pieces = InputLog.segments(long, every)
			local joined: { number } = {}
			for _, piece in pieces do
				t.eq(piece.start, #joined, "each piece starts where the last ended")
				t.truthy(#piece.data <= InputLog.SEGMENT_CHARS, "a piece fits a wire string")
				local codes = InputLog.decode(piece.data)
				t.truthy(codes ~= nil, "a piece is a log")
				t.truthy(#(codes :: { number }) <= InputLog.SEGMENT_TICKS)
				for _, c in codes :: { number } do
					table.insert(joined, c)
				end
			end
			t.deepEq(joined, long)
		end
		-- the client's writer: ticks before the first key are not part of the run
		local w = InputLog.writer()
		for _ = 1, 50 do
			InputLog.push(w, NEUTRAL)
		end
		t.eq((InputLog.take(w)), nil, "nothing to send before the first key")
		local sent: { number } = {}
		for i, code in long do
			InputLog.push(w, code)
			if i % 12 == 0 or i == #long then
				while true do
					local start, data = InputLog.take(w)
					if start == nil then
						break
					end
					t.eq(start, #sent)
					for _, c in InputLog.decode(data) :: { number } do
						table.insert(sent, c)
					end
				end
			end
		end
		t.deepEq(sent, long)
	end)

	t.test("C14: the rules module satisfies the Minigame contract: one seat, no stakes, no money", function()
		t.truthy(Minigame.check(Rules))
		t.eq(Rules.def.game, "tilt_labyrinth")
		t.eq(Rules.def.seats, 1)
		t.eq(Rules.def.class, "no_stakes")
		t.eq(Rules.def.money, "none")
		t.eq(Rules.def.authority, "client_sim_server_replay")
		t.truthy(Rules.verbs.tilt and Rules.verbs.mode)
		t.truthy(Rules.serverVerbs.clock, "the clock is the server's own verb")
		t.truthy(#Rules.NEEDS >= 4, "what the framework must offer is written down")
		local game = Minigame.start(Rules, 1, 1)
		t.eq(Minigame.result(game), nil)
		t.eq(Rules.turn(game.state), 1, "the one player is always the one to play")
		local ok, why = Minigame.input(game, 2, "tilt", { "seg", 0, "h10" })
		t.falsy(ok)
		t.eq(why, "seat")
		ok = Rules.input(game.state, 2, "tilt", { "seg", 0, "h10" })
		t.falsy(ok, "one player at a time")
		t.falsy((Minigame.input(game, 1, "release", {})), "not a verb of this game")
		t.falsy((Rules.input(game.state, 1, "tilt", { "spin" })))
		t.falsy((Rules.input(game.state, 1, "tilt", nil)))
	end)

	t.test("LAB-R4: the clock starts on the first key press, not before", function()
		local state = Rules.init(1, 1)
		local view = Rules.view(state)
		t.eq(view.phase, "ready")
		t.eq(view.clock, "0:00.0")
		t.truthy(string.find(view.line, "start the clock", 1, true) ~= nil, "the status line says what to press")
		-- ticks with no key held do nothing at all
		t.truthy(Rules.input(state, 1, "tilt", { "seg", 0, InputLog.encode(repeated(NEUTRAL, 100)) }))
		t.eq(state.run.tick, 0, "no key, no clock")
		t.eq(state.run.phase, Run.PHASE.READY)
		t.eq(state.run.m.x, Rules.boardOf(state).start.x)
		-- the first key starts it; from then on every tick counts, key or no key
		t.truthy(Rules.input(state, 1, "tilt", { "seg", 0, "h1e59" }))
		t.eq(state.run.tick, 60)
		t.eq(state.run.phase, Run.PHASE.ROLLING)
		t.eq(Rules.view(state).clock, "0:01.0")
		t.eq(Rules.result(state), nil, "a run in progress has no result")
	end)

	t.test("LAB-R1 / R3: a run from START to FINISH: the result is the time and the marbles dropped", function()
		for level, board in Boards.ALL do
			local run, codes = Pilot.play(board, Pilot.STEADY, 1)
			t.eq(run.phase, Run.PHASE.FINISHED)
			local state = Rules.init(1, 1)
			t.truthy(Rules.input(state, 1, "mode", { level }))
			t.truthy(send(state, codes))
			local result = Rules.result(state) :: { [string]: any }
			t.truthy(result ~= nil, `{board.id}: the server's replica finished from the log alone`)
			t.eq(result.done, true)
			t.eq(result.finished, true)
			t.eq(result.why, "finished")
			t.eq(result.winner, 1)
			t.eq(result.tenths, Run.tenths(run), "the same time the player's machine had")
			t.eq(result.tenths, math.floor(#codes / 6 + 0.5), "the time is the length of the log")
			t.eq(result.scores[1], result.tenths)
			t.eq(result.seconds, result.tenths / 10)
			t.eq(result.drops, 0)
			t.eq(result.reached, #board.holes, "every number passed")
			t.eq(result.of, #board.holes)
			t.eq(result.board, board.id)
			t.eq(result.fair, true)
			t.eq(Rules.turn(state), nil, "nobody's turn once it is over")
			t.eq(Run.bytes(state.run), Run.bytes(run), "the replica is the player's run, bit for bit")
			local view = Rules.view(state)
			t.eq(view.phase, "finished")
			t.truthy(string.find(view.line, "Home in " .. Rules.clockText(result.tenths), 1, true) ~= nil, view.line)
			-- nothing more is accepted
			local ok, why = Rules.input(state, 1, "tilt", { "seg", state.run.tick, "e10" })
			t.falsy(ok)
			t.eq(why, "this run is over: play again")
		end
	end)

	t.test("LAB-R2: a marble down a hole comes back on the last checkpoint passed; the clock keeps running", function()
		-- the simplest drop: from the first board's start, tip right and the marble runs into hole 1
		local board = Boards.ALL[1]
		local s = Run.new(board)
		local fellAt = 0
		for _ = 1, 200 do
			Run.step(board, s, RIGHT)
			if bit32.band(s.ev, Run.EV.FELL) ~= 0 then
				fellAt = s.tick
				break
			end
		end
		t.truthy(fellAt > 0, "it ran into the first hole")
		t.eq(s.drops, 1)
		t.eq(s.hole, 1)
		t.eq(s.reached, 1, "a marble down hole 1 reached 1")
		t.eq(s.phase, Run.PHASE.RETURNING)
		t.eq(s.m.on, 0)
		for i = 1, Run.RETURN_TICKS do
			t.eq(s.phase, Run.PHASE.RETURNING, "still rolling home")
			Run.step(board, s, NEUTRAL)
			t.eq(s.tick, fellAt + i, "the clock keeps running while it is away")
		end
		t.eq(s.phase, Run.PHASE.ROLLING, "there is no game over: it is back")
		t.truthy(bit32.band(s.ev, Run.EV.RETURNED) ~= 0)
		t.eq(s.m.on, 1)
		t.eq(s.m.x, board.checkpoints[1].x, "on the start, the last checkpoint it had passed")
		t.eq(s.m.y, board.checkpoints[1].y)
		t.eq(s.m.vx, 0, "set down at rest")
		t.eq(s.m.vy, 0)
		t.eq(s.reached, 1, "its number is not taken away")

		-- and through a whole clumsy run on the spiral: every return is to the checkpoint of the furthest point
		-- reached, and later drops come back to later checkpoints
		local spiral = Boards.ALL[2]
		local run = Run.new(spiral)
		local pilot = Pilot.new(spiral, 1, 3)
		local returns, furthest = 0, 1
		while not Run.over(run) do
			Run.step(spiral, run, Pilot.code(spiral, pilot, run))
			t.eq(run.checkpoint, spiral.checkpointAt[run.progress], "the checkpoint is the last one passed")
			if bit32.band(run.ev, Run.EV.RETURNED) ~= 0 then
				returns += 1
				local cp = spiral.checkpoints[run.checkpoint]
				t.eq(run.m.x, cp.x)
				t.eq(run.m.y, cp.y)
				furthest = math.max(furthest, run.checkpoint)
			end
		end
		t.eq(returns, run.drops, "every marble dropped came back")
		t.truthy(returns >= 3, "the clumsy pilot dropped a few")
		t.truthy(furthest >= 3, "and came back to checkpoints further along, not to the start")
	end)

	t.test("LAB-R3: four minutes and the run is called: the result is the highest number reached", function()
		local state = Rules.init(1, 1)
		t.truthy(Rules.input(state, 1, "mode", { "check_up" }))
		-- rock the board for four minutes without getting anywhere much
		local codes: { number } = {}
		for i = 1, Run.MAX_TICKS + 500 do
			codes[i] = if (i // 45) % 2 == 0 then RIGHT else LEFT
		end
		t.truthy(send(state, codes, 120))
		local result = Rules.result(state) :: { [string]: any }
		t.truthy(result ~= nil, "the run ended by itself")
		t.eq(state.run.tick, Run.MAX_TICKS, "at four minutes to the tick")
		t.eq(result.finished, false)
		t.eq(result.why, "timeout")
		t.eq(result.winner, nil)
		t.eq(result.tenths, 2400)
		t.eq(Rules.clockText(result.tenths), "4:00.0")
		t.eq(result.reached, state.run.reached)
		t.truthy(result.reached >= 1 and result.reached < result.of, "it got somewhere, not everywhere")
		t.truthy(string.find(Rules.line(state), "Four minutes are up", 1, true) ~= nil)
	end)

	t.test("LAB-R3: a run that is abandoned (Q, a walk-away, a bite, an idle clock) keeps its number", function()
		local board = Boards.ALL[2]
		local _, codes = Pilot.play(board, Pilot.STEADY, 1)
		for _, how in { "giveup", "skipTurn" } do
			local state = Rules.init(1, 1)
			t.truthy(Rules.input(state, 1, "mode", { 2 }))
			t.truthy(send(state, table.move(codes, 1, 600, 1, {})))
			local reached = state.run.reached
			t.truthy(reached >= 3, "ten seconds in it has passed some holes")
			if how == "giveup" then
				t.truthy(Rules.input(state, 1, "tilt", { "giveup" }))
			else
				Rules.skipTurn(state)
			end
			local result = Rules.result(state) :: { [string]: any }
			t.eq(result.why, "abandoned")
			t.eq(result.finished, false)
			t.eq(result.reached, reached, "the highest number reached")
			t.eq(result.winner, nil)
			t.eq(Rules.turn(state), nil)
			t.falsy((Rules.input(state, 1, "tilt", { "seg", 600, "e10" })), "nothing after the end")
		end
		-- abandoned before the first key: a result all the same, with nothing reached
		local idle = Rules.init(1, 1)
		Rules.skipTurn(idle)
		local result = Rules.result(idle) :: { [string]: any }
		t.eq(result.reached, 0)
		t.eq(result.tenths, 0)
	end)

	t.test("mode: the board and the knobs' hold are chosen before the first key, never after", function()
		local state = Rules.init(1, 1)
		t.eq(Rules.view(state).board, Boards.ALL[1].id, "the first board unless told otherwise")
		t.eq(Rules.view(state).hold, "stay", "knobs stay where they are left unless told otherwise")
		t.truthy(Rules.input(state, 1, "mode", { 3 }))
		t.eq(Rules.view(state).board, Boards.ALL[3].id)
		t.eq(Rules.view(state).of, #Boards.ALL[3].holes)
		t.truthy(Rules.input(state, 1, "mode", { "the_specialist", "level" }))
		t.eq(Rules.view(state).level, 4)
		t.eq(Rules.view(state).hold, "level")
		t.eq(state.run.hold, Physics.HOLD_LEVEL)
		t.truthy(Rules.input(state, 1, "mode", { 2 }), "the hold is kept when only the board changes")
		t.eq(Rules.view(state).hold, "level")
		for _, bad in { { 0 }, { 5 }, { "nowhere" }, { 2, "wobbly" }, { 2, 1 }, {}, { true } } do
			t.falsy((Rules.input(state, 1, "mode", bad :: { any })), "a mode that does not exist is refused")
		end
		t.eq(Rules.view(state).level, 2, "and changes nothing")
		t.truthy(Rules.input(state, 1, "tilt", { "seg", 0, "h5" }))
		local ok, why = Rules.input(state, 1, "mode", { 1 })
		t.falsy(ok)
		t.eq(why, "the board cannot be changed once the marble is rolling")
	end)

	t.test("a lost, doubled or broken piece of the log never moves the server's marble", function()
		local state = Rules.init(1, 1)
		t.truthy(Rules.input(state, 1, "tilt", { "seg", 0, "h30" }))
		local bytes = Run.bytes(state.run)
		for _, bad in
			{
				{ "seg", 0, "h30" }, -- the same piece again
				{ "seg", 60, "e30" }, -- a piece was lost
				{ "seg", 30, "h121" }, -- more than a piece may carry
				{ "seg", 30, "x9" },
				{ "seg", 30, "" },
				{ "seg", 30, 17 },
				{ "seg", "30", "e5" },
				{ "seg", 30, string.rep("a1b1", 60) }, -- longer than a wire string
				{ "seg" },
			}
		do
			local ok, why = Rules.input(state, 1, "tilt", bad :: { any })
			t.falsy(ok)
			t.truthy(type(why) == "string")
			t.eq(Run.bytes(state.run), bytes, "nothing moved")
		end
		local _, why = Rules.input(state, 1, "tilt", { "seg", 60, "e30" })
		t.eq(why, "gap: the server is at tick 30", "the refusal says where to send from")
		t.truthy(Rules.input(state, 1, "tilt", { "seg", 30, "e30" }), "sent from the right tick, it goes on")
		t.eq(state.run.tick, 60)
	end)

	t.test(
		"the server's replica is the run of record: a digest that disagrees is flagged, a snapshot mends it",
		function()
			local board = Boards.ALL[1]
			local state = Rules.init(1, 1)
			local mine = Run.new(board)
			for _ = 1, 40 do
				Run.step(board, mine, Controls.code(1, 1))
			end
			t.truthy(Rules.input(state, 1, "tilt", { "seg", 0, "i40", Run.digest(mine) }))
			t.eq(Rules.view(state).diverged, false, "the same model, the same digest")
			t.eq(Rules.view(state).digest, Run.digest(mine))
			-- a client whose marble has gone its own way (a machine that rounds differently, or a cheat)
			mine.m.x += 0.01
			for _ = 1, 20 do
				Run.step(board, mine, NEUTRAL)
			end
			t.truthy(Rules.input(state, 1, "tilt", { "seg", 40, "e20", Run.digest(mine) }), "the piece still counts")
			t.eq(Rules.view(state).diverged, true, "but the server says the client has drifted")
			local mended = Run.restore(Rules.snapshot(state)) :: Run.State
			t.eq(Run.bytes(mended), Run.bytes(state.run), "the server's state, sent as numbers, is the state")
			t.truthy(
				Rules.input(state, 1, "tilt", { "seg", 60, "e1", Run.digest(Run.replay(board, 0, repeated(8, 40))) })
			)
			t.eq(Run.restore({ 1, 2, 3 }), nil, "a snapshot that is not one is refused")
			local wrong = Rules.snapshot(state)
			wrong[1] = 99
			t.eq(Run.restore(wrong), nil, "so is one for a board that does not exist")
		end
	)

	t.test("a run is played in real time: one that does not keep pace with the server's clock is not fair", function()
		local board = Boards.ALL[1]
		local _, codes = Pilot.play(board, Pilot.STEADY, 1)
		local function play(secondsPerPiece: number): { [string]: any }
			local state = Rules.init(1, 1)
			local now = 100
			for _, piece in InputLog.segments(codes, 60) do
				t.truthy(Rules.input(state, 1, "clock", { now }))
				t.truthy(Rules.input(state, 1, "tilt", { "seg", piece.start, piece.data }))
				now += secondsPerPiece
			end
			return Rules.result(state) :: { [string]: any }
		end
		t.eq(play(1).fair, true, "a second of log each second")
		t.eq(play(1.05).fair, true, "a little lag is only lag")
		local slow = play(3)
		t.eq(slow.fair, false, "a log that takes three seconds to play each second was not played live")
		t.eq(slow.finished, true, "it is still the player's run")
		t.eq(play(0.2).fair, false, "nor was one that arrives five times faster than time")
		t.falsy((Rules.input(Rules.init(1, 1), 1, "clock", { "noon" })))
		-- without a clock (tests, a framework that has none yet) nothing is called unfair
		local state = Rules.init(1, 1)
		t.truthy(send(state, codes))
		t.eq((Rules.result(state) :: { [string]: any }).fair, true)
	end)

	t.test("the clock reads minutes, seconds and tenths", function()
		t.eq(Rules.clockText(0), "0:00.0")
		t.eq(Rules.clockText(7), "0:00.7")
		t.eq(Rules.clockText(345), "0:34.5")
		t.eq(Rules.clockText(600), "1:00.0")
		t.eq(Rules.clockText(1234), "2:03.4")
		local s = Run.new(Boards.ALL[1])
		s.tick = 93
		t.eq(Run.tenths(s), 16, "93 ticks is 1.55 s, shown as 1.6")
		t.near(Run.seconds(s), 1.55, 1e-12)
	end)

	t.test("the clipboard: the five best times today, one line a player, the record keeps its ghost", function()
		local c = Clipboard.new()
		t.eq(Clipboard.PLACES, 5)
		t.deepEq(Clipboard.list(c, "check_up"), {})
		t.eq(Clipboard.lines(c, "check_up", Rules.clockText)[1], "Labyrinth: best times today")
		t.eq(Clipboard.add(c, "check_up", { name = "Ada", tenths = 400, drops = 2, hold = 0, log = "h10" }), 1)
		t.eq(Clipboard.add(c, "check_up", { name = "Ben", tenths = 350, drops = 5, hold = 0, log = "i10" }), 1)
		t.eq(Clipboard.add(c, "check_up", { name = "Cy", tenths = 500, drops = 0 }), 3)
		t.eq(
			Clipboard.add(c, "check_up", { name = "Dee", tenths = 400, drops = 1 }),
			2,
			"equal time: fewer drops first"
		)
		t.eq(
			Clipboard.add(c, "check_up", { name = "Eve", tenths = 400, drops = 2 }),
			4,
			"all equal: the earlier run stays ahead"
		)
		local names = {}
		for i, e in Clipboard.list(c, "check_up") do
			names[i] = e.name
		end
		t.deepEq(names, { "Ben", "Dee", "Ada", "Eve", "Cy" })
		t.eq(Clipboard.add(c, "check_up", { name = "Flo", tenths = 900, drops = 0 }), nil, "sixth is not on the board")
		t.eq(#Clipboard.list(c, "check_up"), 5)
		t.eq(Clipboard.add(c, "check_up", { name = "Cy", tenths = 600, drops = 0 }), nil, "a worse run changes nothing")
		t.eq(Clipboard.add(c, "check_up", { name = "Cy", tenths = 300, drops = 9, hold = 1, log = "b9" }), 1)
		t.eq(#Clipboard.list(c, "check_up"), 5, "one line a player")
		t.deepEq(Clipboard.ghost(c, "check_up"), { hold = 1, log = "b9" }, "the record's log is kept for the ghost")
		t.eq(Clipboard.list(c, "check_up")[2].log, nil, "only the record's")
		t.eq(Clipboard.ghost(c, "first_visit"), nil)
		t.eq(
			Clipboard.add(c, "first_visit", { name = "Cy", tenths = 150, drops = 0 }),
			1,
			"each board has its own list"
		)
		local lines = Clipboard.lines(c, "check_up", Rules.clockText)
		t.eq(lines[2], "1. Cy  0:30.0  (9 drops)")
		t.eq(lines[3], "2. Ben  0:35.0  (5 drops)")
		t.eq(#lines, 6)
		t.eq(Clipboard.lines(c, "first_visit", Rules.clockText)[2], "1. Cy  0:15.0  (clean)")
	end)
end
