--!strict
-- ReplicatedStorage.Shared.Vehicles.VehicleKinds
-- Every player-enterable vehicle kind as a CarMotor parameter set plus its access rule and its
-- placeholder interior (BUILD_PLAN §1.4 Vehicles/VehicleKinds, §1.5 Devices, §3.18; brief v2 §13a,
-- §14, §15). Kinds: car (the police patrol car), cart (the golf cart: open; one of the shared three since D29, out of
-- the fatal fleet), bike (arcade, balance-free, not in the fleet; Q8 default), pickup and
-- suv (keys for the top two ranked humans, `Ladder.subroles.humanDriver`), jetski (water surface,
-- rental), moped and escooter (owner D29). The town's SHARED little vehicles (owner D29: 3 golf carts, 2 mopeds, 5
-- stand-up electric scooters, Shared/Vehicles/SharedRides) are the kinds marked `shared`: anyone in a person's body
-- rides one, no key, no rental, no police trouble (policeIgnore), and a bump never kills (Server/Vehicles/RideBumps).
-- Logical boxes follow traffic §1 (sedan 2.35 x 4.45 x 2.04 u); the others are scaled from
-- it. Speeds are arcade defaults in studs/s (sedan AI lanes run 6.5-9.5 u/s = 16-24 st/s, traffic §4).
-- Every interior has a driver seat, a dash and an `EyeSocket` (first person on entry, brief v2 §14);
-- offsets are body-local studs (+Z forward in the HTML convention; Placeholder flips at the CFrame).
-- Until data/vehicles/kinds.json compiles, these module defaults are the source; `fromData` merges it.
-- Interface: kind(id), list(), mayDrive(kindId, ctx) -> (ok, reason), isFleet(kindId), isShared(kindId),
--   policeIgnore(kindId), stands(kindId), fromData(t)
-- Pure. No side effects on require.

export type Interior = {
	seat: { number }, -- driver seat centre (x, y, z), body-local studs from the root
	eye: { number }, -- EyeSocket (camera position in first person)
	dash: { number }, -- dash centre
	dashSize: { number },
	open: boolean, -- no roof (cart, bike, jet ski)
}

export type Kind = {
	id: string,
	motor: "car" | "bike" | "jetski",
	size: { number }, -- width, height, length (studs)
	maxSpeed: number, -- studs/s forward
	reverseSpeed: number,
	accel: number, -- studs/s^2
	brake: number,
	drag: number, -- coasting deceleration, studs/s^2
	maxSteer: number, -- radians at the front wheels
	steerRate: number, -- rad/s
	wheelbase: number, -- studs
	access: "anyone" | "humanDriver" | "police" | "rental",
	fleet: boolean, -- in the fatal fleet (traffic tests squirrels against it)
	fleetMaxSpeed: number?, -- the fleet speed cap for carts
	shared: boolean?, -- one of the town's shared little vehicles (owner D29): anyone in a person's body, no key
	stand: boolean?, -- the rider stands (the electric scooter): the hidden seat is a standing body's height over the deck
	wheels: number,
	color: { number },
	interior: Interior,
}

export type AccessCtx = {
	keyHolder: boolean?, -- the player holds this vehicle's key (pickup, SUV, patrol car)
	officer: boolean?, -- the player is a police officer (police carts)
	paidRental: boolean?, -- a jet ski rental is running
	human: boolean?, -- only human bodies drive
}

local st = 2.5

local function interior(open: boolean, w: number, h: number, l: number): Interior
	return {
		seat = { -w * 0.2, -h * 0.1, l * 0.05 },
		eye = { -w * 0.2, h * 0.32, l * 0.02 },
		dash = { 0, h * 0.05, l * 0.24 },
		dashSize = { w * 0.9, h * 0.18, 0.4 },
		open = open,
	}
end

local function make(t: { [string]: any }): Kind
	local s = t.size
	t.interior = t.interior or interior(t.open == true, s[1], s[2], s[3])
	t.open = nil
	return table.freeze(t) :: any
end

local KINDS: { [string]: Kind } = {
	car = make({
		id = "car",
		motor = "car",
		size = { 2.35 * st, 2.04 * st, 4.45 * st },
		maxSpeed = 70,
		reverseSpeed = 18,
		accel = 26,
		brake = 60,
		drag = 7,
		maxSteer = 0.6,
		steerRate = 2.6,
		wheelbase = 2.8 * st,
		access = "police",
		fleet = true,
		wheels = 4,
		color = { 0.1, 0.12, 0.2 },
	}),
	-- The golf cart is one of the town's shared three (owner D29); since D29 no player cart is in the fatal fleet (a
	-- bump knocks someone aside, never more). The shared three's speeds: the scooter about a brisk run (people sprint
	-- at 28), the cart a little quicker, the moped the quickest.
	cart = make({
		id = "cart",
		motor = "car",
		-- 6.25 tall (the traffic's carts, Traffic/Boxes, are 4.75): the drawn canopy is the top of the box, and a seated
		-- R15's head on the bench (5.72 up) clears its underside (6.0) by 0.28 (owner check sheet BIKES_CHECK)
		size = { 1.5 * st, 2.5 * st, 2.6 * st },
		maxSpeed = 26,
		reverseSpeed = 8,
		accel = 15,
		brake = 40,
		drag = 6,
		maxSteer = 0.65,
		steerRate = 3,
		wheelbase = 1.7 * st,
		access = "anyone",
		shared = true,
		fleet = false,
		fleetMaxSpeed = 22,
		wheels = 4,
		color = { 0.92, 0.92, 0.88 },
		open = true,
	}),
	bike = make({
		id = "bike",
		motor = "bike",
		size = { 0.5 * st, 1.2 * st, 1.8 * st },
		maxSpeed = 28,
		reverseSpeed = 3,
		accel = 12,
		brake = 30,
		drag = 4,
		maxSteer = 0.75,
		steerRate = 3.5,
		wheelbase = 1.1 * st,
		access = "anyone",
		fleet = false,
		wheels = 2,
		color = { 0.75, 0.15, 0.15 },
		open = true,
	}),
	pickup = make({
		id = "pickup",
		motor = "car",
		size = { 2.5 * st, 2.3 * st, 5.4 * st },
		maxSpeed = 60,
		reverseSpeed = 15,
		accel = 20,
		brake = 55,
		drag = 7,
		maxSteer = 0.55,
		steerRate = 2.4,
		wheelbase = 3.3 * st,
		access = "humanDriver",
		fleet = true,
		wheels = 4,
		color = { 0.55, 0.25, 0.18 },
	}),
	suv = make({
		id = "suv",
		motor = "car",
		size = { 2.5 * st, 2.5 * st, 4.9 * st },
		maxSpeed = 62,
		reverseSpeed = 15,
		accel = 22,
		brake = 55,
		drag = 7,
		maxSteer = 0.55,
		steerRate = 2.4,
		wheelbase = 3.0 * st,
		access = "humanDriver",
		fleet = true,
		wheels = 4,
		color = { 0.2, 0.3, 0.25 },
	}),
	jetski = make({
		id = "jetski",
		motor = "jetski",
		size = { 1.2 * st, 1.1 * st, 3.0 * st },
		maxSpeed = 45,
		reverseSpeed = 6,
		accel = 18,
		brake = 20,
		drag = 5,
		maxSteer = 0.9,
		steerRate = 3,
		wheelbase = 1.6 * st,
		access = "rental",
		fleet = false,
		wheels = 0,
		color = { 0.95, 0.75, 0.1 },
		open = true,
	}),
}

-- The moped (a small motor scooter, seated: the quickest of the shared three) and the stand-up electric scooter (quick
-- to turn, about a brisk run). Both lean into turns (the bike motor). Mild colours: a buttercream moped, a sky-blue
-- scooter.
KINDS.moped = make({
	id = "moped",
	motor = "bike",
	size = { 1.3, 2.6, 4.0 },
	maxSpeed = 34,
	reverseSpeed = 4,
	accel = 16,
	brake = 34,
	drag = 5,
	maxSteer = 0.7,
	steerRate = 3.4,
	wheelbase = 2.65,
	access = "anyone",
	shared = true,
	fleet = false,
	wheels = 2,
	color = { 0.93, 0.83, 0.55 },
	open = true,
})
KINDS.escooter = make({
	id = "escooter",
	motor = "bike",
	size = { 1.0, 3.2, 3.2 },
	maxSpeed = 22,
	reverseSpeed = 3,
	accel = 18,
	brake = 36,
	drag = 5,
	maxSteer = 0.85,
	steerRate = 4.5,
	wheelbase = 2.3,
	access = "anyone",
	shared = true,
	stand = true,
	fleet = false,
	wheels = 2,
	color = { 0.45, 0.68, 0.88 },
	open = true,
})

local ORDER = { "car", "cart", "bike", "pickup", "suv", "jetski", "moped", "escooter" }

local VehicleKinds = {}

function VehicleKinds.list(): { string }
	return table.clone(ORDER)
end

function VehicleKinds.kind(id: string): Kind
	return KINDS[id] or error(`VehicleKinds: unknown kind {id}`)
end

function VehicleKinds.has(id: string): boolean
	return KINDS[id] ~= nil
end

function VehicleKinds.isFleet(id: string): boolean
	return VehicleKinds.kind(id).fleet
end

-- One of the town's shared little vehicles (owner D29): anyone in a person's body may ride it, nobody owns it.
function VehicleKinds.isShared(id: string): boolean
	local k = KINDS[id]
	return k ~= nil and k.shared == true
end

-- Whether the police take no notice of a vehicle of this kind (owner D29: "you do not get tickets or problems with the
-- police with them"): no ticket, no wanted level, no chase for riding a shared vehicle, whatever a police rule says of
-- other vehicles. Any police or ticket rule asks this first.
function VehicleKinds.policeIgnore(id: string): boolean
	return VehicleKinds.isShared(id)
end

-- Whether the rider stands (the electric scooter): the client plays a standing clip on its seat, not the sit.
function VehicleKinds.stands(id: string): boolean
	local k = KINDS[id]
	return k ~= nil and k.stand == true
end

-- Who may take the wheel (brief v2 §13a, §15; §1.5 Devices): carts and bikes anyone; pickups and
-- SUVs the key holders (top two ranked humans); patrol cars the key-holding officers; jet skis a
-- running rental. Only human bodies drive.
function VehicleKinds.mayDrive(kindId: string, ctx: AccessCtx): (boolean, string?)
	local k = KINDS[kindId]
	if not k then
		return false, "unknown kind"
	end
	if ctx.human == false then
		return false, "only people drive"
	end
	if k.access == "anyone" then
		return true, nil
	elseif k.access == "humanDriver" then
		return ctx.keyHolder == true, if ctx.keyHolder then nil else "needs the key"
	elseif k.access == "police" then
		if not ctx.officer then
			return false, "police only"
		end
		return ctx.keyHolder == true, if ctx.keyHolder then nil else "needs the key"
	else
		return ctx.paidRental == true, if ctx.paidRental then nil else "rent it first"
	end
end

-- fromData(t): merges data/vehicles/kinds.json entries (studs) over the defaults; unknown fields
-- are ignored. Returns the merged ids.
function VehicleKinds.fromData(t: { [string]: { [string]: any } }): { string }
	local ids = {}
	for id, entry in t do
		local base = KINDS[id]
		local merged: { [string]: any } = if base then table.clone(base :: any) else { id = id }
		for key, value in entry do
			if merged[key] ~= nil or key == "interior" then
				merged[key] = value
			end
		end
		KINDS[id] = make(merged)
		table.insert(ids, id)
	end
	return ids
end

return VehicleKinds
