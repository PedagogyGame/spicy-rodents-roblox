--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Import
-- Cross-root require shim (spike S5 finding, 2026-11-09): a server module cannot reach
-- ReplicatedStorage.Shared with one relative string that works everywhere. On disk the shared root
-- is `src/shared` (two levels up from `src/server/AI`); in the engine it is
-- `game.ReplicatedStorage.Shared`, three levels up from `ServerScriptService.Server.AI`
-- (`../../../ReplicatedStorage/Shared/...` resolves there, measured; `@shared`-style aliases do
-- not). Lune and the engine therefore need different strings, and luau-lsp needs a path it can
-- resolve on disk for types. Callers write:
--   local Units = Import.shared("Config/Units") :: typeof(require("../shared/Config/Units"))  -- from a file at the root
--   (one ../ more per folder level below the root)
-- so the value comes from here (engine or Lune) and the type from the on-disk path.
-- Interface: shared(path) -> module. Engine-only branches run only when `script` exists.
-- STANDARD (W0, lead decision): every cross-root require goes through the Import module of its
-- own root (src/server/Import.luau, src/client/Import.luau, src/worldgen/Import.luau). Within a root,
-- plain relative string requires ("./Sibling", "../Up") are used; they resolve identically on disk and
-- in the engine.

local Import = {}

-- From src/client/ the shared root is one level up.
local LUNE_SHARED_PREFIX = "../shared/"

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
