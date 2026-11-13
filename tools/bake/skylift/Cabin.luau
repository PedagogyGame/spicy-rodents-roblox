--!strict
-- tools/bake/skylift/Cabin: the sky lift's cabin, baked once as CabinTemplate (brief v2 §14: "the gondola must
-- hold up at eye level"; BATCH2 item 36: "modelled interiors (benches, windows, grab rail)"). The client clones
-- it six times and places the clones from Shared/Rides/SkyLift.cabin (lane 5); nothing else in the game moves.
-- Frame (SkyLift's contract): origin = the centre of the floor's top surface, -Z forward (the way it travels),
-- +X right (the door side: the platforms are on a cabin's right), +Y up. Outer box X +-3, Z +-4, Y -0.5..7.5;
-- the grip HANG (10.5) above the origin; the hanger stays in the column X, Z +-0.6 up to 0.6 over the cable.
-- What the client relies on (names are the interface):
--   CabinTemplate (Model, ModelStreamingMode Persistent, attributes Template = true, Ride = "sky_lift"):
--     PrimaryPart "Origin": an invisible 0.2 part at the frame's origin (pivot the clone with it: the model's
--       pivot is the frame);
--     Seats/Seat1..Seat4: Seat parts (Disabled, so they never weld anyone; the server seats riders on its own
--       Seat) whose top is SkyLift.SEAT_LOCAL[k] and whose LookVector is the way the sitter faces; each holds an
--       Attachment "EyeSocket" EYE_ABOVE_SEAT over the seat's top (CameraRig's vehicleFirst eye);
--     Doors/DoorFore and Doors/DoorAft: Models of the two sliding leaves, closed; attribute SlideZ is the leaf's
--       travel along the cabin's Z when fully open (SkyLift.doorFrac 0..1 times it);
--     Light: the ceiling panel with a PointLight (Enabled false in the template: the client lights clones at
--       night; attribute NightLight = true);
--     NumberFront / NumberBack: plates with a TextLabel "Number" the client sets to the cabin's number.
--   Every part anchored, CanCollide, CanQuery and CanTouch false: cabins never collide or answer raycasts.
-- The template itself stands TEMPLATE_DEPTH below the base bullwheel, inside the ground, out of sight.
-- Interface: build(kit, parent) -> Model (kit's place = the template's origin, yaw 0); TEMPLATE_DEPTH; BUDGET

local Common = require("./Common")
local Kit = require("../alley/Kit")
local SkyLift = require("../../../src/shared/Rides/SkyLift")

local Cabin = {}

Cabin.BUDGET = 60
Cabin.TEMPLATE_DEPTH = 40

local GHOST: Kit.Opts = { collide = false, query = false, touch = false }

local function opts(extra: Kit.Opts?): Kit.Opts
	local o = table.clone(GHOST)
	if extra then
		for k, v in extra :: any do
			(o :: any)[k] = v
		end
	end
	return o
end

function Cabin.build(kit: Kit.Kit, parent: any): any
	local roblox = kit.roblox
	local CFrame = roblox.CFrame
	local m = kit:model(parent, "CabinTemplate")
	m:SetAttribute("Template", true)
	m:SetAttribute("Ride", SkyLift.RIDE_ID)
	m:SetAttribute("PartBudget", Cabin.BUDGET)
	m.ModelStreamingMode = roblox.Enum.ModelStreamingMode.Persistent
	local HW, HL = SkyLift.CABIN_WIDTH / 2, SkyLift.CABIN_LENGTH / 2 -- 3, 4
	local BELOW = SkyLift.CABIN_BELOW
	local TOP = SkyLift.CABIN_HEIGHT - BELOW -- 7.5
	local SILL, HEAD = 1.4, 6.4 -- the glass band
	local T = 0.15 -- wall thickness
	local RED, CREAM, FRAME, GLASS = Common.RED, Common.CREAM, Common.FRAME, Common.GLASS
	-- cabin (x, y, z) -> kit (X, Y, D): D = -z
	local function box(p: any, name: string, x0, x1, y0, y1, z0, z1, color, material, o: Kit.Opts?)
		return kit:box(p, name, x0, x1, y0, y1, -z1, -z0, color, material, opts(o))
	end

	local origin = kit:at(m, "Origin", 0, 0, 0, 0.2, 0.2, 0.2, CREAM, "SmoothPlastic", opts({ transparency = 1 }))
	m.PrimaryPart = origin

	-- floor and the lower body (opaque, the lift's red)
	box(m, "Floor", -HW, HW, -BELOW, 0, -HL, HL, { 70, 72, 74 }, "DiamondPlate")
	box(m, "LowFront", -HW, HW, 0, SILL, -HL, -HL + T, RED, "SmoothPlastic")
	box(m, "LowBack", -HW, HW, 0, SILL, HL - T, HL, RED, "SmoothPlastic")
	local lowLeft = box(m, "LowLeft", -HW, -HW + T, 0, SILL, -HL + T, HL - T, RED, "SmoothPlastic")
	-- the right side is inset by the door leaves' thickness, so closed leaves sit flush with the outer box
	box(m, "LowRightFore", HW - 2 * T, HW - T, 0, SILL, -HL + T, -1.5, RED, "SmoothPlastic")
	box(m, "LowRightAft", HW - 2 * T, HW - T, 0, SILL, 1.5, HL - T, RED, "SmoothPlastic")
	local g = kit:gui(lowLeft, "Left", 40)
	kit:label(g, { Text = "SKY LIFT", TextColor = CREAM, Size = { 0.7, 0.55 }, Pos = { 0.15, 0.22 } })

	-- glass all round, in thin dark frames
	local glass = opts({ transparency = 0.72, reflectance = 0.08, shadow = false })
	box(m, "GlassFront", -HW + 0.1, HW - 0.1, SILL, HEAD, -HL + 0.04, -HL + 0.1, GLASS, "Glass", glass)
	box(m, "GlassBack", -HW + 0.1, HW - 0.1, SILL, HEAD, HL - 0.1, HL - 0.04, GLASS, "Glass", glass)
	box(m, "GlassLeft", -HW + 0.04, -HW + 0.1, SILL, HEAD, -HL + 0.1, HL - 0.1, GLASS, "Glass", glass)
	box(m, "GlassRightFore", HW - 0.26, HW - 0.2, SILL, HEAD, -HL + 0.1, -1.6, GLASS, "Glass", glass)
	box(m, "GlassRightAft", HW - 0.26, HW - 0.2, SILL, HEAD, 1.6, HL - 0.1, GLASS, "Glass", glass)
	local P = 0.22 -- frame bar
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local x, z = c[1] * (HW - P / 2), c[2] * (HL - P / 2)
		box(
			m,
			`Post{c[1] > 0 and "R" or "L"}{c[2] > 0 and "Aft" or "Fore"}`,
			x - P / 2,
			x + P / 2,
			0,
			HEAD,
			z - P / 2,
			z + P / 2,
			FRAME,
			"Metal"
		)
	end
	box(m, "DoorPostFore", HW - 0.34, HW - 0.15, 0, HEAD, -1.72, -1.5, FRAME, "Metal")
	box(m, "DoorPostAft", HW - 0.34, HW - 0.15, 0, HEAD, 1.5, 1.72, FRAME, "Metal")
	box(m, "MullionLeft", -HW, -HW + P, SILL, HEAD, -0.11, 0.11, FRAME, "Metal")
	box(m, "SillFront", -HW, HW, SILL - 0.12, SILL + 0.06, -HL, -HL + P, FRAME, "Metal")
	box(m, "SillBack", -HW, HW, SILL - 0.12, SILL + 0.06, HL - P, HL, FRAME, "Metal")
	box(m, "SillLeft", -HW, -HW + P, SILL - 0.12, SILL + 0.06, -HL, HL, FRAME, "Metal")
	box(m, "SillRightFore", HW - 0.34, HW - 0.12, SILL - 0.12, SILL + 0.06, -HL, -1.5, FRAME, "Metal")
	box(m, "SillRightAft", HW - 0.34, HW - 0.12, SILL - 0.12, SILL + 0.06, 1.5, HL, FRAME, "Metal")
	box(m, "HeadFront", -HW, HW, HEAD - 0.06, HEAD + 0.1, -HL, -HL + P, FRAME, "Metal")
	box(m, "HeadBack", -HW, HW, HEAD - 0.06, HEAD + 0.1, HL - P, HL, FRAME, "Metal")
	box(m, "HeadLeft", -HW, -HW + P, HEAD - 0.06, HEAD + 0.1, -HL, HL, FRAME, "Metal")
	box(m, "HeadRight", HW - 0.34, HW, HEAD - 0.06, HEAD + 0.1, -HL, HL, FRAME, "Metal")

	-- roof: the cream band (its underside is the ceiling) and a lower crown
	box(m, "Roof", -HW, HW, HEAD + 0.1, TOP - 0.45, -HL + 0.08, HL - 0.08, CREAM, "SmoothPlastic")
	box(m, "RoofCrown", -HW + 0.45, HW - 0.45, TOP - 0.45, TOP, -HL + 0.6, HL - 0.6, CREAM, "SmoothPlastic")
	local light =
		box(m, "Light", -0.5, 0.5, HEAD + 0.04, HEAD + 0.1, -1.2, 1.2, Common.WARM_LIGHT, "Neon", { shadow = false })
	light:SetAttribute("NightLight", true)
	kit:light(
		light,
		"PointLight",
		{ Range = 9, Brightness = 1.2, Color = Common.WARM_LIGHT, Shadows = false, Enabled = false }
	)

	-- the hanger: roof mount, arm and grip (inside the +-0.6 column), the cable through the grip along Z
	local hang = SkyLift.HANG
	box(m, "HangerMount", -0.6, 0.6, TOP - 0.05, TOP + 0.15, -0.6, 0.6, Common.STEEL_DARK, "Metal")
	box(m, "HangerArm", -0.22, 0.22, TOP + 0.15, hang - 0.45, -0.3, 0.3, Common.STEEL_DARK, "Metal")
	box(m, "Grip", -0.55, 0.55, hang - 0.45, hang + SkyLift.GRIP_ABOVE - 0.05, -0.55, 0.55, Common.STEEL, "Metal")

	-- the sliding doors on the right, closed (each leaf: glass, kick panel, edge stile)
	local doors = kit:folder(m, "Doors")
	for _, d in { { "DoorFore", -1.5, 0, -1.5 }, { "DoorAft", 0, 1.5, 1.5 } } do
		local leaf = kit:model(doors, d[1] :: string)
		local z0, z1 = d[2] :: number, d[3] :: number
		leaf:SetAttribute("SlideZ", d[4])
		box(leaf, "Glass", HW - 0.12, HW - 0.04, SILL, HEAD - 0.1, z0, z1, GLASS, "Glass", glass)
		box(leaf, "Kick", HW - 0.14, HW, 0.05, SILL, z0, z1, RED, "SmoothPlastic")
		local edge = if z0 < 0 then z1 - 0.12 else z0
		box(leaf, "Stile", HW - 0.16, HW, 0.05, HEAD - 0.1, edge, edge + 0.12, FRAME, "Metal")
	end

	-- benches facing each other; the Seat parts are the cushions, their tops at SEAT_LOCAL's y
	local seats = kit:folder(m, "Seats")
	local seatTop = SkyLift.SEAT_HEIGHT
	for _, b in { { "Rear", 1 }, { "Front", -1 } } do
		local sg = b[2] :: number -- +1: the rear bench (z > 0), facing forward
		local zIn, zOut = sg * 2.25, sg * (HL - 0.2)
		local zBack = sg * 3.45
		box(
			m,
			`Bench{b[1]}`,
			-HW + 0.2,
			HW - 0.4,
			0,
			seatTop - 0.32,
			math.min(zIn, zOut),
			math.max(zIn, zOut),
			Common.WOOD_DARK,
			"WoodPlanks"
		)
		box(
			m,
			`Backrest{b[1]}`,
			-HW + 0.2,
			HW - 0.4,
			seatTop - 0.32,
			seatTop + 2.1,
			math.min(zBack, zOut),
			math.max(zBack, zOut),
			Common.RED_DARK,
			"Fabric"
		)
	end
	for k = 1, SkyLift.SEATS do
		local L = SkyLift.SEAT_LOCAL[k]
		local x, y, z, facing = L[1], L[2], L[3], L[4]
		-- the cushion: 2.5 wide, 1.2 deep, 0.32 thick, its top at y; LookVector = the sitter's facing
		local s = kit:at(seats, `Seat{k}`, x, y - 0.16, -z, 2.5, 0.32, 1.2, { 150, 42, 34 }, "Fabric", {
			class = "Seat",
			collide = false,
			query = false,
			touch = false,
			rot = CFrame.Angles(0, facing, 0),
		})
		s.Disabled = true
		s:SetAttribute("Seat", k)
		local eye = roblox.Instance.new("Attachment")
		eye.Name = "EyeSocket"
		eye.CFrame = CFrame.new(0, 0.16 + SkyLift.EYE_ABOVE_SEAT, 0)
		eye.Parent = s
	end

	-- the grab rail under the ceiling, along the cabin
	box(m, "GrabRail", -0.08, 0.08, HEAD - 0.6, HEAD - 0.44, -2.1, 2.1, { 190, 192, 194 }, "Metal")
	box(m, "GrabDropFore", -0.06, 0.06, HEAD - 0.44, HEAD + 0.1, -1.9, -1.78, { 190, 192, 194 }, "Metal")
	box(m, "GrabDropAft", -0.06, 0.06, HEAD - 0.44, HEAD + 0.1, 1.78, 1.9, { 190, 192, 194 }, "Metal")

	-- the cabin's number, front and back
	for _, n in { { "NumberFront", -HL + 0.04, "Front" }, { "NumberBack", HL - 0.04, "Back" } } do
		local z = n[2] :: number
		local plate =
			box(m, n[1] :: string, -0.7, 0.7, HEAD + 0.22, HEAD + 0.82, z - 0.04, z + 0.04, CREAM, "SmoothPlastic")
		local pg = kit:gui(plate, n[3] :: string, 40)
		local t = kit:label(pg, { Text = "1", TextColor = Common.RED_DARK, Font = "GothamBlack" })
		t.Name = "Number"
	end
	return m
end

return Cabin
