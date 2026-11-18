--!strict
-- The kite's basic steering (Shared/Items/KiteFlight, the owner on 18 November: "quite basic"): A/D lean it across
-- the wind within a limit and it settles back when let go; W/S let out and reel in the string between its limits;
-- the old straight flight is kept at the centre; the wire's input is clamped and rate-limited both ends; the
-- client's keys (Client/UI/KiteSteer.axes) and the screen's sides.
local KiteFlight = require("@shared/Items/KiteFlight")
local KiteSteer = require("@client/UI/KiteSteer")

local function run(f: KiteFlight.Flight, secs: number, now: number): number
	local t = now
	for _ = 1, math.floor(secs / 0.1 + 0.5) do
		t += 0.1
		KiteFlight.step(f, 0.1, t)
	end
	return t
end

return function(t)
	t.test("at the wind's centre it flies where the old fixed kite flew (22 downwind, 34 up, plus the hand)", function()
		local f = KiteFlight.new()
		local dx, dy, dz = KiteFlight.offset(f, 0)
		local w = KiteFlight.WIND
		local down = dx * w[1] + dz * w[2]
		t.near(down, 22, 0.5, "downwind")
		t.near(dy, 34 + KiteFlight.HAND, 0.6, "up")
		t.near(dx * -w[2] + dz * w[1], 0, 1e-6, "no lean, no sway at t = 0")
	end)

	t.test("D leans it right of downwind, to the limit and no further; let go, it settles back", function()
		local f = KiteFlight.new()
		KiteFlight.steer(f, 1, 0, 0)
		local now = 0
		for _ = 1, 4 do
			KiteFlight.steer(f, 1, 0, now) -- (the client says it again while held)
			now = run(f, 0.5, now)
		end
		t.eq(f.lean, 1, "full lean, clamped")
		local w = KiteFlight.WIND
		local dx, dy, dz = KiteFlight.offset(f, 0)
		local right = dx * -w[2] + dz * w[1]
		local down = dx * w[1] + dz * w[2]
		t.truthy(right > 0, "to the right of a flier facing downwind")
		t.near(math.atan2(right, down), KiteFlight.MAX_LEAN, 1e-6, "the lean's limit")
		local _, dy0 = KiteFlight.offset(KiteFlight.new(), 0)
		t.truthy(dy < dy0, "lower at the edge of the wind")
		-- let go
		KiteFlight.steer(f, 0, 0, now)
		run(f, 1, now)
		t.eq(f.lean, 0, "back at the centre")
		-- and A the other way
		KiteFlight.steer(f, -1, 0, now)
		run(f, 1, now)
		t.eq(f.lean, -1)
	end)

	t.test("W lets the string out and S reels it in, between the limits; it stays where it is left", function()
		local f = KiteFlight.new()
		KiteFlight.steer(f, 0, 1, 0)
		run(f, 1, 0)
		t.near(f.length, KiteFlight.LENGTH + KiteFlight.REEL_RATE, 1e-6, "a second of W")
		local now = 1
		for _ = 1, 20 do
			KiteFlight.steer(f, 0, 1, now)
			now = run(f, 0.5, now)
		end
		t.eq(f.length, KiteFlight.MAX_LENGTH, "no further than the most string")
		KiteFlight.steer(f, 0, 0, now)
		now = run(f, 2, now)
		t.eq(f.length, KiteFlight.MAX_LENGTH, "let go, the string stays out")
		for _ = 1, 30 do
			KiteFlight.steer(f, 0, -1, now)
			now = run(f, 0.5, now)
		end
		t.eq(f.length, KiteFlight.MIN_LENGTH, "no shorter than the least")
		local dx, dy, dz = KiteFlight.offset(f, 0)
		t.near(math.sqrt(dx * dx + (dy - KiteFlight.HAND) ^ 2 + dz * dz), KiteFlight.MIN_LENGTH, 1e-6, "on its string")
	end)

	t.test("a held key the client stops saying is let go after STALE seconds", function()
		local f = KiteFlight.new()
		KiteFlight.steer(f, 1, 1, 0)
		run(f, KiteFlight.STALE + 2, 0)
		t.eq(f.lean, 0, "settled back")
		t.truthy(f.length < KiteFlight.LENGTH + KiteFlight.REEL_RATE * (KiteFlight.STALE + 0.2), "stopped letting out")
	end)

	t.test("the wire's input is clamped: nothing odd gets through", function()
		local cases = {
			{ 5, -9, 1, -1 },
			{ 0 / 0, 0.5, 0, 0.5 },
			{ math.huge, -math.huge, 1, -1 },
			{ "1", {}, 0, 0 },
			{ nil, true, 0, 0 },
		}
		for _, c in cases do
			local x, y = KiteFlight.clampSteer(c[1], c[2])
			t.eq(x, c[3])
			t.eq(y, c[4])
		end
	end)

	t.test("the server's bucket: a burst, then RATE a second; a flood is dropped", function()
		local b = KiteFlight.bucket()
		local took = 0
		for _ = 1, 50 do
			if KiteFlight.accept(b, 0) then
				took += 1
			end
		end
		t.eq(took, KiteFlight.BURST, "one instant: the burst only")
		took = 0
		for i = 1, 100 do
			if KiteFlight.accept(b, i * 0.01) then -- 100 a second for a second
				took += 1
			end
		end
		t.truthy(took <= KiteFlight.RATE + 1, `at most RATE a second (took {took})`)
	end)

	t.test("the client sends a change, says a held key again, and keeps quiet otherwise", function()
		local last = { x = 0, y = 0, at = -math.huge }
		t.falsy(KiteFlight.send(last, 0, 0, 0), "nothing held, nothing sent")
		t.truthy(KiteFlight.send(last, 1, 0, 0), "a change")
		last = { x = 1, y = 0, at = 0 }
		t.falsy(KiteFlight.send(last, -1, 0, 0.05), "not faster than RATE")
		t.truthy(KiteFlight.send(last, -1, 0, 0.11), "the change, a tenth later")
		t.falsy(KiteFlight.send(last, 1, 0, 0.3), "held, not yet RESEND")
		t.truthy(KiteFlight.send(last, 1, 0, KiteFlight.RESEND), "held: said again")
		t.falsy(KiteFlight.send({ x = 0, y = 0, at = 0 }, 0, 0, 5), "let go and quiet")
		-- RESEND is well inside STALE, so a held key is never let go by the server
		t.truthy(KiteFlight.RESEND < KiteFlight.STALE / 2)
	end)

	t.test("the keys, the stick and the touch arrows become the two axes", function()
		local x, y = KiteSteer.axes({ A = true }, 0, 0)
		t.eq(x, -1)
		t.eq(y, 0)
		x, y = KiteSteer.axes({ D = true, W = true }, 0, 0)
		t.eq(x, 1)
		t.eq(y, 1)
		x, y = KiteSteer.axes({ A = true, D = true }, 0.9, -0.9)
		t.eq(x, 1, "both keys: the stick decides")
		t.eq(y, -1)
		x, y = KiteSteer.axes({}, 0.1, -0.2)
		t.eq(x, 0, "inside the dead zone")
		t.eq(y, 0)
		x, y = KiteSteer.axes({}, 0, 0, { left = false, right = true, up = false, down = true })
		t.eq(x, 1, "touch right")
		t.eq(y, -1, "touch down reels in")
		x, y = KiteSteer.axes({ Left = true, Up = true }, 0, 0)
		t.eq(x, -1, "arrow keys")
		t.eq(y, 1)
	end)

	t.test("A is left on the screen: a camera looking back upwind swaps the sides", function()
		local w = KiteFlight.WIND
		t.eq(KiteFlight.screenSide(1, w[1], w[2]), 1, "looking downwind, past the flier at the kite")
		t.eq(KiteFlight.screenSide(1, -w[1], -w[2]), -1, "looking upwind, at the flier")
		t.eq(KiteFlight.screenSide(-1, -w[1], -w[2]), 1)
	end)
end
