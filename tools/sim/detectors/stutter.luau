--!strict
-- Detector: uneven motion.
--   speed_stutter  the speed the player sees in a frame (distance moved / frame time) is not a speed the
--                  car really had around the instant being drawn: it surges, lags, or freezes
--                  (detail.direction: "fast", "slow" or "frozen")
--   accel_spike    the seen speed changes abruptly from one frame to the next
-- speed_stutter is judged against the truth, so a car that really brakes hard does not count; accel_spike
-- is absolute, and `origin` tells whether the truth changed speed that fast itself ("sim") or not ("stream").
-- Frames that jumps.luau reports (a step beyond its limit) are left to it.
local Detect = require("../lib/Detect")

local def: Detect.Def = {
	name = "stutter",
	kinds = {
		speed_stutter = "the car surges, drags or freezes: its speed on screen is not one it really had at that moment",
		accel_spike = "the car's speed on screen changes abruptly between two frames (a jerk)",
	},
	thresholds = {
		{
			key = "relative",
			value = 0.2,
			unit = "fraction",
			why = "a seen speed within 20 % of the true speeds around that instant reads as even; a send that carries one tick more or less than its stamp claims is off by 25 to 50 %",
		},
		{
			key = "absolute",
			value = 1.5,
			unit = "st/s",
			why = "plus 1.5 st/s (0.025 st a frame at 60 fps), so a crawling car's rounding is not a stutter",
		},
		{
			key = "window",
			value = 0.1,
			unit = "s",
			why = "the true speeds are taken this far either side of the instant being drawn: one send interval plus one tick, the span one interpolation step averages over",
		},
		{
			key = "jumpFactor",
			value = 2.5,
			unit = "x",
			why = "a step beyond jumpFactor x speed x dt + jumpSlack is a jump (jumps.luau), not a stutter",
		},
		{ key = "jumpSlack", value = 0.5, unit = "studs", why = "see jumpFactor" },
		{
			key = "accel",
			value = 80,
			unit = "st/s2",
			why = "a speed change between two frames, spread over one send interval (the finest the stream resolves), beyond 80 st/s2 (22 m/s2, over 2 g): no road vehicle does that; smooth braking in the fleet is 25 to 30 st/s2",
		},
	},
	new = function(ctx: Detect.Ctx): Detect.Hooks
		local th = ctx.th
		local last: { [number]: { v: number, frame: number } } = {}
		return {
			frame = function(frame: Detect.Frame)
				for _, id in frame.ids do
					local s, p = frame.v[id], frame.pv[id]
					if not (p and s.vis and p.vis) or s.snap or frame.dt <= 0 then
						last[id] = nil
						continue
					end
					local d = math.sqrt((s.x - p.x) ^ 2 + (s.z - p.z) ^ 2)
					if d > th.jumpFactor * math.max(s.speed, p.speed) * frame.dt + th.jumpSlack then
						last[id] = nil
						continue
					end
					local v = d / frame.dt
					local w = nil
					if frame.ref and s.rok then
						w = ctx.truth:window(id, frame.ref - th.window, frame.ref + th.window)
						if w.flagged > 0 or w.jump > 0 or w.visibility then
							w = nil -- a true teleport: nothing to compare a speed with
						end
					end
					if w then
						local over = v - w.hi
						local under = w.lo - v
						if over > th.relative * w.hi + th.absolute then
							ctx.flag("speed_stutter", frame, s, over, th.relative * w.hi + th.absolute, "st/s", {
								direction = "fast",
								seenSpeed = v,
								trueLo = w.lo,
								trueHi = w.hi,
								origin = "stream",
							})
						elseif under > th.relative * w.lo + th.absolute then
							ctx.flag("speed_stutter", frame, s, under, th.relative * w.lo + th.absolute, "st/s", {
								direction = if v < 0.05 * w.lo then "frozen" else "slow",
								seenSpeed = v,
								trueLo = w.lo,
								trueHi = w.hi,
								origin = "stream",
							})
						end
					end
					local before = last[id]
					if before and before.frame == frame.i - 1 then
						local change = math.abs(v - before.v)
						local accel = change / math.max(frame.dt, 1 / 15)
						if accel > th.accel then
							ctx.flag("accel_spike", frame, s, accel, th.accel, "st/s2", {
								from = before.v,
								to = v,
								trueLo = if w then w.lo else nil,
								trueHi = if w then w.hi else nil,
								origin = if w == nil
									then nil
									elseif (w.hi - w.lo) >= 0.5 * change then "sim"
									else "stream",
							})
						end
					end
					last[id] = { v = v, frame = frame.i }
				end
			end,
		}
	end,
}

return def
