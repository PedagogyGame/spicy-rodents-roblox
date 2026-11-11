--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Render.DoorView
-- The doors of the buildings a body can walk into (owner 2026-11-11: "rooms cannot be entered yet"). The
-- bake leaves every such doorway open in the wall and gives it a leaf that never collides (attribute
-- Auto = true; WorldGen/Builders/Shell), so getting in needs nothing from here: this only shows the
-- leaf opening as a body comes up to it and closing when the last one has gone, on this client, for the
-- lots streamed in round its camera. Nothing is sent and the server moves nothing, so a door can never
-- hold anyone up, lag behind a walker or disagree with the collision.
--   * Bodies are the models of Workspace.Bodies (people, squirrels, the fox, deer, the rodent; held or
--     AI): their root positions are read a few times a second.
--   * A door opens for a body within DoorMotion.OPEN of its doorway and on its level (a squirrel on the
--     roof above does not open the front door), and closes past DoorMotion.CLOSE.
--   * A swing leaf turns away from the body that opened it; a slide leaf runs into the wall (the wide
--     doors of the hospital and the station). Knobs, panels and panes (attribute DoorOf = the leaf's
--     DoorId) ride on the leaf by the same rigid motion.
--   * A leaf whose Locked attribute is true stays shut (nothing locks one yet).
-- Lots stream in and out (their models are Atomic): a lot Model with AutoDoors > 0 is scanned when it
-- arrives, each leaf's baked pose remembered as its closed pose, and forgotten when the lot leaves.
-- Started by Render/TownView.start. No service access at require time (Lune tests require this).
-- Interface: gather(model) -> { Entry }; nearest(entry, bodies) -> (dist, sign); step(entries, bodies,
--   dt, C) -> moved; apply(entry, C); start() -> stop(); PERIOD

local Import = require("../Import")
local DoorMotion = Import.shared("World/DoorMotion") :: typeof(require("../../shared/World/DoorMotion"))

local DoorView = {}

DoorView.PERIOD = 0.1 -- seconds between looks at where the bodies are

export type Body = { x: number, y: number, z: number }
export type Entry = {
	leaf: any,
	closed: any, -- the baked CFrame
	size: any,
	motion: string, -- "swing" | "slide"
	slideSign: number,
	run: number,
	followers: { { part: any, rel: any } }, -- rel: the follower in the leaf's frame
	x: number, -- the doorway: its centre, the direction along it, the leaf's local +Z, half its width
	z: number,
	sill: number,
	tx: number,
	tz: number,
	nx: number,
	nz: number,
	half: number,
	alpha: number, -- 0 closed .. 1 open
	sign: number, -- which way it is opening
	open: boolean,
}

-- The auto doors of one lot Model, each with the parts that ride on it.
function DoorView.gather(model: any): { Entry }
	local out: { Entry } = {}
	local children = model:GetChildren()
	for _, d in children do
		if d:IsA("BasePart") and d:GetAttribute("Auto") == true then
			local closed = d.CFrame
			local id = d:GetAttribute("DoorId")
			local followers = {}
			for _, f in children do
				if f ~= d and f:IsA("BasePart") and id ~= nil and f:GetAttribute("DoorOf") == id then
					table.insert(followers, { part = f, rel = closed:ToObjectSpace(f.CFrame) })
				end
			end
			local right, look = closed.RightVector, closed.LookVector
			local pos = closed.Position
			local slideSign = d:GetAttribute("SlideSign")
			local run = d:GetAttribute("SlideRun")
			table.insert(out, {
				leaf = d,
				closed = closed,
				size = d.Size,
				motion = if d:GetAttribute("Motion") == "slide" then "slide" else "swing",
				slideSign = if type(slideSign) == "number" and slideSign < 0 then -1 else 1,
				run = if type(run) == "number" then run else 0,
				followers = followers,
				x = pos.X,
				z = pos.Z,
				sill = pos.Y - d.Size.Y / 2,
				tx = right.X,
				tz = right.Z,
				nx = -look.X,
				nz = -look.Z,
				half = d.Size.X / 2,
				alpha = 0,
				sign = 1,
				open = false,
			})
		end
	end
	return out
end

-- The nearest body on the door's level: its distance from the doorway, and the way a swing leaf
-- turns to go away from it. math.huge when nobody is about.
function DoorView.nearest(e: Entry, bodies: { Body }): (number, number)
	local best, sign = math.huge, 1
	for _, b in bodies do
		local up = b.y - e.sill
		if up > -4 and up < DoorMotion.TALL then
			local dx, dz = b.x - e.x, b.z - e.z
			-- (a cheap reject first: most bodies are streets away)
			if math.abs(dx) < 40 and math.abs(dz) < 40 then
				local dist = DoorMotion.reach(dx, dz, e.tx, e.tz, e.half)
				if dist < best then
					best, sign = dist, DoorMotion.side(dx, dz, e.nx, e.nz)
				end
			end
		end
	end
	return best, sign
end

-- Puts the leaf and what rides on it where `e.alpha` says (eased at both ends).
function DoorView.apply(e: Entry, C: any)
	local a = e.alpha
	local to = DoorMotion.pose(e.closed, e.size, e.motion, e.sign, e.run, a * a * (3 - 2 * a), C)
	e.leaf.CFrame = to
	for _, f in e.followers do
		f.part.CFrame = to * f.rel
	end
end

-- One frame for a set of doors. `bodies` is where everybody is now, or nil between looks (the doors
-- then only go on moving toward what they last wanted). Returns how many leaves moved.
function DoorView.step(entries: { Entry }, bodies: { Body }?, dt: number, C: any): number
	local moved = 0
	for _, e in entries do
		if bodies then
			local dist, sign = DoorView.nearest(e, bodies)
			local want = DoorMotion.wants(e.open, dist) and e.leaf:GetAttribute("Locked") ~= true
			if want and e.alpha <= 0 then
				-- a shut door picks its way as it starts to open (never half way through a swing)
				e.sign = if e.motion == "slide" then e.slideSign else sign
			end
			e.open = want
		end
		local target = if e.open then 1 else 0
		if e.alpha ~= target then
			e.alpha = DoorMotion.ease(e.alpha, target, dt)
			DoorView.apply(e, C)
			moved += 1
		end
	end
	return moved
end

function DoorView.start(): () -> ()
	local RunService = game:GetService("RunService")
	local alive = true
	local conns: { RBXScriptConnection } = {}
	local lots: { [Instance]: { Entry } } = {}
	local function scan(model: Instance)
		if not model:IsA("Model") then
			return
		end
		local n = model:GetAttribute("AutoDoors")
		if type(n) ~= "number" or n <= 0 then
			return
		end
		lots[model] = DoorView.gather(model)
	end
	task.spawn(function()
		local town = workspace:WaitForChild("Town", 120)
		local folder = town and town:WaitForChild("Lots", 60)
		if not alive or folder == nil then
			return -- no town: no doors to show (they are open to walk through all the same)
		end
		for _, m in folder:GetChildren() do
			scan(m)
		end
		table.insert(
			conns,
			folder.ChildAdded:Connect(function(m: Instance)
				-- an Atomic model arrives whole; one frame's grace for its descendants all the same
				task.defer(function()
					if alive and m.Parent == folder then
						scan(m)
					end
				end)
			end)
		)
		table.insert(
			conns,
			folder.ChildRemoved:Connect(function(m: Instance)
				lots[m] = nil
			end)
		)
		local acc = DoorView.PERIOD
		local seen: { Body } = {}
		table.insert(
			conns,
			RunService.Heartbeat:Connect(function(dt: number)
				acc += dt
				local bodies: { Body }? = nil
				if acc >= DoorView.PERIOD then
					acc = 0
					table.clear(seen)
					local folderB = workspace:FindFirstChild("Bodies")
					if folderB then
						for _, m in folderB:GetChildren() do
							local root = if m:IsA("Model") then m.PrimaryPart else nil
							if root then
								local p = root.Position
								table.insert(seen, { x = p.X, y = p.Y, z = p.Z })
							end
						end
					end
					bodies = seen
				end
				for _, entries in lots do
					DoorView.step(entries, bodies, dt, CFrame)
				end
			end)
		)
	end)
	return function()
		alive = false
		for _, c in conns do
			c:Disconnect()
		end
		-- every door back as it was baked
		for _, entries in lots do
			for _, e in entries do
				if e.leaf.Parent and e.alpha ~= 0 then
					e.alpha, e.open = 0, false
					DoorView.apply(e, CFrame)
				end
			end
		end
		table.clear(lots)
	end
end

return DoorView
