-- tools/review/pinball_blender/dump.luau: the three pinball tables (Shared/Minigames/Pinball), the cabinet's numbers
-- and the bake's themes and painted words, as one JSON file for draw.py and blockout.py (see draw.py's header).
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local R = "../../../src/shared/Minigames/Pinball/"
local Tables = require(R .. "Tables")
local Layout = require(R .. "Layout")
local Cabinet = require(R .. "Cabinet")
local out = {
	layout = {
		WIDTH = Layout.WIDTH,
		LENGTH = Layout.LENGTH,
		BALL_R = Layout.BALL_R,
		FIELD_X1 = Layout.FIELD_X1,
		XC = Layout.XC,
		LANE_X = Layout.LANE_X,
		ARCH_Y = Layout.ARCH_Y,
		TILT = Layout.TILT_RAD,
	},
	cabinet = {
		PF_Y = Cabinet.PF_Y,
		PF_D = Cabinet.PF_D,
		GLASS_H = Cabinet.GLASS_H,
		RAIL = Cabinet.RAIL,
		BODY = Cabinet.BODY,
		BACKBOX = Cabinet.BACKBOX,
		LEGS = Cabinet.LEGS,
		BUTTON = Cabinet.BUTTON,
		ROD_Y0 = Cabinet.ROD_Y0,
		KNOB = Cabinet.KNOB,
		KNOB_H = Cabinet.KNOB_H,
		PULL_TRAVEL = Cabinet.PULL_TRAVEL,
		FLIPPER_H = Cabinet.FLIPPER_H,
		DROP_SINK = Cabinet.DROP_SINK,
	},
	tables = {},
}
for _, id in Tables.IDS do
	local t = Tables.need(id)
	local d = t.def
	out.tables[id] = {
		title = d.title,
		slopeDeg = d.slopeDeg,
		walls = d.walls,
		posts = d.posts,
		bumpers = d.bumpers,
		slings = d.slings,
		flippers = d.flippers,
		targets = d.targets,
		sensors = d.sensors,
		gates = d.gates,
		saucers = d.saucers,
		rails = d.rails,
		lamps = d.lamps,
		plunger = d.plunger,
		drainY = d.drainY,
	}
end
local Bake = require("../../../tools/bake/games/Pinball")
out.art = Bake.ART
out.themes = Bake.THEMES
local path = process.args[1] or "build/review/pinball_tables.json"
local dir = string.match(path, "^(.*)/[^/]*$")
if dir and not fs.isDir(dir) then
	fs.writeDir(dir) -- (a fresh clone has no build/review yet)
end
fs.writeFile(path, serde.encode("json", out, true))
print("ok")
