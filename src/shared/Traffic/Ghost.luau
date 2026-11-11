--!strict
-- ReplicatedStorage.Shared.Traffic.Ghost
-- Ghost vehicles: the server pose stream codec and the client interpolation buffer (BUILD_PLAN D9, §1.6
-- VehiclePoses, W1 #9; traffic.md §13 "render on clients with interpolation, about 100 ms behind").
-- Interface: encode(pose) -> record (Net/Schemas.VehiclePose fields); decode(record) -> Pose;
--            new(opts) -> Buffer; Buffer:push(t, records); Buffer:sample(now) -> { [id] = Pose };
--            seat(x, z, yaw, length, heightAt) -> y, pitch; seen(pose, kind, heightAt) -> x, y, z, yaw, pitch
--            (pure: the root pose a player sees); view(buffer, now, kinds, heightAt, visit) (pure: one
--            client frame, `visit` called per vehicle with its sampled and seen pose);
--            rootCFrame(lib, x, y, z, yaw, pitch, visible) (the CFrame of that pose, lib = PartBuilder.Lib);
--            render(buffer, now, folder, kinds, heightAt, models) (engine: placeholder models, one BulkMoveTo).
--
-- Records are 13 bytes (u16 id, f32 x, f32 z, u8 yaw, u8 speed, u8 bits). The server never sends y:
-- clients take it from World/Height like the server does (traffic.md §13 "Terrain"). A teleported pose
-- (wrap, appear, dispatch) snaps instead of interpolating, so a ghost never streaks across town.
-- Client/Render/VehicleView (outside Track B's paths) is the intended caller of `render`.

local Units = require("../Config/Units")
local PartBuilder = require("../Avatar/PartBuilder")
local VehiclePuppet = require("./VehiclePuppet")

export type Pose = {
	id: number,
	x: number,
	z: number,
	yaw: number,
	speed: number,
	visible: boolean,
	beacons: boolean,
	teleported: boolean,
	stopped: boolean,
}

export type Snapshot = { t: number, poses: { [number]: Pose } }

local Ghost = {}

Ghost.BIT_VISIBLE = 1
Ghost.BIT_BEACONS = 2
Ghost.BIT_TELEPORTED = 4
Ghost.BIT_STOPPED = 8
Ghost.SPEED_STEP = 0.5 -- studs/s per speed byte (max 127.5 st/s; the fastest vehicle is 67.5)
Ghost.DELAY = 0.13 -- render at least this far behind the least-delayed send (about two sends)
-- Owner 2026-11-10: "some of the cars are glitching out". Snapshots were timed by when each packet
-- ARRIVED, with barely one send interval of buffer: a late or lost packet froze every car and the next
-- one threw it forward. What now keeps cars moving evenly (each measured with tools/sim):
--   * each send carries the server's own clock in a stamp record (id STAMP_ID, the seconds modulo
--     STAMP_WRAP in x); snapshots are kept on that clock, in time order, copies dropped
--   * the playout clock (newClock) decides which instant to draw: it buffers more on a jittery line and
--     follows a server stall or a local clock step by steering, never by jumping
--   * when the newest snapshot is older than the render time, a moving car carries on along its last
--     seen velocity for up to EXTRAPOLATE seconds (a stopped car has no velocity, so it does not creep):
--     enough to ride out two or three lost sends (a 0.3 s wifi dropout) without a freeze and a hop
--   * a jump no car could drive is snapped, never streaked (jumped)
--   * on a slope the car pitches with the road (the height under its front and rear), not flat
Ghost.STAMP_ID = 65535
Ghost.EXTRAPOLATE = 0.25

local TAU = 2 * math.pi

function Ghost.encode(p: Pose): { [string]: number }
	local yaw = p.yaw % TAU
	local bits = (if p.visible then Ghost.BIT_VISIBLE else 0)
		+ (if p.beacons then Ghost.BIT_BEACONS else 0)
		+ (if p.teleported then Ghost.BIT_TELEPORTED else 0)
		+ (if p.stopped then Ghost.BIT_STOPPED else 0)
	return {
		id = p.id,
		x = p.x,
		z = p.z,
		yaw = math.floor(yaw / TAU * 256 + 0.5) % 256,
		speed = math.clamp(math.floor(p.speed / Ghost.SPEED_STEP + 0.5), 0, 255),
		bits = bits,
	}
end

function Ghost.decode(r: { [string]: number }): Pose
	local yaw = r.yaw / 256 * TAU
	if yaw > math.pi then
		yaw -= TAU
	end
	local bits = r.bits
	return {
		id = r.id,
		x = r.x,
		z = r.z,
		yaw = yaw,
		speed = r.speed * Ghost.SPEED_STEP,
		visible = bit32.btest(bits, Ghost.BIT_VISIBLE),
		beacons = bit32.btest(bits, Ghost.BIT_BEACONS),
		teleported = bit32.btest(bits, Ghost.BIT_TELEPORTED),
		stopped = bit32.btest(bits, Ghost.BIT_STOPPED),
	}
end

export type Buffer = {
	delay: number,
	snaps: { Snapshot },
	push: (self: Buffer, t: number, records: { { [string]: number } }) -> (),
	sample: (self: Buffer, now: number) -> { [number]: Pose },
}

-- jumped(a, b, span): b is further from a than the car could have driven in `span` seconds at the
-- larger of their speeds (twice over, plus a car length): a teleport whose flagged send was lost on the
-- way, or a jump the server made without flagging it. It is drawn as a snap, never as a streak across
-- town and never carried on (extrapolated) along that impossible velocity.
Ghost.JUMP_SLACK = 6 -- studs
local function jumped(a: Pose, b: Pose, span: number): boolean
	local dx, dz = b.x - a.x, b.z - a.z
	local reach = 2 * math.max(a.speed, b.speed) * math.abs(span) + Ghost.JUMP_SLACK
	return dx * dx + dz * dz > reach * reach
end

-- snapped(a, b, span): b does not follow a by driving (teleported, appeared, vanished, or jumped)
local function snapped(a: Pose, b: Pose, span: number): boolean
	return b.teleported or a.visible ~= b.visible or (a.visible and jumped(a, b, span))
end

local function lerpAngle(a: number, b: number, t: number): number
	local d = math.atan2(math.sin(b - a), math.cos(b - a))
	return a + d * t
end

-- The stamp travels in a 32-bit float, which past a day of uptime resolves only 8 to 60 ms: the
-- snapshots would be spaced unevenly by that much and every car would surge and drag (tools/sim:
-- --uptime-hours 50). So the server sends its clock modulo STAMP_WRAP (resolved to 0.5 ms) and the
-- client's clock (newClock) unwraps it against the stamps before it.
Ghost.STAMP_WRAP = 4096

-- stamp(serverSeconds): the record that carries the server's clock (modulo STAMP_WRAP) in a send.
function Ghost.stamp(serverSeconds: number): { [string]: number }
	return { id = Ghost.STAMP_ID, x = serverSeconds % Ghost.STAMP_WRAP, z = 0, yaw = 0, speed = 0, bits = 0 }
end

-- takeStamp(records): removes the stamp record from a decoded send and returns its seconds (nil when the
-- server sent none).
function Ghost.takeStamp(records: { { [string]: number } }): number?
	for i = #records, 1, -1 do
		if records[i].id == Ghost.STAMP_ID then
			local s = records[i].x
			table.remove(records, i)
			return s
		end
	end
	return nil
end

-- The playout clock: which server instant the client draws at each frame. Every send's (arrival - stamp)
-- is recorded, and the instant drawn is aimed at now - floor - delay:
--   floor: the smallest (arrival - stamp) of the last CLOCK_WINDOW seconds (the least-delayed packet,
--   the network's own floor; it follows the server falling behind after a stall, or the client's clock
--   being resynced, within a second instead of the minutes a fixed creep took)
--   delay: DELAY plus how much later than that floor most packets came (the 95th percentile over
--   SPREAD_WINDOW), at most MAX_DELAY, so a jittery connection buffers enough to keep the cars fed
-- The instant drawn advances by the frame's own length and is steered toward that aim at most SLEW
-- seconds per second, so it never jumps (that would throw every car forward or back, or replay a moment
-- backwards when the local clock steps): at worst the cars run 5 % slow or fast for a while. While the
-- instant drawn is past the newest snapshot (the cars are being carried on or held) and the aim is
-- behind it, as after a server stall (the stamps fall behind: Server/Boot/Game clamps its clock), it
-- falls back at CATCH_UP instead, so the cars crawl on for a moment instead of freezing for seconds.
-- Only an error beyond SNAP seconds (the first packet, a server restart) is taken at once.
Ghost.MAX_DELAY = 0.45
Ghost.CLOCK_WINDOW = 0.5
Ghost.SPREAD_WINDOW = 4.0
Ghost.SLEW = 0.05
Ghost.CATCH_UP = 0.75 -- the slew while the instant drawn is past the newest snapshot and should fall back
Ghost.DEADBAND = 0.004
Ghost.SNAP = 1.0

export type StampClock = {
	offset: number?, -- now - offset - delay = the server instant drawn (nil until the first stamp)
	delay: number, -- the render delay aimed at (Buffer.delay follows it)
	drawn: number?, -- the server instant drawn this frame
	last: number?, -- the newest unwrapped stamp
	seen: { { d: number, at: number } }, -- recent (arrival - stamp), oldest first
	prevNow: number?,
	stamp: (self: StampClock, raw: number, arrival: number) -> number,
	advance: (self: StampClock, now: number, dt: number?, newest: number?) -> number,
}

-- newClock(): `stamp(raw, arrival)` takes a send's stamp (as sent: modulo STAMP_WRAP) and the local time
-- it arrived, records it, and returns the stamp unwrapped (server seconds: snapshots are kept on this
-- timeline). `advance(now, dt?, newest?)` is called once per client frame with the local clock, the
-- frame's length (default: the change in `now`) and the newest snapshot's time: it moves the instant drawn and returns the time to sample the
-- snapshot buffer at (the instant drawn + `delay`, which the buffer subtracts itself).
function Ghost.newClock(): StampClock
	return {
		offset = nil,
		delay = Ghost.DELAY,
		drawn = nil,
		last = nil,
		seen = {},
		prevNow = nil,
		stamp = function(self: StampClock, raw: number, arrival: number): number
			local s = raw
			local last = self.last
			if last then
				s = raw + Ghost.STAMP_WRAP * math.floor((last - raw) / Ghost.STAMP_WRAP + 0.5)
				if s > last then
					self.last = s
				end
			else
				self.last = s
			end
			local seen = self.seen
			table.insert(seen, { d = arrival - s, at = arrival })
			while #seen > 1 and seen[1].at < arrival - Ghost.SPREAD_WINDOW do
				table.remove(seen, 1)
			end
			return s
		end,
		advance = function(self: StampClock, now: number, dt: number?, newest: number?): number
			local step = dt or (if self.prevNow then math.clamp(now - self.prevNow, 0, 0.5) else 0)
			self.prevNow = now
			local seen = self.seen
			local n = #seen
			if n == 0 then
				return now - (self.offset or 0)
			end
			local floor = math.huge
			local latest = seen[n].at
			for i = n, 1, -1 do
				local e = seen[i]
				if e.at < latest - Ghost.CLOCK_WINDOW then
					break
				end
				floor = math.min(floor, e.d)
			end
			local spreads = table.create(n)
			for i, e in seen do
				spreads[i] = math.max(e.d - floor, 0)
			end
			table.sort(spreads)
			local spread = spreads[math.max(1, math.ceil(n * 0.95))]
			local delay = math.min(Ghost.DELAY + spread, Ghost.MAX_DELAY)
			local aim = now - floor - delay
			local drawn = self.drawn
			if drawn == nil or math.abs(aim - (drawn + step)) > Ghost.SNAP then
				drawn = aim
			else
				drawn += step
				local err = aim - drawn
				if math.abs(err) > Ghost.DEADBAND then
					local back = if newest and drawn > newest and err < 0 then Ghost.CATCH_UP else Ghost.SLEW
					drawn += math.clamp(err, -back * step, Ghost.SLEW * step)
				end
			end
			self.drawn = drawn
			self.delay = delay
			self.offset = now - drawn - delay
			return drawn + delay
		end,
	}
end

function Ghost.new(opts: { delay: number?, keep: number? }?): Buffer
	local o: { delay: number?, keep: number? } = opts or {}
	local keep = o.keep or 12
	local buf: Buffer = {
		delay = o.delay or Ghost.DELAY,
		snaps = {},
		push = function(self: Buffer, t: number, records: { { [string]: number } })
			local poses = {}
			for _, r in records do
				local p = Ghost.decode(r)
				poses[p.id] = p
			end
			-- packets overtake each other: keep the snapshots in time order, and a copy of one already
			-- held (a duplicated packet) is dropped
			local snaps = self.snaps
			local at = #snaps + 1
			while at > 1 and snaps[at - 1].t >= t do
				at -= 1
			end
			if snaps[at] and math.abs(snaps[at].t - t) < 1e-6 then
				return
			end
			if at == 1 and #snaps >= keep then
				return -- older than everything kept
			end
			table.insert(snaps, at, { t = t, poses = poses })
			while #snaps > keep do
				table.remove(snaps, 1)
			end
		end,
		sample = function(self: Buffer, now: number): { [number]: Pose }
			local snaps = self.snaps
			local n = #snaps
			if n == 0 then
				return {}
			end
			local rt = now - self.delay
			if rt <= snaps[1].t then
				return snaps[1].poses
			end
			if rt >= snaps[n].t then
				-- starved (a late or lost send): carry each moving car on along the velocity of its last
				-- two snapshots for a moment; a car that was not moving stays exactly where it is
				local newest = snaps[n]
				local before = snaps[n - 1]
				local ahead = math.min(rt - newest.t, Ghost.EXTRAPOLATE)
				if before == nil or ahead <= 0 or newest.t - before.t <= 1e-3 then
					return newest.poses
				end
				local span = newest.t - before.t
				local out = {}
				for id, pb in newest.poses do
					local pa = before.poses[id]
					if
						pa == nil
						or pb.teleported
						or pb.stopped
						or not pa.visible
						or not pb.visible
						or jumped(pa, pb, span)
					then
						out[id] = pb
					else
						local k = ahead / span
						out[id] = {
							id = id,
							x = pb.x + (pb.x - pa.x) * k,
							z = pb.z + (pb.z - pa.z) * k,
							yaw = pb.yaw,
							speed = pb.speed,
							visible = pb.visible,
							beacons = pb.beacons,
							teleported = false,
							stopped = pb.stopped,
						}
					end
				end
				return out
			end
			local i = 1
			while snaps[i + 1].t < rt do
				i += 1
			end
			local a, b = snaps[i], snaps[i + 1]
			local span = b.t - a.t
			local u = (rt - a.t) / span
			local pre = snaps[i - 1]
			local out = {}
			for id, pb in b.poses do
				local pa = a.poses[id]
				if pa == nil then
					out[id] = pb -- seen for the first time
				elseif snapped(pa, pb, span) then
					-- a teleport, an appearance or a disappearance happened by b's instant: snap exactly then.
					-- Until then the car carries on as it was (it used to snap a send early and stand still)
					if pa.visible and not pa.stopped then
						local k = rt - a.t
						out[id] = {
							id = id,
							x = pa.x + math.sin(pa.yaw) * pa.speed * k,
							z = pa.z + math.cos(pa.yaw) * pa.speed * k,
							yaw = pa.yaw,
							speed = pa.speed,
							visible = true,
							beacons = pa.beacons,
							teleported = false,
							stopped = false,
						}
					else
						out[id] = pa
					end
				else
					-- flagged as teleported while it leaves the snapshot it snapped to
					local fresh = false
					if pre then
						local pp = pre.poses[id]
						fresh = pp == nil or snapped(pp, pa, a.t - pre.t)
					end
					out[id] = {
						id = id,
						x = pa.x + (pb.x - pa.x) * u,
						z = pa.z + (pb.z - pa.z) * u,
						yaw = lerpAngle(pa.yaw, pb.yaw, u),
						speed = pa.speed + (pb.speed - pa.speed) * u,
						visible = pb.visible,
						beacons = pb.beacons,
						teleported = fresh,
						stopped = pb.stopped,
					}
				end
			end
			return out
		end,
	}
	return buf
end

-- seat(x, z, yaw, length, heightAt) -> y, pitch: where a vehicle of that length sits on the ground at
-- (x, z) heading `yaw` (HTML yaw: it faces (sin yaw, cos yaw)): the mean of the heights under its front
-- and rear axles, and the nose-up pitch (radians, for CFrame.Angles(pitch, 0, 0) after Units.yawCFrame)
-- that lays it along the slope between them. Pure.
function Ghost.seat(
	x: number,
	z: number,
	yaw: number,
	length: number,
	heightAt: (x: number, z: number) -> number
): (number, number)
	local half = math.max(length, 1) * 0.36 -- the axles sit about 36 % of the length from the middle
	local fx, fz = math.sin(yaw), math.cos(yaw)
	local front = heightAt(x + fx * half, z + fz * half)
	local rear = heightAt(x - fx * half, z - fz * half)
	local pitch = math.atan2(front - rear, 2 * half)
	return (front + rear) / 2, math.clamp(pitch, -0.5, 0.5)
end

Ghost.HIDDEN_Y = -500 -- a hidden ghost parks this far below the map

-- seen(p, kind, heightAt) -> x, y, z, yaw, pitch: the pose `render` gives the root part of a vehicle of
-- that kind for the sampled pose `p`: a visible one sits on the ground under its axles (`seat`), its
-- centre half its box height above it, pitched with the slope; a hidden one parks at HIDDEN_Y, level.
-- Yaw is the HTML yaw (Units.yawCFrame turns it into the engine's). Pure: the headless replay
-- (tools/sim/traffic_replay.luau) records exactly these numbers as "what the player sees".
function Ghost.seen(
	p: Pose,
	kind: string,
	heightAt: (x: number, z: number) -> number
): (number, number, number, number, number)
	if p.visible then
		local y, pitch = Ghost.seat(p.x, p.z, p.yaw, VehiclePuppet.length(kind), heightAt)
		return p.x, y + VehiclePuppet.baseOffset(kind), p.z, p.yaw, pitch
	end
	return p.x, Ghost.HIDDEN_Y, p.z, p.yaw, 0
end

-- view(buffer, now, kinds, heightAt, visit) -> n: one client frame, pure. Samples the buffer at `now` and
-- calls `visit(id, pose, kind, x, y, z, yaw, pitch)` for every sampled vehicle whose kind is known:
-- `pose` is the sampled (interpolated) pose, the five numbers are `seen` (what the root part is given).
-- `render` places the models from exactly these calls and the headless replay (tools/sim) records them,
-- so what the replay measures is what the game draws. Returns the number of vehicles visited.
export type Kinds = { [number]: { kind: string, color: string? } }
function Ghost.view(
	buffer: Buffer,
	now: number,
	kinds: Kinds,
	heightAt: (x: number, z: number) -> number,
	visit: (
		id: number,
		pose: Pose,
		kind: { kind: string, color: string? },
		x: number,
		y: number,
		z: number,
		yaw: number,
		pitch: number
	) -> ()
): number
	local n = 0
	for id, p in buffer:sample(now) do
		local k = kinds[id]
		if k then
			n += 1
			visit(id, p, k, Ghost.seen(p, k.kind, heightAt))
		end
	end
	return n
end

-- rootCFrame(lib, x, y, z, yaw, pitch, visible): the root part's CFrame for a `seen` pose: at (x, y, z),
-- facing the HTML yaw (Config/Units adds the engine's pi), a visible vehicle pitched nose-up by `pitch`
-- about its own X axis. `lib` supplies CFrame and Vector3 (PartBuilder.engineLib() in the game,
-- @lune/roblox in the specs), so the same expression is checked headless.
function Ghost.rootCFrame(
	lib: { CFrame: any, Vector3: any },
	x: number,
	y: number,
	z: number,
	yaw: number,
	pitch: number,
	visible: boolean
): any
	local level = lib.CFrame.new(lib.Vector3.new(x, y, z)) * lib.CFrame.Angles(0, Units.robloxYaw(yaw), 0)
	return if visible then level * lib.CFrame.Angles(pitch, 0, 0) else level
end

-- render(buffer, now, folder, kinds, heightAt, models): engine only. `kinds` maps id -> {kind, color};
-- `models` caches the placeholder Model per id (built from Traffic/VehiclePuppet at the true box).
-- Moves every visible root with one BulkMoveTo (HANDOFF rule 4); hidden ghosts park far below.
function Ghost.render(
	buffer: Buffer,
	now: number,
	folder: Instance,
	kinds: Kinds,
	heightAt: (x: number, z: number) -> number,
	models: { [number]: Model }
): number
	local lib = PartBuilder.engineLib()
	local parts, cframes = {}, {}
	Ghost.view(buffer, now, kinds, heightAt, function(id, p, k, x, y, z, yaw, pitch)
		local model = models[id]
		if not model then
			local spec = VehiclePuppet.spec(k.kind, { color = k.color, name = `Ghost_{id}` })
			local built = PartBuilder.instantiate(spec, lib) :: Model
			built.Parent = folder
			models[id] = built
			model = built
		end
		if model.PrimaryPart then
			table.insert(parts, model.PrimaryPart)
			table.insert(cframes, Ghost.rootCFrame(lib, x, y, z, yaw, pitch, p.visible))
		end
	end)
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
	return #parts
end

return Ghost
