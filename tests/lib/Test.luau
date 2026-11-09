--!strict
-- Tiny assertion library for the Lune test harness (tests/run.luau).
-- A spec file returns `function(t: Test.T)` and registers cases with t.test(name, fn).

local Test = {}

export type Case = { name: string, fn: () -> () }

export type T = {
	test: (name: string, fn: () -> ()) -> (),
	eq: (actual: any, expected: any, msg: string?) -> (),
	neq: (actual: any, unexpected: any, msg: string?) -> (),
	near: (actual: number, expected: number, eps: number?, msg: string?) -> (),
	truthy: (value: any, msg: string?) -> (),
	falsy: (value: any, msg: string?) -> (),
	isType: (value: any, typeName: string, msg: string?) -> (),
	fails: (fn: () -> (), pattern: string?) -> (),
	deepEq: (actual: any, expected: any, msg: string?) -> (),
}

local function fail(msg: string, level: number?)
	error(msg, (level or 2) + 1)
end

local function show(v: any): string
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

local function deepEquals(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEquals(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

function Test.new(): (T, { Case })
	local cases: { Case } = {}
	local t: T = {
		test = function(name: string, fn: () -> ())
			table.insert(cases, { name = name, fn = fn })
		end,
		eq = function(actual: any, expected: any, msg: string?)
			if actual ~= expected then
				fail(`{msg or "eq"}: expected {show(expected)}, got {show(actual)}`)
			end
		end,
		neq = function(actual: any, unexpected: any, msg: string?)
			if actual == unexpected then
				fail(`{msg or "neq"}: did not expect {show(unexpected)}`)
			end
		end,
		near = function(actual: number, expected: number, eps: number?, msg: string?)
			local tolerance = eps or 1e-6
			if actual ~= actual or math.abs(actual - expected) > tolerance then
				fail(`{msg or "near"}: expected {expected} +/- {tolerance}, got {actual}`)
			end
		end,
		truthy = function(value: any, msg: string?)
			if not value then
				fail(`{msg or "truthy"}: got {show(value)}`)
			end
		end,
		falsy = function(value: any, msg: string?)
			if value then
				fail(`{msg or "falsy"}: got {show(value)}`)
			end
		end,
		isType = function(value: any, typeName: string, msg: string?)
			if typeof(value) ~= typeName then
				fail(`{msg or "isType"}: expected {typeName}, got {typeof(value)}`)
			end
		end,
		fails = function(fn: () -> (), pattern: string?)
			local ok, err = pcall(fn)
			if ok then
				fail("fails: function did not error")
			end
			if pattern and not string.find(tostring(err), pattern) then
				fail(`fails: error {show(tostring(err))} does not match {show(pattern)}`)
			end
		end,
		deepEq = function(actual: any, expected: any, msg: string?)
			if not deepEquals(actual, expected) then
				fail(`{msg or "deepEq"}: tables differ`)
			end
		end,
	}
	return t, cases
end

return Test
