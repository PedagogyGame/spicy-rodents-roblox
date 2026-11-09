--!strict
-- ServerScriptService.Server.Roles.RoleLab
-- Dev-only Lab backend (BUILD_PLAN §1.4, §3.7 "The Role Lab's forceRole reads the same rung table and
-- logs when it exceeds a cap; the Lab never edits the ladder"; §4.4 #4 "Become X"). Commands arrive as
-- `Lab.Command` { cmd, args } (Net/Schemas, devOnly) and are refused for non-devs (Config/Flags.isDev).
-- Pure over the RoleService it is given. No side effects on require.
-- Commands: become <rung>; stat <name> <number>; event <kind> [key value]...; perf <number>;
--           tune <path> <value>; export; reset; state
-- Interface: new(roles, opts?) -> Lab; Lab:command(player, cmd, args) -> (ok, result | err); RUNGS

local Import = require("../Import")
local Flags = Import.shared("Config/Flags") :: typeof(require("../../shared/Config/Flags"))
local Ladder = Import.shared("Roles/Ladder") :: typeof(require("../../shared/Roles/Ladder"))
local Tunables = Import.shared("Config/Tunables") :: typeof(require("../../shared/Config/Tunables"))

export type Lab = {
	roles: any,
	isDev: (player: any) -> boolean,
	command: (self: Lab, player: any, cmd: string, args: { any }?) -> (boolean, any),
}

local RoleLab = {}

-- The "Become X" buttons, in ladder order (rungs then side exits).
RoleLab.RUNGS = { "human", "hospital", "police", "squirrel", "rodent", "deer", "fox" }

local STATS = {
	activeMinutes = true,
	activeGameDays = true,
	cents = true,
	reputation = true,
	entourage = true,
	kicks = true,
	questScore = true,
	adminPerformance = true,
	nuts = true,
	cohortMaxNuts = true,
	stinkPct = true,
}

function RoleLab.new(roles: any, opts: { isDev: ((player: any) -> boolean)? }?): Lab
	local lab = { roles = roles, isDev = (opts and opts.isDev) or Flags.isDev } :: Lab

	function lab.command(self: Lab, player: any, cmd: string, args: { any }?): (boolean, any)
		if not self.isDev(player) then
			return false, "dev only"
		end
		local a = args or {}
		if cmd == "become" then
			local rung = a[1]
			if type(rung) ~= "string" or not table.find(RoleLab.RUNGS, rung) then
				return false, "unknown rung"
			end
			local ok, overCap = self.roles:forceRole(player, rung)
			return ok, if overCap then "over cap (logged)" else "ok"
		elseif cmd == "stat" then
			local name, value = a[1], a[2]
			if type(name) ~= "string" or not STATS[name] or type(value) ~= "number" then
				return false, "stat <name> <number>"
			end
			local stats = self.roles:stats(player)
			if not stats then
				return false, "not a member"
			end
			stats[name] = value
			if name == "cents" then
				local m = self.roles:member(player.UserId)
				m.purse.cents = value
			end
			return true, "ok"
		elseif cmd == "event" then
			local kind = a[1]
			if type(kind) ~= "string" or not table.find(Ladder.EVENTS, kind) then
				return false, "unknown event"
			end
			local event: { [string]: any } = { kind = kind, player = player.UserId }
			for i = 2, #a - 1, 2 do
				event[tostring(a[i])] = a[i + 1]
			end
			return true, self.roles:report(event)
		elseif cmd == "perf" then
			local value = a[1]
			if type(value) ~= "number" then
				return false, "perf <number>"
			end
			local previous = self.roles.policePerformance
			self.roles.policePerformance = value
			return true, self.roles:report({ kind = "police.performance", previous = previous, performance = value })
		elseif cmd == "tune" then
			local applied, errors = Tunables.applyOverrides({ [tostring(a[1])] = a[2] })
			return applied == 1, if applied == 1 then "ok" else errors[1]
		elseif cmd == "export" then
			return true, Tunables.diff()
		elseif cmd == "reset" then
			return true, self.roles:resetSession(nil)
		elseif cmd == "state" then
			local rung, sub = self.roles:roleOf(player)
			return true, { rung = rung, subrole = sub, stats = self.roles:stats(player), offers = self.roles:offers() }
		end
		return false, "unknown command"
	end

	return lab
end

return RoleLab
