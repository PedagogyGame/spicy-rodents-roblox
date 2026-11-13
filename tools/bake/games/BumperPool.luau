--!strict
-- tools/bake/games/BumperPool: bumper pool's furniture in the bowling alley's games room (brief v2 §13a), built
-- once per station through the bake registry (tools/bake/GameBakes): the table as real hardware, drawn from the
-- SAME numbers the game plays on (Shared/Minigames/Pool/Tables.bumper: the bed, the four cushion noses, the
-- twelve posts and the two cups; Pool/Furniture: heights, rails, the trays), so what is seen is what is
-- simulated.
--   the bed: blue cloth on slate, cut away at the two cups, each a black hole with a bright rim;
--   four cushions round the bed and a wooden rail outside them; aprons, legs, a floor under the body;
--   twelve posts (a cross of eight in the middle with its one-ball gap, two flanking each cup), each a dark
--     pin with its rubber ring at the height a ball meets it and a bright cap;
--   a little tray outside each end rail where a side's sunk balls collect, each in its own place
--     (Furniture.home: the marked ball first);
--   the ten balls as Models (CueParts.ball: five red, five white, the marked one of each spotted with the
--     other colour) on their starting spots (Tables.bumperStart);
--   a lamp of one shade over the table (Model "Lamp"), a stand with two short cues beside it, and a
--     chalkboard on a post (Model "ScoreBoard": the server writes each side's balls down and the sitting).
-- The table stands where the station is (the Spec's StationDef: Attractions/AlleyLayout.BUMPER_POOL) and
-- nothing here knows where that is.
-- Interface: { build(kit, parent, station, venue) }: kit = tools/bake/alley/Kit in the site's frame, parent =
--   the GamesRoom model, station = the Spec's StationDef. Names the game finds: GamesRoom.BumperPool with
--   Ball1..Ball10 (Models), Lamp and ScoreBoard.

local Furniture = require("../../../src/shared/Minigames/Pool/Furniture")
local Tables = require("../../../src/shared/Minigames/Pool/Tables")
local CueParts = require("./CueParts")

local Bake = {}

local WOOD = { 112, 70, 40 }
local WOOD_DARK = { 66, 40, 26 }
local FELT = { 34, 78, 140 }
local CUSHION = { 28, 66, 120 }
local SLATE = { 44, 46, 50 }
local BLACK = { 12, 12, 14 }
local CHROME = { 200, 200, 206 }
local RUBBER = { 30, 30, 32 }
local PIN = { 54, 54, 60 }
local MAPLE = { 222, 190, 136 }
local CHALK = { 60, 110, 190 }

local F = Furniture
local SOFT = { collide = false, query = false }

function Bake.build(kit: any, parent: any, station: any, _venue: any?)
	if station.joins then
		return nil
	end
	local tb = Tables.bumper()
	local t = CueParts.on(kit, station)
	local m = kit:model(parent, Furniture.modelName("bumper_pool", station.index))
	local W, L = tb.halfW, tb.halfL
	local back = 0.14 -- the cushion's depth from its nose to the wood
	local iw, il = W + back, L + back
	local ow, ol = Furniture.outer(tb)
	local top = F.RAIL_H
	local under = -F.CLOTH_T - F.SLATE_T

	-- the bed, cut away round each cup, and the cup itself: a black hole with a bright rim
	local cuts: { { number } } = {}
	for _, hole in tb.holes do
		local s = hole.r * 0.7
		table.insert(cuts, { hole.x - s, hole.x + s, hole.z - s, hole.z + s })
		t:cyl(m, "CupRim", hole.x, 0.0005, hole.z, 0.003, 2 * hole.r + 0.06, "Y", CHROME, "Metal", SOFT)
		t:cyl(m, "Cup", hole.x, 0.0012, hole.z, 0.003, 2 * hole.r, "Y", BLACK, "SmoothPlastic", SOFT)
		t:box(
			m,
			"CupWell",
			hole.x - s,
			hole.x + s,
			-F.WELL_DEPTH,
			under,
			hole.z - s,
			hole.z + s,
			BLACK,
			"SmoothPlastic",
			SOFT
		)
	end
	for _, r in kit:holes(-iw, iw, -il, il, cuts) do
		t:box(m, "Cloth", r[1], r[2], -F.CLOTH_T, 0, r[3], r[4], FELT, "Fabric")
		t:box(m, "Slate", r[1], r[2], under, -F.CLOTH_T, r[3], r[4], SLATE, "Slate")
	end

	-- the cushions (their noses are the model's four segments) and the rail outside them
	local cushionTop = F.CUSHION_H + 0.03
	t:box(m, "Cushion", -iw, -W, 0, cushionTop, -L, L, CUSHION, "Fabric")
	t:box(m, "Cushion", W, iw, 0, cushionTop, -L, L, CUSHION, "Fabric")
	t:box(m, "Cushion", -iw, iw, 0, cushionTop, -il, -L, CUSHION, "Fabric")
	t:box(m, "Cushion", -iw, iw, 0, cushionTop, L, il, CUSHION, "Fabric")
	for _, r in kit:holes(-ow, ow, -ol, ol, { { -iw, iw, -il, il } }) do
		t:box(m, "Rail", r[1], r[2], under, top, r[3], r[4], WOOD, "Wood")
	end

	-- the twelve posts: a dark pin, the rubber ring a ball meets (Tables.POST_R, at a ball's middle), a cap
	for _, p in tb.posts do
		t:cyl(m, "Pin", p.x, F.POST_H / 2, p.z, F.POST_H, 1.2 * p.r, "Y", PIN, "Metal")
		t:cyl(m, "Ring", p.x, F.POST_RING_H, p.z, 0.11, 2 * p.r, "Y", RUBBER, "Rubber" :: any, SOFT)
		t:cyl(m, "Cap", p.x, F.POST_H + 0.015, p.z, 0.03, 1.5 * p.r, "Y", CHROME, "Metal", SOFT)
	end

	-- the body: aprons, a floor under it, four legs
	local apron = -F.APRON_H + top
	t:box(m, "Apron", -ow, ow, apron, under, -ol, -ol + 0.12, WOOD, "Wood")
	t:box(m, "Apron", -ow, ow, apron, under, ol - 0.12, ol, WOOD, "Wood")
	t:box(m, "Apron", -ow, -ow + 0.12, apron, under, -ol + 0.12, ol - 0.12, WOOD, "Wood")
	t:box(m, "Apron", ow - 0.12, ow, apron, under, -ol + 0.12, ol - 0.12, WOOD, "Wood")
	t:box(m, "Belly", -ow + 0.12, ow - 0.12, apron, apron + 0.08, -ol + 0.12, ol - 0.12, WOOD_DARK, "Wood")
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local x, z = sx * (ow - 0.45), sz * (ol - 0.55)
			t:box(m, "Leg", x - 0.25, x + 0.25, -F.BED_Y, apron, z - 0.25, z + 0.25, WOOD_DARK, "Wood")
		end
	end

	-- a tray outside each end rail: a side's five sunk balls, in their own places
	local r = tb.ballR
	for side = 1, 2 do
		local _, trayY, trayZ = Furniture.cupTray(side, 1)
		local sz = if trayZ > 0 then 1 else -1
		local half = 2.5 * F.TRAY_SLOT + 0.1
		local floorY = trayY - r
		local z0, z1 = sz * (ol - 0.02), trayZ + sz * (r + 0.1)
		t:box(m, "Tray", -half, half, floorY - 0.07, floorY, math.min(z0, z1), math.max(z0, z1), FELT, "Fabric", SOFT)
		local lip0, lip1 = trayZ + sz * (r + 0.04), trayZ + sz * (r + 0.1)
		t:box(
			m,
			"TrayLip",
			-half,
			half,
			floorY,
			floorY + 0.14,
			math.min(lip0, lip1),
			math.max(lip0, lip1),
			WOOD_DARK,
			"Wood",
			SOFT
		)
		for _, sx in { -1, 1 } do
			t:box(
				m,
				"TrayEnd",
				sx * half - 0.03,
				sx * half + 0.03,
				floorY - 0.07,
				floorY + 0.2,
				math.min(z0, z1),
				math.max(z0, z1),
				WOOD_DARK,
				"Wood",
				SOFT
			)
		end
	end

	-- the ten balls on their starting spots
	for _, s in Tables.bumperStart() do
		CueParts.ball(t, m, "bumper", s.id, s.x, s.z)
	end

	CueParts.lamp(t, m, L, 1)
	CueParts.board(t, m, -(ow + 1.2), -(ol - 0.4), "BUMPER POOL\nWalk up and press E")

	-- two short cues on a stand beside the table, and chalk on the rail (none of it in anybody's way)
	local sx, sz = ow + 1.1, -(ol - 0.4)
	local floor = -F.BED_Y
	t:cyl(m, "CueStandBase", sx, floor + 0.06, sz, 0.12, 0.7, "Y", WOOD_DARK, "Wood", SOFT)
	t:cyl(m, "CueStandPost", sx, floor + 1.3, sz, 2.5, 0.09, "Y", WOOD_DARK, "Wood", SOFT)
	for k = 0, 1 do
		local a = k * math.pi + 0.6
		local cx, cz = sx + math.cos(a) * 0.22, sz + math.sin(a) * 0.22
		t:rod(
			m,
			"Cue",
			cx,
			floor + 0.12,
			cz,
			cx - math.cos(a) * 0.06,
			floor + 0.12 + 3.4,
			cz - math.sin(a) * 0.06,
			0.07,
			MAPLE,
			"Wood"
		)
	end
	t:box(m, "Chalk", ow - 0.3, ow - 0.18, top, top + 0.1, 0.9, 1.02, CHALK, "SmoothPlastic", SOFT)
	return m
end

return Bake
