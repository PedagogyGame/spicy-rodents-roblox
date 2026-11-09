--!strict
-- ReplicatedStorage.Shared.World.Ground
-- Ground as a pure function of position and a reference height (fixes the global-state
-- `getGroundAt` [routes_movement verifier 5]). Interface (BUILD_PLAN §1.4):
--   groundAt(x, z, refY), roofAt(x, z, refY), surfaceKind(x, z)   (studs)
-- W0 (spike S6) subset: terrain (World/Height, verbatim v5.4) plus the analytic bridge deck
-- (riverDeckAt). v5.4 getGroundAt (6227) also raises to pavement, mall floors, river platforms, car
-- and building roofs; in Roblox those become real collidable geometry baked from data
-- [worldgen_districts_art §16 "the analytic riverRoofAt and riverDeckAt disappear"], so roofAt
-- stays nil here until W1's Colliders land.
-- W1 (§4.4 #2) adds `Ground.world(opts)`: the full v5.4 getGroundAt order (6227-6247) over data:
-- max(terrain or deck, pavement and curbs from World/Town), roofs from World/Colliders (the body is
-- within 0.47 u below the roof), and the trampoline bed (Movement/Trampoline sites). The static
-- functions below stay the terrain-and-deck subset (golden-tested against tests/golden/terrain.json).
-- Pure: no state, no side effects on require.

local Height = require("./Height")
local Colliders = require("./Colliders")
local Trampoline = require("../Movement/Trampoline")

local Ground = {}

-- A body at refY counts as "on" the deck when it is no more than this far below the deck top
-- (studs). Mirrors v5.4's roof rule (player above roof - 0.47 u) scaled to studs.
Ground.DECK_SNAP_BELOW = 0.47 * Height.STUDS_PER_UNIT

export type SurfaceKind = "water" | "deck" | "terrain"

-- Seat height of a structure: v5.4 seats every lot at terrainHeight(centre) [worldgen_core §3].
function Ground.seatAt(x: number, z: number): number
	return Height.at(x, z)
end

function Ground.groundAt(x: number, z: number, refY: number): number
	local terrain = Height.at(x, z)
	local deck = Height.riverDeckAt(x, z)
	if deck and refY >= deck - Ground.DECK_SNAP_BELOW and deck > terrain then
		return deck
	end
	return terrain
end

function Ground.roofAt(_x: number, _z: number, _refY: number): number?
	return nil
end

function Ground.surfaceKind(x: number, z: number): SurfaceKind
	if Height.riverDeckAt(x, z) ~= nil then
		return "deck"
	end
	if Height.insideRiverWater(x, z) then
		return "water"
	end
	return "terrain"
end

export type GroundWorld = {
	groundAt: (x: number, z: number, refY: number) -> number,
	roofAt: (x: number, z: number, refY: number) -> number?,
	surfaceKind: (x: number, z: number, refY: number?) -> string,
}

export type WorldOpts = {
	town: any?, -- World/Town (pavementAt)
	colliders: any?, -- World/Colliders (roofAt)
	trampolines: { any }?, -- Movement/Trampoline sites (bedAt)
}

-- world(opts): closures over the data-driven layers; every layer is optional.
function Ground.world(opts: WorldOpts): GroundWorld
	local town = opts.town
	local colliders = opts.colliders
	local tramps = opts.trampolines
	local function roofAt(x: number, z: number, refY: number): number?
		if colliders then
			return Colliders.roofAt(colliders, x, z, refY)
		end
		return nil
	end
	local function groundAt(x: number, z: number, refY: number): number
		local y = Ground.groundAt(x, z, refY)
		if town then
			local p = town:pavementAt(x, z)
			if p and p > y then
				y = p
			end
		end
		local roof = roofAt(x, z, refY)
		if roof and roof > y then
			y = roof
		end
		if tramps then
			local bed = Trampoline.bedAt(tramps, x, z, refY)
			if bed and bed > y then
				y = bed
			end
		end
		return y
	end
	local function surfaceKind(x: number, z: number, refY: number?): string
		if refY and roofAt(x, z, refY) then
			return "roof"
		end
		local k = Ground.surfaceKind(x, z)
		if k == "terrain" and town and town:pavementAt(x, z) then
			return "pavement"
		end
		return k
	end
	return { groundAt = groundAt, roofAt = roofAt, surfaceKind = surfaceKind }
end

return Ground
