--!strict
-- tools/games/paintball/arena/views: the review renders' eye points for the paintball arena.
--   lune run tools/games/paintball/arena/views.luau [out.json]        (default build/review/paintball_views.json)
-- Writes a views file for tools/review/render.py (--views): first-person eye points inside WBLW Channel 7, in
-- the arena's frame here and turned into the world's with Arena.PLACE, so the pictures follow the building.
-- The pictures in docs/renders/paintball/ are these views:
--   lune run tools/bake/main.luau && lune run tools/bake/editor_ground.luau && lune run tools/bake/attractions.luau
--   lune run tools/review/export.luau
--   lune run tools/games/paintball/arena/views.luau
--   /root/.cache/spicy-rodents/venv/bin/python -I tools/games/paintball/arena/render.py \
--       --views build/review/paintball_views.json --out build/review/paintball
-- (render.py beside this file is tools/review/render.py with the engine's indoor light put back: its header.)
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Arena = require("../../../../src/shared/Minigames/Paintball/Arena")
local Body = require("../../../../src/shared/Minigames/Paintball/Body")

local F = Arena.FLOOR_HEIGHT
local EYE = Body.STAND_EYE

-- name, what it shows, the feet point, the point looked at (absolute height), field of view.
-- wide: with the town and the terrain; then the feet stand on the terrain there and the look's height is above
-- the terrain under it. air: not an eye point; `feet` is the camera itself, above the arena's floor.
type View = {
	name: string,
	desc: string,
	feet: { number },
	look: { number },
	fov: number?,
	wide: boolean?,
	air: boolean?,
}
local VIEWS: { View } = {
	{
		name = "pb_01_atrium_floor",
		desc = "Ground floor, the atrium's floor from its south-east corner: the fallen lighting rig and its cans, crates, the north stair core's first flight, the first gallery's rail overhead.",
		feet = { 13.5, 0, 13.5 },
		look = { -6, 4.5, -9 },
		fov = 80,
	},
	{
		name = "pb_02_atrium_up",
		desc = "Ground floor, looking up the atrium from its south-west corner: four storeys of galleries and rails, cables down the corners, the hanging half of the rig, the glass roof and the mast through it.",
		feet = { -10.5, 0, 12 },
		look = { 6, 30, -10 },
		fov = 85,
	},
	{
		name = "pb_03_atrium_top",
		desc = "Fourth floor, at the gap in the north rail looking across and down the atrium: the hanging rig, the galleries of the storeys below, the test card on the south core.",
		feet = { 10, 4 * F, -16.6 },
		look = { -9, 36, 15 },
		fov = 85,
	},
	{
		name = "pb_04_dock",
		desc = "Ground floor, the east wing's aisle from the concourse: the outside-broadcast van, crates, the dock's wall.",
		feet = { 31, 0, 5.5 },
		look = { 52, 4.5, -5 },
	},
	{
		name = "pb_05_newsroom",
		desc = "First floor, the newsroom's north bay: cubicles and dead terminals, the stopped clocks and the day's board on the editor's wall, a boarded window in the west wall.",
		feet = { -32, F, -27.5 },
		look = { -55, F + 5, -10 },
		fov = 78,
	},
	{
		name = "pb_06_news_set",
		desc = "First floor, the news studio from between the cameras: the desk on its riser, the set wall, the lighting grid.",
		feet = { 6.5, F, -33 },
		look = { -1, F + 4.5, -52 },
		fov = 75,
	},
	{
		name = "pb_07_studio_a",
		desc = "Second floor, Studio A: the stage and its set, three cameras, light stands, the grid of cans overhead.",
		feet = { -20, 2 * F, -35 },
		look = { 4, 2 * F + 4, -52 },
	},
	{
		name = "pb_08_spawn_exit",
		desc = "Second floor, stepping out of the west spawn room's north door into make-up: desks to duck behind, the door to the concourse.",
		feet = { -57.5, 2 * F, -15 },
		look = { -38, 2 * F + 3.5, -24 },
	},
	{
		name = "pb_09_spawn_room",
		desc = "Second floor, inside the west spawn room at a spawn point: the baffle wall with the room's name, the gap at its end that leads to the south door, the team's colour.",
		feet = { -46, 2 * F, -2.5 },
		look = { -57, 2 * F + 4.5, 5 },
		fov = 80,
	},
	{
		name = "pb_10_gallery",
		desc = "Second floor, the west concourse looking across the atrium: rails to crouch behind, the far gallery, the north core's parapet and stair.",
		feet = { -23, 2 * F, 12 },
		look = { 12, 2 * F + 2, -10 },
	},
	{
		name = "pb_11_stair_core",
		desc = "Second floor, the north core's landing looking up the next flight: open sides, the flight above crossing over.",
		feet = { -13.5, 2 * F, -24 },
		look = { 4, 2 * F + 10, -28 },
		fov = 80,
	},
	{
		name = "pb_12_master_control",
		desc = "Third floor, master control: two rows of consoles facing the wall of dead monitors, racks, the windows onto the concourse.",
		feet = { -35, 3 * F, 16 },
		look = { -56, 3 * F + 4, -6 },
	},
	{
		name = "pb_13_tape_library",
		desc = "Third floor, the tape library: shelving rows with a break half way down, close quarters.",
		feet = { -26, 3 * F, -34 },
		look = { -2, 3 * F + 3.5, -50 },
	},
	{
		name = "pb_14_transmitter",
		desc = "Fourth floor, the transmitter hall: cabinet rows, cable trays to the mast.",
		feet = { -20.5, 4 * F, -33 },
		look = { -3, 4 * F + 4, -50 },
	},
	{
		name = "pb_15_offices",
		desc = "Fourth floor, the offices' corridor: planters to the concourse, office doors.",
		feet = { -37, 4 * F, 12 },
		look = { -44, 4 * F + 4, -20 },
	},
	{
		name = "pb_20_test_card",
		desc = "Third floor, the south gallery looking north across the atrium: the test card on the north core's front, the rails, the galleries either side.",
		feet = { 3, 3 * F, 18.3 },
		look = { -1, 3 * F + 5, -21 },
		fov = 75,
	},
	{
		name = "pb_21_wardrobe",
		desc = "Second floor, wardrobe, outside the west spawn room's south door: the costume rail, cases, the team's curtain in the doorway.",
		feet = { -38, 2 * F, 27 },
		look = { -54, 2 * F + 3.5, 17 },
	},
	{
		name = "pb_16_lobby",
		desc = "The lobby annex from inside the front door: the pass desk and its board, the arena gate, the monitor, the window onto the atrium behind the desk.",
		feet = { -34, 0, 86 },
		look = { -6, 5, 62 },
		fov = 75,
	},
	{
		name = "pb_17_lobby_window",
		desc = "The lobby's east window, as a visitor sees the match: through reception and the hall's wide doorway, up the east concourse and across that side of the atrium's floor.",
		feet = { 24, 0, 62.4 },
		look = { 19.5, 4, 0 },
		fov = 72,
	},
	{
		name = "pb_22_desk_window",
		desc = "At the pass desk: the counter and its card, and behind it the west window onto the concourse and the atrium.",
		feet = { -21, 0, 80 },
		look = { -22, 4, 30 },
		fov = 70,
	},
	{
		name = "pb_23_atrium_down",
		desc = "First floor, at the gap in the east rail looking down into the atrium: the station's number painted on the floor, the fallen rig either side of it, its cables.",
		feet = { 16.6, F, 10 },
		look = { -3, 0, -4 },
		fov = 85,
	},
	{
		name = "pb_18_outside",
		desc = "The station from the street: five storeys of boarded windows, the annex and its door, the sign, the dead mast.",
		feet = { -70, 0, 190 },
		look = { 0, 60, 0 },
		fov = 62,
		wide = true,
	},
	{
		name = "pb_19_from_the_air",
		desc = "Not an eye point: the whole building from the south-east and above, to read the massing, the annex, the roof with its glass and the mast.",
		feet = { 150, 110, 190 },
		look = { 0, 40, 0 },
		fov = 50,
		wide = true,
		air = true,
	},
}

local out = process.args[1] or "build/review/paintball_views.json"
local views: { any } = {}
for _, v in VIEWS do
	local px, py, pz = Arena.toWorld(Arena.PLACE, v.feet[1], v.feet[2] + (if v.air then 0 else EYE), v.feet[3])
	local lx, ly, lz = Arena.toWorld(Arena.PLACE, v.look[1], v.look[2], v.look[3])
	-- outdoors on foot: tools/review/render.py adds the terrain's height under each point (aboveGround)
	local onFoot = v.wide == true and v.air ~= true
	table.insert(views, {
		name = v.name,
		desc = v.desc,
		pos = { px, if onFoot then v.feet[2] + EYE else py, pz },
		look = { lx, if onFoot then v.look[2] else ly, lz },
		aboveGround = if onFoot then true else nil,
		fov = v.fov or 70,
		groups = if v.wide then { "attractions", "terrain", "town" } else { "attractions" },
	})
end
local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
for _, c in { { -62, -2, -62 }, { 62, 76, -62 }, { -62, -2, 92 }, { 62, 76, 92 } } do
	local w = { Arena.toWorld(Arena.PLACE, c[1], c[2], c[3]) }
	for k = 1, 3 do
		lo[k], hi[k] = math.min(lo[k], w[k]), math.max(hi[k], w[k])
	end
end
local doc = {
	about = "Paintball arena review views (tools/games/paintball/arena/views.luau): first-person eye points, world coordinates.",
	defaults = { res = "960x540", samples = 24, groups = { "attractions" } },
	sun = { dir = { 0.35, 0.8, 0.45 }, strength = 3.2, color = { 1.0, 0.9, 0.76 }, angleDeg = 2, skyStrength = 1.0 },
	-- for render.py beside this file: the box (world) whose lights are the arena's, and Lighting.Ambient
	-- (LightingPreset.GOLDEN.ambient, #6b6a5a: 0.14 linear, times pi for a sun's strength)
	indoor = { min = lo, max = hi },
	ambient = { strength = 0.44, color = { 1.0, 0.99, 0.84 } },
	views = views,
}
if not fs.isDir("build/review") then
	fs.writeDir("build/review")
end
fs.writeFile(out, serde.encode("json", doc, true))
print(`views: {#views} eye points -> {out}`)
