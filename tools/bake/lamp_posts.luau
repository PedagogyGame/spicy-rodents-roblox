--!strict
-- tools/bake/lamp_posts: every light post the bakes place -> data/lamp_posts.json (owner D35, "make all trees
-- climbable, and even all light posts"; Shared/World/LampPosts is the format and the rules). Reads the baked models
-- (tools/bake/LampScan.FILES: build/Town.rbxm, build/Attractions.rbxm, the expansions), finds the posts by LampScan's
-- rules, keeps those inside the world (World/Height.worldClamp) and writes them, rounded to 1e-3 studs, sorted by source and id. The id base is kept from the
-- file when it exists. Then `lune run tools/compile/main.luau compile` turns the file into generated/LampPosts.luau.
-- Run after any bake that moves, adds or removes a lamp (tests/unit/lamp_posts.spec.luau fails until it is run: every
-- baked post must have its climb): the town's bake moves its lamps when a tree or a pole is added near one.
-- Usage (repo root, after the bakes): lune run tools/bake/lamp_posts.luau [--check]
--   --check   write nothing; exit 1 when data/lamp_posts.json differs from what the bakes hold now
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Height = require("../../src/shared/World/Height")
local Json = require("../compile/lib/Json")
local LampScan = require("./LampScan")

local OUT = "data/lamp_posts.json"
local ID_BASE = 20001 -- clear of the harvest (0-1331) and every compiled id (the attractions 9000-, the storm drains
-- 9301-, the hollow trees 9411-, the tree shapes 9801-)
local NEEDED = { town = true, attractions = true, bowl_lane = true, skylift = true }

local check = false
for _, a in process.args do
	if a == "--check" then
		check = true
	else
		error("unknown argument: " .. a)
	end
end

Height.configure(require("../../generated/TerrainExtensions") :: any)
local clamp = Height.worldClamp()

local function r3(v: number): number
	return math.floor(v * 1000 + 0.5) / 1000
end

local lines = LampScan.carLanes(require("../../generated/Lanes") :: any, require("../../generated/Roads") :: any)
local posts = {}
local counts = {}
local cut = 0
local outside = 0
for _, f in LampScan.FILES do
	if not fs.isFile(f.file) then
		if NEEDED[f.source] then
			error(`lamp_posts: {f.file} missing (bake it first)`)
		end
		continue
	end
	local found = LampScan.scan(roblox.deserializeModel(fs.readFile(f.file)), f.source)
	local n = 0
	for _, p in found do
		if p.x < clamp.minX or p.x > clamp.maxX or p.z < clamp.minZ or p.z > clamp.maxZ then
			outside += 1
			continue
		end
		n += 1
		local rec: { [string]: any } = {
			id = p.id,
			source = p.source,
			path = p.path,
			x = r3(p.x),
			z = r3(p.z),
			ground = r3(p.ground),
			top = r3(p.top),
			radius = r3(p.radius),
		}
		if p.arm then
			rec.arm = { ox = p.arm.ox, oz = p.arm.oz, reach = p.arm.reach }
			-- an arm over a car lane: its route stops short of the lane (LampScan.armRun)
			local run = LampScan.armRun(rec :: any, lines)
			if run then
				rec.arm.run = run
				cut += 1
			end
		end
		table.insert(posts, rec)
	end
	counts[f.source] = n
end

local idBase = ID_BASE
if fs.isFile(OUT) then
	local old = serde.decode("json", fs.readFile(OUT))
	idBase = old.idBase or ID_BASE
end
local doc = {
	["$schema"] = "lamp posts v1 (Shared/World/LampPosts: its header is the format)",
	src = "BRIEF_ADDENDUM D35 (owner, 2026-11-22): 'make all trees climbable, and even all light posts'. Written by tools/bake/lamp_posts.luau from the baked models (do not edit by hand: re-run it after a bake that moves a lamp). Studs, world space. Owner sheet: docs/owner/CLIMB_POSTS_CHECK.md.",
	idBase = idBase,
	posts = posts,
}
local text = Json.encode(doc, { keyOrder = { "$schema", "src", "idBase", "id", "source", "path" } })
local parts = {}
for _, f in LampScan.FILES do
	if counts[f.source] then
		table.insert(parts, `{f.source} {counts[f.source]}`)
	end
end
local summary =
	`lamp_posts: {#posts} posts ({table.concat(parts, ", ")}); {outside} outside the world left out; {cut} arm route(s) cut short of a car lane`
if check then
	local same = fs.isFile(OUT) and fs.readFile(OUT) == text
	print(summary .. (if same then "; data/lamp_posts.json is current" else "; data/lamp_posts.json is STALE"))
	process.exit(if same then 0 else 1)
end
fs.writeFile(OUT, text)
print(summary .. " -> " .. OUT)
