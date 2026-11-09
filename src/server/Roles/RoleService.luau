--!strict
-- ServerScriptService.Server.Roles.RoleService
-- Join, leave and the 49-slot cap (BUILD_PLAN §1.5 "Join", "The 49-slot server"; Addendum B4).
-- W0 (spike S2) implements only the minimum the possession spike needs:
--   onJoin(player): the 50th arrival is kicked with a polite "server full" message BEFORE any body
--     is assigned, and never counts toward population; everyone else is admitted and possesses the
--     body `pickBody` offers (W1: the Ladder's lowest human rung and Population.pickBody).
--   onLeave(player): release happens before anything else (§1.5 "Release").
-- Promotions, the Ladder and the flyover wait arrive in W1.
-- No side effects on require.
-- Interface: new(deps) -> Roles; Roles:onJoin(player) -> JoinResult, onLeave(player), admittedCount()

local Import = require("../Import")
local PossessionState =
	Import.shared("Actors/PossessionState") :: typeof(require("../../shared/Actors/PossessionState"))

export type JoinResult = "admitted" | "possessed" | "kicked"

export type Deps = {
	possession: any, -- Server/Actors/Possession Service (possess, release)
	pickBody: (player: any) -> any?, -- an Actor, or nil when none is free (W1: flyover wait)
	maxPlayers: number?, -- default PossessionState.MAX_PLAYERS (49)
	kick: ((player: any, message: string) -> ())?, -- default player:Kick(message)
}

export type Roles = {
	deps: Deps,
	admitted: { [number]: boolean },
	admittedN: number,
	kicked: number,
	onJoin: (self: Roles, player: any) -> JoinResult,
	onLeave: (self: Roles, player: any) -> (),
	admittedCount: (self: Roles) -> number,
}

local RoleService = {}

function RoleService.new(deps: Deps): Roles
	local roles = { deps = deps, admitted = {}, admittedN = 0, kicked = 0 } :: Roles

	function roles.onJoin(self: Roles, player: any): JoinResult
		local key = player.UserId :: number
		if self.admitted[key] then
			return "admitted"
		end
		if not PossessionState.admits(self.admittedN, deps.maxPlayers) then
			self.kicked += 1
			if deps.kick then
				deps.kick(player, PossessionState.FULL_MESSAGE)
			else
				(player :: Player):Kick(PossessionState.FULL_MESSAGE)
			end
			return "kicked"
		end
		self.admitted[key] = true
		self.admittedN += 1
		local actor = deps.pickBody(player)
		if actor then
			local ok = deps.possession:possess(player, actor)
			if ok then
				return "possessed"
			end
		end
		return "admitted"
	end

	function roles.onLeave(self: Roles, player: any)
		local key = player.UserId :: number
		-- release first, before anything else (also for a kicked player: a no-op)
		deps.possession:release(player, "leave")
		if self.admitted[key] then
			self.admitted[key] = nil
			self.admittedN -= 1
		end
	end

	function roles.admittedCount(self: Roles): number
		return self.admittedN
	end

	return roles
end

return RoleService
