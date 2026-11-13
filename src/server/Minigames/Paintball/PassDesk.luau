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
-- A pass is remembered by UserId (a Player object is gone when its player leaves) for as long as the
-- server runs, and, given a STORE (the player's profile: whoever wires the desk to it hands over
-- load and save), beyond: a player's pass is loaded from the store the first time the desk is asked
-- about them, and saved to it the moment it is bought (a store that fails to save is the store's to
-- show; the pass holds for this server either way, and the money is never taken twice). The day a pass
-- runs until is on the clock `day` reads: it must be the town's own game-day count (one that carries on
-- from server to server) for a stored pass to mean the same thing everywhere.
-- Interface: new(charge, day, store?) -> Desk { has(player) -> boolean; buy(player) -> (ok, words);
--   untilDay(player) -> day? }; daySecs() (a game day in real seconds, Tunables clock.realSecondsPerDay);
--   types Charge, Store, Desk

local Import = require("../../Import")
local Contract: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract)) =
	Import.shared("Minigames/Paintball/Contract")
local Tunables = Import.shared("Config/Tunables") :: any

export type Charge = (player: any, cents: number, why: string) -> (boolean, string?)
-- Where passes outlive the server (the profile): the game day a player's pass runs until, or nil
export type Store = {
	load: (player: any) -> number?,
	save: (player: any, untilDay: number) -> (),
}
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
function PassDesk.new(charge: Charge, day: () -> number, store: Store?): Desk
	local R = Contract.Rules
	local ends: { [any]: number } = {}
	local loaded: { [any]: boolean } = {} -- the store has been asked about this user
	local paying: { [any]: boolean } = {} -- a charge is on its way for this user
	local function untilDay(player: any): number?
		local key = who(player)
		if store ~= nil and not loaded[key] then
			loaded[key] = true
			local ran, kept = pcall(store.load, player)
			if ran and type(kept) == "number" and kept == kept and (ends[key] == nil or kept > ends[key]) then
				ends[key] = kept
			end
		end
		return ends[key]
	end
	local function has(player: any): boolean
		local e = untilDay(player)
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
			local runs = day() + R.passDays
			ends[key] = runs
			if store ~= nil then
				pcall(store.save, player, runs)
			end
			return true, Contract.textFor("bought")
		end,
		untilDay = untilDay,
	}
end

return PassDesk
