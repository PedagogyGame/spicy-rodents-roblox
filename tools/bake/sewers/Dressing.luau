--!strict
-- tools/bake/sewers/Dressing: the small things that make the drains read (mild: water, moss, leaves, a lost toy or
-- two; no filth). Every piece is visual only (nothing collides with it or queries it) and stays off the squirrel's
-- lane: on the far walkway, in the channel, on the walls above the body, or on the end walls.
--   sign(kit, parent, anchor)                       the drain's stencil on the end wall at each shaft foot
--   chalk(kit, parent, frame, z, section, lane, text, forward)   a chalk arrow on the far wall; the arrow points
--        the way `forward` (+1: the run's +z) as a reader in the lane sees it
--   moss / leaves / boat / duck / ball(...)         at a frame point
--   stand(kit, parent, anchor)                      the fashion stand (BUILD_PLAN W4 #9 builds the shop on it; here a
--        wooden hat stand with a fedora, the v5.4 stand's look), at the chamber's anchor, facing the crossing
-- Interface: each returns the Model or Part it made.

local Kit = require("./Kit")

local Dressing = {}

local VIS: Kit.Opts = { visual = true }
local FLAT: Kit.Opts = { visual = true, shadow = false }

function Dressing.sign(kit: Kit.Kit, parent: any, a: any): any
	local r = kit.roblox
	local V, CF = r.Vector3, r.CFrame
	local p = V.new(a.x, a.y, a.z)
	local cf = CF.lookAt(p, p + V.new(a.facing.x, 0, a.facing.z))
	local plate = kit:at(parent, "Sign", cf * CF.new(0, 0, 0.03), { 2.9, 0.62, 0.05 }, { 58, 98, 96 }, "Metal", VIS)
	kit:label(plate, "Front", a.text, {
		Font = "Michroma",
		TextColor3 = r.Color3.fromRGB(232, 226, 204),
	})
	return plate
end

function Dressing.chalk(
	kit: Kit.Kit,
	parent: any,
	frame: any,
	z: number,
	section: any,
	lane: number,
	text: string,
	forward: number
): any
	local r = kit.roblox
	local V, CF = r.Vector3, r.CFrame
	local side = if lane == 0 then -1 else -lane
	local x = side * (section.innerHalf - 0.012)
	local p = frame * V.new(x, 1.05, z)
	local inward = frame:VectorToWorldSpace(V.new(-side, 0, 0))
	local cf = CF.lookAt(p, p + inward)
	-- a reader facing the wall sees the part's -X as their right
	local right = -cf.RightVector
	local fwd = frame:VectorToWorldSpace(V.new(0, 0, forward))
	local label = if right:Dot(fwd) > 0 then text .. " \u{2192}" else "\u{2190} " .. text
	local plate = kit:at(
		parent,
		"Chalk",
		cf,
		{ 2.4, 0.5, 0.02 },
		{ 0, 0, 0 },
		"SmoothPlastic",
		{ visual = true, transparency = 1, shadow = false }
	)
	kit:label(plate, "Front", label, {
		Font = "PermanentMarker",
		TextColor3 = r.Color3.fromRGB(226, 226, 218),
		TextTransparency = 0.15,
	})
	return plate
end

function Dressing.moss(kit: Kit.Kit, parent: any, frame: any, z: number, section: any, lane: number, w: number): any
	local side = if lane == 0 then -1 else -lane
	local x = side * (section.innerHalf - 0.02)
	local CF = kit.roblox.CFrame
	return kit:at(parent, "Moss", frame * CF.new(x, 0.45, z), { 0.04, 0.6, w }, { 76, 98, 50 }, "Grass", FLAT)
end

function Dressing.leaves(kit: Kit.Kit, parent: any, frame: any, z: number, x: number, n: number): any
	local CF = kit.roblox.CFrame
	local m = kit:model(parent, "Leaves")
	local colours = { { 150, 92, 36 }, { 178, 128, 44 }, { 120, 84, 40 } }
	for i = 1, n do
		local dz = (i - (n + 1) / 2) * 0.55
		local dx = ((i * 37) % 7 - 3) * 0.09
		kit:at(
			m,
			"Leaf",
			frame * CF.new(x + dx, 0.012, z + dz) * CF.Angles(0, i * 1.3, 0),
			{ 0.34, 0.02, 0.24 },
			colours[(i % 3) + 1],
			"Fabric",
			FLAT
		)
	end
	return m
end

-- a paper boat on the channel's water
function Dressing.boat(kit: Kit.Kit, parent: any, frame: any, z: number, section: any): any
	local CF = kit.roblox.CFrame
	local m = kit:model(parent, "PaperBoat")
	local y = (section.water or 0) + 0.06
	local hull = frame * CF.new(0, y, z) * CF.Angles(0, 0.3, 0)
	kit:at(m, "Hull", hull, { 0.24, 0.1, 0.5 }, { 236, 232, 220 }, "SmoothPlastic", FLAT)
	kit:at(m, "Sail", hull * CF.new(0, 0.12, 0), { 0.03, 0.18, 0.26 }, { 236, 232, 220 }, "SmoothPlastic", FLAT)
	return m
end

-- a rubber duck bobbing in the channel
function Dressing.duck(kit: Kit.Kit, parent: any, frame: any, z: number, section: any): any
	local CF = kit.roblox.CFrame
	local m = kit:model(parent, "RubberDuck")
	local y = (section.water or 0) + 0.1
	local base = frame * CF.new(0.1, y, z) * CF.Angles(0, -0.6, 0)
	kit:at(m, "Body", base, { 0.3, 0.3, 0.3 }, { 246, 206, 40 }, "SmoothPlastic", { visual = true, shape = "Ball" })
	kit:at(
		m,
		"Head",
		base * CF.new(0, 0.17, -0.1),
		{ 0.18, 0.18, 0.18 },
		{ 246, 206, 40 },
		"SmoothPlastic",
		{ visual = true, shape = "Ball" }
	)
	kit:at(m, "Beak", base * CF.new(0, 0.16, -0.21), { 0.08, 0.04, 0.08 }, { 236, 120, 30 }, "SmoothPlastic", VIS)
	return m
end

-- a lost tennis ball (the racquet club is by the bowling alley)
function Dressing.ball(kit: Kit.Kit, parent: any, frame: any, z: number, x: number): any
	local CF = kit.roblox.CFrame
	return kit:at(
		parent,
		"TennisBall",
		frame * CF.new(x, 0.11, z),
		{ 0.22, 0.22, 0.22 },
		{ 206, 222, 62 },
		"Fabric",
		{ visual = true, shape = "Ball" }
	)
end

function Dressing.stand(kit: Kit.Kit, parent: any, a: any): any
	local r = kit.roblox
	local V, CF = r.Vector3, r.CFrame
	local p = V.new(a.x, a.y, a.z)
	local cf = CF.lookAt(p, p + V.new(a.facing.x, 0, a.facing.z))
	local m = kit:model(parent, "FashionStand", { Anchor = "fashionStand", Space = a.space })
	local wood, dark = { 132, 92, 58 }, { 104, 74, 50 } -- a tan fedora reads in the chamber's light
	kit:at(m, "Base", cf * CF.new(0, 0.06, 0), { 0.8, 0.12, 0.8 }, wood, "Wood", VIS)
	kit:at(m, "Post", cf * CF.new(0, 0.86, 0), { 0.12, 1.5, 0.12 }, wood, "Wood", VIS)
	kit:at(m, "Arm", cf * CF.new(0, 1.3, 0), { 0.7, 0.08, 0.08 }, wood, "Wood", VIS)
	kit:at(m, "Scarf", cf * CF.new(0.3, 1.05, 0), { 0.1, 0.45, 0.18 }, { 168, 42, 38 }, "Fabric", VIS)
	-- the fedora on top (brim and crown, a band)
	local hat = cf * CF.new(0, 1.66, 0)
	kit:at(
		m,
		"HatBrim",
		hat * CF.Angles(0, 0, math.pi / 2),
		{ 0.04, 0.62, 0.62 },
		dark,
		"Fabric",
		{ visual = true, shape = "Cylinder" }
	)
	kit:at(
		m,
		"HatCrown",
		hat * CF.new(0, 0.13, 0) * CF.Angles(0, 0, math.pi / 2),
		{ 0.24, 0.36, 0.36 },
		dark,
		"Fabric",
		{ visual = true, shape = "Cylinder" }
	)
	kit:at(
		m,
		"HatBand",
		hat * CF.new(0, 0.05, 0) * CF.Angles(0, 0, math.pi / 2),
		{ 0.06, 0.37, 0.37 },
		{ 168, 42, 38 },
		"Fabric",
		{ visual = true, shape = "Cylinder" }
	)
	return m
end

return Dressing
