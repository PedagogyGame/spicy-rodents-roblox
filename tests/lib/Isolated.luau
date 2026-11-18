--!strict
-- tests/lib/Isolated.luau: run a file of test cases in its own Lune process and bring the results back.
-- Why: tests/lib/FakeEngine puts engine globals in place with getfenv, and in Luau that switches off the fast
-- paths (builtin calls, cached globals) for everything that runs afterwards in the same process. Run in the
-- shared runner it made every later spec slower and tipped a timing test over. A cases file under
-- tests/isolated/ has the same shape as a spec (`return function(t) t.test(...) end`); the spec in tests/unit
-- that owns it calls Isolated.register, which runs the child once and reports each case as its own test.
-- Interface: run(casesPath) -> { { name, ok, err } } (casesPath repo-relative, no extension);
--   register(t, casesPath) (one t.test per child case; one failing test if the child could not run)

local process = require("@lune/process")
local serde = require("@lune/serde")

local Isolated = {}

Isolated.MAIN = "tests/lib/isolated_main.luau"
Isolated.MARK = "@@ISOLATED@@"

export type Result = { name: string, ok: boolean, err: string? }

local function lunePaths(): { string }
	local out = { "lune" }
	local home = process.env.HOME
	if home then
		table.insert(out, home .. "/.cargo/bin/lune")
		table.insert(out, home .. "/.rokit/bin/lune")
	end
	return out
end

function Isolated.run(casesPath: string): { Result }
	local lastErr = "lune was not found"
	for _, exe in lunePaths() do
		local ok, res = pcall(process.exec, exe, { "run", Isolated.MAIN, casesPath })
		if ok then
			local out = (res :: any).stdout :: string
			local at = string.find(out, Isolated.MARK, 1, true)
			if at then
				local decoded = serde.decode("json", string.sub(out, at + #Isolated.MARK))
				return decoded :: { Result }
			end
			lastErr = `the isolated run of {casesPath} printed no results (exit {(res :: any).code}):\n{out}\n{(
				res :: any
			).stderr}`
			break
		else
			lastErr = tostring(res)
		end
	end
	return { { name = `isolated run of {casesPath}`, ok = false, err = lastErr } }
end

function Isolated.register(t: { test: (name: string, fn: () -> ()) -> () }, casesPath: string)
	for _, r in Isolated.run(casesPath) do
		t.test(r.name, function()
			if not r.ok then
				error(r.err or "failed", 0)
			end
		end)
	end
end

return Isolated
