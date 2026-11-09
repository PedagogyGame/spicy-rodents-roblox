--!strict
-- Deterministic JSON reading and writing for the compiler.
-- Decoding uses @lune/serde (JSON null becomes nil: a null property is the same as an absent one;
-- arrays never contain null in our data). Encoding sorts keys (with an optional preferred prefix
-- order), prints arrays of scalars on one line and uses the shortest round-trip number form.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Json = {}

-- Marker metatable so an empty table we build can still be written as [] instead of {}.
local ARRAY_MT = { __jsonArray = true }
Json.ARRAY_MT = ARRAY_MT

function Json.array(t: { any }?): { any }
	return setmetatable(t or {}, ARRAY_MT) :: any
end

function Json.isArray(t: any): boolean
	if type(t) ~= "table" then
		return false
	end
	if getmetatable(t) == ARRAY_MT then
		return true
	end
	local n = #t
	if n == 0 then
		return false
	end
	local count = 0
	for _ in pairs(t) do
		count += 1
	end
	return count == n
end

function Json.isEmptyTable(t: any): boolean
	return type(t) == "table" and next(t) == nil
end

function Json.decodeFile(path: string): any
	local text = fs.readFile(path)
	return serde.decode("json", text)
end

function Json.formatNumber(x: number): string
	if x ~= x or x == math.huge or x == -math.huge then
		error("non-finite number cannot be written to JSON")
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

local ESCAPES =
	{ ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["\b"] = "\\b", ["\f"] = "\\f" }
function Json.formatString(s: string): string
	local out = string.gsub(s, '[%c"\\]', function(c)
		local e = ESCAPES[c]
		if e then
			return e
		end
		return string.format("\\u%04x", string.byte(c))
	end)
	return '"' .. out .. '"'
end

local function isScalar(v: any): boolean
	local t = type(v)
	return t == "number" or t == "string" or t == "boolean"
end

local function sortedKeys(t: { [string]: any }, keyOrder: { string }?): { string }
	local keys = {}
	for k in pairs(t) do
		table.insert(keys, tostring(k))
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

type EncodeOptions = { keyOrder: { string }?, indent: string? }

local function encodeValue(v: any, depth: number, opts: EncodeOptions): string
	local indent = opts.indent or "  "
	local pad = string.rep(indent, depth)
	local padIn = string.rep(indent, depth + 1)
	local tv = type(v)
	if tv == "nil" then
		return "null"
	elseif tv == "boolean" then
		return v and "true" or "false"
	elseif tv == "number" then
		return Json.formatNumber(v)
	elseif tv == "string" then
		return Json.formatString(v)
	elseif tv == "table" then
		if Json.isArray(v) or (Json.isEmptyTable(v) and getmetatable(v) == ARRAY_MT) then
			local arr = v :: { any }
			if #arr == 0 then
				return "[]"
			end
			local allScalar = true
			for _, x in arr do
				if not isScalar(x) then
					allScalar = false
					break
				end
			end
			local parts = {}
			if allScalar then
				for _, x in arr do
					table.insert(parts, encodeValue(x, 0, opts))
				end
				return "[" .. table.concat(parts, ", ") .. "]"
			end
			for _, x in arr do
				table.insert(parts, padIn .. encodeValue(x, depth + 1, opts))
			end
			return "[\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "]"
		end
		local obj = v :: { [string]: any }
		local keys = sortedKeys(obj, opts.keyOrder)
		if #keys == 0 then
			return "{}"
		end
		local parts = {}
		for _, k in keys do
			table.insert(parts, padIn .. Json.formatString(k) .. ": " .. encodeValue(obj[k], depth + 1, opts))
		end
		return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
	end
	error("cannot encode value of type " .. tv)
end

function Json.encode(value: any, opts: EncodeOptions?): string
	return encodeValue(value, 0, opts or {}) .. "\n"
end

function Json.writeFile(path: string, value: any, opts: EncodeOptions?)
	fs.writeFile(path, Json.encode(value, opts))
end

return Json
