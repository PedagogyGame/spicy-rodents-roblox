--!strict
-- tools/sim/lib/Truth: the server's true vehicle states over the last few seconds, by server clock.
-- The replay records every simulation tick here (through TrafficService.onTick); detectors ask it where
-- a vehicle really was at the instant a client frame is drawing, and what really happened around then.
-- Interface: new(capacity?) -> Truth; Truth:record(clock, wall, dt, vehicles); Truth:at(id, clock) ->
--            State?; Truth:window(id, from, to) -> Window; Truth:last(id) -> Window (the newest tick alone);
--            jumpLimit(speedBefore, speedAfter, dt); Truth.ticks; Truth.newest
-- A tick's clock is the server clock of the frame that ran it (the clock that stamps the sends), so a
-- send's stamp and the truth it carries line up exactly when the tick and the send share a frame.

local Truth = {}

-- A true step in one tick is a jump (not driving) when it is longer than this allows:
-- JUMP_FACTOR x the faster of the speeds before and after x the tick, plus JUMP_SLACK studs.
Truth.JUMP_FACTOR = 2.5
Truth.JUMP_SLACK = 0.5

-- jumpLimit(speedBefore, speedAfter, dt): the longest step one tick of driving can be.
function Truth.jumpLimit(speedBefore: number, speedAfter: number, dt: number): number
	return Truth.JUMP_FACTOR * math.max(speedBefore, speedAfter) * dt + Truth.JUMP_SLACK
end

export type State = {
	x: number,
	z: number,
	yaw: number,
	visible: boolean,
	speed: number, -- the true speed over the ground (the tick's step / its length; the motor's at a jump)
	stale: boolean, -- the clock asked for is older than the history kept
}

export type Window = {
	lo: number, -- the lowest and highest true speed in the window
	hi: number,
	flagged: number, -- the longest step of a tick the simulation flagged as a teleport (0: none)
	jump: number, -- the longest step of a tick that was a jump without the flag (0: none)
	yawStep: number, -- the largest heading change in one tick (radians)
	visibility: boolean, -- the vehicle appeared or disappeared
	ticks: number,
}

type Track = {
	x: { number },
	z: { number },
	yaw: { number },
	vis: { boolean },
	speed: { number },
	motor: { number },
	flagged: { number },
	jump: { number },
	yawStep: { number },
	visChange: { boolean },
}

export type Truth = {
	capacity: number,
	ticks: number, -- ticks recorded so far
	newest: number, -- the newest tick's clock
	clocks: { number },
	walls: { number },
	tracks: { [number]: Track },
	record: (self: Truth, clock: number, wall: number, dt: number, vehicles: { any }) -> (),
	at: (self: Truth, id: number, clock: number) -> State?,
	window: (self: Truth, id: number, from: number, to: number) -> Window,
	last: (self: Truth, id: number) -> Window,
}

local function wrap(a: number): number
	return math.atan2(math.sin(a), math.cos(a))
end

function Truth.new(capacity: number?): Truth
	local cap = capacity or 512
	local self: Truth
	local function slot(n: number): number
		return (n - 1) % cap + 1
	end
	self = {
		capacity = cap,
		ticks = 0,
		newest = 0,
		clocks = table.create(cap, 0),
		walls = table.create(cap, 0),
		tracks = {},
		record = function(_self: Truth, clock: number, wall: number, dt: number, vehicles: { any })
			local n = self.ticks + 1
			local i, p = slot(n), slot(n - 1)
			self.ticks = n
			self.newest = clock
			self.clocks[i] = clock
			self.walls[i] = wall
			for _, v in vehicles do
				local tr = self.tracks[v.id]
				local first = tr == nil
				if tr == nil then
					tr = {
						x = table.create(cap, 0),
						z = table.create(cap, 0),
						yaw = table.create(cap, 0),
						vis = table.create(cap, false),
						speed = table.create(cap, 0),
						motor = table.create(cap, 0),
						flagged = table.create(cap, 0),
						jump = table.create(cap, 0),
						yawStep = table.create(cap, 0),
						visChange = table.create(cap, false),
					}
					self.tracks[v.id] = tr
				end
				local step, yawStep, visChange = 0, 0, false
				local before = 0
				if not first and n > 1 then
					step = math.sqrt((v.x - tr.x[p]) ^ 2 + (v.z - tr.z[p]) ^ 2)
					yawStep = math.abs(wrap(v.yaw - tr.yaw[p]))
					visChange = tr.vis[p] ~= v.visible
					before = tr.motor[p]
				end
				local driving = v.visible and not visChange
				local limit = Truth.jumpLimit(before, v.speed, dt)
				local flagged = if v.teleported then math.max(step, 1e-9) else 0
				local jump = if driving and not v.teleported and step > limit then step else 0
				tr.x[i], tr.z[i], tr.yaw[i], tr.vis[i] = v.x, v.z, v.yaw, v.visible
				tr.motor[i] = v.speed
				tr.speed[i] = if driving and flagged == 0 and jump == 0 and dt > 0 then step / dt else v.speed
				tr.flagged[i] = flagged
				tr.jump[i] = jump
				tr.yawStep[i] = if driving then yawStep else 0
				tr.visChange[i] = visChange
			end
		end,
		at = function(_self: Truth, id: number, clock: number): State?
			local tr = self.tracks[id]
			local n = self.ticks
			if tr == nil or n == 0 then
				return nil
			end
			local oldest = math.max(1, n - cap + 1)
			-- the newest tick at or before `clock`
			local k = n
			while k > oldest and self.clocks[slot(k)] > clock do
				k -= 1
			end
			local a = slot(k)
			local stale = self.clocks[a] > clock -- older than everything kept
			if k == n or stale then
				return {
					x = tr.x[a],
					z = tr.z[a],
					yaw = tr.yaw[a],
					visible = tr.vis[a],
					speed = tr.speed[a],
					stale = stale,
				}
			end
			local b = slot(k + 1)
			local span = self.clocks[b] - self.clocks[a]
			-- a teleport, a jump or an appearance is a step in the truth: nothing lies between the two
			if span <= 1e-9 or tr.flagged[b] > 0 or tr.jump[b] > 0 or tr.visChange[b] then
				return {
					x = tr.x[a],
					z = tr.z[a],
					yaw = tr.yaw[a],
					visible = tr.vis[a],
					speed = tr.speed[a],
					stale = false,
				}
			end
			local u = (clock - self.clocks[a]) / span
			return {
				x = tr.x[a] + (tr.x[b] - tr.x[a]) * u,
				z = tr.z[a] + (tr.z[b] - tr.z[a]) * u,
				yaw = tr.yaw[a] + wrap(tr.yaw[b] - tr.yaw[a]) * u,
				visible = tr.vis[a],
				speed = tr.speed[a] + (tr.speed[b] - tr.speed[a]) * u,
				stale = false,
			}
		end,
		-- window(id, from, to): what the truth did between two server-clock instants, widened to the
		-- ticks that bracket them (the tick before `from` and the tick after `to` are included).
		window = function(_self: Truth, id: number, from: number, to: number): Window
			local out: Window =
				{ lo = math.huge, hi = 0, flagged = 0, jump = 0, yawStep = 0, visibility = false, ticks = 0 }
			local tr = self.tracks[id]
			local n = self.ticks
			if tr == nil or n == 0 then
				out.lo = 0
				return out
			end
			local oldest = math.max(1, n - cap + 1)
			local k = n
			-- skip the ticks after the one that follows `to`
			while k > oldest and self.clocks[slot(k - 1)] > to do
				k -= 1
			end
			while k >= oldest do
				local i = slot(k)
				out.ticks += 1
				out.lo = math.min(out.lo, tr.speed[i])
				out.hi = math.max(out.hi, tr.speed[i])
				out.flagged = math.max(out.flagged, tr.flagged[i])
				out.jump = math.max(out.jump, tr.jump[i])
				out.yawStep = math.max(out.yawStep, tr.yawStep[i])
				out.visibility = out.visibility or tr.visChange[i]
				if self.clocks[i] < from then
					break -- this was the tick before `from`
				end
				k -= 1
			end
			if out.lo == math.huge then
				out.lo = 0
			end
			return out
		end,
		last = function(_self: Truth, id: number): Window
			local tr = self.tracks[id]
			if tr == nil or self.ticks == 0 then
				return { lo = 0, hi = 0, flagged = 0, jump = 0, yawStep = 0, visibility = false, ticks = 0 }
			end
			local i = slot(self.ticks)
			return {
				lo = tr.speed[i],
				hi = tr.speed[i],
				flagged = tr.flagged[i],
				jump = tr.jump[i],
				yawStep = tr.yawStep[i],
				visibility = tr.visChange[i],
				ticks = 1,
			}
		end,
	}
	return self
end

return Truth
