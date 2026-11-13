--!strict
-- tools/bake/sewers/Build: the storm drains (BRIEF_ADDENDUM D8) as Instances, built only from the compiled layout
-- (Shared/World/SewerLayout over generated/Sewers) and the owner's uploaded modules (data/art/sewer_modules.json).
-- tools/bake/sewers.luau writes the result to build/Sewers.rbxm (Workspace.Sewers in the project files); the specs
-- build it in memory with the same call.
--   Sewers (Folder)
--     TerrainCarve (Folder)   the shaft columns (SewerLayout carveBoxes kind "shaft": the holes that open to the
--                             street), as invisible parts, the alley's convention: tests/lib/BakedWorld lowers the
--                             terrain inside them. The boot carve itself (lane S2) reads SewerLayout.carveBoxes(),
--                             which also holds the buried boxes round the passages and the chamber.
--     P1, P2, P3 (Model)      Pipe.build
-- Interface: build(roblox, layout, art?) -> (Folder, Report)

local Kit = require("./Kit")
local Pipe = require("./Pipe")

local Build = {}

export type Report = { parts: number, slots: number, lamps: number, pipes: { [string]: number } }

function Build.build(roblox: any, layout: any, art: any?): (any, Report)
	local kit = Kit.new(roblox)
	local root = roblox.Instance.new("Folder")
	root.Name = "Sewers"
	local carve = kit:folder(root, "TerrainCarve")
	for i, b in layout.carveBoxes() do
		if b.kind == "shaft" then
			kit:at(
				carve,
				string.format("Shaft%02d", i),
				roblox.CFrame.new((b.x0 + b.x1) / 2, (b.y0 + b.y1) / 2, (b.z0 + b.z1) / 2),
				{ b.x1 - b.x0, b.y1 - b.y0, b.z1 - b.z0 },
				{ 0, 0, 0 },
				"SmoothPlastic",
				{ visual = true, transparency = 1, shadow = false, attrs = { Pipe = b.pipe, Kind = b.kind } }
			)
		end
	end
	local report: Report = { parts = 0, slots = 0, lamps = 0, pipes = {} }
	for _, pipe in layout.pipes do
		local before = kit.count
		local r = Pipe.build(kit, root, layout, pipe, art)
		report.slots += r.slots
		report.lamps += r.lamps
		report.pipes[pipe.id] = kit.count - before
	end
	report.parts = kit.count
	return root, report
end

return Build
