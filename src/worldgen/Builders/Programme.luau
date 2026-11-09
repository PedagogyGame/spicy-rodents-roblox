--!strict
-- ServerScriptService.Server.WorldGen.Builders.Programme
-- Building programmes from data/buildings/*.json (BUILD_PLAN §3.12, §4.4 #7): the Hospital (8 brief
-- rooms, 4 stations, pharmacy shelves with item-slot Attachments, room-name volumes) and the
-- PoliceStation (enterable lobby, briefing room, drone console, 2 player-car pads, the AI cruiser pad)
-- as an enterable Shell with stations, shelves and pads. Builders/Hospital and
-- Builders/PoliceStation are the named families; both call this.
-- Interface: build(ctx) (ctx.building is the generated/Buildings record). Pure.

local Shell = require("./Shell")
local Spec = require("../Spec")

local Programme = {}

local STATION = { 98, 140, 160 }
local SHELF = { 170, 170, 176 }
local PAD = { 70, 70, 76 }

function Programme.build(ctx: Spec.LotCtx)
	local b = ctx.building :: any
	local spu = Spec.SPU
	local rooms: { Shell.Room } = {}
	for _, r in b.rooms do
		local x0, x1, z0, z1 = Shell.fromLot(r.rect)
		table.insert(rooms, { id = r.id, name = r.name, x0 = x0, x1 = x1, z0 = z0, z1 = z1, exterior = r.exterior })
	end
	local doors: { Shell.Door } = {}
	for _, d in b.doors do
		table.insert(
			doors,
			{
				id = d.id,
				a = d.a,
				b = d.b,
				x = d.at[1] * spu,
				z = -d.at[2] * spu,
				w = d.width * spu,
				lockable = d.lockable,
			}
		)
	end
	local extras = {}
	for _, s in b.stations do
		table.insert(
			extras,
			{ id = "station_" .. s.id, kind = "station", room = s.room, x = s.at[1] * spu, z = -s.at[2] * spu }
		)
	end
	for _, s in b.shelves do
		table.insert(
			extras,
			{ id = "shelf_" .. s.id, kind = "shelf", room = s.room, x = s.at[1] * spu, z = -s.at[2] * spu }
		)
	end
	local params = ctx.params
	local wallH = (b.wallHeightU or params.eaveU or ctx.kit.heightU) * spu
	local floorTop = 0.42 * spu -- v5.4 HOSP floor = base + 0.42 (lot notes); the station uses the same step
	Shell.build(ctx, {
		rooms = rooms,
		doors = doors,
		wallH = wallH,
		partH = math.min(b.partitionHeightU * spu, wallH - floorTop),
		doorH = b.doorHeightU * spu,
		thick = 0.6,
		floorTop = floorTop,
		roof = "flat",
		extras = extras,
	})
	for _, s in b.stations do
		ctx.list:add(ctx.frame, "Station_" .. s.id, s.at[1] * spu, floorTop + 1.5, -s.at[2] * spu, 6, 3, 2.5, {
			color = STATION,
			role = "Station",
			attrs = { Station = s.kind, StationId = s.id, Room = s.room },
		})
		ctx.list:extra({
			kind = "Prompt",
			part = "Station_" .. s.id,
			name = "Prompt",
			action = "Use",
			offset = { 0, 1.5, 0 },
			attrs = { Placeholder = true },
		})
	end
	for _, s in b.shelves do
		local len, levels = s.lengthU * spu, s.levels
		local name = "Shelf_" .. s.id
		local h = 2.2 * levels
		ctx.list:add(ctx.frame, name, s.at[1] * spu, floorTop + h / 2, -s.at[2] * spu, len, h, 1.5, {
			color = SHELF,
			role = "Shelf",
			attrs = { ShelfId = s.id, Room = s.room, Slots = levels * s.slotsPerLevel },
		})
		for lv = 1, levels do
			for k = 1, s.slotsPerLevel do
				ctx.list:extra({
					kind = "Attachment",
					part = name,
					name = `Slot_{lv}_{k}`,
					offset = { -len / 2 + (k - 0.5) * len / s.slotsPerLevel, -h / 2 + (lv - 0.5) * 2.2 + 0.6, -0.9 },
					attrs = { ItemSlot = true, Level = lv, Index = k },
				})
			end
		end
	end
	for _, p in b.pads do
		ctx.list:add(ctx.frame, "Pad_" .. p.id, p.at[1] * spu, 0.05, -p.at[2] * spu, p.w * spu, 0.1, p.d * spu, {
			color = PAD,
			material = "Asphalt",
			canCollide = false,
			role = "Pad",
			attrs = { PadKind = p.kind, PadId = p.id },
		})
	end
	ctx.attributes.Building = b.id
	ctx.attributes.Enterable = true
end

return Programme
