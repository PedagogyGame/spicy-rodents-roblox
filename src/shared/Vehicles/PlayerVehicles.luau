--!strict
-- ReplicatedStorage.Shared.Vehicles.PlayerVehicles
-- The pure bookkeeping of every player-enterable vehicle (BUILD_PLAN §1.4 Vehicles/PlayerVehicles,
-- §1.5 Devices, §4.4 #5): who sits in which driver seat, who holds which key, and whether a vehicle
-- is parked. Keys only change hands while the vehicle is parked: a driver who drops out of the top
-- two keeps driving until they exit, then the key passes (§1.5). The engine side (prompts, seat
-- weld, network ownership, the camera switch) lives in Server/Actors/DeviceService and reads this.
-- Interface: new() -> Fleet; add(f, id, kind, x, z, yaw); get(f, id); enter(f, id, driver, ctx)
--   -> (ok, reason); exit(f, driver) -> vehicleId?; vehicleOf(f, driver); setMotion(f, id, speed);
--   grantKeys(f, group, holders) (group "humanDriver" | "police"); keyHolder(f, id) -> driver?;
--   check(f) -> (ok, errors)
-- Drivers are numbers (Player.UserId). Pure. No side effects on require.

local VehicleKinds = require("./VehicleKinds")

export type Vehicle = {
	id: string,
	kind: string,
	x: number,
	z: number,
	yaw: number,
	driver: number?,
	key: number?, -- current key holder (keyed kinds only)
	pendingKey: number | false | nil, -- the next holder, applied when parked (false = nobody)
	speed: number,
	parked: boolean,
}

export type Fleet = {
	vehicles: { [string]: Vehicle },
	order: { string },
	byDriver: { [number]: string },
}

export type EnterCtx = {
	human: boolean?,
	officer: boolean?,
	paidRental: boolean?,
}

local PlayerVehicles = {}

-- a vehicle counts as parked below this speed (studs/s) with no driver input
PlayerVehicles.PARKED_SPEED = 0.5

local function group(kind: string): string?
	local access = VehicleKinds.kind(kind).access
	if access == "humanDriver" or access == "police" then
		return access
	end
	return nil
end

function PlayerVehicles.new(): Fleet
	return { vehicles = {}, order = {}, byDriver = {} }
end

function PlayerVehicles.add(f: Fleet, id: string, kind: string, x: number, z: number, yaw: number): Vehicle
	VehicleKinds.kind(kind)
	assert(f.vehicles[id] == nil, `PlayerVehicles: duplicate id {id}`)
	local v: Vehicle = {
		id = id,
		kind = kind,
		x = x,
		z = z,
		yaw = yaw,
		driver = nil,
		key = nil,
		pendingKey = nil,
		speed = 0,
		parked = true,
	}
	f.vehicles[id] = v
	table.insert(f.order, id)
	return v
end

function PlayerVehicles.get(f: Fleet, id: string): Vehicle?
	return f.vehicles[id]
end

function PlayerVehicles.vehicleOf(f: Fleet, driver: number): string?
	return f.byDriver[driver]
end

function PlayerVehicles.keyHolder(f: Fleet, id: string): number?
	local v = f.vehicles[id]
	return if v then v.key else nil
end

local function applyPendingKey(v: Vehicle)
	if v.pendingKey ~= nil and v.parked and v.driver == nil then
		v.key = if v.pendingKey == false then nil else v.pendingKey :: number
		v.pendingKey = nil
	end
end

-- enter(f, id, driver, ctx): the driver takes the seat if the kind's access rule allows it.
function PlayerVehicles.enter(f: Fleet, id: string, driver: number, ctx: EnterCtx): (boolean, string?)
	local v = f.vehicles[id]
	if not v then
		return false, "no such vehicle"
	end
	if v.driver ~= nil then
		return false, "occupied"
	end
	if f.byDriver[driver] then
		return false, "already driving"
	end
	local ok, reason = VehicleKinds.mayDrive(v.kind, {
		keyHolder = v.key == driver,
		officer = ctx.officer,
		paidRental = ctx.paidRental,
		human = ctx.human,
	})
	if not ok then
		return false, reason
	end
	v.driver = driver
	f.byDriver[driver] = id
	return true, nil
end

-- exit(f, driver): leaves the seat; a key that changed hands meanwhile passes now if parked.
function PlayerVehicles.exit(f: Fleet, driver: number): string?
	local id = f.byDriver[driver]
	if not id then
		return nil
	end
	local v = f.vehicles[id]
	v.driver = nil
	f.byDriver[driver] = nil
	applyPendingKey(v)
	return id
end

function PlayerVehicles.setMotion(f: Fleet, id: string, speed: number, x: number?, z: number?, yaw: number?)
	local v = f.vehicles[id]
	if not v then
		return
	end
	v.speed = speed
	v.x, v.z, v.yaw = x or v.x, z or v.z, yaw or v.yaw
	v.parked = math.abs(speed) < PlayerVehicles.PARKED_SPEED
	applyPendingKey(v)
end

-- grantKeys(f, group, holders): the Ladder's key holders for a group (top two drivers or officers),
-- assigned to that group's vehicles in id order. A vehicle that is driven or moving keeps its key
-- until it is parked and empty (§1.5); a current holder keeps their own vehicle.
function PlayerVehicles.grantKeys(f: Fleet, g: string, holders: { number })
	local wanted: { [number]: boolean } = {}
	for _, h in holders do
		wanted[h] = true
	end
	local ids = {}
	for _, id in f.order do
		if group(f.vehicles[id].kind) == g then
			table.insert(ids, id)
		end
	end
	-- holders that already hold a key in this group keep it
	local placed: { [number]: boolean } = {}
	for _, id in ids do
		local v = f.vehicles[id]
		if v.key and wanted[v.key] then
			placed[v.key] = true
			v.pendingKey = nil
		end
	end
	local queue = {}
	for _, h in holders do
		if not placed[h] then
			table.insert(queue, h)
		end
	end
	for _, id in ids do
		local v = f.vehicles[id]
		if v.key == nil or not wanted[v.key] then
			local nextHolder = table.remove(queue, 1)
			v.pendingKey = if nextHolder then nextHolder else false
			applyPendingKey(v)
		end
	end
end

-- check(f): invariants: byDriver is the inverse of the seats; no driver in two seats.
function PlayerVehicles.check(f: Fleet): (boolean, { string })
	local errors = {}
	for driver, id in f.byDriver do
		local v = f.vehicles[id]
		if not v or v.driver ~= driver then
			table.insert(errors, `driver {driver} maps to {id} which does not seat them`)
		end
	end
	for _, id in f.order do
		local v = f.vehicles[id]
		if v.driver and f.byDriver[v.driver] ~= id then
			table.insert(errors, `vehicle {id} seats {v.driver} who is not mapped back`)
		end
	end
	return #errors == 0, errors
end

return PlayerVehicles
