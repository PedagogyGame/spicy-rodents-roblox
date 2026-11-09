--!strict
-- ReplicatedStorage.Shared.Traffic.Ghost
-- Ghost vehicles: the server pose stream codec and the client interpolation buffer (BUILD_PLAN D9, §1.6
-- VehiclePoses, W1 #9; traffic.md §13 "render on clients with interpolation, about 100 ms behind").
-- Interface: encode(pose) -> record (Net/Schemas.VehiclePose fields); decode(record) -> Pose;
--            new(opts) -> Buffer; Buffer:push(t, records); Buffer:sample(now) -> { [id] = Pose };
--            render(buffer, now, folder, lib, kinds) (engine: placeholder models, one BulkMoveTo).
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
Ghost.DELAY = 0.1 -- render 100 ms behind the newest snapshot

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
				return snaps[n].poses -- hold the newest (no extrapolation: a stopped car must not creep)
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
			local y = if p.visible then heightAt(p.x, p.z) + VehiclePuppet.baseOffset(k.kind) else -500
			table.insert(parts, model.PrimaryPart)
			table.insert(cframes, Units.yawCFrame(p.yaw, Vector3.new(p.x, y, p.z)))
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
	return #parts
end

return Ghost
