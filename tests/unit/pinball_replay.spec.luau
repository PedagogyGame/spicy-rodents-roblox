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
			["buttons"] = { 0, 48, 1, 128 },
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
				local segments, numbers = 0, 0
				local live = playLive(id, 4242, 2, 2, function(seat, seg)
					-- across the wire and back: the segment is plain numbers
					local copy = table.clone(seg)
					local ok, why = Replay.feed(server, seat, copy)
					t.truthy(ok, why)
					t.truthy(Replay.feed(watcher, seat, table.clone(seg), {}))
					segments += 1
					numbers += #seg
				end)
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
				t.truthy(segments / seconds <= 5.1, "five segments a second")
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
		"squirrel: a thump in the log is refused unless the server granted it, and each grant is good once",
		function()
			local r = Replay.new("pinball_space", 3, 1)
			local ok, why = Replay.feed(r, 1, { 0, 48, 5, BTN.THUMP, 6, 0 })
			t.falsy(ok)
			t.eq(why, "thump")
			Replay.grantThump(r)
			t.truthy(Replay.feed(r, 1, { 0, 48, 5, BTN.THUMP, 6, 0 }))
			ok = Replay.feed(r, 1, { 48, 96, 5, BTN.THUMP, 6, 0 })
			t.falsy(ok, "the grant is spent")
			-- holding the bit is one thump, not many
			Replay.grantThump(r)
			t.truthy(Replay.feed(r, 1, { 48, 96, 5, BTN.THUMP, 20, BTN.THUMP + BTN.LEFT, 30, 0 }))
		end
	)

	t.test(
		"pace: the replay knows how far it is ahead of a clock, so a server can refuse a log that outruns time",
		function()
			local r = Replay.new("pinball_acorn", 1, 1)
			t.truthy(Replay.feed(r, 1, { 0, 480 }))
			t.eq(Replay.pace(r, 2), 0)
			t.eq(Replay.pace(r, 1), 240, "a second ahead")
			t.eq(Replay.pace(r, 3), -240, "a second behind")
			t.eq(Replay.SEGMENT_TICKS, 48)
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
		-- the spinner turns the short way round
		a.spin[1], b.spin[1] = 0.9, 0.1
		t.near(Stream.blend(a, b, 0.5).spin[1], 0.0, 1e-9)
		t.eq(Physics.HZ / 60, 4, "four ticks to a 60 Hz frame")
	end)
end
