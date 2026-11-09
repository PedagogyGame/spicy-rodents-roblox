--!strict
-- Minigames/MinigameRules/Darts (brief v2 §13a: mouse aim point, timing meter for power, slight wobble; 501 and
-- cricket): regulation board scoring, the scatter from the timing meter, 501 busts and the double-out,
-- cricket marks, points and the win, turn order, and the server-resolved "throw".
local Darts = require("@shared/Minigames/MinigameRules/Darts")
local Minigame = require("@shared/Minigames/Minigame")
local Rng = require("@shared/Util/Rng")

-- a point (mm) in the middle of a segment's ring: number n, ring radius r
local function at(n: number, r: number): (number, number)
	local idx = table.find(Darts.ORDER, n) :: number
	local a = math.rad((idx - 1) * 18)
	return r * math.sin(a), r * math.cos(a)
end

return function(t)
	t.test("contract and board: 20 at the top, 6 on the right, 3 at the bottom, 11 on the left", function()
		t.truthy(Minigame.check(Darts))
		t.eq(Darts.scoreAt(0, 140).number, 20)
		t.eq(Darts.scoreAt(140, 0).number, 6)
		t.eq(Darts.scoreAt(0, -140).number, 3)
		t.eq(Darts.scoreAt(-140, 0).number, 11)
		t.eq(Darts.scoreAt(0, 0).points, 50)
		t.eq(Darts.scoreAt(0, 0).ring, "bull")
		t.eq(Darts.scoreAt(10, 0).points, 25)
		t.eq(Darts.scoreAt(0, 103).points, 60) -- T20
		t.eq(Darts.scoreAt(0, 166).points, 40) -- D20
		t.eq(Darts.scoreAt(0, 175).ring, "miss")
		local x, y = at(19, 103)
		t.eq(Darts.scoreAt(x, y).points, 57)
		x, y = at(5, 50)
		t.eq(Darts.scoreAt(x, y).points, 5)
		-- every segment once around the board
		for i, n in Darts.ORDER do
			local a = math.rad((i - 1) * 18)
			t.eq(Darts.scoreAt(130 * math.sin(a), 130 * math.cos(a)).number, n, `segment {i}`)
		end
	end)

	t.test("timing: the sweet spot groups tightly; a soft throw drops low, a hard one flies high", function()
		local rng = Rng.new(7)
		local sum2 = 0
		for _ = 1, 400 do
			local x, y = Darts.resolve(rng, 0, 0, 0.5)
			sum2 += x * x + y * y
		end
		local rms = math.sqrt(sum2 / 400)
		t.truthy(rms < 7, `sweet-spot spread {rms} mm`)
		local lowSum, highSum = 0, 0
		for _ = 1, 200 do
			local _, y1 = Darts.resolve(rng, 0, 0, 0.15)
			local _, y2 = Darts.resolve(rng, 0, 0, 0.9)
			lowSum += y1
			highSum += y2
		end
		t.truthy(lowSum / 200 < -25, "soft throw lands low")
		t.truthy(highSum / 200 > 25, "hard throw lands high")
		-- wobble and meter are bounded and pure
		for k = 0, 50 do
			local wx, wy = Darts.wobble(k * 0.13)
			t.truthy(math.abs(wx) <= Darts.WOBBLE_MM and math.abs(wy) <= Darts.WOBBLE_MM)
			local m = Darts.meter(k * 0.11)
			t.truthy(m >= 0 and m <= 1)
		end
		t.near(Darts.meter(Darts.METER_PERIOD), 1, 1e-9)
		t.near(Darts.meter(Darts.METER_PERIOD * 2), 0, 1e-9)
	end)

	t.test("501: three darts a turn, bust restores the turn's start, checkout needs a double", function()
		local s = Darts.init(2, 1)
		t.eq(s.mode, "501")
		local x, y = at(20, 103) -- T20
		Darts.throwAt(s, x, y)
		Darts.throwAt(s, x, y)
		t.eq(s.players[1].score, 381)
		t.eq(Darts.turn(s), 1)
		Darts.throwAt(s, x, y)
		t.eq(s.players[1].score, 321)
		t.eq(Darts.turn(s), 2)
		t.deepEq(s.players[1].history, { 180 })
		-- seat 2 throws three misses
		for _ = 1, 3 do
			Darts.throwAt(s, 999, 999)
		end
		t.eq(s.players[2].score, 501)
		t.eq(Darts.turn(s), 1)
		-- set seat 1 to 32 left: a single 16 leaves 16, then D8 checks out
		s.players[1].score = 32
		s.players[1].turnStart = 32
		local sx, sy = at(16, 50)
		local _, ev = Darts.throwAt(s, sx, sy)
		t.eq(ev, "scored")
		t.eq(s.players[1].score, 16)
		local dx, dy = at(8, 166)
		local hit, ev2 = Darts.throwAt(s, dx, dy)
		t.eq(hit.points, 16)
		t.eq(ev2, "checkout")
		t.truthy(s.done)
		t.eq(s.winner, 1)
		t.eq((Darts.result(s) :: any).winner, 1)
	end)

	t.test("501 busts: below zero, one left, zero on a single; the turn ends at once", function()
		local s = Darts.init(2, 1)
		s.players[1].score = 20
		s.players[1].turnStart = 20
		local x, y = at(20, 103) -- 60: below zero
		local _, ev = Darts.throwAt(s, x, y)
		t.eq(ev, "bust")
		t.eq(s.players[1].score, 20)
		t.eq(Darts.turn(s), 2)
		for _ = 1, 3 do
			Darts.throwAt(s, 999, 999)
		end
		local ox, oy = at(19, 50) -- 19 leaves 1: bust
		_, ev = Darts.throwAt(s, ox, oy)
		t.eq(ev, "bust")
		t.eq(s.players[1].score, 20)
		for _ = 1, 3 do
			Darts.throwAt(s, 999, 999)
		end
		local sx, sy = at(20, 50) -- single 20 to zero: not a double
		_, ev = Darts.throwAt(s, sx, sy)
		t.eq(ev, "bust")
		t.falsy(s.done)
		-- the bull is a double
		for _ = 1, 3 do
			Darts.throwAt(s, 999, 999)
		end
		s.players[1].score = 50
		s.players[1].turnStart = 50
		_, ev = Darts.throwAt(s, 0, 0)
		t.eq(ev, "checkout")
	end)

	t.test("cricket: marks close numbers, extra marks score while a rival is open, closing all wins", function()
		local s = Darts.init(2, 1)
		t.truthy(Darts.setMode(s, "cricket"))
		t.eq(s.players[1].score, 0)
		local x, y = at(20, 103) -- T20
		local _, ev = Darts.throwAt(s, x, y)
		t.eq(ev, "closed")
		t.eq(s.players[1].marks[20], 3)
		Darts.throwAt(s, x, y) -- three more marks: 60 points (seat 2 still open)
		t.eq(s.players[1].score, 60)
		local nx, ny = at(14, 103) -- not a cricket number
		_, ev = Darts.throwAt(s, nx, ny)
		t.eq(ev, "nothing")
		t.falsy(Darts.setMode(s, "501"), "mode locked after the first dart")
		-- seat 2 closes 20: seat 1 can no longer score on it
		Darts.throwAt(s, x, y)
		Darts.throwAt(s, 999, 999)
		Darts.throwAt(s, 999, 999)
		Darts.throwAt(s, x, y)
		t.eq(s.players[1].score, 60)
		-- seat 1 closes everything else with triples (bull: outer + inner = 3 marks)
		local function close(n: number)
			if n == 25 then
				Darts.throwAt(s, 0, 0)
				Darts.throwAt(s, 10, 0)
			else
				local tx, ty = at(n, 103)
				Darts.throwAt(s, tx, ty)
			end
		end
		for _, n in { 19, 18, 17, 16, 15, 25 } do
			if s.done then
				break
			end
			-- skip seat 2's turns with misses
			while Darts.turn(s) == 2 do
				Darts.throwAt(s, 999, 999)
			end
			close(n)
		end
		while not s.done and Darts.turn(s) == 2 do
			Darts.throwAt(s, 999, 999)
		end
		t.truthy(s.done, "seat 1 closed everything with the lead")
		t.eq(s.winner, 1)
	end)

	t.test("throw input: only the seat whose turn it is; args checked; resolved deterministically", function()
		local s = Darts.init(2, 42)
		t.falsy(Darts.input(s, 2, "throw", { 0, 103, 0.5 }))
		t.falsy(Darts.input(s, 1, "throw", { "x", 103, 0.5 }))
		t.falsy(Darts.input(s, 1, "throw", { 0 / 0, 103, 0.5 }))
		t.truthy(Darts.input(s, 1, "throw", { 0, 103, 0.5 }))
		local s2 = Darts.init(2, 42)
		Darts.input(s2, 1, "throw", { 0, 103, 0.5 })
		t.eq(s.players[1].score, s2.players[1].score)
		t.eq((s.lastHit :: any).x, (s2.lastHit :: any).x)
		-- skipTurn finishes the turn with misses
		Darts.skipTurn(s)
		t.eq(Darts.turn(s), 2)
		local v = Darts.view(s)
		t.eq(v.kind, "darts")
		t.eq(#v.seats, 2)
	end)
end
