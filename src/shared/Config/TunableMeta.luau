--!strict
-- ReplicatedStorage.Shared.Config.TunableMeta
-- Unit and range metadata for Tunables leaves (BUILD_PLAN §3.8). Units in "u" (HTML units) are
-- authored as v5.4 wrote them and converted to studs on read through Config/Units, the single
-- boundary (D21); "st" is already studs. A leaf may name an explicit range; otherwise an override
-- must keep the leaf's type and sign. Pure.
-- Interface: isLength(unit) -> boolean; toStuds(value, unit) -> value; RANGES; validate(path, leaf, value) -> (ok, err?)

local Units = require("./Units")

local TunableMeta = {}

-- Units whose values are lengths (or lengths per second / per second squared) in HTML units.
TunableMeta.LENGTH_UNITS = { u = true, ["u/s"] = true, ["u/s2"] = true } :: { [string]: boolean }

-- Explicit live-tuning ranges (authored units). Leaves not listed keep type and sign.
TunableMeta.RANGES = {
	["clock.realSecondsPerDay"] = { 6, 3600 },
	["squirrel.walk"] = { 0.5, 40 },
	["squirrel.sprint"] = { 0.5, 60 },
	["rodent.maxHealth"] = { 1, 1000 },
	["alert.kickMult"] = { 1, 1.82 }, -- D33: must stay below 1.82
	["ai.budgetMs"] = { 0.5, 16 },
} :: { [string]: { number } }

function TunableMeta.isLength(unit: string?): boolean
	return unit ~= nil and TunableMeta.LENGTH_UNITS[unit] == true
end

-- Converts a leaf value (number or array of numbers) to studs when its unit is a length.
function TunableMeta.toStuds(value: any, unit: string?): any
	if not TunableMeta.isLength(unit) then
		return value
	end
	if type(value) == "number" then
		return Units.st(value)
	elseif type(value) == "table" then
		local out = {}
		for k, v in value do
			out[k] = if type(v) == "number" then Units.st(v) else v
		end
		return out
	end
	return value
end

local function finite(v: number): boolean
	return v == v and v ~= math.huge and v ~= -math.huge
end

function TunableMeta.validate(path: string, leaf: { v: any }, value: any): (boolean, string?)
	local current = leaf.v
	if type(value) ~= type(current) then
		return false, `{path}: expected {type(current)}, got {type(value)}`
	end
	if type(value) == "number" then
		if not finite(value) then
			return false, `{path}: not finite`
		end
		local range = TunableMeta.RANGES[path]
		if range then
			if value < range[1] or value > range[2] then
				return false, `{path}: {value} outside [{range[1]}, {range[2]}]`
			end
		elseif (current >= 0) ~= (value >= 0) then
			return false, `{path}: sign change not allowed`
		end
	elseif type(value) == "table" then
		for k, v in current do
			if type(value[k]) ~= type(v) then
				return false, `{path}.{tostring(k)}: shape mismatch`
			end
		end
	end
	return true
end

return TunableMeta
