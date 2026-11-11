--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.Tables
-- The alley's three pinball machines by game id (the ids AlleyLayout.stations() gives the three cabinets):
-- pinball_acorn (ACORN ATTACK), pinball_rodent (SPICY RODENT), pinball_space (SPACE SQUIRREL). One physics
-- core, three playfields, three rule sheets (checklist PIN-R6).
-- Pure; Lune-tested (tests/unit/pinball_layout.spec.luau).
-- Interface: IDS (in cabinet order); get(id) -> Machine.Table?; need(id) -> Machine.Table (errors on an unknown id)

local Machine = require("./Machine")
local TableAcorn = require("./TableAcorn")
local TableSpace = require("./TableSpace")
local TableSpicy = require("./TableSpicy")

local Tables = {}

Tables.IDS = { "pinball_acorn", "pinball_rodent", "pinball_space" }

local BY_ID: { [string]: Machine.Table } = {
	pinball_acorn = TableAcorn,
	pinball_rodent = TableSpicy,
	pinball_space = TableSpace,
}

function Tables.get(id: string): Machine.Table?
	return BY_ID[id]
end

function Tables.need(id: string): Machine.Table
	local t = BY_ID[id]
	assert(t, `no pinball table {id}`)
	return t
end

return Tables
