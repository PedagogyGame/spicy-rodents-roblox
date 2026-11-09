--!strict
-- ServerScriptService.Server.Persistence.Serializer
-- The profile serialiser (BUILD_PLAN §4.4 #6b, §3.20, D26): canonical JSON (sorted keys, integers
-- printed exactly, other numbers with 17 significant digits) inside a versioned envelope
-- { format = "spicy-profile", v = VERSION, record = ... }. Refuses what a DataStore would mangle or
-- that signals a bug: NaN or infinite numbers, functions, sparse or mixed arrays, non-string map keys.
-- Pure Luau (no HttpService), so Lune tests the exact bytes the engine stores; decode is the inverse.
-- Interface: VERSION; encode(value) -> string; decode(text) -> any; pack(record) -> string;
--            unpack(text) -> (record?, err?)

local Serializer = {}

Serializer.VERSION = 1
Serializer.FORMAT = "spicy-profile"

local ESC: { [string]: string } =
	{ ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function encodeString(s: string): string
	return '"'
		.. string.gsub(s, '[%c"\\]', function(c: string): string
			return ESC[c] or string.format("\\u%04x", string.byte(c))
		end)
		.. '"'
end

local function encodeNumber(v: number): string
	if v ~= v or v == math.huge or v == -math.huge then
		error("Serializer: non-finite number")
	end
	if math.floor(v) == v and math.abs(v) < 2 ^ 53 then
		return string.format("%d", v)
	end
	return string.format("%.17g", v)
end

local function encodeValue(v: any, out: { string }, depth: number)
	if depth > 32 then
		error("Serializer: too deep")
	end
	local t = type(v)
	if t == "nil" then
		table.insert(out, "null")
	elseif t == "boolean" then
		table.insert(out, if v then "true" else "false")
	elseif t == "number" then
		table.insert(out, encodeNumber(v))
	elseif t == "string" then
		table.insert(out, encodeString(v))
	elseif t == "table" then
		local n = #v
		local count, stringKeys = 0, 0
		for k in v do
			count += 1
			if type(k) == "string" then
				stringKeys += 1
			end
		end
		if count == 0 then
			table.insert(out, "{}") -- empty tables are maps (profile maps start empty)
		elseif n == count then
			table.insert(out, "[")
			for i = 1, n do
				if i > 1 then
					table.insert(out, ",")
				end
				encodeValue(v[i], out, depth + 1)
			end
			table.insert(out, "]")
		elseif stringKeys == count then
			local keys: { string } = {}
			for k in v do
				table.insert(keys, k)
			end
			table.sort(keys)
			table.insert(out, "{")
			for i, k in keys do
				if i > 1 then
					table.insert(out, ",")
				end
				table.insert(out, encodeString(k))
				table.insert(out, ":")
				encodeValue(v[k], out, depth + 1)
			end
			table.insert(out, "}")
		else
			error("Serializer: mixed or sparse table")
		end
	else
		error(`Serializer: cannot store a {t}`)
	end
end

function Serializer.encode(value: any): string
	local out: { string } = {}
	encodeValue(value, out, 0)
	return table.concat(out)
end

-- Recursive-descent JSON decoder (objects, arrays, strings with \u escapes, numbers, literals).
function Serializer.decode(text: string): any
	local pos = 1
	local function fail(msg: string): never
		error(`Serializer.decode: {msg} at {pos}`)
	end
	local function skip()
		pos = string.find(text, "[^ \t\r\n]", pos) or #text + 1
	end
	local parseValue: () -> any
	local function parseString(): string
		pos += 1
		local parts: { string } = {}
		while true do
			local c = string.sub(text, pos, pos)
			if c == "" then
				fail("unterminated string")
			elseif c == '"' then
				pos += 1
				return table.concat(parts)
			elseif c == "\\" then
				local e = string.sub(text, pos + 1, pos + 1)
				local map =
					{ b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
				if map[e] then
					table.insert(parts, map[e])
					pos += 2
				elseif e == "u" then
					local hex = string.sub(text, pos + 2, pos + 5)
					local code = tonumber(hex, 16)
					if not code then
						fail("bad \\u escape")
					end
					table.insert(parts, utf8.char(code :: number))
					pos += 6
				else
					fail("bad escape")
				end
			else
				local stop = string.find(text, '["\\]', pos) or #text + 1
				table.insert(parts, string.sub(text, pos, stop - 1))
				pos = stop
			end
		end
	end
	parseValue = function(): any
		skip()
		local c = string.sub(text, pos, pos)
		if c == "{" then
			pos += 1
			local obj = {}
			skip()
			if string.sub(text, pos, pos) == "}" then
				pos += 1
				return obj
			end
			while true do
				skip()
				if string.sub(text, pos, pos) ~= '"' then
					fail("expected key")
				end
				local k = parseString()
				skip()
				if string.sub(text, pos, pos) ~= ":" then
					fail("expected :")
				end
				pos += 1
				obj[k] = parseValue()
				skip()
				local d = string.sub(text, pos, pos)
				pos += 1
				if d == "}" then
					return obj
				elseif d ~= "," then
					fail("expected , or }")
				end
			end
		elseif c == "[" then
			pos += 1
			local arr = {}
			skip()
			if string.sub(text, pos, pos) == "]" then
				pos += 1
				return arr
			end
			while true do
				table.insert(arr, parseValue())
				skip()
				local d = string.sub(text, pos, pos)
				pos += 1
				if d == "]" then
					return arr
				elseif d ~= "," then
					fail("expected , or ]")
				end
			end
		elseif c == '"' then
			return parseString()
		elseif string.sub(text, pos, pos + 3) == "true" then
			pos += 4
			return true
		elseif string.sub(text, pos, pos + 4) == "false" then
			pos += 5
			return false
		elseif string.sub(text, pos, pos + 3) == "null" then
			pos += 4
			return nil
		else
			local s, e = string.find(text, "^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
			if not s then
				fail("unexpected character")
			end
			local v = tonumber(string.sub(text, s :: number, e :: number))
			if v == nil then
				fail("bad number")
			end
			pos = (e :: number) + 1
			return v
		end
	end
	local v = parseValue()
	skip()
	if pos <= #text then
		fail("trailing data")
	end
	return v
end

function Serializer.pack(record: any): string
	return Serializer.encode({ format = Serializer.FORMAT, v = Serializer.VERSION, record = record })
end

function Serializer.unpack(text: string): (any, string?)
	local ok, env = pcall(Serializer.decode, text)
	if not ok then
		return nil, `corrupt: {env}`
	end
	if type(env) ~= "table" or env.format ~= Serializer.FORMAT then
		return nil, "not a profile envelope"
	end
	if type(env.v) ~= "number" or env.v > Serializer.VERSION then
		return nil, `envelope v{tostring(env.v)} is newer than this server (v{Serializer.VERSION})`
	end
	return env.record
end

return Serializer
