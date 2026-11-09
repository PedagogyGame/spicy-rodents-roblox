--!strict
-- ServerScriptService.Server.WorldGen.Builders.Interior
-- Interior builder (BUILD_PLAN §3.4, §4.4 #7): an interior template from data/interiors/*.json placed
-- inside the real shell of its house (worldgen_core §16: nobody teleports). Rooms are fractional
-- rects of the footprint; the Shell builds the floor, exterior walls with the front and back
-- openings, partitions, server-owned doors, room volumes and the room graph; this adds furniture
-- (kit category), hide spots (behind/under/inside), the defender spawn, the burglar entry and the
-- squirrel-route sockets (template routes are W3), then the gable roof on top.
-- Interface: build(ctx) (ctx.interior is the template). Pure.

local Building = require("./Building")
local Shell = require("./Shell")
local Spec = require("../Spec")

local Interior = {}

local FURNITURE = { 150, 120, 96 }

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
		})
	end
	local doors: { Shell.Door } = {}
	for _, d in tpl.doors do
		table.insert(
			doors,
			{ id = d.id, a = d.a, b = d.b, x = mx(d.at[1]), z = mz(d.at[2]), w = d.width * spu, lockable = d.lockable }
		)
	end
	local extras = {}
	for _, f in tpl.furniture do
		if f.hide then
			table.insert(
				extras,
				{ id = "hide_" .. f.id, kind = "hide", room = f.room, x = mx(f.at[1]), z = mz(f.at[2]) }
			)
		end
	end
	local eave, peak, _kind, alongX = Building.heights(ctx)
	local floorTop = (tpl.floorU or 0.13) * spu
	Shell.build(ctx, {
		rooms = rooms,
		doors = doors,
		wallH = eave,
		partH = eave - floorTop,
		doorH = tpl.doorHeightU * spu,
		thick = tpl.wallU * spu,
		floorTop = floorTop,
		roof = "none",
		extras = extras,
	})
	if peak > eave + 0.05 then
		Building.roof(ctx, eave, peak, alongX)
	end
	for _, f in tpl.furniture do
		local sx, sy, sz = f.size[1] * spu, f.size[2] * spu, f.size[3] * spu
		local x, z = mx(f.at[1]), mz(f.at[2])
		-- keep furniture inside the walls
		local t = tpl.wallU * spu
		x = math.clamp(x, -W / 2 + t + sx / 2, W / 2 - t - sx / 2)
		z = math.clamp(z, -D / 2 + t + sz / 2, D / 2 - t - sz / 2)
		ctx.list:add(ctx.frame, "Furniture_" .. f.id, x, floorTop + sy / 2, z, sx, sy, sz, {
			color = FURNITURE,
			role = "Furniture",
			attrs = { Kit = f.kit, Room = f.room, HideType = f.hide or "" },
		})
		if f.hide then
			ctx.list:extra({
				kind = "Attachment",
				part = "Nav",
				name = "Hide_" .. f.id,
				offset = { x, 0, z },
				attrs = { HideType = f.hide, Room = f.room },
			})
		end
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
			attrs = { RouteKind = r.kind, Slot = r.slot or "", Room = r.room or "", Template = "W3" },
		})
	end
	ctx.attributes.Interior = tpl.id
	ctx.attributes.BurglarEntry = tpl.burglarEntry.door
	ctx.attributes.RemodelSlots = table.concat(tpl.remodelSlots, ",")
	ctx.attributes.Enterable = true
	ctx.attributes.EaveY = eave
	ctx.attributes.PeakY = peak
	ctx.attributes.Roof = "gable"
end

return Interior
