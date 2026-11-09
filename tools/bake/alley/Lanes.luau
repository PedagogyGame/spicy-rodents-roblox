--!strict
-- tools/bake/alley/Lanes: six lanes in three pairs (brief v2 §13a): maple and pine boards, the foul line, approach
-- dots, target arrows, gutters, capping, pin decks with spots, ten pins per lane (welded composite parts the
-- server unanchors for play), pits with cushions, kickbacks, the masking units with lane numbers, the pinsetter
-- machines and sweep bars, a ball per lane, the ball-return hoods and racks between each pair's approaches,
-- settees and scorer consoles, overhead score monitors (SurfaceGui the server rewrites) and the lights.
-- Names the server relies on (Server/Minigames/BowlingLane): Lanes.Lane<i>.{Ball, Pins.Pin<n> (PrimaryPart
-- Body), Sweep}; Scoreboards.Lane<i>.Screen (SurfaceGui "Score").
-- Interface: build(kit, root) -> nothing; PIN_PROFILE; BALL_COLORS

local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")

local Lanes = {}
local L = AlleyLayout

local MAPLE = { 228, 198, 150 }
local MAPLE2 = { 220, 188, 140 }
local PINE = { 216, 178, 118 }
local PINE2 = { 208, 170, 110 }
local GUTTER = { 46, 48, 54 }
local CAP = { 26, 26, 30 }
local DARK = { 36, 30, 26 }
local PIN_WHITE = { 248, 247, 242 }
local PIN_RED = { 196, 28, 38 }
local KICK = { 34, 36, 58 }

-- Pin profile (studs): { y0, y1, diameter } stacked cylinders, then the head ball. Real pin x 3.8.
Lanes.PIN_PROFILE = {
	{ 0.0, 0.12, 0.30 },
	{ 0.10, 0.30, 0.42 },
	{ 0.28, 0.62, 0.46 },
	{ 0.60, 0.82, 0.36 },
	{ 0.80, 1.17, 0.21 },
}
Lanes.PIN_HEAD = { y = 1.29, d = 0.27 }
Lanes.BALL_COLORS = {
	{ 168, 30, 40 },
	{ 30, 70, 170 },
	{ 30, 128, 70 },
	{ 110, 40, 150 },
	{ 220, 110, 30 },
	{ 24, 120, 130 },
}

local function board(kit: any, parent: any, lane: number)
	local x = L.laneX(lane)
	local half = L.LANE_W / 2
	-- collision bed (one smooth surface for the ball), boards drawn just above it
	kit:box(parent, "Bed", x - half, x + half, L.DUCT_CEIL, -0.01, L.FOUL_D, L.DECK_START, MAPLE, "Wood")
	local strips = 13
	local w = L.LANE_W / strips
	local zones = { { L.FOUL_D, 16, MAPLE, MAPLE2 }, { 16, 40, PINE, PINE2 }, { 40, L.DECK_START, MAPLE, MAPLE2 } }
	for s = 1, strips do
		local sx0 = x - half + (s - 1) * w
		for _, z in zones do
			local col = if s % 2 == 0 then z[3] else z[4]
			kit:box(parent, "Boards", sx0 + 0.006, sx0 + w - 0.006, -0.012, 0, z[1], z[2], col, "Wood", {
				collide = false,
				query = false,
				shadow = false,
			})
		end
	end
	-- seams between strips (thin dark lines)
	for s = 1, strips - 1 do
		local sx = x - half + s * w
		kit:box(
			parent,
			"Seam",
			sx - 0.006,
			sx + 0.006,
			-0.012,
			-0.002,
			L.FOUL_D,
			L.DECK_START,
			{ 150, 112, 70 },
			"Wood",
			{
				collide = false,
				query = false,
				shadow = false,
			}
		)
	end
	-- foul line
	kit:box(
		parent,
		"FoulLine",
		x - half - L.GUTTER_W,
		x + half + L.GUTTER_W,
		-0.01,
		0.004,
		-0.06,
		0.06,
		{ 20, 20, 22 },
		"SmoothPlastic",
		{
			collide = false,
			query = false,
		}
	)
	-- target arrows: seven chevrons in a V pointing at the pins (boards 5..35)
	for k = 1, 7 do
		local ax = x - half + (k * 5 - 0.5) * (L.LANE_W / 39)
		local depthBack = math.abs(k - 4)
		local ad = L.ARROWS_D - depthBack * 0.55
		for side = -1, 1, 2 do
			kit:at(
				parent,
				"Arrow",
				ax + side * 0.09,
				0.003,
				ad - 0.18,
				0.06,
				0.006,
				0.55,
				{ 40, 32, 28 },
				"SmoothPlastic",
				{
					collide = false,
					query = false,
					shadow = false,
					rot = kit.roblox.CFrame.Angles(0, side * 0.42, 0),
				}
			)
		end
	end
	-- range-finder dots further down
	for k = 0, 1 do
		local dx = x + (k * 2 - 1) * 0.78
		kit:cyl(
			parent,
			"Dot",
			dx,
			0.001,
			34,
			0.004,
			0.08,
			"Y",
			DARK,
			"SmoothPlastic",
			{ collide = false, query = false, shadow = false }
		)
	end
	-- gutters both sides, running on into the pit
	for side = -1, 1, 2 do
		local g0 = x + side * half
		local g1 = g0 + side * L.GUTTER_W
		kit:box(
			parent,
			"Gutter",
			math.min(g0, g1),
			math.max(g0, g1),
			L.DUCT_CEIL,
			-L.GUTTER_DEPTH,
			L.FOUL_D - 0.4,
			L.DECK_END,
			GUTTER,
			"Metal"
		)
		-- a rounded lip on the lane side
		kit:cyl(
			parent,
			"GutterLip",
			g0 + side * 0.06,
			-L.GUTTER_DEPTH + 0.06,
			(L.FOUL_D + L.DECK_END) / 2,
			L.DECK_END - L.FOUL_D,
			0.12,
			"D",
			GUTTER,
			"Metal",
			{
				collide = false,
			}
		)
	end
	-- pin deck: lighter maple, pin spots
	kit:box(parent, "Deck", x - half, x + half, L.DUCT_CEIL, 0, L.DECK_START, L.DECK_END, { 236, 214, 172 }, "Wood")
	for n = 1, 10 do
		local px, pd = L.pinLocal(lane, n)
		kit:cyl(
			parent,
			"PinSpot",
			px,
			0.002,
			pd,
			0.004,
			0.18,
			"Y",
			{ 120, 90, 60 },
			"SmoothPlastic",
			{ collide = false, query = false, shadow = false }
		)
	end
	-- the pit
	kit:box(
		parent,
		"PitFloor",
		x - half - L.GUTTER_W,
		x + half + L.GUTTER_W,
		L.PIT_Y - 0.15,
		L.PIT_Y,
		L.DECK_END,
		L.PIT_END,
		{ 20, 20, 22 },
		"Rubber" :: any
	)
	kit:box(
		parent,
		"PitBack",
		x - half - L.GUTTER_W,
		x + half + L.GUTTER_W,
		L.PIT_Y,
		L.MASK_BOTTOM,
		L.PIT_END,
		L.PIT_END + 0.3,
		{ 24, 24, 28 },
		"Fabric"
	)
	kit:box(
		parent,
		"Cushion",
		x - half - L.GUTTER_W + 0.1,
		x + half + L.GUTTER_W - 0.1,
		-0.9,
		L.MASK_BOTTOM,
		L.CUSHION_D,
		L.CUSHION_D + 0.25,
		{ 14, 14, 16 },
		"Fabric"
	)
	-- the ball lift door in the pit floor (the ball drops through it into the duct)
	local sideOf = L.sideOf(lane)
	local hx = x - sideOf * (half + L.GUTTER_W - 0.5)
	kit:box(
		parent,
		"LiftDoor",
		hx - 0.45,
		hx + 0.45,
		L.PIT_Y,
		L.PIT_Y + 0.02,
		L.CUSHION_D - 1.2,
		L.CUSHION_D - 0.3,
		{ 60, 60, 64 },
		"DiamondPlate",
		{ collide = false }
	)
end

local function pins(kit: any, parent: any, lane: number)
	local folder = kit:folder(parent, "Pins")
	for n = 1, 10 do
		local px, pd = L.pinLocal(lane, n)
		local m = kit:model(folder, `Pin{n}`)
		m:SetAttribute("Spot", n)
		local opts = { group = "BowlingPhysics", shadow = true }
		local body
		for i, pr in Lanes.PIN_PROFILE do
			local p = kit:cyl(
				m,
				if i == 3 then "Body" else `Seg{i}`,
				px,
				(pr[1] + pr[2]) / 2,
				pd,
				pr[2] - pr[1],
				pr[3],
				"Y",
				PIN_WHITE,
				"SmoothPlastic",
				opts
			)
			if i == 3 then
				body = p
			end
		end
		kit:ball(m, "Head", px, Lanes.PIN_HEAD.y, pd, Lanes.PIN_HEAD.d, PIN_WHITE, "SmoothPlastic", opts)
		for k = 0, 1 do
			kit:cyl(m, "Stripe", px, 0.95 + k * 0.08, pd, 0.035, 0.225, "Y", PIN_RED, "SmoothPlastic", {
				collide = false,
				query = false,
				massless = true,
				group = "BowlingPhysics",
			})
		end
		m.PrimaryPart = body
		for _, part in m:GetChildren() do
			if part ~= body and part:IsA("BasePart") then
				local w = kit.roblox.Instance.new("WeldConstraint")
				w.Part0 = body
				w.Part1 = part
				w.Parent = body
			end
		end
	end
end

local function machine(kit: any, parent: any, lane: number)
	local x = L.laneX(lane)
	local half = L.LANE_W / 2 + L.GUTTER_W
	local m = kit:model(parent, "Machine")
	-- the pinsetter frame over the deck and pit (seen from the machine room behind)
	kit:box(
		m,
		"Frame",
		x - half + 0.1,
		x + half - 0.1,
		L.MASK_BOTTOM + 0.6,
		9.4,
		L.MACHINE_D0 + 0.6,
		L.MACHINE_D1 - 0.4,
		{ 112, 122, 116 },
		"Metal"
	)
	kit:box(m, "Turret", x - 1.4, x + 1.4, 9.4, 10.8, 58, 62, { 96, 104, 100 }, "Metal")
	kit:cyl(m, "Wheel", x, 6.6, L.MACHINE_D1 - 0.25, 0.3, 4.2, "D", { 80, 86, 84 }, "Metal")
	kit:box(m, "Motor", x + 1.2, x + 2.4, 3.6, 5.0, L.MACHINE_D1 - 1.6, L.MACHINE_D1 - 0.3, { 60, 90, 120 }, "Metal")
	kit:box(
		m,
		"Belt",
		x - 0.2,
		x + 0.2,
		3.6,
		9.2,
		L.MACHINE_D1 - 0.42,
		L.MACHINE_D1 - 0.32,
		{ 30, 30, 30 },
		"Rubber" :: any,
		{ collide = false }
	)
	local tag = kit:box(
		m,
		"SerialPlate",
		x - 0.8,
		x + 0.8,
		7.6,
		8.3,
		L.MACHINE_D1 - 0.42,
		L.MACHINE_D1 - 0.38,
		{ 200, 196, 170 },
		"Metal",
		{ collide = false }
	)
	local g = kit:gui(tag, "Front", 60)
	kit:label(g, { Text = `LANE {lane}  A-2`, TextColor = { 30, 30, 30 }, Font = "Code" })
	-- the sweep bar (parked up inside the machine; BowlingLane drops and sweeps it)
	local sweep = kit:box(
		parent,
		"Sweep",
		x - L.LANE_W / 2 - 0.3,
		x + L.LANE_W / 2 + 0.3,
		L.MASK_BOTTOM + 0.1,
		L.MASK_BOTTOM + 0.7,
		L.DECK_START - 0.15,
		L.DECK_START + 0.05,
		{ 70, 74, 80 },
		"Metal",
		{
			collide = false,
			query = false,
		}
	)
	sweep:SetAttribute("RestY", L.MASK_BOTTOM + 0.4)
	kit:box(
		parent,
		"SweepEdge",
		x - L.LANE_W / 2 - 0.3,
		x + L.LANE_W / 2 + 0.3,
		L.MASK_BOTTOM + 0.1,
		L.MASK_BOTTOM + 0.18,
		L.DECK_START - 0.17,
		L.DECK_START - 0.15,
		{ 240, 196, 40 },
		"SmoothPlastic",
		{
			collide = false,
			query = false,
		}
	)
end

local function kickbacksAndMasking(kit: any, root: any)
	local m = kit:model(root, "Masking")
	for k = 0, L.LANES do
		local kx = -L.LANE_BLOCK_X + k * L.PITCH
		local edge = k == 0 or k == L.LANES
		local w = if edge then 0.6 else 0.4
		-- capping along the whole lane between gutters, then the tall kickback by the deck
		kit:box(m, "Capping", kx - w / 2, kx + w / 2, L.DUCT_CEIL, 0.12, L.FOUL_D - 0.3, 50, CAP, "SmoothPlastic")
		kit:box(
			m,
			"Kickback",
			kx - w / 2,
			kx + w / 2,
			L.PIT_Y,
			L.MASK_BOTTOM,
			50,
			L.PIT_END + 0.3,
			KICK,
			"SmoothPlastic"
		)
		kit:box(
			m,
			"KickbackTrim",
			kx - w / 2 - 0.02,
			kx + w / 2 + 0.02,
			1.0,
			1.15,
			50,
			L.DECK_END,
			{ 236, 196, 64 },
			"Neon",
			{
				collide = false,
			}
		)
		if edge then
			kit:box(
				m,
				"SideWall",
				kx - w / 2,
				kx + w / 2,
				0,
				L.MASK_BOTTOM,
				L.FOUL_D - 0.3,
				50,
				{ 46, 52, 88 },
				"SmoothPlastic"
			)
		end
	end
	-- the masking units: one face across all six lanes, art per pair, lane numbers
	local front = L.MACHINE_D0
	kit:box(
		m,
		"MaskFace",
		-L.LANE_BLOCK_X - 0.3,
		L.LANE_BLOCK_X + 0.3,
		L.MASK_BOTTOM,
		L.CEILING_Y,
		front - 0.4,
		front,
		{ 26, 30, 60 },
		"SmoothPlastic"
	)
	local pairCols = { { 232, 118, 40 }, { 36, 150, 150 }, { 236, 196, 64 } }
	for p = 1, 3 do
		local px = L.pairX(p)
		local col = pairCols[p]
		-- swooping stripes (three bands) and a starburst per pair
		for b = 0, 2 do
			kit:at(
				m,
				"MaskStripe",
				px,
				L.MASK_BOTTOM + 1.6 + b * 0.55,
				front - 0.42,
				11.6,
				0.28,
				0.02,
				if b == 1 then { 240, 240, 230 } else col,
				"Neon",
				{
					collide = false,
					rot = kit.roblox.CFrame.Angles(0, 0, 0.06 * (b - 1)),
				}
			)
		end
		kit:cyl(
			m,
			"Starburst",
			px,
			L.MASK_BOTTOM + 3.9,
			front - 0.43,
			0.02,
			1.2,
			"D",
			{ 255, 230, 140 },
			"Neon",
			{ collide = false }
		)
		for r = 0, 7 do
			kit:at(m, "Ray", px, L.MASK_BOTTOM + 3.9, front - 0.425, 2.4, 0.07, 0.02, { 255, 230, 140 }, "Neon", {
				collide = false,
				rot = kit.roblox.CFrame.Angles(0, 0, r * math.pi / 8),
			})
		end
		-- the down-lights on the pins
		local fixture = kit:box(
			m,
			"PinLight",
			px - 6,
			px + 6,
			L.MASK_BOTTOM - 0.05,
			L.MASK_BOTTOM + 0.1,
			front - 0.2,
			front + 0.4,
			{ 255, 246, 220 },
			"Neon",
			{
				collide = false,
			}
		)
		kit:light(
			fixture,
			"SurfaceLight",
			{ Face = "Bottom", Range = 9, Angle = 70, Brightness = 2.6, Color = { 255, 244, 224 }, Shadows = true }
		)
	end
	for lane = 1, L.LANES do
		local num = kit:box(
			m,
			`LaneNumber{lane}`,
			L.laneX(lane) - 0.8,
			L.laneX(lane) + 0.8,
			L.MASK_BOTTOM + 5.2,
			L.MASK_BOTTOM + 6.8,
			front - 0.45,
			front - 0.41,
			{ 20, 20, 40 },
			"SmoothPlastic",
			{
				collide = false,
			}
		)
		local g = kit:gui(num, "Back", 60)
		kit:label(g, { Text = tostring(lane), TextColor = { 255, 255, 255 }, Font = "FredokaOne" })
	end
end

-- Ball-return hood and rack between each pair's approaches; the riser in the duct comes up inside the hood
-- and the mouth on its bowler side is where the ball (and a squirrel) comes out onto the rails.
local function hoods(kit: any, root: any)
	local folder = kit:folder(root, "Returns")
	local chrome = { 196, 198, 204 }
	local band = { 36, 150, 150 }
	for p = 1, 3 do
		local m = kit:model(folder, `Return{p}`)
		local x = L.pairX(p)
		local hw = L.HOOD_W / 2
		local d0, d1 = L.HOOD_D1, L.HOOD_D0 -- -4.2 .. -0.8
		local mouthHW, mouthY0, mouthY1 = 0.62, 1.35, 2.25
		-- sides and back
		for side = -1, 1, 2 do
			kit:box(m, "HoodSide", x + side * hw - 0.08, x + side * hw + 0.08, 0, 1.6, d0, d1, chrome, "Metal")
			kit:box(
				m,
				"HoodBand",
				x + side * hw - 0.09,
				x + side * hw + 0.09,
				0.9,
				1.15,
				d0,
				d1,
				band,
				"SmoothPlastic",
				{ collide = false }
			)
		end
		kit:box(m, "HoodBack", x - hw, x + hw, 0, 1.6, d1 - 0.12, d1, chrome, "Metal")
		-- the rounded bonnet: a half-buried cylinder along the lane
		kit:cyl(m, "Bonnet", x, 1.6, (d0 + d1) / 2, d1 - d0, L.HOOD_W, "D", chrome, "Metal")
		kit:box(m, "BonnetCapBack", x - hw, x + hw, 1.6, 2.4, d1 - 0.06, d1, chrome, "Metal", { collide = false })
		-- the front face around the mouth
		kit:box(m, "FaceLow", x - hw, x + hw, 0, mouthY0, d0, d0 + 0.12, chrome, "Metal")
		for side = -1, 1, 2 do
			local a = x + side * mouthHW
			local b = x + side * hw
			kit:box(m, "FaceSide", math.min(a, b), math.max(a, b), mouthY0, 2.4, d0, d0 + 0.12, chrome, "Metal")
		end
		kit:box(m, "FaceTop", x - mouthHW, x + mouthHW, mouthY1, 2.6, d0, d0 + 0.12, chrome, "Metal")
		kit:box(
			m,
			"MouthLiner",
			x - mouthHW,
			x + mouthHW,
			mouthY0,
			mouthY1,
			d0 + 0.12,
			d0 + 0.9,
			{ 16, 16, 18 },
			"SmoothPlastic",
			{
				collide = false,
			}
		)
		kit:box(
			m,
			"MouthLip",
			x - mouthHW - 0.05,
			x + mouthHW + 0.05,
			mouthY0 - 0.05,
			mouthY0,
			d0 - 0.15,
			d0 + 0.12,
			{ 30, 30, 34 },
			"Rubber" :: any
		)
		-- the lift's inner chute walls (dark) from the floor opening to the mouth
		kit:box(
			m,
			"ChuteBack",
			x - 0.8,
			x + 0.8,
			0,
			2.3,
			L.SHAFT_D1 + 0.1,
			L.SHAFT_D1 + 0.2,
			{ 20, 20, 22 },
			"SmoothPlastic",
			{ collide = false }
		)
		kit:box(
			m,
			"ChuteFloor",
			x - 0.7,
			x + 0.7,
			1.25,
			1.35,
			d0 + 0.12,
			L.SHAFT_D0,
			{ 30, 30, 34 },
			"Metal",
			{ collide = false }
		)
		-- rails (two, falling gently toward the bowler), supports and an end stop
		local railLen = L.HOOD_D1 - L.RACK_D1
		for side = -1, 1, 2 do
			kit:at(
				m,
				"Rail",
				x + side * 0.18,
				L.RACK_Y - 0.075 - 0.075,
				(L.HOOD_D1 + L.RACK_D1) / 2,
				0.09,
				0.15,
				railLen,
				chrome,
				"Metal",
				{
					rot = kit.roblox.CFrame.Angles(-0.15 / railLen, 0, 0),
				}
			)
		end
		kit:box(
			m,
			"RackStand",
			x - 0.55,
			x + 0.55,
			0,
			L.RACK_Y - 0.4,
			L.RACK_D1 + 0.4,
			L.HOOD_D1 - 0.3,
			{ 40, 44, 70 },
			"SmoothPlastic"
		)
		kit:box(
			m,
			"RackStandBand",
			x - 0.56,
			x + 0.56,
			0.6,
			0.8,
			L.RACK_D1 + 0.4,
			L.HOOD_D1 - 0.3,
			band,
			"SmoothPlastic",
			{ collide = false }
		)
		kit:box(
			m,
			"EndStop",
			x - 0.35,
			x + 0.35,
			L.RACK_Y - 0.4,
			L.RACK_Y + 0.3,
			L.RACK_D1,
			L.RACK_D1 + 0.2,
			chrome,
			"Metal"
		)
		-- a hand dryer vent on top (every ball return has one)
		kit:box(m, "Dryer", x - 0.45, x + 0.45, 2.3, 2.75, -2.8, -1.8, { 60, 62, 66 }, "Metal", { collide = false })
		kit:box(
			m,
			"DryerGrille",
			x - 0.35,
			x + 0.35,
			2.75,
			2.78,
			-2.7,
			-1.9,
			{ 24, 24, 26 },
			"DiamondPlate",
			{ collide = false }
		)
		-- spare house balls resting further down the rack
		local spare = { { 230, 196, 40 }, { 40, 40, 44 }, { 200, 60, 140 } }
		for k, col in spare do
			local d = -7.3 - (k - 1) * 0.9
			local fall = (d - L.HOOD_D1) / (L.RACK_D1 - L.HOOD_D1) * 0.15
			kit:ball(
				m,
				"HouseBall",
				x,
				L.RACK_Y - fall + L.BALL_D / 2,
				d,
				L.BALL_D,
				col,
				"SmoothPlastic",
				{ reflectance = 0.12 }
			)
		end
	end
end

local function approaches(kit: any, root: any)
	local m = kit:model(root, "Approach")
	local holes = {}
	for p = 1, 3 do
		local x = L.pairX(p)
		table.insert(holes, { x - L.DUCT_W / 2, x + L.DUCT_W / 2, L.SHAFT_D0, L.SHAFT_D1 })
	end
	for i, r in kit:holes(-L.LANE_BLOCK_X, L.LANE_BLOCK_X, L.APPROACH_D, L.FOUL_D - 0.06, holes) do
		kit:box(m, `Approach{i}`, r[1], r[2], L.DUCT_CEIL, 0, r[3], r[4], { 222, 192, 146 }, "Wood")
	end
	for lane = 1, L.LANES do
		local x = L.laneX(lane)
		-- board seams on the approach and the dots
		for k = -6, 6 do
			if k ~= 0 then
				kit:box(
					m,
					"ApproachSeam",
					x + k * 0.31 - 0.006,
					x + k * 0.31 + 0.006,
					0,
					0.002,
					L.APPROACH_D,
					-0.1,
					{ 170, 136, 92 },
					"Wood",
					{
						collide = false,
						query = false,
						shadow = false,
					}
				)
			end
		end
		for _, dd in { -3.4, -7.4, -11.6 } do
			for k = -2, 2 do
				kit:cyl(m, "ApproachDot", x + k * 0.52, 0.003, dd, 0.004, 0.09, "Y", DARK, "SmoothPlastic", {
					collide = false,
					query = false,
					shadow = false,
				})
			end
		end
	end
	-- players stay off the lanes (an invisible guard just past the foul line; the ball and pins pass through
	-- it: collision group LaneGuard, registered by Server/Attractions/AttractionService)
	kit:box(m, "LaneGuard", -L.LANE_BLOCK_X, L.LANE_BLOCK_X, 0, 9, 0.6, 0.9, { 255, 0, 0 }, "SmoothPlastic", {
		query = false,
		transparency = 1,
		shadow = false,
		group = "LaneGuard",
	})
	-- the step up to the settee area and its rail line
	kit:box(
		m,
		"SetteeEdge",
		-L.LANE_BLOCK_X,
		L.LANE_BLOCK_X,
		0,
		0.08,
		L.APPROACH_D - 0.3,
		L.APPROACH_D,
		{ 236, 196, 64 },
		"SmoothPlastic",
		{
			collide = false,
		}
	)
end

local function settees(kit: any, root: any)
	local folder = kit:folder(root, "Settees")
	local vinyl = { { 222, 104, 40 }, { 32, 140, 140 }, { 222, 104, 40 } }
	for p = 1, 3 do
		local m = kit:model(folder, `Settee{p}`)
		local x = L.pairX(p)
		local col = vinyl[p]
		local back = L.SETTEE_D - 2.2
		-- a U of bench: back row facing the lanes, two short sides
		kit:box(m, "BenchBase", x - 4.8, x + 4.8, 0, 1.2, back, back + 1.6, { 40, 40, 46 }, "SmoothPlastic")
		kit:box(m, "BenchSeat", x - 4.8, x + 4.8, 1.2, 1.55, back, back + 1.8, col, "Fabric")
		kit:box(m, "BenchBack", x - 4.8, x + 4.8, 1.2, 3.4, back - 0.5, back, col, "Fabric")
		kit:box(
			m,
			"BenchBackTop",
			x - 4.85,
			x + 4.85,
			3.4,
			3.55,
			back - 0.55,
			back + 0.05,
			{ 40, 40, 46 },
			"SmoothPlastic"
		)
		for side = -1, 1, 2 do
			local sx = x + side * 4.0
			kit:box(m, "SideBase", sx - 0.8, sx + 0.8, 0, 1.2, back + 1.6, back + 4.4, { 40, 40, 46 }, "SmoothPlastic")
			kit:box(m, "SideSeat", sx - 0.8, sx + 0.8, 1.2, 1.55, back + 1.6, back + 4.4, col, "Fabric")
			kit:box(
				m,
				"SideBack",
				if side < 0 then sx - 0.8 else sx + 0.3,
				if side < 0 then sx - 0.3 else sx + 0.8,
				1.2,
				3.0,
				back + 1.6,
				back + 4.4,
				col,
				"Fabric"
			)
		end
		-- the scorer's console in the middle: pedestal, tilted screen, a little keypad
		local cd = L.SETTEE_D + 3.2
		kit:box(m, "ConsoleBase", x - 0.7, x + 0.7, 0, 2.3, cd - 0.5, cd + 0.5, { 40, 44, 70 }, "SmoothPlastic")
		local screen = kit:at(m, "ConsoleScreen", x, 2.9, cd, 1.8, 1.2, 0.12, { 18, 22, 40 }, "SmoothPlastic", {
			rot = kit.roblox.CFrame.Angles(-0.6, 0, 0),
		})
		local g = kit:gui(screen, "Back", 80)
		kit:label(g, {
			Text = `LANES {2 * p - 1} - {2 * p}`,
			TextColor = { 120, 230, 230 },
			Font = "GothamBold",
			Size = { 1, 0.4 },
			Pos = { 0, 0.05 },
		})
		kit:label(g, {
			Text = "WALK UP TO A LANE AND PRESS E",
			TextColor = { 255, 210, 90 },
			Font = "GothamBold",
			Size = { 1, 0.35 },
			Pos = { 0, 0.55 },
		})
		-- a little table with a cup
		kit:box(m, "Table", x - 0.6 + 2.6, x + 0.6 + 2.6, 0, 2.1, back - 1.6, back - 0.8, { 60, 44, 32 }, "Wood")
		kit:cyl(
			m,
			"Cup",
			x + 2.5,
			2.35,
			back - 1.2,
			0.5,
			0.3,
			"Y",
			{ 230, 60, 50 },
			"SmoothPlastic",
			{ collide = false }
		)
	end
end

local function scoreboards(kit: any, root: any)
	local folder = kit:folder(root, "Scoreboards")
	for lane = 1, L.LANES do
		local m = kit:model(folder, `Lane{lane}`)
		local x = L.laneX(lane)
		local cy, cd = 9.6, -3.5
		local tilt = kit.roblox.CFrame.Angles(0.22, 0, 0)
		kit:at(
			m,
			"Housing",
			x,
			cy,
			cd + 0.12,
			5.4,
			3.1,
			0.3,
			{ 26, 26, 30 },
			"SmoothPlastic",
			{ collide = false, rot = tilt }
		)
		local screen = kit:at(m, "Screen", x, cy, cd - 0.04, 5.1, 2.8, 0.06, { 14, 18, 40 }, "SmoothPlastic", {
			collide = false,
			rot = tilt,
		})
		local g = kit:gui(screen, "Back", 60)
		g.Name = "Score"
		kit:label(g, {
			Text = `LANE {lane}`,
			TextColor = { 255, 214, 92 },
			Font = "FredokaOne",
			Size = { 1, 0.45 },
			Pos = { 0, 0.08 },
		})
		kit:label(g, {
			Text = "OPEN - walk up and press E",
			TextColor = { 140, 236, 236 },
			Font = "GothamBold",
			Size = { 1, 0.25 },
			Pos = { 0, 0.6 },
		})
		kit:box(
			m,
			"Glow",
			x - 2.5,
			x + 2.5,
			cy - 1.42,
			cy - 1.36,
			cd - 0.3,
			cd + 0.2,
			{ 120, 180, 255 },
			"Neon",
			{ collide = false }
		)
		for side = -1, 1, 2 do
			kit:box(
				m,
				"Hanger",
				x + side * 2 - 0.05,
				x + side * 2 + 0.05,
				cy + 1.5,
				L.CEILING_Y,
				cd,
				cd + 0.1,
				{ 70, 70, 74 },
				"Metal",
				{
					collide = false,
				}
			)
		end
	end
end

local function ceilingLights(kit: any, root: any)
	local m = kit:model(root, "LaneLights")
	-- fluorescent troffers over the approaches and settees, a few real lights among them
	for _, d in { -6, -13, -20 } do
		for p = 1, 3 do
			local x = L.pairX(p)
			local f = kit:box(
				m,
				"Troffer",
				x - 3.6,
				x + 3.6,
				L.CEILING_Y - 0.12,
				L.CEILING_Y,
				d - 0.5,
				d + 0.5,
				{ 250, 248, 238 },
				"Neon",
				{
					collide = false,
				}
			)
			if d == -13 then
				kit:light(f, "PointLight", { Range = 22, Brightness = 1.15, Color = { 255, 244, 226 }, Shadows = true })
			end
		end
	end
	-- dimmer cans down the lanes (cosmic feel), every 12 studs
	for d = 8, 44, 12 do
		for p = 1, 3 do
			kit:cyl(
				m,
				"Can",
				L.pairX(p),
				L.CEILING_Y - 0.1,
				d,
				0.2,
				0.9,
				"Y",
				{ 200, 210, 255 },
				"Neon",
				{ collide = false }
			)
		end
	end
	local mid = kit:box(
		m,
		"LaneWash",
		-2,
		2,
		L.CEILING_Y - 0.1,
		L.CEILING_Y,
		26,
		27,
		{ 190, 200, 255 },
		"Neon",
		{ collide = false }
	)
	kit:light(mid, "PointLight", { Range = 40, Brightness = 0.6, Color = { 200, 210, 255 }, Shadows = false })
	-- ceiling tiles grid over the lane block
	for d = -15, 52, 8 do
		kit:box(
			m,
			"CeilingRib",
			-L.LANE_BLOCK_X,
			L.LANE_BLOCK_X,
			L.CEILING_Y - 0.06,
			L.CEILING_Y,
			d - 0.05,
			d + 0.05,
			{ 70, 70, 82 },
			"Metal",
			{
				collide = false,
			}
		)
	end
end

function Lanes.build(kit: any, root: any)
	local lanes = kit:folder(root, "Lanes")
	for lane = 1, L.LANES do
		local m = kit:model(lanes, `Lane{lane}`)
		m:SetAttribute("Lane", lane)
		m:SetAttribute("Pair", L.pairOf(lane))
		board(kit, m, lane)
		pins(kit, m, lane)
		machine(kit, m, lane)
		local rx, ry, rd = L.rackSlot(lane)
		kit:ball(m, "Ball", rx, ry, rd, L.BALL_D, Lanes.BALL_COLORS[lane], "SmoothPlastic", {
			reflectance = 0.15,
			group = "BowlingPhysics",
		})
	end
	kickbacksAndMasking(kit, root)
	hoods(kit, root)
	approaches(kit, root)
	settees(kit, root)
	scoreboards(kit, root)
	ceilingLights(kit, root)
end

return Lanes
