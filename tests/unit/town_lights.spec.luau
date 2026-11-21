--!strict
-- Client/Render/TownLights: night lighting for the baked buildings. The state follows the street-lamp
-- level with hysteresis (dusk never flickers); fixtures stay lit by day and glow at night; tagged home
-- windows are glass by day and warm at night; day restores exactly what was baked. Run against a real
-- lot Model built by the Lune bake.
local roblox = require("@lune/roblox")
local Bake = require("@worldgen/Bake")
local Factory = require("@worldgen/Factory")
local Greybox = require("@worldgen/Builders/Greybox")
local TownLights = require("@client/Render/TownLights")

return function(t)
	t.test("hysteresis: night begins above 0.35 and ends below 0.25; in between nothing changes", function()
		t.eq(TownLights.next(false, 0), false)
		t.eq(TownLights.next(false, 0.3), false)
		t.eq(TownLights.next(false, 0.35), false)
		t.eq(TownLights.next(false, 0.36), true)
		t.eq(TownLights.next(true, 0.3), true)
		t.eq(TownLights.next(true, 0.25), true)
		t.eq(TownLights.next(true, 0.24), false)
		-- a level wobbling round either threshold switches once, not every frame
		local night, flips = false, 0
		for i = 0, 400 do
			local level = 0.30 + 0.04 * math.sin(i * 0.7) + i * 0.0005
			local now = TownLights.next(night, level)
			if now ~= night then
				flips += 1
				night = now
			end
		end
		t.eq(night, true)
		t.eq(flips, 1)
	end)

	t.test("look: fixtures are lit by day and glow at night; windows are glass by day, warm at night", function()
		local day, dark = TownLights.look(false, "fixture"), TownLights.look(true, "fixture")
		t.eq(day.neon, false)
		t.eq(day.scale, 1) -- the baked brightness: a room is never black
		t.eq(dark.neon, true)
		t.truthy(dark.scale > 1 and dark.scale <= 1.5, "a little brighter at night")
		t.eq(dark.warm, false)
		t.eq(TownLights.look(false, "window").neon, false)
		t.eq(TownLights.look(false, "window").warm, false)
		t.eq(TownLights.look(true, "window").neon, true)
		t.eq(TownLights.look(true, "window").warm, true)
	end)

	t.test("a baked house: every tagged part is found, lit for the night and restored by day", function()
		local factory = Factory.new({
			Instance = roblox.Instance,
			Vector3 = roblox.Vector3,
			CFrame = roblox.CFrame,
			Color3 = roblox.Color3,
			Enum = roblox.Enum,
			UDim2 = roblox.UDim2,
			ColorSequence = roblox.ColorSequence,
		})
		local env = { Enum = roblox.Enum, Color3 = roblox.Color3 }
		local seen = 0
		for _, p in Bake.plans(Bake.data()) do
			if p.id == "core_house_3_blue_cottage" or p.id == "quay_bldg_w_00" or p.id == "hospital_main" then
				seen += 1
				local model = Greybox.build(p, factory)
				local entries = TownLights.gather(model)
				t.eq(#entries, model:GetAttribute("NightLights"), p.id)
				local fixtures, windows = 0, 0
				for _, e in entries do
					if e.kind == "fixture" then
						fixtures += 1
						t.truthy(e.light ~= nil and e.brightness > 0.5, e.part.Name)
						t.eq(e.light.Enabled, true)
					else
						windows += 1
						t.eq(e.material, roblox.Enum.Material.Glass, e.part.Name)
					end
				end
				t.eq(fixtures, model:GetAttribute("RoomLights") or 0, p.id)
				if p.id ~= "hospital_main" then
					t.truthy(windows >= 4, `{p.id}: {windows} windows glow`)
				end
				for _, e in entries do
					TownLights.apply(e, true, env)
					t.eq(e.part.Material, roblox.Enum.Material.Neon, e.part.Name)
					if e.kind == "window" then
						t.near(e.part.Color.R * 255, 255, 0.6)
						t.near(e.part.Color.B * 255, 152, 0.6)
					else
						t.near(e.light.Brightness, e.brightness * 1.25, 1e-5)
						t.eq(e.light.Enabled, true)
					end
				end
				for _, e in entries do
					TownLights.apply(e, false, env)
					t.eq(e.part.Material, e.material, e.part.Name)
					t.eq(e.part.Color, e.color, e.part.Name)
					if e.light then
						t.near(e.light.Brightness, e.brightness, 1e-6)
					end
				end
			end
		end
		t.eq(seen, 3)
	end)
	t.test("staggered (owner 1.1): each building light has its own moment; a fifth come on before the lamps", function()
		local n, early, delays = 400, 0, {}
		local least, most = math.huge, 0
		for i = 1, n do
			local on, off, e = TownLights.stagger("core_house_" .. (i % 20), i * 3.7, 4 + (i % 3) * 9, -i * 2.1)
			t.truthy(on >= 0 and on <= TownLights.HOUSE_ON + TownLights.ROOM_ON, "on within the spread")
			t.truthy(off >= 0 and off <= TownLights.OFF_SPREAD, "off within the spread")
			least, most = math.min(least, on), math.max(most, on)
			delays[math.floor(on / 10)] = true
			if e then
				early += 1
				t.truthy(e >= TownLights.EARLY_LO and e < TownLights.ON, "an early bird lights under the lamps' level")
			end
			-- the same light, the same moment (every client agrees)
			local on2, off2, e2 = TownLights.stagger("core_house_" .. (i % 20), i * 3.7, 4 + (i % 3) * 9, -i * 2.1)
			t.truthy(on == on2 and off == off2 and e == e2, "stable")
		end
		t.truthy(most - least > 40, `varied: {least} .. {most} s after the lamps`)
		local buckets = 0
		for _ in delays do
			buckets += 1
		end
		t.truthy(buckets >= 6, "spread across the evening, not bunched")
		t.truthy(early > n * 0.1 and early < n * 0.32, `about a fifth early: {early} of {n}`)
		-- two lights of one house differ, and so do two houses
		local a = TownLights.stagger("core_house_1", 1, 4, 1)
		local b = TownLights.stagger("core_house_1", 9, 4, 1)
		local c = TownLights.stagger("core_house_2", 1, 4, 1)
		t.truthy(a ~= b and a ~= c)
	end)

	t.test(
		"want: on at its own delay after the lamps, kept through the night, off at its own delay after day",
		function()
			local e: any = { delayOn = 20, delayOff = 10, early = nil, on = false }
			t.falsy(TownLights.want(e, true, 5, 0.5), "night, not yet its moment")
			t.truthy(TownLights.want(e, true, 20, 0.5), "its moment")
			e.on = true
			t.truthy(TownLights.want(e, true, 0, 1), "once on, on through the night")
			t.truthy(TownLights.want(e, false, 5, 0.2), "morning: still on a while")
			t.falsy(TownLights.want(e, false, 10, 0.2), "then dark")
			e.on = false
			t.falsy(TownLights.want(e, false, 100, 0.3), "day: dark, whatever the dusk level, unless an early bird")
			local bird: any = { delayOn = 50, delayOff = 5, early = 0.2, on = false }
			t.truthy(TownLights.want(bird, false, 1000, 0.25), "an early bird lights at dusk, before the lamps")
			t.falsy(TownLights.want(bird, false, 1000, 0.15), "not before its own level")
			t.truthy(TownLights.want(bird, true, 0, 0.4), "and is on when the lamps come on")
		end
	)
end
