--!strict
-- tools/bake/sewers/Chamber: P1's chamber under the crossing, the owner's four-way junction (art_pack 02; data/sewers
-- "junction"; Shared/World/SewerLayout Chamber: centre on the floor, half 6, ports at the four arches).
--   Lining (hidden once his junction is in): (the four arm stubs, 3..6 from the centre, are the arms' passages'
--        lining run on: tools/bake/sewers/Pipe) the arch ring over each arm's opening, the central floor round the sump (his collider metadata: two north-south
--        and two east-west slabs, the sump base), the sump's water and its grate, the four piers (full height, the
--        groin vault's springers) and a flat ceiling at the vault's inner top
--   Shell: the light's holder (the arms' backing is the passages')
--   the light: a SpotLight under the middle of the ceiling (the lightGrate anchor: the manhole lid over the chamber)
--        and his ceiling fixture's diffuser; on the street the manhole lid itself lies on the junction's plate
--        (no shaft is cut through his vault for it: the light inside is the fixture's)
--   the art slot (module "junction"), pivoted on the floor's centre with its +Z on the first port
--   the fashion stand at its anchor
-- Interface: build(kit, ctx, chamber) where ctx = { lining, shell, dressing, art, section, space, slot(name, module,
--   cframe) }

local Dressing = require("./Dressing")
local Kit = require("./Kit")
local Lamps = require("./Lamps")
local Section = require("./Section")
local Water = require("./Water")

local Chamber = {}

Chamber.LID_Y = 0.28 -- the junction plate's top (Lots.core_intersection.Greybox): the lid lies on it

function Chamber.build(kit: Kit.Kit, ctx: any, ch: any, anchors: { any })
	local r = kit.roblox
	local V, CF = r.Vector3, r.CFrame
	local s = ctx.section
	local centre = { x = ch.x, y = ch.y, z = ch.z }
	local o = ch.ports[1].outward
	local C = kit:frame(centre, { x = o.x, y = 0, z = o.z })
	local inner = s.innerHalf
	local lining, shell = ctx.lining, ctx.shell
	-- the arch ring over each arm's opening (the arms themselves are the passages' lining, run on to here)
	for _, d in { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } } do
		local wv = C:VectorToWorldSpace(V.new(d[1], 0, d[2]))
		local A = kit:frame(centre, { x = wv.X, y = 0, z = wv.Z })
		Section.header(kit, lining, A, inner, inner + 0.3, s)
	end
	-- the central floor (his metadata: Floor_Central_NorthSouth x2, Floor_Central_EastWest x2, the sump base)
	local c, m = (Section.PALETTE :: any).concrete[1], (Section.PALETTE :: any).concrete[2]
	local below = s.below
	kit:box(lining, "Floor", C, -inner, inner, -below, 0, 1.2, inner, c, m)
	kit:box(lining, "Floor", C, -inner, inner, -below, 0, -inner, -1.2, c, m)
	kit:box(lining, "Floor", C, 1.2, inner, -below, 0, -1.2, 1.2, c, m)
	kit:box(lining, "Floor", C, -inner, -1.2, -below, 0, -1.2, 1.2, c, m)
	kit:box(lining, "SumpBase", C, -1.2, 1.2, -below - 0.1, -0.74, -1.2, 1.2, c, m)
	Water.sump(kit, lining, C, 1.18, -0.44)
	-- the sump's grate (walked over: under the body's lift)
	local ic, im = (Section.PALETTE :: any).iron[1], (Section.PALETTE :: any).iron[2]
	for k = -2, 2 do
		local z = k * 0.45
		kit:box(
			lining,
			"SumpGrate",
			C,
			-1.2,
			1.2,
			-0.06,
			0.0,
			z - 0.05,
			z + 0.05,
			ic,
			im,
			{ collide = false, query = false }
		)
	end
	kit:box(
		lining,
		"SumpFrame",
		C,
		-1.26,
		1.26,
		-0.09,
		0.03,
		-1.26,
		-1.18,
		{ 196, 150, 52 },
		"Metal",
		{ collide = false, query = false }
	)
	kit:box(
		lining,
		"SumpFrame",
		C,
		-1.26,
		1.26,
		-0.09,
		0.03,
		1.18,
		1.26,
		{ 196, 150, 52 },
		"Metal",
		{ collide = false, query = false }
	)
	-- the piers and the ceiling
	local tc, tm = (Section.PALETTE :: any).trim[1], (Section.PALETTE :: any).trim[2]
	for _, q in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		local px, pz = q[1] * 2.78, q[2] * 2.78
		kit:box(lining, "Pier", C, px - 0.2, px + 0.2, 0, Section.ROOF, pz - 0.2, pz + 0.2, tc, tm)
	end
	local bc, bm = (Section.PALETTE :: any).brick[1], (Section.PALETTE :: any).brick[2]
	kit:box(
		lining,
		"Ceiling",
		C,
		-s.outerHalf,
		s.outerHalf,
		s.spring + inner,
		Section.TOP,
		-s.outerHalf,
		s.outerHalf,
		bc,
		bm
	)
	-- his ceiling light (a diffuser on two hangers) and the light it gives
	kit:box(
		lining,
		"CeilingLight",
		C,
		-1.6,
		1.6,
		3.84,
		3.9,
		-0.08,
		0.08,
		{ 244, 212, 165 },
		"Neon",
		{ visual = true, shadow = false }
	)
	kit:box(lining, "CeilingLightFrame", C, -1.75, 1.75, 3.9, 4.05, -0.12, 0.12, ic, im, { visual = true })
	local grate: any? = nil
	for _, a in anchors do
		if a.kind == "lightGrate" and a.pipe == ch.pipe then
			grate = a
		end
	end
	local holder = kit:at(
		shell,
		"ChamberLight",
		C * CF.new(0, 3.8, 0),
		{ 0.2, 0.2, 0.2 },
		{ 0, 0, 0 },
		"SmoothPlastic",
		{ visual = true, transparency = 1, shadow = false }
	)
	Lamps.spot(
		kit,
		holder,
		"LightGrate",
		C * CF.new(0, 3.8, 0) * CF.Angles(-math.pi / 2, 0, 0),
		ctx.space,
		"lightGrate",
		{
			Range = 12,
			Angle = 100,
		}
	)
	-- the manhole lid on the street over the chamber (on the junction's plate; nothing walks on it)
	if grate then
		local lid = CF.new(grate.x, Chamber.LID_Y + 0.025, grate.z)
		kit:at(
			ctx.dressing,
			"ManholeLid",
			lid * CF.Angles(0, 0, math.pi / 2),
			{ 0.05, 2.1, 2.1 },
			{ 58, 58, 60 },
			"Metal",
			{ visual = true, shape = "Cylinder" }
		)
		kit:at(
			ctx.dressing,
			"ManholeRing",
			lid * CF.new(0, -0.005, 0) * CF.Angles(0, 0, math.pi / 2),
			{ 0.05, 2.3, 2.3 },
			{ 84, 84, 86 },
			"Metal",
			{ visual = true, shape = "Cylinder" }
		)
		for _, sx in { -0.45, 0.45 } do
			kit:at(
				ctx.dressing,
				"PickHole",
				lid * CF.new(sx, 0.026, 0),
				{ 0.16, 0.01, 0.06 },
				{ 16, 16, 18 },
				"SmoothPlastic",
				{ visual = true, shadow = false }
			)
		end
	end
	-- the fashion stand
	for _, a in anchors do
		if a.kind == "fashionStand" and a.pipe == ch.pipe then
			Dressing.stand(kit, ctx.dressing, a)
		end
	end
	ctx.slot("Junction", "junction", C)
end

return Chamber
