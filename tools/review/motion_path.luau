--!strict
-- tools/review/motion_path: write the squirrel's scripted takes as JSON, one file per body and take
-- (build/motion/<variant>_<take>.json), for tools/blender/heroes/render_motion.py (the pictures) and
-- motion_metrics.py (the numbers). Every frame of a take comes out of the game's own motor, drawn pose,
-- camera and animation rules (tools/review/motion/Path.luau says how, and what a frame holds); nothing
-- here ships or touches the game.
-- Usage (repo root):
--   lune run tools/review/motion_path.luau [--variants squirrel,rodent] [--takes walk,sprint,...]
--     [--out build/motion] [--list] [--set Module.table.name=number,...]
-- Takes: walk, sprint, turn, stop, leap, climb, wire, stalk (all, when --takes is not given).
-- --set tries a number of the game's WITHOUT changing the game: the named field of one of the tables in
-- TUNABLE below is set for this run only, so the takes show what the game would do with it (give --out
-- another folder, to keep them apart from the takes of the game as it is). For example:
--   --set Motion.C.visualWireLift=0.08,SquirrelVisual.params.barkGap=0,AnimationDriver.HERO.stride.Wire=6.9

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Path = require("./motion/Path")

-- the tables of the game's numbers that --set may reach (the same tables Path's modules read)
local TUNABLE: { [string]: any } = {
	["AnimationDriver.HERO"] = require("../../src/client/Animation/AnimationDriver").HERO,
	["AnimationDriver.HERO.stride"] = require("../../src/client/Animation/AnimationDriver").HERO.stride,
	["CameraRig.ORBIT"] = require("../../src/client/Camera/CameraRig").ORBIT,
	["Motion.C"] = require("../../src/shared/Routes/Motion").C,
	["SquirrelVisual.params"] = require("../../src/shared/Movement/SquirrelVisual").params,
}

local out = "build/motion"
local variants: { string } = { "squirrel", "rodent" }
local takes: { string } = {}
local listOnly = false

local function split(s: string): { string }
	local list = {}
	for word in string.gmatch(s, "[^,]+") do
		table.insert(list, word)
	end
	return list
end

do
	local args = process.args
	local i = 1
	while i <= #args do
		local a = args[i]
		if a == "--out" then
			out = args[i + 1]
			i += 1
		elseif a == "--variants" then
			variants = split(args[i + 1])
			i += 1
		elseif a == "--takes" then
			takes = split(args[i + 1])
			i += 1
		elseif a == "--list" then
			listOnly = true
		elseif a == "--set" then
			for _, pair in split(args[i + 1]) do
				local where, name, value = string.match(pair, "^(.+)%.([%w_]+)=(.+)$")
				local tbl = if where then TUNABLE[where] else nil
				local number = tonumber(value)
				if tbl == nil or name == nil or number == nil or type(tbl[name]) ~= "number" then
					error(`motion_path: --set {pair}: not a number of the game's that can be tried here`)
				end
				print(`trying {where}.{name} = {number} (the game has {tbl[name]})`)
				tbl[name] = number
			end
			i += 1
		else
			error(`motion_path: unknown argument {a}`)
		end
		i += 1
	end
end

if #takes == 0 then
	for _, def in Path.TAKES do
		table.insert(takes, def.name)
	end
end

if listOnly then
	for _, def in Path.TAKES do
		print(string.format("%-7s %4.2f s  %s", def.name, def.seconds, def.title))
	end
	return
end

local function mkdirs(path: string)
	local at = ""
	for part in string.gmatch(path, "[^/]+") do
		at = if at == "" then part else `{at}/{part}`
		if not fs.isDir(at) then
			fs.writeDir(at)
		end
	end
end
mkdirs(out)

for _, variant in variants do
	for _, name in takes do
		local take = Path.simulate(variant, name)
		local path = `{out}/{variant}_{name}.json`
		fs.writeFile(path, serde.encode("json", take, false))
		-- one line of what happened: how far, how fast, which clips played and for how many frames
		local frames = take.frames
		local last = frames[#frames]
		local top = 0
		local seen: { [string]: number } = {}
		local order: { string } = {}
		local said: { string } = {}
		for _, f in frames do
			top = math.max(top, f.speed)
			if seen[f.clip] == nil then
				seen[f.clip] = 0
				table.insert(order, f.clip)
			end
			seen[f.clip] += 1
			for _, e in f.events do
				table.insert(said, `{e}@{string.format("%.2f", f.t)}`)
			end
		end
		local clips = {}
		for _, c in order do
			table.insert(clips, `{c} {seen[c]}`)
		end
		print(
			string.format(
				"%-8s %-7s %3d frames  ends (%.1f, %.1f, %.1f)  top %.1f st/s  clips: %s%s",
				variant,
				name,
				#frames,
				last.pos.x,
				last.pos.y,
				last.pos.z,
				top,
				table.concat(clips, ", "),
				if #said > 0 then "  events: " .. table.concat(said, " ") else ""
			)
		)
	end
end
print(`motion_path: wrote {#variants * #takes} takes to {out}/`)
