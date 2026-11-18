--!strict
-- The whack-a-mole cabinet as tools/bake/games/WhackAMole bakes it (the same code tools/bake/attractions.luau
-- runs), built in memory on a turned site and measured against Shared/Minigames/WhackAMole/Layout (the owner's
-- model in studs):
--   * every part the client moves or writes on is there under the name it looks for (Layout.NAMES, the names
--     tests/isolated/whack_a_mole_client.luau furnishes its fake cabinet with): five mole Models, the Mallet with
--     its Pivot, the SCORE, TIME and status windows with their Display / Value;
--   * where they stand is where the game plays: each mole over its hole, each hole's mouth at its Layout centre,
--     the mallet's pivot at its rest in the bracket, the windows on the sign;
--   * the look keeps to the rating: FREE PLAY where his coin door was and no coin words anywhere; no mole is green;
--   * people bump into the cabinet, not into its moles or mallet; the whole of it stands on its own floor
--     (Layout.STANDING) and inside the part budget (the parts are printed).
local roblox = require("@lune/roblox")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Games = require("@shared/Minigames/Games")
local Layout = require("@shared/Minigames/WhackAMole/Layout")
local Bake = require("../../tools/bake/games/WhackAMole")
local Kit = require("../../tools/bake/alley/Kit")

local PLACE: AlleyLayout.Place = { x = 40, z = -90, floorY = 12, yaw = 0.6 }

local function world(u: number, v: number, w: number): any
	local X, Y, D = Layout.toSite(u, v, w)
	return roblox.Vector3.new(AlleyLayout.toWorld(PLACE, X, Y, D))
end

return function(t)
	local kit = Kit.new(roblox, PLACE)
	local room = roblox.Instance.new("Model")
	room.Name = "GamesRoom"
	local station: any = nil
	for _, st in Games.stations({ bowling_alley = PLACE }) do
		if st.game == "whack_a_mole" then
			station = st
		end
	end
	assert(station, "a whack-a-mole station")
	Bake.build(kit, room, station, nil)
	local N = Layout.NAMES
	local model = room:FindFirstChild(N.model)

	local function parts(of: any): { any }
		local out = {}
		for _, d in of:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	t.test("lean: inside the part budget (the parts are printed)", function()
		t.truthy(model ~= nil)
		local all = #parts(model)
		local shell = #parts(model:FindFirstChild("Shell"))
		local moles = 0
		for i = 1, 5 do
			moles += #parts(model:FindFirstChild(`{N.mole}{i}`))
		end
		local mallet = #parts(model:FindFirstChild(N.mallet))
		print(
			`whack_bake: {all} parts ({shell} shell, {moles} moles, {mallet} mallet, {all - shell - moles - mallet} windows); budget {Bake.BUDGET}`
		)
		t.truthy(all <= Bake.BUDGET, `{all} parts`)
		t.eq(kit.count, all, "every part the kit made is in the cabinet")
	end)

	t.test("the moles, the mallet and the windows: named as the client looks for them, where the game plays", function()
		for i = 1, 5 do
			local mole = model:FindFirstChild(`{N.mole}{i}`)
			t.truthy(mole and mole:IsA("Model"), `Mole{i}`)
			t.truthy(mole.PrimaryPart ~= nil, `Mole{i} has a pivot`)
			local hu, _, hw = Layout.hole(i)
			local want = world(hu, Layout.MOLE.bodyV, hw)
			t.truthy((mole.PrimaryPart.CFrame.Position - want).Magnitude < 1e-3, `Mole{i} over hole {i}`)
			-- hidden at rest: the head's top is under the deck's face
			local head = mole:FindFirstChild("Head")
			local top = head.CFrame.Position.Y + head.Size.Y / 2
			t.truthy(top < PLACE.floorY + Layout.DECK.top, `Mole{i} below the deck at rest`)
			for _, p in parts(mole) do
				t.falsy(p.CanCollide, "a mole is not bumped into")
				t.truthy(p.Anchored)
			end
			local mouth = model:FindFirstChild("Shell"):FindFirstChild(`Hole{i}`)
			local at = world(hu, mouth.CFrame.Position.Y - PLACE.floorY, hw)
			t.truthy((mouth.CFrame.Position - at).Magnitude < 1e-3, `hole {i}'s mouth at its centre`)
			t.near(mouth.Size.Y, 2 * Layout.DECK.holeR, 1e-4)
		end
		local mallet = model:FindFirstChild(N.mallet)
		t.truthy(mallet and mallet:IsA("Model") and mallet.PrimaryPart and mallet.PrimaryPart.Name == "Pivot")
		local r = Layout.MALLET.rest
		t.truthy((mallet.PrimaryPart.CFrame.Position - world(r[1], r[2], r[3])).Magnitude < 1e-3, "the pivot at rest")
		local head = mallet:FindFirstChild("MalletHead")
		local along = mallet.PrimaryPart.CFrame:PointToObjectSpace(head.CFrame.Position)
		t.near(along.Y, Layout.MALLET.headAt, 1e-3, "the head up the handle from the pivot")
		t.near(along.X, 0, 1e-3)
		for _, p in parts(mallet) do
			t.falsy(p.CanCollide)
		end
		for _, name in { N.score, N.time, N.status } do
			local part = model:FindFirstChild(name)
			local gui = part and part:FindFirstChild(N.display)
			local value = gui and gui:FindFirstChild(N.value)
			t.truthy(value and value:IsA("TextLabel"), `{name}.{N.display}.{N.value}`)
		end
		local W = Layout.WINDOWS.score
		local glass = model:FindFirstChild(N.score)
		t.truthy((glass.CFrame.Position - world(W.u, W.v, (W.glassFront + Layout.m(0.361)) / 2)).Magnitude < 1e-3)
	end)

	t.test("the rating: FREE PLAY where the coin door was, no coin words, no green mole", function()
		local words = {}
		for _, d in model:GetDescendants() do
			if d:IsA("TextLabel") then
				table.insert(words, string.upper(d.Text))
			end
		end
		local all = table.concat(words, " | ")
		t.truthy(string.find(all, "FREE", 1, true) and string.find(all, "PLAY", 1, true), all)
		t.falsy(string.find(all, "COIN", 1, true), all)
		t.falsy(string.find(all, "INSERT", 1, true), all)
		t.falsy(string.find(all, "ONE GOOD ROUND", 1, true), all)
		for i = 1, 5 do
			for _, p in parts(model:FindFirstChild(`{N.mole}{i}`)) do
				local c = p.Color
				t.falsy(c.G > c.R + 0.02 and c.G > c.B, `{p.Name} of Mole{i} is green`)
			end
		end
	end)

	t.test("solid where people walk into it, and all of it on its own floor", function()
		local shell = model:FindFirstChild("Shell")
		for _, name in { "Plinth", "Front", "Rear", "SideLeft", "SideRight", "Deck", "SignCase" } do
			local p = shell:FindFirstChild(name)
			t.truthy(p and p.CanCollide, name)
		end
		local a = Layout.STANDING
		for _, p in parts(model) do
			local X, Y, D = AlleyLayout.toLocal(PLACE, p.CFrame.Position.X, p.CFrame.Position.Y, p.CFrame.Position.Z)
			t.truthy(X >= a.x0 and X <= a.x1 and D >= a.d0 and D <= a.d1, `{p.Name} at X {X} D {D}`)
			t.truthy(Y >= 0 and Y <= Layout.SIGN.v1 + 0.01, `{p.Name} at height {Y}`)
		end
	end)
end
