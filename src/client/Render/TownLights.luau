--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Render.TownLights
-- Night lighting for the town's buildings (the buildings and interiors art pass). The bake tags two
-- kinds of part with the attribute NightLight = true, the way the Backdrop's lit parts are tagged:
--   * room light fixtures (a shade or ceiling panel with a PointLight "Glow" inside it): lit as baked,
--     so a room is never black; at night the shade glows (Neon) and the light is a little brighter;
--   * a stable 60 % of the window panes of homes and the quay: plain glass by day, a warm glow at night.
-- The state follows Lighting's StreetLamps attribute (0..1, written by Client/World/Sky from the day
-- cycle) with hysteresis, so dusk never flickers. Without that attribute nothing is touched: the baked
-- look (rooms lit, windows glass) is already right, and the cloud checks and a failed client module
-- both leave a sane town.
-- Lots stream in and out (their models are Atomic): each lot Model that carries NightLights > 0 is
-- scanned when it arrives, its tagged parts' baked colours and materials remembered, and forgotten when
-- it leaves. A change of state is a few hundred property writes, twice per 12-minute day.
-- Started by Render/TownView.start. No service access at require time (Lune tests require this).
-- Interface: next(night, level) -> night; look(night, kind) -> { neon, scale, warm };
--   gather(model) -> { Entry }; apply(entry, night, env); start() -> stop()

local TownLights = {}

TownLights.ON = 0.35 -- StreetLamps level above which night begins
TownLights.OFF = 0.25 -- and below which it ends
TownLights.PERIOD = 0.5 -- seconds between looks at the level
TownLights.WINDOW = { 255, 218, 152 } -- v5.4 lamp glow #ffda98

export type Entry = { part: any, kind: string, material: any, color: any, light: any?, brightness: number }
export type Env = { Enum: any, Color3: any }
export type Look = { neon: boolean, scale: number, warm: boolean }

-- Night or day, from the lamp level, with hysteresis. Pure.
function TownLights.next(night: boolean, level: number): boolean
	if night then
		return level >= TownLights.OFF
	end
	return level > TownLights.ON
end

-- How a tagged part looks: `kind` is "fixture" (it holds a PointLight) or "window". Pure.
function TownLights.look(night: boolean, kind: string): Look
	if kind == "fixture" then
		return { neon = night, scale = if night then 1.25 else 1, warm = false }
	end
	return { neon = night, scale = 1, warm = night }
end

-- The tagged parts of one lot Model, with what they were baked as.
function TownLights.gather(model: any): { Entry }
	local out: { Entry } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("NightLight") == true then
			local light = d:FindFirstChildOfClass("PointLight")
			table.insert(out, {
				part = d,
				kind = if light then "fixture" else "window",
				material = d.Material,
				color = d.Color,
				light = light,
				brightness = if light then light.Brightness else 0,
			})
		end
	end
	return out
end

-- Puts one tagged part into its night or day look. Day restores exactly what was baked.
function TownLights.apply(e: Entry, night: boolean, env: Env)
	local look = TownLights.look(night, e.kind)
	e.part.Material = if look.neon then env.Enum.Material.Neon else e.material
	if look.warm then
		local w = TownLights.WINDOW
		e.part.Color = env.Color3.fromRGB(w[1], w[2], w[3])
	else
		e.part.Color = e.color
	end
	if e.light then
		e.light.Brightness = e.brightness * look.scale
	end
end

function TownLights.start(): () -> ()
	local RunService = game:GetService("RunService")
	local Lighting = game:GetService("Lighting")
	local env: Env = { Enum = Enum, Color3 = Color3 }
	local alive = true
	local conns: { RBXScriptConnection } = {}
	local lots: { [Instance]: { Entry } } = {}
	local night = false
	local function scan(model: Instance)
		if not model:IsA("Model") then
			return
		end
		local n = model:GetAttribute("NightLights")
		if type(n) ~= "number" or n <= 0 then
			return
		end
		local entries = TownLights.gather(model)
		lots[model] = entries
		if night then
			for _, e in entries do
				TownLights.apply(e, true, env)
			end
		end
	end
	task.spawn(function()
		local town = workspace:WaitForChild("Town", 120)
		local folder = town and town:WaitForChild("Lots", 60)
		if not alive or folder == nil then
			return -- no town: nothing to light (the baked look stands)
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
		local acc = TownLights.PERIOD
		table.insert(
			conns,
			RunService.Heartbeat:Connect(function(dt: number)
				acc += dt
				if acc < TownLights.PERIOD then
					return
				end
				acc = 0
				local level = Lighting:GetAttribute("StreetLamps")
				if type(level) ~= "number" then
					return -- no day cycle running: leave the baked look
				end
				local now = TownLights.next(night, level)
				if now ~= night then
					night = now
					for _, entries in lots do
						for _, e in entries do
							if e.part.Parent then
								TownLights.apply(e, night, env)
							end
						end
					end
				end
			end)
		)
	end)
	return function()
		alive = false
		for _, c in conns do
			c:Disconnect()
		end
		-- back to the baked look
		for _, entries in lots do
			for _, e in entries do
				if e.part.Parent then
					TownLights.apply(e, false, env)
				end
			end
		end
		table.clear(lots)
	end
end

return TownLights
