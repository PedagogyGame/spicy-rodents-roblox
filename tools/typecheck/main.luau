--!strict
-- tools/typecheck/main.luau: strict Luau type checking with luau-lsp, as a gate that only lets the
-- error count go down (owner request 2026-11-11: "Build luau-lsp and add type checking to the check
-- script"). Until then the type checker only ran on GitHub, where its failures went unread, and the
-- code picked up type errors nobody saw. Those known errors are listed in tools/typecheck/baseline.txt;
-- this tool fails on any error that is NOT in that list, so new code must be clean, and the list can
-- only shrink.
--
-- Usage (repo root, after `rojo sourcemap default.project.json -o sourcemap.json --include-non-scripts`):
--   lune run tools/typecheck/main.luau            check against the baseline; exit 1 on a new error
--   lune run tools/typecheck/main.luau --update   rewrite the baseline from this run (after fixing errors)
--   lune run tools/typecheck/main.luau --all      print every error, known or new; exit 1 if there are any
--
-- An error is known by its file and its message with the quoted types blanked out (so a line moving,
-- or a table type gaining a field, does not make an old error look new), counted per file: one more
-- error of the same shape in the same file than the baseline holds is a new error.
--
-- The Roblox type definitions must match the luau-lsp release. They are looked for in
-- $LUAU_LSP_DEFINITIONS, ./globalTypes.d.luau (GitHub Actions downloads it there) and
-- ~/.cache/spicy-rodents/luau-lsp/globalTypes-<version>.d.luau (docs/ENVIRONMENT_SETUP.sh copies it
-- there from the luau-lsp source it builds).
local fs = require("@lune/fs")
local process = require("@lune/process")

local BASELINE = "tools/typecheck/baseline.txt"
local SETTINGS = "build/luau-analyze.json"
local SOURCEMAP = "sourcemap.json"
-- what is checked (the same set GitHub Actions has always checked); specs run under Lune, whose
-- library luau-lsp has no definitions for here
local TARGETS = { "src/", "tests/engine/", "tools/cloud/tasks/" }
local IGNORE = "**/*.spec.luau"
local DETAIL_LINES = 8 -- how much of a multi-line error is printed for a new error

type Diagnostic = { file: string, line: number, col: number, message: string, key: string, detail: { string } }

local mode = "check"
for _, a in process.args do
	if a == "--update" then
		mode = "update"
	elseif a == "--all" then
		mode = "all"
	else
		print("typecheck: unknown argument " .. a)
		process.exit(2)
	end
end

local function fail(message: string): never
	print("typecheck: " .. message)
	return process.exit(1)
end

-- luau-lsp and its version
local probe = process.exec("luau-lsp", { "--version" })
if not probe.ok then
	fail("luau-lsp is not installed (docs/ENVIRONMENT_SETUP.sh builds it from source; rokit.toml pins it)")
end
local version = (probe.stdout:gsub("%s+", ""))

-- the Roblox definitions
local function definitions(): string
	local candidates = {}
	local fromEnv = process.env.LUAU_LSP_DEFINITIONS
	if fromEnv and fromEnv ~= "" then
		table.insert(candidates, fromEnv)
	end
	table.insert(candidates, "globalTypes.d.luau")
	local home = process.env.HOME
	if home and home ~= "" then
		table.insert(candidates, `{home}/.cache/spicy-rodents/luau-lsp/globalTypes-{version}.d.luau`)
	end
	for _, path in candidates do
		if fs.isFile(path) then
			return path
		end
	end
	return fail(
		`no Roblox type definitions for luau-lsp {version}; looked in: {table.concat(candidates, ", ")}`
			.. " (docs/ENVIRONMENT_SETUP.sh installs them)"
	)
end
local defs = definitions()

if not fs.isFile(SOURCEMAP) then
	fail(`{SOURCEMAP} is missing: run rojo sourcemap default.project.json -o {SOURCEMAP} --include-non-scripts`)
end
if not fs.isDir("build") then
	fs.writeDir("build")
end
fs.writeFile(
	SETTINGS,
	[[{
  "luau-lsp.platform.type": "roblox",
  "luau-lsp.sourcemap.enabled": true,
  "luau-lsp.require.mode": "relativeToFile",
  "luau-lsp.diagnostics.strictDatamodelTypes": false
}
]]
)

local args = {
	"analyze",
	"--definitions=" .. defs,
	"--sourcemap=" .. SOURCEMAP,
	"--platform=roblox",
	"--base-luaurc=.luaurc",
	"--settings=" .. SETTINGS,
	"--ignore=" .. IGNORE,
}
for _, target in TARGETS do
	table.insert(args, target)
end
local t0 = os.clock()
local run = process.exec("luau-lsp", args)
local seconds = os.clock() - t0

-- "path [instance path](line,col): Kind: message", then any number of continuation lines
local cwd = process.cwd
if string.sub(cwd, -1) ~= "/" then
	cwd ..= "/"
end
local function blank(message: string): string
	return (string.gsub(message, "'[^']*'", "'…'"))
end
local diagnostics: { Diagnostic } = {}
local current: Diagnostic? = nil
-- luau-lsp prints some errors several times over at the same place (once per instantiation of a
-- generic, it seems): one error per place and message is what counts
local seen: { [string]: boolean } = {}
for raw in string.gmatch(run.stdout .. "\n" .. run.stderr, "[^\n]+") do
	local where, line, col, kind, message = string.match(raw, "^(.-)%((%d+),(%d+)%): (%a+): (.*)$")
	if where and string.find(where, "%.luau") then
		local file = (string.gsub(where, " %[.-%]$", ""))
		if string.sub(file, 1, #cwd) == cwd then
			file = string.sub(file, #cwd + 1)
		end
		local text = `{kind}: {message}`
		local d: Diagnostic = {
			file = file,
			line = tonumber(line) or 0,
			col = tonumber(col) or 0,
			message = text,
			key = blank(text),
			detail = {},
		}
		local place = `{file}({line},{col}): {text}`
		if seen[place] then
			current = nil
		else
			seen[place] = true
			table.insert(diagnostics, d)
			current = d
		end
	elseif string.sub(raw, 1, 1) == "[" then
		current = nil -- [INFO] / [WARN] lines from the tool itself
	elseif current and #current.detail < DETAIL_LINES then
		table.insert(current.detail, raw)
	end
end
if #diagnostics == 0 and not run.ok then
	-- the tool failed for a reason that is not a type error (bad arguments, a crash): show it
	print(run.stdout)
	print(run.stderr)
	fail(`luau-lsp analyze exited with code {run.code} and reported no type errors`)
end

-- counts per file and blanked message
type Counts = { [string]: { [string]: number } }
local function count(list: { Diagnostic }): Counts
	local out: Counts = {}
	for _, d in list do
		local perFile = out[d.file]
		if perFile == nil then
			perFile = {}
			out[d.file] = perFile
		end
		perFile[d.key] = (perFile[d.key] or 0) + 1
	end
	return out
end
local now = count(diagnostics)

local function show(d: Diagnostic)
	print(`{d.file}({d.line},{d.col}): {d.message}`)
	for _, extra in d.detail do
		print("    " .. extra)
	end
end

if mode == "all" then
	for _, d in diagnostics do
		show(d)
	end
	print(`typecheck: {#diagnostics} type errors (luau-lsp {version}, {string.format("%.1f", seconds)} s)`)
	process.exit(if #diagnostics == 0 then 0 else 1)
end

if mode == "update" then
	local lines = {}
	for file, perFile in now do
		for key, n in perFile do
			table.insert(lines, `{file}\t{n}\t{key}`)
		end
	end
	table.sort(lines)
	local header = {
		"# Known type errors: the debt tools/typecheck/main.luau tolerates. One line per file and message",
		"# (quoted types blanked): file <tab> how many <tab> message. The check fails on anything not listed",
		"# here. Fix errors, then run `lune run tools/typecheck/main.luau --update`; never add lines by hand.",
		`# {#diagnostics} errors in total (luau-lsp {version}).`,
	}
	fs.writeFile(BASELINE, table.concat(header, "\n") .. "\n" .. table.concat(lines, "\n") .. "\n")
	print(`typecheck: baseline rewritten: {#diagnostics} known errors in {BASELINE}`)
	process.exit(0)
end

-- check against the baseline
local known: Counts = {}
local knownTotal = 0
if fs.isFile(BASELINE) then
	for raw in string.gmatch(fs.readFile(BASELINE), "[^\n]+") do
		if string.sub(raw, 1, 1) ~= "#" then
			local file, n, key = string.match(raw, "^([^\t]+)\t(%d+)\t(.*)$")
			if file and n and key then
				local perFile = known[file]
				if perFile == nil then
					perFile = {}
					known[file] = perFile
				end
				perFile[key] = tonumber(n) or 0
				knownTotal += tonumber(n) or 0
			end
		end
	end
end

local fresh = 0
local shown: { [string]: boolean } = {}
for _, d in diagnostics do
	local allowed = (known[d.file] and known[d.file][d.key]) or 0
	local have = now[d.file][d.key]
	if have > allowed then
		local tag = d.file .. "\t" .. d.key
		if not shown[tag] then
			shown[tag] = true
			fresh += have - allowed
			if allowed > 0 then
				print(`-- {have} of these in {d.file}, {allowed} known: {have - allowed} new (every one is shown)`)
			end
			for _, other in diagnostics do
				if other.file == d.file and other.key == d.key then
					show(other)
				end
			end
		end
	end
end

local gone = 0
for file, perFile in known do
	for key, n in perFile do
		local have = (now[file] and now[file][key]) or 0
		if have < n then
			gone += n - have
		end
	end
end

local timing = `luau-lsp {version}, {string.format("%.1f", seconds)} s`
if fresh > 0 then
	print(
		`typecheck: {fresh} NEW type error(s) ({#diagnostics} in all, {knownTotal} known in {BASELINE}; {timing}).`
			.. " Fix them; the baseline is for old debt only."
	)
	process.exit(1)
end
print(`typecheck: no new type errors ({#diagnostics} known, listed in {BASELINE}; {timing})`)
if gone > 0 then
	print(`typecheck: {gone} known error(s) are fixed: run lune run tools/typecheck/main.luau --update to lock that in`)
end
