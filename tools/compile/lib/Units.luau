--!strict
-- Unit conversion at the single boundary (BUILD_PLAN 3.1): authored data is in HTML units,
-- generated data is in studs (x 2.5). Which numbers are lengths or speeds is declared in the
-- schemas with "x-unit": "u" (length) or "u/s" (speed); "rad", "s", "none" and absent mean
-- "leave alone". A unit set on an array node applies to the numbers inside it.
--
-- The multiplication is done on the shortest decimal representation of the number
-- ("18.04" x 25 = "451" shifted one place = 45.1) instead of in binary, so authored values with
-- few decimals come out as the exact decimal product (45.1, not 45.099999999999994), and
-- full-precision harvested doubles keep 17 significant digits.
local Schema = require("./Schema")

local Units = {}

Units.STUDS_PER_UNIT = 2.5

local function shortest(x: number): string
	for _, fmt in { "%.15g", "%.16g", "%.17g" } do
		local s = string.format(fmt, x)
		if tonumber(s) == x then
			return s
		end
	end
	return string.format("%.17g", x)
end

-- digits (string of decimal digits, no sign) multiplied by 25, as a digit string
local function mul25(digits: string): string
	local carry = 0
	local out = {}
	for i = #digits, 1, -1 do
		local d = tonumber(string.sub(digits, i, i)) :: number
		local p = d * 25 + carry
		table.insert(out, 1, tostring(p % 10))
		carry = math.floor(p / 10)
	end
	while carry > 0 do
		table.insert(out, 1, tostring(carry % 10))
		carry = math.floor(carry / 10)
	end
	return table.concat(out)
end

function Units.toStuds(x: number): number
	if x ~= x or x == math.huge or x == -math.huge then
		error("cannot convert a non-finite number to studs")
	end
	if x == 0 then
		return 0
	end
	local s = shortest(x)
	local sign = ""
	if string.sub(s, 1, 1) == "-" then
		sign = "-"
		s = string.sub(s, 2)
	end
	local mantissa, exp = string.match(s, "^([%d%.]+)e([%+%-]?%d+)$")
	local e = 0
	if mantissa then
		s = mantissa :: string
		e = tonumber(exp) :: number
	end
	local intPart, fracPart = string.match(s, "^(%d*)%.?(%d*)$")
	if not intPart then
		error("unexpected number format " .. s)
	end
	local digits = (intPart :: string) .. (fracPart :: string)
	local scale = e - #(fracPart :: string) - 1 -- x = digits * 10^(scale) * 10 ; times 2.5 = digits*25 * 10^(scale)
	local product = mul25(digits)
	local text = sign .. product .. "e" .. tostring(scale)
	local result = tonumber(text)
	if result == nil then
		error("conversion failed for " .. s)
	end
	return result
end

local CONVERT_UNITS: { [string]: boolean } = { ["u"] = true, ["u/s"] = true, ["u/s2"] = true }

-- Deep-copies `value`, converting numbers that the schema marks as lengths or speeds.
local function convert(value: any, schema: any, root: any, inherited: string?): any
	if type(schema) ~= "table" then
		return value
	end
	local s = schema :: { [string]: any }
	if s["$ref"] then
		return convert(value, Schema.resolveRef(s["$ref"], root), root, inherited)
	end
	local unit: string? = s["x-unit"] or inherited
	local tv = type(value)
	if tv == "number" then
		if unit and CONVERT_UNITS[unit] then
			return Units.toStuds(value :: number)
		end
		return value
	elseif tv ~= "table" then
		return value
	end
	-- composition: pick the branch that validates
	local branches = (s.oneOf or s.anyOf) :: { any }?
	if branches then
		local idx = Schema.matchingBranch(branches, value, root)
		if idx then
			return convert(value, branches[idx], root, unit)
		end
	end
	if s.allOf then
		local out = value
		for _, sub in s.allOf :: { any } do
			out = convert(out, sub, root, unit)
		end
		return out
	end
	local kind = Schema.typeOf(value)
	if kind == "array" or (kind == "empty" and s.items ~= nil) then
		local arr = value :: { any }
		local out = table.create(#arr)
		for i, item in arr do
			local sub = s.items
			if Schema.typeOf(sub) == "array" then
				sub = (sub :: { any })[i]
			end
			out[i] = convert(item, sub or {}, root, unit)
		end
		return setmetatable(out, getmetatable(value :: any))
	end
	local obj = value :: { [string]: any }
	local props = s.properties :: { [string]: any }?
	local out = {}
	for k, v in pairs(obj) do
		local sub = props and props[k]
		if sub == nil and type(s.additionalProperties) == "table" then
			sub = s.additionalProperties
		end
		-- a unit set on an object node is NOT inherited by its properties (too easy to convert
		-- an unrelated number); only arrays inherit
		out[k] = if sub ~= nil then convert(v, sub, root, nil) else v
	end
	return out
end

function Units.convert(value: any, schema: any): any
	return convert(value, schema, schema, nil)
end

return Units
