--!strict
-- tools/bake/sewers/Pipe: one storm drain (Shared/World/SewerLayout Pipe) as a Model under Workspace.Sewers,
-- streamed whole (ModelStreamingMode Atomic: a pipe never arrives half drawn while a squirrel is in it):
--   Shell     what always stands: the shaft chambers (Section.box), fillers no whole module fits (Section.arched),
--             the backing round everything, the shafts, their roofs and ladders, the bulkheads of lamps no module
--             carries, the "Lamps" part (Lamps.build: an Attachment and a disabled light per lamp anchor), the
--             holders of the chamber's and the light grate's SpotLights, the "Cues" part (Cues.build)
--   Lining    the parts drawing of the owner's modules (Section.arched under each run of art slots, the junction's
--             middle): every part collides (camera, bodies); the art loader sets them invisible once the pipe's art
--             is in
--   Art       one Model per slot, no parts: attributes ArtModule (data/art/sewer_modules.json key), ArtAsset (its
--             Roblox Model id), ArtPivot (CFrame: the module's origin on its walkway top, +Z along, the route in a
--             lane the module leaves clear), Pipe, Space
--   Mouths    each street mouth (Mouth.build: frame, Grate)
--   Dressing  signs, chalk, moss, leaves, the lost things, the fashion stand, the manhole lid, the light grate
-- Attributes on the Model: Pipe, Space, Name, Sign.
-- Interface: build(kit, root, layout, pipe, art) -> { slots, lamps, cues, plans }

local Chamber = require("./Chamber")
local Cues = require("./Cues")
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

type Ctx = {
	kit: Kit.Kit,
	layout: any,
	pipe: any,
	art: any,
	section: any,
	shell: any,
	lining: any,
	dressing: any,
	slot: (name: string, variant: string, pivot: any) -> (),
	cue: (name: string, x: number, y: number, z: number) -> (),
	tops: { [string]: number },
	slots: number, -- passage modules numbered so far (Slot01 ...)
}

local function v3(kit: Kit.Kit, p: Plan.Vec3): any
	return kit.roblox.Vector3.new(p.x, p.y, p.z)
end

-- the runs of a passage (shaft chambers, lining, fillers) and its backing; `into`: how far the last run goes on into
-- a chamber (the junction's arms are the passages' lining run on to its middle square)
local function shell(ctx: Ctx, plan: Plan.Plan, lane: number, into: number)
	local kit, section = ctx.kit, ctx.section
	for _, run in plan.runs do
		local a, b = Plan.at(plan, run.s0), Plan.at(plan, run.s1)
		local leg = plan.legs[run.leg]
		local frame = kit:frame(a, { x = leg.b.x - leg.a.x, y = leg.b.y - leg.a.y, z = leg.b.z - leg.a.z })
		local len = (v3(kit, b) - v3(kit, a)).Magnitude
		if run.kind == "box" then
			Section.box(kit, ctx.shell, frame, 0, len, section, run.endWall, run.header)
			-- a trickle from an outlet in the end wall into the channel
			if section.water ~= nil and run.endWall ~= nil then
				local zo = if run.endWall == "z0" then 0.18 else len - 0.18
				local zf = if run.endWall == "z0" then 0.38 else len - 0.38
				local iron = (Section.PALETTE :: any).iron[1]
				kit:cyl(ctx.shell, "Outlet", frame, { 0, 1.5, zo - 0.2 }, { 0, 1.5, zo + 0.2 }, 0.34, iron, "Metal", {
					visual = true,
				})
				Water.fall(kit, ctx.shell, frame, 0, section.water, 1.45, zf, 0.18)
				local q = frame * kit.roblox.Vector3.new(0, section.water, zf)
				ctx.cue("sewer.trickle", q.X, q.Y, q.Z)
			end
		elseif run.kind == "lining" then
			local extra = if math.abs(run.s1 - plan.length) < 1e-6 then into else 0
			Section.arched(kit, ctx.lining, frame, 0, len + extra, section, lane)
		else
			Section.arched(kit, ctx.shell, frame, 0, len, section, lane, true)
		end
	end
	-- the backing, one casing per leg (a roof over all but the shaft chambers, which have their own)
	for li, leg in plan.legs do
		local frame = kit:frame(leg.a, { x = leg.b.x - leg.a.x, y = leg.b.y - leg.a.y, z = leg.b.z - leg.a.z })
		local k = (v3(kit, leg.b) - v3(kit, leg.a)).Magnitude / (leg.s1 - leg.s0)
		local extra = if li == #plan.legs then into else 0
		Section.backing(kit, ctx.shell, frame, 0, (leg.s1 - leg.s0) * k + extra, section, false)
		local r0: number? = nil
		local function roofTo(sEnd: number)
			if r0 then
				local e = if math.abs(sEnd - plan.length) < 1e-6 then extra else 0
				Section.roof(kit, ctx.shell, frame, (r0 - leg.s0) * k, (sEnd - leg.s0) * k + e, section)
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
end

-- the art slots, each turned so the route runs a lane the module leaves clear
local function slots(ctx: Ctx, plan: Plan.Plan, lane: number)
	for _, s in plan.slots do
		ctx.slots += 1
		local f = Plan.slotFrame(plan, s)
		local entry = ctx.art and ctx.art.modules and ctx.art.modules[s.variant]
		local lanes = entry and entry.lanes
		local flip = false
		if lane ~= 0 and lanes then
			local want = if lane > 0 then "+x" else "-x"
			local other = if lane > 0 then "-x" else "+x"
			if not (lanes[want] and lanes[want].clear) then
				assert(lanes[other] and lanes[other].clear, `{ctx.pipe.id}: no clear lane in {s.variant}`)
				flip = true
			end
		end
		local along = if flip then { x = -f.along.x, y = -f.along.y, z = -f.along.z } else f.along
		ctx.slot(string.format("Slot%02d", ctx.slots), s.variant, ctx.kit:frame(f.origin, along))
	end
end

-- moss and leaves on the far side, chalk midway, the lost things; on the dry culvert the owner's Dry Side plaque at
-- the foot of each ladder
local function dress(ctx: Ctx, plan: Plan.Plan, lane: number)
	local kit, section, pipe = ctx.kit, ctx.section, ctx.pipe
	local L = plan.length
	local function at(s: number): any
		local p, d = Plan.at(plan, s)
		return kit:frame(p, d)
	end
	for _, f in { 0.3, 0.7 } do
		Dressing.moss(kit, ctx.dressing, at(L * f), 0, section, lane, 1.4 + f)
	end
	local farX = if lane == 0 then -2.35 else -lane * 2.1
	Dressing.leaves(kit, ctx.dressing, at(L * 0.4), 0, farX, 2)
	local towards = if pipe.chamber ~= nil then "CROSSROADS" elseif pipe.id == "P2" then "EAST QUAY" else "MAIN ST"
	Dressing.chalk(kit, ctx.dressing, at(L * 0.5), 0, section, lane, towards, 1)
	if section.water ~= nil then
		Dressing.boat(kit, ctx.dressing, at(L * 0.66), 0, section)
	end
	if pipe.id == "P3" then
		Dressing.duck(kit, ctx.dressing, at(L * 0.31), 0, section)
		Dressing.ball(kit, ctx.dressing, at(12.5), 0, farX)
	end
	if section.kind == "dry" then
		local V = kit.roblox.Vector3
		for _, e in plan.ends do
			local fr = at(if e.atStart then 2.0 else L - 2.0)
			local wall = fr * V.new(section.innerHalf - 0.01, 1.25, 0)
			local inward = fr:VectorToWorldSpace(V.new(-1, 0, 0))
			local name = if e.atStart then "PlaqueStart" else "PlaqueEnd"
			ctx.slot(name, "marker", kit.roblox.CFrame.lookAt(wall, wall + inward))
		end
	end
end

-- a light grate in the road over a pipe (P3's in the boulevard): a grille in the vault's crown with daylight behind
-- it and a disabled SpotLight under it; the little grate on the road above
local function lightGrate(ctx: Ctx, plan: Plan.Plan, a: any)
	local kit, section = ctx.kit, ctx.section
	local CF = kit.roblox.CFrame
	local best, bs = math.huge, 0
	for k = 0, 400 do
		local s = plan.length * k / 400
		local p = Plan.at(plan, s)
		local d = (p.x - a.x) ^ 2 + (p.z - a.z) ^ 2
		if d < best then
			best, bs = d, s
		end
	end
	local p, d = Plan.at(plan, bs)
	local fr = kit:frame(p, d)
	local crown = section.spring + section.innerHalf
	local ic, im = (Section.PALETTE :: any).iron[1], (Section.PALETTE :: any).iron[2]
	local glow = { 214, 226, 236 }
	kit:box(
		ctx.dressing,
		"LightGrateGlow",
		fr,
		-0.7,
		0.7,
		crown - 0.2,
		crown - 0.16,
		-0.45,
		0.45,
		glow,
		"SmoothPlastic",
		{
			visual = true,
			shadow = false,
		}
	)
	for k = -3, 3 do
		local x = k * 0.2
		kit:box(ctx.dressing, "LightGrateBar", fr, x - 0.04, x + 0.04, crown - 0.3, crown - 0.2, -0.5, 0.5, ic, im, {
			visual = true,
		})
	end
	local at = fr * CF.new(0, crown - 0.4, 0)
	local holder = kit:at(ctx.shell, "LightGrateLight", at, { 0.2, 0.2, 0.2 }, { 0, 0, 0 }, "SmoothPlastic", {
		visual = true,
		transparency = 1,
		shadow = false,
	})
	Lamps.spot(kit, holder, "LightGrate", at * CF.Angles(-math.pi / 2, 0, 0), ctx.pipe.space, "lightGrate", {
		Color = kit:color({ 236, 240, 246 }),
		Angle = 50,
	})
	local road = Pipe.ROAD_TOP[ctx.pipe.id]
	if road then
		local g = CF.new(a.x, road + 0.02, a.z) * CF.Angles(0, math.atan2(d.x, d.z), 0)
		kit:at(
			ctx.dressing,
			"RoadGrateFrame",
			g,
			{ 1.0, 0.04, 1.7 },
			{ 64, 66, 68 },
			"CorrodedMetal",
			{ visual = true }
		)
		for k = -2, 2 do
			kit:at(
				ctx.dressing,
				"RoadGrateSlot",
				g * CF.new(k * 0.17, 0.021, 0),
				{ 0.07, 0.005, 1.4 },
				{ 14, 14, 16 },
				"SmoothPlastic",
				{
					visual = true,
					shadow = false,
				}
			)
		end
	end
end

-- the sound cue points along the pipe (the mouths', ladders' and outlets' are gathered where those are built)
local function soundPoints(ctx: Ctx, plans: { Plan.Plan })
	local section, pipe, layout = ctx.section, ctx.pipe, ctx.layout
	local high = section.spring + section.innerHalf - 0.4
	for _, plan in plans do
		local s = Cues.DRIP_EVERY / 2
		while s < plan.length do
			local q = Plan.at(plan, s)
			ctx.cue("sewer.drip", q.x, q.y + high, q.z)
			s += Cues.DRIP_EVERY
		end
	end
	local first = plans[1]
	local mid = Plan.at(first, first.length / 2)
	ctx.cue("sewer.hiss", mid.x, mid.y + (section.water or 0), mid.z)
	local function nearest(score: (q: Plan.Vec3) -> number): Plan.Vec3
		local best, bq = math.huge, mid
		for k = 0, 400 do
			local q = Plan.at(first, first.length * k / 400)
			local d = score(q)
			if d < best then
				best, bq = d, q
			end
		end
		return bq
	end
	if pipe.id == "P2" then
		-- the middle of the river (its bed runs x 2017 .. 2277)
		local q = nearest(function(p)
			return math.abs(p.x - 2147)
		end)
		ctx.cue("sewer.riverHum", q.x, q.y + high, q.z)
	end
	for _, ch in layout.chambers do
		if ch.id == pipe.chamber then
			ctx.cue("sewer.carOverhead", ch.x, ch.y + high, ch.z)
		end
	end
	for _, a in layout.anchors do
		if a.kind == "lightGrate" and a.pipe == pipe.id and pipe.chamber == nil then
			ctx.cue("sewer.carOverhead", a.x, a.y + high, a.z)
		end
	end
	if pipe.id == "P3" then
		-- the trolley's rails run along the boulevard at z 18.4 .. 24.8
		local q = nearest(function(p)
			return math.abs(p.z - 21.6)
		end)
		ctx.cue("sewer.trolleyOverhead", q.x, q.y + high, q.z)
	end
end

function Pipe.build(
	kit: Kit.Kit,
	root: any,
	layout: any,
	pipe: any,
	art: any
): { slots: number, lamps: number, cues: number, plans: { Plan.Plan } }
	local r = kit.roblox
	local section = layout.data.sections[pipe.section]
	local model = kit:model(root, pipe.id, { Pipe = pipe.id, Space = pipe.space, Name = pipe.name, Sign = pipe.sign })
	model.ModelStreamingMode = r.Enum.ModelStreamingMode.Atomic
	local artFolder: any
	local made = 0 -- art slots made (passage modules, the junction, the plaques)
	local cues: { Cues.Point } = {}
	local ctx: Ctx
	ctx = {
		kit = kit,
		layout = layout,
		pipe = pipe,
		art = art,
		section = section,
		shell = kit:model(model, "Shell"),
		lining = kit:model(model, "Lining"),
		dressing = nil :: any,
		slot = function(name: string, variant: string, pivot: any)
			made += 1
			local entry = art and art.modules and art.modules[variant]
			kit:model(artFolder, name, {
				ArtModule = variant,
				ArtAsset = if entry and entry.assetId then tostring(entry.assetId) else "",
				ArtPivot = pivot,
				Pipe = pipe.id,
				Space = pipe.space,
			})
		end,
		cue = function(name: string, x: number, y: number, z: number)
			table.insert(cues, { cue = name, x = x, y = y, z = z })
		end,
		tops = {},
		slots = 0,
	}
	artFolder = kit:folder(model, "Art")
	local mouths = kit:model(model, "Mouths")
	ctx.dressing = kit:model(model, "Dressing")

	-- the mouths first: their frames give the shafts' tops
	for _, m in layout.mouthsOf(pipe.id) do
		ctx.tops[m.id] = Mouth.build(kit, mouths, m, pipe.space).under
		ctx.cue("sewer.grateIn", m.x, m.y + 0.3, m.z)
		ctx.cue("sewer.grateOut", m.x, m.y + 0.3, m.z)
		ctx.cue("sewer.streetMurmur", m.x, m.y + 1.5, m.z)
	end

	-- the passages, their art slots, the shafts at their ends, their dressing
	local chamber: any = nil
	for _, ch in layout.chambers do
		if ch.id == pipe.chamber then
			chamber = ch
		end
	end
	local into = if chamber then chamber.half - section.innerHalf else 0
	local plans: { Plan.Plan } = {}
	for _, pass in pipe.passages do
		local lane = if section.routeOffset > 0 then pass.side else 0
		local plan = Plan.plan(layout, pipe, pass, { variants = (Pipe.VARIANTS :: any)[section.kind] })
		table.insert(plans, plan)
		shell(ctx, plan, lane, into)
		slots(ctx, plan, lane)
		for _, e in plan.ends do
			local m = e.mouth
			ctx.cue("sewer.rung", m.shaft.cx, (m.shaft.bottom + ctx.tops[m.id]) / 2, m.shaft.cz)
			Shaft.walls(kit, ctx.shell, m, ctx.tops[m.id], section)
			Shaft.roof(kit, ctx.shell, m, section)
			Shaft.ladder(kit, ctx.shell, m, ctx.tops[m.id])
		end
		dress(ctx, plan, lane)
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
	local nLamps = Lamps.build(kit, ctx.shell, pipe, layout.anchors, covered, ctx.shell)

	-- the chamber, the signs, the light grates
	if chamber then
		Chamber.build(kit, {
			lining = ctx.lining,
			shell = ctx.shell,
			dressing = ctx.dressing,
			section = section,
			space = pipe.space,
			slot = ctx.slot,
		}, chamber, layout.anchors)
	end
	for _, a in layout.anchors do
		if a.pipe == pipe.id and a.kind == "sign" then
			Dressing.sign(kit, ctx.dressing, a)
		elseif a.pipe == pipe.id and a.kind == "lightGrate" and chamber == nil then
			lightGrate(ctx, plans[1], a)
		end
	end

	soundPoints(ctx, plans)
	local nCues = Cues.build(kit, ctx.shell, pipe, cues)
	return { slots = made, lamps = nLamps, cues = nCues, plans = plans }
end

return Pipe
