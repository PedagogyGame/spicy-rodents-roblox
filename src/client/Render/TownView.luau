--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Render.TownView
-- Client-side town dressing (FRB look pass; BUILD_PLAN §3.19, brief v2 §15 street lighting):
--   * Street lamps: a pool of MAX_LIGHTS warm PointLights (data/authored/town/lighting.json warmth,
--     no shadows) moved every half second onto the lamp heads nearest the camera within RADIUS; the
--     heads with Flicker = true flicker gently. Heads are Workspace.Town.Skyline "Head_*" parts.
--   * Skyline massing: each building's far-view box (baked transparent) is shown only while that
--     lot's own model is streamed out, so near the player the real roofs, windows and colours show.
-- Started by Render/VehicleView.start (Main's single client script stays the only script).
-- Interface: start() -> stop(); nearest(points, x, z, max, radius) -> { index } (pure)

local TownView = {}

TownView.MAX_LIGHTS = 40
TownView.RADIUS = 260 -- studs
TownView.PERIOD = 0.5 -- seconds between re-assignments
TownView.WARMTH = { 0.95, 0.75, 0.45 } -- lighting.json lamps.warmth
TownView.RANGE = 26 -- studs
TownView.BRIGHTNESS = 1.6

-- Indices of the `max` points nearest (x, z) within `radius`, nearest first. Pure.
function TownView.nearest(points: { { number } }, x: number, z: number, max: number, radius: number): { number }
	local r2 = radius * radius
	local cand: { { number } } = {}
	for i, p in points do
		local dx, dz = p[1] - x, p[2] - z
		local d2 = dx * dx + dz * dz
		if d2 <= r2 then
			table.insert(cand, { d2, i })
		end
	end
	table.sort(cand, function(a, b)
		if a[1] == b[1] then
			return a[2] < b[2]
		end
		return a[1] < b[1]
	end)
	local out = {}
	for k = 1, math.min(max, #cand) do
		table.insert(out, cand[k][2])
	end
	return out
end

function TownView.start(): () -> ()
	local RunService = game:GetService("RunService")
	local alive = true
	local conns: { RBXScriptConnection } = {}
	local lights: { PointLight } = {}
	task.spawn(function()
		local town = workspace:WaitForChild("Town", 120)
		local skyline = town and town:WaitForChild("Skyline", 60)
		if not alive or town == nil or skyline == nil then
			warn("TownView: no Workspace.Town.Skyline; street lamps stay unlit")
			return
		end
		local heads: { BasePart } = {}
		local points: { { number } } = {}
		local massing: { [string]: BasePart } = {}
		for _, d in skyline:GetChildren() do
			if d:IsA("BasePart") then
				if string.sub(d.Name, 1, 5) == "Head_" then
					table.insert(heads, d)
					table.insert(points, { d.Position.X, d.Position.Z })
				else
					local lot = d:GetAttribute("Lot")
					if type(lot) == "string" then
						massing[lot] = d
					end
				end
			end
		end
		-- Skyline massing only where the lot itself is not streamed in
		local lots = town:FindFirstChild("Lots")
		local function refresh(lotId: string)
			local box = massing[lotId]
			if box then
				box.Transparency = if lots and lots:FindFirstChild(lotId) then 1 else 0
			end
		end
		for id in massing do
			refresh(id)
		end
		if lots then
			table.insert(
				conns,
				lots.ChildAdded:Connect(function(c: Instance)
					refresh(c.Name)
				end)
			)
			table.insert(
				conns,
				lots.ChildRemoved:Connect(function(c: Instance)
					refresh(c.Name)
				end)
			)
		end
		-- the light pool
		local w = TownView.WARMTH
		for i = 1, TownView.MAX_LIGHTS do
			local l = Instance.new("PointLight")
			l.Name = "StreetLight"
			l.Color = Color3.new(w[1], w[2], w[3])
			l.Range = TownView.RANGE
			l.Brightness = TownView.BRIGHTNESS
			l.Shadows = false
			l.Enabled = false
			lights[i] = l
		end
		local flickering: { [PointLight]: number } = {}
		local acc = TownView.PERIOD
		local t = 0
		table.insert(
			conns,
			RunService.Heartbeat:Connect(function(dt: number)
				t += dt
				acc += dt
				if acc >= TownView.PERIOD then
					acc = 0
					local cam = workspace.CurrentCamera
					if cam then
						local p = cam.CFrame.Position
						local pick = TownView.nearest(points, p.X, p.Z, TownView.MAX_LIGHTS, TownView.RADIUS)
						table.clear(flickering)
						for i, l in lights do
							local idx = pick[i]
							if idx then
								local head = heads[idx]
								if l.Parent ~= head then
									l.Parent = head
								end
								l.Enabled = true
								l.Brightness = TownView.BRIGHTNESS
								if head:GetAttribute("Flicker") == true then
									flickering[l] = idx
								end
							else
								l.Enabled = false
							end
						end
					end
				end
				for l, seed in flickering do
					local n = math.sin(t * 13.1 + seed) * math.sin(t * 7.3 + seed * 0.5)
					l.Brightness = TownView.BRIGHTNESS * (if n > 0.82 then 0.25 else 1)
				end
			end)
		)
	end)
	return function()
		alive = false
		for _, c in conns do
			c:Disconnect()
		end
		for _, l in lights do
			l:Destroy()
		end
	end
end

return TownView
