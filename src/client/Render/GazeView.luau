--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Render.GazeView
-- A person in town looks up at a squirrel stalking above them (owner playtest 2026-11-19: "awareness ... if i am
-- prowling and stalking from above"): the server's Stealth/OverheadService writes the body attribute Gaze (a Vector3:
-- the point to look at, the squirrel) while the person glances up, stops to look or has spotted it, and nil after; this
-- module turns the R15's Neck toward it, on top of whatever clip plays (the joint's C0 is turned, and put back exactly
-- when the gaze ends). The head turns at most YAW_MAX either way and tilts back at most PITCH_MAX; it eases there
-- (EASE a second) so a glance reads as a glance. Only bodies with a Gaze cost anything: they are updated at most
-- UPDATE_HZ times a second.
-- Interface: start(opts { bodies }) -> stop(); angles(dx, dy, dz) -> (pitch, yaw) (radians, in the torso's frame;
--   pure); YAW_MAX; PITCH_MAX; EASE; UPDATE_HZ
-- No service access at require time (Lune requires this module).

local GazeView = {}

GazeView.YAW_MAX = math.rad(70)
GazeView.PITCH_MAX = math.rad(60)
GazeView.EASE = 8 -- per second (exponential ease toward the target angles)
GazeView.UPDATE_HZ = 20

-- angles(dx, dy, dz): the neck's tilt back (pitch, + is up) and turn (yaw, + is to the body's left) to look along
-- (dx, dy, dz), a direction in the upper torso's own frame (-Z forward), clamped to what a neck does.
function GazeView.angles(dx: number, dy: number, dz: number): (number, number)
	local level = math.sqrt(dx * dx + dz * dz)
	local yaw = math.atan2(-dx, -dz)
	local pitch = math.atan2(dy, math.max(level, 1e-6))
	return math.clamp(pitch, -math.rad(15), GazeView.PITCH_MAX), math.clamp(yaw, -GazeView.YAW_MAX, GazeView.YAW_MAX)
end

type Entry = {
	body: Model,
	neck: Motor6D?,
	base: CFrame?, -- the neck's own C0
	pitch: number,
	yaw: number,
	target: Vector3?,
}

function GazeView.start(opts: { bodies: Instance }): () -> ()
	local RunService = game:GetService("RunService")
	local entries: { [Instance]: Entry } = {}
	local conns: { RBXScriptConnection } = {}
	local watched: { [Instance]: RBXScriptConnection } = {}

	local function neckOf(body: Model): Motor6D?
		local j = body:FindFirstChild("Neck", true)
		return if j and j:IsA("Motor6D") then j else nil
	end

	local function release(child: Instance)
		local e = entries[child]
		if e then
			entries[child] = nil
			if e.neck and e.base then
				e.neck.C0 = e.base
			end
		end
	end

	local function changed(body: Model)
		local g = body:GetAttribute("Gaze")
		local e = entries[body]
		if typeof(g) == "Vector3" then
			if e == nil then
				local neck = neckOf(body)
				if neck == nil then
					return
				end
				e = { body = body, neck = neck, base = neck.C0, pitch = 0, yaw = 0, target = g }
				entries[body] = e
			else
				e.target = g
			end
		elseif e then
			e.target = nil -- (eases back, then lets go)
		end
	end

	local function add(child: Instance)
		if not child:IsA("Model") or watched[child] then
			return
		end
		local body = child :: Model
		watched[child] = body:GetAttributeChangedSignal("Gaze"):Connect(function()
			changed(body)
		end)
		if body:GetAttribute("Gaze") ~= nil then
			changed(body)
		end
	end

	local function remove(child: Instance)
		local c = watched[child]
		if c then
			c:Disconnect()
			watched[child] = nil
		end
		release(child)
	end

	local acc = 0
	table.insert(
		conns,
		RunService.RenderStepped:Connect(function(dt: number)
			acc += dt
			if acc < 1 / GazeView.UPDATE_HZ or next(entries) == nil then
				return
			end
			local step = acc
			acc = 0
			local k = 1 - math.exp(-GazeView.EASE * step)
			for child, e in entries do
				local neck, base = e.neck, e.base
				if neck == nil or base == nil or neck.Parent == nil then
					entries[child] = nil
					continue
				end
				local wantP, wantY = 0, 0
				if e.target then
					local torso = neck.Part0
					local head = neck.Part1
					if torso and head then
						local rel = torso.CFrame:VectorToObjectSpace(e.target - head.Position)
						wantP, wantY = GazeView.angles(rel.X, rel.Y, rel.Z)
					end
				end
				e.pitch += (wantP - e.pitch) * k
				e.yaw += (wantY - e.yaw) * k
				if e.target == nil and math.abs(e.pitch) < 0.01 and math.abs(e.yaw) < 0.01 then
					release(child)
					continue
				end
				neck.C0 = base * CFrame.Angles(0, e.yaw, 0) * CFrame.Angles(e.pitch, 0, 0)
			end
		end)
	)
	table.insert(conns, opts.bodies.ChildAdded:Connect(add))
	table.insert(conns, opts.bodies.ChildRemoved:Connect(remove))
	for _, child in opts.bodies:GetChildren() do
		add(child)
	end
	return function()
		for _, c in conns do
			c:Disconnect()
		end
		for child in table.clone(watched) do
			remove(child)
		end
	end
end

return GazeView
