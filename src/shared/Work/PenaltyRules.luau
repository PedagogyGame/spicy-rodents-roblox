--!strict
-- ReplicatedStorage.Shared.Work.PenaltyRules
-- The money side of the two D30 penalties, pure (the owner: "if an ambulence driver ignores bite victim that needs to
-- be picked up, or if the errand delivery person steals the item, or places it in their home and does not bring it
-- back ... they should get penalized by losing 100 spicy bucks, and the doctor, gets demoted to lowest townsperson
-- station's money level").
--   * The fine is Tunables work.penaltyCents (S$100.00). The wallet never goes below nothing (Shared/Economy/Bank:
--     no debt anywhere in the game), so a fine takes what there is, up to the fine: fine(balance).
--   * "The lowest townsperson station's money level": the townsperson is the ladder's lowest station (Roles/Ladder
--     rung "human", tier 1), and its money level is what the human queue's money term reads (Economy/EconomyRules
--     .queueMoney, from the wallet): the least money any townsperson in this server holds right now. With no other
--     townsperson in the server, the level is what a newcomer to the lowest rank starts with, the pocket money
--     (Tunables economy.pocketMoneyCents). townLevel(balances, pocket).
--   * A doctor who ignores a bite victim pays the fine and then has no more than that level: ambulance(balance,
--     level) -> (fine taken, the rest taken to bring it down to the level, the balance after). A penalty never
--     gives money: a doctor already at or under the level keeps what is left after the fine.
-- Interface: penalty() -> cents; fine(balance, penalty?) -> cents taken; townLevel(balances, pocket) -> cents;
--   ambulance(balance, level, penalty?) -> (fine, down, after); WHY (the reasons the wallet logs and shows)
-- Pure; whole cents. No side effects on require.

local Tunables = require("../Config/Tunables")

local PenaltyRules = {}

PenaltyRules.WHY = table.freeze({
	errand = "an errand's parcel kept",
	ambulance = "a bite victim left waiting",
	level = "demoted to the lowest townsperson's money",
})

local function cents(v: any): number
	return if type(v) == "number" and v == v and v > 0 then math.floor(v) else 0
end

function PenaltyRules.penalty(): number
	return cents(Tunables.get("work.penaltyCents"))
end

-- What the fine takes from a balance: the penalty, or all there is when there is less.
function PenaltyRules.fine(balance: number, penalty: number?): number
	return math.min(cents(balance), cents(penalty or PenaltyRules.penalty()))
end

-- The lowest townsperson's money: the least of the townspeople's balances; the pocket money when there are none.
function PenaltyRules.townLevel(balances: { number }, pocket: number): number
	local level = math.huge
	for _, b in balances do
		level = math.min(level, cents(b))
	end
	return if level == math.huge then cents(pocket) else level
end

-- An ambulance driver who ignored a bite victim: the fine, then down to the level. Returns the fine taken, what
-- was taken after it to reach the level, and the balance left.
function PenaltyRules.ambulance(balance: number, level: number, penalty: number?): (number, number, number)
	local b = cents(balance)
	local fine = PenaltyRules.fine(b, penalty)
	local after = b - fine
	local down = math.max(0, after - cents(level))
	return fine, down, after - down
end

return PenaltyRules
