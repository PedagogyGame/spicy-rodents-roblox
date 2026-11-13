--!strict
-- tools/bake/sewers/Plan: how one passage (Shared/World/SewerLayout: points from the end wall behind a shaft to the
-- other end wall or the chamber's port, at walkway height, on the art module's axis) is cut up for the bake:
--   legs    the straight stretches between bends and changes of grade (each drawn in its own frame)
--   ends    at a shaft, a "box" run from the end wall to the far side of the shaft's hole: a brick chamber with a
--           flat roof the shaft opens through (the owner's modules have no hole in their vault for a shaft)
--   slots   where the owner's 12-stud module goes (data/art/sewer_modules.json): on a 12-stud grid from the start
--           end wall, so each slot's centre is a lamp anchor and his fixture is where the lamp is; P1's arms are
--           laid from the chamber's port back instead, so two modules fit each arm and meet the junction exactly
--   runs    everything between, in order: "box" (an end), "lining" (under a slot: the parts drawing of the module,
--           hidden once his art is in) and "filler" (an arched stretch no whole module fits: parts, always shown)
-- Positions along a passage are plan studs from its first point (s). Pure (no Instances).
-- Interface: plan(layout, pipe, passage, opts?) -> Plan; Plan.at(plan, s) -> (point, along) (along: the unit 3D
--   direction of the leg there); Plan.slotFrame(plan, slot) -> { origin, along, flip }

local SewerLayout = require("../../../src/shared/World/SewerLayout")

local Plan = {}

Plan.MODULE = 12 -- studs: the owner's passage modules (01, 03) are 12 m long at one stud a metre
Plan.FOLD = 4.0 -- studs: a filler shorter than this beside a shaft chamber is folded into the chamber

export type Vec3 = { x: number, y: number, z: number }
export type Leg = { s0: number, s1: number, a: Vec3, b: Vec3 }
-- a box run's endWall and header: "z0" or "z1", the end of this piece they stand at (nil: not on this piece)
export type Run = { kind: string, s0: number, s1: number, leg: number, endWall: string?, header: string? }
export type Slot = { s0: number, s1: number, index: number, variant: string }
export type End = { mouth: SewerLayout.Mouth, s0: number, s1: number, atStart: boolean }
export type Plan = {
	pipe: SewerLayout.Pipe,
	passage: SewerLayout.Passage,
	length: number,
	legs: { Leg },
	ends: { End },
	slots: { Slot },
	runs: { Run },
}

local function plan2(a: Vec3, b: Vec3): number
	return math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
end

-- the straight legs: consecutive points whose direction and grade agree are one leg
local function legsOf(points: { Vec3 }): { Leg }
	local legs: { Leg } = {}
	local s = 0
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local len = plan2(a, b)
		if len < 1e-6 then
			continue
		end
		local last = legs[#legs]
		if last then
			local la = plan2(last.a, last.b)
			local dx1, dz1, g1 = (last.b.x - last.a.x) / la, (last.b.z - last.a.z) / la, (last.b.y - last.a.y) / la
			local dx2, dz2, g2 = (b.x - a.x) / len, (b.z - a.z) / len, (b.y - a.y) / len
			if math.abs(dx1 - dx2) < 1e-4 and math.abs(dz1 - dz2) < 1e-4 and math.abs(g1 - g2) < 1e-4 then
				last.b = b
				last.s1 = s + len
				s += len
				continue
			end
		end
		table.insert(legs, { s0 = s, s1 = s + len, a = a, b = b })
		s += len
	end
	return legs
end

function Plan.at(p: Plan, s: number): (Vec3, Vec3)
	local legs = p.legs
	local leg = legs[#legs]
	for _, l in legs do
		if s <= l.s1 + 1e-9 then
			leg = l
			break
		end
	end
	local f = (s - leg.s0) / (leg.s1 - leg.s0)
	local a, b = leg.a, leg.b
	local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
	local l3 = math.sqrt(dx * dx + dy * dy + dz * dz)
	return { x = a.x + dx * f, y = a.y + dy * f, z = a.z + dz * f }, { x = dx / l3, y = dy / l3, z = dz / l3 }
end

-- along and across (left +) of a plan point, from the passage's first point on its first leg's heading
local function project(p: Plan, x: number, z: number, fromEnd: boolean): (number, number)
	local leg = if fromEnd then p.legs[#p.legs] else p.legs[1]
	local o = if fromEnd then leg.b else leg.a
	local l = plan2(leg.a, leg.b)
	local dx, dz = (leg.b.x - leg.a.x) / l, (leg.b.z - leg.a.z) / l
	local rx, rz = x - o.x, z - o.z
	return rx * dx + rz * dz, rx * dz - rz * dx
end

-- the shaft's hole (its inside square) along the passage: the nearest and farthest s it reaches
local function holeSpan(p: Plan, m: SewerLayout.Mouth, fromEnd: boolean): (number, number)
	local sh = m.shaft
	local h = sh.inside / 2
	local lo, hi = math.huge, -math.huge
	for _, c in { { -h, -h }, { -h, h }, { h, -h }, { h, h } } do
		local a = project(p, sh.cx + c[1], sh.cz + c[2], fromEnd)
		lo, hi = math.min(lo, a), math.max(hi, a)
	end
	if fromEnd then
		return p.length + lo, p.length + hi
	end
	return lo, hi
end

export type Opts = { variants: { full: string, plain: string, every: number, first: number }? }

function Plan.plan(layout: SewerLayout.Layout, pipe: SewerLayout.Pipe, passage: SewerLayout.Passage, opts: Opts?): Plan
	local o: Opts = opts or {}
	local legs = legsOf(passage.points)
	local p: Plan = {
		pipe = pipe,
		passage = passage,
		length = legs[#legs].s1,
		legs = legs,
		ends = {},
		slots = {},
		runs = {},
	}
	local L = p.length
	local first, last = passage.points[1], passage.points[#passage.points]
	-- the mouths whose shafts stand at this passage's ends
	for _, m in layout.mouthsOf(pipe.id) do
		local dStart = math.sqrt((m.shaft.cx - first.x) ^ 2 + (m.shaft.cz - first.z) ^ 2)
		local dEnd = math.sqrt((m.shaft.cx - last.x) ^ 2 + (m.shaft.cz - last.z) ^ 2)
		if dStart < 8 and m.route == passage.route then
			local _, hi = holeSpan(p, m, false)
			table.insert(p.ends, { mouth = m, s0 = 0, s1 = hi, atStart = true })
		elseif dEnd < 8 and m.route == passage.route and pipe.chamber == nil then
			local lo = holeSpan(p, m, true)
			table.insert(p.ends, { mouth = m, s0 = lo, s1 = L, atStart = false })
		end
	end
	table.sort(p.ends, function(a, b)
		return a.s0 < b.s0
	end)
	local free0 = 0
	local free1 = L
	for _, e in p.ends do
		if e.atStart then
			free0 = e.s1
		else
			free1 = e.s0
		end
	end
	-- the slots
	local M = Plan.MODULE
	local starts: { number } = {}
	if pipe.chamber ~= nil then
		local s = L - M
		while s >= free0 - 1e-6 do
			table.insert(starts, 1, s)
			s -= M
		end
	else
		local s = M
		while s + M <= free1 + 1e-6 do
			if s >= free0 - 1e-6 then
				table.insert(starts, s)
			end
			s += M
		end
	end
	local v = o.variants
	for i, s in starts do
		local variant = "brick"
		if v then
			variant = if (i - v.first) % v.every == 0 then v.full else v.plain
		end
		table.insert(p.slots, { s0 = s, s1 = s + M, index = i, variant = variant })
	end
	-- the runs: ends (box), slots (lining), fillers between, each cut at the legs' ends
	local cuts: { { kind: string, s0: number, s1: number, wall: string? } } = {}
	local cursor = 0
	local function add(kind: string, s0: number, s1: number, wall: string?)
		if s1 - s0 < 1e-6 then
			return
		end
		table.insert(cuts, { kind = kind, s0 = s0, s1 = s1, wall = wall })
	end
	local startEnd = nil :: End?
	local endEnd = nil :: End?
	for _, e in p.ends do
		if e.atStart then
			startEnd = e
		else
			endEnd = e
		end
	end
	if startEnd then
		add("box", 0, startEnd.s1, "start")
		cursor = startEnd.s1
	end
	local function filler(to: number)
		if to - cursor > 1e-6 then
			add("filler", cursor, to)
		end
		cursor = to
	end
	if #p.slots > 0 then
		filler(p.slots[1].s0)
		add("lining", p.slots[1].s0, p.slots[#p.slots].s1)
		cursor = p.slots[#p.slots].s1
	end
	if endEnd then
		filler(endEnd.s0)
		add("box", endEnd.s0, L, "end")
	else
		filler(L)
	end
	-- fold a filler too short to draw into the box run beside it
	local folded = {}
	for i, c in cuts do
		if c.kind == "filler" and c.s1 - c.s0 < Plan.FOLD then
			local prev, nxt = cuts[i - 1], cuts[i + 1]
			if prev and prev.kind == "box" then
				prev.s1 = c.s1
				continue
			elseif nxt and nxt.kind == "box" then
				nxt.s0 = c.s0
				continue
			end
		end
		table.insert(folded, c)
	end
	-- cut at the legs; a shaft chamber cut in two keeps its end wall on the piece at the passage's end and its
	-- header on the piece that meets the arched run
	for _, c in folded do
		for li, leg in legs do
			local a, b = math.max(c.s0, leg.s0), math.min(c.s1, leg.s1)
			if b - a > 1e-6 then
				local run: Run = { kind = c.kind, s0 = a, s1 = b, leg = li }
				if c.kind == "box" then
					local atStart = c.wall == "start"
					if atStart and math.abs(a - c.s0) < 1e-6 then
						run.endWall = "z0"
					elseif not atStart and math.abs(b - c.s1) < 1e-6 then
						run.endWall = "z1"
					end
					if atStart and math.abs(b - c.s1) < 1e-6 then
						run.header = "z1"
					elseif not atStart and math.abs(a - c.s0) < 1e-6 then
						run.header = "z0"
					end
				end
				table.insert(p.runs, run)
			end
		end
	end
	return p
end

-- where an art slot's module goes: its centre on the axis at walkway height, along the chord of its 12 studs, and
-- whether it is turned end for end (so the route runs the module's clear lane: data/art/sewer_modules.json lanes)
function Plan.slotFrame(p: Plan, slot: Slot): { origin: Vec3, along: Vec3, flip: boolean }
	local a = Plan.at(p, slot.s0)
	local b = Plan.at(p, slot.s1)
	local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
	local l = math.sqrt(dx * dx + dy * dy + dz * dz)
	return {
		origin = { x = (a.x + b.x) / 2, y = (a.y + b.y) / 2, z = (a.z + b.z) / 2 },
		along = { x = dx / l, y = dy / l, z = dz / l },
		flip = false,
	}
end

return Plan
