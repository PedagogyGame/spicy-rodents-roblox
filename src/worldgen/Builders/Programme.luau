--!strict
-- ServerScriptService.Server.WorldGen.Builders.Programme
-- Building programmes from data/buildings/*.json (BUILD_PLAN §3.12, §4.4 #7): the Hospital (8 brief
-- rooms, 4 stations, pharmacy shelves with item-slot Attachments, room-name volumes) and the
-- PoliceStation (enterable lobby, briefing room, drone console, 2 player-car pads, the AI cruiser pad)
-- as an enterable Shell with stations, shelves and pads, every room dressed for its purpose by
-- Builders/Furnish (reception desk and waiting chairs, ward beds with curtains, treatment bays,
-- medicine cabinets; the station's front desk, holding cell, lockers and briefing chairs).
-- Builders/Hospital and Builders/PoliceStation are the named families; both call this.
-- Interface: build(ctx) (ctx.building is the generated/Buildings record). Pure.

local Building = require("./Building")
local Facade = require("./Facade")
local Furnish = require("./Furnish")
local Furniture = require("./Furniture")
local Import = require("../Import")
local Shell = require("./Shell")
local Spec = require("../Spec")
local HospitalLayout =
	Import.shared("Infection/HospitalLayout") :: typeof(require("../../shared/Infection/HospitalLayout"))
local StaffRounds = Import.shared("Actors/StaffRounds") :: typeof(require("../../shared/Actors/StaffRounds"))

local Programme = {}

local SHELF = { 226, 228, 226 }
local PAD = { 70, 70, 76 }

function Programme.build(ctx: Spec.LotCtx)
	local b = ctx.building :: any
	local spu = Spec.SPU
	local rooms: { Shell.Room } = {}
	for _, r in b.rooms do
		local x0, x1, z0, z1 = Shell.fromLot(r.rect)
		table.insert(rooms, {
			id = r.id,
			name = r.name,
			x0 = x0,
			x1 = x1,
			z0 = z0,
			z1 = z1,
			exterior = r.exterior,
			kind = if r.exterior then "exterior" else Furnish.roomKind(b.id, r.id),
		})
	end
	local doors: { Shell.Door } = {}
	for _, d in b.doors do
		table.insert(doors, {
			id = d.id,
			a = d.a,
			b = d.b,
			x = d.at[1] * spu,
			z = -d.at[2] * spu,
			w = d.width * spu,
			lockable = d.lockable,
		})
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
	local partH = math.min(b.partitionHeightU * spu, wallH - floorTop)
	local layout: Shell.Layout = {
		rooms = rooms,
		doors = doors,
		wallH = wallH,
		partH = partH,
		doorH = b.doorHeightU * spu,
		thick = 0.6,
		floorTop = floorTop,
		roof = "flat",
		extras = extras,
		windows = if b.id == "hospital" then "bands" else nil,
		plainFront = b.id == "hospital", -- Builders/Hospital draws the entrance piers and lintel
	}
	-- the rooms' dressing (Builders/Furnish): stations and shelves stay exactly where the data puts
	-- them and are dressed as desks, consoles, a pin board and shelving; the recipes add the rest
	local pins: { [string]: { Furnish.Pin } } = {}
	for _, s in b.stations do
		pins[s.room] = pins[s.room] or {}
		table.insert(pins[s.room], {
			id = "Station_" .. s.id,
			kind = "station",
			x = s.at[1] * spu,
			z = -s.at[2] * spu,
			fixed = true,
			sx = 6,
			sz = 2.5,
			dress = Furnish.STATION_DRESS[s.kind] or "desk",
		})
	end
	for _, s in b.shelves do
		pins[s.room] = pins[s.room] or {}
		table.insert(pins[s.room], {
			id = "Shelf_" .. s.id,
			kind = "shelf",
			x = s.at[1] * spu,
			z = -s.at[2] * spu,
			fixed = true,
			sx = s.lengthU * spu,
			sz = 1.5,
			dress = "shelf",
			w = s.lengthU * spu,
			seats = s.levels,
		})
	end
	local infoRooms = {}
	for _, r in rooms do
		table.insert(infoRooms, {
			id = r.id,
			kind = r.kind :: string,
			x0 = r.x0,
			x1 = r.x1,
			z0 = r.z0,
			z1 = r.z1,
			exterior = r.exterior,
		})
	end
	local band = nil
	if b.id == "hospital" then
		-- the ground-floor ribbon window of Building.bands, seen from inside
		local height = wallH - floorTop
		local floorH = height / math.clamp(math.floor(height / 10 + 0.3), 1, 4)
		band = { y = floorTop + 0.5 * floorH + 0.4, h = math.min(4.2, floorH * 0.42) }
	end
	local tones = if b.id == "hospital" then "hospital" else "police"
	-- Where people stand and walk indoors, kept clear before any furniture is placed: staff, patients
	-- and stretchers are kinematic (nothing stops them at a bed or a desk), so a way that crosses
	-- furniture is a person walking through it.
	local lanes: { { number } } = {}
	local discs: { { x: number, z: number, r: number } } = {}
	if b.id == "hospital" then
		-- the hospital sequence's own layout (Shared/Infection/HospitalLayout): the cots the server
		-- stands in the wards, the lanes every walk follows and the staff's rounds, the check-in spot
		-- in front of the reception desk and the intake in front of the triage desk
		local ways = HospitalLayout.plan(b, HospitalLayout.BEDS)
		if ways then
			for _, l in ways.lanes do
				table.insert(lanes, { l[1] * spu, -l[2] * spu, l[3] * spu, -l[4] * spu })
			end
			for _, bed in ways.beds do
				pins[bed.ward] = pins[bed.ward] or {}
				table.insert(pins[bed.ward], {
					id = "Cot" .. bed.index,
					kind = "cot",
					x = bed.x * spu,
					z = -bed.z * spu,
					fixed = true,
					sx = HospitalLayout.BED.width,
					sz = HospitalLayout.BED.length,
				})
			end
			table.insert(discs, { x = ways.reception[1] * spu, z = -ways.reception[2] * spu, r = 2.5 })
			table.insert(discs, { x = ways.intake[1] * spu, z = -ways.intake[2] * spu, r = 2.5 })
		end
	else
		-- the station's indoor staff walk the v5.4 round about their post (Shared/Actors/StaffRounds;
		-- world offsets from the lot's centre, turned into the model's frame)
		local cx, cz, r = StaffRounds.bounds(StaffRounds.POLICE.x, StaffRounds.POLICE.z)
		local c, s = ctx.frame.c, ctx.frame.s
		table.insert(discs, { x = cx * c - cz * s, z = cx * s + cz * c, r = r + 1.5 })
	end
	local plan = Furnish.plan(ctx, {
		building = b.id,
		tones = tones,
		rooms = infoRooms,
		doors = doors,
		thick = 0.6,
		partition = math.max(0.6 * 0.6, 0.3),
		floorTop = floorTop,
		ceiling = partH,
		doorH = b.doorHeightU * spu,
		grid = Shell.grid(ctx, layout),
		band = band,
		pins = pins,
		discs = discs,
		lanes = lanes,
		laneHalf = HospitalLayout.LANE,
		columns = if b.id == "hospital" then 28 else nil,
	})
	Shell.build(ctx, layout)
	local T = Furniture.TONES[tones]
	for _, s in b.stations do
		ctx.list:add(ctx.frame, "Station_" .. s.id, s.at[1] * spu, floorTop + 1.5, -s.at[2] * spu, 6, 3, 2.5, {
			color = if b.id == "hospital" then T.white else T.wood,
			material = if b.id == "hospital" then "SmoothPlastic" else "Wood",
			role = "Station",
			attrs = { Station = s.kind, StationId = s.id, Room = s.room },
		})
		ctx.list:extra({
			kind = "Prompt",
			part = "Station_" .. s.id,
			name = "Prompt",
			action = "Use",
			offset = { 0, 1.5, 0 },
			attrs = { Placeholder = true } :: Spec.Attrs,
		})
	end
	for _, s in b.shelves do
		local len, levels = s.lengthU * spu, s.levels
		local name = "Shelf_" .. s.id
		local h = 2.2 * levels
		ctx.list:add(ctx.frame, name, s.at[1] * spu, floorTop + h / 2, -s.at[2] * spu, len, h, 1.5, {
			color = SHELF,
			material = "Metal",
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
					attrs = { ItemSlot = true, Level = lv, Index = k } :: Spec.Attrs,
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
	Furnish.emit(ctx, plan)
	ctx.attributes.FurnishSkipped = table.concat(plan.skipped, ",")
	ctx.attributes.FurnishUnreached = #plan.unreached
	Building.dress(ctx, wallH + 0.6, wallH + 0.6, true, false)
	if b.id ~= "hospital" then
		-- the hospital has its own parapet and roof sign (Builders/Hospital); the station gets a
		-- parapet and its name over the door
		local style = Facade.style(ctx)
		Facade.flatRoof(ctx, wallH + 0.6, style, false)
		local text = ctx.params.sign or ctx.kit.signText
		if text then
			Building.sign(ctx, text, math.min(wallH - 1.6, floorTop + b.doorHeightU * spu + 4.6), 30)
		end
	end
	ctx.attributes.Building = b.id
	ctx.attributes.Enterable = true
end

return Programme
