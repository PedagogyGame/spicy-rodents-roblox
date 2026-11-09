--!strict
-- Lune place test (BUILD_PLAN §6.4). Opens a built place with @lune/roblox and asserts:
--   * every node of the Rojo project file exists in the place with the right class, and every
--     `$properties` value matches (booleans, numbers, strings and enums by name);
--   * every file under a `$path` directory became the expected instance (ModuleScript, Script,
--     LocalScript, Folder, or a named instance for .model.json / .rbxm / .rbxmx);
--   * no SurfaceAppearance, PartOperation (union) or BaseWrap exists anywhere in the place, so
--     the place stays publishable through Open Cloud;
--   * ServerStorage.EngineTests exists only when the project maps it (ci.project.json).
-- Usage: lune run tests/place/check_place.luau <place.rbxl|rbxlx> <project.json>

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local placePath = process.args[1] or "build/test.rbxl"
local projectPath = process.args[2] or "default.project.json"

local failures: { string } = {}
local checks = 0

local function check(cond: boolean, msg: string)
	checks += 1
	if not cond then
		table.insert(failures, msg)
	end
end

local contents = fs.readFile(placePath)
local game = roblox.deserializePlace(contents)
local project = serde.decode("json", fs.readFile(projectPath))

local function childByName(parent: any, name: string): any
	local ok, inst = pcall(function()
		return parent:FindFirstChild(name)
	end)
	if ok then
		return inst
	end
	return nil
end

local function instanceAt(path: { string }): any
	local current: any = game
	for i, name in path do
		if i == 1 then
			local okService, service = pcall(function()
				return game:GetService(name)
			end)
			current = if okService then service else childByName(game, name)
		else
			current = childByName(current, name)
		end
		if current == nil then
			return nil
		end
	end
	return current
end

local function propertyMatches(inst: any, name: string, expected: any): (boolean, string)
	local ok, actual = pcall(function()
		return (inst :: any)[name]
	end)
	if not ok then
		return false, `cannot read {name}: {tostring(actual)}`
	end
	local actualType = typeof(actual)
	if actualType == "EnumItem" then
		return tostring((actual :: any).Name) == tostring(expected),
			`{name}: expected {expected}, got {tostring(actual)}`
	end
	if type(expected) == "number" and type(actual) == "number" then
		return math.abs(actual - expected) < 1e-6, `{name}: expected {expected}, got {actual}`
	end
	return actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`
end

-- Files on disk -> expected instance (name, className or nil when any class is fine).
local function expectedFromFile(entry: string): (string?, string?)
	if string.find(entry, "%.spec%.luau$") then
		return nil, nil
	end
	if string.find(entry, "%.server%.luau$") then
		return string.sub(entry, 1, -13), "Script"
	end
	if string.find(entry, "%.client%.luau$") then
		return string.sub(entry, 1, -13), "LocalScript"
	end
	if string.find(entry, "%.luau$") then
		return string.sub(entry, 1, -6), "ModuleScript"
	end
	if string.find(entry, "%.model%.json$") then
		return string.sub(entry, 1, -12), nil
	end
	if string.find(entry, "%.rbxmx?$") then
		return string.gsub(entry, "%.rbxmx?$", ""), nil
	end
	return nil, nil
end

local function checkDirectory(dir: string, inst: any, instPath: string)
	for _, entry in fs.readDir(dir) do
		local full = `{dir}/{entry}`
		if fs.isDir(full) then
			local child = childByName(inst, entry)
			check(child ~= nil, `{instPath}.{entry}: missing (from directory {full})`)
			if child then
				local hasInit = fs.isFile(`{full}/init.luau`)
				local className = tostring((child :: any).ClassName)
				if hasInit then
					check(
						className == "ModuleScript",
						`{instPath}.{entry}: expected ModuleScript (init.luau), got {className}`
					)
				else
					check(className == "Folder", `{instPath}.{entry}: expected Folder, got {className}`)
				end
				checkDirectory(full, child, `{instPath}.{entry}`)
			end
		elseif entry ~= "init.luau" then
			local name, className = expectedFromFile(entry)
			if name then
				local child = childByName(inst, name)
				check(child ~= nil, `{instPath}.{name}: missing (from file {full})`)
				if child and className then
					local actualClass = tostring((child :: any).ClassName)
					check(actualClass == className, `{instPath}.{name}: expected {className}, got {actualClass}`)
				end
			end
		end
	end
end

local function resolvePath(spec: any): (string?, boolean)
	if type(spec) == "string" then
		return spec, false
	end
	if type(spec) == "table" and type(spec.optional) == "string" then
		return spec.optional, true
	end
	return nil, false
end

local function walkNode(node: any, path: { string })
	local instPath = table.concat(path, ".")
	local inst = instanceAt(path)
	local pathSpec, optional = resolvePath(node["$path"])
	if pathSpec and optional and not (fs.isDir(pathSpec) or fs.isFile(pathSpec)) then
		-- Optional path that is absent: the instance may legitimately be missing.
		return
	end
	check(inst ~= nil, `{instPath}: missing`)
	if inst == nil then
		return
	end
	if node["$className"] and #path > 0 then
		local actualClass = tostring((inst :: any).ClassName)
		check(actualClass == node["$className"], `{instPath}: expected {node["$className"]}, got {actualClass}`)
	end
	if type(node["$properties"]) == "table" then
		for propName, expected in node["$properties"] do
			local ok, msg = propertyMatches(inst, propName, expected)
			check(ok, `{instPath}.{msg}`)
		end
	end
	if pathSpec and fs.isDir(pathSpec) then
		checkDirectory(pathSpec, inst, instPath)
	end
	for key, child in node do
		if string.sub(key, 1, 1) ~= "$" and type(child) == "table" then
			local childPath = table.clone(path)
			table.insert(childPath, key)
			walkNode(child, childPath)
		end
	end
end

for key, child in project.tree do
	if string.sub(key, 1, 1) ~= "$" and type(child) == "table" then
		walkNode(child, { key })
	end
end

-- Forbidden classes (keeps Open Cloud publishing valid, §6.4) and stray art captures.
local forbidden = {
	SurfaceAppearance = 0,
	UnionOperation = 0,
	NegateOperation = 0,
	IntersectOperation = 0,
	WrapLayer = 0,
	WrapTarget = 0,
}
local total = 0
for _, inst in game:GetDescendants() do
	total += 1
	local className = tostring((inst :: any).ClassName)
	if forbidden[className] ~= nil then
		forbidden[className] += 1
	end
end
for className, count in forbidden do
	check(count == 0, `{count} {className} instance(s) in the place`)
end

-- EngineTests only in the CI project.
local engineTests = instanceAt({ "ServerStorage", "EngineTests" })
local projectHasEngineTests = project.tree.ServerStorage ~= nil and project.tree.ServerStorage.EngineTests ~= nil
check(
	(engineTests ~= nil) == projectHasEngineTests,
	`ServerStorage.EngineTests presence ({engineTests ~= nil}) does not match project ({projectHasEngineTests})`
)

print(`place test: {placePath} against {projectPath}: {total} instances, {checks} checks, {#failures} failure(s)`)
for _, f in failures do
	print("  FAIL " .. f)
end
if #failures > 0 then
	process.exit(1)
end
