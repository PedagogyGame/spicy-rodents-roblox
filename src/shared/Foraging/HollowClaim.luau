--!strict
-- ReplicatedStorage.Shared.Foraging.HollowClaim
-- A hollow tree's nut meter and its claim (brief v2 §3: "Claiming is proximity, not a ritual: no scent-marking
-- animation. A squirrel owns a tree while its meter is at 70% or above and it has visited the tree at least once
-- every three in-game days while at 70%; miss that and the claim lapses"; §7: "Nuts stored in a claimed hollow raise
-- its meter. Above 70 %, the squirrel owns the tree and other squirrels cannot take its nuts"; a squirrel carries at
-- most 9). Pure rules over a plain record; the server (Foraging/HollowService) holds one per hollow and decides who
-- is inside. A claimant is a Who: any key the server gives (Foraging/HollowService: the player, or the computer's
-- body), so a player's claim stays theirs, not the body's.
--   meter = stored / capacity (capacity per hollow: data/hollows.json, premium trees twice the default)
--   bringing nuts in (deposit) stores them, up to capacity, and counts as a visit by that squirrel; nobody brings
--   nuts into another squirrel's claimed tree (they stay carried)
--   the claim: a tree nobody holds is taken by the squirrel whose nuts lift the meter to `ownAt` or above, once it has
--   brought in at least `margin` of the capacity itself since the tree was last claimed (one nut into a lapsed
--   tree's store takes nothing); the owner keeps it while the meter stays at `ownAt` less `margin` or above (a
--   claim just made does not lapse with the first day's decay) and it visits at least once every `visitDays` game
--   days; otherwise it lapses
--   the meter decays `decayPerDay` of capacity each game day (nuts eaten and spoiled), so an abandoned tree empties
--   taking nuts out (withdraw): the owner always may; another squirrel only while the tree is unclaimed
--   one tree each (owner, D16 #21 "a squirrel may claim only one tree"): a squirrel that holds a tree brings no nuts
--   into any other (they stay carried), so it never claims a second; its claim moves only once the first has
--   lapsed. The caller says which tree it holds (heldBy over every claim) as `elsewhere`
-- Interface: new() -> Claim; meter(c, capacity); deposit(c, who, n, day, capacity, ownAt, margin, elsewhere?) ->
--   stored (taken from the n carried); visit(c, who, day); withdraw(c, who, n) -> taken; update(c, day, capacity,
--   ownAt, visitDays, decayPerDay, margin) -> changed (decay and lapse up to `day`); owned(c) -> owner?;
--   heldBy(claims, who) -> key? (the tree `who` holds, keyed as in `claims`); carry(carried, n, max) -> (carried,
--   taken). `day` is fractional game days. No side effects on require.

local HollowClaim = {}

export type Who = string | number
export type Claim = {
	stored: number,
	owner: Who?,
	brought: { [Who]: number }, -- nuts each squirrel brought in since the tree was last claimed or lapsed
	lastVisit: number?, -- the owner's last visit (game days)
	since: number?, -- when the owner claimed it
	asOf: number?, -- the day the decay has been applied up to
}

function HollowClaim.new(): Claim
	return { stored = 0, owner = nil, brought = {}, lastVisit = nil, since = nil, asOf = nil }
end

function HollowClaim.meter(c: Claim, capacity: number): number
	if capacity <= 0 then
		return 0
	end
	return math.clamp(c.stored / capacity, 0, 1)
end

function HollowClaim.owned(c: Claim): Who?
	return c.owner
end

-- carry(carried, n, max): picking up n nuts with `carried` already held, never more than max (Tunables
-- forage.carryMax): the new count and how many were taken
function HollowClaim.carry(carried: number, n: number, max: number): (number, number)
	local taken = math.max(0, math.min(n, max - carried))
	return carried + taken, taken
end

-- visit: squirrel `who` is inside on `day` (the owner's visits keep the claim)
function HollowClaim.visit(c: Claim, who: Who, day: number)
	if c.owner == who then
		c.lastVisit = day
	end
end

-- heldBy: the key (in `claims`) of the tree `who` owns, nil when it owns none
function HollowClaim.heldBy<K>(claims: { [K]: Claim }, who: Who): K?
	for k, c in claims do
		if c.owner == who then
			return k
		end
	end
	return nil
end

-- deposit: `who` brings n nuts in on `day`; returns how many were stored (the rest stays carried: the tree is full,
-- or it is another squirrel's, or `elsewhere`: `who` already holds another tree, and a squirrel keeps one)
function HollowClaim.deposit(
	c: Claim,
	who: Who,
	n: number,
	day: number,
	capacity: number,
	ownAt: number,
	margin: number,
	elsewhere: boolean?
): number
	if c.owner ~= nil and c.owner ~= who then
		return 0
	end
	if elsewhere and c.owner ~= who then
		return 0
	end
	local room = math.max(0, capacity - c.stored)
	local stored = math.max(0, math.min(n, room))
	c.stored += stored
	if c.owner == nil and stored > 0 then
		local own = (c.brought[who] or 0) + stored
		c.brought[who] = own
		if HollowClaim.meter(c, capacity) >= ownAt and own >= margin * capacity then
			c.owner, c.since = who, day
			table.clear(c.brought)
		end
	end
	HollowClaim.visit(c, who, day)
	return stored
end

-- withdraw: `who` takes up to n nuts out (another squirrel's claimed tree gives nothing)
function HollowClaim.withdraw(c: Claim, who: Who, n: number): number
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
	decayPerDay: number,
	margin: number
): boolean
	local from = c.asOf or day
	if day > from then
		c.stored = math.max(0, c.stored - decayPerDay * capacity * (day - from))
	end
	c.asOf = math.max(from, day)
	if c.owner == nil then
		return false
	end
	local lapsed = HollowClaim.meter(c, capacity) < ownAt - margin or day - (c.lastVisit or c.since or day) > visitDays
	if lapsed then
		c.owner, c.lastVisit, c.since = nil, nil, nil
		table.clear(c.brought)
		return true
	end
	return false
end

return HollowClaim
