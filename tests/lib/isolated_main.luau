--!strict
-- tests/lib/isolated_main.luau: the child side of tests/lib/Isolated. Loads one cases file (the same shape as
-- a spec), runs every case, and prints the results as JSON after a marker line for the parent to read.
-- Usage (the parent does this): lune run tests/lib/isolated_main.luau tests/isolated/<name>
-- Interface: a script; prints `@@ISOLATED@@` then a JSON list of { name, ok, err }.

local process = require("@lune/process")
local serde = require("@lune/serde")
local Test = require("./Test")

local casesPath = process.args[1]
local results: { { name: string, ok: boolean, err: string? } } = {}

if casesPath == nil then
	table.insert(results, { name = "isolated_main", ok = false, err = "no cases file given" })
else
	-- this file lives in tests/lib: a repo-relative path is two levels up
	local okLoad, cases = pcall(require, "../../" .. casesPath)
	if not okLoad or type(cases) ~= "function" then
		table.insert(results, { name = casesPath, ok = false, err = `could not load: {tostring(cases)}` })
	else
		local t, list = Test.new()
		local okReg, regErr = pcall(cases, t)
		if not okReg then
			table.insert(results, { name = casesPath, ok = false, err = `cases body errored: {tostring(regErr)}` })
		end
		for _, case in list do
			local ok, err = pcall(case.fn)
			table.insert(results, { name = case.name, ok = ok, err = if ok then nil else tostring(err) })
		end
	end
end

print("@@ISOLATED@@" .. serde.encode("json", results))
