--!strict
-- ReplicatedStorage.Shared.Combat.VigilanteRules
-- Keeps exactly round(share x human actors) vigilante flags, on AI bodies only (brief v2 §8: "8% of all human actors
-- on the map at any moment have a vigilante streak"; BUILD_PLAN §1.4). A flag on a body a player takes moves to another
-- AI body at the next rebalance (CombatService runs it once a second, so within 1 s). Which bodies: the flags already
-- held stay where they are; new ones go to the AI bodies first in a fixed order of their ids (Combat/CombatRules.hash),
-- so the same people are the town's vigilantes every server unless players take them. A flagged person is tough
-- (CombatRules.temperament).
-- Interface: target(humans, share) -> n; rebalance(humans, flags, share) -> flags (a new set; `flags` is not changed)
-- humans: { { id, ai: boolean } } (every human actor; ai: the AI drives the body now)
-- Pure. No side effects on require.

local CombatRules = require("./CombatRules")

export type Human = { id: any, ai: boolean }

local VigilanteRules = {}

function VigilanteRules.target(humans: { Human }, share: number): number
	return math.floor(#humans * share + 0.5)
end

local function rank(id: any): number
	return CombatRules.hash(`vigilante:{tostring(id)}`)
end

function VigilanteRules.rebalance(humans: { Human }, flags: { [any]: boolean }, share: number): { [any]: boolean }
	local want = VigilanteRules.target(humans, share)
	local kept: { any } = {}
	local free: { any } = {}
	for _, h in humans do
		if h.ai then
			if flags[h.id] then
				table.insert(kept, h.id)
			else
				table.insert(free, h.id)
			end
		end
	end
	local function byRank(a: any, b: any): boolean
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		return tostring(a) < tostring(b)
	end
	table.sort(kept, byRank)
	table.sort(free, byRank)
	local out: { [any]: boolean } = {}
	local n = 0
	for _, id in kept do
		if n >= want then
			break
		end
		out[id] = true
		n += 1
	end
	for _, id in free do
		if n >= want then
			break
		end
		out[id] = true
		n += 1
	end
	return out
end

return VigilanteRules
