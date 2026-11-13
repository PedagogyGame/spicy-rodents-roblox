--!strict
-- ServerScriptService.Server.Attractions.AttractionService
-- Boots the attraction buildings baked on their own (Workspace.Attractions from tools/bake/attractions.luau;
-- data/attractions.json; brief v2 §13a; BUILD_PLAN §1.1 rule 13): carves the boot terrain out of the bowling
-- alley's nine ball-return ducts (and from under its alley, over its entrance ramp and out of the front-west
-- corner, where the ground stands above the floor) so the squirrel tunnels are open air, registers
-- the collision groups (LaneGuard keeps people off the lanes; BowlingPhysics is the baked group of the ball and
-- pins, which are scripted and collide with nothing), swings the steel push-bar exit doors on E (from inside only, like the real thing:
-- the prompt needs line of sight), and starts the MinigameService with its Heartbeat step. Every model under
-- Workspace.Attractions that carries the bake's Origin attributes is a SITE for minigames (the bowling alley, and
-- each expansion venue a game has baked: Shared/Minigames/Games explains sites); the service is handed them all
-- and puts each registered game's stations where they stand. Missing Workspace.Attractions is reported, never
-- fatal.
-- Interface: start(opts) -> Attractions { minigames, place (the alley's), sites, step(dt), stop() } | nil;
--   sites(folder) -> { [siteId]: { root, place } }

local Import = require("../Import")
local Data = Import.shared("Data") :: typeof(require("../../shared/Data"))
local MinigameService = require("../Minigames/MinigameService")

local AttractionService = {}

export type Opts = {
	net: any?,
	canPlay: ((player: any) -> (boolean, string?))?,
	bodyOf: ((player: any) -> Model?)?,
	animals: (() -> { { [string]: any } })?, -- squirrel-family bodies (a lane in play knocks them off it)
	knock: ((id: any, x: number, y: number, z: number, text: string) -> ())?,
	heartbeat: boolean?, -- default true
	terrain: boolean?, -- carve terrain (default true)
	prompts: boolean?,
	seed: number?, -- the lanes' seeded streams (default: from the clock, printed so a game can be replayed)
	-- what the games may ask of the rest of the town (Server/Minigames/ServerGame.Town: people, body, release,
	-- charge, best); handed to MinigameService as it is, every member optional
	games: { [string]: any }?,
	-- paintball's own hand from the town (PaintballService.Deps: fit, day, passStore), handed on as it is
	paintball: { [string]: any }?,
}

local function carve(root: Instance): number
	local folder = root:FindFirstChild("TerrainCarve")
	if folder == nil then
		return 0
	end
	local n = 0
	for _, p in folder:GetChildren() do
		if p:IsA("BasePart") then
			workspace.Terrain:FillBlock(p.CFrame, p.Size, Enum.Material.Air)
			n += 1
		end
	end
	return n
end

local function collisionGroups()
	local PhysicsService = game:GetService("PhysicsService")
	for _, g in { "BowlingPhysics", "LaneGuard" } do
		pcall(function()
			if not PhysicsService:IsCollisionGroupRegistered(g) then
				PhysicsService:RegisterCollisionGroup(g)
			end
		end)
	end
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable("LaneGuard", "BowlingPhysics", false)
	end)
end

-- The push-bar doors: both leaves swing out together on E, close after a while.
local function doors(root: Instance, conns: { RBXScriptConnection }): { step: (dt: number) -> () }
	local folder = root:FindFirstChild("Doors")
	local leaves: { { model: Model, home: CFrame, hinge: Vector3, side: number } } = {}
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("Door") == "push_bar" and m.PrimaryPart then
				local home = m:GetPivot()
				local leaf = m.PrimaryPart :: BasePart
				local side = (m:GetAttribute("Side") :: number?) or 1
				-- the hinge edge: the leaf's end toward its HingeX (local X across the building)
				local half = leaf.Size.X / 2
				local hinge = (leaf.CFrame * CFrame.new(side * half, 0, 0)).Position
				table.insert(leaves, { model = m, home = home, hinge = hinge, side = side })
			end
		end
	end
	local openT, target, t = 0, 0, 0
	local function trigger()
		target = 1
		openT = 5
	end
	for _, l in leaves do
		local leaf = l.model.PrimaryPart :: BasePart
		local att = Instance.new("Attachment")
		att.Name = "PushPoint"
		att.CFrame = CFrame.new(0, -0.2, 0.4) -- just inside the building (the leaf's +Z face, local -D)
		att.Parent = leaf
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "DoorPrompt"
		prompt.ActionText = "Push"
		prompt.ObjectText = "Exit to the alley"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 6
		prompt.RequiresLineOfSight = true
		prompt:SetAttribute("Door", true)
		prompt.Parent = att
		table.insert(conns, prompt.Triggered:Connect(trigger))
	end
	return {
		step = function(dt: number)
			if openT > 0 then
				openT -= dt
				if openT <= 0 then
					target = 0
				end
			end
			local prev = t
			t += math.clamp(target - t, -dt * 2.5, dt * 2.5)
			if t ~= prev then
				local a = t * t * (3 - 2 * t)
				for _, l in leaves do
					-- out toward the alley: the leaf's +Z side (local +D); left leaf turns one way, right the other
					local angle = -a * math.rad(100) * l.side
					local rot = CFrame.new(l.hinge) * CFrame.Angles(0, angle, 0) * CFrame.new(-l.hinge)
					l.model:PivotTo(rot * l.home)
				end
			end
		end,
	}
end

-- The baked places with games in them: a child of Workspace.Attractions with OriginX / OriginZ / FloorY / Yaw.
-- Its site id is its Site attribute (the bake writes it), else its AttractionId.
function AttractionService.sites(folder: Instance): { [string]: MinigameService.Site }
	local out: { [string]: MinigameService.Site } = {}
	for _, m in folder:GetChildren() do
		local x, z = m:GetAttribute("OriginX"), m:GetAttribute("OriginZ")
		local floorY, yaw = m:GetAttribute("FloorY"), m:GetAttribute("Yaw")
		local id = m:GetAttribute("Site") or m:GetAttribute("AttractionId")
		if
			type(id) == "string"
			and type(x) == "number"
			and type(z) == "number"
			and type(floorY) == "number"
			and type(yaw) == "number"
		then
			out[id] = { root = m, place = { x = x, z = z, floorY = floorY, yaw = yaw } }
		end
	end
	return out
end

function AttractionService.start(opts: Opts?): any?
	local o: Opts = opts or {}
	local folder = workspace:FindFirstChild("Attractions")
	local alley = folder and folder:FindFirstChild("BowlingAlley")
	if alley == nil then
		warn(
			"[Attractions] Workspace.Attractions.BowlingAlley missing (run lune run tools/bake/attractions.luau and rebuild): no bowling alley"
		)
		return nil
	end
	collisionGroups()
	local carved = 0
	if o.terrain ~= false then
		local ok, err = pcall(function()
			carved = carve(alley)
		end)
		if not ok then
			warn(`[Attractions] terrain carve failed: {err}`)
		end
	end
	local place = {
		x = alley:GetAttribute("OriginX") :: number,
		z = alley:GetAttribute("OriginZ") :: number,
		floorY = alley:GetAttribute("FloorY") :: number,
		yaw = alley:GetAttribute("Yaw") :: number,
	}
	-- the ball's way home is the squirrel's ball-return run (data/attractions.json -> generated/Attractions: one enclosed
	-- route per pair of lanes, kind "tunnel"; BowlingLane keeps the stretch from the pit on, so the alley vent is not
	-- on the ball's way)
	local tunnels: { [number]: { { number } } } = {}
	local ok, mod = pcall(function()
		return Data.default():module("Attractions")
	end)
	if ok and type(mod) == "table" and type((mod :: any).routes) == "table" then
		for _, r in (mod :: any).routes do
			if r.kind == "tunnel" or (r.kind == "bridge" and string.find(r.name, "tunnel", 1, true)) then
				-- the pair is the route's own field (data/attractions.json); an older record names its first lane
				local pair = if type(r.pair) == "number"
					then r.pair
					else ((tonumber(string.match(r.name, "lanes (%d+)")) or 0) + 1) // 2
				tunnels[pair] = r.points
			end
		end
	end
	local conns: { RBXScriptConnection } = {}
	local seed = o.seed or (os.time() % 1000000)
	local sites = AttractionService.sites(folder :: Instance)
	sites.bowling_alley = { root = alley, place = place }
	local minigames = MinigameService.new({
		sites = sites,
		tunnels = tunnels,
		net = o.net,
		canPlay = o.canPlay,
		bodyOf = o.bodyOf,
		animals = o.animals,
		knock = o.knock,
		prompts = o.prompts,
		seed = seed,
		games = o.games,
		paintball = o.paintball,
	})
	local doorRig = doors(alley, conns)
	local function step(dt: number)
		minigames:step(dt)
		doorRig.step(dt)
	end
	if o.heartbeat ~= false then
		table.insert(
			conns,
			game:GetService("RunService").Heartbeat:Connect(function(dt: number)
				local good, err = pcall(step :: (number) -> any, math.min(dt, 0.1))
				if not good then
					warn(`[Attractions] step failed: {err}`)
				end
			end)
		)
	end
	local siteCount = 0
	for _ in sites do
		siteCount += 1
	end
	print(
		`[Attractions] bowling alley ready: {#minigames.order} stations on {siteCount} site(s), {carved} terrain carves, seed {seed}`
	)
	return {
		minigames = minigames,
		place = place,
		sites = sites,
		carved = carved,
		step = step,
		stop = function()
			minigames:stop()
			for _, c in conns do
				c:Disconnect()
			end
		end,
	}
end

return AttractionService
