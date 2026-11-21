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
-- Staggered (owner, 1.1: "make the lights in the town on the buildings and houses come on at more staggered and varied
-- times, the street lights etc however should still all come on at the same time"): the street lamps are Render/
-- TownView's pool and still switch together at ON; each building light here has its own moment, the same on every
-- client (TownLights.stagger, from the lot's name and the part's place): a fifth are early birds that come on while
-- it is still dusk (their own level under ON), the rest follow the lamps by a delay of their house's (0 .. HOUSE_ON s)
-- plus their own (0 .. ROOM_ON s); in the morning each goes dark its own while after day begins (0 .. OFF_SPREAD s).
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
TownLights.EARLY = 0.2 -- the share of building lights that come on before the street lamps
TownLights.EARLY_LO = 0.1 -- the lowest lamp level an early bird lights at (up to ON)
TownLights.HOUSE_ON = 40 -- seconds after the lamps: a house's own delay, up to this
TownLights.ROOM_ON = 30 -- and each light's own on top, up to this
TownLights.OFF_SPREAD = 45 -- seconds after day begins: each light's own, up to this

export type Entry = {
	part: any,
	kind: string,
	material: any,
	color: any,
	light: any?,
	brightness: number,
	delayOn: number, -- seconds after night begins
	delayOff: number, -- seconds after day begins
	early: number?, -- an early bird: the lamp level it lights at (under ON)
	on: boolean, -- in its night look now
}
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

-- A stable number in [0, 1) from a name and a place (the same on every client, different from light to light). Pure.
local function unit(name: string, x: number, y: number, z: number, salt: number): number
	local h = salt * 0.6180339887
	for i = 1, #name do
		h = (h * 31 + string.byte(name, i)) % 1000003
	end
	local v = math.sin(h * 0.000127 + x * 12.9898 + y * 78.233 + z * 37.719 + salt * 4.1414) * 43758.5453
	return v - math.floor(v)
end

-- stagger(lot, x, y, z) -> (delayOn, delayOff, early?): one building light's own moments (see the header). Pure.
function TownLights.stagger(lot: string, x: number, y: number, z: number): (number, number, number?)
	local house = unit(lot, 0, 0, 0, 1) * TownLights.HOUSE_ON
	local room = unit(lot, x, y, z, 2) * TownLights.ROOM_ON
	local off = unit(lot, x, y, z, 3) * TownLights.OFF_SPREAD
	local early: number? = nil
	if unit(lot, x, y, z, 4) < TownLights.EARLY then
		early = TownLights.EARLY_LO + unit(lot, x, y, z, 5) * (TownLights.ON - TownLights.EARLY_LO)
	end
	return house + room, off, early
end

-- want(e, night, sinceFlip, level) -> boolean: should this light be in its night look, `sinceFlip` seconds after the
-- town's night or day began, at lamp level `level`? Once on it stays on through the night. Pure.
function TownLights.want(e: Entry, night: boolean, sinceFlip: number, level: number): boolean
	local early = e.early ~= nil and level > (e.early :: number)
	if night then
		return e.on or early or sinceFlip >= e.delayOn
	end
	return early or (e.on and sinceFlip < e.delayOff)
end

-- The tagged parts of one lot Model, with what they were baked as.
function TownLights.gather(model: any): { Entry }
	local out: { Entry } = {}
	local lot = tostring(model.Name)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("NightLight") == true then
			local light = d:FindFirstChildOfClass("PointLight")
			-- (its place, for its own moment; a part with none readable shares its house's)
			local okPos, pos = pcall(function(): any
				return d.CFrame.Position
			end)
			local px, py, pz = 0, 0, 0
			if okPos and pos then
				px, py, pz = pos.X, pos.Y, pos.Z
			end
			local delayOn, delayOff, early = TownLights.stagger(lot, px, py, pz)
			table.insert(out, {
				part = d,
				kind = if light then "fixture" else "window",
				material = d.Material,
				color = d.Color,
				light = light,
				brightness = if light then light.Brightness else 0,
				delayOn = delayOn,
				delayOff = delayOff,
				early = early,
				on = false,
			})
		end
	end
	return out
end

-- Puts one tagged part into its night or day look. Day restores exactly what was baked.
function TownLights.apply(e: Entry, night: boolean, env: Env)
	local look = TownLights.look(night, e.kind)
	e.on = night
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
	local flipAt = -math.huge -- os.clock() when the town's night or day last began
	local level0 = 0 -- the lamp level last read
	local settle = true -- some light may still be waiting for its moment
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
		-- (a lot streaming in takes each light's state for this moment of the evening)
		local since = os.clock() - flipAt
		for _, e in entries do
			if TownLights.want(e, night, since, level0) then
				TownLights.apply(e, true, env)
			end
		end
		settle = true
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
					flipAt = os.clock()
					settle = true
				end
				-- each light at its own moment: while any may still be waiting, or the level is in the early birds' band
				local band = level > TownLights.EARLY_LO - 0.05 and level < TownLights.ON + 0.05
				if level ~= level0 and band then
					settle = true
				end
				level0 = level
				if not settle then
					return
				end
				local since = os.clock() - flipAt
				local longest = if night then TownLights.HOUSE_ON + TownLights.ROOM_ON else TownLights.OFF_SPREAD
				settle = since <= longest + TownLights.PERIOD or band
				for _, entries in lots do
					for _, e in entries do
						if e.part.Parent then
							local want = TownLights.want(e, night, since, level)
							if want ~= e.on then
								TownLights.apply(e, want, env)
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
