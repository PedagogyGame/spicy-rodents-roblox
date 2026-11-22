--!strict
-- ServerScriptService.Server.Work.Penalties
-- The D30 penalties, applied (the rules are Shared/Work/PenaltyRules; read its header for what "the lowest
-- townsperson station's money level" means and why a fine never takes a balance below nothing):
--   * errandStolen(player, what): an errand runner kept a bank errand's parcel (past the time limit, kept in their
--     own home, or took it out of the server: Server/Work/ErrandService decides which). The fine through the wallet,
--     a line on their screen, and a reputation report (kind "errand_stolen").
--   * ambulanceIgnored(player): a doctor driving the ambulance ignored a bite victim who needed picking up (the
--     doctors' work decides that and demotes: RoleService.demote; this is only the money side). The fine, then the
--     doctor's money down to the lowest townsperson's (PenaltyRules.ambulance), a line on their screen, and a
--     reputation report (kind "ambulance_ignored").
-- Money moves only through the town's wallet (Economy/Credits: wallet.purse(player):debit(cents, why), which takes
-- earnings before pocket money and is logged and shown like any other change). A saved stock-option balance (the
-- D30 stock options) is not wallet money and is never touched here.
-- Reputation: the D30 reputation work owns it; this calls report(player, kind, severity) inside a pcall, through
-- deps.report when given, else through the first of REPUTATION_MODULES that loads and has a `report` (none: nothing
-- happens, the money penalty stands).
-- The module-level functions (Penalties.errandStolen, Penalties.ambulanceIgnored) use the instance Boot/Game
-- installs (Penalties.install(deps)); before that they do nothing and return 0, with a warning.
-- Interface: new(deps) -> Instance { errandStolen(player, what?) -> cents, ambulanceIgnored(player) -> (fine, down) };
--   install(deps) -> Instance; errandStolen(player, what?); ambulanceIgnored(player); REPUTATION_MODULES; SEVERITY
-- Pure over deps (a player is a Player or a PlayerLike stub with a UserId); no side effects on require.

local Import = require("../Import")
local PenaltyRules = Import.shared("Work/PenaltyRules") :: typeof(require("../../shared/Work/PenaltyRules"))
local EconomyRules = Import.shared("Economy/EconomyRules") :: typeof(require("../../shared/Economy/EconomyRules"))
local Bank = Import.shared("Economy/Bank") :: typeof(require("../../shared/Economy/Bank"))

local Penalties = {}

-- where the reputation work's report(player, kind, severity) may live (shared first, then the server's)
Penalties.REPUTATION_MODULES = table.freeze({ "Reputation/Reputation", "Reputation/ReputationService" })
-- how bad each is on the reputation work's scale (0..1: only extreme acts are marked at all)
Penalties.SEVERITY = table.freeze({ errand_stolen = 0.8, ambulance_ignored = 0.9 })

export type Deps = {
	wallet: any, -- Economy/Credits.Wallet (purse(player), tell(player, words))
	-- the balances of every other player on the townsperson rung (default: deps.roles' members on "human")
	townBalances: ((except: any) -> { number })?,
	roles: any?, -- Roles/RoleService (members: by UserId, each { rung, purse })
	pocket: (() -> number)?, -- default EconomyRules.pocketMoney
	report: ((player: any, kind: string, severity: number) -> ())?,
	warn: ((line: string) -> ())?,
}

export type Instance = {
	errandStolen: (player: any, what: string?) -> number,
	ambulanceIgnored: (player: any) -> (number, number),
}

local function userId(player: any): any
	local ok, id = pcall(function()
		return (player :: any).UserId
	end)
	return if ok and id ~= nil then id else player
end

local function defaultReport(player: any, kind: string, severity: number)
	for _, path in Penalties.REPUTATION_MODULES do
		local ok, mod = pcall(Import.shared, path)
		if ok and type(mod) == "table" and type((mod :: any).report) == "function" then
			(mod :: any).report(player, kind, severity)
			return
		end
	end
end

function Penalties.new(deps: Deps): Instance
	local wallet = deps.wallet
	local shout = deps.warn or function(line: string)
		warn(`[Penalties] {line}`)
	end
	local report = deps.report or defaultReport
	local pocket = deps.pocket or EconomyRules.pocketMoney

	local function rep(player: any, kind: string)
		local ok, err = pcall(function()
			report(player, kind, Penalties.SEVERITY[kind] or 1)
		end)
		if not ok then
			shout(`reputation report {kind} failed: {err}`)
		end
	end

	local function take(player: any, cents: number, why: string): number
		if cents <= 0 then
			return 0
		end
		local ok, err = wallet.purse(player):debit(cents, why)
		if not ok then
			shout(`could not take {cents}c ({why}) from {tostring(userId(player))}: {tostring(err)}`)
			return 0
		end
		return cents
	end

	local function balances(except: any): { number }
		if deps.townBalances then
			return deps.townBalances(except)
		end
		local out: { number } = {}
		local roles = deps.roles
		local me = userId(except)
		if roles and type(roles.members) == "table" then
			for id, m in roles.members do
				if id ~= me and m.rung == "human" and m.purse then
					table.insert(out, m.purse.cents)
				end
			end
		end
		return out
	end

	return {
		errandStolen = function(player: any, what: string?): number
			local taken = take(player, PenaltyRules.fine(wallet.balance(player)), PenaltyRules.WHY.errand)
			wallet.tell(
				player,
				`You kept {what or "the parcel"} instead of delivering it: {Bank.amount(taken)} taken as a penalty.`
			)
			rep(player, "errand_stolen")
			return taken
		end,
		ambulanceIgnored = function(player: any): (number, number)
			local level = PenaltyRules.townLevel(balances(player), pocket())
			local fine, down = PenaltyRules.ambulance(wallet.balance(player), level)
			local tookFine = take(player, fine, PenaltyRules.WHY.ambulance)
			local tookDown = take(player, down, PenaltyRules.WHY.level)
			local rest = if tookDown > 0
				then `, and your money is down to the lowest townsperson's ({Bank.amount(level)})`
				else ""
			wallet.tell(player, `A bite victim was left waiting: {Bank.amount(tookFine)} penalty{rest}.`)
			rep(player, "ambulance_ignored")
			return tookFine, tookDown
		end,
	}
end

local installed: Instance? = nil

-- Boot/Game's: the instance the module-level functions use.
function Penalties.install(deps: Deps): Instance
	installed = Penalties.new(deps)
	return installed :: Instance
end

function Penalties.errandStolen(player: any, what: string?): number
	if installed == nil then
		warn("[Penalties] errandStolen before install: nothing taken")
		return 0
	end
	return (installed :: Instance).errandStolen(player, what)
end

-- The money side of a doctor's demotion for an ignored bite victim (the doctors' work calls it; it demotes).
function Penalties.ambulanceIgnored(player: any): (number, number)
	if installed == nil then
		warn("[Penalties] ambulanceIgnored before install: nothing taken")
		return 0, 0
	end
	return (installed :: Instance).ambulanceIgnored(player)
end

return Penalties
