--!strict
-- ServerScriptService.Server.Minigames.Paintball.PassDesk
-- The paintball access pass (brief v2 §13; checklist PB-12): 20 spicy cents at the pass desk buys five
-- in-game days of paintball and both lounges. Money is the town's (ServerGame.Town.charge: spicy cents
-- through the existing economy, never real money; a stand-in that says yes until the town has a
-- wallet); a refusal is shown in the town's own words. A holder is never sold a second pass, and
-- NOBODY IS CHARGED TWICE FOR ONE: the town's charge may take its time (a wallet kept in a store
-- yields), and a second press of the desk while the first is still being paid for is answered "Not
-- now." and charges nothing. A pass
-- is checked only when joining a match, so a match in progress always finishes (decision D5).
-- Until there is a profile to keep it in, a pass is remembered for as long as the server runs, by
-- UserId (a Player object is gone when its player leaves).
-- Interface: new(charge, day) -> Desk { has(player) -> boolean; buy(player) -> (ok, words);
--   untilDay(player) -> day? }; daySecs() (a game day in real seconds, Tunables clock.realSecondsPerDay)

local Import = require("../../Import")
local Contract: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract)) =
	Import.shared("Minigames/Paintball/Contract")
local Tunables = Import.shared("Config/Tunables") :: any

export type Charge = (player: any, cents: number, why: string) -> (boolean, string?)
export type Desk = {
	has: (player: any) -> boolean,
	buy: (player: any) -> (boolean, string),
	-- the in-game day a player's pass runs out on (nil: no pass was ever bought)
	untilDay: (player: any) -> number?,
}

local PassDesk = {}

-- A game day in real seconds, as the town's clock has it now.
function PassDesk.daySecs(): number
	local secs = Tunables.get("clock.realSecondsPerDay")
	return if type(secs) == "number" and secs > 0 then secs else 720
end

local function who(player: any): any
	if (type(player) == "table" or typeof(player) == "Instance") and player.UserId ~= nil then
		return player.UserId
	end
	return player
end

-- `charge` is the town's; `day` reads the in-game day (a fraction counts: five days is five days from
-- the minute of buying).
function PassDesk.new(charge: Charge, day: () -> number): Desk
	local R = Contract.Rules
	local ends: { [any]: number } = {}
	local paying: { [any]: boolean } = {} -- a charge is on its way for this user
	local function has(player: any): boolean
		local e = ends[who(player)]
		return e ~= nil and day() < e
	end
	return {
		has = has,
		buy = function(player: any): (boolean, string)
			if has(player) then
				return false, Contract.textFor("has_pass")
			end
			local key = who(player)
			if paying[key] then
				return false, Contract.textFor("phase")
			end
			paying[key] = true
			local ran, ok, why = pcall(charge, player, R.passCents, "a paintball pass")
			paying[key] = nil
			if not ran then
				error(ok, 0) -- (the town's fault is the town's to show; the desk is open again)
			end
			if not ok then
				return false, if type(why) == "string" and why ~= "" then why else Contract.textFor("pass")
			end
			ends[key] = day() + R.passDays
			return true, Contract.textFor("bought")
		end,
		untilDay = function(player: any): number?
			return ends[who(player)]
		end,
	}
end

return PassDesk
