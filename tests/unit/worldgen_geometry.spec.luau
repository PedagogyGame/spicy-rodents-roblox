--!strict
-- WorldGen Geometry and Doors tests (BUILD_PLAN §4.4 #7): the pure rotation Geometry uses for
-- RouteCheck/DoorReach/roof plates equals the CFrame Factory builds (Ry * Rx * Rz), oriented-box
-- distance, cylinder axis angles, the room graph and server-owned door swing round trips.
local roblox = require("@lune/roblox")
local Geometry = require("@worldgen/Geometry")
local RoomGraph = require("@worldgen/RoomGraph")
local Doors = require("@worldgen/Doors")

return function(t)
	t.test("Geometry.rotate matches CFrame.Angles(0,yaw,0)*Angles(pitch,0,0)*Angles(0,0,roll)", function()
		local seed = 7
		local function rnd(a: number, b: number): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return a + (b - a) * seed / 2147483648
		end
		for _ = 1, 200 do
			local yaw, pitch, roll = rnd(-4, 4), rnd(-2, 2), rnd(-2, 2)
			local v = { rnd(-5, 5), rnd(-5, 5), rnd(-5, 5) }
			local cf = roblox.CFrame.Angles(0, yaw, 0) * roblox.CFrame.Angles(pitch, 0, 0) * roblox.CFrame.Angles(0, 0, roll)
			local w = cf * roblox.Vector3.new(v[1], v[2], v[3])
			local g = Geometry.rotate(v, yaw, pitch, roll)
			t.near(g[1], w.X, 1e-4)
			t.near(g[2], w.Y, 1e-4)
			t.near(g[3], w.Z, 1e-4)
			local back = Geometry.unrotate(g, yaw, pitch, roll)
			t.near(back[1], v[1], 1e-9)
			t.near(back[3], v[3], 1e-9)
		end
	end)

	t.test("frame point: model-local -Z is the front (LookVector)", function()
		local f = Geometry.frame(10, 2, -5, math.pi) -- q = 0: front +Z
		local x, y, z = Geometry.point(f, 0, 1, -3)
		t.near(x, 10, 1e-12)
		t.near(y, 3, 1e-12)
		t.near(z, -2, 1e-12)
	end)

	t.test("box distance and cylinder axis angles", function()
		local b = { cx = 0, cy = 0, cz = 0, yaw = math.pi / 4, pitch = 0, sx = 2, sy = 2, sz = 2 }
		t.near(Geometry.boxDistance(b, { 0, 0, 0 }), 0, 1e-12)
		t.near(Geometry.boxDistance(b, { 0, 3, 0 }), 2, 1e-12)
		t.near(Geometry.boxDistance(b, { math.sqrt(2) + 1, 0, 0 }), 1, 1e-9)
		local d = { 1, 2, -3 }
		local yaw, roll = Geometry.axisAngles(d)
		local x = Geometry.rotate({ 1, 0, 0 }, yaw, 0, roll)
		local n = math.sqrt(14)
		t.near(x[1], 1 / n, 1e-12)
		t.near(x[2], 2 / n, 1e-12)
		t.near(x[3], -3 / n, 1e-12)
		local ix = Geometry.index(16)
		Geometry.add(ix, { box = b, owner = "b" })
		Geometry.add(ix, { a = { 30, 0, 0 }, b = { 40, 0, 0 }, r = 0.5, owner = "w" })
		t.near((Geometry.nearest(ix, { 35, 2, 0 }, 4)), 1.5, 1e-12)
		t.eq((Geometry.nearest(ix, { 100, 0, 0 }, 4)), math.huge)
	end)

	t.test("room graph: connected layouts pass, an isolated room is reported", function()
		local rooms = { { id = "a", rect = { 0, 1, 0, 1 } }, { id = "b", rect = { 1, 2, 0, 1 } } }
		local doors = { { id = "front", a = "a", b = "outside", at = { 0.5, 0 } }, { id = "ab", a = "a", b = "b", at = { 1, 0.5 } } }
		local g = RoomGraph.build(rooms, doors, { { id = "hide", room = "b" } })
		t.eq(#RoomGraph.unreached(g, "outside"), 0)
		local g2 = RoomGraph.build(rooms, { doors[1] }, {})
		t.deepEq(RoomGraph.unreached(g2, "outside"), { "room:b" })
	end)

	t.test("server-owned door: open swings 1.35 rad about the hinge, close restores the pose", function()
		local leaf = roblox.Instance.new("Part")
		leaf.Size = roblox.Vector3.new(4, 7, 0.4)
		local closed = roblox.CFrame.new(5, 3.5, 2) * roblox.CFrame.Angles(0, 0.3, 0)
		leaf.CFrame = closed
		leaf:SetAttribute("ServerOwned", true)
		leaf:SetAttribute("Lockable", true)
		leaf:SetAttribute("Open", false)
		leaf:SetAttribute("Locked", false)
		t.truthy(Doors.setOpen(leaf, true, roblox.CFrame))
		t.eq(leaf:GetAttribute("Open"), true)
		t.eq(leaf.CanCollide, false)
		local hinge = closed * roblox.CFrame.new(-2, 0, 0)
		t.near((leaf.CFrame * roblox.CFrame.new(-2, 0, 0)).Position.X, hinge.Position.X, 1e-4) -- hinge stays put
		t.falsy(Doors.setOpen(leaf, true, roblox.CFrame))
		t.truthy(Doors.setOpen(leaf, false, roblox.CFrame))
		t.near(leaf.CFrame.Position.X, closed.Position.X, 1e-4)
		t.near(leaf.CFrame.Position.Z, closed.Position.Z, 1e-4)
		t.near(leaf.CFrame.LookVector.X, closed.LookVector.X, 1e-5)
		Doors.setLocked(leaf, true)
		t.falsy(Doors.setOpen(leaf, true, roblox.CFrame))
	end)
end
