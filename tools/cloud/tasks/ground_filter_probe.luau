--!strict
-- Ground filter probe (squirrel motor work, 2026-11-09): what would the client's ground ray stand on if it
-- counted every visible part instead of only colliding ones? Casts both from analytic ground + 1.5 st (as
-- ClientWorld does) over a dense grid of the town and groups the samples where they differ by what the
-- visible ray met, so the ground-ray filter can be chosen from the built world rather than guessed.
--   node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/ground_filter_probe.luau --version <v> --place ci
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
req(worldGen, "WorldTerrain").write(workspace.Terrain)
task.wait(2)
local Height = req(shared, "World", "Height")
local Ground = req(shared, "World", "Ground")
local Town = req(shared, "World", "Town")
local Data = req(shared, "Data")
local ground = Ground.world({ town = Town.fromData(Data.default()) })

local solid = RaycastParams.new()
solid.FilterType = Enum.RaycastFilterType.Exclude
solid.RespectCanCollide = true
local any = RaycastParams.new()
any.FilterType = Enum.RaycastFilterType.Exclude
any.RespectCanCollide = false

local function strip(s: string): string
	return (string.gsub(s, "[%d_%.%-]+$", ""))
end
local function label(inst: Instance): string
	if inst:IsA("Terrain") then
		return "Terrain"
	end
	local parts = {}
	local at: Instance? = inst
	while at and at ~= workspace and #parts < 4 do
		table.insert(parts, 1, strip(at.Name))
		at = at.Parent
	end
	return table.concat(parts, "/")
end

type Row = {
	n: number,
	sum: number,
	min: number,
	max: number,
	collide: boolean,
	transparency: number,
	sizeY: number,
	ex: { number },
	full: string,
}
local function grid(x0: number, x1: number, z0: number, z1: number, step: number): any
	local rows: { [string]: Row } = {}
	local n, same, solidMiss, anyMiss = 0, 0, 0, 0
	local solidVsAnalytic: { [string]: Row } = {}
	for x = x0, x1, step do
		for z = z0, z1, step do
			n += 1
			local h = Height.at(x, z)
			local a = ground.groundAt(x, z, h + 1)
			local from = Vector3.new(x + 0.137, a + 1.5, z + 0.219)
			local r = workspace:Raycast(from, Vector3.new(0, -400, 0), solid)
			local v = workspace:Raycast(from, Vector3.new(0, -400, 0), any)
			if not r then
				solidMiss += 1
			end
			if not v then
				anyMiss += 1
			end
			if r and v then
				local d = v.Position.Y - r.Position.Y
				if math.abs(d) <= 0.02 then
					same += 1
				else
					local key = label(v.Instance) .. " over " .. label(r.Instance)
					local row = rows[key]
					if not row then
						local p = v.Instance :: BasePart
						row = {
							n = 0,
							sum = 0,
							min = math.huge,
							max = -math.huge,
							collide = p.CanCollide,
							transparency = p.Transparency,
							sizeY = p.Size.Y,
							ex = { math.floor(from.X), math.floor(v.Position.Y * 100) / 100, math.floor(from.Z) },
							full = p:GetFullName(),
						}
						rows[key] = row
					end
					row.n += 1
					row.sum += d
					row.min = math.min(row.min, d)
					row.max = math.max(row.max, d)
				end
				-- what the colliding ray stands on that is not the analytic ground (props, floors, cars)
				local da = r.Position.Y - a
				if math.abs(da) > 0.25 then
					local key = label(r.Instance)
					local row = solidVsAnalytic[key]
					if not row then
						local p = r.Instance :: BasePart
						row = {
							n = 0,
							sum = 0,
							min = math.huge,
							max = -math.huge,
							collide = true,
							transparency = if p:IsA("Terrain") then 0 else p.Transparency,
							sizeY = if p:IsA("Terrain") then 0 else p.Size.Y,
							ex = { math.floor(from.X), math.floor(r.Position.Y * 100) / 100, math.floor(from.Z) },
							full = p:GetFullName(),
						}
						solidVsAnalytic[key] = row
					end
					row.n += 1
					row.sum += da
					row.min = math.min(row.min, da)
					row.max = math.max(row.max, da)
				end
			end
		end
	end
	local function list(t: { [string]: Row }): { any }
		local out = {}
		for k, row in t do
			table.insert(out, {
				key = k,
				n = row.n,
				mean = math.floor(row.sum / row.n * 100) / 100,
				min = math.floor(row.min * 100) / 100,
				max = math.floor(row.max * 100) / 100,
				collide = row.collide,
				transparency = row.transparency,
				sizeY = math.floor(row.sizeY * 100) / 100,
				ex = row.ex,
				full = row.full,
			})
		end
		table.sort(out, function(p, q)
			return p.n > q.n
		end)
		while #out > 70 do
			table.remove(out)
		end
		return out
	end
	return {
		n = n,
		same = same,
		solidMiss = solidMiss,
		anyMiss = anyMiss,
		visibleDiffers = list(rows),
		solidOffAnalytic = list(solidVsAnalytic),
	}
end

local result: { [string]: any } = { suite = "ground_filter_probe", placeVersion = game.PlaceVersion }
result.core = grid(-640, 640, -560, 560, 2.5)
result.outer = grid(-1500, 2600, -1300, 1050, 11)
local top: { string } = {}
for _, c in workspace:GetChildren() do
	table.insert(top, c.Name .. ":" .. c.ClassName)
end
result.workspace = top
local town = workspace:FindFirstChild("Town")
if town then
	local kids: { string } = {}
	for _, c in town:GetChildren() do
		table.insert(kids, c.Name .. ":" .. #c:GetChildren())
	end
	result.town = kids
end
return result
