--!strict
-- ReplicatedStorage.Shared.Gigs.GigRules
-- The gig contract (BUILD_PLAN §1.4; brief v2 §13a "one rule for all gigs: an extra-good job earns a
-- tip; a bad job gives a very minor reputation ding"): each gig scores a 0-1 quality from a trace;
-- quality >= 0.9 tips, < 0.4 dings (reputation event gig_bad), base pay in cents from the gig def.
-- W1 ships the contract with ONE implemented gig (lawn mowing: quality = mown coverage, time-penalised);
-- the other five are declared and score "todo" until W4's GigService.
-- Interface: GIGS; def(gig); quality(gig, trace) -> number?; payout(gig, quality) -> Payout

export type GigDef = { id: string, baseCents: number, tipCents: number, targetSecs: number?, implemented: boolean }
export type Payout = { cents: number, tip: number, reputationEvent: string? }

local GigRules = {}

GigRules.TIP_AT = 0.9
GigRules.DING_BELOW = 0.4

-- stylua: ignore
GigRules.GIGS = {
	mow = { id = "mow", baseCents = 3, tipCents = 2, targetSecs = 60, implemented = true },
	delivery = { id = "delivery", baseCents = 3, tipCents = 2, implemented = false },
	sign_spin = { id = "sign_spin", baseCents = 2, tipCents = 1, implemented = false },
	car_wash = { id = "car_wash", baseCents = 3, tipCents = 2, implemented = false },
	paper_route = { id = "paper_route", baseCents = 4, tipCents = 2, implemented = false },
	steakhouse_tables = { id = "steakhouse_tables", baseCents = 4, tipCents = 3, implemented = false },
} :: { [string]: GigDef }

function GigRules.def(gig: string): GigDef?
	return GigRules.GIGS[gig]
end

-- mow trace: { cells = total lawn cells, mown = cells cut, secs = time taken }
function GigRules.quality(gig: string, trace: { [string]: number }): number?
	if gig == "mow" then
		local d = GigRules.GIGS.mow
		local cells = math.max(1, trace.cells or 1)
		local coverage = math.clamp((trace.mown or 0) / cells, 0, 1)
		local over = math.max(0, (trace.secs or 0) - (d.targetSecs :: number))
		local timeFactor = math.clamp(1 - over / (d.targetSecs :: number), 0.5, 1)
		return coverage * timeFactor
	end
	return nil -- not implemented in W1
end

function GigRules.payout(gig: string, quality: number): Payout
	local d = GigRules.GIGS[gig]
	assert(d, `GigRules.payout: unknown gig {gig}`)
	local q = math.clamp(quality, 0, 1)
	if q >= GigRules.TIP_AT then
		return { cents = d.baseCents, tip = d.tipCents, reputationEvent = "gig_tip" }
	elseif q < GigRules.DING_BELOW then
		return { cents = d.baseCents, tip = 0, reputationEvent = "gig_bad" }
	end
	return { cents = d.baseCents, tip = 0, reputationEvent = nil }
end

return GigRules
