--!strict
-- ServerScriptService.Server.Persistence.MemoryStore
-- The W1 in-memory profile store (BUILD_PLAN §4.4 #6b; the DataStore binding lands in W4 #11). It has
-- the DataStoreLike shape ProfileStore drives (UpdateAsync with a transform, GetAsync) and keeps every
-- record as the Serializer's string, so each write proves the profile survives the exact bytes a
-- DataStore would hold. Server-life only. No side effects on require.
-- Interface: new() -> Store; Store:UpdateAsync(key, transform) -> (value, info); Store:GetAsync(key);
--            Store:raw(key) -> string?; Store:writes()

local Serializer = require("./Serializer")

export type Store = {
	_data: { [string]: string },
	_writes: number,
	UpdateAsync: (self: Store, key: string, transform: (any, any) -> any) -> (any, any),
	GetAsync: (self: Store, key: string) -> any,
	raw: (self: Store, key: string) -> string?,
	writes: (self: Store) -> number,
}

local MemoryStore = {}

local function load(self: Store, key: string): any
	local text = self._data[key]
	if text == nil then
		return nil
	end
	local record, err = Serializer.unpack(text)
	if err then
		error(`MemoryStore: {key}: {err}`)
	end
	return record
end

function MemoryStore.new(): Store
	local store = { _data = {}, _writes = 0 } :: Store

	function store.UpdateAsync(self: Store, key: string, transform: (any, any) -> any): (any, any)
		local current = load(self, key)
		local nextValue = transform(current, nil)
		if nextValue == nil then
			return current, nil -- a nil transform result cancels the write (DataStore semantics)
		end
		self._data[key] = Serializer.pack(nextValue)
		self._writes += 1
		return load(self, key), nil
	end

	function store.GetAsync(self: Store, key: string): any
		return load(self, key)
	end

	function store.raw(self: Store, key: string): string?
		return self._data[key]
	end

	function store.writes(self: Store): number
		return self._writes
	end

	return store
end

return MemoryStore
