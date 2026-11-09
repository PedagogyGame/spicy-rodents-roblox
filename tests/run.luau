--!strict
-- Lune test runner (BUILD_PLAN §6.2). Discovers *.spec.luau under tests/ and src/, runs each
-- with the tiny assertion lib in tests/lib/Test.luau, prints a summary and exits non-zero on
-- any failure. Usage, from the repo root:
--   lune run tests/run.luau            # all specs
--   lune run tests/run.luau units moon # only specs whose path contains one of the words

local fs = require("@lune/fs")
local process = require("@lune/process")
local Test = require("./lib/Test")

local ROOTS = { "tests", "src" }
local filters = process.args

local function wanted(path: string): boolean
	if #filters == 0 then
		return true
	end
	for _, f in filters do
		if string.find(path, f, 1, true) then
			return true
		end
	end
	return false
end

local function discover(dir: string, out: { string })
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			discover(path, out)
		elseif string.sub(entry, -10) == ".spec.luau" then
			table.insert(out, path)
		end
	end
end

local specs: { string } = {}
for _, root in ROOTS do
	if fs.isDir(root) then
		discover(root, specs)
	end
end
table.sort(specs)

local totalPassed, totalFailed, filesRun = 0, 0, 0
local started = os.clock()

for _, specPath in specs do
	if not wanted(specPath) then
		continue
	end
	filesRun += 1
	-- tests/run.luau lives in tests/, so a repo-relative path becomes "../<path>" without .luau.
	local modulePath = "../" .. string.sub(specPath, 1, -6)
	local okLoad, specOrErr = pcall(require, modulePath)
	if not okLoad or type(specOrErr) ~= "function" then
		totalFailed += 1
		print(`FAIL  {specPath}: could not load spec: {tostring(specOrErr)}`)
		continue
	end
	local t, cases = Test.new()
	local okRegister, regErr = pcall(specOrErr, t)
	if not okRegister then
		totalFailed += 1
		print(`FAIL  {specPath}: spec body errored: {tostring(regErr)}`)
		continue
	end
	for _, case in cases do
		local ok, err = pcall(case.fn)
		if ok then
			totalPassed += 1
			print(`ok    {specPath} :: {case.name}`)
		else
			totalFailed += 1
			print(`FAIL  {specPath} :: {case.name}\n      {tostring(err)}`)
		end
	end
end

local elapsed = os.clock() - started
print(
	`\n{totalPassed} passed, {totalFailed} failed across {filesRun} spec file(s) in {string.format("%.2f", elapsed)} s`
)
if totalFailed > 0 or filesRun == 0 then
	process.exit(1)
end
