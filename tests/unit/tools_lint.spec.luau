--!strict
-- Every directory of Luau tools is formatted and linted by tools/ci.sh (its LUAU_DIRS), and a minigame's own
-- tools have ONE home that is already on the list: tools/games/<game>/. Before this, a game that added a
-- calibrate tool had to add its directory to the one line that holds the list (every game's merge after the
-- first conflicted there), and a directory left off that line was never formatted or linted at all.
local fs = require("@lune/fs")

-- tool directories from before the rule, never formatted: nothing may join them
local NOT_LINTED = { ["tools/placeholders"] = true, ["tools/review"] = true }

-- the directories tools/ci.sh hands to stylua and selene: `LUAU_DIRS=(...)` and every `LUAU_DIRS+=(...)`
local function lintedDirs(): { string }
	local out = {}
	for list in string.gmatch(fs.readFile("tools/ci.sh"), "LUAU_DIRS%+?=%(([^)]*)%)") do
		for dir in string.gmatch(list, "%S+") do
			table.insert(out, dir)
		end
	end
	return out
end

local function covered(dir: string, linted: { string }): boolean
	for _, root in linted do
		if dir == root or string.sub(dir, 1, #root + 1) == root .. "/" then
			return true
		end
	end
	for root in NOT_LINTED do
		if dir == root or string.sub(dir, 1, #root + 1) == root .. "/" then
			return true
		end
	end
	return false
end

-- every directory under `dir` that holds a .luau file of its own
local function luauDirs(dir: string, out: { string })
	local has = false
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			luauDirs(path, out)
		elseif string.sub(entry, -5) == ".luau" then
			has = true
		end
	end
	if has then
		table.insert(out, dir)
	end
end

return function(t)
	t.test(
		"tools/ci.sh formats and lints tools/games (when a game has put a tool there) without a new line per game",
		function()
			local linted = lintedDirs()
			t.truthy(table.find(linted, "src") and table.find(linted, "tests"), table.concat(linted, " "))
			t.truthy(table.find(linted, "tools/games"), "tools/games is one of LUAU_DIRS")
			-- (stylua refuses a path that is not there, and no game has a tool yet: the directory is added only if it exists)
			local sh = fs.readFile("tools/ci.sh")
			t.truthy(string.find(sh, "if [ -d tools/games ]; then\n\tLUAU_DIRS+=(tools/games)\nfi", 1, true))
			t.truthy(covered("tools/games/pool", linted) and covered("tools/games/pinball/lib", linted))
			t.falsy(covered("tools/some_new_game", linted), "a tool directory beside tools/games is not on the list")
		end
	)

	t.test("every directory of Luau tools is on that list", function()
		local linted = lintedDirs()
		local dirs: { string } = {}
		luauDirs("tools", dirs)
		t.truthy(#dirs >= 10, `{#dirs} tool directories`)
		for _, dir in dirs do
			t.truthy(
				covered(dir, linted),
				`{dir} holds Luau that tools/ci.sh never formats or lints: a minigame's tools go in tools/games/<game>/`
			)
		end
	end)
end
