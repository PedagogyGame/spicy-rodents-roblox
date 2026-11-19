--!strict
-- ServerScriptService.Server.Items.Lending
-- A bought thing stays its buyer's (owner, D16 #26: "purchased items (unless otherwise specified) remain only in the
-- original buyer's inventory"). Whoever else catches or picks one up only borrows it: it is in their hand to throw
-- back (a game of catch goes on as before), it never enters their inventory (Items/Inventory), and it goes home to
-- the buyer's things when it is not thrown on in C.holdSecs, when the borrower walks off with it (C.walkOff), changes
-- body or leaves, or when the buyer leaves the server (into their record by UserId: theirs again if they come back).
-- A thrown thing nobody picks up goes home after C.groundSecs (at once if the buyer has left). Things the game
-- gives (ItemRules.findersKeep) go to whoever picks them up, as before; none of the corner store's do.
-- This is the pure half: the decisions and the ledger of loans. Items/ItemWorld does the parts and the Tools.
-- Interface: C; WORDS; pickUp(findersKeep, ownerKey, whoKey) -> "own" | "lend" | "keep"; reach(startDist) -> studs;
--   due(loan, now, facts) -> why? ("ownerGone" | "holderGone" | "idle" | "walked"); ledger() -> Ledger { lend(holder,
--   thing, now, startDist?) -> Loan, get(token) -> Loan?, holds(holder, item, token) -> boolean, take(token) ->
--   Loan?, of(holder) -> { Loan }, all() -> { Loan } }; say(words, ...) (string.format)
-- No side effects on require.

local Lending = {}

Lending.C = table.freeze({
	holdSecs = 20, -- a borrowed thing not thrown on within this goes home
	walkOff = 60, -- studs from the buyer: a borrower further off than this (or than C.walkSlack past where they
	walkSlack = 20, --   picked it up, if that was further) has walked off with it, and it goes home
	groundSecs = 60, -- a thrown thing left lying this long goes home (it was 120 s before the rule)
})

-- What players read (string.format: names are display names, things are "frisbee", "whoopee cushion").
Lending.WORDS = table.freeze({
	caught = "Caught %s's %s! Throw it back: it goes home by itself in %d seconds.",
	picked = "%s's %s: throw it back. It goes home by itself in %d seconds.",
	borrowed = "%s has your %s.",
	home = "Your %s is back in your hands.",
	wentHome = "%s's %s went back to them.",
	ownerLeft = "%s left, so their %s went home with them.",
	returned = "That %s is %s's: it went back to them.",
	placedHome = "%s picked up your %s: it is back in your things.",
	notYours = "That is %s's: you can only throw it back.",
})

export type Thing = {
	item: string, -- ItemRules id
	owner: any, -- the buyer (a Player)
	ownerKey: any, -- the buyer's UserId (Items/Inventory's key)
	ownerName: string,
}
export type Loan = {
	token: number,
	thing: Thing,
	holder: any, -- the borrower (a Player)
	since: number, -- when it came into their hand
	reach: number, -- studs from the buyer past which it has been walked off with
	tool: any?, -- the borrowed Tool in their hand (Items/ItemWorld's)
}
export type Facts = {
	ownerHere: boolean, -- the buyer is still in the game
	holderHere: boolean, -- the borrower is still in the game, a person, with the Tool
	dist: number?, -- borrower to buyer, studs (nil: either has no body)
}
export type Ledger = {
	lend: (holder: any, thing: Thing, now: number, startDist: number?) -> Loan,
	get: (token: number) -> Loan?,
	holds: (holder: any, item: string, token: any) -> boolean,
	take: (token: number) -> Loan?,
	of: (holder: any) -> { Loan },
	all: () -> { Loan },
}

-- who gets a thing picked up or caught: its buyer has it back ("own"), a thing the game gave is kept by whoever
-- picks it up ("keep"), anyone else only borrows it ("lend")
function Lending.pickUp(findersKeep: boolean, ownerKey: any, whoKey: any): string
	if ownerKey ~= nil and whoKey == ownerKey then
		return "own"
	end
	return if findersKeep then "keep" else "lend"
end

-- how far from the buyer a borrower who picked it up `startDist` studs off may go
function Lending.reach(startDist: number?): number
	return math.max(Lending.C.walkOff, (startDist or 0) + Lending.C.walkSlack)
end

-- why a loan ends now, nil while it goes on
function Lending.due(loan: Loan, now: number, facts: Facts): string?
	if not facts.ownerHere then
		return "ownerGone"
	end
	if not facts.holderHere then
		return "holderGone"
	end
	if now - loan.since >= Lending.C.holdSecs then
		return "idle"
	end
	if facts.dist ~= nil and facts.dist > loan.reach then
		return "walked"
	end
	return nil
end

function Lending.say(words: string, ...: any): string
	return string.format(words, ...)
end

function Lending.ledger(): Ledger
	local loans: { [number]: Loan } = {}
	local nextToken = 0
	return {
		lend = function(holder: any, thing: Thing, now: number, startDist: number?): Loan
			nextToken += 1
			local loan: Loan = {
				token = nextToken,
				thing = thing,
				holder = holder,
				since = now,
				reach = Lending.reach(startDist),
				tool = nil,
			}
			loans[nextToken] = loan
			return loan
		end,
		get = function(token: number): Loan?
			return loans[token]
		end,
		holds = function(holder: any, item: string, token: any): boolean
			local loan = if type(token) == "number" then loans[token] else nil
			return loan ~= nil and loan.holder == holder and loan.thing.item == item
		end,
		take = function(token: number): Loan?
			local loan = loans[token]
			loans[token] = nil
			return loan
		end,
		of = function(holder: any): { Loan }
			local out = {}
			for _, loan in loans do
				if loan.holder == holder then
					table.insert(out, loan)
				end
			end
			table.sort(out, function(a: Loan, b: Loan): boolean
				return a.token < b.token
			end)
			return out
		end,
		all = function(): { Loan }
			local out = {}
			for _, loan in loans do
				table.insert(out, loan)
			end
			table.sort(out, function(a: Loan, b: Loan): boolean
				return a.token < b.token
			end)
			return out
		end,
	}
end

return Lending
