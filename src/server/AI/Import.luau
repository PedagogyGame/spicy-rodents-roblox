--!strict
-- ServerScriptService.Server.AI.Import
-- Cross-root require shim (spike S5 finding, 2026-11-09): a server module cannot reach
-- ReplicatedStorage.Shared with one relative string that works everywhere. On disk the shared root
-- is `src/shared` (two levels up from `src/server/AI`); in the engine it is
-- `game.ReplicatedStorage.Shared`, three levels up from `ServerScriptService.Server.AI`
-- (`../../../ReplicatedStorage/Shared/...` resolves there, measured; `@shared`-style aliases do
-- not). Lune and the engine therefore need different strings, and luau-lsp needs a path it can
-- resolve on disk for types. Callers write:
--   local Units = Import.shared("Config/Units") :: typeof(require("../../shared/Config/Units"))
-- so the value comes from here (engine or Lune) and the type from the on-disk path.
-- Interface: shared(path) -> module. Engine-only branches run only when `script` exists.
-- The lead may move this to src/server/Import.luau (or change the Rojo tree) for every root.

local Import = {}

-- From src/server/AI/ the shared root is two levels up.
local LUNE_SHARED_PREFIX = "../../shared/"

local function engineShared(path: string): any
	local node: Instance = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
		or error("Import.shared: ReplicatedStorage.Shared missing")
	for part in string.gmatch(path, "[^/]+") do
		node = node:FindFirstChild(part) or error(`Import.shared: {path} missing at {part}`)
	end
	if not node:IsA("ModuleScript") then
		error(`Import.shared: {path} is not a ModuleScript`)
	end
	return (require :: any)(node)
end

-- `path` is relative to the shared root, with forward slashes: "Config/Units", "Actors/Species".
function Import.shared(path: string): any
	if script ~= nil then
		return engineShared(path)
	end
	return (require :: any)(LUNE_SHARED_PREFIX .. path)
end

return Import
