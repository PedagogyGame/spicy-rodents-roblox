--!strict
-- ServerScriptService.Server.WorldGen.Doors
-- Server-owned doors (BUILD_PLAN §3.4, §4.4 #7): every door leaf the bake makes carries DoorId,
-- ServerOwned, Lockable, Open and Locked attributes; only the server moves it. A leaf swings 1.35 rad
-- about its hinge edge (v5.4 buildHouse door: opens sign * open * 1.35 rad), so the closed pose is
-- recoverable from the open one and no extra state is stored.
-- Interface: pose(closed, size, open, sign, CFrameT) -> CFrame; setOpen(leaf, open, CFrameT?) -> boolean;
--   setLocked(leaf, locked) ; collect(root) -> { [doorId]: BasePart }
-- The prompts are placeholders until the W2 door service wires them (Enabled = false).

local Doors = {}

Doors.SWING = 1.35

-- Pose of a leaf whose closed CFrame is `closed`: hinge on its local -X edge, swing about +Y.
function Doors.pose(closed: any, size: any, open: boolean, sign: number, C: any): any
	if not open then
		return closed
	end
	local hinge = closed * C.new(-size.X / 2, 0, 0)
	return hinge * C.Angles(0, sign * Doors.SWING, 0) * C.new(size.X / 2, 0, 0)
end

-- Server-side open/close. Returns false (and does nothing) when the door is locked or unchanged.
function Doors.setOpen(leaf: any, open: boolean, C: any?): boolean
	local CF = C or CFrame
	if leaf:GetAttribute("ServerOwned") ~= true then
		error("Doors.setOpen: " .. leaf:GetFullName() .. " is not a server-owned door")
	end
	local was = leaf:GetAttribute("Open") == true
	if was == open or (open and leaf:GetAttribute("Locked") == true) then
		return false
	end
	local sign = leaf:GetAttribute("SwingSign") or 1
	local closed = leaf.CFrame
	if was then
		-- open = closed * T(-w/2) * Ry(s*swing) * T(w/2), so closed = open * T(-w/2) * Ry(-s*swing) * T(w/2)
		closed = leaf.CFrame * CF.new(-leaf.Size.X / 2, 0, 0) * CF.Angles(0, -sign * Doors.SWING, 0) * CF.new(leaf.Size.X / 2, 0, 0)
	end
	leaf.CFrame = Doors.pose(closed, leaf.Size, open, sign, CF)
	leaf.CanCollide = not open
	leaf:SetAttribute("Open", open)
	return true
end

function Doors.setLocked(leaf: any, locked: boolean)
	if leaf:GetAttribute("Lockable") ~= true and locked then
		error("Doors.setLocked: " .. leaf.Name .. " is not lockable")
	end
	leaf:SetAttribute("Locked", locked)
end

function Doors.collect(root: any): { [string]: any }
	local out: { [string]: any } = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("ServerOwned") == true then
			local id = d:GetAttribute("DoorId")
			local lot = d:FindFirstAncestorOfClass("Model")
			out[(if lot then lot.Name .. ":" else "") .. tostring(id)] = d
		end
	end
	return out
end

return Doors
