--!strict
-- ReplicatedStorage.Shared.Foraging.ForageRules
-- The nut spots' rules (brief v2 §7; owner D16 #22; Shared/Foraging/NutSpots has the spots): what a spot holds, how
-- its nuts grow back on the game clock, and when a squirrel standing at one picks a nut up. Pure; the server
-- (Server/Foraging/ForageService) holds one SpotState per spot and decides where each squirrel is.
--   A spot holds up to its kind's stock. Taking a nut from a full spot starts its clock: one nut grows back every
--   regrowDays game days until it is full again (a spot nobody visits stays full; nothing is lost while it is).
--   A squirrel picks a nut up by being there: its feet within C.reach studs level of the spot's middle and within
--   C.rise of its ground (one on a fence or a branch over it is not there), never with a key (as a hollow's hole is
--   run into, and so a phone needs no button). One nut at a time, C.gap seconds apart per squirrel, never more than
--   it can carry (Tunables forage.carryMax; Shared/Foraging/HollowClaim.carry).
--   Who forages: squirrels. The Spicy Rodent does not: nuts do nothing for it (it claims no hollow; it heals by
--   resting in a hollow or a drain while fed, and it is fed by biting, so a pile of nuts never stands in for the
--   chase).
--   The computer's squirrels forage lightly (C.ai*): every C.aiEvery seconds each one near a spot with nuts may go
--   to the nearest point of its route (its brain's "bait") and, within C.aiReach (its point is its route's line: a
--   trunk route's foot is the trunk's axis), eats a nut there, C.aiNibble seconds sitting. It never carries one, so
--   it never fills a hollow: players compete with them for nuts, never for trees.
-- Interface: C; newSpot(stock, day) -> SpotState; regrow(s, stock, regrowDays, day) -> boolean (changed);
--   take(s, stock, day) -> boolean; inReach(sx, sy, sz, x, y, z, reach, rise) -> boolean; ready(last?, now, gap) ->
--   boolean; forages(species, variant?) -> boolean. `day` is fractional game days. No side effects on require.

local ForageRules = {}

ForageRules.C = table.freeze({
	reach = 2.4, -- studs level from a spot's middle to a player's squirrel's feet (the pile is about 1.2 across)
	rise = 1.8, -- studs between those feet and the spot's ground
	gap = 0.5, -- seconds between one squirrel's pick-ups
	look = 0.1, -- seconds between the server's looks at the players' squirrels
	aiEvery = 4, -- seconds between the computer squirrels' looks
	aiReach = 6, -- studs level: a computer squirrel's route point this near eats
	aiRise = 4,
	aiNotice = 14, -- studs level: one this near a spot with nuts may go to it
	aiChance = 0.35, -- each look, for each one that near
	aiNibble = 3, -- seconds it sits nibbling
})

export type SpotState = {
	left: number, -- nuts there now
	since: number, -- the game day the nut growing back now started (when not full)
}

function ForageRules.newSpot(stock: number, day: number): SpotState
	return { left = stock, since = day }
end

-- regrow: the nuts grown back by `day`; true when the count changed
function ForageRules.regrow(s: SpotState, stock: number, regrowDays: number, day: number): boolean
	if s.left >= stock then
		s.left = stock
		s.since = day
		return false
	end
	if not (regrowDays > 0) or day <= s.since then
		return false
	end
	local n = math.floor((day - s.since) / regrowDays)
	if n <= 0 then
		return false
	end
	local add = math.min(n, stock - s.left)
	s.left += add
	s.since = if s.left >= stock then day else s.since + add * regrowDays
	return true
end

-- take: one nut picked up on `day` (false: none there)
function ForageRules.take(s: SpotState, stock: number, day: number): boolean
	if s.left < 1 then
		return false
	end
	if s.left >= stock then
		s.since = day -- (the first nut gone starts the clock)
	end
	s.left -= 1
	return true
end

function ForageRules.inReach(
	sx: number,
	sy: number,
	sz: number,
	x: number,
	y: number,
	z: number,
	reach: number,
	rise: number
): boolean
	local dx, dz = x - sx, z - sz
	return dx * dx + dz * dz <= reach * reach and math.abs(y - sy) <= rise
end

function ForageRules.ready(last: number?, now: number, gap: number): boolean
	return last == nil or now - last >= gap
end

function ForageRules.forages(species: string?, variant: string?): boolean
	return species == "squirrel" and variant ~= "spicy"
end

return ForageRules
