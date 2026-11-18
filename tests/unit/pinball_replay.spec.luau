--!strict
-- Minigames/Pinball InputLog, Replay and Stream (checklist PIN-P6): the player's machine runs the model live and
-- sends only its input log; the server's replay of that log is the same game, bit for bit, and is the score of
-- record; a watcher's replay is too. The guards on what a client may send; the thump only the server can
-- grant; a skipped ball; and the frames a client draws from, squeezed and opened again.
local Bot = require("@shared/Minigames/Pinball/Bot")
local InputLog = require("@shared/Minigames/Pinball/InputLog")
local Layout = require("@shared/Minigames/Pinball/Layout")
local Machine = require("@shared/Minigames/Pinball/Machine")
local Physics = require("@shared/Minigames/Pinball/Physics")
local Replay = require("@shared/Minigames/Pinball/Replay")
local Rules = require("@shared/Minigames/Pinball/Rules")
local Stream = require("@shared/Minigames/Pinball/Stream")
local Tables = require("@shared/Minigames/Pinball/Tables")
local Test = require("../lib/Test")

local BTN, PHASE = Machine.BTN, Machine.PHASE

local function digest(v: any): string
	if type(v) ~= "table" then
		return if type(v) == "number" then string.format("%.17g", v) else tostring(v)
	end
	local keys = {}
	for k in v do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, k in keys do
		table.insert(parts, tostring(k) .. "=" .. digest(v[k]))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

-- a whole game played live by computer players (one per seat), every segment handed to `send`
local function playLive(
	id: string,
	seed: number,
	players: number,
	level: number,
	send: (seat: number, seg: InputLog.Segment) -> ()
): Replay.State
	local tbl = Tables.need(id)
	local live = Replay.new(id, seed, players)
	local bots = {}
	for seat = 1, players do
		bots[seat] = Bot.new(level, seed * 31 + seat)
	end
	local rec = Replay.recorder(live)
	local guard = 0
	while not Replay.over(live) do
		local seat = live.m.up
		local seg = Replay.live(live, rec, Bot.step(bots[seat], tbl, live.m))
		if seg then
			send(seat, seg)
		end
		guard += 1
		assert(guard < 240 * 60 * 40, "the game did not end")
	end
	return live
end

return function(t: Test.T)
	t.test(
		"InputLog: a recorder keeps only the changes; a second of holding one flipper is a handful of numbers",
		function()
			local rec = InputLog.recorder(1000)
			for i = 1, 240 do
				InputLog.push(rec, if i > 10 and i <= 200 then BTN.LEFT else 0)
			end
			local seg = InputLog.cut(rec)
			t.deepEq(seg, { 1000, 1240, 11, BTN.LEFT, 201, 0 })
			t.eq(InputLog.changes(seg), 2)
			-- the next segment starts where this one ended and carries the buttons over
			InputLog.push(rec, 0)
			InputLog.push(rec, BTN.RIGHT)
			t.deepEq(InputLog.cut(rec), { 1240, 1242, 2, BTN.RIGHT })
			-- played back, every tick has its buttons
			local seen: { number } = {}
			local held, ticks = InputLog.play(seg, 0, function(buttons: number): boolean?
				table.insert(seen, buttons)
				return nil
			end)
			t.eq(#seen, 240)
			t.eq(ticks, 240)
			t.eq(seen[10], 0)
			t.eq(seen[11], BTN.LEFT)
			t.eq(seen[200], BTN.LEFT)
			t.eq(seen[201], 0)
			t.eq(held, 0)
		end
	)

	t.test("InputLog.check: only a well-formed segment that starts where the last ended gets in", function()
		t.truthy(InputLog.check({ 0, 48 }, 0))
		t.truthy(InputLog.check({ 0, 48, 1, 3, 48, 0 }, 0))
		local bad: { [string]: any } = {
			["not a segment"] = "seg",
			["length"] = { 0 },
			["out of order"] = { 5, 48 },
			["span"] = { 0, 0 },
			["ticks"] = { 0, 48.5 },
			["offsets"] = { 0, 48, 49, 1 },
			["buttons"] = { 0, 48, 1, 4096 },
			["numbers"] = { 0, 48, 1, 0.5 },
		}
		for why, seg in bad do
			local ok, got = InputLog.check(seg, 0)
			t.falsy(ok, why)
			t.eq(got, why)
		end
		t.falsy(InputLog.check({ 0, 48, 1, -1 }, 0))
		t.falsy(InputLog.check({ 0, 48, 0, 1 }, 0), "an offset of zero is the tick before")
		t.falsy(InputLog.check({ 0, 48, 5, 1, 5, 2 }, 0), "offsets must rise")
		t.falsy(InputLog.check({ 0, 48, 1, 0 / 0 }, 0), "not a number")
		t.falsy(InputLog.check({ 0, InputLog.MAX_TICKS + 1 }, 0), "too long")
		local busy = { 0, InputLog.MAX_TICKS }
		for i = 1, InputLog.MAX_CHANGES + 1 do
			table.insert(busy, i)
			table.insert(busy, i % 2)
		end
		local ok, why = InputLog.check(busy, 0)
		t.falsy(ok)
		t.eq(why, "too many changes")
	end)

	t.test(
		"PIN-P6: the server's replay of the input log is the same game as the one the player saw, bit for bit",
		function()
			for _, id in Tables.IDS do
				local server = Replay.new(id, 4242, 2)
				local watcher = Replay.new(id, 4242, 2)
				local segments, numbers, longest = 0, 0, 0
				local live = playLive(id, 4242, 2, 2, function(seat, seg)
					-- across the wire and back: two numbers and a short string (InputLog.pack)
					local from, to, packed = InputLog.pack(seg)
					longest = math.max(longest, #packed)
					local copy = InputLog.unpack(from, to, packed)
					assert(copy, "the segment did not open again")
					t.deepEq(copy, seg)
					local ok, why = Replay.feed(server, seat, copy)
					t.truthy(ok, why)
					t.truthy(Replay.follow(watcher, seat, table.clone(seg), {}))
					segments += 1
					numbers += #seg
				end)
				t.truthy(longest <= InputLog.WIRE_CHARS, `{id}: the longest message was {longest} characters`)
				t.truthy(Replay.over(server), `{id}: the replay reached the end of the game`)
				t.eq(server.tick, live.tick)
				t.eq(digest(server.m), digest(live.m), `{id}: the machines are identical`)
				t.eq(digest(watcher.m), digest(live.m))
				t.eq(server.m.scores[1], live.m.scores[1])
				t.eq(server.m.scores[2], live.m.scores[2])
				t.falsy(server.suspect, `{id}: play never trips the rate guard`)
				-- the log is small: a few numbers a second
				local seconds = live.tick / 240
				t.truthy(numbers / seconds < 40, `{id}: {numbers / seconds} numbers a second`)
				t.truthy(segments / seconds <= 10.1, "ten segments a second (the wire carries twenty messages)")
			end
		end
	)

	t.test(
		"PIN-P6: no segment runs across two balls; the next player's log starts where the last ball ended",
		function()
			local server = Replay.new("pinball_acorn", 7, 3)
			local lastSeat, hands = 0, 0
			local live = playLive("pinball_acorn", 7, 3, 1, function(seat, seg)
				if seat ~= lastSeat then
					hands += 1
					lastSeat = seat
				end
				t.eq(server.m.up, seat, "each segment belongs to the player whose ball is up")
				t.eq(seg[1], server.tick)
				t.truthy(Replay.feed(server, seat, seg))
			end)
			t.eq(hands, 9, "three players, three balls each, one after another")
			t.eq(digest(server.m), digest(live.m))
		end
	)

	t.test("PIN-P6: a different log is a different game: the score cannot be claimed, only played", function()
		local a = Replay.new("pinball_rodent", 1, 1)
		local b = Replay.new("pinball_rodent", 1, 1)
		local hold = 260 -- nine tenths of a full pull
		t.truthy(Replay.feed(a, 1, { 0, 400, 1, BTN.PLUNGE, hold, 0 }))
		t.truthy(Replay.feed(b, 1, { 0, 400, 1, BTN.PLUNGE, hold - 60, 0 }))
		for _ = 1, 20 do
			t.truthy(Replay.feed(a, 1, { a.tick, a.tick + 240, 30, BTN.LEFT + BTN.RIGHT, 80, 0 }))
			t.truthy(Replay.feed(b, 1, { b.tick, b.tick + 240, 30, BTN.LEFT + BTN.RIGHT, 80, 0 }))
		end
		t.neq(digest(a.m.phys), digest(b.m.phys))
		-- nothing in a segment is a score: only ticks and buttons
		local ok, why = Replay.feed(a, 1, { a.tick, a.tick + 10, 1, 1000000 })
		t.falsy(ok)
		t.eq(why, "buttons")
	end)

	t.test("guards: wrong seat, out of order, a finished game; a segment is all or nothing", function()
		local r = Replay.new("pinball_acorn", 3, 2)
		local before = digest(r.m)
		local ok, why = Replay.feed(r, 2, { 0, 48 })
		t.falsy(ok)
		t.eq(why, "not your ball")
		ok, why = Replay.feed(r, 1, { 10, 48 })
		t.falsy(ok)
		t.eq(why, "out of order")
		ok, why = Replay.feed(r, 1, { 0, 48, 60, 1 })
		t.falsy(ok)
		t.eq(digest(r.m), before, "a refused segment changes nothing")
		t.eq(r.tick, 0)
		t.truthy(Replay.feed(r, 1, { 0, 48 }))
		t.eq(r.tick, 48)
		for _ = 1, 6 do
			Replay.skip(r)
		end
		t.truthy(Replay.over(r))
		ok, why = Replay.feed(r, 1, { r.tick, r.tick + 48 })
		t.falsy(ok)
		t.eq(why, "the game is over")
	end)

	t.test(
		"squirrel: a thump in the log is refused unless the server granted it; a grant is good once and does not keep",
		function()
			local r = Replay.new("pinball_space", 3, 1)
			local ok, why = Replay.feed(r, 1, { 0, 48, 5, BTN.THUMP, 6, 0 })
			t.falsy(ok)
			t.eq(why, "thump")
			t.eq(r.tick, 0, "a refused segment plays nothing")
			t.truthy(Replay.grantThump(r))
			t.truthy(Replay.feed(r, 1, { 0, 48, 5, BTN.THUMP, 6, 0 }))
			ok = Replay.feed(r, 1, { 48, 96, 5, BTN.THUMP, 6, 0 })
			t.falsy(ok, "the grant is spent")
			-- the same animal, the same thump: no second grant inside two seconds
			t.eq(Replay.THUMP_TICKS, Machine.THUMP_COOL)
			t.truthy(Replay.THUMP_TICKS >= 2 * Physics.HZ)
			t.falsy(Replay.grantThump(r), "a second grant 48 ticks after the first is refused")
			t.truthy(Replay.feed(r, 1, { 48, 48 + Replay.THUMP_TICKS }))
			t.truthy(Replay.grantThump(r), "two seconds on, another animal may land")
			-- holding the bit is one thump, not many
			local at = r.tick
			t.truthy(Replay.feed(r, 1, { at, at + 48, 5, BTN.THUMP, 20, BTN.THUMP + BTN.LEFT, 30, 0 }))
			-- a grant the log did not use does not keep: it cannot be saved up for a chosen moment
			t.truthy(Replay.feed(r, 1, { r.tick, r.tick + Replay.THUMP_TICKS }))
			t.truthy(Replay.grantThump(r))
			for _ = 1, 3 do
				t.truthy(Replay.feed(r, 1, { r.tick, r.tick + 240 }))
			end
			ok, why = Replay.feed(r, 1, { r.tick, r.tick + 48, 5, BTN.THUMP, 6, 0 })
			t.falsy(ok, "three seconds after the grant it has lapsed")
			t.eq(why, "thump")
			-- through the rules: the server's verb says when it is too soon
			local rules = Rules.forTable("pinball_space")
			local state = rules.init(1, 3)
			t.truthy(rules.input(state, 1, "thump"))
			ok, why = rules.input(state, 1, "thump")
			t.falsy(ok)
			t.eq(why, "too soon")
		end
	)

	t.test(
		"squirrel: the thump is judged by the server only: a watcher who was never given the grant follows the same game",
		function()
			local id = "pinball_acorn"
			local tbl = Tables.need(id)
			-- the player's machine plays live; the server judges; a watcher copies the server's replay BEFORE the grant
			local live, server = Replay.new(id, 12, 2), Replay.new(id, 12, 2)
			local rec = Replay.recorder(live)
			local bot = Bot.new(2, 3)
			local watcher: Replay.State? = nil
			local other = Replay.new(id, 12, 2) -- the second player's machine, following from the first tick
			local granted, thumped, fed = false, false, 0
			for tick = 1, 240 * 12 do
				local buttons = Bot.step(bot, tbl, live.m)
				if granted and not thumped and live.m.launched then
					buttons += BTN.THUMP -- the player's machine was told of the thump and puts it in its log
					thumped = true
				end
				local seg = Replay.live(live, rec, buttons)
				if seg then
					local ok, why = Replay.feed(server, 1, seg, nil, Replay.sum(live))
					t.truthy(ok, why)
					t.truthy(Replay.follow(other, 1, table.clone(seg)))
					if watcher then
						local wok, wwhy = Replay.follow(watcher, 1, table.clone(seg))
						t.truthy(wok, `the watcher follows: {wwhy}`)
						t.eq(watcher.tick, server.tick)
						t.eq(Replay.sum(watcher), Replay.sum(server), "to the same sum")
					end
					fed += 1
				end
				if tick == 600 then
					watcher = Replay.clone(server)
				elseif tick == 900 then
					t.truthy(Replay.grantThump(server))
					granted = true
				end
			end
			t.truthy(thumped, "the thump was in the log")
			local w = watcher :: Replay.State
			t.eq(w.thumps, 0, "the watcher never held a grant")
			t.eq(digest(w.m), digest(server.m), "the watcher's machine is the server's")
			t.eq(digest(other.m), digest(server.m), "and so is the other player's")
			t.falsy(server.drift)
			-- the judge still refuses what a follower lets through: the guard has not gone, it has moved
			local judge, follower = Replay.new(id, 1, 1), Replay.new(id, 1, 1)
			local seg = { 0, 48, 5, BTN.THUMP, 6, 0 }
			t.falsy(Replay.feed(judge, 1, seg))
			t.truthy(Replay.follow(follower, 1, seg))
			-- a follower still checks the order and the form
			local ok, why = Replay.follow(follower, 1, { 10, 96 })
			t.falsy(ok)
			t.eq(why, "out of order")
			ok, why = Replay.follow(follower, 2, { 48, 96 })
			t.falsy(ok)
			t.eq(why, "not your ball")
		end
	)

	t.test(
		"time: the server tells the replay its clock; a ball's log may run half a second ahead and two behind, no further",
		function()
			t.eq(Replay.AHEAD_SECONDS, 0.5)
			t.eq(Replay.BEHIND_SECONDS, 2)
			t.eq(Replay.SEGMENT_TICKS, InputLog.WIRE_TICKS)
			t.eq(Physics.HZ / Replay.SEGMENT_TICKS, 10, "ten segments a second")
			-- with no clock told, time is not judged (specs, tools, a follower)
			local free = Replay.new("pinball_acorn", 1, 1)
			t.truthy(Replay.feed(free, 1, { 0, 720 }))
			t.eq(Replay.pace(free), 0)
			-- a burst: thirty seconds of log in one go. The server plays half a second of it and no more
			local r = Replay.new("pinball_acorn", 1, 1)
			t.eq(Replay.clock(r, 100), "ok", "the first word of the time starts the clock (any origin)")
			local taken = 0
			for i = 1, 300 do
				local ok, why = Replay.feed(r, 1, { r.tick, r.tick + 24 })
				if ok then
					taken += 1
				else
					t.eq(why, "ahead")
				end
				t.truthy(i < 300 or not ok)
			end
			t.eq(taken, 5, "five segments are half a second")
			t.eq(r.tick, 120, "nothing past the bound was simulated")
			t.eq(Replay.pace(r), 120)
			-- a refused segment played nothing, so the same segment is good once the clock has caught up
			t.eq(Replay.clock(r, 100.125), "ok")
			t.truthy(Replay.feed(r, 1, { 120, 144 }))
			-- played in time, a log is never ahead and never behind
			local honest = Replay.new("pinball_acorn", 1, 1)
			for i = 0, 99 do
				t.eq(Replay.clock(honest, 7 + i / 10), "ok")
				t.truthy(Replay.feed(honest, 1, { honest.tick, honest.tick + 24 }))
			end
			t.falsy(honest.late)
			t.truthy(Replay.fair(honest))
			-- slow motion: a quarter of the speed. Two seconds behind comes after 2.7 s of it
			local slow = Replay.new("pinball_acorn", 1, 2)
			local verdict = "ok"
			local seconds = 0
			while verdict == "ok" and seconds < 10 do
				seconds += 0.1
				verdict = Replay.clock(slow, 50 + seconds)
				if verdict == "ok" then
					t.truthy(Replay.feed(slow, 1, { slow.tick, slow.tick + 6 }))
				end
			end
			t.eq(verdict, "behind")
			t.near(
				seconds,
				2 / 0.75 + Replay.BEHIND_HOLD,
				0.25,
				"0.75 s is lost in every second of quarter speed, and the verdict waits BEHIND_HOLD"
			)
			-- the caller takes the ball: it is played out dead, and the game is marked late
			local epoch = slow.epoch
			Replay.lapse(slow)
			t.truthy(slow.late)
			t.falsy(Replay.fair(slow), "a game that was out of pace is not fair")
			t.eq(slow.m.up, 2, "the ball has gone to the next player")
			t.eq(slow.epoch, epoch + 1, "every copy that was ahead of the server needs a clone")
			t.truthy(slow.own > 1000, `the dead ball took {slow.own} ticks, all the server's own`)
			-- time is measured ball by ball: the new ball starts level, whatever the last one cost
			t.eq(Replay.pace(slow), 0)
			t.eq(Replay.clock(slow, 50 + seconds + 0.1), "ok")
			t.truthy(Replay.feed(slow, 2, { slow.tick, slow.tick + 24 }))
			t.near(Replay.pace(slow), 0, 1e-6)
			-- a clock never runs back
			Replay.clock(slow, 1)
			t.truthy(slow.now > 50)
			-- the lateness is the slow seat's: the other player's score may still go on the board
			t.truthy(slow.lateSeats[1])
			t.falsy(slow.lateSeats[2])
			t.falsy(Replay.fair(slow, 1))
			t.truthy(Replay.fair(slow, 2))
		end
	)

	t.test(
		"time: a stall on the line is not slow play. Nothing arriving for three and a half seconds is never behind; the held-up log arrives in a burst, catches up and the ball, the next ball and the board place are kept",
		function()
			local r = Replay.new("pinball_rodent", 3, 2)
			local tbl = Tables.need(r.id)
			local bot = Bot.new(1, 4)
			-- the player's own machine, played at full speed against the server's clock (0.1 s a step)
			local live = Replay.new("pinball_rodent", 3, 2)
			local liveRec = Replay.recorder(live)
			local queue: { InputLog.Segment } = {}
			local function play(seconds: number)
				local due = live.tick + math.floor(seconds * Physics.HZ + 0.5)
				while live.tick < due and live.m.up == 1 do
					local seg = Replay.live(live, liveRec, Bot.step(bot, tbl, live.m))
					if seg then
						table.insert(queue, seg)
					end
				end
			end
			local now = 20
			local function deliver(): (boolean, string?)
				while #queue > 0 do
					local ok, why = Replay.feed(r, 1, queue[1])
					if not ok then
						return false, why
					end
					table.remove(queue, 1)
				end
				return true
			end
			-- two seconds of ball one in time, the segments arriving a step later
			t.eq(Replay.clock(r, now), "ok")
			for _ = 1, 20 do
				play(0.1)
				now += 0.1
				t.eq(Replay.clock(r, now), "ok")
				t.truthy(deliver())
			end
			-- the line stalls for 3.5 s: the player plays on, nothing arrives; the clock never says "behind"
			for _ = 1, 35 do
				play(0.1)
				now += 0.1
				t.eq(Replay.clock(r, now), "ok", `stalled {now - 22} s`)
			end
			t.eq(r.m.up, 1, "the ball is still the player's")
			t.falsy(r.late)
			-- the held-up log arrives in one burst and is played at once (none of it is ahead of the clock)
			t.truthy(deliver())
			t.eq(r.tick, live.tick)
			-- and play goes on in time: the verdict after the burst finds the log level with the clock
			for _ = 1, 20 do
				play(0.1)
				now += 0.1
				t.eq(Replay.clock(r, now), "ok")
				t.truthy(deliver())
			end
			t.eq(r.epoch, 0, "the server never played by itself")
			t.falsy(r.late)
			t.truthy(Replay.fair(r, 1) and Replay.fair(r))
			t.eq(Replay.sum(r), Replay.sum(live), "the server's game is the player's")
		end
	)

	t.test(
		"time: one player's balls in a row are one stretch of their clock (a ball ending does not restart it); a ball the server played itself starts the next player's clock afresh",
		function()
			local r = Replay.new("pinball_acorn", 1, 1)
			local live = Replay.new("pinball_acorn", 1, 1)
			local tbl = Tables.need(r.id)
			local bot = Bot.new(1, 2)
			local rec = Replay.recorder(live)
			local now = 5
			Replay.clock(r, now)
			local ball = r.m.ball
			local steps = 0
			while r.ballTick == 0 and steps < 240 * 600 do
				for _ = 1, 24 do
					local seg = Replay.live(live, rec, Bot.step(bot, tbl, live.m))
					if seg then
						t.truthy(Replay.feed(r, 1, seg))
					end
				end
				now += 0.1
				steps += 24
				t.eq(Replay.clock(r, now), "ok")
			end
			t.truthy(r.ballTick > 0 and r.m.ball >= ball, "ball one ended by the log")
			t.eq(r.clockTick, 0, "the clock runs on from the first ball")
			t.near(Replay.pace(r), 0, 30)
			-- the server plays the ball out itself: the clock starts again from that moment
			Replay.skip(r)
			t.eq(r.clockTick, r.tick)
			t.eq(r.ballClock, r.now)
		end
	)

	t.test(
		"retire: a seat that is not up leaves the ball in play alone (no epoch, the same sum); its balls are passed over at the next hand-over, whenever before it a copy is told",
		function()
			local r = Replay.new("pinball_acorn", 7, 3)
			local copy = Replay.clone(r)
			-- a ball launched and left to drain, the same hands on every copy (by the tick)
			local function hands(tick: number): number
				return if tick % 2000 < 200 then BTN.PLUNGE else 0
			end
			local rec1 = Replay.recorder(r)
			for _ = 1, 600 do
				Replay.live(r, rec1, hands(r.tick))
			end
			local sum, epoch = Replay.sum(r), r.epoch
			t.falsy(Replay.retire(r, 2), "the ball in play was not taken")
			t.eq(r.epoch, epoch)
			t.eq(Replay.sum(r), sum)
			t.truthy(r.m.gone[2])
			-- a copy that is told later (it is ahead of the server, or behind it) reaches the same hand-over
			local rec = Replay.recorder(copy)
			for i = 1, 30000 do
				if i == 900 then
					t.falsy(Replay.retire(copy, 2))
				end
				Replay.live(copy, rec, hands(copy.tick))
				if copy.m.up ~= 1 then
					break
				end
			end
			local rec2 = Replay.recorder(r)
			while r.m.up == 1 do
				Replay.live(r, rec2, hands(r.tick))
			end
			t.eq(copy.m.up, 3, "seat 2 is passed over")
			t.eq(r.m.up, 3)
			t.eq(Replay.sum(copy), Replay.sum(r))
			-- the player up retiring is the server's own play: the ball is taken and the epoch rises
			t.truthy(Replay.retire(r, 3))
			t.eq(r.epoch, epoch + 1)
			t.eq(r.m.up, 1)
		end
	)

	t.test('time: through the rules the server\'s verb "clock" takes a ball that has fallen behind', function()
		local rules = Rules.forTable("pinball_rodent")
		local view = rules.view :: (any) -> { [string]: any }
		t.truthy(rules.verbs.clock)
		t.truthy(rules.serverVerbs and rules.serverVerbs.clock, "only the server tells the time")
		local state = rules.init(2, 5)
		t.truthy(rules.input(state, 1, "clock", { 10 }))
		t.falsy(rules.input(state, 1, "clock", { "now" }))
		t.falsy(rules.input(state, 1, "clock", { 0 / 0 }))
		local from, to, packed = InputLog.pack({ 0, 24 })
		t.truthy(rules.input(state, 1, "log", { from, to, packed }))
		t.eq(view(state).pace, 0.1, "a tenth of a second of log at the clock's zero")
		t.falsy(view(state).late)
		t.eq(view(state).epoch, 0)
		-- a log that runs ahead is refused whole and may be sent in again
		local ok, why = true, nil :: string?
		local tick = 24
		for _ = 1, 10 do
			from, to, packed = InputLog.pack({ tick, tick + 24 })
			ok, why = rules.input(state, 1, "log", { from, to, packed })
			if not ok then
				break
			end
			tick += 24
		end
		t.falsy(ok)
		t.eq(why, "ahead")
		t.eq(view(state).tick, tick, "the acknowledgement has not moved")
		t.truthy(rules.input(state, 1, "clock", { 10.5 }))
		t.truthy(rules.input(state, 1, "log", { from, to, packed }))
		-- the machine goes quiet (a stall on the line): nothing arriving is never behind, however long
		t.truthy(rules.input(state, 1, "clock", { 12 }))
		t.truthy(rules.input(state, 1, "clock", { 14 }))
		t.eq(rules.turn and rules.turn(state), 1, "a quiet line is not slow play")
		t.falsy(view(state).late)
		-- the held-up log comes in a burst and catches up
		tick = 144
		while tick + 24 <= 936 do
			from, to, packed = InputLog.pack({ tick, tick + 24 })
			t.truthy(rules.input(state, 1, "log", { from, to, packed }))
			tick += 24
		end
		t.truthy(rules.input(state, 1, "clock", { 14.1 }))
		t.eq(rules.turn and rules.turn(state), 1)
		-- slow motion: the segments keep arriving but the log falls further and further behind; two seconds
		-- behind, held for half a second, the ball is taken
		local clock = 14.1
		for _ = 1, 60 do
			clock += 0.1
			t.truthy(rules.input(state, 1, "clock", { clock }))
			if rules.turn and rules.turn(state) ~= 1 then
				break
			end
			from, to, packed = InputLog.pack({ tick, tick + 6 })
			t.truthy(rules.input(state, 1, "log", { from, to, packed }))
			tick += 6
		end
		t.eq(rules.turn and rules.turn(state), 2, "more than two seconds behind: the ball is taken")
		t.near(clock, 14.1 + (480 - 72) / 180 + Replay.BEHIND_HOLD, 0.35)
		t.truthy(view(state).late)
		t.eq(view(state).epoch, 1)

		-- the game is played out; its result says it was not fair, and the board does not take it
		for _ = 1, 8 do
			if rules.skipTurn then
				rules.skipTurn(state)
			end
		end
		local result = rules.result(state)
		assert(result, "the game is over")
		t.eq(result.fair, false)
		t.eq(result.late, true)
		local clean = rules.init(1, 5)
		for _ = 1, 3 do
			(rules.skipTurn :: (any) -> ())(clean)
		end
		local cleanResult = rules.result(clean)
		assert(cleanResult, "the game is over")
		t.eq(cleanResult.fair, true)
	end)

	t.test("a segment that runs past the end of its ball is played to the end of the ball only, and says so", function()
		local id = "pinball_acorn"
		-- seat 1 plunges, never flips and sends three-second segments without cutting at the ball's end
		local server, honest = Replay.new(id, 5, 2), Replay.new(id, 5, 2)
		local played: number? = 0
		local ok, why: string? = true, nil
		local sent = 0
		local first = { 0, 720, 1, BTN.PLUNGE, 250, 0 }
		ok, why, played = Replay.feed(server, 1, first)
		t.truthy(ok)
		t.eq(why, nil)
		t.eq(played, 720, "a whole segment says how many ticks it played")
		t.truthy(Replay.feed(honest, 1, first))
		sent = 720
		for _ = 1, 40 do
			ok, why, played = Replay.feed(server, 1, { sent, sent + 720 })
			t.truthy(ok)
			if why ~= nil then
				break
			end
			-- (the honest machine cuts where the ball ends: fed tick by tick it stops there by itself)
			t.truthy(Replay.feed(honest, 1, { sent, sent + 720 }))
			sent += 720
		end
		t.eq(why, "overrun", "the segment that crossed the end of the ball says so")
		t.eq(server.m.up, 2, "the ball has changed hands")
		t.truthy((played :: number) < 720, `only {played} of its 720 ticks were this ball's`)
		t.eq(server.tick, sent + (played :: number), "the replay stands where the ball ended")
		t.truthy(server.drift, "the sender believes it is further on: it is sent a clone")
		-- the ticks that were played are the same game an honest cut would have given
		local exact = { sent, sent + (played :: number) }
		ok, why = Replay.feed(honest, 1, exact)
		t.truthy(ok)
		t.eq(why, nil)
		t.eq(digest(honest.m), digest(server.m))
		-- the next player's first segment starts where the ball ended, not where the late sender thought
		t.truthy(Replay.feed(server, 2, { server.tick, server.tick + 24 }))
		ok, why = Replay.feed(server, 1, { sent + 720, sent + 1440 })
		t.falsy(ok)
		-- through the rules: the verb answers true, "overrun" and the view shows the drift
		local rules = Rules.forTable(id)
		local view = rules.view :: (any) -> { [string]: any }
		local state = rules.init(2, 5)
		t.truthy(rules.input(state, 1, "seg", { first }))
		local at = 720
		local rok, rwhy: string? = true, nil
		for _ = 1, 40 do
			rok, rwhy = rules.input(state, 1, "seg", { { at, at + 720 } })
			if rwhy ~= nil then
				break
			end
			at += 720
		end
		t.truthy(rok)
		t.eq(rwhy, "overrun")
		t.eq(view(state).drift, true)
		t.eq(view(state).tick, server.tick - 24, "the acknowledgement is the tick the ball ended at")
	end)

	t.test("idle: the replay knows how long the buttons have not changed, ball by ball", function()
		local r = Replay.new("pinball_acorn", 1, 2)
		t.eq(Replay.idleSeconds(r), 0)
		t.truthy(Replay.feed(r, 1, { 0, 480 }))
		t.eq(Replay.idleSeconds(r), 2, "two seconds with the ball on the plunger and nothing pressed")
		-- a button held is not a button changed: a cradle held for ever is idle too
		t.truthy(Replay.feed(r, 1, { 480, 720, 1, BTN.LEFT }))
		t.near(Replay.idleSeconds(r), 239 / 240, 1e-9)
		t.truthy(Replay.feed(r, 1, { 720, 960 }))
		t.near(Replay.idleSeconds(r), 479 / 240, 1e-9)
		t.truthy(Replay.feed(r, 1, { 960, 1200, 240, 0 }))
		t.eq(Replay.idleSeconds(r), 0, "let go on the last tick")
		-- the next ball starts the count again
		t.truthy(Replay.feed(r, 1, { 1200, 1440 }))
		Replay.skip(r)
		t.eq(r.m.up, 2)
		t.eq(Replay.idleSeconds(r), 0)
		local rules = Rules.forTable("pinball_acorn")
		local view = rules.view :: (any) -> { [string]: any }
		t.eq(view(r).idle, 0)
		t.eq(view(r).tick, r.tick, "the view's tick is where the next segment must start")
	end)

	t.test(
		"sum: one number of the state; a segment that comes with another machine's sum is taken, and marked as drift",
		function()
			local id = "pinball_rodent"
			local tbl = Tables.need(id)
			local live, server = Replay.new(id, 21, 1), Replay.new(id, 21, 1)
			t.eq(Replay.sum(live), Replay.sum(server))
			local rec = Replay.recorder(live)
			local bot = Bot.new(2, 5)
			local sums: { [number]: boolean } = {}
			local distinct, sent = 0, 0
			for _ = 1, 240 * 30 do
				local seg = Replay.live(live, rec, Bot.step(bot, tbl, live.m))
				if seg then
					local sum = Replay.sum(live)
					t.truthy(sum % 1 == 0 and sum >= 0 and sum < 2 ^ 31, "a whole number that travels as it is")
					t.truthy(Replay.feed(server, 1, seg, nil, sum))
					t.eq(Replay.sum(server), sum)
					sent += 1
					if not sums[sum] then
						sums[sum] = true
						distinct += 1
					end
				end
			end
			t.falsy(server.drift, "the same model on the same log: no drift, ever")
			t.truthy(distinct > sent * 0.9, `the sum moves with the game ({distinct} different in {sent})`)
			-- a machine that has come apart (here: its ball moved a hair) says so with its next segment
			-- (a copy of the server's replay stands exactly where the last segment ended)
			t.truthy(not Replay.over(server), "the game is still on after thirty seconds")
			local broken = Replay.clone(server)
			local brokenRec = Replay.recorder(broken)
			brokenRec.held = broken.held
			local ball = broken.m.phys.balls[1]
			if ball then
				ball.x += 0.001
			else
				broken.m.scores[1] += 10
			end
			local seg: InputLog.Segment? = nil
			while seg == nil do
				seg = Replay.live(broken, brokenRec, 0)
			end
			t.truthy(Replay.feed(server, 1, seg, nil, Replay.sum(broken)), "the segment is taken all the same")
			t.truthy(server.drift, "and the replay is marked: the player's machine is sent a copy to carry on from")
			-- through the rules: the sum is the fourth argument of "log", and the view says drift
			local rules = Rules.forTable(id)
			local state = rules.init(1, 21)
			local view = rules.view :: (any) -> { [string]: any }
			local fresh = Replay.new(id, 21, 1)
			local freshRec = Replay.recorder(fresh)
			local first: InputLog.Segment? = nil
			while first == nil do
				first = Replay.live(fresh, freshRec, 0)
			end
			local from, to, packed = InputLog.pack(first)
			t.truthy(rules.input(state, 1, "log", { from, to, packed, Replay.sum(fresh) }))
			t.eq(view(state).drift, false)
			local second: InputLog.Segment? = nil
			while second == nil do
				second = Replay.live(fresh, freshRec, 0)
			end
			from, to, packed = InputLog.pack(second)
			t.truthy(rules.input(state, 1, "log", { from, to, packed, Replay.sum(fresh) + 1 }))
			t.eq(view(state).drift, true)
		end
	)

	t.test(
		"PIN-P6: on the wire a segment is fromTick, toTick and one string of at most 200 characters, and opens again",
		function()
			-- every button and the analogue plunger, at the first and the last tick a segment can hold
			local seg =
				{ 7200, 7200 + InputLog.MAX_TICKS, 1, InputLog.BUTTONS_MAX, 2, 0, 500, BTN.LEFT, InputLog.MAX_TICKS, 5 }
			local from, to, packed = InputLog.pack(seg)
			t.eq(from, 7200)
			t.eq(to, 7200 + InputLog.MAX_TICKS)
			t.eq(#packed, 16, "four characters a change")
			t.truthy(string.match(packed, "^[%w%-_]*$"), `plain characters only: {packed}`)
			t.deepEq(InputLog.unpack(from, to, packed), seg)
			t.truthy(InputLog.check(InputLog.unpack(from, to, packed), 7200))
			-- nothing held and nothing changed: an empty string
			local _, _, none = InputLog.pack({ 0, 24 })
			t.eq(none, "")
			t.deepEq(InputLog.unpack(0, 24, ""), { 0, 24 })
			-- the most a message holds is more than the player's machine ever puts in one
			t.eq(InputLog.WIRE_CHANGES * 4, InputLog.WIRE_CHARS)
			t.truthy(InputLog.WIRE_TICKS <= InputLog.WIRE_CHANGES, "a change every tick of a segment still fits")
			local full = { 0, 60 }
			for i = 1, InputLog.WIRE_CHANGES do
				table.insert(full, i)
				table.insert(full, i % 2)
			end
			local _, _, long = InputLog.pack(full)
			t.eq(#long, InputLog.WIRE_CHARS)
			t.deepEq(InputLog.unpack(0, 60, long), full)
			table.insert(full, 51)
			table.insert(full, 0)
			t.fails(function()
				InputLog.pack(full)
			end, "too many changes")
			-- what is not a packed segment is nil, never an error; what unpacks still has to pass check()
			for what, bad in
				{
					["a number"] = 5,
					["not a multiple of four"] = "AAA",
					["another alphabet"] = "AA A",
					["a high first character"] = "QAAA",
					["too long"] = string.rep("A", InputLog.WIRE_CHARS + 4),
				} :: { [string]: any }
			do
				t.eq(InputLog.unpack(0, 24, bad), nil, what)
			end
			t.eq(InputLog.unpack("0", 24, ""), nil)
			t.eq(InputLog.unpack(0, nil, ""), nil)
			local zero = InputLog.unpack(0, 24, "AAAA")
			t.deepEq(zero, { 0, 24, 0, 0 }, "offset 0 unpacks")
			t.falsy(InputLog.check(zero, 0), "and is refused by check()")
		end
	)

	t.test(
		"PIN-P6: however the buttons are worked, the player's machine never cuts a segment too big for one message",
		function()
			local id = "pinball_acorn"
			local live, server = Replay.new(id, 9, 1), Replay.new(id, 9, 1)
			local rec = Replay.recorder(live)
			local rng = 12345
			local cuts = 0
			local sent = ""
			for tick = 1, 240 * 20 do
				-- a different word of buttons on every tick: flippers, nudges, an analogue plunger
				rng = (rng * 69069 + 1) % 4294967296
				local buttons = Machine.buttons(rng // 65536 % 64, (tick % 32) / 31)
				local seg = Replay.live(live, rec, buttons)
				if seg then
					cuts += 1
					t.truthy(InputLog.changes(seg) <= InputLog.WIRE_CHANGES)
					local from, to, packed = InputLog.pack(seg)
					t.truthy(#packed <= InputLog.WIRE_CHARS)
					local back = InputLog.unpack(from, to, packed)
					assert(back, "the segment did not open again")
					local ok, why = Replay.feed(server, live.m.up, back)
					t.truthy(ok, why)
					sent = digest(live.m)
				end
				if Replay.over(live) then
					break
				end
			end
			t.truthy(cuts >= 100, `{cuts} segments`)
			t.eq(digest(server.m), sent, "and the server has the game as it stood at the last segment")
		end
	)

	t.test(
		"watchers: a copy of the replay taken in mid-ball, fed the segments that follow, is the same game to the end",
		function()
			local id = "pinball_space"
			local server = Replay.new(id, 77, 2)
			local late: Replay.State? = nil
			local fed = 0
			local live = playLive(id, 77, 2, 2, function(seat, seg)
				local from, to, packed = InputLog.pack(seg)
				local copy = InputLog.unpack(from, to, packed)
				assert(copy, "the segment did not open again")
				t.truthy(Replay.feed(server, seat, copy))
				if late then
					t.truthy(Replay.feed(late, seat, table.clone(seg)))
				end
				fed += 1
				if fed == 150 then
					-- somebody walks up fifteen seconds into the game: the server sends them its replay as it is
					late = Replay.clone(server)
					t.eq(digest(late), digest(server))
					t.truthy(#server.m.phys.balls > 0 or server.m.phase ~= PHASE.PLAY)
				end
			end)
			assert(late, "the game was long enough to walk up to")
			t.truthy(Replay.over(late))
			t.eq(digest(late), digest(server), "the latecomer's replay is the server's")
			t.eq(digest(late.m), digest(live.m), "and the player's own machine")
			-- the copy is its own: feeding one does not move the other
			local a = Replay.new(id, 1, 1)
			local b = Replay.clone(a)
			t.truthy(Replay.feed(a, 1, { 0, 240 }))
			t.eq(b.tick, 0)
			t.eq(b.m.phys.tick, 0)
		end
	)

	t.test(
		"skip: an abandoned ball is played out dead and the next ball stands on the plunger, the same in every replay",
		function()
			local a = Replay.new("pinball_rodent", 9, 2)
			local b = Replay.new("pinball_rodent", 9, 2)
			t.truthy(Replay.feed(a, 1, { 0, 300, 1, BTN.PLUNGE, 250, 0 }))
			t.truthy(Replay.feed(b, 1, { 0, 300, 1, BTN.PLUNGE, 250, 0 }))
			Replay.skip(a)
			Replay.skip(b)
			t.eq(a.m.up, 2)
			t.eq(a.m.phase, PHASE.PLAY)
			t.eq(a.m.ballTicks, 0)
			t.eq(#a.m.phys.balls, 1)
			t.eq(a.tick, b.tick)
			t.eq(digest(a.m), digest(b.m))
			t.truthy(a.tick - 300 <= Machine.FORFEIT_TICKS + 4000)
			-- and the next player's log goes on from there
			t.truthy(Replay.feed(a, 2, { a.tick, a.tick + 48 }))
		end
	)

	t.test("the rate guard: a score that climbs faster than the table allows marks the replay suspect", function()
		local r = Replay.new("pinball_acorn", 1, 1)
		t.truthy(Replay.feed(r, 1, { 0, 240 }))
		t.falsy(r.suspect)
		r.m.scores[1] += Tables.need("pinball_acorn").sheet.maxScorePerSec * 6
		t.truthy(Replay.feed(r, 1, { 240, 480 }))
		t.truthy(r.suspect)
	end)

	t.test("Stream: a frame holds everything a drawer needs, and never anything in thin air", function()
		for _, id in Tables.IDS do
			local tbl = Tables.need(id)
			local m = Machine.new(tbl, 5, 2)
			local bot = Bot.new(2, 5)
			local out: { number } = {}
			local frame: Stream.Frame? = nil
			for tick = 1, 240 * 25 do
				Machine.step(tbl, m, Bot.step(bot, tbl, m), out)
				if tick % 4 == 0 then
					local f = Stream.read(tbl, m, frame)
					frame = f
					t.eq(f.tick, m.phys.tick)
					t.eq(#f.balls, f.nBalls * 3)
					t.eq(#f.flippers, 2)
					t.eq(#f.lamps, #tbl.def.lamps)
					t.truthy(f.pull >= 0 and f.pull <= 1)
					for i = 1, f.nBalls do
						local x, y, h = f.balls[i * 3 - 2], f.balls[i * 3 - 1], f.balls[i * 3]
						-- on the playfield, inside the cabinet (C10: nothing is drawn outside its table)
						t.truthy(x > 0 and x < Layout.WIDTH, `{id}: ball x {x}`)
						t.truthy(y > 0 and y < Layout.LENGTH, `{id}: ball y {y}`)
						t.truthy(h >= 0 and h < 0.5, `{id}: ball height {h}`)
						local across, _, along = Stream.ballAt(f, i)
						t.truthy(
							math.abs(across) < Layout.WIDTH / 2 and math.abs(along) < Layout.LENGTH / 2 + 0.1,
							`{id}: {across} {along} from {x} {y} {h}`
						)
					end
					for i = 1, 2 do
						t.truthy(f.flippers[i] >= tbl.c.frest[i] - 1e-9 and f.flippers[i] <= tbl.c.fup[i] + 1e-9)
					end
				end
				table.clear(out)
			end
		end
	end)

	t.test("Stream: a frame packs into whole numbers and opens again to a thousandth of a stud", function()
		local tbl = Tables.need("pinball_acorn")
		local m = Machine.new(tbl, 5, 3)
		local bot = Bot.new(3, 9)
		local out: { number } = {}
		for tick = 1, 240 * 20 do
			Machine.step(tbl, m, Bot.step(bot, tbl, m), out)
			if tick % 97 == 0 then
				local f = Stream.read(tbl, m)
				local packed = Stream.pack(tbl, f)
				t.truthy(#packed < 40, `a frame is {#packed} numbers`)
				for _, v in packed do
					t.truthy(v % 1 == 0 and v >= 0, "whole numbers")
				end
				local g = Stream.unpack(tbl, packed)
				t.eq(g.tick, f.tick)
				t.eq(g.phase, f.phase)
				t.eq(g.up, f.up)
				t.eq(g.ball, f.ball)
				t.eq(g.say, f.say)
				t.eq(g.saveOn, f.saveOn)
				t.eq(g.tilted, f.tilted)
				t.eq(g.nBalls, f.nBalls)
				t.deepEq(g.scores, f.scores)
				t.deepEq(g.lamps, f.lamps)
				t.deepEq(g.drops, f.drops)
				for i = 1, #f.balls do
					t.near(g.balls[i], f.balls[i], 0.0006)
				end
				for i = 1, 2 do
					t.near(g.flippers[i], f.flippers[i], 0.0001)
				end
				t.near(g.pull, f.pull, 0.003)
				t.near(g.spin[1], f.spin[1], 0.005)
			end
			table.clear(out)
		end
	end)

	t.test("Stream.blend: the frame between two frames moves what moves and never slides a ball that jumped", function()
		local tbl = Tables.need("pinball_acorn")
		local m = Machine.new(tbl, 5, 1)
		local a = Stream.read(tbl, m)
		for _ = 1, 100 do
			Machine.step(tbl, m, BTN.PLUNGE + BTN.LEFT, {})
		end
		local b = Stream.read(tbl, m)
		local mid = Stream.blend(a, b, 0.5)
		t.near(mid.pull, (a.pull + b.pull) / 2, 1e-9)
		t.near(mid.flippers[1], (a.flippers[1] + b.flippers[1]) / 2, 1e-9)
		t.eq(mid.flippers[2], b.flippers[2])
		t.eq(mid.tick, b.tick)
		t.deepEq(Stream.blend(a, b, 1).balls, b.balls)
		-- a ball that is somewhere else entirely is shown where it is, not half way
		local c = Stream.read(tbl, m)
		c.balls[1], c.balls[2] = 0.5, 3.0
		local jumped = Stream.blend(b, c, 0.5)
		t.eq(jumped.balls[1], 0.5)
		t.eq(jumped.balls[2], 3.0)
		-- two balls: the first jumps (fed to the plunger), the second rolls on and is still blended (each ball
		-- is judged by itself, not every ball after the first that jumped)
		local two0, two1 = Stream.read(tbl, m), Stream.read(tbl, m)
		two0.nBalls, two1.nBalls = 2, 2
		two0.balls = { 1.0, 2.0, 0, 3.0, 4.0, 0 }
		two1.balls = { 4.5, 0.5, 0, 3.1, 4.2, 0 }
		local half = Stream.blend(two0, two1, 0.5)
		t.eq(half.balls[1], 4.5, "the jumped ball is where it is")
		t.near(half.balls[4], 3.05, 1e-9, "the other ball is half way")
		t.near(half.balls[5], 4.1, 1e-9)

		-- the spinner turns the short way round
		a.spin[1], b.spin[1] = 0.9, 0.1
		t.near(Stream.blend(a, b, 0.5).spin[1], 0.0, 1e-9)
		t.eq(Physics.HZ / 60, 4, "four ticks to a 60 Hz frame")
	end)
end
