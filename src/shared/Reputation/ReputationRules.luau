--!strict
-- ReplicatedStorage.Shared.Reputation.ReputationRules
-- Two-sided reputation (BUILD_PLAN §1.4, §3.15; brief v2 §13a): event deltas (gig tip/ding, rescue, true
-- sighting report, lost pet, cafe sitting per game hour, mischief seen, a landed kick), player votes
-- (5 up and 5 down per in-game day per voter, one vote per target per day, players only by default
-- (Q21), each weighted by the voter's own reputation clamp(0.25 + rep/100, 0.25, 1.5) to blunt
-- brigading), the range [-100, 100], and the entourage size (companions, capped). Pure.
-- Interface: RULES; clamp(rep); weight(voterRep); tick(rep, event, n?) -> rep; newVoteWindow() -> Window;
--            applyVote(window, day, voterId, voterRep, targetId, targetRep, dir) -> (ok, newTargetRep | reason);
--            entourage(companions) -> number

local ReputationRules = {}

-- stylua: ignore
ReputationRules.RULES = table.freeze({
	range = { -100, 100 }, start = 0,
	events = table.freeze({ gig_tip = 2, gig_bad = -1, rescue = 6, true_report = 3, false_report = -1, lost_pet_returned = 5,
		cafe_seat_per_game_hour = 1, mischief_seen_by_npc = -1, kick_landed = 4 }),
	votes = table.freeze({ up = 5, down = 5, base = 2, weightMin = 0.25, weightMax = 1.5 }),
	maxCompanions = 4,
})

local R = ReputationRules.RULES

function ReputationRules.clamp(rep: number): number
	return math.clamp(rep, R.range[1], R.range[2])
end

function ReputationRules.weight(voterRep: number): number
	return math.clamp(R.votes.weightMin + voterRep / 100, R.votes.weightMin, R.votes.weightMax)
end

function ReputationRules.tick(rep: number, event: string, n: number?): number
	local d = R.events[event]
	assert(d ~= nil, `ReputationRules.tick: unknown event {event}`)
	return ReputationRules.clamp(rep + d * (n or 1))
end

export type Window = { day: number, used: { [any]: { up: number, down: number, targets: { [any]: boolean } } } }

function ReputationRules.newVoteWindow(): Window
	return { day = -1, used = {} }
end

-- dir: 1 (thumbs up) or -1 (down). The window resets when the in-game day changes.
function ReputationRules.applyVote(
	w: Window,
	day: number,
	voterId: any,
	voterRep: number,
	targetId: any,
	targetRep: number,
	dir: number
): (boolean, number | string)
	if day ~= w.day then
		w.day = day
		w.used = {}
	end
	if voterId == targetId then
		return false, "self"
	end
	if dir ~= 1 and dir ~= -1 then
		return false, "dir"
	end
	local u = w.used[voterId]
	if not u then
		u = { up = 0, down = 0, targets = {} }
		w.used[voterId] = u
	end
	if u.targets[targetId] then
		return false, "same target today"
	end
	if dir == 1 and u.up >= R.votes.up then
		return false, "no up votes left"
	elseif dir == -1 and u.down >= R.votes.down then
		return false, "no down votes left"
	end
	if dir == 1 then
		u.up += 1
	else
		u.down += 1
	end
	u.targets[targetId] = true
	return true, ReputationRules.clamp(targetRep + dir * R.votes.base * ReputationRules.weight(voterRep))
end

function ReputationRules.entourage(companions: number): number
	return math.clamp(math.floor(companions), 0, R.maxCompanions)
end

return ReputationRules
