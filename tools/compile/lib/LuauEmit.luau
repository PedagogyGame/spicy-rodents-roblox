--!strict
-- Emits Luau ModuleScript sources (`return { ... }`) from plain data, deterministically:
-- keys sorted (with an optional preferred prefix order), shortest round-trip numbers, strings
-- escaped, arrays of scalars inline. Records can be split into size-bounded chunks.
local LuauEmit = {}

local KEYWORDS: { [string]: boolean } = {}
for _, k in
	{
		"and",
		"break",
		"do",
		"else",
		"elseif",
		"end",
		"false",
		"for",
		"function",
		"if",
		"in",
		"local",
		"nil",
		"not",
		"or",
		"repeat",
		"return",
		"then",
		"true",
		"until",
		"while",
		"continue",
		"type",
		"export",
	}
do
	KEYWORDS[k] = true
end

function LuauEmit.formatNumber(x: number): string
	if x ~= x or x == math.huge or x == -math.huge then
		error("non-finite number in generated data")
	end
	if x == 0 then
		return "0"
	end
	if x % 1 == 0 and math.abs(x) < 9007199254740992 then
		return string.format("%d", x)
	end
	for _, fmt in { "%.15g", "%.16g", "%.17g" } do
		local s = string.format(fmt, x)
		if tonumber(s) == x then
			return s
		end
	end
	return string.format("%.17g", x)
end

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["\0"] = "\\0" }
function LuauEmit.formatString(s: string): string
	local out = string.gsub(s, '[%c"\\]', function(c)
		local e = ESCAPES[c]
		if e then
			return e
		end
		return string.format("\\%03d", string.byte(c))
	end)
	return '"' .. out .. '"'
end

local function formatKey(k: string): string
	if string.find(k, "^[%a_][%w_]*$") and not KEYWORDS[k] then
		return k
	end
	return "[" .. LuauEmit.formatString(k) .. "]"
end

local function isArray(t: any): boolean
	if type(t) ~= "table" then
		return false
	end
	local n = #t
	if n == 0 then
		return next(t) == nil
	end
	local count = 0
	for _ in pairs(t) do
		count += 1
	end
	return count == n
end

local function isScalar(v: any): boolean
	local t = type(v)
	return t == "number" or t == "string" or t == "boolean"
end

local function sortedKeys(t: { [string]: any }, keyOrder: { string }?): { string }
	local keys = {}
	for k in pairs(t) do
		if type(k) ~= "string" then
			error("generated tables must have string keys or be arrays; got key " .. tostring(k))
		end
		table.insert(keys, k)
	end
	local rank: { [string]: number } = {}
	if keyOrder then
		for i, k in keyOrder do
			rank[k] = i
		end
	end
	table.sort(keys, function(a, b)
		local ra, rb = rank[a], rank[b]
		if ra and rb then
			return ra < rb
		elseif ra then
			return true
		elseif rb then
			return false
		end
		return a < b
	end)
	return keys
end

export type Options = { keyOrder: { string }?, inlineLimit: number? }

local function emit(v: any, depth: number, opts: Options): string
	local tv = type(v)
	if tv == "number" then
		return LuauEmit.formatNumber(v)
	elseif tv == "string" then
		return LuauEmit.formatString(v)
	elseif tv == "boolean" then
		return v and "true" or "false"
	elseif tv == "nil" then
		error("nil cannot appear in a generated table literal")
	elseif tv ~= "table" then
		error("cannot emit value of type " .. tv)
	end
	local pad = string.rep("\t", depth)
	local padIn = string.rep("\t", depth + 1)
	if isArray(v) then
		local arr = v :: { any }
		if #arr == 0 then
			return "{}"
		end
		local parts = {}
		local allScalar = true
		for _, x in arr do
			if x == nil then
				error("array with a hole cannot be emitted")
			end
			if not isScalar(x) then
				allScalar = false
			end
		end
		if allScalar then
			for _, x in arr do
				table.insert(parts, emit(x, 0, opts))
			end
			local line = "{ " .. table.concat(parts, ", ") .. " }"
			if #line + depth * 4 <= (opts.inlineLimit or 110) then
				return line
			end
		end
		parts = {}
		for _, x in arr do
			table.insert(parts, padIn .. emit(x, depth + 1, opts) .. ",")
		end
		return "{\n" .. table.concat(parts, "\n") .. "\n" .. pad .. "}"
	end
	local obj = v :: { [string]: any }
	local keys = sortedKeys(obj, opts.keyOrder)
	if #keys == 0 then
		return "{}"
	end
	local parts = {}
	local inlineOk = true
	for _, k in keys do
		if not isScalar(obj[k]) then
			inlineOk = false
		end
		table.insert(parts, formatKey(k) .. " = " .. emit(obj[k], depth + 1, opts))
	end
	if inlineOk then
		local line = "{ " .. table.concat(parts, ", ") .. " }"
		if #line + depth * 4 <= (opts.inlineLimit or 110) then
			return line
		end
	end
	local lines = {}
	for _, p in parts do
		table.insert(lines, padIn .. p .. ",")
	end
	return "{\n" .. table.concat(lines, "\n") .. "\n" .. pad .. "}"
end

function LuauEmit.value(v: any, opts: Options?): string
	return emit(v, 0, opts or {})
end

-- A complete ModuleScript source. `header` lines are written as comments after --!strict.
function LuauEmit.module(value: any, header: { string }, opts: Options?): string
	local lines = { "--!strict" }
	for _, h in header do
		table.insert(lines, "-- " .. h)
	end
	table.insert(lines, "return " .. emit(value, 0, opts or {}))
	return table.concat(lines, "\n") .. "\n"
end

-- Splits `records` into chunks whose emitted size stays under `maxBytes` (at least one record each).
function LuauEmit.chunk(records: { any }, maxBytes: number, opts: Options?): { { any } }
	local chunks: { { any } } = {}
	local current: { any } = {}
	local size = 0
	for _, r in records do
		local len = #emit(r, 1, opts or {}) + 3
		if size > 0 and size + len > maxBytes then
			table.insert(chunks, current)
			current = {}
			size = 0
		end
		table.insert(current, r)
		size += len
	end
	if #current > 0 then
		table.insert(chunks, current)
	end
	return chunks
end

return LuauEmit
