--!strict
-- Detector: a vehicle meeting what is not another fleet vehicle (overlap.luau has those pairs).
--   through_person      a moving, visible vehicle's box is into a person standing or walking on the road
--                       (a townsperson or a player's human: `world.people`, kind "human")
--   through_player_car  a visible vehicle's box is into a player's vehicle (`world.cars`: the cars, carts,
--                       bikes, pickups and SUVs of Server/Actors/DeviceService, parked or driven)
-- Judged on the server's own state every simulation tick (origin sim): what the server does is what every
-- client draws 0.13 s later, and the player's car and body are where the player's own client has them.
-- Squirrels are left out on purpose: a car running over a player's squirrel is the game (the fatal sweep).
-- A scenario supplies `world.cars` as { id, kind, x, z, yaw, width, length } in studs.
local Detect = require("../lib/Detect")

local R_PERSON = 1.0 -- studs: a townsperson's body radius (AICarMotor's R_HUMAN, 0.4 u)

type Episode = { inc: { [string]: any }, last: number, first: number, ticks: number }

local def: Detect.Def = {
	name = "meetings",
	kinds = {
		through_person = "a car drives into or through a person on the road",
		through_player_car = "a car drives into or through a player's vehicle",
	},
	thresholds = {
		{
			key = "depth",
			value = 0.3,
			unit = "studs",
			why = "the same depth as box_overlap: a third of a stud into a body is a visible clip, less is touching",
		},
		{
			key = "moved",
			value = 0.01,
			unit = "studs/tick",
			why = "through_person is about the car's motion: a person walking into a car standing still is not the car's glitch",
		},
		{
			key = "gap",
			value = 0.5,
			unit = "s",
			why = "contacts of one pair closer together than this are one incident",
		},
	},
	new = function(ctx: Detect.Ctx): Detect.Hooks
		local th = ctx.th
		local open: { [string]: Episode } = {}
		local prev: { [number]: { number } } = {}
		ctx.stats.through_person_ticks = 0
		ctx.stats.through_player_car_ticks = 0

		local function close(key: string)
			local ep = open[key]
			open[key] = nil
			ep.inc.duration = ep.last - ep.first
			ep.inc.frames = ep.ticks
			ctx.report(ep.inc)
		end

		local function hit(kind: string, wall: number, v: any, depth: number, other: string, detail: { [string]: any })
			ctx.stats[`{kind}_ticks`] += 1
			local key = `{kind}|{v.id}|{other}`
			local ep = open[key]
			if ep == nil then
				ep = {
					inc = {
						kind = kind,
						t = wall,
						vehicle = v.id,
						magnitude = -math.huge,
						limit = th.depth,
						unit = "studs",
						origin = "sim",
					},
					first = wall,
					last = wall,
					ticks = 0,
				}
				open[key] = ep
			end
			ep.last = wall
			ep.ticks += 1
			if depth > ep.inc.magnitude then
				ep.inc.magnitude = depth
				ep.inc.truth = {
					visible = v.visible,
					x = v.x,
					y = v.y,
					z = v.z,
					yaw = v.yaw,
					speed = v.speed,
					phase = v.phase,
					s = v.s,
					dir = v.dir,
					lane = if v.route then v.route.id else v.lane.id,
				}
				detail.worstAt = wall
				ep.inc.detail = detail
			end
		end

		return {
			tick = function(tick: Detect.Tick)
				local world = tick.world or {}
				local people = world.people or {}
				local cars = world.cars or {}
				for _, v in tick.vehicles do
					local p = prev[v.id]
					local moved = if p then math.abs(v.x - p[1]) + math.abs(v.z - p[2]) else 0
					prev[v.id] = { v.x, v.z }
					local info = ctx.vehicles[v.id]
					local box = v.box or (info and info.box)
					if not v.visible or box == nil then
						continue
					end
					local me = { x = v.x, z = v.z, yaw = v.yaw, hw = box.width / 2, hl = box.length / 2 }
					local reach = (box.length + box.width) / 2
					if moved > th.moved and not v.teleported then
						for i, h in people do
							if h.kind == "squirrel" or h.visible == false then
								continue
							end
							local dx, dz = h.x - v.x, h.z - v.z
							if dx * dx + dz * dz > (reach + 2) ^ 2 then
								continue
							end
							local depth =
								Detect.obbOverlap(me, { x = h.x, z = h.z, yaw = v.yaw, hw = R_PERSON, hl = R_PERSON })
							if depth > th.depth then
								hit("through_person", tick.wall, v, depth, `p{h.id or i}`, {
									person = { h.x, h.z },
									speed = v.speed,
									moved = moved,
								})
							end
						end
					end
					for _, c in cars do
						local dx, dz = c.x - v.x, c.z - v.z
						if dx * dx + dz * dz > (reach + (c.length + c.width) / 2) ^ 2 then
							continue
						end
						local depth = Detect.obbOverlap(
							me,
							{ x = c.x, z = c.z, yaw = c.yaw, hw = c.width / 2, hl = c.length / 2 }
						)
						if depth > th.depth then
							hit("through_player_car", tick.wall, v, depth, tostring(c.id), {
								other = c.id,
								otherKind = c.kind,
								otherAt = { c.x, c.z, c.yaw },
								speed = v.speed,
							})
						end
					end
				end
				for key, ep in open do
					if tick.wall - ep.last > th.gap then
						close(key)
					end
				end
			end,
			finish = function()
				local keys = {}
				for key in open do
					table.insert(keys, key)
				end
				table.sort(keys)
				for _, key in keys do
					close(key)
				end
			end,
		}
	end,
}

return def
