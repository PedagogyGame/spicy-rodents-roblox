--!strict
-- tools/bake/skylift/Signs: the way to the sky lift signposted from town (review: "from town nothing says there
-- is a ride, Lift Road is 295 studs of empty road ... a child would not know it is an attraction until they reach
-- its steps"). Model xs_lift_signs (streaming Default: its pieces stand from the town centre to Lift Road; each
-- piece is an Atomic Model). Everything is in the F4 bake: nothing is added to the town bake.
--   Fingerposts: a dark post with cream arms pointing the way ("SKY LIFT", "THE LOOKOUT"; "TOWN CENTRE" back), at
--     the town's central crossing and where the westside street meets the three cross streets toward the centre,
--     each on the sidewalk's outer edge, clear of the town's lamps, poles and trees.
--   Pylon: a tall lit sign where the westside street ends and Lift Road begins: a red board ("SKY LIFT", "THE
--     LOOKOUT") on a column, a cabin on its cable over it, floodlit at night.
--   Banners: a red "SKY LIFT" banner on each of Lift Road's lamp posts.
--   Shelter: a roofed bench on Lift Road's east verge with a map board for those walking from town.
-- Interface: build(roblox, parent) -> Model; spots() -> { Spot } (pure: every piece's world x, z and kind);
--   BUDGET

local Approach = require("./Approach")
local Common = require("./Common")
local Kit = require("../alley/Kit")

local Signs = {}

Signs.BUDGET = 70

export type Spot = { name: string, kind: string, x: number, z: number, arms: { { any } }? }

-- Each fingerpost: its spot (world x, z) and its arms { text, dx, dz } (unit direction the arm points).
local SOUTH, WEST, EAST = { 0, -1 }, { -1, 0 }, { 1, 0 }
function Signs.spots(): { Spot }
	local out: { Spot } = {
		-- the central crossing (rd_001 x rd_010), its south-west corner: west along the main east-west street
		{
			name = "FingerCentre",
			kind = "finger",
			x = -33.4,
			z = -33.4,
			arms = { { "SKY LIFT", WEST[1], WEST[2] }, { "THE LOOKOUT", WEST[1], WEST[2] } },
		},
		-- the westside street (x -722.5) where the cross streets come in from the centre: on its east sidewalk's
		-- outer edge (x -697.5, 6.25 wide), pointing south down the street to Lift Road
		{
			name = "FingerWestsideNorth",
			kind = "finger",
			x = -695.0,
			z = 386,
			arms = {
				{ "SKY LIFT", SOUTH[1], SOUTH[2] },
				{ "THE LOOKOUT", SOUTH[1], SOUTH[2] },
				{ "TOWN CENTRE", EAST[1], EAST[2] },
			},
		},
		{
			name = "FingerWestsideMid",
			kind = "finger",
			x = -695.0,
			z = -24,
			arms = {
				{ "SKY LIFT", SOUTH[1], SOUTH[2] },
				{ "THE LOOKOUT", SOUTH[1], SOUTH[2] },
				{ "TOWN CENTRE", EAST[1], EAST[2] },
			},
		},
		{
			name = "FingerWestsideSouth",
			kind = "finger",
			x = -695.0,
			z = -480,
			arms = { { "SKY LIFT", SOUTH[1], SOUTH[2] }, { "THE LOOKOUT", SOUTH[1], SOUTH[2] } },
		},
		-- where the westside street ends and Lift Road begins: the pylon on the west verge, past the sidewalk
		{ name = "Pylon", kind = "pylon", x = -757.5, z = -632 },
		-- the shelter on Lift Road's east verge, past the sidewalk (x -700.6..-694.4)
		{ name = "Shelter", kind = "shelter", x = -690.6, z = -712 },
	}
	for i, l in Approach.roadLamps() do
		table.insert(out, { name = `Banner{i}`, kind = "banner", x = l.x, z = l.z })
	end
	return out
end

local POST = { 34, 40, 38 } -- the fingerposts' dark green
local BOARD = { 240, 234, 216 }

local function fingerpost(kit0: Kit.Kit, parent: any, s: Spot)
	local roblox = kit0.roblox
	local CFrame = roblox.CFrame
	local x, z = s.x, s.z
	local g = Common.ground(x, z)
	local m = kit0:model(parent, s.name)
	m.ModelStreamingMode = roblox.Enum.ModelStreamingMode.Atomic
	kit0:cyl(m, "Base", x, g + 0.15, -z, 0.5, 0.9, "Y", POST, "Metal")
	kit0:cyl(m, "Post", x, g + 4.4, -z, 9.6, 0.36, "Y", POST, "Metal")
	kit0:ball(m, "Finial", x, g + 9.3, -z, 0.55, Common.RED, "Metal", { collide = false, query = false })
	for i, a in s.arms :: { { any } } do
		local text, dx, dz = a[1] :: string, a[2] :: number, a[3] :: number
		local len = if #text > 9 then 4.6 else 3.8
		local yaw = math.atan2(-dz, dx)
		local y = g + 8.3 - (i - 1) * 1.15
		local bx, bz = x + dx * (0.25 + len / 2), z + dz * (0.25 + len / 2)
		local board = kit0:at(m, "Arm", bx, y, -bz, len, 0.9, 0.16, BOARD, "SmoothPlastic", {
			collide = false,
			query = false,
			rot = CFrame.Angles(0, yaw, 0),
		})
		-- the pointed end: a square turned 45 degrees on the arm's tip
		local tx, tz = x + dx * (0.25 + len), z + dz * (0.25 + len)
		kit0:at(m, "ArmTip", tx, y, -tz, 0.64, 0.64, 0.16, BOARD, "SmoothPlastic", {
			collide = false,
			query = false,
			rot = CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, math.pi / 4),
		})
		for _, face in { "Front", "Back" } do
			local gui = kit0:gui(board, face, 40)
			kit0:label(gui, {
				Text = text,
				TextColor = if text == "TOWN CENTRE" then POST else Common.RED_DARK,
				Font = "GothamBlack",
				Size = { 0.9, 0.66 },
				Pos = { 0.05, 0.17 },
			})
		end
	end
end

local function pylon(kit0: Kit.Kit, parent: any, s: Spot)
	local roblox = kit0.roblox
	local x, z = s.x, s.z
	local g = Common.ground(x, z)
	local m = kit0:model(parent, s.name)
	m.ModelStreamingMode = roblox.Enum.ModelStreamingMode.Atomic
	kit0:box(m, "Plinth", x - 1.6, x + 1.6, g - 0.8, g + 0.9, -z - 1.6, -z + 1.6, Common.CONCRETE, "Concrete")
	kit0:box(m, "Column", x - 0.55, x + 0.55, g + 0.9, g + 15.8, -z - 0.55, -z + 0.55, Common.STEEL_DARK, "Metal")
	-- the board: across the street's line (its faces to the north, toward town, and to the south)
	local b0, b1 = g + 15.6, g + 20.6
	local board = kit0:box(m, "Board", x - 4.4, x + 4.4, b0, b1, -z - 0.35, -z + 0.35, Common.RED, "SmoothPlastic", {
		collide = false,
	})
	for _, face in { "Front", "Back" } do
		local gui = kit0:gui(board, face, 30)
		gui.Brightness = 2
		kit0:label(gui, {
			Text = "SKY LIFT",
			TextColor = Common.CREAM,
			Font = "GothamBlack",
			Size = { 0.9, 0.5 },
			Pos = { 0.05, 0.08 },
		})
		kit0:label(gui, {
			Text = "THE LOOKOUT  -  RIDES ALL DAY",
			TextColor = Common.CREAM,
			Font = "GothamBold",
			Size = { 0.86, 0.2 },
			Pos = { 0.07, 0.66 },
		})
	end
	-- a cabin on its cable over the board (the lift's livery: red, a cream window band, glass)
	local c0 = b1 + 0.3
	kit0:box(m, "CabinBody", x - 1.5, x + 1.5, c0, c0 + 2.2, -z - 0.6, -z + 0.6, Common.RED, "SmoothPlastic", {
		collide = false,
		query = false,
	})
	kit0:box(m, "CabinWindows", x - 1.3, x + 1.3, c0 + 1.0, c0 + 1.8, -z - 0.65, -z + 0.65, Common.GLASS, "Glass", {
		collide = false,
		query = false,
	})
	kit0:box(m, "CabinRoof", x - 1.65, x + 1.65, c0 + 2.2, c0 + 2.45, -z - 0.7, -z + 0.7, Common.CREAM, "Metal", {
		collide = false,
		query = false,
	})
	Common.rodW(kit0, m, "Hanger", { x, c0 + 2.45, z }, { x, c0 + 3.6, z }, 0.18, Common.STEEL_DARK, "Metal", {
		collide = false,
		query = false,
	})
	Common.rodW(
		kit0,
		m,
		"Cable",
		{ x - 4.6, c0 + 3.95, z },
		{ x + 4.6, c0 + 3.45, z },
		0.16,
		Common.ROPE,
		"Metal",
		{ collide = false, query = false }
	)
	-- floodlights: a lamp bar over each face, shining down onto the board
	for _, side in { -1, 1 } do
		local bar = kit0:box(
			m,
			"Floodlight",
			x - 3.6,
			x + 3.6,
			b1 + 0.05,
			b1 + 0.3,
			-z - side * 0.9 - 0.15,
			-z - side * 0.9 + 0.15,
			Common.WARM_LIGHT,
			"Neon",
			{ collide = false, query = false, shadow = false }
		)
		bar:SetAttribute("NightLight", true)
		kit0:light(bar, "SpotLight", {
			Face = "Bottom",
			Range = 9,
			Brightness = 2.2,
			Angle = 100,
			Color = Common.WARM_LIGHT,
			Shadows = false,
		})
	end
end

local function banner(kit0: Kit.Kit, parent: any, s: Spot, side: number)
	local roblox = kit0.roblox
	local x, z = s.x, s.z
	local g = Common.ground(x, z)
	local m = kit0:model(parent, s.name)
	m.ModelStreamingMode = roblox.Enum.ModelStreamingMode.Atomic
	-- on the post's side away from the road (the lamp's arm reaches over the road), hung from a bracket
	Common.rodW(
		kit0,
		m,
		"Bracket",
		{ x + side * 0.45, g + 12.5, z },
		{ x + side * 2.1, g + 12.5, z },
		0.14,
		POST,
		"Metal",
		{
			collide = false,
			query = false,
		}
	)
	local x0, x1 = x + side * 0.5, x + side * 2.0
	local flag = kit0:box(
		m,
		"Banner",
		math.min(x0, x1),
		math.max(x0, x1),
		g + 8.6,
		g + 12.4,
		-z - 0.04,
		-z + 0.04,
		Common.RED,
		"Fabric",
		{ collide = false, query = false }
	)
	for _, face in { "Front", "Back" } do
		local gui = kit0:gui(flag, face, 40)
		kit0:label(gui, {
			Text = "SKY\nLIFT",
			TextColor = Common.CREAM,
			Font = "GothamBlack",
			Size = { 0.8, 0.6 },
			Pos = { 0.1, 0.2 },
		})
	end
end

local function shelter(kit0: Kit.Kit, parent: any, s: Spot)
	local roblox = kit0.roblox
	local g = Common.ground(s.x, s.z)
	-- its own frame: +D toward the road (west), +X south along it
	local k = Kit.new(roblox, { x = s.x, z = s.z, floorY = g, yaw = math.pi / 2 })
	local m = k:model(parent, s.name)
	m.ModelStreamingMode = roblox.Enum.ModelStreamingMode.Atomic
	for _, px in { -3.5, 3.5 } do
		k:box(m, "Post", px - 0.12, px + 0.12, -0.4, 7.4, 1.3, 1.54, Common.FRAME, "Metal")
		k:box(m, "Post", px - 0.12, px + 0.12, -0.4, 7.4, -1.7, -1.46, Common.FRAME, "Metal")
	end
	k:box(m, "Roof", -3.9, 3.9, 7.4, 7.7, -2.0, 1.9, Common.RED, "Metal")
	k:box(m, "BackGlass", -3.38, 3.38, 0.4, 7.2, -1.62, -1.54, Common.GLASS, "Glass", { transparency = 0.5 })
	k:box(m, "Seat", -2.6, 2.6, 1.3, 1.6, -1.45, -0.35, Common.WOOD, "WoodPlanks")
	k:box(m, "SeatLeg", -0.2, 0.2, -0.3, 1.3, -1.4, -0.5, Common.FRAME, "Metal")
	-- the map board at the north end, for those walking down from town
	local map = k:box(m, "MapBoard", -3.62, -3.38, 0.6, 6.8, -1.46, 1.3, Common.CREAM, "SmoothPlastic")
	for _, face in { "Left", "Right" } do
		local gui = k:gui(map, face, 30)
		k:label(gui, {
			Text = "SKY LIFT",
			TextColor = Common.RED,
			Font = "GothamBlack",
			Size = { 0.9, 0.16 },
			Pos = { 0.05, 0.05 },
		})
		k:label(gui, {
			Text = "Lift Road: the station is at the end,\npast the car park.\nCabins up to THE LOOKOUT\nrestaurant all day, free.\nOr walk the hill trail.",
			TextColor = Common.WOOD_DARK,
			Font = "Gotham",
			Size = { 0.86, 0.62 },
			Pos = { 0.07, 0.28 },
		})
	end
end

function Signs.build(roblox: any, parent: any): any
	local kit0 = Common.worldKit(roblox)
	local m = kit0:model(parent, "xs_lift_signs")
	m.ModelStreamingMode = roblox.Enum.ModelStreamingMode.Default
	m:SetAttribute("Family", Common.FAMILY)
	m:SetAttribute("PartBudget", Signs.BUDGET)
	local lamps = Approach.roadLamps()
	local nBanner = 0
	for _, s in Signs.spots() do
		if s.kind == "finger" then
			fingerpost(kit0, m, s)
		elseif s.kind == "pylon" then
			pylon(kit0, m, s)
		elseif s.kind == "shelter" then
			shelter(kit0, m, s)
		elseif s.kind == "banner" then
			nBanner += 1
			banner(kit0, m, s, lamps[nBanner].side)
		end
	end
	return m
end

return Signs
