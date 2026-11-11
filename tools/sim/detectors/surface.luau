--!strict
-- Detector: the vehicle against the ground AS BAKED, which is what a player sees it stand on.
--   buried   a wheel is inside the road (or lot paving) that is drawn under it
--   hover    a wheel hangs above the drawn road or ground: daylight under the tyre
--   ledge    the drawn ground under a wheel steps up or down while the car goes straight on at its
--            own height: it drives through a step in the road (or off one into the air)
-- ground.luau judges the car against the game's analytic ground (World/Ground: terrain plus a fixed
-- paving offset). The town is not built that way: worldgen/Plan.road lays every road as flat parts
-- (segments of at most 40 studs along it, level ACROSS its whole width at its centre line's height), so
-- on a wide road over sloping ground, and where two roads cross, the asphalt a player sees is not where
-- World/Height says. ctx.bakedAt (lib/Baked: worldgen/Surface over the lot and road plans the bake
-- builds, with the terrain under them) is that drawn ground. Checked under the four wheels of the car as
-- drawn (root pose, box size, pitch), every `every` frames, staggered by vehicle.
local Detect = require("../lib/Detect")

local def: Detect.Def = {
	name = "surface",
	mergeGap = 0.5,
	kinds = {
		buried = "a wheel is sunk into the drawn road surface: the car drives half inside the asphalt",
		hover = "a wheel hangs above the drawn road surface: daylight under the tyre",
		ledge = "the car drives straight through a step in the drawn road: the asphalt jumps up or down under a wheel that stays level",
	},
	thresholds = {
		{
			key = "buried",
			value = 0.35,
			unit = "studs",
			why = "a quarter of a sedan's wheel (radius about 1.3 st) in the asphalt: plainly sunk; the analytic road is 0.14 st above the terrain the car is seated on, so 0.14 is the normal state",
		},
		{
			key = "hover",
			value = 0.35,
			unit = "studs",
			why = "the same depth of daylight under a tyre",
		},
		{
			key = "ledge",
			value = 0.5,
			unit = "studs",
			why = "a step in the drawn road a car crosses without following it, from one check to the next; a kerb is 0.3 to 0.6 st",
		},
		{
			key = "maxAbove",
			value = 3.5,
			unit = "studs",
			why = "a part more than this above the wheel is overhead (a deck or roof the car passes under), not ground",
		},
		{
			key = "every",
			value = 2,
			unit = "frames",
			why = "30 checks a second at 60 fps: a car at 25 st/s moves under a stud between checks",
		},
	},
	new = function(ctx: Detect.Ctx): Detect.Hooks
		local th = ctx.th
		local every = math.max(1, math.floor(th.every))
		local WHEELS = {
			{ 0.34, 0.8, "front right" },
			{ 0.34, -0.8, "front left" },
			{ -0.34, 0.8, "rear right" },
			{ -0.34, -0.8, "rear left" },
		}
		-- the last check per vehicle: per wheel, the drawn ground minus the wheel's own height
		local last: { [number]: { gaps: { number }, x: number, z: number, i: number } } = {}
		local stats = ctx.stats
		stats.checks, stats.buriedChecks, stats.hoverChecks = 0, 0, 0
		stats.worstBuried, stats.worstHover = 0, 0
		return {
			frame = function(frame: Detect.Frame)
				for _, id in frame.ids do
					local s = frame.v[id]
					if not s.vis then
						last[id] = nil
						continue
					end
					if (frame.i + id) % every ~= 0 then
						continue
					end
					local box = ctx.vehicles[id].box
					local hw, hh = box.width / 2, box.height / 2
					local fx, fz = math.sin(s.yaw), math.cos(s.yaw)
					local rx, rz = fz, -fx
					local sinP, cosP = math.sin(s.pitch), math.cos(s.pitch)
					local gaps: { number } = {}
					local deepest, deepWhere, highest, highWhere = -math.huge, "", -math.huge, ""
					local tops: { number } = {}
					for k, w in WHEELS do
						local along, across = w[1] * box.length, w[2] * hw
						local forward = along * cosP + hh * sinP
						local px, pz = s.x + fx * forward + rx * across, s.z + fz * forward + rz * across
						local py = s.y + along * sinP - hh * cosP
						local top = ctx.bakedAt(px, pz, py + th.maxAbove)
						tops[k] = top
						local gap = top - py -- > 0: the ground is above the tyre's bottom (buried)
						gaps[k] = gap
						if gap > deepest then
							deepest, deepWhere = gap, w[3]
						end
						if -gap > highest then
							highest, highWhere = -gap, w[3]
						end
					end
					stats.checks += 1
					if deepest > stats.worstBuried then
						stats.worstBuried = deepest
					end
					if highest > stats.worstHover then
						stats.worstHover = highest
					end
					if deepest > th.buried then
						stats.buriedChecks += 1
						ctx.flag(
							"buried",
							frame,
							s,
							deepest,
							th.buried,
							"studs",
							{
								where = deepWhere,
								ground = math.max(table.unpack(tops)),
								heightAt = ctx.heightAt(s.x, s.z),
							}
						)
					end
					if highest > th.hover then
						stats.hoverChecks += 1
						ctx.flag("hover", frame, s, highest, th.hover, "studs", { where = highWhere })
					end
					local l = last[id]
					local p = frame.pv[id]
					if l and l.i == frame.i - every and p and p.vis and not s.snap then
						local moved = math.sqrt((s.x - l.x) ^ 2 + (s.z - l.z) ^ 2)
						if moved < 4 then
							local worst, where = 0, ""
							for k, w in WHEELS do
								local d = math.abs(gaps[k] - l.gaps[k])
								if d > worst then
									worst, where = d, w[3]
								end
							end
							if worst > th.ledge then
								ctx.flag("ledge", frame, s, worst, th.ledge, "studs", { where = where, moved = moved })
							end
						end
					end
					last[id] = { gaps = gaps, x = s.x, z = s.z, i = frame.i }
				end
			end,
		}
	end,
}

return def
