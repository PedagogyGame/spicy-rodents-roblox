--!strict
-- Detector: vehicles popping in and out.
--   appear / disappear   the vehicle is drawn in one frame and was hidden in the frame before (or the
--                        reverse): it pops into or out of existence where it stands
--   ghost_visibility     the vehicle is drawn although the truth being drawn has it hidden (or hidden
--                        although the truth shows it) for longer than a send interval explains
-- Every pop is reported: whether a player is looking is the hunter's question, and detail.inside (studs
-- inside the town's modelled rectangle, negative outside) says how central the spot is. `origin` is "sim"
-- when the server's vehicle really appeared or hid around the instant being drawn (the motorcycles, the
-- legacy ambulance, the event sedans, dispatches), "stream" when only the drawn one flickered.
local Detect = require("../lib/Detect")

local def: Detect.Def = {
	name = "visibility",
	kinds = {
		appear = "a car pops into existence",
		disappear = "a car vanishes",
		ghost_visibility = "a car is drawn where there is none, or missing where there is one",
	},
	thresholds = {
		{
			key = "window",
			value = 0.12,
			unit = "s",
			why = "the truth is searched this far either side of the instant being drawn for a real appearance (origin sim)",
		},
		{
			key = "mismatch",
			value = 0.2,
			unit = "s",
			why = "a snap to the newer snapshot shows or hides a car up to one send interval (0.067 s) early; three times that is no longer the snap",
		},
	},
	new = function(ctx: Detect.Ctx): Detect.Hooks
		local th = ctx.th
		local wrongSince: { [number]: number } = {}
		return {
			frame = function(frame: Detect.Frame)
				for _, id in frame.ids do
					local s, p = frame.v[id], frame.pv[id]
					if p and p.vis ~= s.vis then
						local origin = nil
						if frame.ref then
							local w = ctx.truth:window(id, frame.ref - th.window, frame.ref + th.window)
							origin = if w.visibility then "sim" else "stream"
						end
						-- where it stands: the pose it appears at, or the last pose it was drawn at
						local at = if s.vis then s else p
						ctx.flag(if s.vis then "appear" else "disappear", frame, at, 1, 1, "pop", {
							origin = origin,
							at = { at.x, at.z },
							inside = Detect.inside(at.x, at.z),
						})
					end
					if s.rok and s.vis ~= s.rvis then
						local since = wrongSince[id] or frame.t
						wrongSince[id] = since
						if frame.t - since > th.mismatch then
							ctx.flag("ghost_visibility", frame, s, frame.t - since, th.mismatch, "s", {
								origin = "stream",
								drawn = s.vis,
								truth = s.rvis,
							})
						end
					else
						wrongSince[id] = nil
					end
				end
			end,
		}
	end,
}

return def
