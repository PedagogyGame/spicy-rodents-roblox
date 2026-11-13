--!strict
-- tools/games/pool/review_scene.luau: the cue-sport tables alone, as a scene for the offline renderer
-- (tools/review/render.py), so the baked hardware can be LOOKED AT without Studio and without rendering the
-- whole town. It builds the pool tables and the bumper pool table through the bake registry (the same code
-- tools/bake/attractions.luau runs), on a bare floor at the origin, and writes
--   <out>/tables.rbxm   the Models as baked
--   <out>/scene.json    the parts, lights and SurfaceGui text (tools/review/attractions_export.luau)
--   <out>/views.json    eye points worked out from the tables' own numbers (Shared/Minigames/Pool/Furniture,
--                       Tables): the shooter's stance, the cue view, straight down from above, a corner
--                       pocket with the rack, the tray; the bumper pool table from its end and from above
-- With "play" a table is shown as a game leaves it (a spread of balls, some down in the tray) instead of an
-- idle rack. Usage, from the repo root:
--   lune run tools/games/pool/review_scene.luau [out dir, default build/review_pool] [play]
--   /root/.cache/spicy-rodents/venv/bin/python -I tools/review/render.py --scene <out>/scene.json \
--       --views <out>/views.json --out <out>
-- Interface: a script; writes the three files and prints what it wrote.

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")
local Furniture = require("../../../src/shared/Minigames/Pool/Furniture")
local Games = require("../../../src/shared/Minigames/Games")
local Tables = require("../../../src/shared/Minigames/Pool/Tables")
local GameBakes = require("../../bake/GameBakes")
local Kit = require("../../bake/alley/Kit")
local attractionsExport = require("../../review/attractions_export")

local OUT = process.args[1] or "build/review_pool"
local PLAY = process.args[2] == "play"
local PLACE: AlleyLayout.Place = { x = 0, z = 0, floorY = 0, yaw = 0 }

local kit = Kit.new(roblox, PLACE)
local root = roblox.Instance.new("Model")
root.Name = "PoolReview"
local room = kit:model(root, "GamesRoom")
local stations: { any } = {}
for _, st in Games.stations({ bowling_alley = PLACE }) do
	if st.game == "pool" or st.game == "bumper_pool" then
		GameBakes.build(st.game, kit, room, st, nil)
		table.insert(stations, st)
	end
end

-- a floor under everything and a wall behind, so the tables stand somewhere
local minX, maxX, minD, maxD = math.huge, -math.huge, math.huge, -math.huge
for _, st in stations do
	minX, maxX = math.min(minX, st.x - 14), math.max(maxX, st.x + 14)
	minD, maxD = math.min(minD, st.d - 16), math.max(maxD, st.d + 16)
end
kit:box(root, "Floor", minX, maxX, -0.5, 0, minD, maxD, { 92, 70, 58 }, "Wood")

-- a table as a game leaves it: balls spread, a few down (their Models moved as the server's hardware does)
local function spread(st: any)
	local model = room:FindFirstChild(Furniture.modelName(st.game, st.index))
	if model == nil then
		return
	end
	local tb = if st.game == "pool" then Tables.eightBall() else Tables.bumper()
	local lie: { [number]: { number } } = {}
	local down: { number }
	if st.game == "pool" then
		lie = {
			[0] = { -0.9, -2.3 },
			[1] = { 1.2, 0.4 },
			[2] = { -1.6, 3.1 },
			[4] = { 2.2, -1.2 },
			[6] = { -0.3, 1.5 },
			[8] = { 0.6, 2.9 },
			[9] = { 1.9, 4.4 },
			[10] = { -2.1, -0.7 },
			[12] = { 0.2, -0.4 },
			[13] = { -1.1, 4.7 },
			[15] = { 2.3, 2.2 },
		}
		down = { 3, 5, 7, 11, 14 }
	else
		lie = {
			[1] = { 0.5, 1.4 },
			[2] = { -1.3, -1.9 },
			[4] = { -1.5, 0.9 },
			[6] = { -0.7, -1.2 },
			[7] = { 1.2, 2.3 },
			[8] = { 1.4, -0.6 },
			[10] = { -0.2, 0.2 },
		}
		down = { 3, 5, 9 }
	end
	local function move(id: number, x: number, y: number, z: number)
		local ball = model:FindFirstChild(Furniture.ballName(id))
		if ball then
			local wx, wy, wz = Furniture.world(PLACE, st, x, y, z)
			-- (a turn of its own for each, as balls lie after a game)
			-- (Lune's instances have no PivotTo: every part is carried by the move of the Skin, the pivot)
			local skin = ball:FindFirstChild("Skin")
			if skin then
				local to = roblox.CFrame.new(wx, wy, wz) * roblox.CFrame.Angles(id * 0.9, id * 1.7, id * 0.4)
				local by = to * skin.CFrame:Inverse()
				for _, p in ball:GetDescendants() do
					if p:IsA("BasePart") then
						p.CFrame = by * p.CFrame
					end
				end
			end
		end
	end
	for id, at in lie do
		move(id, at[1], tb.ballR, at[2])
	end
	for _, id in down do
		local x, y, z = Furniture.home(tb, id)
		move(id, x, y, z)
	end
end
if PLAY then
	for _, st in stations do
		spread(st)
	end
end

if not fs.isDir(OUT) then
	fs.writeDir(OUT)
end
local rbxm = `{OUT}/tables.rbxm`
fs.writeFile(rbxm, roblox.serializeModel({ root }))
local scene: { [string]: any } = { version = 1, parts = {}, stats = { groups = {} } }
attractionsExport(scene, rbxm)
fs.writeFile(`{OUT}/scene.json`, serde.encode("json", scene, false))

-- the views: every eye point from the tables' own numbers
local views: { any } = {}
local function world(st: any, x: number, y: number, z: number): { number }
	local wx, wy, wz = Furniture.world(PLACE, st, x, y, z)
	return { wx, wy, wz }
end
local function view(name: string, desc: string, pos: { number }, look: { number }, fov: number, up: { number }?)
	table.insert(views, { name = name, desc = desc, pos = pos, look = look, fov = fov, up = up })
end
for _, st in stations do
	local tb = if st.game == "pool" then Tables.eightBall() else Tables.bumper()
	local hw, hl = Furniture.outer(tb)
	local tag = if st.game == "pool" then `pool{st.index}` else "bumper"
	if st.game == "pool" and st.index ~= 1 then
		continue
	end
	-- the shooter's stance at the head of the table: eyes of a person standing behind the head rail
	view(
		`{tag}_stance`,
		"A player's eyes standing behind the head rail, looking down the table.",
		world(st, 0, 2.3, -(hl + Furniture.STAND + 0.6)),
		world(st, 0, 0, hl * 0.25),
		62
	)
	-- the cue view: low behind a ball on the head spot (the controller's camera)
	view(
		`{tag}_cue`,
		"The cue view: low behind the ball on the head spot, looking up the table.",
		world(st, 0, 1.75 + tb.ballR, tb.headZ - 3.4),
		world(st, 0, tb.ballR, tb.headZ + 3.2),
		58
	)
	view(
		`{tag}_top`,
		"Straight down from above the table (the top view), the head on the left.",
		world(st, 0, 7.6, 0),
		world(st, 0, 0, 0),
		if st.game == "pool" then 72 else 50,
		{ -1, 0, 0 }
	)
	view(
		`{tag}_corner`,
		"A corner pocket close up, from the side of the table, with the rack behind.",
		world(st, -(hw + 1.6), 1.5, hl * 0.55),
		world(st, -hw + 0.3, 0, hl - 0.2),
		50
	)
	view(
		`{tag}_side`,
		"From the side, a step back: the whole table, the lamp, the legs.",
		world(st, -(hw + 7.5), 2.6, -1),
		world(st, 0, 0.6, 0),
		60
	)
	view(
		`{tag}_tray`,
		"The foot end and the tray where potted balls collect.",
		world(st, 1.2, 0.9, hl + 3.2),
		world(st, 0, -0.5, hl),
		55
	)
	if st.game == "pool" then
		view(
			`{tag}_side_pocket`,
			"A side pocket and its jaws, close.",
			world(st, hw * 0.1, 1.3, 1.5),
			world(st, hw - 0.3, 0, 0),
			45
		)
	end
end
local doc = {
	about = "Views of the cue-sport tables alone (tools/games/pool/review_scene.luau). Roblox coordinates, studs.",
	defaults = { res = "960x540", samples = 32, groups = { "attractions" } },
	sun = { dir = { 0.35, 0.8, -0.3 }, strength = 2.4, color = { 1.0, 0.94, 0.86 }, angleDeg = 8, skyStrength = 0.9 },
	views = views,
}
fs.writeFile(`{OUT}/views.json`, serde.encode("json", doc, true))
print(`pool review: {#stations} tables, {kit.count} parts, {#views} views -> {OUT}/scene.json, views.json`)
