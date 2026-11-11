--!strict
-- Ground probe (squirrel motor work, 2026-11-09): what a downward ray actually meets in the built town, against
-- the analytic ground the server AI walks on. Writes the boot terrain, then samples lines at 0.5 st spacing:
-- the colliding-only ray (the client's old probe), the any-part ray (the visible surface), World/Height and
-- World/Ground with pavement. Returns per-line statistics, hit histograms, the samples that leave the analytic
-- ground and one decimated profile; `ok` pins terrain surface = Height on flats and the river at WATER_Y.
--   node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/ground_probe.luau --version <v> --place ci
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local server = SSS:FindFirstChild("Server") :: Instance
local worldGen = server:FindFirstChild("WorldGen") :: Instance
local shared = RS:FindFirstChild("Shared") :: Instance
local function req(parent: Instance, ...: string): any
	local at = parent
	for _, n in { ... } do
		at = at:FindFirstChild(n) or error(`missing {n} under {at:GetFullName()}`)
	end
	return (require :: any)(at)
end
local result: { [string]: any } = { suite = "ground_probe", placeVersion = game.PlaceVersion }
local t0 = os.clock()
local stats = req(worldGen, "WorldTerrain").write(workspace.Terrain)
result.terrainSeconds = os.clock() - t0
result.terrainStats = { seconds = stats.seconds }
-- terrain colliders are built after the write: a ray cast in the same resumption can miss all of it
task.wait(2)
local Height = req(shared, "World", "Height")
local Ground = req(shared, "World", "Ground")
local Town = req(shared, "World", "Town")
local Data = req(shared, "Data")
local town = Town.fromData(Data.default())
local ground = Ground.world({ town = town })

local solid = RaycastParams.new()
solid.FilterType = Enum.RaycastFilterType.Exclude
solid.RespectCanCollide = true
local any = RaycastParams.new()
any.FilterType = Enum.RaycastFilterType.Exclude
any.RespectCanCollide = false

local function label(inst: Instance): string
	if inst:IsA("Terrain") then
		return "Terrain"
	end
	local p = inst.Parent
	local n = string.gsub(inst.Name, "[%d_%.%-]+$", "")
	local pn = if p then string.gsub(p.Name, "[%d_%.%-]+$", "") else "?"
	return `{pn}/{n}`
end

local function line(name: string, x0: number, z0: number, x1: number, z1: number, step: number): any
	local dx, dz = x1 - x0, z1 - z0
	local len = math.sqrt(dx * dx + dz * dz)
	local n = math.floor(len / step)
	local out: { [string]: any } = { name = name, n = n }
	local hist: { [string]: number } = {}
	local histAny: { [string]: number } = {}
	local miss, missAny = 0, 0
	local sumD, maxD, minD = 0, -math.huge, math.huge
	local sumV, maxV, minV = 0, -math.huge, math.huge
	local sumT, maxT, minT, nT = 0, -math.huge, math.huge, 0
	local jumps05, jumps15, jumps30 = 0, 0, 0
	local vjumps05, vjumps15 = 0, 0
	local prev: number?, prevA: number?, prevVis: number? = nil, nil, nil
	local profile: { { any } } = {}
	local anomalies: { { any } } = {}
	for i = 0, n do
		local x, z = x0 + dx * i / n, z0 + dz * i / n
		local h = Height.at(x, z)
		local a = ground.groundAt(x, z, h + 1)
		local from = Vector3.new(x, a + 6, z)
		local r = workspace:Raycast(from, Vector3.new(0, -60, 0), solid)
		local v = workspace:Raycast(from, Vector3.new(0, -60, 0), any)
		local ry: number? = nil
		local vy: number? = nil
		local rl, vl = "-", "-"
		if r then
			ry = r.Position.Y
			rl = label(r.Instance)
			hist[rl] = (hist[rl] or 0) + 1
			local d = r.Position.Y - a
			sumD += d
			maxD = math.max(maxD, d)
			minD = math.min(minD, d)
			if r.Instance:IsA("Terrain") then
				local dt = r.Position.Y - h
				sumT += dt
				nT += 1
				maxT = math.max(maxT, dt)
				minT = math.min(minT, dt)
			end
		else
			miss += 1
		end
		if v then
			vy = v.Position.Y
			vl = label(v.Instance)
			histAny[vl] = (histAny[vl] or 0) + 1
			local d = v.Position.Y - a
			sumV += d
			maxV = math.max(maxV, d)
			minV = math.min(minV, d)
		else
			missAny += 1
		end
		-- sample-to-sample jumps beyond what the analytic slope explains
		if ry and prev and prevA then
			local j = math.abs((ry - prev) - (a - prevA))
			if j > 0.05 then
				jumps05 += 1
			end
			if j > 0.15 then
				jumps15 += 1
			end
			if j > 0.3 then
				jumps30 += 1
			end
		end
		if vy and prevVis and prevA then
			local j = math.abs((vy - prevVis) - (a - prevA))
			if j > 0.05 then
				vjumps05 += 1
			end
			if j > 0.15 then
				vjumps15 += 1
			end
		end
		-- where the colliding ray leaves the analytic ground, or steps beyond what its slope explains
		do
			local off = if ry then ry - a else nil
			local j = if ry and prev and prevA then (ry - prev) - (a - prevA) else 0
			if #anomalies < 40 and ((off and math.abs(off) > 0.2) or math.abs(j) > 0.15) then
				local last = anomalies[#anomalies]
				-- one entry per run of the same label within 3 st
				if not (last and last[6] == rl and math.abs(last[1] - x) + math.abs(last[2] - z) < 3) then
					-- (a row of numbers, words and a flag for the JSON report: the first entry says so to the checker)
					table.insert(anomalies, {
						(math.floor(x * 100) / 100) :: any,
						math.floor(z * 100) / 100,
						math.floor(h * 100) / 100,
						math.floor(a * 100) / 100,
						if ry then math.floor(ry * 100) / 100 else "miss",
						rl,
						math.floor(j * 100) / 100,
						if r then r.Instance:GetFullName() else "-",
						if r then r.Instance.CanCollide else false,
					})
				end
			end
		end
		prev, prevA, prevVis = ry, a, vy
		if i % 4 == 0 and #profile < 160 then
			table.insert(profile, {
				(math.floor(x * 10) / 10) :: any,
				math.floor(z * 10) / 10,
				math.floor(h * 100) / 100,
				math.floor(a * 100) / 100,
				if ry then math.floor(ry * 100) / 100 else "miss",
				rl,
				if vy then math.floor(vy * 100) / 100 else "miss",
				vl,
			})
		end
	end
	local hits = n + 1 - miss
	out.solid = {
		miss = miss,
		meanMinusAnalytic = if hits > 0 then sumD / hits else 0,
		maxMinusAnalytic = maxD,
		minMinusAnalytic = minD,
		jumpsOver005 = jumps05,
		jumpsOver015 = jumps15,
		jumpsOver030 = jumps30,
		hist = hist,
	}
	out.terrainVsHeight = { n = nT, mean = if nT > 0 then sumT / nT else 0, max = maxT, min = minT }
	out.visible = {
		miss = missAny,
		meanMinusAnalytic = if n + 1 - missAny > 0 then sumV / (n + 1 - missAny) else 0,
		maxMinusAnalytic = maxV,
		minMinusAnalytic = minV,
		jumpsOver005 = vjumps05,
		jumpsOver015 = vjumps15,
		hist = histAny,
	}
	out.profile = profile
	out.anomalies = anomalies
	return out
end

-- does a ray meet the terrain at all here?
local test = workspace:Raycast(Vector3.new(500, 200, 500), Vector3.new(0, -400, 0), solid)
result.raycastWorks = test ~= nil
result.testHit = if test then { y = test.Position.Y, inst = test.Instance:GetFullName() } else nil

-- the river: the water surface and (ignoring water) the mud bed, against Height
do
	local wet = RaycastParams.new()
	wet.IgnoreWater = false
	local dry = RaycastParams.new()
	dry.IgnoreWater = true
	local river: { any } = {}
	for x = -2600, 2600, 10 do
		for _, z in { -200, 0, 300 } do
			if Height.insideRiverWater(x, z) and #river < 12 then
				local w = workspace:Raycast(Vector3.new(x, 60, z), Vector3.new(0, -200, 0), wet)
				local d = workspace:Raycast(Vector3.new(x, 60, z), Vector3.new(0, -200, 0), dry)
				table.insert(river, {
					x = x,
					z = z,
					waterY = Height.WATER_Y,
					bedHeight = Height.at(x, z),
					rayWater = if w then w.Position.Y else nil,
					rayWaterMat = if w then w.Material.Name else nil,
					rayBed = if d then d.Position.Y else nil,
					rayBedInst = if d then label(d.Instance) else nil,
				})
			end
		end
	end
	result.river = river
end

local lines: { any } = {}
table.insert(lines, line("street_x0_centre", 0, -300, 0, 300, 0.5))
table.insert(lines, line("street_x0_lane", 8, -300, 8, 300, 0.5))
table.insert(lines, line("sidewalk_x-30", -30.25, -300, -30.25, 300, 0.5))
table.insert(lines, line("across_street_z40", -60, 40, 60, 40, 0.25))
table.insert(lines, line("diagonal_core", -400, -380, 400, 420, 0.5))
table.insert(lines, line("diagonal_outer", -900, 300, -200, -500, 0.5))
table.insert(lines, line("east_hills", 1800, 200, 2200, 320, 0.5))
table.insert(lines, line("estate", -1100, -600, -500, -250, 0.5))
result.lines = lines

-- The pinned part (the town once sat under 2 st of terrain, 2026-11-09): on flat ground the terrain surface
-- is Height.at, the streets' colliding surface is the analytic ground, and the river surface is WATER_Y.
local failures: { string } = {}
local function expect(cond: boolean, what: string)
	if not cond then
		table.insert(failures, what)
	end
end
expect(result.raycastWorks, "a ray meets the terrain")
for _, l in lines do
	if l.name == "across_street_z40" then
		local tv = l.terrainVsHeight
		expect(tv.n > 100, `{l.name}: terrain samples {tv.n}`)
		expect(math.abs(tv.mean) < 0.02 and tv.max < 0.05 and tv.min > -0.05, `{l.name}: terrain - Height {tv.mean}`)
	elseif l.name == "street_x0_centre" or l.name == "sidewalk_x-30" then
		expect(l.solid.miss == 0, `{l.name}: misses {l.solid.miss}`)
		expect(math.abs(l.solid.meanMinusAnalytic) < 0.03, `{l.name}: surface - analytic {l.solid.meanMinusAnalytic}`)
	end
end
local wetSamples = 0
for _, s in result.river do
	if s.rayWaterMat == "Water" then
		wetSamples += 1
		expect(math.abs(s.rayWater - s.waterY) < 0.05, `river surface {s.rayWater} at {s.x},{s.z}`)
	end
end
expect(wetSamples >= 3, `river samples {wetSamples}`)
result.failures = failures
result.ok = #failures == 0
return result
