--!strict
-- Detector: a vehicle moves further in one client frame than its speed allows.
--   position_jump       a hop
--   teleport_unflagged  a hop of a car length or more, with no teleport flag on the pose being drawn:
--                       the car streaks across the street (a wrap interpolated as if it were driving)
--   teleport_flagged    the same distance but the pose is a snap the server asked for (a wrap, a
--                       dispatch): correct replication, still a car vanishing here and reappearing
--                       there. Counted as one pop (magnitude 1, like appear / disappear: every one is
--                       reported, none outranks a real fault); detail.distance has the length and
--                       detail.insideFrom / insideTo say how central both ends are
-- `origin` says where it comes from: "sim" when the server's own state jumped around the instant being
-- drawn (detail.truth: "flagged teleport" or "unflagged jump"), "stream" when the truth drove smoothly
-- and only the reconstruction hopped.
local Detect = require("../lib/Detect")

local def: Detect.Def = {
	name = "jumps",
	kinds = {
		position_jump = "the car hops: it moves further in one frame than its speed allows",
		teleport_unflagged = "the car streaks or snaps a car length or more in one frame, and its pose carries no teleport flag",
		teleport_flagged = "the car vanishes and reappears elsewhere in one frame (a snap the server flagged: a wrap, a dispatch)",
	},
	thresholds = {
		{
			key = "factor",
			value = 2.5,
			unit = "x",
			why = "a frame's step may be this many times speed x dt: between two sends the pose moves at their average speed, so a car that is braking or pulling away legitimately outruns the speed on the wire",
		},
		{
			key = "slack",
			value = 0.5,
			unit = "studs",
			why = "plus half a stud, less than a wheel's width: a smaller hop is not seen",
		},
		{
			key = "teleport",
			value = 10,
			unit = "studs",
			why = "a step of a car length (a sedan is 11.1 st) in one frame is a teleport, not a hop",
		},
		{
			key = "window",
			value = 0.12,
			unit = "s",
			why = "the truth is searched this far either side of the instant being drawn for a jump of its own: one send interval (0.067 s) plus a tick (0.033 s) and margin",
		},
	},
	new = function(ctx: Detect.Ctx): Detect.Hooks
		local th = ctx.th
		return {
			frame = function(frame: Detect.Frame)
				for _, id in frame.ids do
					local s, p = frame.v[id], frame.pv[id]
					if p and s.vis and p.vis then
						local d = math.sqrt((s.x - p.x) ^ 2 + (s.z - p.z) ^ 2)
						local speed = math.max(s.speed, p.speed)
						local limit = th.factor * speed * frame.dt + th.slack
						if d > limit then
							local truth, origin = "unknown", nil
							if frame.ref then
								local w = ctx.truth:window(id, frame.ref - th.window, frame.ref + th.window)
								if w.flagged > 0 then
									truth, origin = "flagged teleport", "sim"
								elseif w.jump > 0 then
									truth, origin = "unflagged jump", "sim"
								else
									truth, origin = "continuous", "stream"
								end
							end
							local detail = {
								origin = origin,
								truth = truth,
								from = { p.x, p.z },
								to = { s.x, s.z },
								insideFrom = Detect.inside(p.x, p.z),
								insideTo = Detect.inside(s.x, s.z),
								wireSpeed = speed,
								distance = d,
							}
							if s.snap and d >= th.teleport then
								ctx.flag("teleport_flagged", frame, s, 1, 1, "pop", detail)
							elseif d >= th.teleport then
								ctx.flag("teleport_unflagged", frame, s, d, limit, "studs", detail)
							else
								ctx.flag("position_jump", frame, s, d, limit, "studs", detail)
							end
						end
					end
				end
			end,
		}
	end,
}

return def
