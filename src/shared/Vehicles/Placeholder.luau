--!strict
-- ReplicatedStorage.Shared.Vehicles.Placeholder
-- The player's vehicles at the true logical boxes, with a placeholder interior (BUILD_PLAN §4.4 #5,
-- §5.2; RigSpec.car names): RootPart (the logical box, invisible, the PrimaryPart and the collider), the
-- drawn vehicle, a DriverSeat (Seat), a Dash part with a DashSocket attachment and an EyeSocket attachment
-- where the first-person camera sits (brief v2 §14). The numbers come from Vehicles/VehicleKinds.
-- The drawn vehicle is shaped in the traffic cars' style (owner playtest 2026-11-19: "bikes and things that
-- were basic colors"): the patrol car and the golf cart as the traffic draws them (Traffic/VehiclePuppet),
-- the pickup, SUV and jet ski from VehiclePuppet's player kinds, the bike from Vehicles/RidePuppet, each
-- fitted inside the VehicleKinds box (`look`); the seat and, on the open kinds, the dash are not drawn
-- (the saddle, the bench, the seat are). A kind with no look keeps the old greybox body. Engine only
-- (Instances) in `build`; `look` is pure. Tools/placeholders (Track B) may supply richer models under
-- ReplicatedStorage.Assets.Vehicles.<kind> with the same names; `build` prefers those.
-- Interface: build(kindId, name?) -> Model; look(kindId, name?) -> PartBuilder.ModelSpec?; eyeSocket(model) -> Attachment?
-- No side effects on require.

local PartBuilder = require("../Avatar/PartBuilder")
local RidePuppet = require("./RidePuppet")
local VehiclePuppet = require("../Traffic/VehiclePuppet")
local VehicleKinds = require("./VehicleKinds")

local Placeholder = {}

type Wheel = { name: string, sx: number, sz: number }
local WHEELS4: { Wheel } = {
	{ name = "WheelFL", sx = -1, sz = -1 },
	{ name = "WheelFR", sx = 1, sz = -1 },
	{ name = "WheelBL", sx = -1, sz = 1 },
	{ name = "WheelBR", sx = 1, sz = 1 },
}
local WHEELS2: { Wheel } = { { name = "WheelF", sx = 0, sz = -1 }, { name = "WheelB", sx = 0, sz = 1 } }

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

-- The traffic kind (or VehiclePuppet player kind) that draws each player kind.
local DRAWN: { [string]: string } =
	{ car = "patrol_car", cart = "cart", pickup = "pickup", suv = "suv", jetski = "jetski" }
Placeholder.BIKE_SCALE = 0.88 -- the adult bicycle (5 studs long) shrunk into the bike's 4.5-stud box

local function toHex(c: { number }): string
	return string.format(
		"#%02x%02x%02x",
		math.floor(c[1] * 255 + 0.5),
		math.floor(c[2] * 255 + 0.5),
		math.floor(c[3] * 255 + 0.5)
	)
end

-- look(kindId, name?): the shaped vehicle for a player kind, its RootPart the VehicleKinds box, or nil (greybox).
function Placeholder.look(kindId: string, name: string?): PartBuilder.ModelSpec?
	local k = VehicleKinds.kind(kindId)
	local box = { k.size[1], k.size[2], k.size[3] }
	if kindId == "bike" then
		return RidePuppet.bicycle({ scale = Placeholder.BIKE_SCALE, frame = toHex(k.color), size = box, name = name })
	end
	local drawn = DRAWN[kindId]
	if drawn == nil then
		return nil
	end
	-- the patrol car keeps the traffic's white and its bar; the rest wear their VehicleKinds colour
	local color = if kindId == "car" then nil else toHex(k.color)
	return VehiclePuppet.spec(drawn, { color = color, name = name, box = box })
end

-- The drawn vehicle as a Model whose RootPart is the solid, queryable collider every vehicle had (the rest welded to
-- it, massless, colliding with nothing).
local function shaped(spec: PartBuilder.ModelSpec): Model
	local model = PartBuilder.instantiate(spec, PartBuilder.engineLib()) :: Model
	model:SetAttribute("Placeholder", nil)
	model:SetAttribute("Species", nil)
	for _, key in { "BaseOffset", "BoxW", "BoxL", "BoxH", "RideKind" } do
		model:SetAttribute(key, nil)
	end
	local root = model.PrimaryPart :: BasePart
	root.CanCollide = true
	root.CanQuery = true
	root.Massless = false
	root.Anchored = false
	return model
end

-- The old greybox body (a kind with no look): a body block, cabin glass on a closed kind, the wheels.
local function greybox(model: Model, root: BasePart, k: VehicleKinds.Kind, color: Color3)
	local w, h, l = k.size[1], k.size[2], k.size[3]
	local origin = CFrame.new()
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
		for _, spec in WHEELS4 do
			local wheel = part(
				model,
				spec.name,
				Vector3.new(wheelR * 0.8, wheelR * 2, wheelR * 2),
				origin * CFrame.new(spec.sx * (w / 2 - wheelR * 0.3), -h / 2 + wheelR, spec.sz * l * 0.32),
				Color3.new(0.08, 0.08, 0.08)
			)
			wheel.Shape = Enum.PartType.Cylinder
			weld(root, wheel)
		end
	elseif k.wheels == 2 then
		for _, spec in WHEELS2 do
			local wheel = part(
				model,
				spec.name,
				Vector3.new(wheelR * 0.4, wheelR * 2, wheelR * 2),
				origin * CFrame.new(0, -h / 2 + wheelR, spec.sz * l * 0.38),
				Color3.new(0.08, 0.08, 0.08)
			)
			wheel.Shape = Enum.PartType.Cylinder
			weld(root, wheel)
		end
	end
end

-- The interior every kind has: the seat, the dash and its socket, the eye and seat sockets, and (greybox car) the bar.
-- On a drawn vehicle the seat is not drawn, nor the dash of an open kind: the drawn saddle, bench or seat shows.
local function interior(model: Model, root: BasePart, k: VehicleKinds.Kind, kindId: string, drawn: boolean)
	local w, h, l = k.size[1], k.size[2], k.size[3]
	local origin = CFrame.new()
	local int = k.interior
	local seat = Instance.new("Seat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(math.min(2, w * 0.4), 0.4, math.min(2, l * 0.25))
	seat.CFrame = origin * CFrame.new(v(int.seat))
	seat.Color = Color3.new(0.15, 0.15, 0.15)
	seat.CanCollide = false
	seat.Massless = true
	seat.Transparency = if drawn then 1 else 0
	seat.Parent = model
	weld(root, seat)
	local dash = part(
		model,
		"Dash",
		Vector3.new(int.dashSize[1], int.dashSize[2], int.dashSize[3]),
		origin * CFrame.new(v(int.dash)),
		Color3.new(0.12, 0.12, 0.14)
	)
	dash.Transparency = if drawn and k.interior.open then 1 else 0
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
	if kindId == "car" and not drawn then
		-- the patrol car's beacon bar (a drawn patrol car has its own): bright red and blue Neon halves (review 2026-11-09)
		for _, half in
			{
				{ name = "LightBar", x = -1, color = Color3.fromRGB(255, 42, 42) },
				{ name = "LightBarB", x = 1, color = Color3.fromRGB(47, 107, 255) },
			}
		do
			local bar = part(
				model,
				half.name,
				Vector3.new(w * 0.3, 0.3, 0.6),
				origin * CFrame.new(half.x * w * 0.15, h / 2 + 0.15, 0),
				half.color
			)
			bar.Material = Enum.Material.Neon
			weld(root, bar)
		end
	end
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
	local spec = Placeholder.look(kindId, name or kindId)
	local model: Model
	if spec then
		model = shaped(spec)
	else
		model = Instance.new("Model")
		local root = part(model, "RootPart", Vector3.new(w, h, l), CFrame.new(), color, 1)
		root.CanCollide = true
		root.CanQuery = true
		root.Massless = false
		model.PrimaryPart = root
	end
	model.Name = name or kindId
	model:SetAttribute("VehicleKind", kindId)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local root = model.PrimaryPart :: BasePart
	if spec == nil then
		greybox(model, root, k, color)
	end
	interior(model, root, k, kindId, spec ~= nil)
	return model
end

function Placeholder.eyeSocket(model: Model): Attachment?
	local found = model:FindFirstChild("EyeSocket", true)
	return if found and found:IsA("Attachment") then found else nil
end

return Placeholder
