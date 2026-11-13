--!strict
-- tools/bake/sewers/Pipe: one storm drain (Shared/World/SewerLayout Pipe) as a Model under Workspace.Sewers,
-- streamed whole (ModelStreamingMode Atomic: a pipe never arrives half drawn while a squirrel is in it):
--   Shell     what always stands: the shaft chambers (Section.box), fillers no whole module fits (Section.arched),
--             the backing round everything, the shafts, their roofs and ladders, the bulkheads of lamps no module
--             carries
--   Lining    the parts drawing of the owner's modules (Section.arched under each run of art slots; the junction):
--             every part collides (camera, bodies); the art loader sets them invisible once the pipe's art is in
--   Art       one Model per slot, no parts: attributes ArtModule (data/art/sewer_modules.json key), ArtAsset (its
--             Roblox Model id), ArtPivot (CFrame: the module's origin on its walkway top, +Z along, the route in a
--             lane the module leaves clear), Pipe, Space
--   Mouths    each street mouth (Mouth.build: frame, Grate)
--   Dressing  signs, chalk, moss, leaves, the lost things, the fashion stand, the manhole lid, the light grate
--   Lamps     the disabled lights (Lamps.build), and each light grate's SpotLight
-- Attributes on the Model: Pipe, Space, Name, Sign.
-- Interface: build(kit, root, layout, pipe, art) -> { slots, lamps, plans }

local Chamber = require("./Chamber")
local Dressing = require("./Dressing")
local Kit = require("./Kit")
local Lamps = require("./Lamps")
local Mouth = require("./Mouth")
local Plan = require("./Plan")
local Section = require("./Section")
local Shaft = require("./Shaft")
local Water = require("./Water")

local Pipe = {}

-- which of the owner's variants each section repeats (data/art/sewer_modules.json): the full module every `every`
-- slots from slot `first`, the plain one between
Pipe.VARIANTS = {
	brick = { full = "brick", plain = "brickPlain", every = 4, first = 2 },
	dry = { full = "dry", plain = "dryPlain", every = 5, first = 3 },
}
Pipe.ROAD_TOP = { ["P3"] = 9.515 } -- the boulevard's surface at P3's light grate (Roads.rd_019 Seg037; the spec checks)

local function lanesOf(art: any, variant: string): any
	local m = art and art.modules and art.modules[variant]
	return m and m.lanes
end

function Pipe.build(
	kit: Kit.Kit,
	root: any,
	layout: any,
	pipe: any,
	art: any
): { slots: number, lamps: number, plans: { any } }
	local r = kit.roblox
	local V, CF = r.Vector3, r.CFrame
	local section = layout.data.sections[pipe.section]
	local model = kit:model(root, pipe.id, { Pipe = pipe.id, Space = pipe.space, Name = pipe.name, Sign = pipe.sign })
	model.ModelStreamingMode = r.Enum.ModelStreamingMode.Atomic
	local shell = kit:model(model, "Shell")
	local lining = kit:model(model, "Lining")
	local artFolder = kit:folder(model, "Art")
	local mouths = kit:model(model, "Mouths")
	local dressing = kit:model(model, "Dressing")
	local nSlots = 0
	local function slot(name: string, variant: string, pivot: any)
		nSlots += 1
		local entry = art and art.modules and art.modules[variant]
		kit:model(artFolder, name, {
			ArtModule = variant,
			ArtAsset = if entry and entry.assetId then tostring(entry.assetId) else "",
			ArtPivot = pivot,
			Pipe = pipe.id,
			Space = pipe.space,
		})
	end

	-- the mouths first: their frames give the shafts' tops
	local tops: { [string]: number } = {}
	for _, m in layout.mouthsOf(pipe.id) do
		local built = Mouth.build(kit, mouths, m, pipe.space)
		tops[m.id] = built.under
	end

	local plans = {}
	local slotIndex = 0
	for _, pass in pipe.passages do
		local lane = if section.routeOffset > 0 then pass.side else 0
		local plan = Plan.plan(layout, pipe, pass, { variants = (Pipe.VARIANTS :: any)[section.kind] })
		table.insert(plans, plan)
		-- into the chamber: the arms' lining runs on to the junction's central square (half - innerHalf more)
		local into = 0
		if pipe.chamber ~= nil then
			for _, ch in layout.chambers do
				if ch.id == pipe.chamber then
					into = ch.half - section.innerHalf
				end
			end
		end
		for _, run in plan.runs do
			local a = Plan.at(plan, run.s0)
			local b = Plan.at(plan, run.s1)
			local leg = plan.legs[run.leg]
			local frame = kit:frame(a, { x = leg.b.x - leg.a.x, y = leg.b.y - leg.a.y, z = leg.b.z - leg.a.z })
			local len = (V.new(b.x, b.y, b.z) - V.new(a.x, a.y, a.z)).Magnitude
			if run.kind == "box" then
				Section.box(kit, shell, frame, 0, len, section, run.endWall, run.header)
				-- a trickle from an outlet in the end wall into the channel
				if section.water ~= nil and run.endWall ~= nil then
					local zo = if run.endWall == "z0" then 0.18 else len - 0.18
					local zf = if run.endWall == "z0" then 0.38 else len - 0.38
					local ic = (Section.PALETTE :: any).iron[1]
					kit:cyl(
						shell,
						"Outlet",
						frame,
						{ 0, 1.5, zo - 0.2 },
						{ 0, 1.5, zo + 0.2 },
						0.34,
						ic,
						"Metal",
						{ visual = true }
					)
					Water.fall(kit, shell, frame, 0, section.water, 1.45, zf, 0.18)
				end
			elseif run.kind == "lining" then
				local extra = if math.abs(run.s1 - plan.length) < 1e-6 then into else 0
				Section.arched(kit, lining, frame, 0, len + extra, section, lane)
			else
				Section.arched(kit, shell, frame, 0, len, section, lane, true)
			end
		end
		-- the backing, one casing per leg (a roof over all but the shaft chambers, which have their own)
		for li, leg in plan.legs do
			local a, b = leg.a, leg.b
			local frame = kit:frame(a, { x = b.x - a.x, y = b.y - a.y, z = b.z - a.z })
			local k = (V.new(b.x, b.y, b.z) - V.new(a.x, a.y, a.z)).Magnitude / (leg.s1 - leg.s0)
			local extra = if li == #plan.legs then into else 0
			Section.backing(kit, shell, frame, 0, (leg.s1 - leg.s0) * k + extra, section, false)
			local r0: number? = nil
			local function roofTo(sEnd: number)
				if r0 then
					local e = if math.abs(sEnd - plan.length) < 1e-6 then extra else 0
					Section.roof(kit, shell, frame, (r0 - leg.s0) * k, (sEnd - leg.s0) * k + e, section)
					r0 = nil
				end
			end
			for _, run in plan.runs do
				if run.leg == li then
					if run.kind == "box" then
						roofTo(run.s0)
					elseif r0 == nil then
						r0 = run.s0
					end
				end
			end
			roofTo(leg.s1)
		end
		-- the art slots, each turned so the route runs a lane the module leaves clear
		for _, s in plan.slots do
			slotIndex += 1
			local f = Plan.slotFrame(plan, s)
			local lanes = lanesOf(art, s.variant)
			local flip = false
			if lane ~= 0 and lanes then
				local want = if lane > 0 then "+x" else "-x"
				local other = if lane > 0 then "-x" else "+x"
				if not (lanes[want] and lanes[want].clear) then
					assert(lanes[other] and lanes[other].clear, `{pipe.id}: no clear lane in {s.variant}`)
					flip = true
				end
			end
			local along = if flip then { x = -f.along.x, y = -f.along.y, z = -f.along.z } else f.along
			slot(string.format("Slot%02d", slotIndex), s.variant, kit:frame(f.origin, along))
		end
		-- the shafts at the ends
		for _, e in plan.ends do
			local m = e.mouth
			Shaft.walls(kit, shell, m, tops[m.id], section)
			Shaft.roof(kit, shell, m, section)
			Shaft.ladder(kit, shell, m, tops[m.id])
		end
		-- dressing along the passage: moss and leaves on the far side, chalk midway
		local L = plan.length
		local function at(sAt: number): (any, number)
			local p, d = Plan.at(plan, sAt)
			return kit:frame(p, d), 0
		end
		for _, fz in { 0.3, 0.7 } do
			local fr = at(L * fz)
			Dressing.moss(kit, dressing, fr, 0, section, lane, 1.4 + fz)
		end
		local farX = if lane == 0 then -2.35 else -lane * 2.1
		Dressing.leaves(kit, dressing, (at(L * 0.4)), 0, farX, 3)
		local towards = if pipe.chamber ~= nil then "CROSSROADS" elseif pipe.id == "P2" then "EAST QUAY" else "MAIN ST"
		Dressing.chalk(kit, dressing, (at(L * 0.5)), 0, section, lane, towards, 1)
		if section.water ~= nil then
			Dressing.boat(kit, dressing, (at(L * 0.66)), 0, section)
		end
		if pipe.id == "P3" then
			Dressing.duck(kit, dressing, (at(L * 0.31)), 0, section)
			Dressing.ball(kit, dressing, (at(12.5)), 0, farX)
		end
		-- the Dry Side plaque at the foot of each culvert ladder, on the wall away from the walkway's middle
		if section.kind == "dry" then
			for _, e in plan.ends do
				local sFoot = if e.atStart then 2.0 else L - 2.0
				local p, d = Plan.at(plan, sFoot)
				local fr = kit:frame(p, d)
				local wall = fr * V.new(section.innerHalf - 0.01, 1.25, 0)
				local inward = fr:VectorToWorldSpace(V.new(-1, 0, 0))
				slot(
					string.format("Plaque%s", if e.atStart then "Start" else "End"),
					"marker",
					CF.lookAt(wall, wall + inward)
				)
			end
		end
	end

	-- the lamps: a bulkhead only where no module carries a fixture
	local function covered(a: any): boolean
		for _, plan in plans do
			for _, s in plan.slots do
				for k = 0, 24 do
					local p = Plan.at(plan, s.s0 + (s.s1 - s.s0) * k / 24)
					if (p.x - a.x) ^ 2 + (p.z - a.z) ^ 2 < 3.2 ^ 2 and math.abs(p.y + section.lamp[2] - a.y) < 0.5 then
						return true
					end
				end
			end
		end
		return false
	end
	local nLamps = Lamps.build(kit, shell, pipe, layout.anchors, covered, shell)

	-- the chamber, the signs, the light grates
	if pipe.chamber ~= nil then
		for _, ch in layout.chambers do
			if ch.id == pipe.chamber then
				Chamber.build(kit, {
					lining = lining,
					shell = shell,
					dressing = dressing,
					section = section,
					space = pipe.space,
					slot = slot,
				}, ch, layout.anchors)
			end
		end
	end
	for _, a in layout.anchors do
		if a.pipe ~= pipe.id then
			continue
		end
		if a.kind == "sign" then
			Dressing.sign(kit, dressing, a)
		elseif a.kind == "lightGrate" and pipe.chamber == nil then
			-- a grille in the vault's crown with daylight behind it, and its little grate in the road above
			local plan = plans[1]
			local best, bs = math.huge, 0
			for k = 0, 400 do
				local sk = plan.length * k / 400
				local p = Plan.at(plan, sk)
				local dd = (p.x - a.x) ^ 2 + (p.z - a.z) ^ 2
				if dd < best then
					best, bs = dd, sk
				end
			end
			local p, d = Plan.at(plan, bs)
			local fr = kit:frame(p, d)
			local crown = section.spring + section.innerHalf
			local ic, im = (Section.PALETTE :: any).iron[1], (Section.PALETTE :: any).iron[2]
			kit:box(
				dressing,
				"LightGrateGlow",
				fr,
				-0.7,
				0.7,
				crown - 0.2,
				crown - 0.16,
				-0.45,
				0.45,
				{ 214, 226, 236 },
				"SmoothPlastic",
				{ visual = true, shadow = false }
			)
			for k = -3, 3 do
				local x = k * 0.2
				kit:box(
					dressing,
					"LightGrateBar",
					fr,
					x - 0.04,
					x + 0.04,
					crown - 0.3,
					crown - 0.2,
					-0.5,
					0.5,
					ic,
					im,
					{ visual = true }
				)
			end
			local holder = kit:at(
				shell,
				"LightGrateLight",
				fr * CF.new(0, crown - 0.4, 0),
				{ 0.2, 0.2, 0.2 },
				{ 0, 0, 0 },
				"SmoothPlastic",
				{ visual = true, transparency = 1, shadow = false }
			)
			Lamps.spot(
				kit,
				holder,
				"LightGrate",
				fr * CF.new(0, crown - 0.4, 0) * CF.Angles(-math.pi / 2, 0, 0),
				pipe.space,
				"lightGrate",
				{
					Color = r.Color3.fromRGB(236, 240, 246),
					Angle = 50,
				}
			)
			local road = Pipe.ROAD_TOP[pipe.id]
			if road then
				local g = CF.new(a.x, road + 0.02, a.z) * CF.Angles(0, math.atan2(d.x, d.z), 0)
				kit:at(dressing, "RoadGrateFrame", g, { 1.0, 0.04, 1.7 }, { 64, 66, 68 }, "Metal", { visual = true })
				for k = -2, 2 do
					kit:at(
						dressing,
						"RoadGrateSlot",
						g * CF.new(k * 0.17, 0.021, 0),
						{ 0.07, 0.005, 1.4 },
						{ 14, 14, 16 },
						"SmoothPlastic",
						{ visual = true, shadow = false }
					)
				end
			end
		end
	end
	return { slots = nSlots, lamps = nLamps, plans = plans }
end

return Pipe
