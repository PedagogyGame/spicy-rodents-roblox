local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local Bake = require("../../src/worldgen/Bake")
local town = roblox.deserializeModel(fs.readFile("build/Town.rbxm"))[1]
local l = Bake.instanceLines(town)
print(l[1]); print(l[2]); print(l[3]); print(l[#l])
