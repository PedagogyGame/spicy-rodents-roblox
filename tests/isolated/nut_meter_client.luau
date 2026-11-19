--!strict
-- tests/isolated/nut_meter_client.luau: cases for tests/unit/nut_meter_engine.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- The nut meter on the squirrel's own screen (Client/UI/NutMeter; owner D16 #22), on that fake engine: hidden until
-- the server writes NutsMax; the count, the tree and its bar, the hint following the attributes; "+1" beside the
-- count and the pick-up's tick at each nut; "stored 9" (no tick) as nuts go into a tree; hidden again when the server
-- clears them (the player picked another body), and gone on stop().
-- Interface: return function(t) (the spec shape)
local NutMeter = require("@client/UI/NutMeter")
local FakeEngine = require("@tests/lib/FakeEngine")

local function find(root: any, name: string): any
	for _, d in root:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end

return function(t)
	t.test("the meter follows the server's attributes: count, tree, hint, +1 and its tick, stored, hidden", function()
		FakeEngine.with(function()
			local player = FakeEngine.new("Player", "Owner")
			FakeEngine.new("PlayerGui", "PlayerGui").Parent = player
			local h = NutMeter.start({ player = player })
			local gui = h.gui
			t.eq(gui.Parent, player:FindFirstChild("PlayerGui"))
			t.eq(gui.Enabled, false, "not a squirrel: nothing on screen")
			local count, tree, hint, flash, fill =
				find(gui, "Count"), find(gui, "Tree"), find(gui, "Hint"), find(gui, "Flash"), find(gui, "Fill")
			local tick = find(gui, "Nuts.Pick")
			t.truthy(tick and tick.SoundId ~= "", "the pick-up's tick")
			-- a squirrel: the server writes the meter
			player:SetAttribute("NutTree", "")
			player:SetAttribute("NutInside", "")
			player:SetAttribute("NutsCarried", 0)
			player:SetAttribute("NutsMax", 9)
			t.eq(gui.Enabled, true)
			t.eq(count.Text, "0/9")
			t.eq(tree.Visible, false)
			t.eq(hint.Text, "Find nuts: oaks, yards, the park")
			-- a nut picked up
			player:SetAttribute("NutsCarried", 1)
			t.eq(count.Text, "1/9")
			t.eq(flash.Visible, true)
			t.eq(flash.Text, "+1")
			t.eq(tick.played, 1)
			t.eq(hint.Text, "Run them into a hollow tree")
			FakeEngine.runDelayed()
			t.eq(flash.Visible, false, "the +1 goes after a moment")
			-- into a free hollow, nine carried: stored, no tick
			player:SetAttribute("NutsCarried", 9)
			t.eq(tick.played, 2)
			player:SetAttribute("NutInside", "H7|0.45|free")
			t.eq(tree.Visible, true)
			t.eq(tree.Text, "H7")
			t.eq(hint.Text, "Nobody's: fill to 70% to claim")
			player:SetAttribute("NutsCarried", 0)
			t.eq(flash.Text, "stored 9")
			t.eq(tick.played, 2, "no tick for storing")
			-- it claimed the tree: its own, and the bar by the server's store
			player:SetAttribute("NutTree", "H7")
			player:SetAttribute("NutStore", 0.72)
			player:SetAttribute("NutInside", "")
			t.eq(tree.Text, "H7")
			t.near(fill.Size.X.Scale, 0.72, 1e-6)
			t.eq(hint.Visible, false, "nothing to say")
			-- another body: the server clears the meter
			for _, k in { "NutsCarried", "NutsMax", "NutTree", "NutStore", "NutInside" } do
				player:SetAttribute(k, nil)
			end
			t.eq(gui.Enabled, false)
			h.stop()
			t.eq(gui.Parent, nil)
		end)
	end)
end
