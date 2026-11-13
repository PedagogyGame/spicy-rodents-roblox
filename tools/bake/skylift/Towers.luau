--!strict
-- tools/bake/skylift/Towers: the sky lift's nine line towers and its far-view layer (BATCH2 item 36: "towers and
-- cable visible from town"; §2.2 Skyline rule).
--   f4_lift_tower_<k> (Model, Atomic, one per SkyLift.towers() head): a concrete footing on the slope, a
--     galvanised lattice that tapers from a wide base to a narrow column BELOW the passing cabins (the cabins
--     clear its column by about a stud either side), a head cap, a crossarm over both strands and a sheave
--     train riding on each strand (the wheels sit on the rope: the cabins' hangers pass under nothing), and a
--     number plate. Attributes Tower = k, CableY.
--   f4_lift_base_Skyline (Model, Persistent, <= SKYLINE_BUDGET parts): for each tower a slim core mast and a crossarm,
--     both inside the detailed tower's own volume (so they vanish behind it when the tower streams in), and the
--     haul rope's straight spans between the two stations (every loop segment longer than SPAN_MIN): the rope
--     is drawn only here, so it is never missing and never doubled.
-- Interface: build(roblox, parent) -> { Model }; skyline(roblox, parent) -> Model;
--   TOWER_BUDGET, SKYLINE_BUDGET, ROPE_D

local Common = require("./Common")
local Kit = require("../alley/Kit")
local SkyLift = require("../../../src/shared/Rides/SkyLift")

local Towers = {}

Towers.TOWER_BUDGET = 36
-- the masts and arms (18) and the rope: 2 strands x (11 open spans + the extra chords across the steepest
-- towers' vertical blends, SkyLift.ROPE_SAG)
Towers.SKYLINE_BUDGET = 66 -- 18 + 48 rope pieces on the compiled data

Towers.ROPE_D = 0.34
Towers.NECK_BELOW = 13 -- the lattice narrows this far under the cable head (cabin floors hang 10.5 below it)
Towers.HALF_WIDE = 2.5 -- lattice half-width at the footing
Towers.HALF_NARROW = 0.85 -- ... and over the neck (a cabin's inner side passes 2 from the centre line)

local LEG_D = 0.42
local BRACE_D = 0.2

local function ridePoints(): { { number } }
	for _, r in Common.expansion().rides do
		if r.id == SkyLift.RIDE_ID then
			return r.points
		end
	end
	error("skylift bake: no ride sky_lift")
end

-- grade of the line in the tower's +D direction before (D < 0) and after (D > 0) its head
local function grades(k: number): (number, number)
	local P = ridePoints()
	local a, b, c = P[k + 1], P[k + 2], P[k + 3]
	local hb = math.sqrt((b[1] - a[1]) ^ 2 + (b[3] - a[3]) ^ 2)
	local hf = math.sqrt((c[1] - b[1]) ^ 2 + (c[3] - b[3]) ^ 2)
	return (b[2] - a[2]) / hb, (c[2] - b[2]) / hf
end

local function towerKit(roblox: any, t: SkyLift.Tower): Kit.Kit
	return Kit.new(roblox, { x = t.x, z = t.z, floorY = 0, yaw = t.yaw })
end

-- lowest and highest ground under a square of half-size r round the tower's foot
local function groundRange(kit: Kit.Kit, r: number): (number, number)
	local lo, hi = math.huge, -math.huge
	for i = -2, 2 do
		for j = -2, 2 do
			local p = kit:cf(i * r / 2, 0, j * r / 2).Position
			local g = Common.ground(p.X, p.Z)
			lo, hi = math.min(lo, g), math.max(hi, g)
		end
	end
	return lo, hi
end

-- a sheave (diameter 1.2, 0.32 thick, axle across the line) at tower-local (x, cy, d): its box's corners, edge
-- middles and centre all clear of the cabins' swept volume by SHEAVE_MARGIN
Towers.SHEAVE_MARGIN = 0.05
local function wheelClear(kit: Kit.Kit, x: number, cy: number, d: number): boolean
	for _, i in { -1, 0, 1 } do
		for _, j in { -1, 0, 1 } do
			for _, k in { -1, 0, 1 } do
				local p = kit:cf(x + i * 0.16, cy + j * 0.6, d + k * 0.6).Position
				if not SkyLift.sweptClear(p.X, p.Y, p.Z, Towers.SHEAVE_MARGIN) then
					return false
				end
			end
		end
	end
	return true
end

function Towers.build(roblox: any, parent: any): { any }
	local out = {}
	for _, t in SkyLift.towers() do
		local k = t.index
		local kit = towerKit(roblox, t)
		local m = kit:model(parent, `f4_lift_tower_{k}`)
		m.ModelStreamingMode = roblox.Enum.ModelStreamingMode.Atomic
		m:SetAttribute("Tower", k)
		m:SetAttribute("CableY", t.y)
		m:SetAttribute("Family", Common.FAMILY)
		m:SetAttribute("PartBudget", Towers.TOWER_BUDGET)
		local gb, gf = grades(k)
		local cable = t.y
		local lo, hi = groundRange(kit, 3.4)
		local foot = hi + 0.6
		-- footing: a concrete block from under the low side to just over the high side
		kit:box(m, "Footing", -3.2, 3.2, lo - 1.6, foot, -3.2, 3.2, Common.CONCRETE, "Concrete")
		kit:box(m, "Plinth", -2.8, 2.8, foot, foot + 0.35, -2.8, 2.8, Common.CONCRETE_DARK, "Concrete")
		local base = foot + 0.35
		local neck = cable - Towers.NECK_BELOW - math.max(math.abs(gb), math.abs(gf)) * 4
		local head = cable + 0.9
		local W, N = Towers.HALF_WIDE, Towers.HALF_NARROW
		local steel = Common.STEEL
		local lattice = { collide = true, query = true }
		-- four legs: the taper, then the straight column
		for _, c in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
			local sx, sd = c[1], c[2]
			kit:rod(m, "Leg", sx * W, base, sd * W, sx * N, neck, sd * N, LEG_D, steel, "Metal", lattice)
			kit:rod(m, "Leg", sx * N, neck, sd * N, sx * N, head, sd * N, LEG_D, steel, "Metal", lattice)
		end
		-- bracing on the taper: an X on the faces across the line (the side faces are left open: the budget)
		local function wAt(y: number): number
			return W + (N - W) * (y - base) / (neck - base)
		end
		for _, sd in { -1, 1 } do
			local w0, w1 = wAt(base + 0.3), wAt(neck - 0.3)
			kit:rod(m, "Brace", -w0, base + 0.3, sd * w0, w1, neck - 0.3, sd * w1, BRACE_D, steel, "Metal")
			kit:rod(m, "Brace", w0, base + 0.3, sd * w0, -w1, neck - 0.3, sd * w1, BRACE_D, steel, "Metal")
		end
		-- the ring where the taper meets the column
		for _, y in { neck } do
			local w = wAt(y)
			for _, e in { { -1, -1, 1, -1 }, { 1, -1, 1, 1 }, { 1, 1, -1, 1 }, { -1, 1, -1, -1 } } do
				kit:rod(m, "Ring", e[1] * w, y, e[2] * w, e[3] * w, y, e[4] * w, BRACE_D, steel, "Metal")
			end
		end
		-- zig-zag bracing up the column, on the faces across the line
		local panels = math.max(1, math.floor((head - neck) / 4.5))
		for _, sd in { -1, 1 } do
			for p = 1, panels do
				local y0 = neck + (head - neck) * (p - 1) / panels
				local y1 = neck + (head - neck) * p / panels
				local s = if p % 2 == 1 then 1 else -1
				kit:rod(m, "Brace", -s * N, y0, sd * N, s * N, y1, sd * N, BRACE_D, steel, "Metal")
			end
		end
		-- head cap and crossarm (over both strands, clear of the grips: they reach 0.6 over the rope)
		kit:box(m, "HeadCap", -1.25, 1.25, head, cable + 1.9, -1.25, 1.25, Common.STEEL_DARK, "Metal")
		local arm = SkyLift.STRAND + 1.6
		kit:box(m, "Crossarm", -arm, arm, cable + 1.9, cable + 2.7, -0.42, 0.42, steel, "Metal")
		-- sheave trains: two wheels on each strand, their bottoms over the rope by more than a grip's reach
		for _, side in { 1, -1 } do
			local x = side * SkyLift.STRAND
			local wheels = {}
			for _, d in { -1.35, 1.35 } do
				-- the rope under this wheel, on the blended profile (d < 0: toward the base)
				local rope = SkyLift.heightAt(t.h + d)
				-- as low over the rope as the passing grips allow: the lowest centre whose wheel box clears the
				-- cabins' swept volume by SHEAVE_MARGIN (the grips reach GRIP_ABOVE over the rope)
				local cy = rope + SkyLift.GRIP_ABOVE + 0.6
				while not wheelClear(kit, x, cy, d) and cy < rope + 4 do
					cy += 0.05
				end
				table.insert(wheels, { d, cy })
				kit:cyl(m, "Sheave", x, cy, d, 0.32, 1.2, "X", Common.STEEL_DARK, "Metal", {
					collide = false,
					query = false,
				})
			end
			-- the train's side plate from axle to axle, and its hanger up to the crossarm
			local a, b = wheels[1], wheels[2]
			local top = math.max(a[2], b[2])
			kit:rod(m, "TrainPlate", x - 0.28, a[2], a[1], x - 0.28, b[2], b[1], 0.3, steel, "Metal")
			kit:box(m, "TrainHanger", x - 0.45, x - 0.15, top, cable + 1.9, -0.2, 0.2, steel, "Metal")
		end
		-- the tower's number, on the footing's face toward the base station
		local plate =
			kit:box(m, "NumberPlate", -0.7, 0.7, foot - 1.35, foot - 0.15, -3.28, -3.2, Common.CREAM, "SmoothPlastic", {
				collide = false,
				query = false,
			})
		local g = kit:gui(plate, "Back", 40)
		kit:label(g, { Text = tostring(k), TextColor = Common.RED_DARK, Font = "GothamBlack" })
		table.insert(out, m)
	end
	return out
end

-- The far-view layer (the rope's open spans: Common.ropeSegments().spans).
function Towers.skyline(roblox: any, parent: any): any
	local kit0 = Common.worldKit(roblox)
	local m = kit0:model(parent, "f4_lift_base_Skyline")
	m.ModelStreamingMode = roblox.Enum.ModelStreamingMode.Persistent
	m:SetAttribute("Family", Common.FAMILY)
	m:SetAttribute("PartBudget", Towers.SKYLINE_BUDGET)
	local far = { collide = false, query = false, shadow = true }
	for _, t in SkyLift.towers() do
		local kit = towerKit(roblox, t)
		local _, hi = groundRange(kit, 3.4)
		local base = hi + 0.95
		kit:box(m, `Mast{t.index}`, -0.5, 0.5, base, t.y + 0.9, -0.5, 0.5, Common.STEEL, "Metal", far)
		local arm = SkyLift.STRAND + 1.5
		kit:box(m, `Arm{t.index}`, -arm, arm, t.y + 1.95, t.y + 2.65, -0.36, 0.36, Common.STEEL, "Metal", far)
	end
	local n = 0
	for _, seg in Common.ropeSegments().spans do
		n += 1
		Common.rodW(kit0, m, `Span{n}`, seg[1], seg[2], Towers.ROPE_D, Common.ROPE, "Metal", far)
	end
	m:SetAttribute("Spans", n)
	return m
end

return Towers
