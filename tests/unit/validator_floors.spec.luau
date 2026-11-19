--!strict
-- The floors a squirrel stands on against the floor the server's validator finds (validator round 5: a grounded packet
-- whose stand height is unknown, or that rose, needs a floor within ValidatorWorld.C.FLOOR_NEAR under its feet, a whole
-- flag; the round-4 review asked where a drawn floor sits more than that over its collider).
-- What the client's motor stands on (Client/World/ClientWorld.groundAt): the first colliding part a ray down from just
-- over the feet meets (in the squirrel's collision group), else the terrain, and over that the topmost non-colliding
-- ground plate of Town.Lots and Town.Roads (Shared/World/GroundPlate). What the server's floor ray meets
-- (ValidatorWorld.engineRays): the same colliding parts in the same group (SquirrelProbe, RespectCanCollide), the
-- terrain, the water, the cars, and the same ground plates by the same rule. Every interior outside Town.Lots (the corner
-- store, the lounge, the alley's rafters and vent, the sky lift's cabin: their own bakes, Workspace.Expansion and
-- Workspace.Attractions) stands on colliders only, so the two agree there by construction; the plates are measured here,
-- every plate of the baked town at its centre and four corners: how far over the colliding surface under it (what the
-- server's ray met before round 5) and whether the server's rule now finds the floor the client stands on.
local fs = require("@lune/fs")
local GroundPlate = require("@shared/World/GroundPlate")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local BakedWorld = require("@tests/lib/BakedWorld")
local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local ClientWorld = require("@client/World/ClientWorld")
local HollowLayout = require("@shared/World/HollowLayout")
local SewerLayout = require("@shared/World/SewerLayout")
local HollowShell = require("@server/World/HollowShell")
local SewerStandIn = require("@tests/lib/SewerStandIn")
local roblox = require("@lune/roblox")

-- the class of a colliding part a squirrel may stand on, for the sweep below
local function classOf(p: BakedWorld.Part): string
	local parentName = string.match(p.path, "([^%.]+)%.[^%.]+$") or ""
	if ValidatorWorld.isBough(p.name, parentName) then
		return "bough cylinder"
	elseif ClientWorld.isTrunk(p.name, parentName) then
		return "trunk"
	elseif string.sub(p.name, 1, 4) == "Limb" or string.sub(parentName, 1, 5) == "Limb_" then
		return "limb"
	elseif string.find(p.path, "Tramp", 1, true) or string.find(p.name, "Bed", 1, true) then
		return "trampoline"
	elseif string.find(p.path, "Rafter", 1, true) or p.name == "Truss" then
		return "rafter"
	elseif string.find(p.path, "Cabin", 1, true) then
		return "cabin"
	elseif string.sub(p.name, 1, 3) == "Seg" then
		return "road segment"
	end
	return "other"
end

return function(t)
	t.test(
		"the ground plates of the baked town: measured over their colliders, and the server's floor meets them",
		function()
			t.truthy(fs.isFile("build/Town.rbxm"), "build/Town.rbxm (lune run tools/bake/main.luau)")
			local town = BakedWorld.load("build/Town.rbxm")
			-- (the terrain as the server writes it: World/Height with the generated extensions, Server/WorldGen/WorldTerrain)
			Height.configure(Data.default():module("TerrainExtensions"))
			local inFolders: { [string]: boolean } = {}
			for _, n in GroundPlate.FOLDERS do
				inFolders[n] = true
			end
			local function solid(p: BakedWorld.Part): boolean
				return p.squirrelSolid
			end
			local function isPlate(p: BakedWorld.Part): boolean
				local folder = string.match(p.path, "^([^%.]+)") or "" -- (paths start under Town: Lots.<lot>.<part>)
				return not p.collide
					and inFolders[folder] == true
					and GroundPlate.like(p.name, p.hy * 2, p.transparency)
			end
			-- the client's ground at (x, z) for feet near refY (ClientWorld.groundAt), and the colliding surface under it
			local function clientGround(x: number, z: number, refY: number): (number, number)
				local from = refY + BakedWorld.RAY_ABOVE
				local hit = town.raycast(x, from, z, 0, -400, 0, solid)
				local solidY = if hit then from - 400 * hit else town.terrainAt(x, z)
				local p = town.raycast(x, from, z, 0, solidY - from, 0, isPlate)
				return if p then math.max(solidY, from + (solidY - from) * p) else solidY, solidY
			end
			-- the server's floorNear: ValidatorWorld.floor at FLOOR_NEAR over the live floor ray, by the server's own rule
			-- (BakedWorld.validatorRays: colliders, the bough cylinders included, terrain, water, plates)
			local _, down = BakedWorld.validatorRays(town)
			local serverFloorNear = ValidatorWorld.floor(down, ValidatorWorld.C.FLOOR_NEAR)
			local plates, samples, worst, worstAt, overBefore = 0, 0, -math.huge, "", 0
			local missed: { string } = {}
			local byFolder: { [string]: number } = {}
			for _, p in town.parts do
				if not isPlate(p) then
					continue
				end
				plates += 1
				local folder = string.match(p.path, "^([^%.]+)") or ""
				byFolder[folder] = (byFolder[folder] or 0) + 1
				local inset = 0.8
				for _, f in { { 0, 0 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
					local ex, ez = math.max(0, p.hx - inset) * f[1], math.max(0, p.hz - inset) * f[2]
					local x = p.px + p.ax[1] * ex + p.az[1] * ez
					local z = p.pz + p.ax[3] * ex + p.az[3] * ez
					samples += 1
					local feet, solidY = clientGround(x, z, p.y1)
					local gap = feet - solidY
					if gap > worst then
						worst, worstAt = gap, p.path
					end
					if gap > ValidatorWorld.C.FLOOR_NEAR then
						overBefore += 1
					end
					if not serverFloorNear(x, feet, z) then
						table.insert(missed, `{p.path} at ({math.floor(x)}, {math.floor(z)}), feet {feet}`)
					end
				end
			end
			Height.configure(nil)
			local folders = {}
			for k, n in byFolder do
				table.insert(folders, `{k} {n}`)
			end
			print(
				`      {plates} plates ({table.concat(folders, ", ")}), {samples} points: the client's feet up to {string.format(
					"%.2f",
					worst
				)} st over the colliding surface ({worstAt}); {overBefore} points over FLOOR_NEAR (a climb before round 5), {#missed} with no floor the server meets now`
			)
			for i = 1, math.min(#missed, 10) do
				print(`        {missed[i]}`)
			end
			t.truthy(plates > 0, "plates found")
			t.eq(#missed, 0, "the server's floor meets every plate the client stands on")
		end
	)

	t.test(
		"every part a squirrel stands on in the bakes: the server's floor ray meets the client's ground (the ray sweep)",
		function()
			-- What the client's motor stands on (ClientWorld.groundAt, BakedWorld.groundPart: the first colliding part in the
			-- squirrel's group under the feet) against the server's floorNear over its live floor ray (ValidatorWorld.floor at
			-- FLOOR_NEAR over BakedWorld.validatorRays' down: the server's own rule), at points on the top of every colliding
			-- part of every bake (each part's top face in its own frame, nine points) where the client's ground is that part.
			-- "before": the round-6 floor ray, which looked past the bough cylinders (the wall ray's rule).
			Height.configure(Data.default():module("TerrainExtensions"))
			local worlds: { { name: string, w: BakedWorld.World } } = {}
			for _, f in
				{
					"build/Town.rbxm",
					"build/Attractions.rbxm",
					"build/Expansion_F1.rbxm",
					"build/Expansion_F2.rbxm",
					"build/Expansion_F4.rbxm",
					"build/Expansion_LoungeClassic.rbxm",
					"build/Expansion_NeighbourhoodShop.rbxm",
				}
			do
				if fs.isFile(f) then
					table.insert(worlds, { name = f, w = BakedWorld.load(f) })
				end
			end
			t.truthy(#worlds >= 2, "the bakes (lune run tools/bake/main.luau and the expansion bakes)")
			table.insert(
				worlds,
				{ name = "storm drains (SewerStandIn)", w = SewerStandIn.world(SewerLayout.default()) }
			)
			table.insert(worlds, {
				name = "hollow trees (HollowShell)",
				w = BakedWorld.fromModel((HollowShell.build(roblox, HollowLayout.default()))),
			})
			local rows: { string } = {}
			local missedNow, missedBefore = 0, 0
			local byClass: { [string]: { n: number, now: number, before: number } } = {}
			for _, wf in worlds do
				local name, w = wf.name, wf.w
				local _, down = BakedWorld.validatorRays(w)
				-- (the round-6 floor ray: past the bough cylinders, as the wall ray)
				local function solidPastBoughs(p: BakedWorld.Part): boolean
					local parentName = string.match(p.path, "([^%.]+)%.[^%.]+$") or ""
					return p.squirrelSolid and not ValidatorWorld.isBough(p.name, parentName)
				end
				local function before(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number): boolean
					if w.raycast(ox, oy, oz, dx, dy, dz, solidPastBoughs) ~= nil then
						return true
					end
					return down(ox, oy, oz, dx, dy, dz)
						and w.raycast(ox, oy, oz, dx, dy, dz, function(p: BakedWorld.Part): boolean
								return p.squirrelSolid
							end)
							== nil
				end
				local nearNow = ValidatorWorld.floor(down, ValidatorWorld.C.FLOOR_NEAR)
				local nearBefore = ValidatorWorld.floor(before, ValidatorWorld.C.FLOOR_NEAR)
				local n, now, bef = 0, 0, 0
				for _, p in w.parts do
					if not p.squirrelSolid then
						continue
					end
					local class = classOf(p)
					local c = byClass[class]
					if c == nil then
						c = { n = 0, now = 0, before = 0 }
						byClass[class] = c
					end
					for _, u in { -0.6, 0, 0.6 } do
						for _, v in { -0.6, 0, 0.6 } do
							local lx, lz = u * p.hx, v * p.hz
							local x = p.px + p.ax[1] * lx + p.ay[1] * p.hy + p.az[1] * lz
							local y = p.py + p.ax[2] * lx + p.ay[2] * p.hy + p.az[2] * lz
							local z = p.pz + p.ax[3] * lx + p.ay[3] * p.hy + p.az[3] * lz
							local feet, part = w.groundPart(x, z, y + 0.05)
							if part ~= p then
								continue
							end
							n += 1
							c.n += 1
							if not nearNow(x, feet, z) then
								now += 1
								c.now += 1
							end
							if not nearBefore(x, feet, z) then
								bef += 1
								c.before += 1
							end
						end
					end
				end
				missedNow += now
				missedBefore += bef
				table.insert(rows, `{name}: {n} points stood on; no server floor now {now}, before {bef}`)
			end
			Height.configure(nil)
			for _, r in rows do
				print("      " .. r)
			end
			local classes = {}
			for k in byClass do
				table.insert(classes, k)
			end
			table.sort(classes)
			for _, k in classes do
				local c = byClass[k]
				print(`        {k}: {c.n} points; no server floor now {c.now}, before {c.before}`)
			end
			t.truthy(missedBefore > 0, "the round-6 floor ray missed the bough cylinders")
			t.eq(missedNow, 0, "the server's floor ray meets the client's ground on every part of every bake")
		end
	)
end
