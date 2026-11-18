--!strict
-- The whack-a-mole cabinet's meshes from the owner's Blender file (tools/blender/whack_a_mole) and their loader
-- (Server/Assets/WhackArt):
--   * what publish.py wrote agrees with itself: Shared/Minigames/WhackAMole/Art (what the loader reads) and
--     data/art/whack_a_mole.json (the record) name the same pieces at the same places; about 12,000 triangles,
--     every mole and the mallet in pieces of their own, every material painted from Layout.COLORS, no mole green;
--   * with no asset id (as now) the loader does nothing at all;
--   * given a Model, it puts every piece at its place over a cabinet the real bake built, a mole's pieces in its
--     Mole model and the mallet's in the Mallet (their pivots untouched), hides the baked look and keeps the
--     bake's collision and lettering; a second time it does nothing.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Art = require("@shared/Minigames/WhackAMole/Art")
local Games = require("@shared/Minigames/Games")
local Layout = require("@shared/Minigames/WhackAMole/Layout")
local WhackArt = require("@server/Assets/WhackArt")
local Bake = require("../../tools/bake/games/WhackAMole")
local Kit = require("../../tools/bake/alley/Kit")
local Test = require("../lib/Test")

local PLACE: AlleyLayout.Place = { x = 40, z = -90, floorY = 12, yaw = 0.6 }

local function cabinet(): any
	local kit = Kit.new(roblox, PLACE)
	local room = roblox.Instance.new("Model")
	for _, st in Games.stations({ bowling_alley = PLACE }) do
		if st.game == "whack_a_mole" then
			Bake.build(kit, room, st, nil)
		end
	end
	return room:FindFirstChild(Layout.NAMES.model)
end

-- the uploaded Model as LoadAsset hands it back: a Model holding a Model of MeshParts, each at the origin
local function asset(extra: string?): any
	local outer = roblox.Instance.new("Model")
	local inner = roblox.Instance.new("Model")
	inner.Parent = outer
	local names = {}
	for name in Art.pieces do
		table.insert(names, name)
	end
	if extra then
		table.insert(names, extra)
	end
	for _, name in names do
		local p = roblox.Instance.new("MeshPart")
		p.Name = name
		p.Parent = inner
	end
	return outer
end

return function(t: Test.T)
	t.test("what publish.py wrote: the loader's data and the record agree; about 12,000 triangles", function()
		local doc = serde.decode("json", fs.readFile("data/art/whack_a_mole.json"))
		local recorded: { [string]: any } = {}
		for _, p in doc.pieces do
			recorded[p.name] = p
		end
		local n, total = 0, 0
		for name, p in Art.pieces do
			n += 1
			total += p.tris
			local r = recorded[name]
			t.truthy(r ~= nil, `{name} is in the record`)
			for i = 1, 3 do
				t.near(p.centre[i], r.centre[i], 1e-3, `{name} centre {i}`)
			end
			t.eq(p.group, r.group)
			t.eq(p.material, r.material)
		end
		t.eq(n, #doc.pieces)
		t.eq(total, Art.total)
		t.eq(total, doc.total)
		t.truthy(total > 9000 and total < 14000, `{total} triangles`)
		t.eq(doc.sourceTris + doc.leftOut.lettering, 232092, "his GLB's 232,092 triangles are all accounted for")
		local id = doc.assets.whack.assetId
		t.eq(Art.assetId, if id == nil then "" else tostring(id), "the same asset id (none yet)")
	end)

	t.test("each mole and the mallet are pieces of their own; every piece painted; no mole green", function()
		local moles: { [number]: number } = {}
		local mallet = 0
		for name, p in Art.pieces do
			if p.group == "mole" then
				local i = p.mole :: number
				moles[i] = (moles[i] or 0) + 1
				t.truthy(string.sub(name, 1, 5) == `Mole{i}`, name)
				local c = WhackArt.colour(p)
				t.falsy(c[2] > c[1] + 5 and c[2] > c[3], `{name} is green`)
			elseif p.group == "mallet" then
				mallet += 1
			else
				t.eq(p.group, "shell")
			end
			t.truthy(WhackArt.colour(p) ~= nil)
			t.truthy(roblox.Enum.Material[p.robloxMaterial] ~= nil, p.robloxMaterial)
		end
		for i = 1, 5 do
			t.truthy((moles[i] or 0) >= 4, `mole {i} in {moles[i] or 0} pieces`)
		end
		t.truthy(mallet >= 3)
		t.eq(WhackArt.colour({ material = "fur", mole = 3, group = "mole" }), Layout.COLORS.charcoal)
	end)

	t.test("no asset id: the loader does nothing", function()
		local model = cabinet()
		local spawned = 0
		t.falsy(WhackArt.start(model, PLACE, {
			data = { assetId = "", pieces = Art.pieces },
			spawn = function(_f: () -> ())
				spawned += 1
			end,
		}))
		t.eq(spawned, 0)
		local report = WhackArt.install(model, PLACE, { assetId = "", pieces = Art.pieces }, { env = roblox :: any })
		t.falsy(report.loaded)
		t.eq(report.why, "no asset id")
		local shell = model:FindFirstChild("Shell")
		t.eq(shell:FindFirstChild("Deck").Transparency, 0, "the baked cabinet as it was")
	end)

	t.test(
		"a Model: every piece in its place and model, the baked look hidden, collision and lettering kept",
		function()
			local model = cabinet()
			local N = Layout.NAMES
			local pivots = {}
			for i = 1, 5 do
				pivots[i] = model:FindFirstChild(`{N.mole}{i}`).PrimaryPart
			end
			local data = { assetId = "123", pieces = Art.pieces }
			local report = WhackArt.install(model, PLACE, data, {
				env = roblox :: any,
				load = function(id: number): any
					t.eq(id, 123)
					return asset("Stray")
				end,
			})
			t.truthy(report.loaded, report.why)
			local n = 0
			for _ in Art.pieces do
				n += 1
			end
			t.eq(report.pieces, n)
			t.eq(report.unknown, 1, "a piece the data does not name is left alone")
			for name, p in Art.pieces do
				local holder = if p.group == "mole"
					then model:FindFirstChild(`{N.mole}{p.mole}`)
					elseif p.group == "mallet" then model:FindFirstChild(N.mallet)
					else model:FindFirstChild("Shell")
				local part = holder:FindFirstChild(name)
				t.truthy(part ~= nil and part:IsA("MeshPart"), `{name} in its model`)
				local X, Y, D = Layout.toSite(p.centre[1], p.centre[2], p.centre[3])
				local want = roblox.Vector3.new(AlleyLayout.toWorld(PLACE, X, Y, D))
				t.truthy((part.CFrame.Position - want).Magnitude < 1e-3, `{name} at its centre`)
				t.falsy(part.CanCollide)
				local c = WhackArt.colour(p)
				t.near(part.Color.R * 255, c[1], 0.6, `{name} painted`)
			end
			for i = 1, 5 do
				t.eq(model:FindFirstChild(`{N.mole}{i}`).PrimaryPart, pivots[i], "the clients' pivot is the baked one")
			end
			local shell = model:FindFirstChild("Shell")
			local deck = shell:FindFirstChild("Deck")
			t.eq(deck.Transparency, 1, "the baked deck hidden")
			t.truthy(deck.CanCollide, "its collision kept")
			t.truthy(shell:FindFirstChild("Plate"):FindFirstChildWhichIsA("SurfaceGui") ~= nil, "FREE PLAY kept")
			local value = model:FindFirstChild(N.score):FindFirstChild(N.display):FindFirstChild(N.value)
			t.truthy(value ~= nil, "the SCORE window's text kept")
			t.eq(model:GetAttribute("Art"), "123")
			local again = WhackArt.install(model, PLACE, data, { env = roblox :: any, load = asset })
			t.falsy(again.loaded)
			t.eq(again.why, "already installed")
		end
	)
end
