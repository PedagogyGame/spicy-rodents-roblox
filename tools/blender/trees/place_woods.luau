--!strict
-- tools/blender/trees/place_woods.luau: scatter the D34 woods (data/woods.json groves) over the town as baked and
-- write data/woods_placed.json, every tree where WorldGen/WoodsPlan allows it (tests/unit/woods.spec.luau holds each
-- placement to the same rule, so a later change to the town that crowds a tree fails there: run this again).
--   lune run tools/blender/trees/place_woods.luau [--dry]     then lune run tools/compile/main.luau compile
-- Per grove, in order: a `lone` grove stands its one tree at the clear spot nearest `at` (within `search`) with a
-- quarter more room than its crown; a `rect` or `disc` grove throws darts (seeded, WoodsPlan.rng(seed + grove)) and
-- keeps each that WoodsPlan.check passes, its kind drawn by the weights and its scale from the range, its
-- neighbours in the woods at least `share` of the two crowns apart, until `count` stand or the darts run out.
-- Output: one tree a line, [kind, x, ground y, z, yaw (radians), scale, grove]; counts per grove and kind.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Height = require("@shared/World/Height")
local WoodsPlan = require("@worldgen/WoodsPlan")
local WoodsWorld = require("@tests/lib/WoodsWorld")

local dry = table.find(process.args, "--dry") ~= nil
local doc = serde.decode("json", fs.readFile("data/woods.json"))
local ctx = WoodsWorld.new()
local world = ctx.world

local function r2(v: number): number
	return math.floor(v * 100 + 0.5) / 100
end

local placed: { { any } } = {}
local others: { { number } } = {}
local counts: { [string]: number } = {}
local kindCounts: { [string]: number } = {}

local function pick(mix: { [string]: number }, u: number): string
	local keys = {}
	local total = 0
	for k, w in mix do
		table.insert(keys, k)
		total += w
	end
	table.sort(keys)
	local acc = 0
	for _, k in keys do
		acc += mix[k] / total
		if u <= acc then
			return k
		end
	end
	return keys[#keys]
end

local function stand(g: any, kind: string, x: number, z: number, yaw: number, scale: number, share: number)
	local k = doc.kinds[kind]
	table.insert(placed, { kind, r2(x), r2(Height.at(x, z)), r2(z), math.floor(yaw * 1000 + 0.5) / 1000, r2(scale), g.id })
	table.insert(others, { x, z, k.crown * scale, share })
	counts[g.id] = (counts[g.id] or 0) + 1
	kindCounts[kind] = (kindCounts[kind] or 0) + 1
end

for gi, g in doc.groves do
	local rnd = WoodsPlan.rng(doc.seed + 7919 * gi)
	if g.lone then
		local kind = pick(g.mix, 0)
		local crown = doc.kinds[kind].crown
		local best: { number }? = nil
		local step = 6
		for r = 0, g.search, step do
			local n = math.max(1, math.floor(2 * math.pi * r / step))
			for i = 0, n - 1 do
				local a = (i + 0.5 * (r / step % 2)) / n * 2 * math.pi
				local x, z = g.at[1] + math.cos(a) * r, g.at[2] + math.sin(a) * r
				if WoodsPlan.check(world, x, z, crown * 1.25, others) == nil then
					best = { x, z }
					break
				end
			end
			if best then
				break
			end
		end
		if best then
			stand(g, kind, best[1], best[2], rnd() * 2 * math.pi, 1, 1)
		else
			print(`place_woods: no room for {g.label} within {g.search} of {g.at[1]}, {g.at[2]}`)
		end
	else
		local want = g.count
		local darts = want * 80
		local got = 0
		-- a clumped grove ([radius, trees per copse]) throws its darts round copse centres strewn over its area
		local centres: { { number } } = {}
		if g.clump then
			for _ = 1, math.ceil(want / g.clump[2]) * 2 do
				table.insert(centres, {
					g.rect[1] + (g.rect[2] - g.rect[1]) * rnd(),
					g.rect[3] + (g.rect[4] - g.rect[3]) * rnd(),
				})
			end
		end
		for _ = 1, darts do
			if got >= want then
				break
			end
			local x, z
			if g.clump then
				local c = centres[1 + math.floor(rnd() * #centres)]
				local a, rr = rnd() * 2 * math.pi, g.clump[1] * math.sqrt(rnd())
				x, z = c[1] + math.cos(a) * rr, c[2] + math.sin(a) * rr
			elseif g.rect then
				x = g.rect[1] + (g.rect[2] - g.rect[1]) * rnd()
				z = g.rect[3] + (g.rect[4] - g.rect[3]) * rnd()
			else
				local a, rr = rnd() * 2 * math.pi, g.disc[3] * math.sqrt(rnd())
				x, z = g.disc[1] + math.cos(a) * rr, g.disc[2] + math.sin(a) * rr
			end
			local kind = pick(g.mix, rnd())
			local scale = g.scale[1] + (g.scale[2] - g.scale[1]) * rnd()
			local yaw = rnd() * 2 * math.pi
			local crown = doc.kinds[kind].crown * scale
			-- (the grove's own spacing first: cheaper than the town's)
			local near = false
			for _, o in others do
				local need = math.max(WoodsPlan.C.WOODS_MIN, math.min(g.share, o[4]) * (o[3] + crown))
				if (o[1] - x) ^ 2 + (o[2] - z) ^ 2 < need * need then
					near = true
					break
				end
			end
			if not near and WoodsPlan.check(world, x, z, crown, nil) == nil then
				stand(g, kind, x, z, yaw, scale, g.share)
				got += 1
			end
		end
		if got < want then
			print(`place_woods: {g.id}: {got} of {want} (no more room)`)
		end
	end
end

local lines = {}
for _, t in placed do
	table.insert(lines, "    " .. serde.encode("json", t))
end
local function obj(m: { [string]: number }): string
	local keys = {}
	for k in m do
		table.insert(keys, k)
	end
	table.sort(keys)
	local parts = {}
	for _, k in keys do
		table.insert(parts, `"{k}": {m[k]}`)
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end
local text = table.concat({
	"{",
	'  "$schema": "woods placed v1: [kind, x, ground y, z, yaw radians, scale, grove] (tools/blender/trees/place_woods.luau from data/woods.json; do not edit by hand)",',
	`  "count": {#placed},`,
	`  "groves": {obj(counts)},`,
	`  "kinds": {obj(kindCounts)},`,
	'  "trees": [',
	table.concat(lines, ",\n"),
	"  ]",
	"}",
	"",
}, "\n")
print(`place_woods: {#placed} trees; groves {obj(counts)}`)
print(`place_woods: kinds {obj(kindCounts)}`)
if not dry then
	fs.writeFile("data/woods_placed.json", text)
	print("place_woods: wrote data/woods_placed.json")
end
