--!strict
-- ReplicatedStorage.Shared.Data
-- Read-only accessors over the compiled data (tools/compile output: generated/ on disk,
-- ReplicatedStorage.Shared.Generated in the engine). BUILD_PLAN §1.4, §3. Chunks load lazily on first
-- use through `Generated.Index`; a module the compiler has not produced yet reads as empty and is listed
-- by missing(), so callers never branch on the wave. Returned tables are the compiled ones: treat them
-- as read-only (they are frozen in the engine by table.freeze on load).
-- Pure apart from the loader: Data.new(loader) takes any `name -> module?`; Data.default() picks the
-- engine folder or the Lune path. No side effects on require.
-- Interface: new(loader) -> Data; default() -> Data; Data:index(); lots(); lot(id); lotType(t); routes()
--            (Routes/Registry); lanes(); roads(); cast(); forks(); wildlife(); nav(); colliders(); forage();
--            hollows(); quests(); markers(); assets(); bakeHash(); has(name); missing()

local Registry = require("./Routes/Registry")

export type Loader = (name: string) -> any?

export type Data = {
	_load: Loader,
	_cache: { [string]: any },
	_missing: { [string]: boolean },
	_byId: { [string]: { [string]: any } },
	_routes: Registry.Registry?,
	index: (self: Data) -> any,
	module: (self: Data, name: string) -> { any },
	byId: (self: Data, name: string, id: string) -> any?,
	lots: (self: Data) -> { any },
	lot: (self: Data, id: string) -> any?,
	lotType: (self: Data, t: string) -> any?,
	routes: (self: Data) -> Registry.Registry,
	lanes: (self: Data) -> { any },
	roads: (self: Data) -> { any },
	cast: (self: Data) -> { any },
	forks: (self: Data) -> { any },
	wildlife: (self: Data) -> any,
	nav: (self: Data) -> any,
	colliders: (self: Data) -> { any },
	forage: (self: Data) -> any,
	hollows: (self: Data) -> { any },
	quests: (self: Data) -> { any },
	markers: (self: Data) -> { any },
	assets: (self: Data) -> any,
	bakeHash: (self: Data) -> string?,
	has: (self: Data, name: string) -> boolean,
	missing: (self: Data) -> { string },
}

local Data = {}

local EMPTY = table.freeze({})

function Data.new(loader: Loader): Data
	local data = { _load = loader, _cache = {}, _missing = {}, _byId = {} } :: Data

	local function loadName(self: Data, name: string): any?
		local cached = self._cache[name]
		if cached ~= nil then
			return cached
		end
		local ok, mod = pcall(self._load, name)
		if not ok or mod == nil then
			return nil
		end
		self._cache[name] = mod
		return mod
	end

	function data.index(self: Data): any
		return loadName(self, "Index") or { modules = {} }
	end

	-- A compiled module by its Index name, its chunks concatenated in order (arrays) or the single
	-- chunk as is (records). Missing modules read as an empty table and are remembered.
	function data.module(self: Data, name: string): { any }
		local key = "module:" .. name
		local cached = self._cache[key]
		if cached ~= nil then
			return cached
		end
		local entry = self:index().modules[name]
		if not entry then
			self._missing[name] = true
			self._cache[key] = EMPTY
			return EMPTY :: any
		end
		local result: any
		if #entry.chunks == 1 then
			result = loadName(self, entry.chunks[1])
		else
			local all = {}
			for _, chunk in entry.chunks do
				for _, rec in (loadName(self, chunk) or {}) :: { any } do
					table.insert(all, rec)
				end
			end
			result = all
		end
		if result == nil then
			self._missing[name] = true
			result = EMPTY
		end
		self._cache[key] = result
		return result
	end

	function data.byId(self: Data, name: string, id: string): any?
		local map = self._byId[name]
		if not map then
			map = {}
			for _, rec in self:module(name) do
				if type(rec) == "table" and rec.id ~= nil then
					map[rec.id] = rec
				end
			end
			self._byId[name] = map
		end
		return map[id]
	end

	function data.lots(self: Data)
		return self:module("Lots")
	end
	function data.lot(self: Data, id: string)
		return self:byId("Lots", id)
	end
	function data.lotType(self: Data, t: string)
		return self:byId("LotTypes", t)
	end
	function data.routes(self: Data): Registry.Registry
		if not self._routes then
			local entry = self:index().modules.Routes
			local loaders = {}
			if entry then
				for i, chunk in entry.chunks do
					loaders[i] = function()
						return loadName(self, chunk) or {}
					end
				end
			else
				self._missing.Routes = true
			end
			self._routes = Registry.new({ loaders = loaders, studsPerUnit = self:index().studsPerUnit })
		end
		return self._routes :: Registry.Registry
	end
	function data.lanes(self: Data)
		return self:module("Lanes")
	end
	function data.roads(self: Data)
		return self:module("Roads")
	end
	function data.cast(self: Data)
		return self:module("Cast")
	end
	function data.forks(self: Data)
		return self:module("Forks")
	end
	function data.wildlife(self: Data)
		return self:module("Wildlife")
	end
	function data.nav(self: Data)
		return self:module("Nav")
	end
	function data.colliders(self: Data)
		return self:module("Colliders")
	end
	function data.forage(self: Data)
		return self:module("Forage")
	end
	function data.hollows(self: Data)
		return self:module("Hollows")
	end
	function data.quests(self: Data)
		return self:module("Quests")
	end
	function data.markers(self: Data)
		return self:module("Markers")
	end
	function data.assets(self: Data)
		return self:module("Assets")
	end
	function data.bakeHash(self: Data): string?
		local idx = self:index()
		return idx.bakeHash or (idx.harvestPin and idx.harvestPin.sha256)
	end
	function data.has(self: Data, name: string): boolean
		return self:index().modules[name] ~= nil
	end
	function data.missing(self: Data): { string }
		local out = {}
		for name in self._missing do
			table.insert(out, name)
		end
		table.sort(out)
		return out
	end

	return data
end

local defaultData: Data? = nil

-- The process-wide instance over the compiled data: Shared.Generated in the engine, generated/ in Lune.
function Data.default(): Data
	if defaultData then
		return defaultData
	end
	local loader: Loader
	if script ~= nil then
		local folder = (script :: any).Parent:FindFirstChild("Generated")
		loader = function(name: string): any?
			local m = folder and folder:FindFirstChild(name)
			if not m then
				return nil
			end
			local mod = (require :: any)(m)
			if type(mod) == "table" and not table.isfrozen(mod) then
				table.freeze(mod)
			end
			return mod
		end
	else
		-- init.luau: "./" is src/shared, "../../" is the repo root
		loader = function(name: string): any?
			return (require :: any)("../../generated/" .. name)
		end
	end
	defaultData = Data.new(loader)
	return defaultData :: Data
end

return Data
