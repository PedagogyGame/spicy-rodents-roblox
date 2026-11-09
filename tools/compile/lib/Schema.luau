--!strict
-- A JSON Schema (draft-07 subset) validator in Luau, enough for data/schema/*.schema.json.
-- Supported: type (string or list), properties, required, additionalProperties (bool or schema),
-- items (schema or tuple list), minItems, maxItems, enum, const, minimum, maximum,
-- exclusiveMinimum, exclusiveMaximum, multipleOf, minLength, maxLength, pattern (a regex subset
-- translated to Luau patterns: anchors, classes [..], \d \w \s, * + ?), oneOf, anyOf, allOf, not,
-- $ref to "#/$defs/<name>" or "#/definitions/<name>" in the same document.
-- Annotations ignored here but read by Units: "x-unit" ("u" length, "u/s" speed, "rad", "s", "none").
-- Because @lune/serde decodes JSON null as nil, "null" in a type list means "may be absent"; such a
-- property must not be listed in `required`.
local Schema = {}

export type Error = { path: string, message: string }

local function typeOf(v: any): string
	local t = type(v)
	if t == "nil" then
		return "null"
	elseif t == "boolean" then
		return "boolean"
	elseif t == "number" then
		return "number"
	elseif t == "string" then
		return "string"
	elseif t == "table" then
		local n = #v
		if n == 0 then
			return if next(v) == nil then "empty" else "object"
		end
		local count = 0
		for _ in pairs(v) do
			count += 1
		end
		return if count == n then "array" else "object"
	end
	return t
end
Schema.typeOf = typeOf

local function describe(v: any): string
	local t = typeOf(v)
	if t == "string" then
		local s = v :: string
		if #s > 40 then
			s = string.sub(s, 1, 37) .. "..."
		end
		return string.format("string %q", s)
	elseif t == "number" or t == "boolean" then
		return t .. " " .. tostring(v)
	end
	return t
end

local function matchesType(v: any, want: string): boolean
	local have = typeOf(v)
	if want == "integer" then
		return have == "number" and (v :: number) % 1 == 0
	elseif want == "array" or want == "object" then
		return have == want or have == "empty"
	end
	return have == want
end

-- Translate the regex subset we use in schemas into a Luau pattern.
local function regexToLuau(re: string): string
	local out = string.gsub(re, "\\([dwsDW%.%-%+%*%?%(%)%[%]%^%$])", function(c)
		if c == "d" then
			return "%d"
		elseif c == "w" then
			return "[%w_]"
		elseif c == "s" then
			return "%s"
		elseif c == "D" then
			return "%D"
		elseif c == "W" then
			return "[^%w_]"
		end
		return "%" .. c
	end)
	-- an unescaped "-" outside a class is a literal in regex but a lazy quantifier in Luau
	local buf, inClass, k = {}, false, 1
	while k <= #out do
		local c = string.sub(out, k, k)
		if c == "%" then
			table.insert(buf, string.sub(out, k, k + 1))
			k += 2
		else
			if c == "[" then
				inClass = true
			elseif c == "]" then
				inClass = false
			end
			table.insert(buf, if c == "-" and not inClass then "%-" else c)
			k += 1
		end
	end
	out = table.concat(buf)
	if string.find(out, "[|{}]") then
		error("unsupported regex feature in pattern: " .. re)
	end
	return out
end

-- Expand groups and alternation into plain alternatives: "^(a|b(\\.c)?)$" -> { "^a$", "^b$", "^b\\.c$" }.
-- Handles nested "( | )" groups with an optional trailing "?" (W1: the lot `seat` pattern).
local function expandRegex(re: string): { string }
	local i, n = 1, #re
	while i <= n do
		local c = string.sub(re, i, i)
		if c == "\\" then
			i += 2
		elseif c == "[" then
			local close = string.find(re, "]", i + 1, true) or n
			i = close + 1
		elseif c == "(" then
			local depth, j = 1, i + 1
			local alts: { string } = {}
			local start = j
			while j <= n and depth > 0 do
				local d = string.sub(re, j, j)
				if d == "\\" then
					j += 1
				elseif d == "(" then
					depth += 1
				elseif d == ")" then
					depth -= 1
					if depth == 0 then
						table.insert(alts, string.sub(re, start, j - 1))
					end
				elseif d == "|" and depth == 1 then
					table.insert(alts, string.sub(re, start, j - 1))
					start = j + 1
				end
				j += 1
			end
			local prefix, rest = string.sub(re, 1, i - 1), string.sub(re, j)
			if string.sub(rest, 1, 1) == "?" then
				rest = string.sub(rest, 2)
				table.insert(alts, "")
			end
			local out: { string } = {}
			for _, a in alts do
				for _, e in expandRegex(prefix .. a .. rest) do
					table.insert(out, e)
				end
			end
			return out
		else
			i += 1
		end
	end
	return { re }
end

local function matchesPattern(str: string, re: string): boolean
	for _, alt in expandRegex(re) do
		if string.find(str, regexToLuau(alt)) then
			return true
		end
	end
	return false
end

local function resolveRef(ref: string, root: any): any
	local name = string.match(ref, "^#/%$defs/([%w_%-]+)$") or string.match(ref, "^#/definitions/([%w_%-]+)$")
	if not name then
		error("unsupported $ref: " .. ref)
	end
	local defs = (root["$defs"] or root["definitions"]) :: { [string]: any }?
	local s = defs and defs[name]
	if not s then
		error("unresolved $ref: " .. ref)
	end
	return s
end
Schema.resolveRef = resolveRef

local validate: (schema: any, value: any, path: string, root: any, errors: { Error }) -> ()

local function push(errors: { Error }, path: string, message: string)
	table.insert(errors, { path = path, message = message })
end

local function joinTypes(t: any): string
	if type(t) == "table" then
		return table.concat(t :: { string }, "|")
	end
	return tostring(t)
end

validate = function(schema: any, value: any, path: string, root: any, errors: { Error })
	if schema == true then
		return
	elseif schema == false then
		push(errors, path, "no value allowed here")
		return
	end
	if type(schema) ~= "table" then
		error("schema node must be a table or boolean at " .. path)
	end
	local s = schema :: { [string]: any }
	if s["$ref"] then
		local target = resolveRef(s["$ref"], root)
		validate(target, value, path, root, errors)
		-- siblings of $ref are ignored (draft-07 semantics)
		return
	end
	-- type
	local want = s.type
	if want ~= nil then
		local ok = false
		if type(want) == "table" then
			for _, w in want :: { string } do
				if matchesType(value, w) then
					ok = true
					break
				end
			end
		else
			ok = matchesType(value, want :: string)
		end
		if not ok then
			push(errors, path, string.format("expected %s, got %s", joinTypes(want), describe(value)))
			return
		end
	end
	if value == nil then
		return
	end
	if s.enum then
		local found = false
		for _, e in s.enum :: { any } do
			if e == value then
				found = true
				break
			end
		end
		if not found then
			local list = {}
			for _, e in s.enum :: { any } do
				table.insert(list, tostring(e))
			end
			push(errors, path, string.format("value %s is not one of [%s]", describe(value), table.concat(list, ", ")))
		end
	end
	if s.const ~= nil and s.const ~= value then
		push(errors, path, string.format("expected constant %s, got %s", tostring(s.const), describe(value)))
	end
	local tv = type(value)
	if tv == "number" then
		local n = value :: number
		if n ~= n or n == math.huge or n == -math.huge then
			push(errors, path, "number must be finite")
		end
		if s.minimum and n < s.minimum then
			push(errors, path, string.format("%s is below minimum %s", tostring(n), tostring(s.minimum)))
		end
		if s.maximum and n > s.maximum then
			push(errors, path, string.format("%s is above maximum %s", tostring(n), tostring(s.maximum)))
		end
		if s.exclusiveMinimum and n <= s.exclusiveMinimum then
			push(errors, path, string.format("%s must be greater than %s", tostring(n), tostring(s.exclusiveMinimum)))
		end
		if s.exclusiveMaximum and n >= s.exclusiveMaximum then
			push(errors, path, string.format("%s must be less than %s", tostring(n), tostring(s.exclusiveMaximum)))
		end
		if s.multipleOf and math.abs(n / s.multipleOf - math.round(n / s.multipleOf)) > 1e-9 then
			push(errors, path, string.format("%s is not a multiple of %s", tostring(n), tostring(s.multipleOf)))
		end
	elseif tv == "string" then
		local str = value :: string
		if s.minLength and #str < s.minLength then
			push(errors, path, string.format("string shorter than %d", s.minLength))
		end
		if s.maxLength and #str > s.maxLength then
			push(errors, path, string.format("string longer than %d", s.maxLength))
		end
		if s.pattern and not matchesPattern(str, s.pattern) then
			push(errors, path, string.format("%s does not match pattern %s", describe(value), s.pattern))
		end
	elseif tv == "table" then
		local kind = typeOf(value)
		local asArray = kind == "array"
			or (kind == "empty" and (s.items ~= nil or s.minItems ~= nil or s.type == "array"))
		if asArray then
			local arr = value :: { any }
			if s.minItems and #arr < s.minItems then
				push(errors, path, string.format("array has %d items, minimum %d", #arr, s.minItems))
			end
			if s.maxItems and #arr > s.maxItems then
				push(errors, path, string.format("array has %d items, maximum %d", #arr, s.maxItems))
			end
			if s.items ~= nil then
				if typeOf(s.items) == "array" then
					local tuple = s.items :: { any }
					for i, sub in tuple do
						if i <= #arr then
							validate(sub, arr[i], path .. "[" .. i .. "]", root, errors)
						elseif s.minItems == nil or i <= s.minItems then
							push(errors, path, string.format("tuple item %d is missing", i))
						end
					end
					if #arr > #tuple and s.additionalItems == false then
						push(errors, path, string.format("tuple has %d extra item(s)", #arr - #tuple))
					end
				else
					for i, item in arr do
						validate(s.items, item, path .. "[" .. i .. "]", root, errors)
					end
				end
			end
			if s.uniqueItems then
				local seen: { [any]: boolean } = {}
				for i, item in arr do
					local key = if type(item) == "table" then nil else item
					if key ~= nil then
						if seen[key] then
							push(errors, path .. "[" .. i .. "]", "duplicate item " .. describe(item))
						end
						seen[key] = true
					end
				end
			end
		else
			local obj = value :: { [string]: any }
			local props = s.properties :: { [string]: any }?
			if s.required then
				for _, req in s.required :: { string } do
					if obj[req] == nil then
						push(errors, path, string.format("missing required property %q", req))
					end
				end
			end
			for k, v in pairs(obj) do
				local sub = props and props[k]
				local childPath = path .. "." .. tostring(k)
				if sub ~= nil then
					validate(sub, v, childPath, root, errors)
				elseif s.additionalProperties == false then
					push(errors, childPath, "unexpected property")
				elseif type(s.additionalProperties) == "table" then
					validate(s.additionalProperties, v, childPath, root, errors)
				end
			end
			if s.minProperties then
				local count = 0
				for _ in pairs(obj) do
					count += 1
				end
				if count < s.minProperties then
					push(errors, path, string.format("object has %d properties, minimum %d", count, s.minProperties))
				end
			end
		end
	end
	if s.allOf then
		for _, sub in s.allOf :: { any } do
			validate(sub, value, path, root, errors)
		end
	end
	if s.anyOf then
		local ok = false
		local branchErrors = {}
		for i, sub in s.anyOf :: { any } do
			local errs: { Error } = {}
			validate(sub, value, path, root, errs)
			if #errs == 0 then
				ok = true
				break
			end
			table.insert(branchErrors, string.format("[%d] %s", i, errs[1].message))
		end
		if not ok then
			push(errors, path, "matches none of anyOf: " .. table.concat(branchErrors, "; "))
		end
	end
	if s.oneOf then
		local matches = 0
		local branchErrors = {}
		for i, sub in s.oneOf :: { any } do
			local errs: { Error } = {}
			validate(sub, value, path, root, errs)
			if #errs == 0 then
				matches += 1
			else
				table.insert(branchErrors, string.format("[%d] %s: %s", i, errs[1].path, errs[1].message))
			end
		end
		if matches ~= 1 then
			push(
				errors,
				path,
				string.format(
					"matches %d of oneOf branches (need exactly 1): %s",
					matches,
					table.concat(branchErrors, "; ")
				)
			)
		end
	end
	if s["not"] then
		local errs: { Error } = {}
		validate(s["not"], value, path, root, errs)
		if #errs == 0 then
			push(errors, path, "value matches a forbidden schema (not)")
		end
	end
end

-- Returns the list of errors (empty when valid).
function Schema.validate(schema: any, value: any, rootName: string?): { Error }
	local errors: { Error } = {}
	validate(schema, value, rootName or "$", schema, errors)
	return errors
end

-- Index of the first oneOf/anyOf branch that validates, or nil.
function Schema.matchingBranch(branches: { any }, value: any, root: any): number?
	for i, sub in branches do
		local errs: { Error } = {}
		validate(sub, value, "$", root, errs)
		if #errs == 0 then
			return i
		end
	end
	return nil
end

function Schema.formatErrors(file: string, errors: { Error }, limit: number?): string
	local lines = {}
	local max = limit or 30
	for i, e in errors do
		if i > max then
			table.insert(lines, string.format("  ... and %d more", #errors - max))
			break
		end
		table.insert(lines, string.format("  %s %s: %s", file, e.path, e.message))
	end
	return table.concat(lines, "\n")
end

return Schema
