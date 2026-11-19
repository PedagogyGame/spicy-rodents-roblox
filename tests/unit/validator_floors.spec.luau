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
			-- the server's floorNear (ValidatorWorld.floor at FLOOR_NEAR over engineRays' down: colliders, terrain, plates)
			local function serverFloorNear(x: number, y: number, z: number): boolean
				local from = y + ValidatorWorld.C.RAY_ABOVE
				local depth = ValidatorWorld.C.RAY_ABOVE + ValidatorWorld.C.FLOOR_NEAR
				if town.raycast(x, from, z, 0, -depth, 0, solid) or town.raycast(x, from, z, 0, -depth, 0, isPlate) then
					return true
				end
				local g = town.terrainAt(x, z)
				return g <= from and g >= from - depth
			end
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
end
