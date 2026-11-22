--!strict
-- ReplicatedStorage.Shared.Reputation.Reputation
-- The one door any server service uses to say a player did something the town will hold against them (owner D30:
-- reputation in the background, only for extreme acts). The caller has already judged the act extreme by its own rules
-- (an errand's delivery kept, a bite victim driven past); here it is handed to the server's reputation
-- (Server/Reputation/ReputationService, bound at boot), which rests each kind a while so it is never a stream:
--     local ok, Reputation = pcall(function() return Import.shared("Reputation/Reputation") end)
--     if ok then Reputation.report(player, "errand_theft", 2) end
--   kind      "errand_theft", "ignored_victim" (the notice's words: Reputation/Conduct.KINDS; another kind reads
--             "something you did upset the town")
--   severity  1, 2 or 3 (default 1): 5, 10 or 15 points (Conduct.C.reported)
-- report returns true when it counted (the player was told); false when it did not (resting, no player, nothing bound:
-- on a client, or in a spec that never started the service). It never errors.
-- Interface: report(player, kind, severity?) -> boolean; bind(sink?) (the server's, at boot; nil unbinds); bound()
-- No side effects on require.

local Reputation = {}

export type Sink = { report: (player: any, kind: string, severity: number?) -> boolean }

local sink: Sink? = nil

function Reputation.bind(s: Sink?)
	sink = s
end

function Reputation.bound(): boolean
	return sink ~= nil
end

function Reputation.report(player: any, kind: string, severity: number?): boolean
	local s = sink
	if s == nil or player == nil then
		return false
	end
	local ok, counted = pcall(s.report, player, kind, severity)
	return ok and counted == true
end

return Reputation
