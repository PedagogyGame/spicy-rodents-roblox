--!strict
-- Smoke test for every skeleton area (BUILD_PLAN §4.3 item 1): each ModuleScript under src/
-- requires under Lune without side effects and returns a table. Server, client and worldgen
-- stubs are pure today; once a module needs the engine it is listed in ENGINE_ONLY below and
-- covered by tests/engine/BootSmoke instead.
local fs = require("@lune/fs")

local ENGINE_ONLY: { [string]: boolean } = {}

local AREAS = {
	{ name = "shared", dir = "src/shared", minModules = 40 },
	{ name = "server", dir = "src/server", minModules = 30 },
	{ name = "worldgen", dir = "src/worldgen", minModules = 5 },
	{ name = "client", dir = "src/client", minModules = 10 },
}

local function collect(dir: string, out: { string })
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			collect(path, out)
		elseif
			string.sub(entry, -5) == ".luau"
			and not string.find(entry, "%.server%.luau$")
			and not string.find(entry, "%.client%.luau$")
			and not string.find(entry, "%.spec%.luau$")
		then
			table.insert(out, path)
		end
	end
end

return function(t)
	for _, area in AREAS do
		local files: { string } = {}
		collect(area.dir, files)
		table.sort(files)

		t.test(`{area.name}: at least {area.minModules} modules exist`, function()
			t.truthy(#files >= area.minModules, `{#files} found`)
		end)

		t.test(`{area.name}: every module has --!strict and a header comment`, function()
			for _, file in files do
				local src = fs.readFile(file)
				t.truthy(string.sub(src, 1, 9) == "--!strict", `{file} lacks --!strict`)
				t.truthy(string.find(src, "\n%-%- ") ~= nil, `{file} lacks a header comment`)
			end
		end)

		t.test(`{area.name}: every module requires under Lune and returns a table`, function()
			for _, file in files do
				if ENGINE_ONLY[file] then
					continue
				end
				-- Strip ".luau"; an init.luau is required by its directory.
				local modulePath = "../../" .. string.sub(file, 1, -6)
				if string.sub(modulePath, -5) == "/init" then
					modulePath = string.sub(modulePath, 1, -6)
				end
				local ok, mod = pcall(require, modulePath)
				t.truthy(ok, `{file}: {tostring(mod)}`)
				t.eq(type(mod), "table", file)
			end
		end)
	end

	t.test("exactly one server Script and one client LocalScript entry point", function()
		local serverScripts, clientScripts = 0, 0
		local function scan(dir: string)
			for _, entry in fs.readDir(dir) do
				local path = `{dir}/{entry}`
				if fs.isDir(path) then
					scan(path)
				elseif string.find(entry, "%.server%.luau$") then
					serverScripts += 1
				elseif string.find(entry, "%.client%.luau$") then
					clientScripts += 1
				end
			end
		end
		scan("src")
		t.eq(serverScripts, 1, "server scripts")
		t.eq(clientScripts, 1, "client scripts")
	end)
end
