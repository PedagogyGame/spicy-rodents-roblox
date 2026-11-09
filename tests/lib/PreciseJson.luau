--!strict
-- Lune's serde JSON decoder is not round-trip exact for every double (it can be off by one ulp,
-- e.g. 2.0752915949449546 decodes as 2.0752915949449542). Golden vectors from V8 must be read back
-- bit-exactly, so this decoder quotes every number literal with a sentinel before decoding and then
-- converts it with Luau's correctly rounded tonumber.
local serde = require("@lune/serde")

local PreciseJson = {}

local SENTINEL = "#~n:"

local function restore(value: any): any
	if type(value) == "string" then
		if string.sub(value, 1, #SENTINEL) == SENTINEL then
			return tonumber(string.sub(value, #SENTINEL + 1))
		end
		return value
	elseif type(value) == "table" then
		for k, v in value do
			value[k] = restore(v)
		end
	end
	return value
end

function PreciseJson.decode(text: string): any
	-- Quote number literals that follow a structural character ([ , :), outside strings.
	local out = table.create(#text // 64)
	local i, n = 1, #text
	local inString = false
	local prevStructural = true
	while i <= n do
		local c = string.sub(text, i, i)
		if inString then
			if c == "\\" then
				table.insert(out, string.sub(text, i, i + 1))
				i += 2
				continue
			elseif c == '"' then
				inString = false
			end
			table.insert(out, c)
			i += 1
		elseif c == '"' then
			inString = true
			prevStructural = false
			table.insert(out, c)
			i += 1
		elseif prevStructural and string.match(c, "[%-%d]") then
			local s, e = string.find(text, "^%-?%d[%d%.eE%+%-]*", i)
			assert(s and e, "bad number")
			table.insert(out, '"' .. SENTINEL .. string.sub(text, s, e) .. '"')
			i = e + 1
			prevStructural = false
		else
			if string.match(c, "[%[,:]") then
				prevStructural = true
			elseif not string.match(c, "%s") then
				prevStructural = false
			end
			table.insert(out, c)
			i += 1
		end
	end
	return restore(serde.decode("json", table.concat(out)))
end

return PreciseJson
