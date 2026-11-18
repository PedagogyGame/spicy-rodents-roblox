--!strict
-- ReplicatedStorage.Shared.Foraging.HollowClaim
-- A hollow tree's nut meter and its claim (brief v2 §3: "Claiming is proximity, not a ritual: no scent-marking
-- animation. A squirrel owns a tree while its meter is at 70% or above and it has visited the tree at least once
-- every three in-game days while at 70%; miss that and the claim lapses"; §7: "Nuts stored in a claimed hollow raise
-- its meter. Above 70 %, the squirrel owns the tree and other squirrels cannot take its nuts"; a squirrel carries at
-- most 9). Pure rules over a plain record; the server (Foraging/HollowService) holds one per hollow and decides who
-- is inside. Squirrels are named by any number (the town actor id: a player's squirrel and the computer's alike).
--   meter = stored / capacity (capacity per hollow: data/hollows.json, premium trees twice the default)
--   bringing nuts in (deposit) stores them, up to capacity, and counts as a visit by that squirrel
--   the claim: whoever brings in the nuts that lift the meter to `ownAt` or above owns it, if nobody holds it;
--   the owner keeps it while the meter stays at `ownAt` or above and it visits at least once every `visitDays`
--   game days; otherwise it lapses (nobody owns it until the meter is lifted again)
--   the meter decays `decayPerDay` of capacity each game day (nuts eaten and spoiled), so an abandoned tree empties
--   taking nuts out (withdraw): the owner always may; another squirrel only while the tree is unclaimed
-- Interface: new() -> Claim; meter(c, capacity); deposit(c, who, n, day, capacity, ownAt) -> stored (taken from the
--   n carried); visit(c, who, day); withdraw(c, who, n) -> taken; update(c, day, capacity, ownAt, visitDays,
--   decayPerDay) -> changed (decay and lapse up to `day`); owned(c) -> owner?; carry(carried, n, max) -> (carried,
--   taken). `day` is fractional game days. No side effects on require.

local HollowClaim = {}

export type Claim = {
	stored: number,
	owner: number?,
	lastVisit: number?, -- the owner's last visit (game days)
	since: number?, -- when the owner claimed it
	asOf: number?, -- the day the decay has been applied up to
}

function HollowClaim.new(): Claim
	return { stored = 0, owner = nil, lastVisit = nil, since = nil, asOf = nil }
end

function HollowClaim.meter(c: Claim, capacity: number): number
	if capacity <= 0 then
		return 0
	end
	return math.clamp(c.stored / capacity, 0, 1)
end

function HollowClaim.owned(c: Claim): number?
	return c.owner
end

-- carry(carried, n, max): picking up n nuts with `carried` already held, never more than max (Tunables
-- forage.carryMax): the new count and how many were taken
function HollowClaim.carry(carried: number, n: number, max: number): (number, number)
	local taken = math.max(0, math.min(n, max - carried))
	return carried + taken, taken
end

-- visit: squirrel `who` is inside on `day` (the owner's visits keep the claim)
function HollowClaim.visit(c: Claim, who: number, day: number)
	if c.owner == who then
		c.lastVisit = day
	end
end

-- deposit: `who` brings n nuts in on `day`; returns how many were stored (the rest stays carried: the tree is full)
function HollowClaim.deposit(c: Claim, who: number, n: number, day: number, capacity: number, ownAt: number): number
	local room = math.max(0, capacity - c.stored)
	local stored = math.max(0, math.min(n, room))
	c.stored += stored
	if c.owner == nil and stored > 0 and HollowClaim.meter(c, capacity) >= ownAt then
		c.owner, c.since = who, day
	end
	HollowClaim.visit(c, who, day)
	return stored
end

-- withdraw: `who` takes up to n nuts out (another squirrel's claimed tree gives nothing)
function HollowClaim.withdraw(c: Claim, who: number, n: number): number
	if c.owner ~= nil and c.owner ~= who then
		return 0
	end
	local taken = math.max(0, math.min(n, c.stored))
	c.stored -= taken
	return taken
end

-- update: the decay since the last update and the claim's lapse, as of `day`; true when the owner changed
function HollowClaim.update(
	c: Claim,
	day: number,
	capacity: number,
	ownAt: number,
	visitDays: number,
	decayPerDay: number
): boolean
	local from = c.asOf or day
	if day > from then
		c.stored = math.max(0, c.stored - decayPerDay * capacity * (day - from))
	end
	c.asOf = math.max(from, day)
	if c.owner == nil then
		return false
	end
	local lapsed = HollowClaim.meter(c, capacity) < ownAt or day - (c.lastVisit or c.since or day) > visitDays
	if lapsed then
		c.owner, c.lastVisit, c.since = nil, nil, nil
		return true
	end
	return false
end

return HollowClaim
