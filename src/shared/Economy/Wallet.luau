--!strict
-- ReplicatedStorage.Shared.Economy.Wallet
-- Spicy Dollars kept in integer cents (BUILD_PLAN D26, brief v2 §13a; spike S15). Pure arithmetic on
-- a plain integer so the profile stores a number, never a float: every amount must be a whole,
-- finite, non-negative number of cents, and a balance never exceeds MAX_CENTS (well inside the
-- 2^53 exact-integer range of a Luau number and of the DataStore's JSON).
-- Interface: isCents(v), credit(balance, cents) -> (ok, newBalance | reason),
--            debit(balance, cents) -> (ok, newBalance | reason), format(cents) -> "S$12.34",
--            purse(cents?, watch?) -> Purse (W1: the server-life wallet until W4 binds it to the profile);
--            Purse:credit(cents, why) / Purse:debit(cents, why) -> (ok, reason?), Purse.cents, Purse.history
-- A purse made with `watch` reports every change to it as it is recorded (Economy/Bank keeps the town's
-- log and the balance on screen that way, whoever holds the purse).

local Wallet = {}

-- One trillion Spicy Dollars: far above any earnable or buyable balance, far below 2^53.
Wallet.MAX_CENTS = 100_000_000_000_000

function Wallet.isCents(v: any): boolean
	return type(v) == "number" and v == v and v >= 0 and v <= Wallet.MAX_CENTS and math.floor(v) == v
end

-- Returns (true, newBalance) or (false, reason); the balance is unchanged on failure.
function Wallet.credit(balance: number, cents: number): (boolean, number | string)
	if not Wallet.isCents(balance) then
		return false, "bad balance"
	end
	if not Wallet.isCents(cents) then
		return false, "bad amount"
	end
	local nextBalance = balance + cents
	if nextBalance > Wallet.MAX_CENTS then
		return false, "over cap"
	end
	return true, nextBalance
end

function Wallet.debit(balance: number, cents: number): (boolean, number | string)
	if not Wallet.isCents(balance) then
		return false, "bad balance"
	end
	if not Wallet.isCents(cents) then
		return false, "bad amount"
	end
	if cents > balance then
		return false, "insufficient"
	end
	return true, balance - cents
end

-- "S$1,600.00"; whole-dollar grouping with commas, always two cent digits.
function Wallet.format(cents: number): string
	local sign = if cents < 0 then "-" else ""
	local abs = math.abs(math.floor(cents))
	local dollars = abs // 100
	local rest = abs % 100
	local digits = tostring(dollars)
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return `{sign}S${grouped}.{string.format("%02d", rest)}`
end

export type Entry = { delta: number, why: string, balance: number }
export type Purse = {
	cents: number,
	history: { Entry }, -- the last HISTORY entries, oldest first
	credit: (self: Purse, cents: number, why: string) -> (boolean, string?),
	debit: (self: Purse, cents: number, why: string) -> (boolean, string?),
}

Wallet.HISTORY = 20

local function record(p: Purse, delta: number, why: string, watch: ((entry: Entry) -> ())?)
	local entry = { delta = delta, why = why, balance = p.cents }
	table.insert(p.history, entry)
	if #p.history > Wallet.HISTORY then
		table.remove(p.history, 1)
	end
	if watch then
		watch(entry)
	end
end

-- A server-life wallet (BUILD_PLAN §4.4 #6b: "Wallet (server-life until W4)").
function Wallet.purse(cents: number?, watch: ((entry: Entry) -> ())?): Purse
	local p = { cents = cents or 0, history = {} } :: Purse
	assert(Wallet.isCents(p.cents), "Wallet.purse: bad opening balance")
	function p.credit(self: Purse, amount: number, why: string): (boolean, string?)
		local ok, r = Wallet.credit(self.cents, amount)
		if not ok then
			return false, r :: string
		end
		self.cents = r :: number
		record(self, amount, why, watch)
		return true
	end
	function p.debit(self: Purse, amount: number, why: string): (boolean, string?)
		local ok, r = Wallet.debit(self.cents, amount)
		if not ok then
			return false, r :: string
		end
		self.cents = r :: number
		record(self, -amount, why, watch)
		return true
	end
	return p
end

return Wallet
