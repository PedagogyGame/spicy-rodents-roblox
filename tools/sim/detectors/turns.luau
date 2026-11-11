--!strict
-- Detector: heading.
--   yaw_jump        the car's heading turns further in one frame than a vehicle can steer
--   sideways_slide  the car travels in a direction its nose does not point (it crabs or slides)
--   reverse_travel  the car travels backwards faster than a parking manoeuvre (the trolley is
--                   double-ended and exempt; the event sedans back into their spaces at 0.7 st/s)
-- The direction of travel is measured over at least `minMove` studs of seen motion, so a creeping car's
-- rounding does not swing it. `origin` is "sim" when the server's own heading did it (the true heading
-- stepped that fast, or the seen pose matches the true pose being drawn), else "stream".
local Detect = require("../lib/Detect")

local REVERSIBLE = { trolley = true } -- traffic.md §5.4: the trolley shuttles, its body never rotates

local def: Detect.Def = {
	name = "turns",
	mergeGap = 1,
	kinds = {
		yaw_jump = "the car's nose snaps round: its heading turns faster than a vehicle can steer",
		sideways_slide = "the car slides or crabs: it travels in a direction its nose does not point",
		reverse_travel = "the car drives backwards",
	},
	thresholds = {
		{
			key = "rate",
			value = 3.5,
			unit = "rad/s",
			why = "200 degrees a second: the tightest real turn in the fleet, the ice cream van's U-turn (radius about 14 st at up to 19 st/s), is 1.4 rad/s",
		},
		{
			key = "slack",
			value = 0.03,
			unit = "rad",
			why = "the yaw byte on the wire is 1.4 degrees (0.0245 rad): one step of it is not a snap",
		},
		{
			key = "slide",
			value = 0.3,
			unit = "rad",
			why = "17 degrees between nose and travel: wheels do not slip that far; the yaw byte and the chord of an interpolated turn stay under 6 degrees",
		},
		{
			key = "minMove",
			value = 1.5,
			unit = "studs",
			why = "the direction of travel is taken over at least this much seen motion",
		},
		{
			key = "reverseSpeed",
			value = 3,
			unit = "st/s",
			why = "backing up slower than a walk is parking (the event sedans reverse into their spaces at 0.7 st/s, traffic.md §5.11); faster is a car driving backwards",
		},
		{
			key = "window",
			value = 0.12,
			unit = "s",
			why = "the truth is searched this far either side of the instant being drawn for a heading step of its own",
		},
	},
	new = function(ctx: Detect.Ctx): Detect.Hooks
		local th = ctx.th
		local anchor: { [number]: { x: number, z: number, t: number } } = {}
		return {
			frame = function(frame: Detect.Frame)
				for _, id in frame.ids do
					local s, p = frame.v[id], frame.pv[id]
					if not (p and s.vis and p.vis) or s.snap then
						anchor[id] = nil
						continue
					end
					local w = nil
					if frame.ref then
						w = ctx.truth:window(id, frame.ref - th.window, frame.ref + th.window)
					end
					-- yaw_jump
					local turn = math.abs(Detect.wrapAngle(s.yaw - p.yaw))
					local limit = th.rate * frame.dt + th.slack
					if turn > limit then
						local origin = nil
						if w then
							origin = if w.yawStep > th.rate / 30 + th.slack
									or w.flagged > 0
									or w.jump > 0
								then "sim"
								else "stream"
						end
						ctx.flag("yaw_jump", frame, s, turn, limit, "rad", {
							origin = origin,
							from = p.yaw,
							to = s.yaw,
							rate = turn / math.max(frame.dt, 1e-6),
							trueYawStep = if w then w.yawStep else nil,
						})
					end
					-- sideways_slide / reverse_travel: nose against travel
					local a = anchor[id]
					local step = math.sqrt((s.x - p.x) ^ 2 + (s.z - p.z) ^ 2)
					if a == nil or step > 2.5 * math.max(s.speed, p.speed) * frame.dt + 3 then
						anchor[id] = { x = s.x, z = s.z, t = frame.t } -- a jump: start measuring again from here
						continue
					end
					local dx, dz = s.x - a.x, s.z - a.z
					if dx * dx + dz * dz >= th.minMove * th.minMove then
						local off = math.abs(Detect.wrapAngle(math.atan2(dx, dz) - s.yaw))
						-- the server's own doing when the seen pose is the true pose being drawn
						local origin = nil
						if s.rok then
							local same = math.abs(Detect.wrapAngle(s.yaw - s.ryaw)) < 0.1
								and (s.x - s.rx) ^ 2 + (s.z - s.rz) ^ 2 < 2.25
							origin = if same then "sim" else "stream"
						end
						local moved = math.sqrt(dx * dx + dz * dz)
						local speed = moved / math.max(frame.t - a.t, 1e-6)
						local detail = {
							origin = origin,
							travel = math.atan2(dx, dz),
							yaw = s.yaw,
							moved = moved,
							speed = speed,
						}
						local info = ctx.vehicles[id]
						if off > math.pi - th.slide then
							if speed > th.reverseSpeed and not (info and REVERSIBLE[info.class]) then
								ctx.flag("reverse_travel", frame, s, math.deg(off), 90, "deg", detail)
							end
						elseif off > th.slide then
							ctx.flag(
								"sideways_slide",
								frame,
								s,
								math.deg(math.min(off, math.pi - off)),
								math.deg(th.slide),
								"deg",
								detail
							)
						end
						anchor[id] = { x = s.x, z = s.z, t = frame.t }
					end
				end
			end,
		}
	end,
}

return def
