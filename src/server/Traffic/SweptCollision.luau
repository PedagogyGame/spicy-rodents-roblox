--!strict
-- ServerScriptService.Server.Traffic.SweptCollision
-- The fatal test for every squirrel actor with teleport flags.
-- Interface (BUILD_PLAN §1.4, D9): step, markTeleported; signal RunOver(actor, vehicle, driver?)
--
-- The server-side port of v5.4's finishTrafficFrame (traffic.md §8.1-§8.4, L15870-15897) for many
-- squirrels: every tick, every squirrel actor's move (previous tick -> this tick) is swept against every
-- fleet vehicle's move (previous pose -> current pose) with the exact Shared/Traffic/Swept maths and the
-- vehicle's logical box (traffic.md §2, §9: sedan 2.35 x 4.45 x 2.04 u, delivery van 3.0 x 5.9 x 3.65,
-- ice cream van 3.35 x 6.55 x 3.58, trolley 3.5 x 11 x 4.12, dump truck 3.35 x 8.9 x 4.12, RV
-- 3.2 x 8.7 x 4.3). Per vehicle, in fleet order: invisible at either end -> skip; travel < 1e-5 u
-- (stationary never kills) or travel > max(12, 80 dt + 2) u (a wrap) -> skip; a vehicle or actor marked
-- teleported this tick -> skip (D9: every scripted reposition and every possession resets the previous
-- pose; traffic.md verifier 1). First hit wins per squirrel. A sphere broad phase (Swept.broadPhase)
-- rejects far pairs before the exact test. Pure and steppable: `step(actors, vehicles, dt)` returns the
-- hits; the owning service emits `RunOver(actor, vehicle, driver?)`. Budget (spike S4): 15 squirrels x
-- 50 vehicles <= 0.5 ms per tick.

local Import = require("../Import")
local Swept = Import.shared("Traffic/Swept") :: typeof(require("../../shared/Traffic/Swept"))
local Units = Import.shared("Config/Units") :: typeof(require("../../shared/Config/Units"))
local Boxes = Import.shared("Traffic/Boxes") :: typeof(require("../../shared/Traffic/Boxes"))

local SweptCollision = {}
SweptCollision.__index = SweptCollision

export type Box = { width: number, length: number, height: number }

export type ActorPose = {
	id: any,
	x: number,
	y: number,
	z: number, -- reference point: standing height (surface + 0.18 u), traffic.md §8.4
	prevX: number,
	prevY: number,
	prevZ: number,
	teleported: boolean?, -- set by the caller for this tick (possession, respawn, interior transit)
}

export type VehiclePose = {
	id: any,
	kind: string, -- key into the box table (sedan, delivery_van, ice_cream_van, trolley, dump_truck, rv, cart)
	x: number,
	y: number,
	z: number, -- footprint centre at the base (terrain + 0.04 u for sedans, traffic.md §8.4)
	yaw: number, -- HTML heading
	prevX: number,
	prevY: number,
	prevZ: number,
	prevYaw: number,
	visible: boolean,
	prevVisible: boolean,
	teleported: boolean?, -- a scripted reposition this tick: never swept
	box: Box?, -- overrides the kind's box (player vehicles with true dimensions)
	label: string?,
	driver: any?,
}

export type Hit = { actorId: any, vehicleId: any, kind: string, label: string?, driver: any? }

export type Stats = { pairs: number, narrow: number, hits: number, skippedVehicles: number }

export type SweptCollision = typeof(setmetatable(
	{} :: {
		boxes: { [string]: Box },
		scale: number,
		_teleported: { [any]: boolean },
		stats: Stats,
	},
	SweptCollision
))

-- Logical boxes in studs: the shared table (Traffic/Boxes; traffic.md §2 and §9 in HTML units x 2.5), so
-- the AI fleet, the placeholder vehicles and this test agree. Motorcycles are listed there but are not in
-- the fatal fleet (traffic.md §5.12): their pose carries no box here unless the caller passes one.
local BOXES: { [string]: Box } = {}
for kind, b in Boxes.BOXES do
	if Boxes.FATAL[kind] then
		BOXES[kind] = b
	end
end
SweptCollision.BOXES = BOXES

function SweptCollision.new(opts: { boxes: { [string]: Box }?, scale: number? }?): SweptCollision
	local o = opts or {}
	local self = setmetatable({
		boxes = o.boxes or SweptCollision.BOXES,
		scale = o.scale or Units.STUDS_PER_UNIT,
		_teleported = {} :: { [any]: boolean },
		stats = { pairs = 0, narrow = 0, hits = 0, skippedVehicles = 0 },
	}, SweptCollision)
	return self
end

-- markTeleported(actorId): the actor's previous pose is invalid for the next step (possession handoff,
-- respawn, interior transit, the Reset button).
function SweptCollision.markTeleported(self: SweptCollision, actorId: any)
	self._teleported[actorId] = true
end

-- boxFor(vehicle): the logical box, from the override or the kind table.
function SweptCollision.boxFor(self: SweptCollision, vehicle: VehiclePose): Box?
	return vehicle.box or self.boxes[vehicle.kind]
end

-- step(actors, vehicles, dt) -> hits. Vehicles in fleet order; first hit wins per actor.
function SweptCollision.step(
	self: SweptCollision,
	actors: { ActorPose },
	vehicles: { VehiclePose },
	dt: number
): { Hit }
	local hits: { Hit } = {}
	local stats = self.stats
	stats.pairs = 0
	stats.narrow = 0
	stats.hits = 0
	stats.skippedVehicles = 0
	local scale = self.scale
	local teleported = self._teleported
	local hitActor: { [any]: boolean } = {}
	local n = #actors
	for _, v in vehicles do
		if not v.visible or not v.prevVisible or v.teleported then
			stats.skippedVehicles += 1
			continue
		end
		local tdx, tdz = v.x - v.prevX, v.z - v.prevZ
		local travel = math.sqrt(tdx * tdx + tdz * tdz)
		if Swept.travelFilterSkips(travel, dt, scale) then
			stats.skippedVehicles += 1
			continue
		end
		local box = self:boxFor(v)
		if not box then
			stats.skippedVehicles += 1
			continue
		end
		local w, l, h = box.width, box.length, box.height
		for i = 1, n do
			local a = actors[i]
			if hitActor[a.id] or a.teleported or teleported[a.id] then
				continue
			end
			stats.pairs += 1
			if
				Swept.broadPhase(
					a.prevX,
					a.prevY,
					a.prevZ,
					a.x,
					a.y,
					a.z,
					v.prevX,
					v.prevY,
					v.prevZ,
					v.x,
					v.y,
					v.z,
					v.prevYaw,
					v.yaw,
					w,
					l,
					h,
					scale
				)
			then
				stats.narrow += 1
				if
					Swept.hitN(
						a.prevX,
						a.prevY,
						a.prevZ,
						a.x,
						a.y,
						a.z,
						v.prevX,
						v.prevY,
						v.prevZ,
						v.x,
						v.y,
						v.z,
						v.prevYaw,
						v.yaw,
						w,
						l,
						h,
						scale
					)
				then
					hitActor[a.id] = true
					stats.hits += 1
					table.insert(
						hits,
						{ actorId = a.id, vehicleId = v.id, kind = v.kind, label = v.label, driver = v.driver }
					)
				end
			end
		end
	end
	-- teleport marks apply to one step
	for id in teleported do
		teleported[id] = nil
	end
	return hits
end

return SweptCollision
