--!strict
-- ServerStorage.EngineTests.BootSmoke (CI place only; ci.project.json)
-- Requires every ModuleScript under the three code roots in the real engine (the
-- type-checker stand-in, BUILD_PLAN §6.5) and checks the project-file properties (§1.2).
-- Run by tools/cloud/tasks/boot_smoke.luau through Open Cloud Luau Execution (spike S1).

local BootSmoke = {}

export type Result = {
	ok: boolean,
	injected: boolean,
	required: number,
	failed: { { path: string, err: string } },
	warnings: { string },
	properties: { [string]: boolean },
	unreadableProperties: { string },
	stringRequireOk: boolean,
	roots: { [string]: number },
}

local ROOTS: { { name: string, get: () -> Instance? } } = {
	{
		name = "ReplicatedStorage.Shared",
		get = function()
			return game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
		end,
	},
	{
		name = "ServerScriptService.Server",
		get = function()
			return game:GetService("ServerScriptService"):FindFirstChild("Server")
		end,
	},
	{
		name = "StarterPlayer.StarterPlayerScripts.Client",
		get = function()
			local sp = game:GetService("StarterPlayer")
			local sps = sp:FindFirstChild("StarterPlayerScripts")
			return if sps then sps:FindFirstChild("Client") else nil
		end,
	},
}

-- Several of the plan's project-file properties are NotScriptable (ModelStreamingBehavior,
-- StreamOutBehavior, PlayerCharacterDestroyBehavior, SignalBehavior, Lighting.Technology): the
-- engine refuses to read them from a script, so the Lune place test (tests/place/check_place.luau)
-- is authoritative for those. Here every read is pcall-wrapped; unreadable ones are listed, not failed.
local function checkProperties(): ({ [string]: boolean }, { string }, { [string]: boolean })
	local ws = game:GetService("Workspace")
	local players = game:GetService("Players")
	local lighting = game:GetService("Lighting")
	local checks: { { name: string, read: () -> boolean, warnOnly: boolean? } } = {
		{
			name = "StreamingEnabled",
			read = function()
				return ws.StreamingEnabled == true
			end,
		},
		{
			name = "ModelStreamingBehavior",
			read = function()
				return (ws :: any).ModelStreamingBehavior == Enum.ModelStreamingBehavior.Improved
			end,
		},
		{
			name = "StreamOutBehavior",
			read = function()
				return (ws :: any).StreamOutBehavior == Enum.StreamOutBehavior.Opportunistic
			end,
		},
		{
			name = "PlayerCharacterDestroyBehavior",
			read = function()
				return (ws :: any).PlayerCharacterDestroyBehavior == Enum.PlayerCharacterDestroyBehavior.Disabled
			end,
		},
		{
			name = "SignalBehavior",
			read = function()
				return (ws :: any).SignalBehavior == Enum.SignalBehavior.Deferred
			end,
		},
		{
			name = "CharacterAutoLoads",
			read = function()
				return players.CharacterAutoLoads == false
			end,
		},
		{
			-- Players.MaxPlayers in the place file is overridden at runtime by the Place's serverSize
			-- (Creator Hub "Max players" / cloud v2 PATCH), so a mismatch is a warning, not a failure.
			name = "MaxPlayers49",
			warnOnly = true,
			read = function()
				return players.MaxPlayers == 49
			end,
		},
		{
			name = "LightingFuture",
			read = function()
				return (lighting :: any).Technology == Enum.Technology.Future
			end,
		},
	}
	local results: { [string]: boolean } = {}
	local unreadable: { string } = {}
	local warnOnly: { [string]: boolean } = {}
	for _, check in checks do
		if check.warnOnly then
			warnOnly[check.name] = true
		end
		local ok, pass = pcall(check.read)
		if ok then
			results[check.name] = pass == true
		else
			table.insert(unreadable, check.name)
		end
	end
	return results, unreadable, warnOnly
end

function BootSmoke.run(): Result
	-- tools/cloud run_engine_tests --inject rebuilds the tree inside the task instead of using a
	-- saved version; read-only properties (Players.MaxPlayers) cannot be set there.
	local injected = script.Parent ~= nil and script.Parent:GetAttribute("Injected") == true
	local properties, unreadable, warnOnly = checkProperties()
	local result: Result = {
		ok = true,
		injected = injected,
		required = 0,
		failed = {},
		warnings = {},
		properties = properties,
		unreadableProperties = unreadable,
		stringRequireOk = false,
		roots = {},
	}

	for _, root in ROOTS do
		local inst = root.get()
		if not inst then
			result.ok = false
			table.insert(result.failed, { path = root.name, err = "root missing" })
			continue
		end
		local count = 0
		for _, desc in inst:GetDescendants() do
			if desc:IsA("ModuleScript") then
				count += 1
				local ok, err = pcall(require, desc)
				if ok then
					result.required += 1
				else
					result.ok = false
					table.insert(result.failed, { path = desc:GetFullName(), err = tostring(err) })
				end
			end
		end
		result.roots[root.name] = count
	end

	-- Relative string requires (Calendar requires "./Moon") must work in the engine too.
	local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
	local timeFolder = shared and shared:FindFirstChild("Time")
	local calendarModule = timeFolder and timeFolder:FindFirstChild("Calendar")
	if calendarModule and calendarModule:IsA("ModuleScript") then
		local ok, calendar = pcall(require, calendarModule)
		if ok and type(calendar) == "table" and type(calendar.lunarAge) == "function" then
			local okCall, age = pcall(calendar.lunarAge, 7.4)
			result.stringRequireOk = okCall and type(age) == "number" and age > 7 and age < 8
		end
	end
	if not result.stringRequireOk then
		result.ok = false
	end

	for name, pass in result.properties do
		if not pass then
			if injected then
				table.insert(result.warnings, "property not applied in inject mode: " .. name)
			elseif warnOnly[name] then
				table.insert(result.warnings, "property differs at runtime (serverSize overrides the file): " .. name)
			else
				result.ok = false
				table.insert(result.failed, { path = "property:" .. name, err = "unexpected value" })
			end
		end
	end

	return result
end

return BootSmoke
