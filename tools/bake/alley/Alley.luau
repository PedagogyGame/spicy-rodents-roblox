--!strict
-- tools/bake/alley/Alley: the whole bowling alley, in the order its pieces are built (tools/bake/attractions.luau
-- and the bake's own spec, tests/unit/attractions_alley_bake.spec.luau, both come through here, so what is
-- tested is what is written to build/Attractions.rbxm):
--   Shell       the structure in front of the back module: foundation, the nine tunnels, floors, walls with
--               every opening of the plan, ceilings, roof, house lights, terrain carve boxes
--   Lanes       eighteen lanes in nine pairs: beds, pins, sweeps, balls, masking, returns, approaches, settees,
--               scoreboards
--   Concourse   plain counters in the serving openings, signs, the snack tables, the house balls
--   GamesRoom   the games' furniture at the plan's places, the dartboard, the fortune teller, the room's dressing
--   BackModule  the interim back of house (corridor, stand-in pinsetters, rear wall and exit, rear alley): the
--               owner's backstage replaces it whole
--   Forecourt   the landing, the ramp, the pylon sign
--   the roof run (BRIEF_ADDENDUM D9, D10; Shared/Attractions/AlleyRoof):
--   Yard        the house and the tree behind the games wing, in the attraction's annex (data/attractions.json)
-- Interface: build(kit, root, data) -> nothing (data: the attraction's record of data/attractions.json)

local Shell = require("./Shell")
local Lanes = require("./Lanes")
local Concourse = require("./Concourse")
local GamesRoom = require("./GamesRoom")
local BackModule = require("./BackModule")
local Forecourt = require("./Forecourt")
local Yard = require("./Yard")

local Alley = {}

function Alley.build(kit: any, root: any, data: any)
	Shell.build(kit, root, data)
	Lanes.build(kit, root)
	Concourse.build(kit, root)
	GamesRoom.build(kit, root)
	BackModule.build(kit, root)
	Forecourt.build(kit, root, data)
	Yard.build(kit, root)
end

return Alley
