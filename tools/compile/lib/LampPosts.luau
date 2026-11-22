--!strict
-- tools/compile: data/lamp_posts.json -> generated/LampPosts.luau (BRIEF_ADDENDUM D35: the owner's "make all trees
-- climbable, and even all light posts"). Shared/World/LampPosts.build, the one place the rules live, turns the posts the
-- bakes placed (tools/bake/lamp_posts.luau found them) into route records (origin "lampPost": a climb per post, an arm
-- where the post has one) and their canopy forks; this module checks what they must hold and hands the table to the
-- emitter. Shared/Data appends `routes` to the Registry after the tree shapes and merges `forks` into the canopy forks.
-- Invariants: post ids unique; route ids unique, clear of the harvest and of every other compiled id; every post at
-- least C.minHeight tall; an arm's fork on its own climb.
-- Interface: compile(ctx) -> Module? (nil when the file is absent).
local fs = require("@lune/fs")
local Json = require("./Json")
local LampPosts = require("../../../src/shared/World/LampPosts")

local Lib = {}

function Lib.compile(ctx: any): any?
	local rel = "data/lamp_posts.json"
	local path = ctx.repo .. "/" .. rel
	if not fs.isFile(path) then
		return nil
	end
	local doc = Json.decodeFile(path)
	local postIds: { [string]: boolean } = {}
	for _, p in doc.posts do
		ctx.invariant("lamp post id unique: " .. p.id, not postIds[p.id])
		postIds[p.id] = true
		ctx.invariant(
			`lamp post {p.id}: at least {LampPosts.C.minHeight} studs tall`,
			p.top - p.ground - LampPosts.C.stand >= LampPosts.C.minHeight
		)
	end
	local compiled = LampPosts.build({ idBase = doc.idBase, posts = doc.posts })
	local seen: { [number]: boolean } = {}
	for _, r in compiled.routes do
		ctx.invariant("lamp post route id unique: " .. r.id, not seen[r.id])
		ctx.invariant("lamp post route id clear of the harvest: " .. r.id, not ctx.routeIds[r.id])
		ctx.invariant("lamp post route id clear of the other compiled routes: " .. r.id, not ctx.otherIds[r.id])
		seen[r.id] = true
	end
	for _, f in compiled.forks do
		for _, e in f.forks do
			ctx.invariant(`lamp post arm {e.branch} forks off its climb {f.trunk}`, seen[f.trunk] and seen[e.branch])
		end
	end
	local arms = 0
	for _, p in compiled.posts do
		if p.arm then
			arms += 1
		end
	end
	return {
		name = "LampPosts",
		value = compiled,
		records = #compiled.routes,
		map = true,
		source = rel,
		header = {
			`STUDS, world space. The D35 lamp-post climbs (Shared/World/LampPosts: its header is the interface): {#compiled.posts}`,
			`posts, {arms} with an arm. routes: world-space route records (origin lampPost) that Shared/Data appends to the`,
			"Routes Registry; forks: each arm's canopy fork on its climb, merged into the harvest's by Shared/Data; posts:",
			"per post its route ids.",
		},
	}
end

return Lib
