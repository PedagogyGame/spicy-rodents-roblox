--!strict
-- tools/bake/games/Paintball: the paintball arena's place in the world (brief v2 §13; checklist PB-5): WBLW
-- Channel 7, the abandoned five-storey TV station on site "f3_tv_station" (the venue's frame in generated/Expansion).
-- OWNED BY THE ARENA LANE of the paintball contract (src/shared/Minigames/Paintball/Contract). The building is DATA
-- (ArenaDataPlan through ArenaData.plan()); tools/games/paintball/arena/PartList turns that data into a list of
-- parts, one for each collision box, the same size in the same place, and this file only makes the Instances:
-- what is drawn solid inside the arena is exactly what a ball stops on, and a spec holds it to that.
-- build is called once for each of paintball's two stations: it builds everything for the arena's own and nothing
-- for the pass desk's prompt (station.joins ~= nil).
-- WHAT THE REST OF PAINTBALL FINDS BY NAME, all under ONE sub-model of the site's Model named Arena.MODEL
-- ("PaintballArena"; attribute Boxes = how many collision boxes it was baked from):
--   Floor0 .. Floor4, Roof   a Model a storey (the building streams in pieces): one Part for each box, with the
--             attribute Box = its index in arena.boxes; an invisible Part "Ramp" for each stair ramp (CanCollide,
--             not CanQuery: bodies walk on it, a raycast passes it); on the middle storey one Part for each
--             spawn-room doorway named Arena.CURTAIN .. team ("Curtain1", "Curtain2": see-through, in the team's
--             colour, CanCollide false; a seated client makes the other team's solid on its own screen).
--   Monitor   every part named Arena.MONITOR (old sets on carts about the floors, master control's wall, one in
--             the lobby): attribute ScreenFace = the NormalId its screen is on, and on that face a SurfaceGui
--             named "Screen" holding one TextLabel "Text" (the station's name until the server writes the score).
--             Inside the volume a monitor is a `prop` box's own part: a ball stops on it.
--   Lobby, Outside   the annex with the pass desk and the two windows onto the atrium, and the building from the
--             street: parts only, all outside the arena volume.
-- Lights are PointLights without shadows inside the strip lights, stage lamps and lobby fittings.
-- Interface: { build(kit, parent, station, venue) }
local Arena = require("../../../src/shared/Minigames/Paintball/Arena")
local ArenaData = require("../../../src/shared/Minigames/Paintball/ArenaData")
local PartList = require("../../games/paintball/arena/PartList")

local Bake = {}

local function make(kit: any, model: any, groups: { [string]: any }, p: PartList.Part): any
	local group = groups[p.group]
	if group == nil then
		group = kit:model(model, p.group)
		groups[p.group] = group
	end
	local roblox = kit.roblox
	local attrs: { [string]: any } = {}
	if p.box then
		attrs.Box = p.box
	end
	if p.screen then
		attrs.ScreenFace = p.screen
	end
	local opts = {
		collide = p.collide,
		query = if p.query == nil then p.collide else p.query,
		shadow = p.shadow,
		transparency = p.transparency,
		rot = if p.tilt then roblox.CFrame.Angles(0, 0, p.tilt) else nil,
		attrs = attrs,
	}
	local part = kit:box(group, p.name, p.x0, p.x1, p.y0, p.y1, p.d0, p.d1, p.color, p.material, opts)
	-- one SurfaceGui a face, whatever is written on it
	local guis: { [string]: any } = {}
	local function gui(face: string): any
		local g = guis[face]
		if g == nil then
			local w = math.max(p.x1 - p.x0, p.y1 - p.y0, p.d1 - p.d0)
			g = kit:gui(part, face, math.clamp(math.floor(900 / w), 8, 50))
			guis[face] = g
		end
		return g
	end
	for _, s in p.signs or {} do
		local props: { [string]: any } = { Text = s.text, TextColor = PartList.TONE[s.tone], Font = "GothamBlack" }
		if s.rect then
			props.Pos = { s.rect[1], s.rect[2] }
			props.Size = { s.rect[3], s.rect[4] }
		end
		if s.bg then
			props.Bg = PartList.TONE[s.bg]
		end
		kit:label(gui(s.face), props)
	end
	if p.screen then
		local screen = gui(p.screen)
		screen.Name = "Screen"
		local label =
			kit:label(screen, { Text = "WBLW 7", TextColor = { 96, 110, 104 }, Bg = { 14, 18, 20 }, Font = "Code" })
		label.Name = "Text"
	end
	if p.light then
		kit:light(
			part,
			"PointLight",
			{ Color = p.light.color, Range = p.light.range, Brightness = p.light.brightness, Shadows = false }
		)
	end
	return part
end

function Bake.build(kit: any, parent: any, station: any, venue: any?)
	if station.joins ~= nil then
		return -- the pass desk's prompt: the desk itself is part of the lobby, built with the arena
	end
	local model = kit:model(parent, Arena.MODEL)
	local plan = ArenaData.plan()
	model:SetAttribute("Boxes", #plan.kinds)
	local groups: { [string]: any } = {}
	for _, p in PartList.solids(plan) do
		make(kit, model, groups, p)
	end
	for _, p in PartList.dressing(venue) do
		make(kit, model, groups, p)
	end
end

return Bake
