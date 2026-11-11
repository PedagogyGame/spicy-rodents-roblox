--!strict
-- Minigames/Labyrinth/Pilot and Stream: every board is proved solvable by a scripted run through the keys alone;
-- computer hands at each skill level play whole runs to the end on several seeds; and what a watcher (or a
-- ghost) draws from the relayed log is, tick for tick, the run the player had.
local Boards = require("@shared/Minigames/Labyrinth/Boards")
local Clipboard = require("@shared/Minigames/Labyrinth/Clipboard")
local Controls = require("@shared/Minigames/Labyrinth/Controls")
local InputLog = require("@shared/Minigames/Labyrinth/InputLog")
local Physics = require("@shared/Minigames/Labyrinth/Physics")
local Pilot = require("@shared/Minigames/Labyrinth/Pilot")
local Rules = require("@shared/Minigames/Labyrinth/Rules")
local Run = require("@shared/Minigames/Labyrinth/Run")
local Stream = require("@shared/Minigames/Labyrinth/Stream")

local STAY, LEVEL = Physics.HOLD_STAY, Physics.HOLD_LEVEL
local TICK = Physics.TICK

-- play a watcher until it has nothing left to play
local function drain(w: Stream.Watch)
	for _ = 1, 100000 do
		Stream.advance(w, TICK)
		if #w.waiting - w.head + 1 <= 0 or Run.over(w.run) then
			return
		end
	end
	error("the watcher never ran dry")
end

return function(t)
	t.test("every board is solvable: a scripted run through the keys reaches the finish, no marble dropped", function()
		for _, board in Boards.ALL do
			for _, hold in { STAY, LEVEL } do
				local run, codes = Pilot.play(board, Pilot.STEADY, 1, hold)
				local how = if hold == STAY then "knobs that stay" else "knobs that level"
				t.eq(run.phase, Run.PHASE.FINISHED, `{board.id}, {how}: the marble reached the cup`)
				t.eq(run.drops, 0, `{board.id}, {how}: without dropping a marble`)
				t.eq(run.reached, #board.holes)
				t.eq(run.progress, #board.pathCells)
				t.truthy(run.tick < 60 * 60, `{board.id}: in under a minute ({run.tick / 60} s)`)
				-- the script is nothing but keys: codes 0..8, starting with a key press
				t.eq(#codes, run.tick, "one code a tick of the clock")
				t.truthy(codes[1] ~= Controls.NEUTRAL, "the log starts with the first key")
				for _, code in codes do
					t.truthy(Controls.valid(code))
				end
				-- and the script alone, written down and read back, is the run
				local text = InputLog.encode(codes)
				local read = InputLog.decode(text, Run.MAX_TICKS) :: { number }
				t.eq(Run.bytes(Run.replay(board, hold, read)), Run.bytes(run), "replayed from its log, the same bytes")
			end
		end
	end)

	t.test(
		"a pilot is deterministic, and its dice are its own: same seed same run, another seed another run",
		function()
			local board = Boards.ALL[2]
			local a, codesA = Pilot.play(board, 2, 11)
			local b, codesB = Pilot.play(board, 2, 11)
			t.eq(Run.bytes(a), Run.bytes(b))
			t.deepEq(codesA, codesB)
			local _, codesC = Pilot.play(board, 2, 12)
			t.neq(InputLog.encode(codesA), InputLog.encode(codesC), "a different seed is a different run")
			-- the steady hand has no dice at all
			local _, s1 = Pilot.play(board, Pilot.STEADY, 1)
			local _, s2 = Pilot.play(board, Pilot.STEADY, 999)
			t.deepEq(s1, s2)
			t.fails(function()
				Pilot.new(board, 9, 1)
			end, "no such pilot level")
		end
	)

	t.test("three skill levels and the steady hand, with names that belong in a waiting room", function()
		t.eq(#Pilot.LEVELS, 4)
		t.eq(Pilot.LEVELS[Pilot.STEADY].id, "steady")
		local seen: { [string]: boolean } = {}
		for _, level in Pilot.LEVELS do
			t.truthy(#level.name > 0 and not seen[level.name], "each has its own name")
			seen[level.name] = true
			t.truthy(level.react < 16, "what it saw fits in its memory")
		end
		t.truthy(Pilot.LEVELS[1].react > Pilot.LEVELS[2].react and Pilot.LEVELS[2].react > Pilot.LEVELS[3].react)
		t.truthy(Pilot.LEVELS[1].judge > Pilot.LEVELS[2].judge and Pilot.LEVELS[2].judge > Pilot.LEVELS[3].judge)
		t.truthy(Pilot.LEVELS[1].slip > Pilot.LEVELS[2].slip and Pilot.LEVELS[2].slip > Pilot.LEVELS[3].slip)
	end)

	t.test("whole runs by every level on several seeds: the first board is finished by all of them", function()
		local board = Boards.ALL[1]
		for level = 1, #Pilot.LEVELS do
			for seed = 1, 5 do
				local run, codes = Pilot.play(board, level, seed)
				t.eq(run.phase, Run.PHASE.FINISHED, `{Pilot.LEVELS[level].name}, seed {seed}`)
				t.eq(#codes, run.tick)
				t.truthy(run.tick > 8 * 60, "nobody does it in under eight seconds")
			end
		end
	end)

	t.test(
		"whole runs to the end through the rules: the best hands finish every board, the rest get a result",
		function()
			for index, board in Boards.ALL do
				for level = 1, 3 do
					for seed = 1, 3 do
						local run, codes = Pilot.play(board, level, seed)
						t.truthy(Run.over(run), "every run ends")
						-- the server's side: the log arrives in pieces and the replica reaches the same end
						local state = Rules.init(1, seed)
						t.truthy(Rules.input(state, 1, "mode", { index }))
						for _, piece in InputLog.segments(codes) do
							local ok, why = Rules.input(state, 1, "tilt", { "seg", piece.start, piece.data })
							t.truthy(ok, why)
						end
						local result = Rules.result(state) :: { [string]: any }
						t.truthy(result ~= nil, `{board.id}, {Pilot.LEVELS[level].name}, seed {seed}: a result`)
						t.eq(result.finished, run.phase == Run.PHASE.FINISHED)
						t.eq(result.tenths, Run.tenths(run))
						t.eq(result.drops, run.drops)
						t.eq(result.reached, run.reached)
						t.truthy(result.reached >= 1 and result.reached <= result.of)
						if result.finished then
							t.eq(result.reached, result.of)
							t.eq(result.why, "finished")
						else
							t.eq(result.why, "timeout", "a run that does not finish ends at four minutes")
							t.eq(run.tick, Run.MAX_TICKS)
						end
						if level == 3 then
							t.truthy(result.finished, `{board.id}: Dr. Maple finishes (seed {seed})`)
						end
					end
				end
			end
		end
	)

	t.test("skill shows: on the spiral the clumsy hand takes longer and drops more than the good one", function()
		local board = Boards.ALL[2]
		local function average(level: number): (number, number)
			local ticks, drops = 0, 0
			for seed = 1, 6 do
				local run = Pilot.play(board, level, seed)
				ticks += run.tick
				drops += run.drops
			end
			return ticks / 6 / 60, drops / 6
		end
		local pipTime, pipDrops = average(1)
		local hazelTime, hazelDrops = average(2)
		local mapleTime, mapleDrops = average(3)
		t.truthy(pipTime > hazelTime and hazelTime > mapleTime, `times {pipTime}, {hazelTime}, {mapleTime}`)
		t.truthy(pipDrops > hazelDrops and hazelDrops >= mapleDrops, `drops {pipDrops}, {hazelDrops}, {mapleDrops}`)
		t.truthy(mapleDrops < 2, "the good hand rarely drops one here")
		t.truthy(pipDrops > 5, "the clumsy one drops plenty")
		t.truthy(mapleTime > 20 and mapleTime < 45, `a good run of the spiral is about half a minute ({mapleTime} s)`)
	end)

	t.test("a pilot levels the board while its marble rolls home", function()
		local board = Boards.ALL[1]
		local run = Run.new(board)
		for _ = 1, 200 do
			Run.step(board, run, Controls.code(1, 0)) -- into the first hole, board hard over
			if run.phase == Run.PHASE.RETURNING then
				break
			end
		end
		t.eq(run.phase, Run.PHASE.RETURNING)
		t.eq(run.m.tx, Physics.TILT_MAX)
		local pilot = Pilot.new(board, Pilot.STEADY, 1)
		for _ = 1, Run.RETURN_TICKS - 1 do
			Run.step(board, run, Pilot.code(board, pilot, run))
		end
		t.eq(run.phase, Run.PHASE.RETURNING)
		t.truthy(math.abs(run.m.tx) < 0.5, `the board is level for the marble's return ({run.m.tx} degrees)`)
	end)

	t.test("LAB-S4: a watcher fed the relayed pieces sees the player's run, tick for tick, a moment behind", function()
		local board = Boards.ALL[3]
		local run, codes = Pilot.play(board, 2, 5)
		local w = Stream.watch(nil, board, STAY) :: Stream.Watch
		t.truthy(w ~= nil)
		t.eq(Stream.boardOf(w), board)
		local pieces = InputLog.segments(codes)
		-- the first piece alone is not enough to start: it waits for its buffer
		t.truthy(Stream.push(w, pieces[1].start, pieces[1].data))
		t.eq(InputLog.SEND_EVERY, Stream.BUFFER, "one piece is exactly the buffer")
		t.truthy(Stream.advance(w, TICK) == 1, "with a buffer's worth it starts")
		-- live: a piece arrives every SEND_EVERY ticks and the watcher plays one tick a frame
		local played = 1
		for i = 2, #pieces do
			for _ = 1, InputLog.SEND_EVERY do
				played += Stream.advance(w, TICK)
			end
			t.truthy(Stream.push(w, pieces[i].start, pieces[i].data))
			t.truthy(w.next - w.run.tick <= 2 * InputLog.SEND_EVERY + Stream.BUFFER, "never far behind")
		end
		drain(w)
		t.eq(Run.bytes(w.run), Run.bytes(run), "the watcher ends on the very same state")
		t.eq(w.run.tick, run.tick)
		-- a doubled or lost piece is refused and changes nothing
		local ok, why = Stream.push(w, 0, pieces[1].data)
		t.falsy(ok)
		t.truthy(string.find(why :: string, "gap", 1, true) ~= nil)
		t.falsy((Stream.push(w, w.next, "zz")))
		t.truthy(played > 0)
	end)

	t.test(
		"a watcher that falls behind hurries, one that is starved waits, a late one starts from a snapshot",
		function()
			local board = Boards.ALL[2]
			local run, codes = Pilot.play(board, Pilot.STEADY, 1)
			local pieces = InputLog.segments(codes, 120)
			-- behind: four seconds arrive at once; it plays two ticks for one until it has caught up
			local w = Stream.watch(nil, board, STAY) :: Stream.Watch
			for i = 1, 2 do
				t.truthy(Stream.push(w, pieces[i].start, pieces[i].data))
			end
			t.eq(Stream.advance(w, TICK), 2, "hurrying")
			local frames = 1
			while w.next - w.run.tick > Stream.HURRY do
				Stream.advance(w, TICK)
				frames += 1
			end
			t.truthy(frames < 240 - Stream.HURRY, "it catches up faster than time")
			t.eq(Stream.advance(w, TICK), 1, "then back to one tick a frame")
			-- starved: it stops, holds its last state, and goes on when more comes
			drain(w)
			local held = Run.bytes(w.run)
			t.eq(Stream.advance(w, 1), 0)
			t.eq(Run.bytes(w.run), held, "nothing arrives, nothing moves")
			t.truthy(Stream.push(w, pieces[3].start, pieces[3].data))
			t.truthy(Stream.advance(w, TICK) >= 1, "more came: on it goes")
			-- a long frame never plays more than a quarter of a second at once
			t.truthy(Stream.advance(w, 5) <= 2 * 15 + 2)

			-- a watcher who walks in mid-run is sent the server's snapshot and the pieces from there
			local state = Rules.init(1, 1)
			t.truthy(Rules.input(state, 1, "mode", { 2 }))
			local late: Stream.Watch? = nil
			for i, piece in pieces do
				t.truthy(Rules.input(state, 1, "tilt", { "seg", piece.start, piece.data }))
				if late ~= nil then
					t.truthy(Stream.push(late, piece.start, piece.data))
				elseif i == 4 then
					late = Stream.watch(Rules.snapshot(state))
					t.truthy(late ~= nil, "a snapshot starts a watcher")
					t.eq((late :: Stream.Watch).next, state.run.tick, "it expects the next piece")
				end
			end
			drain(late :: Stream.Watch)
			t.eq(
				Run.bytes((late :: Stream.Watch).run),
				Run.bytes(run),
				"the late watcher ends where everyone else does"
			)
			t.eq(Stream.watch({ 1, 2, 3 }), nil, "something that is not a snapshot starts nothing")
			t.eq(Stream.watch(nil), nil)
		end
	)

	t.test("the day's record plays back as a ghost from the clipboard's log", function()
		local board = Boards.ALL[1]
		local run, codes = Pilot.play(board, 3, 2)
		local c = Clipboard.new()
		t.eq(
			Clipboard.add(c, board.id, {
				name = "Dr. Maple",
				tenths = Run.tenths(run),
				drops = run.drops,
				hold = STAY,
				log = InputLog.encode(codes),
			}),
			1
		)
		local record = Clipboard.ghost(c, board.id) :: { hold: number, log: string }
		local ghost = Stream.ghost(board, record.hold, record.log) :: Stream.Watch
		t.truthy(ghost ~= nil)
		t.eq(Stream.advance(ghost, TICK), 1, "a ghost starts at once")
		drain(ghost)
		t.eq(ghost.run.phase, Run.PHASE.FINISHED)
		t.eq(ghost.run.tick, run.tick, "the ghost finishes on the record's own tick")
		t.eq(Stream.ghost(board, STAY, "not a log"), nil)
	end)

	t.test("LAB-C4 / S2: the pose is what to draw: marble, tilts, knobs, and the roll home through the box", function()
		local board = Boards.ALL[1]
		local run = Run.new(board)
		local pose = Stream.pose(board, run)
		t.eq(pose.x, board.start.x)
		t.eq(pose.y, board.start.y)
		t.eq(pose.lift, board.marbleR, "on the flat the marble sits on the board")
		t.truthy(pose.shown)
		t.eq(pose.tiltX, 0)
		t.eq(pose.knobLeft, 0)
		t.eq(pose.home, 0)
		-- W: the left-hand knob turns and the board tips forward; the Up arrow: the right-hand knob
		local before = Run.copy(run)
		Run.step(board, run, Controls.fromKeys({ W = true }))
		for _ = 1, 9 do
			before = Run.copy(run)
			Run.step(board, run, Controls.fromKeys({ W = true }))
		end
		pose = Stream.pose(board, run)
		t.truthy(pose.tiltY > 1 and pose.tiltX == 0, "the board visibly tips forward")
		t.truthy(pose.knobLeft > 20 and pose.knobRight == 0, "and the left-hand knob has turned")
		local half = Stream.pose(board, run, before, 0.5)
		t.near(half.tiltY, (before.m.ty + run.m.ty) / 2, 1e-12, "between two ticks the pose is blended")
		t.near(half.y, (before.m.y + run.m.y) / 2, 1e-12)
		Run.step(board, run, Controls.fromKeys({ Up = true }))
		t.truthy(Stream.pose(board, run).knobRight > 0, "the Up arrow turns the right-hand knob")
		-- over a rim the marble sinks; down the hole it is gone and its roll home runs from 0 to 1
		local fresh = Run.new(board)
		Run.step(board, fresh, Controls.code(1, 0)) -- one tap: the clock is running
		local first = board.holes[1]
		Physics.place(fresh.m, first.x - first.r + 0.004, first.y) -- set down a hair over hole 1's rim
		local sank, last = false, 0
		for _ = 1, 400 do
			Run.step(board, fresh, Controls.NEUTRAL)
			pose = Stream.pose(board, fresh)
			if fresh.phase == Run.PHASE.ROLLING and fresh.m.rim > 0 then
				t.truthy(pose.lift < board.marbleR, "it sinks as it tips over the rim")
				sank = true
			elseif fresh.phase == Run.PHASE.RETURNING then
				t.falsy(pose.shown, "down the hole it is not on the board")
				t.truthy(pose.home >= last and pose.home <= 1, "the roll home only goes forward")
				last = pose.home
				t.eq(pose.fromX, board.holes[fresh.hole].x, "from the hole it went down")
				t.eq(pose.toX, board.checkpoints[fresh.checkpoint].x, "to the checkpoint it comes back on")
			elseif fresh.drops > 0 then
				break
			end
		end
		t.truthy(sank)
		t.truthy(last > 0.95, "the roll home ran its length")
		t.truthy(Stream.pose(board, fresh).shown, "and the marble is back")
		t.eq(Stream.pose(board, fresh).home, 0)
	end)

	t.test("LAB-S3: sound cues come from the model: click by how hard, rumble by how fast, plonk, bell", function()
		local board = Boards.ALL[1]
		local run, codes = Pilot.play(board, 1, 4)
		t.truthy(run.drops >= 1, "this clumsy run drops a marble (pick another seed if the tuning changes)")
		local replay = Run.new(board)
		local heard: { [string]: number } = {}
		local loudest, quietest, topRumble = 0, 1, 0
		for _, code in codes do
			Run.step(board, replay, code)
			for _, cue in Stream.cues(board, replay) do
				heard[cue.name] = (heard[cue.name] or 0) + 1
				t.truthy(cue.volume > 0 and cue.volume <= 1)
				if cue.name == Stream.CUES.click then
					loudest = math.max(loudest, cue.volume)
					quietest = math.min(quietest, cue.volume)
				end
			end
			local volume, pitch = Stream.rumble(replay)
			t.truthy(volume >= 0 and volume <= 1 and pitch >= 0.8 and pitch <= 1.4)
			if replay.m.on == 0 then
				t.eq(volume, 0, "a marble that is away does not rumble")
			end
			topRumble = math.max(topRumble, volume)
		end
		t.eq(heard[Stream.CUES.start], 1, "the clock starts once")
		t.eq(heard[Stream.CUES.bell], 1, "the bell rings once, at the finish")
		t.eq(heard[Stream.CUES.plonk], run.drops + 1, "a plonk for every hole, and one into the cup")
		t.eq(heard[Stream.CUES.home], run.drops)
		t.eq(heard[Stream.CUES.back], run.drops)
		t.truthy((heard[Stream.CUES.click] or 0) >= 3, "walls click")
		t.truthy(loudest > quietest, "harder hits click louder")
		t.truthy(topRumble > 0.3, "the rumble grows with speed")
		local numbers = heard[Stream.CUES.number] or 0
		t.truthy(numbers >= #board.holes / 2 and numbers <= #board.holes, "a new number is rung once, never twice")
		-- a still marble is silent
		local still = Run.new(board)
		t.eq((Stream.rumble(still)), 0)
		t.eq(#Stream.cues(board, still), 0)
		-- every cue has a name of its own for MinigameSounds
		local names: { [string]: boolean } = {}
		for _, name in Stream.CUES :: { [string]: string } do
			t.truthy(string.sub(name, 1, 10) == "labyrinth_" and not names[name])
			names[name] = true
		end
	end)
end
