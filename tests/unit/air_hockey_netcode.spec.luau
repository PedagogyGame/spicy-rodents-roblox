--!strict
-- Air hockey over a network, with no engine (tools/games/air_hockey/Line: the referee, each player's Seat and
-- watchers' Replicas joined by queues that deliver late): what a player is shown against what the referee
-- decided for the same instant.
--   Against the computer the player's own screen IS the match: at 0, 80 and 150 ms each way the puck and both
--   mallets shown are the referee's to the last bit at every frame of whole matches, nothing is ever corrected,
--   and the hand's log is ten messages a second.
--   Against a person the player's own mallet is still exactly their hand, with no delay. What the OTHER hand
--   does cannot be known at once, and it is never guessed on the screen: the far mallet and the puck in the far
--   half are drawn a moment late, from what the referee decided, and the puck in the player's own half is the
--   present puck. The bounds below say how late, and how exactly what is drawn is the referee's match.
-- Also here: the wire format, the referee's refusals, a hand that is late, a seat that changes hands mid-match,
-- a watcher who arrives late.
local Referee = require("@shared/Minigames/AirHockey/Referee")
local Replica = require("@shared/Minigames/AirHockey/Replica")
local Seat = require("@shared/Minigames/AirHockey/Seat")
local Sim = require("@shared/Minigames/AirHockey/Sim")
local Wire = require("@shared/Minigames/AirHockey/Wire")
local Line = require("../../tools/games/air_hockey/Line")

return function(t)
	t.test("wire: a hand is quantised to a quarter of a millimetre, the same on both sides", function()
		for side = 0, 1 do
			local s = if side == 1 then 1 else -1
			for _, p in { { 0, s * 0.8 }, { 0.556, s * 1.106 }, { -0.556, s * 0.064 }, { 0.1234, s * 0.4567 } } do
				local x, y = Wire.snap(side, p[1], p[2])
				t.near(x, p[1], 0.00014)
				t.near(y, p[2], 0.00014)
				-- (a snapped hand snaps to itself: what the client steps is what the server unpacks)
				local qx, qy = Wire.quantise(side, x, y)
				local x2, y2 = Wire.target(side, qx, qy)
				t.eq(x2, x)
				t.eq(y2, y)
			end
			-- a hand off the table, or in the other half, is at its edge
			local qx, qy = Wire.quantise(side, 9, -s * 5)
			t.eq(qx, Wire.STEPS)
			t.eq(qy, 0)
		end
	end)

	t.test("wire: a segment's events survive packing, in arguments the wire can carry", function()
		local events: { [number]: any } = {}
		for tick = 101, 148 do
			events[tick] = { (tick * 37) % 4096, (tick * 91) % 4096 }
		end
		events[120][3] = true
		events[150] = { false, false, true }
		local strings = Wire.pack(events, 100)
		t.truthy(#strings >= 2 and #strings <= 6)
		for _, text in strings do
			t.truthy(#text <= 200 and #text % Wire.EVENT == 0)
		end
		local back = Wire.unpack(strings, 100, 150) :: any
		for tick, e in events do
			t.eq(back[tick][1], e[1], `tick {tick}`)
			t.eq(back[tick][2], e[2])
			t.eq(back[tick][3] == true, e[3] == true)
		end
		t.eq(Wire.join(back, 100), table.concat(strings))
		-- what is not a segment is refused, never guessed at
		t.eq(Wire.unpack({ "00" }, 0, 10), nil, "half an event")
		t.eq(Wire.unpack({ "0500000400AA" }, 0, 10), nil, "out of order")
		t.eq(Wire.unpack({ "0C0000" }, 0, 10), nil, "beyond the segment")
		t.eq(Wire.unpack({ "00 000" }, 0, 10), nil, "not a digit")
		t.eq(Wire.unpack({ 5 }, 0, 10), nil, "not a string")
		t.eq(Wire.unpack({ "000000" }, 0, 10), nil, "tick 0 of a segment is the one before it")
	end)

	t.test("referee: a log must carry on from itself, be short enough and not ahead of the clock", function()
		local r = Referee.new({ t0 = 0, game = 1, human = { [0] = true, [1] = false } })
		t.eq(Referee.mode(r), "0")
		local ok, why = Referee.accept(r, 0, 0, 24, { "010000" }, 30)
		t.truthy(ok, why)
		ok, why = Referee.accept(r, 0, 0, 24, {}, 60)
		t.eq(ok, false)
		t.eq(why, "That part of the game arrived out of order")
		ok, why = Referee.accept(r, 0, 24, 24 + Wire.MAX_SEGMENT + 1, {}, 99999)
		t.eq(ok, false)
		ok, why = Referee.accept(r, 0, 24, 400, {}, 100)
		t.eq(why, "That part of the game is ahead of the clock")
		ok, why = Referee.accept(r, 0, 24, 48, { "zz" }, 100)
		t.eq(why, "That part of the game could not be read")
		ok, why = Referee.accept(r, 1, 0, 24, {}, 100)
		t.eq(why, "The computer is playing that end")
		ok, why = Referee.accept(r, 0, 24.5, 48, {}, 100)
		t.eq(ok, false)
		-- nothing refused moved the match; the one segment taken is played exactly to its end
		local msg = Referee.advance(r, 100) :: any
		t.eq(msg.n0, 0)
		t.eq(msg.n, 24)
		t.eq(r.n, 24)
		t.eq(msg.a, "010000")
		t.eq(Referee.advance(r, 5000), nil, "against the computer the referee never steps by the clock")
	end)

	for _, ms in { 0, 80, 150 } do
		local frames = math.floor(ms / 1000 * 60 + 0.5)
		t.test(`against the computer at {ms} ms each way: the screen is the match, to the last bit`, function()
			local line = Line.new({
				humans = { [0] = true, [1] = false },
				lag = { [0] = frames, [1] = frames },
				hands = { [0] = Line.hands.chaser(1) },
				difficulty = Sim.DIFFICULTY.hard,
				watchers = 1,
			})
			t.truthy(Line.play(line, 240), "the match is played to seven")
			Line.run(line, 1)
			local seat = line.seats[0]
			local e = Line.errors(line, 0)
			t.eq(seat.resims, 0, "nothing was ever corrected")
			t.eq(seat.replica.desyncs, 0)
			t.eq(e.near.max, 0, "the puck in the player's half")
			t.eq(e.far.max, 0, "the puck in the far half")
			t.eq(e.own.max, 0, "the player's own mallet")
			t.eq(e.other.max, 0, "the computer's mallet")
			t.truthy(e.frames - e.undecided > 600, `{e.frames} frames compared`)
			t.eq(#line.refused, 0, table.concat(line.refused, "; "))
			-- the screen and the referee end on the same score, and the referee's is the one that counts
			t.eq(seat.pred.score0, line.ref.sim.score0)
			t.eq(seat.pred.score1, line.ref.sim.score1)
			t.eq(math.max(line.ref.sim.score0, line.ref.sim.score1), 7)
			-- the log: ten messages a second, never one a frame
			local perSecond = line.sent[0] / line.time
			t.truthy(perSecond > 8 and perSecond <= 10.01, `{perSecond} messages a second`)
			-- a watcher saw the same match
			local watcher = line.watchers[1]
			Replica.step(watcher)
			t.eq(watcher.desyncs, 0)
			t.eq(watcher.sim.score0, line.ref.sim.score0)
			t.eq(watcher.sim.score1, line.ref.sim.score1)
		end)
	end

	t.test("against the computer from the Ember end, at a frame rate that is no multiple of the ticks", function()
		local line = Line.new({
			humans = { [0] = false, [1] = true },
			lag = { [0] = 4, [1] = 4 },
			hands = { [1] = Line.hands.chaser(1.5) },
			fps = 144,
		})
		for i = 1, 144 * 40 do
			-- (frames of uneven length, and one long hitch)
			Line.frame(line, if i == 2000 then 0.4 else (1 / 144) * (0.6 + (i % 5) * 0.2))
		end
		local e = Line.errors(line, 1)
		t.eq(line.seats[1].resims, 0)
		t.truthy(e.near.max < 1e-12 and e.far.max < 1e-12 and e.own.max < 1e-12, `{e.near.max} {e.far.max}`)
		t.eq(#line.refused, 0, table.concat(line.refused, "; "))
		t.truthy(line.ref.n > 240 * 35, "the referee kept up through the hitch")
	end)

	-- Two people. What is drawn is the referee's match, not all of it at one moment: this end now, the far end as
	-- late as the stream (Seat's header). Bounds in metres on a 2.34 m bed and in seconds; the measured figures
	-- are printed by `lune run tools/games/air_hockey/netcode.luau`.
	for _, case in
		{
			{ ms = 0, late = 0.085, shown = 0.002, live = 0.95, near = 0.01 },
			{ ms = 40, late = 0.135, shown = 0.004, live = 0.88, near = 0.03 },
			{ ms = 80, late = 0.235, shown = 0.012, live = 0.7, near = 0.2 },
			{ ms = 150, late = 0.375, shown = 0.012, live = 0.45, near = 0.45 },
		}
	do
		local frames = math.floor(case.ms / 1000 * 60 + 0.5)
		t.test(
			`two people at {case.ms} ms each way: your hand is now, the far end is the referee's a moment ago`,
			function()
				local line = Line.new({
					humans = { [0] = true, [1] = true },
					lag = { [0] = frames, [1] = frames },
					hands = { [0] = Line.hands.chaser(1), [1] = Line.hands.chaser(2) },
				})
				Line.run(line, 60)
				t.eq(#line.refused, 0, table.concat(line.refused, "; "))
				t.eq(line.ref.cuts, 0, "neither hand was late enough to be played without")
				for side = 0, 1 do
					local seat = line.seats[side]
					local e = Line.errors(line, side)
					local sm = Line.smooth(line, side)
					t.eq(seat.replica.desyncs, 0)
					t.truthy(
						e.own.max < 1e-9,
						`a player's own mallet is their hand, with no delay (off by {e.own.max} m)`
					)
					-- the far mallet: the other player's real hand, never a guess, and never faster than a hand
					t.truthy(
						e.farShown.p95 < 1e-5,
						`side {side}: the far mallet drawn is the referee's ({e.farShown.p95} m)`
					)
					t.truthy(e.farShown.mean < 0.002, `side {side}: far mallet off by {e.farShown.mean} m on average`)
					t.truthy(e.farLate.p95 < case.late, `side {side}: the far mallet is drawn {e.farLate.p95} s late`)
					t.truthy(
						sm.malletOver <= sm.frames * 0.002,
						`side {side}: the far mallet moved faster than a hand on {sm.malletOver} frames`
					)
					-- the puck: the referee's puck of the moment it is drawn at, and never later than the far mallet
					t.truthy(
						e.puckShown.mean < case.shown,
						`side {side}: the puck drawn is {e.puckShown.mean} m from the referee's on average`
					)
					t.truthy(e.puckShown.p95 < 0.005, `side {side}: and within {e.puckShown.p95} m on 95 frames in 100`)
					t.truthy(e.puckLate.max <= e.farLate.max + 1e-9, "the puck is never drawn later than the far end")
					-- in this player's own half it is the present puck (the rest: a strike at the far end is
					-- not known here yet, or the puck is being brought to the present)
					t.truthy(
						e.nearLive > case.live,
						`side {side}: in their own half the puck drawn is the present puck on {e.nearLive * 100} % of frames`
					)
					t.truthy(
						e.near.mean < case.near,
						`side {side}: puck in the near half off by {e.near.mean} m on average`
					)
					local perSecond = line.sent[side] / math.min(line.time, line.ref.n / 240 + 0.5)
					t.truthy(perSecond > 12 and perSecond <= 15.01, `{perSecond} messages a second`)
				end
				t.truthy(line.ref.sim.hitSerial > 30, "a real rally")
			end
		)
	end

	t.test(
		"two people: the moment the puck is drawn at never runs backward, slows to no less than SLOW, and a sound is heard when its contact is seen",
		function()
			local line = Line.new({
				humans = { [0] = true, [1] = true },
				lag = { [0] = 3, [1] = 3 },
				hands = { [0] = Line.hands.chaser(1), [1] = Line.hands.chaser(2) },
			})
			local seat = line.seats[0]
			local last, lastFar = nil :: number?, nil :: number?
			local heard, contacts = 0, 0
			local slowest, fastest = math.huge, 0
			for _ = 1, 60 * 30 do
				local hits = line.ref.sim.hitSerial
				Line.frame(line)
				contacts += line.ref.sim.hitSerial - hits
				if seat.ready and seat.mode == "2" and line.ref.sim.winner < 0 then
					if last and lastFar then
						local step = seat.puckAt - last
						t.truthy(step >= -1e-9, "the puck's moment went back")
						t.truthy(seat.farAt - lastFar >= -1e-9, "the far mallet's moment went back")
						if step > 0 then
							slowest, fastest = math.min(slowest, step / 4), math.max(fastest, step / 4)
						end
					end
					last, lastFar = seat.puckAt, seat.farAt
					t.truthy(
						seat.puckAt <= seat.tick and seat.puckAt >= seat.farAt - 1e-9,
						"between the far end's moment and now"
					)
					Seat.heard(seat, function(what: number, speed: number)
						heard += 1
						t.truthy(what >= Sim.HIT_RAIL and what <= Sim.HIT_MALLET + 1)
						t.truthy(speed >= 0 and speed <= 2 * Sim.MAX_SPEED + 3.5)
					end)
				end
			end
			t.truthy(fastest <= Seat.FAST + 1e-6, `quickened to {fastest} of its speed at most`)
			t.truthy(fastest > 2, "a puck coming back was brought to the present")
			t.truthy(contacts > 40, "a rally")
			t.truthy(heard >= contacts * 0.9 and heard <= contacts + 2, `{heard} contacts heard of {contacts} decided`)
		end
	)

	t.test("two people: a hand that stops arriving is not waited for, and comes back into the match", function()
		local line = Line.new({
			humans = { [0] = true, [1] = true },
			lag = { [0] = 2, [1] = 2 },
			hands = { [0] = Line.hands.chaser(1), [1] = Line.hands.chaser(1) },
		})
		Line.run(line, 5)
		local before = line.ref.n
		-- Ember's messages are held up for a second and a half
		line.lag[1] = 90
		Line.run(line, 1.5)
		t.truthy(line.ref.cuts > 0, "the match went on without that hand")
		t.truthy(line.ref.n > before + 240, "and did not stop for it")
		line.lag[1] = 2
		Line.run(line, 6)
		local cuts = line.ref.cuts
		Line.run(line, 4)
		t.eq(line.ref.cuts, cuts, "once it arrives again it is waited for again")
		t.eq(#line.refused, 0, "the late part of the log was taken, not refused: " .. table.concat(line.refused, "; "))
		for side = 0, 1 do
			t.eq(line.seats[side].replica.desyncs, 0)
			t.eq(line.seats[side].pred.score0, line.ref.sim.score0)
		end
	end)

	t.test("a seat changes hands mid-match: the computer's end is taken by a person, and given back", function()
		local line = Line.new({
			humans = { [0] = true, [1] = false },
			lag = { [0] = 3, [1] = 3 },
			hands = { [0] = Line.hands.chaser(1), [1] = Line.hands.chaser(1) },
		})
		Line.run(line, 6)
		-- a person sits down at the Ember end
		Referee.control(line.ref, 1, true)
		local seat = Seat.new(1)
		line.seats[1] = seat
		Seat.begin(seat, 1, Referee.expects(line.ref, 1))
		Line.tell(line, Referee.snapshot(line.ref))
		t.eq(Referee.mode(line.ref), "2")
		Line.run(line, 8)
		t.eq(#line.refused, 0, table.concat(line.refused, "; "))
		t.truthy(line.sent[1] > 60, "the newcomer's hand is in the match")
		t.eq(seat.replica.desyncs, 0)
		t.eq(line.seats[0].replica.desyncs, 0)
		t.truthy(Line.errors(line, 1).own.max < 1e-9, "the newcomer's mallet is their hand")
		-- and leaves: the computer has the end again, harder than before
		line.seats[1] = nil
		line.ref.sim.difficulty = Sim.DIFFICULTY.hard
		Referee.control(line.ref, 1, false)
		Line.tell(line, Referee.snapshot(line.ref))
		Line.run(line, 1)
		local resims = line.seats[0].resims
		Line.run(line, 7)
		t.eq(Referee.mode(line.ref), "0")
		t.eq(line.seats[0].replica.desyncs, 0, "the replay follows the change of hands and of difficulty")
		t.eq(line.seats[0].pred.difficulty, Sim.DIFFICULTY.hard)
		t.eq(line.seats[0].resims, resims, "alone with the computer again, nothing more is corrected")
		local e = Line.errors(line, 0)
		t.truthy(e.own.max < 1e-9, "their own mallet is their hand")
	end)

	t.test("a watcher who arrives late starts from the next message and sees the same match", function()
		local line = Line.new({
			humans = { [0] = true, [1] = false },
			lag = { [0] = 3, [1] = 3 },
			hands = { [0] = Line.hands.chaser(1) },
		})
		Line.run(line, 9)
		local late = Replica.new()
		table.insert(line.watchers, late)
		Line.run(line, 9)
		t.eq(late.jumps, 1, "one message taken as it stands, then replayed from there")
		t.eq(late.desyncs, 0)
		Replica.step(late)
		t.truthy(late.tick > line.ref.n - 60, "a few frames behind the referee, no more")
		local truth = line.truth[late.tick]
		t.eq(late.sim.px, truth[1], "the watcher holds what the referee decided for that tick")
		t.eq(late.sim.py, truth[2])
		t.eq(late.sim.p0x, truth[3])
		t.eq(late.sim.p1y, truth[6])
		-- and a stream message that is not one is ignored
		local held = Wire.state(late.sim)
		t.eq(Replica.push(late, { kind = "air_hockey" }), false)
		t.eq(Replica.push(late, { g = 1, n0 = 0, n = 5, m = "0", a = "", b = "", t0 = 0, s = { 1, 2 } }), false)
		t.truthy(Wire.same(late.sim, held))
	end)
end
