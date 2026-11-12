--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.Tables
-- The alley's three pinball machines by game id (the ids AlleyLayout.stations() gives the three cabinets):
-- pinball_acorn (ACORN ATTACK), pinball_rodent (SPICY RODENT), pinball_space (SPACE SQUIRREL). One physics
-- core, three playfields, three rule sheets (checklist PIN-R6).
-- Pure; Lune-tested (tests/unit/pinball_layout.spec.luau).
-- The minigame registry knows them as ONE game, "pinball", whose stations carry the theme as `variant`
-- (AlleyLayout.PINBALLS: acorn, rodent, space): VARIANTS maps a variant to its table id.
-- Interface: IDS (in cabinet order); VARIANTS; get(id) -> Machine.Table?; need(id) -> Machine.Table (errors on
--   an unknown id); forVariant(variant) -> table id?

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

Tables.VARIANTS =
	{ acorn = "pinball_acorn", rodent = "pinball_rodent", space = "pinball_space" } :: { [string]: string }

-- forVariant(variant): the table id for a station's variant (a table id is also taken as it is).
function Tables.forVariant(variant: any): string?
	if type(variant) ~= "string" then
		return nil
	end
	if BY_ID[variant] then
		return variant
	end
	return Tables.VARIANTS[variant]
end

function Tables.get(id: string): Machine.Table?
	return BY_ID[id]
end

function Tables.need(id: string): Machine.Table
	local t = BY_ID[id]
	assert(t, `no pinball table {id}`)
	return t
end

return Tables
