--!strict
-- ReplicatedStorage.Shared.Config.Flags
-- Feature flags and dev gating (BUILD_PLAN §1.4): a dev is anyone in Studio or a UserId on the dev
-- list (the owner's account is added by the server at init from docs/spec/PROJECT_IDS.md's owner id;
-- no id is hard-coded here). Flags default off unless listed; Lune tests set the environment through
-- configure(). Engine reads happen only inside isStudio's default, never on require.
-- Interface: enabled(name) -> boolean; set(name, on); isDev(player) -> boolean;
--            configure({ devUserIds?, isStudio? })

local Flags = {}

-- Defaults for the W1 spine. Role Lab and live Tunables are dev-gated at their call sites as well.
Flags.defaults = {
	roleLab = true, -- the dev-only Role Lab backend exists (still gated by isDev per command)
	liveTunables = true, -- Tunables mirror to ReplicatedStorage.TunablesLive for devs
	moveValidatorEnforce = false, -- log-only until W7 (BUILD_PLAN §1.4 MoveValidator)
	persistence = false, -- DataStore binding lands in W4 #11; W1 uses the in-memory store
} :: { [string]: boolean }

local state = {
	flags = table.clone(Flags.defaults) :: { [string]: boolean },
	devUserIds = {} :: { [number]: boolean },
	isStudio = nil :: (() -> boolean)?,
}

local function engineIsStudio(): boolean
	local ok, result = pcall(function()
		return game:GetService("RunService"):IsStudio()
	end)
	return ok and result == true
end

function Flags.configure(opts: { devUserIds: { number }?, isStudio: (() -> boolean)? })
	if opts.devUserIds then
		state.devUserIds = {}
		for _, id in opts.devUserIds do
			state.devUserIds[id] = true
		end
	end
	if opts.isStudio ~= nil then
		state.isStudio = opts.isStudio
	end
end

function Flags.enabled(name: string): boolean
	return state.flags[name] == true
end

function Flags.set(name: string, on: boolean)
	state.flags[name] = on
end

function Flags.reset()
	state.flags = table.clone(Flags.defaults)
end

function Flags.isDev(player: any): boolean
	local studio = if state.isStudio then state.isStudio() else engineIsStudio()
	if studio then
		return true
	end
	local id = if type(player) == "table" or typeof(player) == "Instance" then player.UserId else nil
	return type(id) == "number" and state.devUserIds[id] == true
end

return Flags
