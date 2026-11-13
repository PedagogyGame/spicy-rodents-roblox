--!strict
-- tools/bake/games/Pool: pool's furniture in the bowling alley's games room (brief v2 §13a), built once per
-- station through the bake registry (tools/bake/GameBakes): an eight-ball table as real hardware, drawn from
-- the SAME numbers the game plays on (Shared/Minigames/Pool/Tables: the bed, the six cushion noses, the twelve
-- jaw facings, the six holes; Pool/Furniture: heights, rails, the tray), so what is seen is what is simulated.
--   the bed: cloth on slate, cut away at the six pockets, each with a dark well a ball drops into;
--   six cushions between the pockets, their ends cut back along the jaws' own lines;
--   wooden rails with eighteen sights, cut away behind each pocket; aprons, a floor under the body, four legs;
--   the head spot and the foot spot; two cubes of chalk;
--   the tray under the foot rail where potted balls collect, each in its own place (Furniture.home);
--   the sixteen balls as Models (CueParts.ball: numbered, solid and striped, the cue ball dotted), racked as an
--     idle table lies (Tables.rack) with the cue ball on the head spot;
--   a lamp of three green shades over the table (Model "Lamp") and a stand of cues beside it.
-- The table stands where the station is (the Spec's StationDef: Attractions/AlleyLayout.POOL_TABLES) and
-- nothing here knows where that is.
-- Interface: { build(kit, parent, station, venue) }: kit = tools/bake/alley/Kit in the site's frame, parent =
--   the GamesRoom model, station = the Spec's StationDef. Names the game finds: GamesRoom.Pool<index> with
--   CueBall, Ball1..Ball15 (Models) and Lamp.

local Furniture = require("../../../src/shared/Minigames/Pool/Furniture")
local Tables = require("../../../src/shared/Minigames/Pool/Tables")
local CueParts = require("./CueParts")

local Bake = {}

local WOOD = { 108, 68, 40 }
local WOOD_DARK = { 66, 40, 26 }
local FELT = { 28, 112, 72 }
local CUSHION = { 24, 98, 62 }
local SLATE = { 44, 46, 50 }
local BLACK = { 14, 14, 16 }
local PEARL = { 236, 234, 220 }
local CHALK = { 60, 110, 190 }
local MAPLE = { 222, 190, 136 }

local F = Furniture
local SOFT = { collide = false, query = false }

function Bake.build(kit: any, parent: any, station: any, _venue: any?)
	local tb = Tables.eightBall()
	local t = CueParts.on(kit, station)
	local m = kit:model(parent, Furniture.modelName("pool", station.index))
	local W, L = tb.halfW, tb.halfL
	local iw, il = W + F.CUSHION_BACK, L + F.CUSHION_BACK -- where the cloth ends and the wood begins
	local ow, ol = Furniture.outer(tb)
	local top = F.RAIL_H
	local cushionTop = F.CUSHION_H + 0.04

	-- the pockets: a square cut through cloth, slate and rail round each hole, and a dark well under it
	local cuts: { { number } } = {}
	for _, hole in tb.holes do
		local s = hole.r * 0.92
		table.insert(cuts, { hole.x - s, hole.x + s, hole.z - s, hole.z + s })
		t:box(
			m,
			"PocketWell",
			hole.x - s - 0.2,
			hole.x + s + 0.2,
			-F.WELL_DEPTH - 0.08,
			-F.WELL_DEPTH,
			hole.z - s - 0.2,
			hole.z + s + 0.2,
			BLACK,
			"SmoothPlastic",
			SOFT
		)
		-- the well's sides, so nothing shows through it
		for _, side in { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } } do
			local ax, az = side[1], side[2]
			local x0, x1 = hole.x - s - 0.03, hole.x + s + 0.03
			local z0, z1 = hole.z - s - 0.03, hole.z + s + 0.03
			if ax ~= 0 then
				x0 = hole.x + ax * (s + 0.015) - 0.015
				x1 = x0 + 0.03
			else
				z0 = hole.z + az * (s + 0.015) - 0.015
				z1 = z0 + 0.03
			end
			t:box(m, "PocketLiner", x0, x1, -F.WELL_DEPTH, -F.CLOTH_T - F.SLATE_T, z0, z1, BLACK, "SmoothPlastic", SOFT)
		end
	end
	for _, r in kit:holes(-iw, iw, -il, il, cuts) do
		t:box(m, "Cloth", r[1], r[2], -F.CLOTH_T, 0, r[3], r[4], FELT, "Fabric")
		t:box(m, "Slate", r[1], r[2], -F.CLOTH_T - F.SLATE_T, -F.CLOTH_T, r[3], r[4], SLATE, "Slate")
	end

	-- the rails: the wooden frame round the cloth, cut away behind each pocket
	local ring: { { number } } = { { -iw, iw, -il, il } }
	for _, c in cuts do
		table.insert(ring, c)
	end
	for _, r in kit:holes(-ow, ow, -ol, ol, ring) do
		t:box(m, "Rail", r[1], r[2], -F.CLOTH_T - F.SLATE_T, top, r[3], r[4], WOOD, "Wood")
	end

	-- the cushions (the noses the balls meet) and the jaws at their ends
	for _, seg in tb.segs do
		if seg.jaw then
			-- its rubber lies on the side away from the pocket it leads into
			local hx, hz, best = 0, 0, math.huge
			local mx, mz = (seg.x1 + seg.x2) / 2, (seg.z1 + seg.z2) / 2
			for _, hole in tb.holes do
				local d = (hole.x - mx) ^ 2 + (hole.z - mz) ^ 2
				if d < best then
					hx, hz, best = hole.x, hole.z, d
				end
			end
			local side = if (mx - hx) * -seg.tz + (mz - hz) * seg.tx > 0 then 1 else -1
			t:slab(m, "Jaw", seg.x1, seg.z1, seg.x2, seg.z2, 0, cushionTop, 0.09, side, CUSHION, "Fabric")
		elseif math.abs(seg.x1 - seg.x2) < 1e-9 then
			local sx = if seg.x1 > 0 then 1 else -1
			t:box(
				m,
				"Cushion",
				seg.x1,
				seg.x1 + sx * F.CUSHION_BACK,
				0,
				cushionTop,
				math.min(seg.z1, seg.z2),
				math.max(seg.z1, seg.z2),
				CUSHION,
				"Fabric"
			)
		else
			local sz = if seg.z1 > 0 then 1 else -1
			t:box(
				m,
				"Cushion",
				math.min(seg.x1, seg.x2),
				math.max(seg.x1, seg.x2),
				0,
				cushionTop,
				seg.z1,
				seg.z1 + sz * F.CUSHION_BACK,
				CUSHION,
				"Fabric"
			)
		end
	end

	-- the sights, the two spots, the chalk
	for _, s in Furniture.sights(tb) do
		t:cyl(m, "Sight", s.x, top + 0.002, s.z, 0.012, 2 * F.SIGHT_R, "Y", PEARL, "SmoothPlastic", SOFT)
	end
	for _, z in { tb.headZ, tb.footZ } do
		t:cyl(m, "Spot", 0, 0.002, z, 0.006, 0.08, "Y", { 20, 84, 54 }, "SmoothPlastic", SOFT)
	end
	t:box(m, "Chalk", ow - 0.34, ow - 0.22, top, top + 0.1, -1.1, -0.98, CHALK, "SmoothPlastic", SOFT)
	t:box(m, "Chalk", -ow + 0.2, -ow + 0.32, top, top + 0.1, 2.0, 2.12, CHALK, "SmoothPlastic", SOFT)

	-- the body: aprons, a floor under it, legs
	local under = -F.CLOTH_T - F.SLATE_T
	t:box(m, "Apron", -ow, ow, -F.APRON_H, under, -ol, -ol + 0.14, WOOD, "Wood")
	t:box(m, "Apron", -ow, ow, -F.APRON_H, under, ol - 0.14, ol, WOOD, "Wood")
	t:box(m, "Apron", -ow, -ow + 0.14, -F.APRON_H, under, -ol + 0.14, ol - 0.14, WOOD, "Wood")
	t:box(m, "Apron", ow - 0.14, ow, -F.APRON_H, under, -ol + 0.14, ol - 0.14, WOOD, "Wood")
	t:box(m, "Belly", -ow + 0.14, ow - 0.14, -F.APRON_H, -F.APRON_H + 0.08, -ol + 0.14, ol - 0.14, WOOD_DARK, "Wood")
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local x, z = sx * (ow - 0.6), sz * (ol - 1.0)
			t:box(
				m,
				"Leg",
				x - F.LEG_W / 2,
				x + F.LEG_W / 2,
				-F.BED_Y,
				-F.APRON_H,
				z - F.LEG_W / 2,
				z + F.LEG_W / 2,
				WOOD_DARK,
				"Wood"
			)
		end
	end

	-- the tray under the foot rail: fifteen places, lined with cloth
	local r = tb.ballR
	local _, trayY, trayZ = Furniture.tray(1)
	local half = 7.5 * F.TRAY_SLOT + 0.12
	local floorY = trayY - r
	t:box(m, "Tray", -half, half, floorY - 0.07, floorY, ol - 0.02, trayZ + r + 0.1, FELT, "Fabric", SOFT)
	t:box(m, "TrayLip", -half, half, floorY, floorY + 0.14, trayZ + r + 0.04, trayZ + r + 0.1, WOOD_DARK, "Wood", SOFT)
	for _, sx in { -1, 1 } do
		t:box(
			m,
			"TrayEnd",
			sx * half - 0.03,
			sx * half + 0.03,
			floorY - 0.07,
			floorY + 0.2,
			ol - 0.02,
			trayZ + r + 0.1,
			WOOD_DARK,
			"Wood",
			SOFT
		)
	end

	-- the balls, as an idle table lies: racked on the foot spot, the cue ball on the head spot
	for _, s in Tables.rack(station.index or 1) do
		CueParts.ball(t, m, "eightball", s.id, s.x, s.z)
	end

	CueParts.lamp(t, m, L, 3)

	-- a stand of cues by the head of the table (uncollidable: nobody trips on it walking round)
	local sx, sz = -(ow + 1.3), -(ol + 1.1)
	local floor = -F.BED_Y
	t:cyl(m, "CueStandBase", sx, floor + 0.06, sz, 0.12, 0.9, "Y", WOOD_DARK, "Wood", SOFT)
	t:cyl(m, "CueStandPost", sx, floor + 1.7, sz, 3.3, 0.1, "Y", WOOD_DARK, "Wood", SOFT)
	t:cyl(m, "CueStandRing", sx, floor + 2.9, sz, 0.08, 0.8, "Y", WOOD, "Wood", SOFT)
	for k = 0, 3 do
		local a = k * math.pi / 2 + 0.4
		local cx, cz = sx + math.cos(a) * 0.3, sz + math.sin(a) * 0.3
		t:rod(
			m,
			"Cue",
			cx,
			floor + 0.12,
			cz,
			cx - math.cos(a) * 0.08,
			floor + 0.12 + F.CUE_LEN,
			cz - math.sin(a) * 0.08,
			0.08,
			MAPLE,
			"Wood"
		)
	end
	return m
end

return Bake
