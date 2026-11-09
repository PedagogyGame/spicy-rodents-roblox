--!strict
-- ServerScriptService.Server.Persistence.MockDataStore
-- An in-memory stand-in for a GlobalDataStore with fault injection (spike S15): the Lune tests run
-- ProfileStore and the receipt handler against it (crash, retry, double delivery, two servers), and
-- it can back a Studio play-solo session when API services are off. Values are deep-copied in and
-- out, as the real service serialises them. UpdateAsync follows the engine contract: the transform
-- gets (old, keyInfo) and returns the new value, or nil to cancel without writing.
-- Faults (queued, consumed one per call): "error" (throws before anything happens), "commitThenError"
-- (writes, then throws: the ambiguous failure), "throttle" (throws a 'request was throttled' error).
-- Interface: new() -> Store; store:UpdateAsync(key, fn), store:GetAsync(key), store:fail(kind, n),
--            store:peek(key), store.calls

local ProfileSchema = require("./ProfileSchema")

export type Fault = "error" | "commitThenError" | "throttle"
export type Store = {
	data: { [string]: any },
	faults: { Fault },
	calls: { updates: number, gets: number, writes: number },
	UpdateAsync: (self: Store, key: string, transform: (any, any) -> any) -> (any, any),
	GetAsync: (self: Store, key: string) -> any,
	fail: (self: Store, kind: Fault, count: number?) -> (),
	peek: (self: Store, key: string) -> any,
}

local MockDataStore = {}

local function takeFault(self: Store): Fault?
	return table.remove(self.faults, 1)
end

local function updateAsync(self: Store, key: string, transform: (any, any) -> any): (any, any)
	self.calls.updates += 1
	local fault = takeFault(self)
	if fault == "error" then
		error("MockDataStore: 502 internal error (injected)")
	elseif fault == "throttle" then
		error("MockDataStore: request was throttled (injected)")
	end
	local old = ProfileSchema.deepCopy(self.data[key])
	local new = transform(old, nil)
	if new == nil then
		return nil, nil
	end
	self.data[key] = ProfileSchema.deepCopy(new)
	self.calls.writes += 1
	if fault == "commitThenError" then
		error("MockDataStore: connection lost after commit (injected)")
	end
	return ProfileSchema.deepCopy(new), nil
end

local function getAsync(self: Store, key: string): any
	self.calls.gets += 1
	local fault = takeFault(self)
	if fault == "error" or fault == "throttle" then
		error(`MockDataStore: {fault} (injected)`)
	end
	return ProfileSchema.deepCopy(self.data[key])
end

function MockDataStore.new(): Store
	local store = {
		data = {},
		faults = {},
		calls = { updates = 0, gets = 0, writes = 0 },
		UpdateAsync = updateAsync,
		GetAsync = getAsync,
		fail = function(self: Store, kind: Fault, count: number?)
			for _ = 1, count or 1 do
				table.insert(self.faults, kind)
			end
		end,
		peek = function(self: Store, key: string): any
			return ProfileSchema.deepCopy(self.data[key])
		end,
	}
	return store :: Store
end

return MockDataStore
