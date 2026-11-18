--!strict
-- Detector: two vehicles in the same place.
--   box_overlap  the logical boxes (Traffic/Boxes: the boxes the placeholders are built to and the fatal
--                test sweeps) of two visible vehicles, as drawn, are into each other
-- One incident per pair for as long as they overlap; the magnitude is the deepest they got (the smallest
-- distance one would have to move to be clear). `origin` is "sim" when the true poses of the instant
-- being drawn overlap as well (the server put them there: a shared lane, a wrap or an appearance onto
-- another car), "stream" when only the drawn ones do (one of them is ahead of or behind its truth).
local Detect = require("../lib/Detect")

local def: Detect.Def = {
	name = "overlap",
	mergeGap = 0.5,
	kinds = {
		box_overlap = "two cars are inside each other",
	},
	thresholds = {
		{
			key = "depth",
			value = 0.3,
			unit = "studs",
			why = "bodies a third of a stud into each other: less than that is paint touching, and lanes 7.6 st apart leave wide vehicles close",
		},
		{
			key = "every",
			value = 2,
			unit = "frames",
			why = "pairs are tested on every second frame: an overlap that lasts one frame at 60 fps is not seen",
		},
	},
	new = function(ctx: Detect.Ctx): Detect.Hooks
		local th = ctx.th
		local every = math.max(1, math.floor(th.every))
		return {
			frame = function(frame: Detect.Frame)
				if frame.i % every ~= 0 then
					return
				end
				local ids = frame.ids
				for i = 1, #ids do
					local a = frame.v[ids[i]]
					if not a.vis then
						continue
					end
					local boxA = ctx.vehicles[a.id].box
					for j = i + 1, #ids do
						local b = frame.v[ids[j]]
						if not b.vis then
							continue
						end
						local boxB = ctx.vehicles[b.id].box
						local reach = (boxA.length + boxA.width + boxB.length + boxB.width) / 2
						local dx, dz = b.x - a.x, b.z - a.z
						if
							dx * dx + dz * dz > reach * reach
							or math.abs(a.y - b.y) > (boxA.height + boxB.height) / 2
						then
							continue
						end
						local depth = Detect.obbOverlap(
							{ x = a.x, z = a.z, yaw = a.yaw, hw = boxA.width / 2, hl = boxA.length / 2 },
							{ x = b.x, z = b.z, yaw = b.yaw, hw = boxB.width / 2, hl = boxB.length / 2 }
						)
						if depth > th.depth then
							local origin, trueDepth = nil, nil
							if a.rok and b.rok and a.rvis and b.rvis then
								trueDepth = Detect.obbOverlap(
									{ x = a.rx, z = a.rz, yaw = a.ryaw, hw = boxA.width / 2, hl = boxA.length / 2 },
									{ x = b.rx, z = b.rz, yaw = b.ryaw, hw = boxB.width / 2, hl = boxB.length / 2 }
								)
								origin = if trueDepth > th.depth then "sim" else "stream"
							elseif a.rok and b.rok then
								origin = "stream"
							end
							ctx.flag("box_overlap", frame, a, depth, th.depth, "studs", {
								origin = origin,
								other = b.id,
								otherName = ctx.vehicles[b.id].name,
								otherAt = { b.x, b.z, b.yaw },
								trueDepth = trueDepth,
							}, `{a.id}-{b.id}`)
						end
					end
				end
			end,
		}
	end,
}

return def
