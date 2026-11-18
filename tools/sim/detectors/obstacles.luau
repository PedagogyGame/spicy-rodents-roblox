--!strict
-- Detector: the vehicle against the town.
--   through_building  the car's box, as drawn, is inside a building (World/Colliders: every solid lot)
--   off_road          the car's centre is off every carriageway (the asphalt and cobble strips of
--                     World/Town; the rail strip counts for the trolley): it drives over a sidewalk,
--                     a yard or open ground
-- Checked every `every` frames, staggered by vehicle. Both come from where the lane or the route puts
-- the vehicle (origin sim) unless the drawn pose is away from the true pose being drawn (origin stream:
-- a streak across a teleport cuts through whatever lies between). Trees, lamp posts, parked props and
-- other street furniture are not in World/Colliders and are not tested here.
local Detect = require("../lib/Detect")

local CARRIAGEWAY = { asphalt = true, cobble = true }

local def: Detect.Def = {
	name = "obstacles",
	mergeGap = 0.5,
	kinds = {
		through_building = "the car drives through a building",
		off_road = "the car drives where there is no road: across a sidewalk, a yard or open ground",
	},
	thresholds = {
		{
			key = "depth",
			value = 0.5,
			unit = "studs",
			why = "half a stud into a wall: less is the box brushing a facade that the placeholder body does not reach",
		},
		{
			key = "offRoad",
			value = 2,
			unit = "studs",
			why = "the centre two studs beyond the edge of the nearest carriageway: at least a wheel is over the kerb on the narrowest vehicle that has one",
		},
		{
			key = "minSpeed",
			value = 1,
			unit = "st/s",
			why = "off_road is about driving: a vehicle standing where it was parked or dispatched to is not reported",
		},
		{
			key = "every",
			value = 4,
			unit = "frames",
			why = "a standing condition: 15 checks a second at 60 fps is enough",
		},
	},
	new = function(ctx: Detect.Ctx): Detect.Hooks
		local th = ctx.th
		local every = math.max(1, math.floor(th.every))
		local town, colliders = ctx.town, ctx.colliders
		local Colliders = ctx.Colliders
		-- distance from (x, z) to the nearest strip the vehicle may drive on (0: on one)
		local function roadDistance(x: number, z: number, rail: boolean): (number, string?)
			local best, id = math.huge, nil
			for _, s in town.strips do
				if CARRIAGEWAY[s.kind] or (rail and s.kind == "rail") then
					local along, across = if s.axis == "z" then z else x, if s.axis == "z" then x else z
					local da = math.max(0, math.abs(across - s.coord) - s.half)
					local dl = math.max(0, s.min - along, along - s.max)
					local d = math.sqrt(da * da + dl * dl)
					if d < best then
						best, id = d, s.id
					end
				end
			end
			return best, id
		end
		return {
			frame = function(frame: Detect.Frame)
				for _, id in frame.ids do
					local s = frame.v[id]
					if not s.vis or (frame.i + id) % every ~= 0 then
						continue
					end
					local info = ctx.vehicles[id]
					local box = info.box
					local origin = nil
					if s.rok then
						origin = if (s.x - s.rx) ^ 2 + (s.z - s.rz) ^ 2 < 2.25 then "sim" else "stream"
					end
					if colliders then
						local reach = (box.length + box.width) / 2
						local me = { x = s.x, z = s.z, yaw = s.yaw, hw = box.width / 2, hl = box.length / 2 }
						for _, b in Colliders.query(colliders, s.x - reach, s.z - reach, s.x + reach, s.z + reach) do
							-- above the roof or below the base is not inside
							if s.y - box.height / 2 > b.peak or s.y + box.height / 2 < b.y0 then
								continue
							end
							local depth = Detect.obbOverlap(me, { x = b.cx, z = b.cz, yaw = 0, hw = b.hw, hl = b.hd })
							if depth > th.depth then
								ctx.flag("through_building", frame, s, depth, th.depth, "studs", {
									origin = origin,
									building = b.id,
									footprint = { b.cx - b.hw, b.cz - b.hd, b.cx + b.hw, b.cz + b.hd },
								}, `{id}|{b.id}`)
							end
						end
					end
					if town and s.speed > th.minSpeed then
						local d, nearest = roadDistance(s.x, s.z, info.class == "trolley")
						if d > th.offRoad then
							ctx.flag(
								"off_road",
								frame,
								s,
								d,
								th.offRoad,
								"studs",
								{ origin = origin, nearestRoad = nearest }
							)
						end
					end
				end
			end,
		}
	end,
}

return def
