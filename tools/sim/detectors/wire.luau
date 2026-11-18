--!strict
-- Detector: the server's own state and what it puts on the wire, before any client is involved.
--   sim_jump_unflagged    the server moved a visible vehicle further in one tick than driving can, and
--                         did not flag it as a teleport: every client will draw it sliding there
--   sim_yaw_snap          the server turned a visible vehicle's heading by a large angle in one tick
--   teleport_bit_dropped  the server flagged a teleport, but the flag was gone again before the next
--                         send (the flag lives for one 30 Hz tick, sends go at 15 Hz): the wire never
--                         carried it, so clients interpolate across the teleport
--   teleport_bit_lost     every send that carried the flag was lost on the network (the service flags
--                         a jump on one send; a server that repeated it would need them all lost)
-- These are counted per event on the server's timeline (t is the wall-clock time of the tick or send),
-- not per client frame; the jumps and turns detectors show what each one looks like on screen.
-- ctx.stats: teleports flagged / carried / dropped / lost, and how much older the state in a send is than
-- its stamp (stateOlderThanStampMs: the stamp is the server's frame clock, the state is the last whole
-- 30 Hz tick; the difference is the tick accumulator's remainder, 0 on an exact 60 Hz server and up to a
-- frame's length, different for every send, on a real one: the client spaces the snapshots by stamps, so
-- that difference is a timing error on every pose).
local Detect = require("../lib/Detect")
local Truth = require("../lib/Truth")

local def: Detect.Def = {
	name = "wire",
	kinds = {
		sim_jump_unflagged = "the server itself moves the car in one step without flagging a teleport: clients draw it sliding across",
		sim_yaw_snap = "the server itself turns the car round in one step: clients draw it spinning on the spot",
		teleport_bit_dropped = "a teleport the server flagged never reached the wire: clients streak the car across instead of snapping it",
		teleport_bit_lost = "the one packet that carried a teleport flag was lost: that client streaks the car across",
	},
	thresholds = {
		{
			key = "yaw",
			value = 0.5,
			unit = "rad",
			why = "29 degrees in one 1/30 s tick is 860 degrees a second: not steering, a snap",
		},
		{
			key = "visibleStep",
			value = 3,
			unit = "studs",
			why = "a flagged teleport shorter than this needs no flag: interpolating across it is a nudge, not a streak",
		},
	},
	new = function(ctx: Detect.Ctx): Detect.Hooks
		local th = ctx.th
		local stats = ctx.stats
		stats.teleportsFlagged = 0
		stats.teleportsCarried = 0
		stats.teleportsDropped = 0
		stats.teleportsLost = 0
		stats.stateOlderThanStampMsMax = 0
		stats.stateOlderThanStampMsMean = 0
		local ageSum, sends = 0, 0
		local prev: { [number]: { x: number, z: number, yaw: number, vis: boolean, speed: number } } = {}
		-- flagged teleports of visible vehicles waiting for the next send
		local pending: { [number]: { t: number, step: number, from: { number }, to: { number }, lost: number? } } = {}
		local function reportLost(id: number, tp: any, wall: number, n: number?)
			stats.teleportsLost += 1
			ctx.report({
				kind = "teleport_bit_lost",
				t = wall,
				vehicle = id,
				magnitude = tp.step,
				limit = th.visibleStep,
				unit = "studs",
				origin = "stream",
				detail = { from = tp.from, to = tp.to, teleportAt = tp.t, send = n, lostSends = tp.lost },
			})
		end
		return {
			tick = function(tick: Detect.Tick)
				for _, v in tick.vehicles do
					local p = prev[v.id]
					if p and p.vis and v.visible then
						local step = math.sqrt((v.x - p.x) ^ 2 + (v.z - p.z) ^ 2)
						local limit = Truth.jumpLimit(p.speed, v.speed, tick.dt)
						if v.teleported then
							if step > th.visibleStep then
								stats.teleportsFlagged += 1
								pending[v.id] = { t = tick.wall, step = step, from = { p.x, p.z }, to = { v.x, v.z } }
							end
						elseif step > limit then
							ctx.report({
								kind = "sim_jump_unflagged",
								t = tick.wall,
								vehicle = v.id,
								magnitude = step,
								limit = limit,
								unit = "studs",
								origin = "sim",
								detail = {
									from = { p.x, p.z },
									to = { v.x, v.z },
									phase = v.phase,
									dir = v.dir,
									lane = if v.route then v.route.id else v.lane.id,
									speed = v.speed,
									tick = tick.n,
								},
							})
						end
						local turn = math.abs(Detect.wrapAngle(v.yaw - p.yaw))
						if turn > th.yaw and not v.teleported then
							ctx.report({
								kind = "sim_yaw_snap",
								t = tick.wall,
								vehicle = v.id,
								magnitude = turn,
								limit = th.yaw,
								unit = "rad",
								origin = "sim",
								detail = {
									from = p.yaw,
									to = v.yaw,
									at = { v.x, v.z },
									phase = v.phase,
									lane = if v.route then v.route.id else v.lane.id,
									tick = tick.n,
								},
							})
						end
					end
					prev[v.id] = { x = v.x, z = v.z, yaw = v.yaw, vis = v.visible, speed = v.speed }
				end
			end,
			send = function(send: Detect.Send)
				sends += 1
				local age = send.age * 1000
				ageSum += age
				stats.stateOlderThanStampMsMean = ageSum / sends
				stats.stateOlderThanStampMsMax = math.max(stats.stateOlderThanStampMsMax, age)
				for id, tp in pending do
					local pose = send.poses[id]
					local detail = { from = tp.from, to = tp.to, teleportAt = tp.t, send = send.n }
					if pose and pose.teleported then
						if send.lost then
							-- the next send may carry it again: wait for it
							tp.lost = (tp.lost or 0) + 1
							continue
						end
						stats.teleportsCarried += 1
					elseif tp.lost then
						reportLost(id, tp, send.wall, send.n)
					else
						stats.teleportsDropped += 1
						ctx.report({
							kind = "teleport_bit_dropped",
							t = send.wall,
							vehicle = id,
							magnitude = tp.step,
							limit = th.visibleStep,
							unit = "studs",
							origin = "sim",
							detail = detail,
						})
					end
					pending[id] = nil
				end
			end,
			finish = function()
				for id, tp in pending do
					if tp.lost then
						reportLost(id, tp, tp.t, nil)
					end
				end
			end,
		}
	end,
}

return def
