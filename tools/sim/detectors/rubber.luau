--!strict
-- Detector: the pose on screen against the truth it is meant to show.
--   rubber_band  the drawn car is away from where the car truly was at the instant the frame is drawing
-- The client draws the past on purpose (Ghost.DELAY behind the newest send, plus the trip over the
-- network); that lag is not an error and is taken out here: the reference is the true pose at the
-- server-clock instant `frame.ref` (the client clock minus the delay minus the stamp clock's offset).
-- What is left is what the reconstruction got wrong: a car carried past its stop by extrapolation, held
-- back and then released, dragged along a teleport, or out of step with its stamps.
-- detail.along / detail.across split the error along the true heading (positive: drawn ahead) and
-- sideways; the summary's "drawn pose behind the server's pose" line has the plain lag.
local Detect = require("../lib/Detect")

local def: Detect.Def = {
	name = "rubber",
	kinds = {
		rubber_band = "the car is drawn away from where it really was, then pulled back (rubber-banding)",
	},
	thresholds = {
		{
			key = "base",
			value = 1.5,
			unit = "studs",
			why = "a stud and a half: about a wheel's diameter, the smallest pull-back that reads as one",
		},
		{
			key = "tick",
			value = 1 / 30,
			unit = "s",
			why = "plus the distance driven in one simulation tick: a send can carry a state up to one tick older than its stamp",
		},
	},
	new = function(ctx: Detect.Ctx): Detect.Hooks
		local th = ctx.th
		return {
			frame = function(frame: Detect.Frame)
				for _, id in frame.ids do
					local s = frame.v[id]
					if s.vis and s.rok and s.rvis then
						local dx, dz = s.x - s.rx, s.z - s.rz
						local err = math.sqrt(dx * dx + dz * dz)
						local limit = th.base + s.rspeed * th.tick
						if err > limit then
							local fx, fz = math.sin(s.ryaw), math.cos(s.ryaw)
							local w = ctx.truth:window(id, (frame.ref :: number) - 0.12, (frame.ref :: number) + 0.12)
							ctx.flag("rubber_band", frame, s, err, limit, "studs", {
								along = dx * fx + dz * fz,
								across = dx * fz - dz * fx,
								origin = if w.flagged > 0 or w.jump > 0 then "sim" else "stream",
								truth = if w.flagged > 0
									then "flagged teleport"
									elseif w.jump > 0 then "unflagged jump"
									else "continuous",
							})
						end
					end
				end
			end,
		}
	end,
}

return def
