--!strict
-- ReplicatedStorage.Shared.Actors.PossessionState
-- Pure possession bookkeeping and the names both sides agree on (BUILD_PLAN §1.5, D1, D3; spike S2).
-- The ledger is the single truth of "who drives which body": a bijection between driver keys
-- (Player.UserId; Studio test players are negative, which is fine) and actor ids. Server/Actors/
-- Possession owns the only ledger; clients read the replicated `DriverUserId` attribute instead.
-- Also the 49-slot admission rule (Addendum B4) as a pure function, so RoleService and the tests
-- share it. No Instances, no side effects on require (Lune and the engine run it the same way).
-- Interface: ATTR, NET, HOLD_SECONDS, MAX_PLAYERS, newLedger(), bind, unbind, actorOf, driverOf,
-- count, check(ledger) -> (ok, errors), admits(admittedCount, max?) -> boolean

local Ladder = require("../Roles/Ladder")

local PossessionState = {}

-- Attributes on a body Model (server-written, replicated). MoveState/Clip/ClipT0 are D3's
-- replicated animation state for AI bodies; a driven body's own client animates from its motor.
PossessionState.ATTR = table.freeze({
	ActorId = "ActorId",
	Species = "Species",
	Driver = "DriverUserId", -- 0 = AI
	MoveState = "MoveState", -- "idle" | "walk" | "run"
	Clip = "Clip",
	ClipT0 = "ClipT0", -- workspace:GetServerTimeNow() when the clip phase was 0
	Speed = "Speed", -- studs per second the brain is moving at
})

-- ReplicatedStorage.<folder> holds these RemoteEvents (W0; W1 moves them into Shared/Net).
PossessionState.NET = table.freeze({
	folder = "PossessionNet",
	Granted = "Granted", -- server -> client: GrantPayload
	Released = "Released", -- server -> client: (actorId, why)
	Recover = "Recover", -- client -> server: the Roblox menu's Reset, routed to recovery
	-- Devices (§1.5 Devices; W1): vehicles and the drone. The body stays possessed.
	DeviceGranted = "DeviceGranted", -- server -> client: { device: "vehicle" | "drone", model, kind }
	DeviceReleased = "DeviceReleased", -- server -> client: (why)
	DeviceRequest = "DeviceRequest", -- client -> server: ("interact") enter the nearest vehicle or get out
})

-- Humans keep the AI's last move direction for up to this long, or until the first input (§1.5 step 5).
PossessionState.HOLD_SECONDS = 0.75
-- Addendum B4: the place stays at Roblox's 50; the server turns the 50th arrival away.
-- Both read Roles/Ladder, the only place the ladder is stated (§3.7; round-1 hand-off).
PossessionState.MAX_PLAYERS = Ladder.server.maxPlayers
PossessionState.FULL_MESSAGE = Ladder.FULL_MESSAGE

-- Snapshot taken from the brain at possession (§1.5 step 2). Positions in studs, yaw in radians
-- about +Y (Roblox convention: yaw 0 faces -Z).
export type Snapshot = {
	x: number,
	y: number,
	z: number,
	yaw: number,
	vx: number,
	vy: number,
	vz: number,
	mode: string, -- brain mode at suspend ("walk", "run", "idle", "rail", ...)
	clip: string?,
	clipT: number?, -- seconds into the clip when suspended
	brain: { [string]: any }?, -- brain-specific resume data (routeId, s, dir, goal)
}

export type GrantPayload = {
	actorId: string,
	species: string,
	snapshot: Snapshot,
	serverTime: number, -- workspace:GetServerTimeNow() (or the injected clock) at the grant
	holdSeconds: number,
}

export type Ledger = {
	byActor: { [string]: number },
	byDriver: { [number]: string },
}

function PossessionState.newLedger(): Ledger
	return { byActor = {}, byDriver = {} }
end

-- Binds a driver to an actor. Errors if either side is already bound: callers release first.
function PossessionState.bind(ledger: Ledger, driver: number, actorId: string)
	if ledger.byDriver[driver] ~= nil then
		error(`PossessionState.bind: driver {driver} already drives {ledger.byDriver[driver]}`)
	end
	if ledger.byActor[actorId] ~= nil then
		error(`PossessionState.bind: actor {actorId} already driven by {ledger.byActor[actorId]}`)
	end
	ledger.byDriver[driver] = actorId
	ledger.byActor[actorId] = driver
end

-- Removes the driver's binding; returns the actor id it drove (nil if none).
function PossessionState.unbind(ledger: Ledger, driver: number): string?
	local actorId = ledger.byDriver[driver]
	if actorId == nil then
		return nil
	end
	ledger.byDriver[driver] = nil
	ledger.byActor[actorId] = nil
	return actorId
end

function PossessionState.actorOf(ledger: Ledger, driver: number): string?
	return ledger.byDriver[driver]
end

function PossessionState.driverOf(ledger: Ledger, actorId: string): number?
	return ledger.byActor[actorId]
end

function PossessionState.count(ledger: Ledger): number
	local n = 0
	for _ in ledger.byDriver do
		n += 1
	end
	return n
end

-- The two maps must be exact inverses.
function PossessionState.check(ledger: Ledger): (boolean, { string })
	local errors = {}
	for driver, actorId in ledger.byDriver do
		if ledger.byActor[actorId] ~= driver then
			table.insert(errors, `driver {driver} -> {actorId} but actor -> {ledger.byActor[actorId]}`)
		end
	end
	for actorId, driver in ledger.byActor do
		if ledger.byDriver[driver] ~= actorId then
			table.insert(errors, `actor {actorId} -> {driver} but driver -> {ledger.byDriver[driver]}`)
		end
	end
	return #errors == 0, errors
end

-- B4: an arrival is admitted when fewer than `max` players are already admitted. The arrival
-- itself is not counted, and a turned-away arrival never counts toward population.
function PossessionState.admits(admittedCount: number, max: number?): boolean
	return admittedCount < (max or PossessionState.MAX_PLAYERS)
end

return PossessionState
