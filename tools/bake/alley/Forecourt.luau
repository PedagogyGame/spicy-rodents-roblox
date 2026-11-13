--!strict
-- tools/bake/alley/Forecourt: the way in from the street (brief addendum D5), outside the main doors of the
-- eighteen-lane alley: the landing at floor level under the canopy, the ramp down from it to where the walk from
-- Bowl Lane arrives (data/expansion.json xpath_alley_steps ends at the ramp's foot; nothing bakes that walk yet),
-- planters at the landing's edges, two lamp posts, and the pylon sign with the giant pin by the road. The
-- geometry is Shared/Attractions/AlleyLayout's (LANDING, RAMP, ENTRANCE); the ground here is at or just under the
-- floor, so the terrain is cut out from over the ramp and the landing.
-- Interface: build(kit, root, data) -> nothing

local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")
local Shell = require("./Shell")

local Forecourt = {}
local L = AlleyLayout
local C = Shell.C
local STEEL = { 70, 74, 80 }

function Forecourt.build(kit: any, root: any, data: any)
	local o = kit:model(root, "Forecourt")
	local carve = root:FindFirstChild("TerrainCarve") or kit:folder(root, "TerrainCarve")
	local land, ramp, ent = L.LANDING, L.RAMP, L.ENTRANCE
	local front = L.FRONT_D - L.WALL_T -- the front wall's outer face
	local CFrame = kit.roblox.CFrame
	-- the landing (level with the floor) and the ramp down to the walk
	kit:box(o, "Landing", land.x0, land.x1, -3.5, 0, land.d0, front, C.concrete, "Concrete")
	kit:box(o, "RampBase", ramp.x0, ramp.x1, -3.5, ramp.y0, ramp.d0, land.d0, C.concrete, "Concrete")
	kit:wedge(
		o,
		"Ramp",
		(ramp.x0 + ramp.x1) / 2,
		ramp.y0 / 2,
		(ramp.d0 + land.d0) / 2,
		ramp.x1 - ramp.x0,
		-ramp.y0,
		land.d0 - ramp.d0,
		C.concrete,
		"Concrete",
		{ rot = CFrame.Angles(0, math.pi, 0) }
	)
	for _, cx in { ramp.x0 - 0.25, ramp.x1 + 0.25 } do
		kit:box(o, "RampCheek", cx - 0.25, cx + 0.25, -3.5, 0.3, ramp.d0, land.d0, C.brickDark, "Brick")
	end
	-- a mat at the doors, and a painted line where the ramp meets the walk
	kit:box(o, "DoorMat", ent.x0 + 0.6, ent.x1 - 0.6, 0, 0.03, front - 2.6, front - 0.3, { 40, 44, 48 }, "Fabric", {
		collide = false,
	})
	-- planters along the landing's edges (a stud's drop to the grass on the east side)
	for _, px in { { land.x0, ramp.x0 - 0.5 }, { ramp.x1 + 0.5, land.x1 } } do
		local x0, x1 = px[1], px[2]
		kit:box(o, "Planter", x0, x1, 0, 0.9, land.d0, front - 1.2, C.brickDark, "Brick")
		kit:box(
			o,
			"PlanterSoil",
			x0 + 0.15,
			x1 - 0.15,
			0.85,
			0.92,
			land.d0 + 0.15,
			front - 1.35,
			{ 70, 52, 36 },
			"Ground",
			{
				collide = false,
			}
		)
		for k = 0, 2 do
			kit:ball(
				o,
				"Shrub",
				(x0 + x1) / 2 + (k - 1) * 0.3,
				1.45,
				land.d0 + 1.1 + k * 1.6,
				1.5,
				{ 64, 112, 52 },
				"Grass",
				{ collide = false }
			)
		end
	end
	-- the ground is cut from over the ramp and the landing (it stands a little above the ramp's west edge)
	kit:box(
		carve,
		"Entrance",
		land.x0 - 0.5,
		land.x1 + 0.5,
		ramp.y0 - 0.15,
		7,
		ramp.d0 - 0.5,
		front + 0.1,
		{ 255, 0, 0 },
		"SmoothPlastic",
		{ collide = false, query = false, transparency = 1, shadow = false }
	)
	-- a lamp post each side of the ramp's foot
	for _, lx in { ramp.x0 - 2.2, ramp.x1 + 2.2 } do
		local ld = ramp.d0 + 1.5
		kit:cyl(o, "LampPost", lx, 3.6, ld, 9.2, 0.35, "Y", STEEL, "Metal")
		kit:cyl(o, "LampFoot", lx, -0.6, ld, 1.0, 0.9, "Y", C.concrete, "Concrete")
		local globe = kit:ball(o, "LampGlobe", lx, 8.6, ld, 1.3, { 255, 236, 200 }, "Neon", { collide = false })
		kit:light(globe, "PointLight", { Range = 26, Brightness = 1.3, Color = { 255, 226, 186 }, Shadows = false })
	end
	-- the pylon sign by the road with a giant pin on top
	local pyX, pyD = 4, front - 11
	kit:box(o, "PylonFooting", pyX - 1.5, pyX + 1.5, -3.5, 0.4, pyD - 1.5, pyD + 1.5, C.concrete, "Concrete")
	kit:cyl(o, "PylonPole", pyX, 9, pyD, 18.8, 0.9, "Y", STEEL, "Metal")
	local board =
		kit:box(o, "PylonBoard", pyX - 7, pyX + 7, 12, 16, pyD - 0.4, pyD + 0.4, { 30, 36, 78 }, "SmoothPlastic")
	for _, face in { "Front", "Back" } do
		local pg = kit:gui(board, face, 12)
		kit:label(pg, { Text = data.name, TextColor = { 255, 210, 80 }, Font = "FredokaOne", Size = { 1, 0.58 } })
		kit:label(pg, {
			Text = `{L.LANES} LANES - POOL - PINBALL - AIR HOCKEY`,
			TextColor = { 120, 230, 230 },
			Font = "GothamBold",
			Size = { 1, 0.3 },
			Pos = { 0, 0.64 },
		})
	end
	for _, ty in { 11.8, 16.0 } do
		kit:box(o, "PylonTrim", pyX - 7.2, pyX + 7.2, ty, ty + 0.2, pyD - 0.5, pyD + 0.5, C.orange, "Neon", {
			collide = false,
		})
	end
	-- the giant pin (x 5 of a lane pin)
	local s = 5
	local base = 16.2
	local profile =
		{ { 0, 0.12, 0.30 }, { 0.10, 0.30, 0.42 }, { 0.28, 0.62, 0.46 }, { 0.60, 0.82, 0.36 }, { 0.80, 1.15, 0.20 } }
	for i, pr in profile do
		kit:cyl(
			o,
			`GiantPin{i}`,
			pyX,
			base + (pr[1] + pr[2]) / 2 * s,
			pyD,
			(pr[2] - pr[1]) * s,
			pr[3] * s,
			"Y",
			{ 246, 246, 240 },
			"SmoothPlastic"
		)
	end
	kit:ball(o, "GiantPinHead", pyX, base + 1.28 * s, pyD, 0.27 * s, { 246, 246, 240 }, "SmoothPlastic")
	for k = 0, 1 do
		kit:cyl(
			o,
			"GiantPinStripe",
			pyX,
			base + (0.96 + k * 0.08) * s,
			pyD,
			0.04 * s,
			0.205 * s,
			"Y",
			{ 200, 30, 40 },
			"SmoothPlastic"
		)
	end
end

return Forecourt
