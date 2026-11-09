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
-- Pure: no state, no side effects on require.

local Height = require("./Height")

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

return Ground
