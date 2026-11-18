--!strict
-- The owner's sewer modules in the game (Client/World/SewerArt, Server/World/SewerService.loadArt): the window of
-- slots drawn round the body, the placement check, and the server's load into ReplicatedStorage.SewerArt. The cases on
-- a fake engine are in tests/isolated/sewer_art.luau (each reported here as its own test); the budget of every window
-- of every pipe is held in tests/unit/sewers_bake.spec.luau. Nothing here can show the modules arrive upright in the
-- engine: tests/engine/Sewers.luau checks that when Luau Execution returns.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local SewerArt = require("@client/World/SewerArt")
local Isolated = require("@tests/lib/Isolated")
local FakeEngine = require("@tests/lib/FakeEngine")
local SewerService = require("@server/World/SewerService")

return function(t)
	local art = serde.decode("json", fs.readFile("data/art/sewer_modules.json"))

	t.test("the window: the slots of the body's drain within the radius, nearest first, at most the cap", function()
		local slots: { SewerArt.Slot } = {}
		for i = 1, 20 do
			table.insert(slots, {
				module = "brick",
				space = if i <= 15 then "a" else "b",
				pivot = roblox.CFrame.new(i * 12, 0, 0) :: any,
				tris = 5000,
				meshes = 30,
			})
		end
		local w = SewerArt.window(slots, "a", roblox.Vector3.new(60, 0, 0) :: any, 48, 10)
		t.eq(w[1], 5, "the nearest first")
		for _, i in w do
			t.eq(slots[i].space, "a")
			t.truthy(math.abs(i * 12 - 60) <= 48)
		end
		t.eq(#w, 9)
		t.eq(#SewerArt.window(slots, "a", roblox.Vector3.new(60, 0, 0) :: any, 48, 3), 3)
		t.eq(#SewerArt.window(slots, "b", roblox.Vector3.new(60, 0, 0) :: any, 48, 10), 0, "another drain's: none")
		local tris, meshes = SewerArt.cost(slots, w)
		t.eq(tris, 45000)
		t.eq(meshes, 270)
	end)

	t.test("the server loads each module the bake names once, visual only; a failure leaves it out", function()
		FakeEngine.with(function()
			local root = FakeEngine.new("Folder", "Sewers")
			for i, name in { "brick", "brick", "junction", "dry" } do
				local slot = FakeEngine.new("Model", `Slot{i}`)
				slot:SetAttribute("ArtModule", name)
				slot:SetAttribute("ArtAsset", tostring(art.modules[name].assetId))
				slot.Parent = root
			end
			local calls: { [string]: number } = {}
			local insert = {
				LoadAsset = function(_self: any, id: number): any
					local key = tostring(id)
					calls[key] = (calls[key] or 0) + 1
					if key == tostring(art.modules.dry.assetId) then
						error("HTTP 403 (Forbidden)")
					end
					local container = FakeEngine.new("Model", "Container")
					local model = FakeEngine.model("SR sewer module", roblox.CFrame.new(0, 0, 0), container)
					local part = FakeEngine.new("MeshPart", "Wall")
					part.CanCollide = true
					part.Parent = model
					return container
				end,
			}
			local into = FakeEngine.new("Folder", "SewerArt")
			local loaded, failed = SewerService.loadArt(root, into, insert)
			t.deepEq(loaded, { "brick", "junction" })
			t.truthy(failed.dry ~= nil and string.find(failed.dry, "403", 1, true) ~= nil, tostring(failed.dry))
			t.eq(calls[tostring(art.modules.brick.assetId)], 1, "brick loaded once for two slots")
			local brick = into:FindFirstChild("brick")
			t.truthy(brick ~= nil and brick:IsA("Model"))
			local wall = brick:FindFirstChild("Wall")
			t.eq(wall.CanCollide, false)
			t.eq(wall.CanQuery, false)
			t.eq(wall.CanTouch, false)
			t.eq(wall.Anchored, true)
			-- a second call takes what is already there
			SewerService.loadArt(root, into, insert)
			t.eq(calls[tostring(art.modules.brick.assetId)], 1)
		end)
	end)

	Isolated.register(t, "tests/isolated/sewer_art")
end
