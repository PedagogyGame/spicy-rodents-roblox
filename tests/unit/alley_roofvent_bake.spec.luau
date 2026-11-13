--!strict
-- The rooftop vent as baked (tools/bake/alley/RoofVent; BRIEF_ADDENDUM D9: "an elaborate roof based vent"), on the
-- alley baked in memory by its own bake code (tests/lib/BakedWorld.bakeAlley), held to route 9107
-- (Shared/Attractions/AlleyRoof) and the enclosed-run contract (Shared/Routes/Enclosure):
--   * the body's section (1.6 wide, 1.7 high) swept along 9107 meets nothing, seen or colliding, and the body's box
--     where each mouth launches it is clear (BakedWorld.clearance, mouthClearance);
--   * the louvre's sill is the roof membrane, the boot's floor is the D 16.5 truss's plate (route 9120's line);
--   * between the mouths the run is closed: walls either side and a roof over it all the way (the squirrel is out of
--     sight in there: Enclosure.hidden), and the only ways out are the bent slat and the boot;
--   * the unit is what the owner asked for, elaborate: the louvre bank with one bent slat, the filter rack, the coil,
--     the blower, the plenum, the exhaust stack with a fan the client turns, the flanged duct, the drop and the boot's
--     grille, the access doors and the plate; within its part budget.
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local AlleyRoof = require("@shared/Attractions/AlleyRoof")
local Registry = require("@shared/Routes/Registry")
local Motion = require("@shared/Routes/Motion")
local BakedWorld = require("../lib/BakedWorld")
local Spinners = require("@client/World/Spinners")

local R = AlleyRoof

return function(t)
	local world, place, root = BakedWorld.bakeAlley()
	local records = R.records(place)
	local registry = Registry.fromRecords(records :: any)
	local vent = registry:get(R.VENT) :: Registry.Route
	local function toLocal(x: number, y: number, z: number): (number, number, number)
		return AlleyLayout.toLocal(place, x, y, z)
	end

	t.test("the body swept along 9107 meets nothing, seen or colliding; both mouths launch it clear", function()
		local hits = BakedWorld.clearance(world, registry, vent, { step = 0.1 })
		local names = {}
		for _, b in hits do
			table.insert(
				names,
				`{b.path} (t {string.format("%.3f", b.t0)}..{string.format("%.3f", b.t1)}, {b.studs} st)`
			)
		end
		t.eq(#hits, 0, table.concat(names, "; "))
		for _, m in BakedWorld.mouthClearance(world, registry, vent) do
			local list = {}
			for _, p in m.parts do
				table.insert(list, p.path)
			end
			t.eq(#m.parts, 0, `the {m.mouth} mouth launches into {table.concat(list, ", ")}`)
		end
		print(`      9107: {string.format("%.1f", vent.length)} st swept clear at 0.1 st`)
	end)

	t.test("the louvre's sill is the roof; the boot's floor is the plate the chord route runs on", function()
		local mouth = registry:pointAt(vent, 0)
		local g = world.groundAt(mouth.x, mouth.z, mouth.y)
		t.near(g, mouth.y, 0.05, "the louvre's sill")
		local _, gy = toLocal(mouth.x, g, mouth.z)
		t.near(gy, R.WING_ROOF.y, 0.01, "the sill is the membrane")
		local boot = registry:pointAt(vent, 1)
		t.near(world.groundAt(boot.x, boot.z, boot.y), boot.y, 0.05, "the boot's floor")
		local chord = registry:get(R.FIRST_RAFTER) :: Registry.Route
		local c0 = registry:pointAt(chord, 0)
		t.near(c0.x, boot.x, 1e-3)
		t.near(c0.y, boot.y, 1e-3)
		t.near(c0.z, boot.z, 1e-3)
	end)

	t.test("between the mouths the run is closed: walls either side and a roof over it all the way", function()
		local motorish = { registry = registry } :: any
		local spec = vent.enclosure :: any
		local w0 = (spec.mouths[1].reach + 0.6) / vent.length
		local w1 = 1 - (spec.mouths[2].reach + 0.6) / vent.length
		local open = 0
		local n = 0
		for i = 0, 200 do
			local tt = w0 + (w1 - w0) * i / 200
			local sec = Motion.section(motorish, vent, tt) :: Motion.Section
			local p = registry:pointAt(vent, tt)
			local mid = 0.85
			local cx, cy, cz = p.x + sec.up.x * mid, p.y + sec.up.y * mid, p.z + sec.up.z * mid
			local function hits(dx: number, dy: number, dz: number, reach: number): boolean
				local h = world.raycast(cx, cy, cz, dx * reach, dy * reach, dz * reach, function(q)
					return q.collide
				end)
				return h ~= nil
			end
			-- (either side within reach; overhead, where the body stands upright, the channel's deck, the duct's top or
			-- the drop's top; down the drop the body's back is to the open boot)
			local s, u = sec.side, sec.up
			local closed = hits(s.x, s.y, s.z, 1.5)
				and hits(-s.x, -s.y, -s.z, 1.5)
				and (u.y < 0.7 or hits(0, 1, 0, 3.5))
			if not closed then
				open += 1
				local X, Y, D = toLocal(p.x, p.y, p.z)
				print(`      open at t {string.format("%.3f", tt)} ({X}, {Y}, {D})`)
			end
			n += 1
		end
		t.eq(open, 0, `{open} of {n} samples between the mouths are open to a side or above`)
	end)

	t.test(
		"elaborate, within budget: louvres with one bent slat, the plant, the stack's fan, the duct, the boot",
		function()
			local unit = root:FindFirstChild("RoofVent") :: any
			t.truthy(unit ~= nil, "the RoofVent model")
			local counts: { [string]: number } = {}
			local parts = 0
			for _, d in unit:GetDescendants() do
				if d:IsA("BasePart") then
					counts[d.Name] = (counts[d.Name] or 0) + 1
					parts += 1
				end
			end
			t.truthy((counts.Slat or 0) >= 12, `{counts.Slat} louvre slats`)
			t.eq(counts.BentSlat, 1, "one bent slat")
			for _, name in
				{
					"FilterRack",
					"Coil",
					"BlowerScroll",
					"PlenumRamp",
					"PlenumStep",
					"Stack",
					"DuctFloor",
					"Flange",
					"DropSide",
					"BootGrille",
					"Door1",
					"UnitPlate",
					"ChannelLamp",
				}
			do
				t.truthy((counts[name] or 0) >= 1, name)
			end
			local fan = unit:FindFirstChild("Fan")
			t.truthy(fan ~= nil and (fan:GetAttribute("SpinRpm") or 0) > 0, "the fan turns (SpinRpm)")
			t.truthy(fan.PrimaryPart ~= nil and fan.PrimaryPart.Name == "Hub", "about its hub (Client/World/Spinners)")
			local rpm = fan:GetAttribute("SpinRpm") :: number
			t.near(Spinners.angleAt(rpm, 60 / rpm / 2), math.pi, 1e-9, "half a turn in half a revolution's time")
			t.near(Spinners.angleAt(rpm, 60 / rpm * 3), 0, 1e-9, "and back where it started after three")
			t.eq(counts.Blade, 5, "five blades")
			t.truthy(parts <= 140, `the vent is {parts} parts`)
			print(`      the vent: {parts} parts`)
		end
	)
end
