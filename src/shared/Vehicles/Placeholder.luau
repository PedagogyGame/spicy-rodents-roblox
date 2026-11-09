--!strict
-- ReplicatedStorage.Shared.Vehicles.Placeholder
-- Greybox vehicle models at the true logical boxes, with a placeholder interior (BUILD_PLAN §4.4 #5,
-- §5.2; RigSpec.car names): RootPart (the logical box, invisible, the PrimaryPart), Body, wheels,
-- a DriverSeat (Seat), a Dash part with a DashSocket attachment and an EyeSocket attachment where the
-- first-person camera sits (brief v2 §14). Open kinds (cart, bike, jet ski) get no roof. Engine
-- only (Instances); the numbers come from Vehicles/VehicleKinds. Tools/placeholders (Track B) may
-- supply richer models under ReplicatedStorage.Assets.Vehicles.<kind> with the same names; `build`
-- prefers those.
-- Interface: build(kindId, name?) -> Model; eyeSocket(model) -> Attachment?
-- No side effects on require.

local VehicleKinds = require("./VehicleKinds")

local Placeholder = {}

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	transparency: number?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Transparency = transparency or 0
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

-- body-local (x, y, z) in the HTML convention (+Z forward) to a Roblox offset (front is -Z)
local function v(t: { number }): Vector3
	return Vector3.new(-t[1], t[2], -t[3])
end

function Placeholder.build(kindId: string, name: string?): Model
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Vehicles")
	local template = folder and folder:FindFirstChild(kindId)
	if template and template:IsA("Model") and template.PrimaryPart then
		local m = template:Clone()
		m.Name = name or kindId
		m:SetAttribute("VehicleKind", kindId)
		return m
	end

	local k = VehicleKinds.kind(kindId)
	local w, h, l = k.size[1], k.size[2], k.size[3]
	local color = Color3.new(k.color[1], k.color[2], k.color[3])
	local model = Instance.new("Model")
	model.Name = name or kindId
	model:SetAttribute("VehicleKind", kindId)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local origin = CFrame.new()

	local root = part(model, "RootPart", Vector3.new(w, h, l), origin, color, 1)
	root.CanCollide = true
	root.CanQuery = true
	root.Massless = false
	model.PrimaryPart = root

	local wheelR = if k.wheels > 0 then math.min(h * 0.22, 1.6) else 0
	local bodyH = if k.interior.open then h * 0.45 else h - wheelR
	local body =
		part(model, "Body", Vector3.new(w, bodyH, l), origin * CFrame.new(0, -h / 2 + wheelR + bodyH / 2, 0), color)
	weld(root, body)
	if not k.interior.open then
		-- cabin glass band so the interior reads from outside
		local glass = part(
			model,
			"Glass",
			Vector3.new(w * 0.96, h * 0.3, l * 0.5),
			origin * CFrame.new(0, h * 0.28, 0),
			Color3.new(0.6, 0.75, 0.85),
			0.55
		)
		weld(root, glass)
	end
	if k.wheels == 4 then
		for _, spec in { { "WheelFL", -1, -1 }, { "WheelFR", 1, -1 }, { "WheelBL", -1, 1 }, { "WheelBR", 1, 1 } } do
			local wheel = part(
				model,
				spec[1] :: string,
				Vector3.new(wheelR * 0.8, wheelR * 2, wheelR * 2),
				origin
					* CFrame.new(
						(spec[2] :: number) * (w / 2 - wheelR * 0.3),
						-h / 2 + wheelR,
						(spec[3] :: number) * l * 0.32
					),
				Color3.new(0.08, 0.08, 0.08)
			)
			wheel.Shape = Enum.PartType.Cylinder
			weld(root, wheel)
		end
	elseif k.wheels == 2 then
		for _, spec in { { "WheelF", -1 }, { "WheelB", 1 } } do
			local wheel = part(
				model,
				spec[1] :: string,
				Vector3.new(wheelR * 0.4, wheelR * 2, wheelR * 2),
				origin * CFrame.new(0, -h / 2 + wheelR, (spec[2] :: number) * l * 0.38),
				Color3.new(0.08, 0.08, 0.08)
			)
			wheel.Shape = Enum.PartType.Cylinder
			weld(root, wheel)
		end
	end

	-- interior: seat, dash, sockets
	local int = k.interior
	local seat = Instance.new("Seat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(math.min(2, w * 0.4), 0.4, math.min(2, l * 0.25))
	seat.CFrame = origin * CFrame.new(v(int.seat))
	seat.Color = Color3.new(0.15, 0.15, 0.15)
	seat.CanCollide = false
	seat.Massless = true
	seat.Parent = model
	weld(root, seat)
	local dash = part(
		model,
		"Dash",
		Vector3.new(int.dashSize[1], int.dashSize[2], int.dashSize[3]),
		origin * CFrame.new(v(int.dash)),
		Color3.new(0.12, 0.12, 0.14)
	)
	weld(root, dash)
	local dashSocket = Instance.new("Attachment")
	dashSocket.Name = "DashSocket"
	dashSocket.Parent = dash
	local eye = Instance.new("Attachment")
	eye.Name = "EyeSocket"
	eye.Position = v(int.eye)
	eye.Parent = root
	local seatSocket = Instance.new("Attachment")
	seatSocket.Name = "DriverSeat"
	seatSocket.Position = v(int.seat)
	seatSocket.Parent = root
	if kindId == "car" then
		local bar = part(
			model,
			"LightBar",
			Vector3.new(w * 0.6, 0.3, 0.6),
			origin * CFrame.new(0, h / 2 + 0.15, 0),
			Color3.new(0.2, 0.2, 0.9)
		)
		weld(root, bar)
	end
	return model
end

function Placeholder.eyeSocket(model: Model): Attachment?
	local found = model:FindFirstChild("EyeSocket", true)
	return if found and found:IsA("Attachment") then found else nil
end

return Placeholder
