--!strict
-- Detector: the vehicle against the ground.
--   height_jump    the car's height changes more in a frame than a slope under a moving car could
--   pitch_jump     the car's nose pitches up or down faster than a slope could tip it
--   sink           a wheel or the belly is below the ground
--   float          a wheel is above the ground with daylight under it
--   tilt_mismatch  the car's pitch is not the slope of the ground from bumper to bumper
--   roll_missing   the ground slopes sideways under the car, which never rolls
-- The ground is the game's own (World/Ground over World/Height, the bridge deck and the town's paving:
-- ctx.surfaceAt), sampled under the four wheels of the car as drawn (root pose, box size, pitch, roll). The
-- contact kinds are checked every `every` frames, staggered by vehicle. All of these come from where the
-- vehicle is drawn, so their origin is the seating maths (Ghost.seat) or the lane, not the network.
local Detect = require("../lib/Detect")

local def: Detect.Def = {
	name = "ground",
	mergeGap = 0.5,
	kinds = {
		height_jump = "the car pops up or down: its height changes faster than the ground under it could",
		pitch_jump = "the car's nose twitches up or down",
		sink = "a wheel or the belly of the car is buried in the ground",
		float = "a wheel hangs in the air: daylight under the car",
		tilt_mismatch = "the car is tilted nose-up or nose-down against the ground it stands on",
		roll_missing = "the road slopes sideways under the car but the car does not lean with it: one side digs in, the other lifts",
	},
	thresholds = {
		{
			key = "slope",
			value = 0.6,
			unit = "rise/run",
			why = "31 degrees: steeper than any road in the town; the pitch itself is clamped at 0.5 rad",
		},
		{ key = "heightSlack", value = 0.15, unit = "studs", why = "plus 0.15 st, under a kerb's height (0.61 st)" },
		{
			key = "pitchRate",
			value = 1.5,
			unit = "rad/s",
			why = "86 degrees a second: a sedan at 24 st/s cresting the sharpest rise in the town tips well under this",
		},
		{ key = "pitchSlack", value = 0.01, unit = "rad", why = "plus half a degree of rounding" },
		{
			key = "sink",
			value = 0.75,
			unit = "studs",
			why = "deeper than a kerb (0.61 st): the tyres are visibly in the ground (paving sits 0.14 st over the terrain, so 0.14 is normal)",
		},
		{ key = "float", value = 0.75, unit = "studs", why = "a kerb's height of daylight under a wheel" },
		{
			key = "tilt",
			value = 0.12,
			unit = "rad",
			why = "7 degrees between the car's pitch and the bumper-to-bumper slope: the nose or tail is half a stud off the ground on a sedan",
		},
		{
			key = "roll",
			value = 0.12,
			unit = "rad",
			why = "7 degrees between the crossfall and the car's roll: its sides are half a stud off on a sedan",
		},
		{
			key = "every",
			value = 4,
			unit = "frames",
			why = "contact is a standing condition: 15 checks a second at 60 fps is enough",
		},
	},
	new = function(ctx: Detect.Ctx): Detect.Hooks
		local th = ctx.th
		local every = math.max(1, math.floor(th.every))
		return {
			frame = function(frame: Detect.Frame)
				for _, id in frame.ids do
					local s, p = frame.v[id], frame.pv[id]
					if not s.vis then
						continue
					end
					if p and p.vis and not s.snap then
						local d = math.sqrt((s.x - p.x) ^ 2 + (s.z - p.z) ^ 2)
						-- a jump along the ground is jumps.luau's; here only what the ground explains
						if d <= 2.5 * math.max(s.speed, p.speed) * frame.dt + 0.5 then
							local rise = math.abs(s.y - p.y)
							local limit = th.slope * d + th.heightSlack
							if rise > limit then
								ctx.flag(
									"height_jump",
									frame,
									s,
									rise,
									limit,
									"studs",
									{ from = p.y, to = s.y, moved = d }
								)
							end
							local tip = math.abs(s.pitch - p.pitch)
							local tipLimit = th.pitchRate * frame.dt + th.pitchSlack
							if tip > tipLimit then
								ctx.flag(
									"pitch_jump",
									frame,
									s,
									tip,
									tipLimit,
									"rad",
									{ from = p.pitch, to = s.pitch, moved = d }
								)
							end
						end
					end
					if (frame.i + id) % every ~= 0 then
						continue
					end
					local info = ctx.vehicles[id]
					local box = info.box
					local half, hw, hh = box.length / 2, box.width / 2, box.height / 2
					local fx, fz = math.sin(s.yaw), math.cos(s.yaw)
					local rx, rz = -fz, fx -- the car's right (Ghost.rootCFrame's RightVector)
					-- a point of the box's underside, `along` towards the nose and `across` to the right
					local function under(along: number, across: number): (number, number, number)
						return Detect.bodyPoint(s, along, across, -hh)
					end
					local deepest, highest = -math.huge, -math.huge
					local where = ""
					for _, w in
						{
							{ 0.34 * box.length, 0.8 * hw, "front right" },
							{ 0.34 * box.length, -0.8 * hw, "front left" },
							{ -0.34 * box.length, 0.8 * hw, "rear right" },
							{ -0.34 * box.length, -0.8 * hw, "rear left" },
							{ 0, 0, "belly" },
						} :: { { any } }
					do
						local px, py, pz = under(w[1], w[2])
						local gap = py - ctx.surfaceAt(px, pz, s.y)
						if -gap > deepest then
							deepest, where = -gap, w[3]
						end
						if w[3] ~= "belly" and gap > highest then
							highest = gap
						end
					end
					if deepest > th.sink then
						ctx.flag("sink", frame, s, deepest, th.sink, "studs", { where = where })
					end
					if highest > th.float then
						ctx.flag("float", frame, s, highest, th.float, "studs", nil)
					end
					local front = ctx.surfaceAt(s.x + fx * half, s.z + fz * half, s.y)
					local rear = ctx.surfaceAt(s.x - fx * half, s.z - fz * half, s.y)
					local slope = math.atan2(front - rear, box.length)
					if math.abs(s.pitch - slope) > th.tilt then
						ctx.flag(
							"tilt_mismatch",
							frame,
							s,
							math.abs(s.pitch - slope),
							th.tilt,
							"rad",
							{ pitch = s.pitch, groundSlope = slope }
						)
					end
					local right = ctx.surfaceAt(s.x + rx * hw, s.z + rz * hw, s.y)
					local left = ctx.surfaceAt(s.x - rx * hw, s.z - rz * hw, s.y)
					local crossfall = math.atan2(right - left, box.width)
					local unrolled = math.abs(crossfall - (s.roll or 0))
					if unrolled > th.roll then
						ctx.flag(
							"roll_missing",
							frame,
							s,
							unrolled,
							th.roll,
							"rad",
							{ crossfall = crossfall, roll = s.roll or 0 }
						)
					end
				end
			end,
		}
	end,
}

return def
