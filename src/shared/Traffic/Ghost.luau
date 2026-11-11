--!strict
-- ReplicatedStorage.Shared.Traffic.Ghost
-- Ghost vehicles: the server pose stream codec and the client interpolation buffer (BUILD_PLAN D9, §1.6
-- VehiclePoses, W1 #9; traffic.md §13 "render on clients with interpolation, about 100 ms behind").
-- Interface: encode(pose) -> record (Net/Schemas.VehiclePose fields); decode(record) -> Pose;
--            new(opts) -> Buffer; Buffer:push(t, records); Buffer:sample(now) -> { [id] = Pose };
--            seat(x, z, yaw, length, heightAt) -> y, pitch; seen(pose, kind, heightAt) -> x, y, z, yaw, pitch
--            (pure: the root pose a player sees); render(buffer, now, folder, kinds, heightAt, models)
--            (engine: placeholder models, one BulkMoveTo).
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

-- render(buffer, now, folder, kinds, heightAt, models): engine only. `kinds` maps id -> {kind, color};
-- `models` caches the placeholder Model per id (built from Traffic/VehiclePuppet at the true box).
-- Moves every visible root with one BulkMoveTo (HANDOFF rule 4); hidden ghosts park far below.
function Ghost.render(
	buffer: Buffer,
	now: number,
	folder: Instance,
	kinds: { [number]: { kind: string, color: string? } },
	heightAt: (x: number, z: number) -> number,
	models: { [number]: Model }
): number
	local lib = PartBuilder.engineLib()
	local parts, cframes = {}, {}
	for id, p in buffer:sample(now) do
		local model = models[id]
		local k = kinds[id]
		if not model and k then
			local spec = VehiclePuppet.spec(k.kind, { color = k.color, name = `Ghost_{id}` })
			local built = PartBuilder.instantiate(spec, lib) :: Model
			built.Parent = folder
			models[id] = built
			model = built
		end
		if model and model.PrimaryPart and k then
			table.insert(parts, model.PrimaryPart)
			local x, y, z, yaw, pitch = Ghost.seen(p, k.kind, heightAt)
			local level = Units.yawCFrame(yaw, Vector3.new(x, y, z))
			table.insert(cframes, if p.visible then level * CFrame.Angles(pitch, 0, 0) else level)
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
	return #parts
end

return Ghost
