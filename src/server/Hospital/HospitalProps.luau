--!strict
-- ServerScriptService.Server.Hospital.HospitalProps
-- The cots in the hospital's two wards (owner 2026-11-10: a patient is admitted, treated and released):
-- one at each bed of Infection/HospitalLayout, built from a few anchored parts at boot. A patient is
-- posed sitting up on the mattress (Client/Animation/AnimationDriver lowers a "treated" body by the
-- sit height less HospitalLayout.BED.top), so the cots are decoration only: they do not collide, are
-- not hit by raycasts (the client's ground probe would otherwise lift a patient onto the mattress a
-- second time) and fire no touches. Placeholder art until the hospital's interior pass.
-- Engine only inside the function. No side effects on require.
-- Interface: build(layout, parent?) -> Folder (Workspace.HospitalProps); spec(layout) -> { Cot }
--   (pure: where each part goes, for the Lune test)

local Import = require("../Import")
local HospitalLayout =
	Import.shared("Infection/HospitalLayout") :: typeof(require("../../shared/Infection/HospitalLayout"))
local Height = Import.shared("World/Height") :: typeof(require("../../shared/World/Height"))

export type PartSpec = {
	name: string,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	color: { number },
}
export type Cot = { index: number, yaw: number, parts: { PartSpec } }

local HospitalProps = {}

local FLOOR_TOP = 0.42 * 2.5 -- the hospital's floor above its seat (WorldGen/Builders/Programme)
local FRAME = { 201, 208, 204 } -- v5.4 stretcher frame #c9d0cc
local MATTRESS = { 230, 229, 219 } -- the hospital's white #e6e5db
local PILLOW = { 98, 142, 157 } -- the hospital's blue #628e9d

-- spec(layout): the parts of every cot in world studs. A cot lies along the hospital's depth (its
-- head toward the back wall); `yaw` is the rotation about +Y that turns the parts' Z onto that axis.
function HospitalProps.spec(layout: any): { Cot }
	local bed = HospitalLayout.BED
	local floorY = Height.at(layout.lot.x, layout.lot.z) + FLOOR_TOP
	-- the front direction in world space (HTML yaw 0 faces +Z)
	local fx, fz = math.sin(layout.yaw), math.cos(layout.yaw)
	local out: { Cot } = {}
	for _, b in layout.beds do
		local parts: { PartSpec } = {}
		local function part(
			name: string,
			along: number,
			y: number,
			sx: number,
			sy: number,
			sz: number,
			color: { number }
		)
			table.insert(parts, {
				name = name,
				x = b.x + fx * along,
				y = floorY + y,
				z = b.z + fz * along,
				sx = sx,
				sy = sy,
				sz = sz,
				color = color,
			})
		end
		part("Frame", 0, bed.top - 0.75, bed.width, 0.5, bed.length, FRAME)
		part("Mattress", 0, bed.top - 0.25, bed.width - 0.3, 0.5, bed.length - 0.3, MATTRESS)
		part("Pillow", -(bed.length / 2 - 0.9), bed.top + 0.2, bed.width - 0.9, 0.4, 1.4, PILLOW)
		for _, side in { -1, 1 } do
			part("Leg", side * (bed.length / 2 - 0.4), (bed.top - 1) / 2, bed.width - 0.4, bed.top - 1, 0.3, FRAME)
		end
		table.insert(out, { index = b.index, yaw = math.atan2(fx, fz), parts = parts })
	end
	return out
end

-- build(layout, parent?): the cots as parts under Workspace.HospitalProps (rebuilt if it exists).
function HospitalProps.build(layout: any, parent: Instance?): Folder
	local home = parent or workspace
	local old = home:FindFirstChild("HospitalProps")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "HospitalProps"
	for _, cot in HospitalProps.spec(layout) do
		local model = Instance.new("Model")
		model.Name = `Cot{cot.index}`
		for _, p in cot.parts do
			local part = Instance.new("Part")
			part.Name = p.name
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Material = Enum.Material.SmoothPlastic
			part.Color = Color3.fromRGB(p.color[1], p.color[2], p.color[3])
			part.Size = Vector3.new(p.sx, p.sy, p.sz)
			part.CFrame = CFrame.new(p.x, p.y, p.z) * CFrame.Angles(0, cot.yaw, 0)
			part.Parent = model
		end
		model.Parent = folder
	end
	folder.Parent = home
	return folder
end

return HospitalProps
