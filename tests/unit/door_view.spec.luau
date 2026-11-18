--!strict
-- Shared/World/DoorMotion and Client/Render/DoorView: the doors of the enterable buildings open as a body
-- comes near and close behind it, on each client. The motion is pure (a swing about the hinge edge away
-- from the walker, or a slide along the wall), a door opens inside OPEN and closes past CLOSE, and on
-- the baked lots every auto leaf is found with the knob and panels that ride on it, opens fully for a
-- body at its threshold, ignores a squirrel on the roof and a locked leaf, and comes back exactly to its
-- baked pose.
local roblox = require("@lune/roblox")
local Bake = require("@worldgen/Bake")
local Factory = require("@worldgen/Factory")
local Greybox = require("@worldgen/Builders/Greybox")
local DoorMotion = require("@shared/World/DoorMotion")
local DoorView = require("@client/Render/DoorView")

return function(t)
	local C = roblox.CFrame
	local V3 = roblox.Vector3

	t.test(
		"pose: a swing turns 1.35 rad about the hinge edge, a slide runs along the leaf; alpha 0 is the baked pose",
		function()
			local closed = C.new(5, 4, 2) * C.Angles(0, 0.3, 0)
			local size = V3.new(6, 8, 0.3)
			t.eq(DoorMotion.pose(closed, size, "swing", 1, 0, 0, C), closed)
			t.eq(DoorMotion.pose(closed, size, "slide", 1, 6, 0, C), closed)
			for _, sign in { 1, -1 } do
				for _, alpha in { 0.3, 1 } do
					local open = DoorMotion.pose(closed, size, "swing", sign, 0, alpha, C)
					-- the hinge edge stays where it was
					local h0, h1 = (closed * C.new(-3, 0, 0)).Position, (open * C.new(-3, 0, 0)).Position
					t.truthy((h0 - h1).Magnitude < 1e-4, "the hinge moved")
					-- the free edge has turned by alpha * SWING, toward the leaf's local -Z for sign +1
					local free = closed:PointToObjectSpace((open * C.new(3, 0, 0)).Position)
					local angle = math.atan2(-free.Z, free.X + 3)
					t.near(angle, sign * DoorMotion.SWING * alpha, 1e-4)
					t.near(free.Y, 0, 1e-5)
				end
			end
			local slid = DoorMotion.pose(closed, size, "slide", -1, 6, 0.5, C)
			local moved = closed:PointToObjectSpace(slid.Position)
			t.near(moved.X, -3, 1e-5)
			t.near(moved.Z, 0, 1e-5)
			t.near(DoorMotion.SWING, 1.35, 1e-9)
		end
	)

	t.test("when: open inside OPEN of the doorway, shut past CLOSE, measured from the whole doorway", function()
		t.truthy(DoorMotion.CLOSE > DoorMotion.OPEN + 1, "a gap, so a body at the edge does not flap the door")
		t.eq(DoorMotion.wants(false, DoorMotion.OPEN - 0.1), true)
		t.eq(DoorMotion.wants(false, DoorMotion.OPEN + 0.1), false)
		t.eq(DoorMotion.wants(true, DoorMotion.OPEN + 0.1), true, "it stays open until the body is well away")
		t.eq(DoorMotion.wants(true, DoorMotion.CLOSE + 0.1), false)
		t.eq(DoorMotion.wants(false, math.huge), false)
		-- a doorway along x, 22 st wide: a body in front of its far end is as near as one at its middle
		t.near(DoorMotion.reach(0, 5, 1, 0, 11), 5, 1e-9)
		t.near(DoorMotion.reach(10, 5, 1, 0, 11), 5, 1e-9)
		t.near(DoorMotion.reach(14, 4, 1, 0, 11), 5, 1e-9, "past the jamb: from the jamb")
		-- away from the walker: the body on the leaf's +Z side sends the free edge to -Z
		t.eq(DoorMotion.side(0, 3, 0, 1), 1)
		t.eq(DoorMotion.side(0, -3, 0, 1), -1)
		-- opening takes OPEN_SECS, closing CLOSE_SECS, at an even rate, never past the end
		local a = 0
		for _ = 1, 6 do
			a = DoorMotion.ease(a, 1, DoorMotion.OPEN_SECS / 5)
		end
		t.eq(a, 1)
		t.near(DoorMotion.ease(1, 0, DoorMotion.CLOSE_SECS / 2), 0.5, 1e-9)
		t.eq(DoorMotion.ease(0.01, 0, 1), 0)
	end)

	t.test("the baked buildings: every auto leaf opens for a body at its threshold and comes back exactly", function()
		local factory = Factory.new({
			Instance = roblox.Instance,
			Vector3 = roblox.Vector3,
			CFrame = roblox.CFrame,
			Color3 = roblox.Color3,
			Enum = roblox.Enum,
			UDim2 = roblox.UDim2,
			ColorSequence = roblox.ColorSequence,
		})
		local seen, leaves, riders = 0, 0, 0
		for _, p in Bake.plans(Bake.data()) do
			if p.id == "core_house_1_bungalow" or p.id == "hospital_main" or p.id == "west_police_station" then
				seen += 1
				local model = Greybox.build(p, factory)
				local entries = DoorView.gather(model)
				t.eq(#entries, model:GetAttribute("AutoDoors"), p.id)
				for _, e in entries do
					leaves += 1
					local tag = `{p.id}.{e.leaf.Name}`
					t.eq(e.leaf.CanCollide, false, tag)
					t.truthy(#e.followers >= 1, `{tag}: a knob, a pull or panels ride on it`)
					local baked: { any } = {}
					for i, f in e.followers do
						baked[i] = f.part.CFrame
						t.eq(f.part.CanCollide, false, f.part.Name)
					end
					riders += #e.followers
					local one = { e }
					-- nobody about: nothing moves
					t.eq(DoorView.step(one, {}, 0.1, C), 0)
					-- a squirrel on the roof straight above the door: not on the door's level
					t.eq(DoorView.step(one, { { x = e.x, y = e.sill + 16, z = e.z } }, 0.1, C), 0)
					t.eq(e.open, false, `{tag} opened for a body on the roof`)
					-- a body 5 st in front (the leaf's +Z side), a person's root 3 st above the sill
					local body = { x = e.x + e.nx * 5, y = e.sill + 3, z = e.z + e.nz * 5 }
					t.eq(DoorView.step(one, { body }, 0.05, C), 1)
					t.eq(e.open, true, tag)
					t.truthy(e.alpha > 0 and e.alpha < 1, `{tag} jumped open`)
					for _ = 1, 12 do
						DoorView.step(one, nil, 0.05, C) -- between looks it goes on opening
					end
					t.eq(e.alpha, 1, tag)
					local open = e.leaf.CFrame
					if e.motion == "slide" then
						local moved = e.closed:PointToObjectSpace(open.Position)
						t.near(moved.X, e.slideSign * e.run, 1e-3, `{tag} slid`)
						t.near(moved.Z, 0, 1e-3, `{tag} left the wall`)
						t.truthy(e.run >= e.half * 2 - 1e-6, `{tag}: the doorway is clear`)
					else
						-- swung away from the body: the free edge is on the far side from it
						local free = (open * C.new(e.half, 0, 0)).Position
						local side = (free.X - e.x) * e.nx + (free.Z - e.z) * e.nz
						t.truthy(side < -1, `{tag} swung toward the walker`)
						local hinge = (open * C.new(-e.half, 0, 0)).Position
						t.truthy((hinge - (e.closed * C.new(-e.half, 0, 0)).Position).Magnitude < 1e-3, tag)
					end
					for i, f in e.followers do
						-- rigid: the same place on the leaf
						local now = open:ToObjectSpace(f.part.CFrame)
						t.truthy((now.Position - f.rel.Position).Magnitude < 1e-3, `{f.part.Name} slid on its leaf`)
						t.truthy((f.part.CFrame.Position - baked[i].Position).Magnitude > 0.05, `{f.part.Name} stayed`)
					end
					-- the body walks through and stands 8.5 st beyond: still open (inside CLOSE)
					body.x, body.z = e.x - e.nx * 8.5, e.z - e.nz * 8.5
					DoorView.step(one, { body }, 0.05, C)
					t.eq(e.open, true, `{tag} shut on the walker's heels`)
					t.eq(e.alpha, 1)
					-- and goes: it closes, all the way back to the baked pose
					body.x, body.z = e.x - e.nx * 30, e.z - e.nz * 30
					DoorView.step(one, { body }, 0.05, C)
					t.eq(e.open, false, tag)
					for _ = 1, 20 do
						DoorView.step(one, nil, 0.05, C)
					end
					t.eq(e.alpha, 0)
					t.truthy((e.leaf.CFrame.Position - e.closed.Position).Magnitude < 1e-4, `{tag} did not come back`)
					t.near(e.leaf.CFrame.LookVector.X, e.closed.LookVector.X, 1e-4)
					t.near(e.leaf.CFrame.LookVector.Z, e.closed.LookVector.Z, 1e-4)
					for i, f in e.followers do
						t.truthy((f.part.CFrame.Position - baked[i].Position).Magnitude < 1e-3, `{f.part.Name} is off`)
					end
					-- from the other side a swing leaf goes the other way
					if e.motion == "swing" then
						DoorView.step(one, { { x = e.x - e.nx * 4, y = e.sill + 1, z = e.z - e.nz * 4 } }, 1, C)
						local free = (e.leaf.CFrame * C.new(e.half, 0, 0)).Position
						t.truthy((free.X - e.x) * e.nx + (free.Z - e.z) * e.nz > 1, `{tag} swung toward the walker`)
						DoorView.step(one, {}, 2, C)
						t.eq(e.alpha, 0)
					end
					-- a locked leaf stays shut
					e.leaf:SetAttribute("Locked", true)
					t.eq(DoorView.step(one, { { x = e.x, y = e.sill + 3, z = e.z } }, 0.1, C), 0)
					t.eq(e.open, false, `{tag} opened although it is locked`)
					e.leaf:SetAttribute("Locked", false)
				end
				-- a plain lot has none
				t.eq(#DoorView.gather(roblox.Instance.new("Model")), 0)
			end
		end
		t.eq(seen, 3)
		print(`      {leaves} leaves opened and closed, {riders} knobs, pulls and panels rode on them`)
		t.eq(leaves, 6 + 10 + 4)
	end)
end
