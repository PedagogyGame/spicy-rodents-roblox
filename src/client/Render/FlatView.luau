--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Render.FlatView
-- One of the computer's squirrels knocked flat by a car, on this client (owner D21; Server/Wildlife/RoadSquirrels).
-- The server lays the body on its side where it was hit and writes one attribute on it, Flat (the server time of the
-- hit), until the squirrel is back in town; this module draws the rest, mildly (no gore, no blood, nothing left on the
-- road):
--   * a puff of dust where it lies: PUFF.count small pale balls that swell, drift up a little and fade in PUFF.secs
--     (plain client parts, no shadows, no collision, no queries: five parts for half a second);
--   * the fade: the body goes from solid to unseen over the last FADE of the LIE seconds it lies there (the parts' and
--     decals' LocalTransparencyModifier), and stays unseen while the attribute is set (the server has sunk it out of
--     sight by then anyway: a client that misses the fade shows nothing odd);
--   * back: with the attribute gone the body is solid again at once (it is on a tree by then).
-- A body that streams in already Flat is simply unseen (no puff for a hit nobody saw).
-- No service access at require time (Lune requires this module).
-- Interface: start(opts { bodies, now? }) -> stop(); fade(age) -> 0..1 (the body's transparency `age` seconds after
--   the hit; pure); puff(age, index) -> (size, rise, transparency) or nil once it is over (pure); LIE; FADE; PUFF

local FlatView = {}

FlatView.LIE = 3 -- seconds it lies there (Server/Wildlife/RoadSquirrels C.lieSecs)
FlatView.FADE = 1 -- ... of which the last second is the fade (C.fadeSecs)
-- the dust: pale road dust (never green, never red)
FlatView.PUFF = table.freeze({
	count = 5,
	secs = 0.55,
	size = { 0.5, 1.6 }, -- studs: each ball swells from the first to the second
	rise = 1.2, -- studs it drifts up
	spread = 1.1, -- studs from the body the balls start within
	color = { 214, 205, 188 },
	fresh = 1.5, -- seconds after the hit a puff is still worth drawing
})

-- fade(age): how unseen the body is `age` seconds after the hit: solid while it lies, fading over the last FADE,
-- unseen after
function FlatView.fade(age: number): number
	return math.clamp((age - (FlatView.LIE - FlatView.FADE)) / FlatView.FADE, 0, 1)
end

-- puff(age, index): ball `index` of the puff `age` seconds in: its size, how far it has risen, its transparency; nil
-- once the puff is over. Each ball swells a little differently (by its index: no dice on the client).
function FlatView.puff(age: number, index: number): (number?, number?, number?)
	local P = FlatView.PUFF
	if age < 0 or age >= P.secs then
		return nil, nil, nil
	end
	local u = age / P.secs
	local grow = 0.8 + 0.1 * ((index * 7) % 5)
	local size = (P.size[1] + (P.size[2] - P.size[1]) * u) * grow
	return size, P.rise * u, 0.35 + 0.65 * u
end

type Entry = {
	body: Model,
	conn: RBXScriptConnection,
	added: RBXScriptConnection?,
	shown: number, -- the transparency last written (0: solid)
}

function FlatView.start(opts: { bodies: Instance, now: (() -> number)? }): () -> ()
	local RunService = game:GetService("RunService")
	local now = opts.now or function(): number
		return workspace:GetServerTimeNow()
	end
	local entries: { [Instance]: Entry } = {}
	local flat: { [Instance]: Entry } = {} -- the bodies lying or away right now (the only ones a frame costs)
	local puffs: { { at: number, parts: { BasePart }, x: number, y: number, z: number } } = {}
	local holder = Instance.new("Folder")
	holder.Name = "FlatView"
	holder.Parent = workspace

	local function setSeen(inst: Instance, transparency: number)
		if inst:IsA("BasePart") or inst:IsA("Decal") then
			pcall(function()
				(inst :: any).LocalTransparencyModifier = transparency
			end)
		end
	end

	local function show(e: Entry, transparency: number)
		if e.shown == transparency then
			return
		end
		e.shown = transparency
		for _, d in e.body:GetDescendants() do
			setSeen(d, transparency)
		end
	end

	local function puffAt(body: Model, at: number)
		local P = FlatView.PUFF
		local pivot = body:GetPivot().Position
		local parts: { BasePart } = {}
		for i = 1, P.count do
			local part = Instance.new("Part")
			part.Name = "Dust"
			part.Shape = Enum.PartType.Ball
			part.Material = Enum.Material.SmoothPlastic
			part.Color = Color3.fromRGB(P.color[1], P.color[2], P.color[3])
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Parent = holder
			parts[i] = part
		end
		table.insert(puffs, { at = at, parts = parts, x = pivot.X, y = pivot.Y, z = pivot.Z })
	end

	local function apply(e: Entry)
		local at = e.body:GetAttribute("Flat")
		if type(at) ~= "number" then
			flat[e.body] = nil
			if e.added then
				e.added:Disconnect()
				e.added = nil
			end
			show(e, 0)
			return
		end
		if flat[e.body] == nil then
			flat[e.body] = e
			-- (parts that stream in while it is unseen are unseen too)
			e.added = e.body.DescendantAdded:Connect(function(d: Instance)
				setSeen(d, e.shown)
			end)
			local age = now() - at
			if age >= 0 and age < FlatView.PUFF.fresh then
				puffAt(e.body, at)
			end
		end
	end

	local function add(child: Instance)
		if not child:IsA("Model") or entries[child] then
			return
		end
		local body = child :: Model
		local e: Entry = { body = body, conn = nil :: any, shown = 0 }
		e.conn = body:GetAttributeChangedSignal("Flat"):Connect(function()
			apply(e)
		end)
		entries[child] = e
		if body:GetAttribute("Flat") ~= nil then
			apply(e)
		end
	end

	local function remove(child: Instance)
		local e = entries[child]
		if e then
			entries[child] = nil
			flat[child] = nil
			e.conn:Disconnect()
			if e.added then
				e.added:Disconnect()
			end
			show(e, 0)
		end
	end

	local conns: { RBXScriptConnection } = {}
	table.insert(conns, opts.bodies.ChildAdded:Connect(add))
	table.insert(conns, opts.bodies.ChildRemoved:Connect(remove))
	for _, child in opts.bodies:GetChildren() do
		add(child)
	end
	-- only while a squirrel lies somewhere, or a puff hangs in the air, does a frame do anything
	table.insert(
		conns,
		RunService.Heartbeat:Connect(function()
			if next(flat) == nil and #puffs == 0 then
				return
			end
			local t = now()
			for _, e in flat do
				local at = e.body:GetAttribute("Flat")
				if type(at) == "number" then
					-- (in a few steps: a fade written every frame would touch every part sixty times a second)
					show(e, math.floor(FlatView.fade(t - at) * 8 + 0.5) / 8)
				end
			end
			for i = #puffs, 1, -1 do
				local p = puffs[i]
				local P = FlatView.PUFF
				local over = false
				for k, part in p.parts do
					-- (a client clock a moment behind the server's starts the puff at its beginning)
					local size, rise, transparency = FlatView.puff(math.max(0, t - p.at), k)
					if size == nil or rise == nil or transparency == nil then
						over = true
						break
					end
					local angle = k * 2.399963 -- (the golden angle: the balls spread evenly round the body)
					local r = P.spread * (0.4 + 0.6 * ((k * 3) % 5) / 4)
					part.Size = Vector3.new(size, size, size)
					part.Transparency = transparency
					part.Position = Vector3.new(p.x + math.cos(angle) * r, p.y + 0.3 + rise, p.z + math.sin(angle) * r)
				end
				if over then
					for _, part in p.parts do
						part:Destroy()
					end
					table.remove(puffs, i)
				end
			end
		end)
	)
	return function()
		for _, c in conns do
			c:Disconnect()
		end
		for child in entries do
			remove(child)
		end
		holder:Destroy()
	end
end

return FlatView
