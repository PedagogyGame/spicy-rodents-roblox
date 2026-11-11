--!strict
-- ServerScriptService.Server.WorldGen.Builders.Interior
-- Interior builder (BUILD_PLAN §3.4, §4.4 #7): an interior template from data/interiors/*.json placed
-- inside the real shell of its house (worldgen_core §16: nobody teleports). Rooms are fractional
-- rects of the footprint; the Shell builds the floor, exterior walls with the front and back
-- openings, partitions, server-owned doors, room volumes and the room graph; Builders/Furnish dresses
-- every room for its purpose (the template's own furniture keeps its name, Furniture_<id>, its hide
-- type and a place as near its template spot as the doors allow; the room's recipe adds the rest:
-- floors, wall linings, a ceiling, lights, curtains, pictures). This also adds the hide spots
-- (behind/under/inside), the defender spawn, the burglar entry and the squirrel-route sockets (template
-- routes are W3), then the gable roof on top.
-- Interface: build(ctx) (ctx.interior is the template). Pure.

local Building = require("./Building")
local Furnish = require("./Furnish")
local Shell = require("./Shell")
local Spec = require("../Spec")

local Interior = {}

-- One colour set per home (Furniture.TONES).
local TONES: { [string]: string } = {
	frb_victorian = "victorian",
	frb_bungalow = "bungalow",
	frb_brick = "brick",
	frb_cottage = "cottage",
}

function Interior.build(ctx: Spec.LotCtx)
	local tpl = ctx.interior :: any
	local W, D, spu = ctx.W, ctx.D, Spec.SPU
	local function mx(fx: number): number
		return (fx - 0.5) * W
	end
	local function mz(fz: number): number
		return -(fz - 0.5) * D
	end
	local rooms: { Shell.Room } = {}
	for _, r in tpl.rooms do
		table.insert(rooms, {
			id = r.id,
			name = r.name,
			x0 = mx(r.rect[1]),
			x1 = mx(r.rect[2]),
			z0 = mz(r.rect[4]),
			z1 = mz(r.rect[3]),
			kind = Furnish.roomKind("house", r.id),
		})
	end
	local doors: { Shell.Door } = {}
	for _, d in tpl.doors do
		table.insert(
			doors,
			{ id = d.id, a = d.a, b = d.b, x = mx(d.at[1]), z = mz(d.at[2]), w = d.width * spu, lockable = d.lockable }
		)
	end
	local eave, peak, _kind, alongX = Building.heights(ctx)
	local floorTop = (tpl.floorU or 0.13) * spu
	local thick = tpl.wallU * spu
	local layout: Shell.Layout = {
		rooms = rooms,
		doors = doors,
		wallH = eave,
		partH = eave - floorTop,
		doorH = tpl.doorHeightU * spu,
		thick = thick,
		floorTop = floorTop,
		roof = "none",
		extras = {},
	}

	-- the rooms are laid out first: the room graph needs to know where the hide spots end up
	local pins: { [string]: { Furnish.Pin } } = {}
	for _, f in tpl.furniture do
		pins[f.room] = pins[f.room] or {}
		table.insert(pins[f.room], {
			id = "Furniture_" .. f.id,
			kind = Furnish.KIT_KIND[f.kit] or "bookshelf",
			x = mx(f.at[1]),
			z = mz(f.at[2]),
			hide = f.hide,
			w = if f.kit == "counter" then math.clamp(f.size[1] * spu, 8, 12) else nil,
			seats = if f.kit == "table" then 6 else nil,
		})
	end
	local infoRooms = {}
	for _, r in rooms do
		table.insert(infoRooms, { id = r.id, kind = r.kind :: string, x0 = r.x0, x1 = r.x1, z0 = r.z0, z1 = r.z1 })
	end
	local plan = Furnish.plan(ctx, {
		building = "house",
		tones = TONES[tpl.id] or "bungalow",
		rooms = infoRooms,
		doors = doors,
		thick = thick,
		partition = math.max(thick * 0.6, 0.3),
		floorTop = floorTop,
		ceiling = math.min(Furnish.CEILING, eave - floorTop - 0.5),
		doorH = tpl.doorHeightU * spu,
		grid = Shell.grid(ctx, layout),
		pins = pins,
		discs = {},
	})
	local hides = Furnish.hideSpots(plan)
	for _, h in hides do
		table.insert(
			layout.extras,
			{ id = "hide_" .. string.sub(h.id, 11), kind = "hide", room = h.room, x = h.x, z = h.z }
		)
	end

	Shell.build(ctx, layout)
	if peak > eave + 0.05 then
		Building.roof(ctx, eave, peak, alongX)
	end
	Building.dress(ctx, eave, peak, false, false)
	Furnish.emit(ctx, plan)
	for _, h in hides do
		ctx.list:extra({
			kind = "Attachment",
			part = "Nav",
			name = "Hide_" .. string.sub(h.id, 11),
			offset = { h.x, 0, h.z },
			attrs = { HideType = h.hide, Room = h.room } :: Spec.Attrs,
		})
	end
	local ds = tpl.defenderSpawn
	ctx.list:extra({
		kind = "Attachment",
		part = "Nav",
		name = "DefenderSpawn",
		offset = { mx(ds.at[1]), 0, mz(ds.at[2]) },
		attrs = { Room = ds.room },
	})
	for i, r in tpl.squirrelRoutes do
		ctx.list:extra({
			kind = "Attachment",
			part = "Nav",
			name = `SquirrelRoute{i}`,
			offset = { 0, 0, 0 },
			attrs = { RouteKind = r.kind, Slot = r.slot or "", Room = r.room or "", Template = "W3" } :: Spec.Attrs,
		})
	end
	ctx.attributes.Interior = tpl.id
	ctx.attributes.BurglarEntry = tpl.burglarEntry.door
	ctx.attributes.RemodelSlots = table.concat(tpl.remodelSlots, ",")
	ctx.attributes.Enterable = true
	ctx.attributes.EaveY = eave
	ctx.attributes.PeakY = peak
	ctx.attributes.Roof = "gable"
	ctx.attributes.FurnishSkipped = table.concat(plan.skipped, ",")
	ctx.attributes.FurnishUnreached = #plan.unreached
end

return Interior
