--!strict
-- tools/games/paintball/arena/views: the review renders' eye points for the paintball arena.
--   lune run tools/games/paintball/arena/views.luau [out.json]        (default build/review/paintball_views.json)
-- Writes a views file for tools/review/render.py (--views): first-person eye points inside WBLW Channel 7, in
-- the arena's frame here and turned into the world's with Arena.PLACE, so the pictures follow the building.
-- The pictures in docs/renders/paintball/ are these views:
--   lune run tools/bake/attractions.luau && lune run tools/review/export.luau
--   lune run tools/games/paintball/arena/views.luau
--   /root/.cache/spicy-rodents/venv/bin/python -I tools/review/render.py --views build/review/paintball_views.json \
--       --out build/review/paintball
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Arena = require("../../../../src/shared/Minigames/Paintball/Arena")
local Body = require("../../../../src/shared/Minigames/Paintball/Body")

local F = Arena.FLOOR_HEIGHT
local EYE = Body.STAND_EYE

-- name, what it shows, the feet point, the point looked at (absolute height), field of view
type View = { name: string, desc: string, feet: { number }, look: { number }, fov: number?, wide: boolean? }
local VIEWS: { View } = {
	{
		name = "pb_01_atrium_floor",
		desc = "Ground floor, standing in the atrium's south-west corner looking up and across: the fallen lighting rig, the galleries and rails of four storeys, the glass roof.",
		feet = { -12, 0, 11 },
		look = { 8, 30, -12 },
		fov = 80,
	},
	{
		name = "pb_02_atrium_top",
		desc = "Fourth floor, at the east rail looking down and across the atrium: the hanging half of the rig, the galleries below, the north stair core's parapet.",
		feet = { 16.8, 4 * F, 8 },
		look = { -14, 26, -8 },
		fov = 80,
	},
	{
		name = "pb_03_dock",
		desc = "Ground floor, the east wing's aisle: the outside-broadcast van, crates, the long look to the dock's wall.",
		feet = { 18, 0, 5 },
		look = { 50, 4, -3 },
	},
	{
		name = "pb_04_newsroom",
		desc = "First floor, the newsroom from the concourse: cubicles, desks, the editor's office behind its windows.",
		feet = { -24, F, -6 },
		look = { -52, F + 3, -18 },
	},
	{
		name = "pb_05_news_set",
		desc = "First floor, the news studio from behind camera two: the desk on its riser, the set wall, the lighting grid.",
		feet = { 4, F, -31 },
		look = { -1, F + 4, -50 },
	},
	{
		name = "pb_06_studio_a",
		desc = "Second floor, Studio A: the stage and its set, three cameras, light stands, the grid of cans overhead.",
		feet = { -20, 2 * F, -35 },
		look = { 4, 2 * F + 4, -52 },
	},
	{
		name = "pb_07_spawn_exit",
		desc = "Second floor, stepping out of the west spawn room's north door into make-up: desks to duck behind, the door to the concourse.",
		feet = { -57.5, 2 * F, -15 },
		look = { -38, 2 * F + 3.5, -24 },
	},
	{
		name = "pb_08_gallery",
		desc = "Second floor, the west concourse looking across the atrium: rails to crouch behind, the far gallery, a set on its cart.",
		feet = { -23, 2 * F, 12 },
		look = { 12, 2 * F + 2, -10 },
	},
	{
		name = "pb_09_stair_core",
		desc = "Second floor, the north core's landing looking up the next flight: open sides, the flight above crossing over.",
		feet = { -13.5, 2 * F, -24 },
		look = { 4, 2 * F + 10, -28 },
		fov = 80,
	},
	{
		name = "pb_10_master_control",
		desc = "Third floor, master control: two rows of consoles facing the wall of dead monitors, racks, the windows onto the concourse.",
		feet = { -35, 3 * F, 16 },
		look = { -56, 3 * F + 4, -6 },
	},
	{
		name = "pb_11_tape_library",
		desc = "Third floor, the tape library: shelving rows with a break half way down, close quarters.",
		feet = { -26, 3 * F, -34 },
		look = { -2, 3 * F + 3.5, -50 },
	},
	{
		name = "pb_12_transmitter",
		desc = "Fourth floor, the transmitter hall: cabinet rows, cable trays to the mast.",
		feet = { -27, 4 * F, -33 },
		look = { 0, 4 * F + 4, -50 },
	},
	{
		name = "pb_13_lobby",
		desc = "The lobby annex from inside the front door: the pass desk and its board, the arena gate, the monitor, the window onto the atrium behind the desk.",
		feet = { -34, 0, 86 },
		look = { -6, 5, 62 },
		fov = 75,
	},
	{
		name = "pb_14_lobby_window",
		desc = "The lobby's east window: reception, the hall door and the atrium floor beyond, as a visitor sees the match.",
		feet = { 29, 0, 63.5 },
		look = { 14, 4, 22 },
	},
	{
		name = "pb_15_outside",
		desc = "The station from the street: five storeys of boarded windows, the annex and its door, the sign, the dead mast.",
		feet = { -95, -6, 185 },
		look = { 0, 62, 10 },
		fov = 62,
		wide = true,
	},
	{
		name = "pb_16_offices",
		desc = "Fourth floor, the offices' corridor: planters to the concourse, office doors.",
		feet = { -37, 4 * F, 12 },
		look = { -44, 4 * F + 4, -20 },
	},
}

local out = process.args[1] or "build/review/paintball_views.json"
local views: { any } = {}
for _, v in VIEWS do
	local px, py, pz = Arena.toWorld(Arena.PLACE, v.feet[1], v.feet[2] + EYE, v.feet[3])
	local lx, ly, lz = Arena.toWorld(Arena.PLACE, v.look[1], v.look[2], v.look[3])
	table.insert(views, {
		name = v.name,
		desc = v.desc,
		pos = { px, py, pz },
		look = { lx, ly, lz },
		fov = v.fov or 70,
		groups = if v.wide then { "attractions", "terrain", "town" } else { "attractions" },
	})
end
local doc = {
	about = "Paintball arena review views (tools/games/paintball/arena/views.luau): first-person eye points, world coordinates.",
	defaults = { res = "960x540", samples = 32, groups = { "attractions" } },
	sun = { dir = { 0.35, 0.8, 0.45 }, strength = 3.2, color = { 1.0, 0.9, 0.76 }, angleDeg = 2, skyStrength = 1.0 },
	views = views,
}
if not fs.isDir("build/review") then
	fs.writeDir("build/review")
end
fs.writeFile(out, serde.encode("json", doc, true))
print(`views: {#views} eye points -> {out}`)
