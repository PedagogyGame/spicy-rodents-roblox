--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Render.Beacons
-- The flashing light bar of an ambulance out with a doctor (owner D30: the doctors drive the ambulances "with the
-- siren/lights"). Server/Actors/DeviceService marks such a vehicle with the model attribute Siren; its drawing
-- (Shared/Traffic/VehiclePuppet) has a two-half bar, LightBar (red) and LightBarB (white), in Neon. Here the halves
-- take turns, PERIOD seconds each, on every client. Cost: at most three models (the three ambulances), two parts each,
-- looked at ten times a second; nothing else is touched.
-- (No siren sound yet: the game has none in its audio, and an upload is the lead's.)
-- Pure part (Lune-tested): PERIOD, lit(t, half) -> boolean ("A" | "B": is that half lit at time t?).
-- Engine part: start() (one loop; never on require).

local Beacons = {}

Beacons.PERIOD = 0.35 -- s each half is lit

function Beacons.lit(t: number, half: string): boolean
	local first = math.floor(t / Beacons.PERIOD) % 2 == 0
	return if half == "A" then first else not first
end

function Beacons.start()
	local RunService = game:GetService("RunService")
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		local folder = workspace:FindFirstChild("Vehicles")
		if folder == nil then
			return
		end
		local t = os.clock()
		for _, model in folder:GetChildren() do
			if model:GetAttribute("Siren") == true then
				local a = model:FindFirstChild("LightBar", true)
				local b = model:FindFirstChild("LightBarB", true)
				if a and a:IsA("BasePart") then
					a.Transparency = if Beacons.lit(t, "A") then 0 else 0.7
				end
				if b and b:IsA("BasePart") then
					b.Transparency = if Beacons.lit(t, "B") then 0 else 0.7
				end
			end
		end
	end)
end

return Beacons
