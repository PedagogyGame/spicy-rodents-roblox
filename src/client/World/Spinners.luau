--!strict
-- StarterPlayer.StarterPlayerScripts.Client.World.Spinners
-- Turns the baked things that spin, on this computer only (nothing is sent to the server): every Model in the
-- Workspace with the attribute SpinRpm (revolutions a minute) turns about the world's up axis through its pivot
-- (its PrimaryPart). The bowling alley's rooftop vent's exhaust fan is one (tools/bake/alley/RoofVent: RoofVent.Fan).
-- Models streamed in later are picked up as they arrive; one that leaves the Workspace is dropped.
-- Interface: angleAt(rpm, seconds) -> radians (pure); start() -> nothing (idempotent)

local Spinners = {}

-- The angle a spinner has turned after `seconds` at `rpm`, kept in [0, 2 pi).
function Spinners.angleAt(rpm: number, seconds: number): number
	local a = rpm / 60 * 2 * math.pi * seconds
	return a % (2 * math.pi)
end

type Spinner = { model: Model, home: CFrame, rpm: number }

local started = false

function Spinners.start()
	if started then
		return
	end
	started = true
	local RunService = game:GetService("RunService")
	local list: { Spinner } = {}
	local function add(inst: Instance)
		if not inst:IsA("Model") then
			return
		end
		local rpm = inst:GetAttribute("SpinRpm")
		if type(rpm) ~= "number" or rpm == 0 or inst.PrimaryPart == nil then
			return
		end
		table.insert(list, { model = inst, home = inst:GetPivot(), rpm = rpm })
	end
	for _, d in workspace:GetDescendants() do
		add(d)
	end
	workspace.DescendantAdded:Connect(add)
	local t0 = os.clock()
	RunService.RenderStepped:Connect(function()
		local now = os.clock() - t0
		for i = #list, 1, -1 do
			local s = list[i]
			if s.model.Parent == nil then
				table.remove(list, i)
			else
				local a = Spinners.angleAt(s.rpm, now)
				s.model:PivotTo(CFrame.new(s.home.Position) * CFrame.Angles(0, a, 0) * s.home.Rotation)
			end
		end
	end)
end

return Spinners
