--!strict
-- Luau Execution task script: the paintball arena in the real engine (checklist PB-5). What the Lune specs
-- (tests/unit/paintball_arena_bake.spec.luau) hold in memory, held in a place: the engine's own raycast against
-- the baked parts gives the answer of arena.sweep, so a ball stops where a wall is drawn and nowhere else.
--   1. the model: Workspace has one Model named Arena.MODEL with its storeys, the lobby and the outside;
--   2. the parts: one for every box of ArenaData.build(), where the box is and of its size, solid and seen; a
--      Ramp for every flight (walked on, not ray-cast); curtains that stop nothing; monitors with their Screen;
--   3. the rays: RAYS segments from open points inside the volume, each asked of workspace:Raycast (the arena's
--      model only) and of arena.sweep: the same hit or the same miss, the hit points within TOLERANCE studs and
--      the same face. A ray that grazes an edge may differ; more than GRAZES of them fails the check.
--   4. the paint: every mark of the plan is a label in a SurfaceGui named "Paint" on its box's part; the widest
--      painted face's canvas is reported (numbers.paintCanvas, in pixels: the floors are the largest).
-- NOT YET RUN in the engine: the session that wrote it (2026-11-13) had the cloud tools off limits. It does not
-- walk a body up the stairs: that wants a Humanoid and a player's eye, at the playtest. And one thing only an eye
-- in the place can settle: which way round a Top face's SurfaceGui lies. The bake takes it as the review renders
-- draw it (left to right along the part's X, top to bottom along its Z). Stand on the first floor's gallery and
-- look down: the 7 on the atrium's floor is inside its square frame and the taped T behind each studio camera is
-- behind it; if they are mirrored along z, PartList's rect for "+y" is the one line to change.
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/games/paintball/arena/engine_check.luau --version <v> --place ci
-- (a saved CI place built from ci.project.json with build/Attractions.rbxm baked in)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RAYS = 4000
local TOLERANCE = 0.02
local GRAZES = 8

local shared = ReplicatedStorage:WaitForChild("Shared", 10) :: Instance
local folder = (shared:FindFirstChild("Minigames") :: Instance):FindFirstChild("Paintball") :: Instance
local Arena = (require :: any)(folder:FindFirstChild("Arena"))
local ArenaData = (require :: any)(folder:FindFirstChild("ArenaData"))

local started = os.clock()
local failures: { string } = {}
local function fail(text: string)
	if #failures < 40 then
		table.insert(failures, text)
	end
end

local model: Model? = nil
local models = 0
for _, d in Workspace:GetDescendants() do
	if d:IsA("Model") and d.Name == Arena.MODEL then
		model = d
		models += 1
	end
end
if model == nil then
	error(`no Model named {Arena.MODEL} in Workspace: the place needs build/Attractions.rbxm baked in`)
end
if models ~= 1 then
	fail(`{models} models named {Arena.MODEL}`)
end
for _, name in { "Floor0", "Floor1", "Floor2", "Floor3", "Floor4", "Roof", "Lobby", "Outside" } do
	if model:FindFirstChild(name) == nil then
		fail(`the arena has no {name}`)
	end
end

local arena = ArenaData.build()
local boxes: { number } = arena.boxes
local n = #boxes // 6

-- the arena's frame in this place, from the ground slab's own part (box 1: the whole ground, a stud thick)
local ground: BasePart? = nil
local byBox: { [number]: BasePart } = {}
local ramps, monitors, parts = 0, 0, 0
local curtains = { 0, 0 }
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
		local i = d:GetAttribute("Box")
		if typeof(i) == "number" then
			if byBox[i] ~= nil then
				fail(`box {i} has two parts`)
			end
			byBox[i] = d
			if i == 1 then
				ground = d
			end
		elseif d.Name == "Ramp" then
			ramps += 1
			if not d.CanCollide or d.CanQuery then
				fail("a ramp must be walked on and not ray-cast")
			end
		end
		if d.Name == Arena.MONITOR then
			monitors += 1
			local screen = d:FindFirstChild("Screen")
			if screen == nil or not screen:IsA("SurfaceGui") or screen:FindFirstChild("Text") == nil then
				fail("a monitor has no Screen with its Text")
			end
		end
		for team = 1, 2 do
			if d.Name == Arena.CURTAIN .. team then
				curtains[team] += 1
				if d.CanCollide or d.CanQuery then
					fail(`a curtain of team {team} is solid on the server`)
				end
			end
		end
		if not d.Anchored then
			fail(`{d:GetFullName()} is not anchored`)
		end
	end
end
if ground == nil then
	error("the arena's ground slab (Box = 1) is missing")
end
local gx = ground.CFrame.XVector
local place = {
	x = ground.Position.X,
	y = ground.Position.Y - (boxes[2] + boxes[5]) / 2,
	z = ground.Position.Z,
	yaw = math.atan2(-gx.Z, gx.X),
}

local misplaced = 0
for i = 1, n do
	local part = byBox[i]
	local k = (i - 1) * 6
	if part == nil then
		fail(`box {i} has no part`)
		continue
	end
	local lx, ly, lz = Arena.toLocal(place, part.Position.X, part.Position.Y, part.Position.Z)
	local off = math.max(
		math.abs(lx - (boxes[k + 1] + boxes[k + 4]) / 2),
		math.abs(ly - (boxes[k + 2] + boxes[k + 5]) / 2),
		math.abs(lz - (boxes[k + 3] + boxes[k + 6]) / 2),
		math.abs(part.Size.X - (boxes[k + 4] - boxes[k + 1])),
		math.abs(part.Size.Y - (boxes[k + 5] - boxes[k + 2])),
		math.abs(part.Size.Z - (boxes[k + 6] - boxes[k + 3]))
	)
	if off > 2e-3 then
		misplaced += 1
		fail(`box {i}'s part is {off} studs out`)
	end
	if not part.CanCollide or not part.CanQuery or part.Transparency >= 0.9 then
		fail(`box {i}'s part is not solid and seen`)
	end
end
if ramps ~= #arena.ramps then
	fail(`{ramps} ramps for {#arena.ramps} flights`)
end
if curtains[1] ~= #arena.curtains[1] or curtains[2] ~= #arena.curtains[2] then
	fail(`curtains: {curtains[1]} and {curtains[2]}`)
end

-- the rays
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { model }
params.IgnoreWater = true
local rng = Random.new(20261113)
local cast, hits, grazes, worst = 0, 0, 0, 0
while cast < RAYS do
	local x0 = rng:NextNumber(-Arena.HALF + 1, Arena.HALF - 1)
	local y0 = rng:NextNumber(0.5, Arena.HEIGHT - 0.5)
	local z0 = rng:NextNumber(-Arena.HALF + 1, Arena.HALF - 1)
	if arena.sweep(x0, y0, z0, x0, y0, z0) ~= nil then
		continue -- inside something solid: the engine does not see a part from its inside
	end
	cast += 1
	local dir = rng:NextUnitVector()
	local len = rng:NextNumber(2, 90)
	local x1, y1, z1 = x0 + dir.X * len, y0 + dir.Y * len, z0 + dir.Z * len
	local s, nx, ny, nz = arena.sweep(x0, y0, z0, x1, y1, z1)
	local ox, oy, oz = Arena.toWorld(place, x0, y0, z0)
	local dx, dy, dz = Arena.dirToWorld(place, x1 - x0, y1 - y0, z1 - z0)
	local result = Workspace:Raycast(Vector3.new(ox, oy, oz), Vector3.new(dx, dy, dz), params)
	if (s == nil) ~= (result == nil) then
		-- one of them hit, the other missed: an edge grazed, or a wall that is not where it is drawn
		local at = if s ~= nil then s * len else (result :: RaycastResult).Distance
		if len - at < 0.05 then
			grazes += 1 -- the hit was at the very end of the ray
		else
			grazes += 1
			fail(
				`ray from ({x0}, {y0}, {z0}) to ({x1}, {y1}, {z1}): the data {if s then "hits" else "misses"}, the engine does not agree`
			)
		end
	elseif s ~= nil and result ~= nil then
		hits += 1
		local gap = math.abs(result.Distance - s * len)
		local wx, wy, wz = Arena.dirToWorld(place, nx, ny, nz)
		local sameFace = (result.Normal - Vector3.new(wx, wy, wz)).Magnitude < 1e-3
		if gap > TOLERANCE then
			grazes += 1
			fail(`ray from ({x0}, {y0}, {z0}) to ({x1}, {y1}, {z1}): hit points {gap} studs apart`)
		elseif not sameFace then
			grazes += 1 -- an edge: the same point, the neighbouring face
		end
		worst = math.max(worst, gap)
	end
end
-- the paint
local marks = #ArenaData.plan().marks
local labels, paintCanvas = 0, 0
for _, d in model:GetDescendants() do
	if d:IsA("SurfaceGui") and d.Name == "Paint" then
		labels += #d:GetChildren()
		local face = d.Parent :: BasePart
		paintCanvas =
			math.max(paintCanvas, d.PixelsPerStud * math.max(face.Size.X, face.Size.Y, face.Size.Z))
		if d.LightInfluence ~= 1 then
			fail("paint is lit by the room")
		end
	end
end
if labels ~= marks then
	fail(`{labels} painted labels for {marks} marks`)
end

if grazes > GRAZES then
	fail(`{grazes} of {cast} rays disagree: over {GRAZES}`)
elseif misplaced == 0 and #failures > 0 then
	-- a few grazes are allowed: drop their lines if nothing else failed
	local kept: { string } = {}
	for _, f in failures do
		if string.sub(f, 1, 8) ~= "ray from" then
			table.insert(kept, f)
		end
	end
	failures = kept
end

local ok = #failures == 0
print(`PaintballArena: ok={ok} parts={parts} boxes={n} rays={cast} hits={hits} grazes={grazes} worst={worst}`)
for _, f in failures do
	print(`  FAIL {f}`)
end
return {
	suite = "PaintballArena",
	ok = ok,
	failures = failures,
	numbers = {
		parts = parts,
		boxes = n,
		ramps = ramps,
		monitors = monitors,
		marks = labels,
		paintCanvas = paintCanvas,
		rays = cast,
		hits = hits,
		grazes = grazes,
		worstGap = worst,
	},
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
