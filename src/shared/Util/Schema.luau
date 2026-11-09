--!strict
-- ReplicatedStorage.Shared.Util.Schema
-- Declarative payload validators for the Net layer and data files (BUILD_PLAN §1.6: "every inbound
-- payload is type- and range-checked: finite numbers, known enums, existing IDs"). A schema is a plain
-- table so Net/Schemas reads as one reviewable file. Pure.
-- Interface: num{min,max,int}, str{max,enum}, bool(), enum{...}, opt(s), arr(s, max), rec{field = s},
--            any(), custom(fn, name); check(schema, value) -> (ok, err?)

export type Schema = {
	kind: string,
	min: number?,
	max: number?,
	int: boolean?,
	maxLen: number?,
	values: { [string]: boolean }?,
	inner: Schema?,
	fields: { [string]: Schema }?,
	fn: ((v: any) -> boolean)?,
	name: string?,
}

local Schema = {}

function Schema.num(o: { min: number?, max: number?, int: boolean? }?): Schema
	local opts = o or {}
	return { kind = "number", min = opts.min, max = opts.max, int = opts.int }
end

function Schema.str(o: { max: number?, enum: { string }? }?): Schema
	local opts = o or {}
	local values: { [string]: boolean }? = nil
	if opts.enum then
		local set: { [string]: boolean } = {}
		for _, v in opts.enum do
			set[v] = true
		end
		values = set
	end
	return { kind = "string", maxLen = opts.max or 200, values = values }
end

function Schema.enum(list: { string }): Schema
	return Schema.str({ enum = list, max = 64 })
end

function Schema.bool(): Schema
	return { kind = "boolean" }
end

function Schema.any(): Schema
	return { kind = "any" }
end

function Schema.opt(inner: Schema): Schema
	return { kind = "optional", inner = inner }
end

function Schema.arr(inner: Schema, max: number?): Schema
	return { kind = "array", inner = inner, max = max or 64 }
end

function Schema.rec(fields: { [string]: Schema }): Schema
	return { kind = "record", fields = fields }
end

function Schema.custom(fn: (v: any) -> boolean, name: string): Schema
	return { kind = "custom", fn = fn, name = name }
end

local function isFinite(v: number): boolean
	return v == v and v ~= math.huge and v ~= -math.huge
end

local function check(s: Schema, v: any, path: string): (boolean, string?)
	local k = s.kind
	if k == "any" then
		return true
	elseif k == "optional" then
		if v == nil then
			return true
		end
		return check(s.inner :: Schema, v, path)
	elseif k == "number" then
		if type(v) ~= "number" or not isFinite(v) then
			return false, `{path}: expected a finite number`
		end
		if s.int and math.floor(v) ~= v then
			return false, `{path}: expected an integer`
		end
		if (s.min and v < s.min) or (s.max and v > s.max) then
			return false, `{path}: {v} out of range`
		end
		return true
	elseif k == "string" then
		if type(v) ~= "string" then
			return false, `{path}: expected a string`
		end
		if #v > (s.maxLen :: number) then
			return false, `{path}: string too long`
		end
		if s.values and not s.values[v] then
			return false, `{path}: unknown value '{v}'`
		end
		return true
	elseif k == "boolean" then
		if type(v) ~= "boolean" then
			return false, `{path}: expected a boolean`
		end
		return true
	elseif k == "array" then
		if type(v) ~= "table" then
			return false, `{path}: expected an array`
		end
		local n = #v
		if n > (s.max :: number) then
			return false, `{path}: array too long`
		end
		local count = 0
		for _ in v do
			count += 1
		end
		if count ~= n then
			return false, `{path}: not a plain array`
		end
		for i = 1, n do
			local ok, err = check(s.inner :: Schema, v[i], `{path}[{i}]`)
			if not ok then
				return false, err
			end
		end
		return true
	elseif k == "record" then
		if type(v) ~= "table" then
			return false, `{path}: expected a record`
		end
		local fields = s.fields :: { [string]: Schema }
		for key in v do
			if type(key) ~= "string" or not fields[key] then
				return false, `{path}: unexpected field {tostring(key)}`
			end
		end
		for name, fs in fields do
			local ok, err = check(fs, v[name], `{path}.{name}`)
			if not ok then
				return false, err
			end
		end
		return true
	elseif k == "custom" then
		if not (s.fn :: (any) -> boolean)(v) then
			return false, `{path}: not a valid {s.name}`
		end
		return true
	end
	return false, `{path}: unknown schema kind {k}`
end

function Schema.check(s: Schema, value: any): (boolean, string?)
	return check(s, value, "$")
end

return Schema
