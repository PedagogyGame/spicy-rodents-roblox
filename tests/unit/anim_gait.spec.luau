--!strict
-- Procedural gait (Client/Animation/Gait): squirrels bound (front pair together, back pair opposite),
-- fox and deer trot (diagonal pairs together); the swing grows with speed and is still at rest; the
-- phase advances one cycle per stride; the tail sways at rest and while running; climbing speed
-- (3D) animates the same as ground speed. Also Client/Render/TownView's nearest-lamp selection.
local Gait = require("@client/Animation/Gait")
local TownView = require("@client/Render/TownView")

return function(t)
	t.test("bound vs trot: which legs move together", function()
		local sq = Gait.params("squirrel", 0.9)
		local pose = Gait.pose(math.pi / 2, 16, 0, sq, 3)
		t.truthy(sq.bound)
		t.near(pose.legs.FrontL.upper, pose.legs.FrontR.upper, 0.1)
		t.truthy(pose.legs.FrontL.upper * pose.legs.BackL.upper < 0, "back pair opposite the front")
		local fox = Gait.params("fox", 2.05)
		local fp = Gait.pose(math.pi / 2, 18, 0, fox, 2)
		t.near(fp.legs.FrontL.upper, fp.legs.BackR.upper, 1e-9)
		t.near(fp.legs.FrontL.upper, -fp.legs.FrontR.upper, 1e-9)
	end)

	t.test("swing grows with speed; still legs at rest but the tail sways", function()
		local p = Gait.params("deer", 4.4)
		local rest = Gait.pose(1, 0, 3.7, p, 1)
		for _, leg in rest.legs do
			t.eq(leg.upper, 0)
		end
		t.truthy(math.abs(rest.tail[1].yaw) > 0, "idle tail sway")
		local walk = Gait.pose(math.pi / 2, 4, 0, p, 1)
		local run = Gait.pose(math.pi / 2, 22, 0, p, 1)
		t.truthy(math.abs(run.legs.FrontL.upper) > math.abs(walk.legs.FrontL.upper), "faster swings wider")
		t.truthy(math.abs(run.legs.FrontL.upper) <= p.swing + 1e-9, "bounded")
	end)

	t.test("phase: one cycle per stride, wraps", function()
		local p = Gait.params("squirrel", 0.9)
		local ph = 0
		local steps = 100
		for _ = 1, steps do
			ph = Gait.advance(ph, p.stride, 1 / steps, p) -- one stride in one second
		end
		t.truthy(ph < 1e-6 or math.abs(ph - 2 * math.pi) < 1e-6, `phase {ph}`)
		t.eq(Gait.advance(1, 0, 1, p), 1)
		t.truthy(Gait.PROCEDURAL.squirrel and Gait.PROCEDURAL.deer and Gait.PROCEDURAL.fox)
		t.eq(Gait.PROCEDURAL.human, nil)
	end)

	t.test("TownView.nearest: nearest first, within the radius, at most max", function()
		local pts = { { 0, 0 }, { 10, 0 }, { 5, 0 }, { 500, 0 } }
		local pick = TownView.nearest(pts, 6, 0, 2, 100)
		t.eq(#pick, 2)
		t.eq(pick[1], 3)
		t.eq(pick[2], 2)
		t.eq(#TownView.nearest(pts, 0, 0, 10, 100), 3)
	end)
end
