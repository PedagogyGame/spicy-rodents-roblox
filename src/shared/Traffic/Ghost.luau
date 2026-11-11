--!strict
-- ReplicatedStorage.Shared.Traffic.Ghost
-- Ghost vehicles: the server pose stream codec and the client interpolation buffer (BUILD_PLAN D9, §1.6
-- VehiclePoses, W1 #9; traffic.md §13 "render on clients with interpolation, about 100 ms behind").
-- Interface: encode(pose) -> record (Net/Schemas.VehiclePose fields); decode(record) -> Pose;
--            new(opts) -> Buffer; Buffer:push(t, records); Buffer:sample(now) -> { [id] = Pose };
--            seat(x, z, yaw, length, heightAt, track?) -> y, pitch, roll;
--            seen(pose, kind, heightAt) -> x, y, z, yaw, pitch, roll
--            (pure: the root pose a player sees); view(buffer, now, kinds, heightAt, visit) (pure: one
--            client frame, `visit` called per vehicle with its sampled and seen pose);
--            rootCFrame(lib, x, y, z, yaw, pitch, visible, roll?) (the CFrame of that pose, lib = PartBuilder.Lib);
--            render(buffer, now, folder, kinds, heightAt, models) (engine: placeholder models, one BulkMoveTo).
--
-- Records are 13 bytes (u16 id, f32 x, f32 z, u8 yaw, u8 speed, u8 bits). The server never sends y:
-- clients take it from the ground they are given (traffic.md §13 "Terrain"; the game passes
-- World/RoadSurface.ground, the roads as drawn over World/Height). A teleported pose
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
Ghost.DELAY = 0.13 -- render this far behind the newest snapshot (about two sends)
-- Owner 2026-11-10: "some of the cars are glitching out". Snapshots were timed by when each packet
-- ARRIVED, with barely one send interval of buffer: a late or lost packet froze every car and the next
-- one threw it forward. Three things now keep cars moving evenly:
--   * each send carries the server's own clock in a stamp record (id STAMP_ID, the seconds in x);
--     Ghost.newClock turns stamps into local times with the smallest delay seen, so snapshots are spaced
--     as the server spaced them however the packets bunch up
--   * when the newest snapshot is older than the render time, a moving car carries on along its last
--     seen velocity for up to EXTRAPOLATE seconds (a stopped car has no velocity, so it does not creep)
--   * on a slope the car pitches with the road (the height under its front and rear), not flat
Ghost.STAMP_ID = 65535
Ghost.EXTRAPOLATE = 0.12

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

local function lerpAngle(a: number, b: number, t: number): number
	local d = math.atan2(math.sin(b - a), math.cos(b - a))
	return a + d * t
end

-- stamp(serverSeconds): the record that carries the server's clock in a send.
function Ghost.stamp(serverSeconds: number): { [string]: number }
	return { id = Ghost.STAMP_ID, x = serverSeconds, z = 0, yaw = 0, speed = 0, bits = 0 }
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

-- A clock that places server stamps on the local timeline: stamp + the smallest (arrival - stamp) seen
-- lately. The least-delayed packet defines the offset, so jitter never moves a snapshot; the offset is
-- allowed to drift up slowly, so a clock that falls behind recovers.
export type StampClock = { offset: number?, localTime: (self: StampClock, stamp: number, arrival: number) -> number }
function Ghost.newClock(): StampClock
	return {
		offset = nil,
		localTime = function(self: StampClock, stamp: number, arrival: number): number
			local d = arrival - stamp
			local o = self.offset
			if o == nil or d < o or d > o + 2 then
				o = d -- the first packet, a less delayed one, or a server restart
			else
				o += 0.0002 -- drift toward later arrivals by 0.2 ms per send
			end
			self.offset = o
			return stamp + o
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
			table.insert(self.snaps, { t = t, poses = poses })
			while #self.snaps > keep do
				table.remove(self.snaps, 1)
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
					if pa == nil or pb.teleported or pb.stopped or not pa.visible or not pb.visible then
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
			local u = (rt - a.t) / (b.t - a.t)
			local out = {}
			for id, pb in b.poses do
				local pa = a.poses[id]
				if pa == nil or pb.teleported or not pa.visible or not pb.visible then
					out[id] = pb -- snap: new, teleported, or appearing/disappearing
				else
					out[id] = {
						id = id,
						x = pa.x + (pb.x - pa.x) * u,
						z = pa.z + (pb.z - pa.z) * u,
						yaw = lerpAngle(pa.yaw, pb.yaw, u),
						speed = pa.speed + (pb.speed - pa.speed) * u,
						visible = pb.visible,
						beacons = pb.beacons,
						teleported = false,
						stopped = pb.stopped,
					}
				end
			end
			return out
		end,
	}
	return buf
end

-- seat(x, z, yaw, length, heightAt, track?) -> y, pitch, roll: where a vehicle of that length sits on the
-- ground at (x, z) heading `yaw` (HTML yaw: it faces (sin yaw, cos yaw)): the mean of the heights under
-- its front and rear axles, the nose-up pitch (radians, for CFrame.Angles(pitch, 0, 0) after
-- Units.yawCFrame) that lays it along the slope between them, and, given its track (the distance
-- between its left and right wheels; VehiclePuppet.track), the roll (radians, right side up, for
-- CFrame.Angles(0, 0, roll) after the pitch) that lays it across the slope between them. Without the roll a car on a cambered road or a hillside sits level, one
-- side's wheels in the road and the other's in the air (on the town's rolled roads, 0.2 to 0.45 st on
-- the RVs, dump trucks and the trolley: tools/sim detectors/surface). Pure.
function Ghost.seat(
	x: number,
	z: number,
	yaw: number,
	length: number,
	heightAt: (x: number, z: number) -> number,
	track: number?
): (number, number, number)
	local half = math.max(length, 1) * 0.36 -- the axles sit about 36 % of the length from the middle
	local fx, fz = math.sin(yaw), math.cos(yaw)
	local front = heightAt(x + fx * half, z + fz * half)
	local rear = heightAt(x - fx * half, z - fz * half)
	local pitch = math.atan2(front - rear, 2 * half)
	local roll = 0
	if track and track > 0 then
		-- the vehicle's right, (-fz, fx): Units.yawCFrame's RightVector for this yaw
		local side = track / 2
		local right = heightAt(x - fz * side, z + fx * side)
		local left = heightAt(x + fz * side, z - fx * side)
		roll = math.clamp(math.atan2(right - left, track), -0.35, 0.35)
	end
	return (front + rear) / 2, math.clamp(pitch, -0.5, 0.5), roll
end

Ghost.HIDDEN_Y = -500 -- a hidden ghost parks this far below the map

-- seen(p, kind, heightAt) -> x, y, z, yaw, pitch, roll: the pose `render` gives the root part of a vehicle
-- of that kind for the sampled pose `p`: a visible one sits on the ground under its wheels (`seat`), its
-- centre half its box height above it, pitched and rolled with the ground; a hidden one parks at
-- HIDDEN_Y, level.
-- Yaw is the HTML yaw (Units.yawCFrame turns it into the engine's). Pure: the headless replay
-- (tools/sim/traffic_replay.luau) records exactly these numbers as "what the player sees".
function Ghost.seen(
	p: Pose,
	kind: string,
	heightAt: (x: number, z: number) -> number
): (number, number, number, number, number, number)
	if p.visible then
		local y, pitch, roll =
			Ghost.seat(p.x, p.z, p.yaw, VehiclePuppet.length(kind), heightAt, VehiclePuppet.track(kind))
		return p.x, y + VehiclePuppet.baseOffset(kind), p.z, p.yaw, pitch, roll
	end
	return p.x, Ghost.HIDDEN_Y, p.z, p.yaw, 0, 0
end

-- view(buffer, now, kinds, heightAt, visit) -> n: one client frame, pure. Samples the buffer at `now` and
-- calls `visit(id, pose, kind, x, y, z, yaw, pitch, roll)` for every sampled vehicle whose kind is known:
-- `pose` is the sampled (interpolated) pose, the six numbers are `seen` (what the root part is given).
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
		pitch: number,
		roll: number
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

-- rootCFrame(lib, x, y, z, yaw, pitch, visible, roll?): the root part's CFrame for a `seen` pose: at
-- (x, y, z), facing the HTML yaw (Config/Units adds the engine's pi), a visible vehicle pitched nose-up by
-- `pitch` about its own X axis, then rolled right side up by `roll` about its own Z axis. `lib` supplies CFrame and Vector3 (PartBuilder.engineLib() in the game,
-- @lune/roblox in the specs), so the same expression is checked headless.
function Ghost.rootCFrame(
	lib: { CFrame: any, Vector3: any },
	x: number,
	y: number,
	z: number,
	yaw: number,
	pitch: number,
	visible: boolean,
	roll: number?
): any
	local level = lib.CFrame.new(lib.Vector3.new(x, y, z)) * lib.CFrame.Angles(0, Units.robloxYaw(yaw), 0)
	if not visible then
		return level
	end
	local pitched = level * lib.CFrame.Angles(pitch, 0, 0)
	return if roll and roll ~= 0 then pitched * lib.CFrame.Angles(0, 0, roll) else pitched
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
	Ghost.view(buffer, now, kinds, heightAt, function(id, p, k, x, y, z, yaw, pitch, roll)
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
			table.insert(cframes, Ghost.rootCFrame(lib, x, y, z, yaw, pitch, p.visible, roll))
		end
	end)
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
	return #parts
end

return Ghost
