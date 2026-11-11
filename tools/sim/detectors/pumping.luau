--!strict
-- Detector: the server's own speed changing direction tick after tick (brake, accelerate, brake ...).
--   speed_pumping   a visible vehicle's speed goes up and down on alternate ticks: it lurches. This is
--                   the simulation's own state (a yield test that is true on one tick and false on the
--                   next as the braking shortens its look-ahead), so every client draws it; the 15 Hz
--                   stream smooths the single ticks but not the lurching as a whole.
-- The stutter detector cannot see it: it compares what is drawn with the true speeds around that
-- instant, and here the truth itself is what jerks. Counted per vehicle on the server's timeline.
local Detect = require("../lib/Detect")

local def: Detect.Def = {
	name = "pumping",
	kinds = {
		speed_pumping = "the car lurches: it brakes and speeds up again several times a second",
	},
	thresholds = {
		{
			key = "accel",
			value = 15,
			unit = "st/s2",
			why = "a change of half a stud a second in one 1/30 s tick: firm braking or pulling away; smaller wobbles are not felt",
		},
		{
			key = "reversals",
			value = 3,
			unit = "count",
			why = "three changes between braking and accelerating within the window: once is a car that braked and went on, three is a lurch",
		},
		{
			key = "window",
			value = 1,
			unit = "s",
			why = "the reversals are counted over one second: a lurch is several a second, a car that brakes for a stop and pulls away later is not",
		},
	},
	new = function(ctx: Detect.Ctx): Detect.Hooks
		local th = ctx.th
		local last: { [number]: { speed: number, sign: number, flips: { number }, open: any? } } = {}
		-- (an open incident's table is the one handed to ctx.report: its duration and magnitude are
		-- updated in place as the episode goes on)
		return {
			tick = function(tick: Detect.Tick)
				for _, v in tick.vehicles do
					local p = last[v.id]
					if not p or not v.visible or v.teleported then
						last[v.id] = { speed = v.speed, sign = 0, flips = {}, open = nil }
						continue
					end
					local a = (v.speed - p.speed) / tick.dt
					local sign = if a > th.accel then 1 elseif a < -th.accel then -1 else 0
					if sign ~= 0 then
						if p.sign ~= 0 and sign ~= p.sign then
							table.insert(p.flips, tick.wall)
						end
						p.sign = sign
					end
					while #p.flips > 0 and p.flips[1] < tick.wall - th.window do
						table.remove(p.flips, 1)
					end
					if #p.flips >= th.reversals then
						-- one incident per lurching episode: it stays open while the reversals keep coming
						local open = p.open
						if open and tick.wall - open.detail.last <= th.window then
							local d = open.detail
							d.last = tick.wall
							d.lo = math.min(d.lo, v.speed)
							d.hi = math.max(d.hi, v.speed)
							open.duration = d.last - d.first
							if #p.flips > open.magnitude then
								open.magnitude = #p.flips
								open.severity = open.magnitude / open.limit
							end
						else
							open = {
								kind = "speed_pumping",
								t = tick.wall,
								vehicle = v.id,
								magnitude = #p.flips,
								limit = th.reversals,
								unit = "reversals/s",
								origin = "sim",
								detail = { first = tick.wall, last = tick.wall, lo = v.speed, hi = v.speed, phase = v.phase },
							}
							p.open = open
							ctx.report(open)
						end
					end
					p.speed = v.speed
				end
			end,
		}
	end,
}

return def
