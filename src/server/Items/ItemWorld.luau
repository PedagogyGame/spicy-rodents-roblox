--!strict
-- ServerScriptService.Server.Items.ItemWorld
-- The engine half of using a corner-store item (Items/ItemService decides; this does it in the world). Every
-- effect is plain parts, a Sound with a cue name, an attribute, a brain event or a message to the owner's
-- client; nothing runs per frame but the few things in the world that move (thrown things settle on their own;
-- STEP only looks at kites, whoopee cushions and bait every 0.1 s).
--   sound      a Sound named by its cue at the holder (SOUNDS has the ids: empty until the lead fills them from
--              the stock library; docs/AUDIO_BUDGET.md "Corner store")
--   squirt     a burst of water from the nozzle; a computer-run person hit hurries off, a player is told
--   stun       the rodent (a player's or the computer's) held still for the seconds
--   startle    the air horn: people hurry off, squirrels bolt, players are told
--   vfx        bubbles from the wand for a few seconds
--   light      a spotlight in the flashlight's head (bright at night, faint by day); open: the umbrella's canopy
--   playlist   the radio plays its cues one after another while it is on
--   throw      a copy of the thing flies (the engine's physics: one loose part; a frisbee glides on a small lift)
--              and lands; E picks it up (it is yours then); a person it hits in flight catches it; left alone 2
--              minutes it goes back to the thrower. The newspaper is litter: gone after 20 s.
--   write      the chalk's filtered words on the ground in front (5 minutes; 30 in the town at most)
--   tape       a strip of duct tape on what is ahead (5 minutes; 40 at most)
--   place      a lawn chair (sat in at once; E folds it back up, its owner's) or a whoopee cushion (the next person
--              to come within a stud and a half sets it off; E picks it up)
--   bait       a pile on the ground; nearby squirrels come to it (their brain's "bait"); bird seed brings birds
--   treat      body attributes TreatUntil (server time) and TreatScale: Client/Controllers/Human walks faster
--   read, askText, screenshot   a message to the owner's client (Client/Items/ItemClient)
--   kite       up on its string downwind of its flier, swaying; reeled in on the next use or out of the zone
-- Interface: start(opts) -> World { service (ItemService), use(player, id, payload?), step(), stop() }; SOUNDS;
--   KITE (the flight's numbers)
-- Engine only inside the functions; no side effects on require.

local Import = require("../Import")
local ItemRules = Import.shared("Items/ItemRules") :: typeof(require("../../shared/Items/ItemRules"))
local Clock = Import.shared("Time/Clock") :: typeof(require("../../shared/Time/Clock"))
local ItemService = require("./ItemService")

local ItemWorld = {}

-- cue name -> sound asset id, "rbxassetid://<n>": empty until the lead picks a sound from Roblox's licensed
-- library (no uploads; docs/AUDIO_BUDGET.md "Corner store"). Every cue of ItemRules.CUES and
-- ItemRules.RADIO_PLAYLIST has a row (tests/unit/corner_store_items.spec.luau).
local SOUNDS: { [string]: string } = {
	["Items.WaterGun"] = "",
	["Items.Harmonica"] = "",
	["Items.BikeHorn"] = "",
	["Items.AirHorn"] = "",
	["Items.Bubbles"] = "",
	["Items.CameraClick"] = "",
	["Items.TapeRip"] = "",
	["Items.Whoopee"] = "",
	["Items.SodaFizz"] = "",
	["Items.Wrapper"] = "",
	["Items.PaperRustle"] = "",
	["Items.ChairUnfold"] = "",
	["Items.Click"] = "",
	["Items.UmbrellaOpen"] = "",
	["Items.Throw"] = "",
	["Items.Chalk"] = "",
	["Items.Scatter"] = "",
	["Items.Crunch"] = "",
	["Items.KiteWind"] = "",
	["Radio.Oldies1"] = "",
	["Radio.Oldies2"] = "",
	["Radio.SoftRock"] = "",
	["Radio.Country"] = "",
	["Radio.Jazz"] = "",
	["Radio.Weather"] = "",
}
ItemWorld.SOUNDS = SOUNDS

ItemWorld.KITE = table.freeze({
	launchSecs = 3, -- from the hand to its height
	height = 34, -- studs above its flier
	back = 22, -- studs downwind
	sway = 4, -- studs side to side
	swayHz = 0.15,
	reelSecs = 2.5,
	wind = { 0.6, 0.8 }, -- the town's wind (XZ, unit)
})

export type StartOpts = {
	inventory: any, -- Items/Inventory
	possession: any, -- Actors/Possession
	runtime: any, -- Actors/ActorsRuntime (world, byTownId)
	fire: (player: any, payload: { [string]: any }) -> (),
	zones: { any }?, -- generated/Expansion.zones (the kite's)
	heartbeat: boolean?,
}

export type World = {
	service: any,
	use: (player: any, itemId: string, payload: { [string]: any }?) -> (boolean, string?),
	step: () -> (),
	stop: () -> (),
}

local function newPart(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

function ItemWorld.start(opts: StartOpts): World
	local Players = game:GetService("Players")
	local Debris = game:GetService("Debris")
	local TextService = game:GetService("TextService")
	local folder = Instance.new("Folder")
	folder.Name = "CornerStoreItems"
	folder.Parent = workspace
	local clock = Clock.fromEngine()
	local possession = opts.possession
	local rt = opts.runtime
	local conns: { RBXScriptConnection } = {}

	local function actorOf(player: any): any?
		return possession and possession:actorOf(player)
	end
	local function rootOf(player: any): BasePart?
		local a = actorOf(player)
		local body = a and a.body
		local r = body and (body :: Model).PrimaryPart
		return r
	end
	local function toolOf(player: any, itemId: string): Tool?
		if typeof(player) ~= "Instance" then
			return nil
		end
		local p = player :: Player
		for _, holder in { p.Character, p:FindFirstChildOfClass("Backpack") } :: { Instance? } do
			for _, t in (if holder then holder:GetChildren() else {}) :: { Instance } do
				if t:IsA("Tool") and t:GetAttribute("ItemId") == itemId then
					return t
				end
			end
		end
		return nil
	end
	local function handleOf(player: any, itemId: string): BasePart?
		local t = toolOf(player, itemId)
		local h = t and t:FindFirstChild("Handle")
		return if h and h:IsA("BasePart") then h else nil
	end
	local function notify(player: any, words: string)
		opts.fire(player, { kind = "notice", text = words })
	end
	local function playCue(cue: string, at: Instance?)
		if at == nil then
			return
		end
		local s = Instance.new("Sound")
		s.Name = cue
		s.SoundId = SOUNDS[cue] or ""
		s.RollOffMaxDistance = 80
		s.Parent = at
		if s.SoundId ~= "" then
			s:Play()
		end
		Debris:AddItem(s, 6)
	end
	local function groundBelow(x: number, y: number, z: number): Vector3?
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ex: { Instance } = { folder }
		for _, p in Players:GetPlayers() do
			if p.Character then
				table.insert(ex, p.Character)
			end
		end
		params.FilterDescendantsInstances = ex
		local hit = workspace:Raycast(Vector3.new(x, y + 2, z), Vector3.new(0, -12, 0), params)
		if hit then
			return hit.Position
		end
		return nil
	end
	local function aheadOf(player: any, dist: number): (Vector3?, BasePart?)
		local root = rootOf(player)
		if root == nil then
			return nil, nil
		end
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
		return root.Position + flat * dist, root
	end
	-- a capped list of things left in the world (oldest goes first)
	local function capped(list: { Instance }, item: Instance, max: number, secs: number)
		table.insert(list, item)
		while #list > max do
			local old = table.remove(list, 1)
			if old then
				old:Destroy()
			end
		end
		Debris:AddItem(item, secs)
	end
	local writings: { Instance } = {}
	local tapes: { Instance } = {}

	-- the town's brains, for a computer-run person, squirrel or the rodent
	local function brainOf(id: any): any?
		local world = rt and rt.world
		return world and world.brains[id]
	end
	local function playerOfTown(id: any): any?
		local actor = rt and rt.byTownId and rt.byTownId[id]
		if actor == nil then
			return nil
		end
		for _, p in Players:GetPlayers() do
			if actorOf(p) == actor then
				return p
			end
		end
		return nil
	end

	local function nearby(x: number, z: number, r: number): { ItemService.Target }
		local out: { ItemService.Target } = {}
		local world = rt and rt.world
		if world == nil then
			return out
		end
		local r2 = r * r
		for _, a in world.actors do
			local dx, dz = a.x - x, a.z - z
			if dx * dx + dz * dz <= r2 then
				local kind = a.species
				if a.species == "squirrel" and a.variant == "spicy" then
					kind = "rodent"
				end
				local p = playerOfTown(a.id)
				local px, py, pz = a.x, a.y, a.z
				if p then
					local root = rootOf(p)
					if root then
						px, py, pz = root.Position.X, root.Position.Y, root.Position.Z
					end
				end
				table.insert(out, { kind = kind, id = a.id, x = px, y = py, z = pz, player = p })
			end
		end
		return out
	end

	-- a thrown thing, flying then lying where it lands until someone picks it up
	local function throw(player: any, e: { [string]: any }): boolean
		local tool = toolOf(player, e.item)
		local root = rootOf(player)
		if tool == nil or root == nil then
			return false
		end
		local model = Instance.new("Model")
		model.Name = "Thrown_" .. e.item
		local main: BasePart? = nil
		for _, c in tool:GetChildren() do
			if c:IsA("BasePart") then
				local p = c:Clone()
				for _, w in p:GetChildren() do
					if w:IsA("WeldConstraint") then
						w:Destroy()
					end
				end
				p.Anchored = false
				p.CanQuery = true
				p.Parent = model
				if main == nil then
					main = p
					p.CanCollide = true
					p.Massless = false
				else
					p.CanCollide = false
					p.Massless = true
					local w = Instance.new("WeldConstraint")
					w.Part0 = main
					w.Part1 = p
					w.Parent = p
				end
			end
		end
		if main == nil then
			model:Destroy()
			return false
		end
		local m = main :: BasePart
		local look = root.CFrame.LookVector
		local start = root.Position + look * 2.5 + Vector3.new(0, 1.5, 0)
		model.Parent = folder
		model:PivotTo(CFrame.new(start) * m.CFrame.Rotation)
		m:SetNetworkOwner(nil)
		m.AssemblyLinearVelocity = (look * (1 - e.lift) + Vector3.new(0, e.lift, 0)).Unit * e.speed
		if e.item == "frisbee" then
			-- a frisbee glides: a small upward push against gravity while it is fast
			local att = Instance.new("Attachment")
			att.Parent = m
			local lift = Instance.new("VectorForce")
			lift.Attachment0 = att
			lift.RelativeTo = Enum.ActuatorRelativeTo.World
			lift.Force = Vector3.new(0, m.AssemblyMass * workspace.Gravity * 0.6, 0)
			lift.Parent = m
			m.AssemblyAngularVelocity = Vector3.new(0, 18, 0)
			task.delay(1.6, function()
				lift:Destroy()
			end)
		end
		tool:Destroy()
		if e.item == "newspaper" then
			Debris:AddItem(model, 20)
			return true
		end
		local owner = player
		local taken = false
		local function give(to: any)
			if taken then
				return
			end
			taken = true
			model:Destroy()
			opts.inventory.add(to, e.item)
		end
		-- a person it hits in flight catches it
		local touch = m.Touched:Connect(function(other: BasePart)
			if taken or m.AssemblyLinearVelocity.Magnitude < 4 then
				return
			end
			local who = Players:GetPlayerFromCharacter(other:FindFirstAncestorOfClass("Model"))
			if who and who ~= owner then
				local a = actorOf(who)
				if a and a.species == "human" then
					notify(who, "Caught it!")
					give(who)
				end
			end
		end)
		m.CanTouch = true
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Pick up"
		prompt.ObjectText = tool.Name
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 8
		prompt.Parent = m
		prompt.Triggered:Connect(function(who: Player)
			local a = actorOf(who)
			if a and a.species == "human" then
				give(who)
			end
		end)
		task.delay(120, function()
			touch:Disconnect()
			if not taken and owner.Parent == Players then
				give(owner)
				notify(owner, "Your " .. string.lower(tool.Name) .. " is back in your hands.")
			elseif not taken then
				taken = true
				model:Destroy()
			end
		end)
		return true
	end

	-- kites in the air: flier, model, string ends, phase
	type Kite = { player: any, model: Model, a0: Attachment, a1: Attachment, t: number, reel: number? }
	local kites: { Kite } = {}
	-- whoopee cushions waiting for a sitter
	type Cushion = { part: BasePart, owner: any, armed: boolean }
	local cushions: { Cushion } = {}
	-- baits on the ground, and the birds at them
	type Bait = { part: BasePart, birds: { BasePart }, untilT: number, t: number }
	local baits: { Bait } = {}

	local function kiteDown(k: Kite)
		if k.reel == nil then
			k.reel = 0
		end
	end

	local function act(player: any, e: { [string]: any }, targets: { ItemService.Target }?): boolean?
		local kind = e.kind
		local root = rootOf(player)
		if kind == "sound" then
			playCue(e.cue, root)
		elseif kind == "squirt" then
			local h = handleOf(player, "water_gun")
			if h then
				local att = Instance.new("Attachment")
				att.Parent = h
				local pe = Instance.new("ParticleEmitter")
				pe.Color = ColorSequence.new(Color3.fromRGB(150, 200, 255))
				pe.Speed = NumberRange.new(30, 36)
				pe.Lifetime = NumberRange.new(0.3, 0.45)
				pe.Size = NumberSequence.new(0.2)
				pe.SpreadAngle = Vector2.new(3, 3)
				pe.Acceleration = Vector3.new(0, -40, 0)
				pe.EmissionDirection = Enum.NormalId.Front
				pe.Enabled = false
				pe.Parent = att
				pe:Emit(24)
				Debris:AddItem(att, 1.5)
			end
			playCue(ItemRules.CUES.water_gun, root)
			for _, t in (targets or {}) :: { ItemService.Target } do
				if t.player then
					notify(t.player, "You got squirted!")
				elseif t.kind == "human" and root then
					local b = brainOf(t.id)
					if b then
						b:onEvent({
							type = "witness",
							threat = { x = root.Position.X, z = root.Position.Z },
							alert = 2,
						})
					end
				end
			end
		elseif kind == "stun" then
			for _, t in (targets or {}) :: { ItemService.Target } do
				if t.player then
					local r = rootOf(t.player)
					if r then
						local was = r.Anchored
						r.Anchored = true
						r:SetAttribute("Stunned", true)
						notify(t.player, "Squirted! Stunned for a moment.")
						task.delay(e.secs, function()
							if r.Parent then
								r.Anchored = was
								r:SetAttribute("Stunned", nil)
							end
						end)
					end
				else
					local world = rt and rt.world
					local a = world and world.actorsById[t.id]
					if world and a then
						local TownAI = require("../AI/TownAI") :: any
						TownAI.suspend(world, t.id)
						local x, y, z = a.x, a.y, a.z
						task.delay(e.secs, function()
							if world.possessed[t.id] then
								TownAI.resume(world, t.id, x, y, z)
							end
						end)
					end
				end
			end
		elseif kind == "startle" then
			for _, t in (targets or {}) :: { ItemService.Target } do
				if t.player and t.player ~= player then
					notify(t.player, "AIR HORN! You nearly jump out of your skin.")
				elseif t.player == nil and root then
					local b = brainOf(t.id)
					if b and (t.kind == "squirrel" or t.kind == "rodent") then
						b:onEvent({ type = "startle" })
					elseif b and t.kind == "human" then
						b:onEvent({
							type = "witness",
							threat = { x = root.Position.X, z = root.Position.Z },
							alert = 3,
						})
					end
				end
			end
		elseif kind == "vfx" then
			local h = handleOf(player, "bubbles")
			if h then
				local att = Instance.new("Attachment")
				att.Position = Vector3.new(0, h.Size.Y / 2 + 0.6, 0)
				att.Parent = h
				local pe = Instance.new("ParticleEmitter")
				pe.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255), Color3.fromRGB(255, 200, 250))
				pe.Transparency = NumberSequence.new(0.35)
				pe.LightEmission = 0.3
				pe.Rate = 10
				pe.Speed = NumberRange.new(2, 4)
				pe.Lifetime = NumberRange.new(2, 3.5)
				pe.Size = NumberSequence.new(0.25, 0.5)
				pe.Acceleration = Vector3.new(0, 1.2, 0)
				pe.SpreadAngle = Vector2.new(35, 35)
				pe.Parent = att
				task.delay(e.secs, function()
					pe.Enabled = false
				end)
				Debris:AddItem(att, e.secs + 4)
			end
			playCue(ItemRules.CUES.bubbles, root)
		elseif kind == "light" then
			local h = handleOf(player, "flashlight")
			if h then
				local beam = h:FindFirstChild("Beam") :: SpotLight?
				if beam == nil then
					local s = Instance.new("SpotLight")
					s.Name = "Beam"
					s.Face = Enum.NormalId.Top
					s.Angle = 40
					s.Shadows = false
					s.Parent = h
					beam = s
				end
				local b = beam :: SpotLight
				b.Enabled = e.on == true
				b.Brightness = if e.strong then 4 else 0.6
				b.Range = if e.strong then 45 else 14
			end
		elseif kind == "open" then
			local t = toolOf(player, "umbrella")
			local canopy = t and t:FindFirstChild("OpenCanopy")
			if canopy and canopy:IsA("BasePart") then
				canopy.Transparency = if e.on then 0 else 1
			end
			playCue(ItemRules.CUES.umbrella, root)
		elseif kind == "playlist" then
			local h = handleOf(player, "radio")
			if h then
				local s = h:FindFirstChild("RadioSound") :: Sound?
				if s == nil then
					local snd = Instance.new("Sound")
					snd.Name = "RadioSound"
					snd.RollOffMaxDistance = 60
					snd.Volume = 0.6
					snd.Parent = h
					s = snd
					local i = 0
					-- one track after another, round the playlist, while it is on
					snd.Ended:Connect(function()
						if snd:GetAttribute("On") then
							i = i % #e.tracks + 1
							snd:SetAttribute("Track", e.tracks[i])
							snd.SoundId = SOUNDS[e.tracks[i]] or ""
							if snd.SoundId ~= "" then
								snd:Play()
							end
						end
					end)
				end
				local snd = s :: Sound
				snd:SetAttribute("On", e.on == true)
				if e.on then
					snd:SetAttribute("Track", e.tracks[1])
					snd.SoundId = SOUNDS[e.tracks[1]] or ""
					if snd.SoundId ~= "" then
						snd:Play()
					end
					notify(player, "Radio on: " .. string.gsub(e.tracks[1], "^Radio%.", ""))
				else
					snd:Stop()
				end
			end
		elseif kind == "throw" then
			return throw(player, e)
		elseif kind == "read" then
			notify(player, `PEPPER'S GAZETTE: {e.headline}`)
			playCue(ItemRules.CUES.newspaper, root)
		elseif kind == "askText" or kind == "screenshot" then
			opts.fire(player, { kind = "item", action = kind, item = e.item, max = e.max, left = e.left })
			if kind == "screenshot" then
				playCue(ItemRules.CUES.camera, root)
			end
		elseif kind == "write" then
			local at = aheadOf(player, 3)
			local g = at and groundBelow(at.X, at.Y, at.Z)
			if g == nil or root == nil then
				return false
			end
			local look = root.CFrame.LookVector
			local yaw = math.atan2(-look.X, -look.Z)
			local w = math.clamp(utf8.len(e.text) or #e.text, 4, 20) * 0.9
			local p = newPart(
				"Chalk",
				Vector3.new(w, 0.05, 2),
				CFrame.new(g + Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, yaw, 0),
				Color3.new(1, 1, 1),
				folder
			)
			p.Transparency = 1
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Top
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 40
			gui.Parent = p
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Text = e.text
			label.TextScaled = true
			label.FontFace = Font.fromEnum(Enum.Font.PatrickHand)
			label.TextColor3 = Color3.fromRGB(250, 240, 250)
			label.Rotation = 180
			label.Parent = gui
			capped(writings, p, 30, 300)
		elseif kind == "tape" then
			if root == nil then
				return false
			end
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { folder, (root :: BasePart).Parent :: Instance }
			local hit = workspace:Raycast(root.Position, root.CFrame.LookVector * e.reach, params)
			if hit == nil then
				notify(player, "Nothing close enough to tape.")
				return false
			end
			local cf = CFrame.lookAt(hit.Position + hit.Normal * 0.02, hit.Position + hit.Normal)
			local p = newPart("Tape", Vector3.new(1.6, 0.35, 0.03), cf, Color3.fromRGB(170, 172, 178), folder)
			p.Material = Enum.Material.Fabric
			capped(tapes, p, 40, 300)
		elseif kind == "place" then
			local at = aheadOf(player, if e.prop == "lawn_chair" then 3 else 2.5)
			local g = at and groundBelow(at.X, at.Y, at.Z)
			if g == nil or root == nil then
				notify(player, "No room to put it down here.")
				return false
			end
			local look = root.CFrame.LookVector
			local yaw = math.atan2(look.X, look.Z)
			if e.prop == "lawn_chair" then
				local m = Instance.new("Model")
				m.Name = "LawnChair"
				local base = CFrame.new(g) * CFrame.Angles(0, yaw + math.pi, 0)
				local seat = Instance.new("Seat")
				seat.Name = "Seat"
				seat.Size = Vector3.new(2, 0.3, 1.8)
				seat.CFrame = base * CFrame.new(0, 1.0, 0)
				seat.Color = Color3.fromRGB(60, 150, 90)
				seat.Anchored = true
				seat.Material = Enum.Material.Fabric
				seat.Parent = m
				local back = newPart(
					"Back",
					Vector3.new(2, 2, 0.15),
					base * CFrame.new(0, 2.0, 0.9),
					Color3.fromRGB(250, 200, 60),
					m
				)
				back.CanCollide = true
				newPart(
					"Frame",
					Vector3.new(2.1, 0.12, 2),
					base * CFrame.new(0, 0.5, 0),
					Color3.fromRGB(200, 202, 208),
					m
				)
				m.Parent = folder
				local owner = player
				local fold = Instance.new("ProximityPrompt")
				fold.ActionText = "Fold up"
				fold.ObjectText = "Lawn chair"
				fold.HoldDuration = 0.4
				fold.RequiresLineOfSight = false
				fold.MaxActivationDistance = 7
				fold.Parent = seat
				fold.Triggered:Connect(function(who: Player)
					if who ~= owner then
						notify(who, "That is somebody's chair.")
						return
					end
					if seat.Occupant then
						seat:Sit(nil :: any)
					end
					m:Destroy()
					opts.inventory.add(owner, "lawn_chair")
				end)
				-- its owner sits down in it at once
				local holder = actorOf(player)
				local body = if holder then holder.body else nil
				local hum = body and body:FindFirstChildOfClass("Humanoid")
				if hum then
					task.defer(function()
						seat:Sit(hum)
					end)
				end
				-- an owner who leaves the game takes the chair along
				task.spawn(function()
					while m.Parent do
						if owner.Parent ~= Players then
							m:Destroy()
						end
						task.wait(5)
					end
				end)
			else
				local p = newPart(
					"WhoopeeCushion",
					Vector3.new(1.2, 0.25, 1.2),
					CFrame.new(g + Vector3.new(0, 0.12, 0)),
					Color3.fromRGB(255, 120, 160),
					folder
				)
				p.Shape = Enum.PartType.Cylinder
				p.CFrame = CFrame.new(g + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2)
				local c: Cushion = { part = p, owner = player, armed = true }
				table.insert(cushions, c)
				local prompt = Instance.new("ProximityPrompt")
				prompt.ActionText = "Pick up"
				prompt.ObjectText = "Whoopee cushion"
				prompt.RequiresLineOfSight = false
				prompt.MaxActivationDistance = 6
				prompt.Parent = p
				prompt.Triggered:Connect(function(who: Player)
					local a = actorOf(who)
					if p.Parent and a and a.species == "human" then
						p:Destroy()
						opts.inventory.add(who, "whoopee_cushion")
					end
				end)
				Debris:AddItem(p, 600)
			end
			playCue(ItemRules.CUES[if e.prop == "lawn_chair" then "lawn_chair" else "whoopee_cushion"], root)
		elseif kind == "bait" then
			if root == nil then
				return false
			end
			local g = groundBelow(root.Position.X, root.Position.Y, root.Position.Z) or root.Position
			local p = newPart(
				"Bait",
				Vector3.new(1.4, 0.2, 1.4),
				CFrame.new(g + Vector3.new(0, 0.1, 0)),
				if e.item == "bird_seed" then Color3.fromRGB(214, 190, 120) else Color3.fromRGB(170, 120, 70),
				folder
			)
			local world = rt and rt.world
			local untilT = (world and world.now or 0) + e.secs
			for _, t in (targets or {}) :: { ItemService.Target } do
				local b = brainOf(t.id)
				if b and t.player == nil then
					b:onEvent({ type = "bait", x = g.X, z = g.Z, untilTime = untilT })
				end
			end
			local birds: { BasePart } = {}
			for i = 1, e.birds or 0 do
				local a = i * 2.1
				local bird = newPart(
					"Bird",
					Vector3.new(0.5, 0.45, 0.8),
					CFrame.new(g + Vector3.new(math.cos(a) * 3, 0.25, math.sin(a) * 3)),
					Color3.fromRGB(110, 100, 95),
					folder
				)
				bird.Shape = Enum.PartType.Ball
				table.insert(birds, bird)
			end
			table.insert(baits, { part = p :: BasePart, birds = birds, untilT = os.clock() + e.secs, t = 0 } :: Bait)
		elseif kind == "treat" then
			local a = actorOf(player)
			local body = a and a.body
			if body then
				body:SetAttribute("TreatUntil", workspace:GetServerTimeNow() + e.secs)
				body:SetAttribute("TreatScale", e.scale)
			end
			playCue(ItemRules.CUES.soda, root)
		elseif kind == "kite" then
			for _, k in kites do
				if k.player == player then
					kiteDown(k)
					return true
				end
			end
			if not e.on then
				return true
			end
			local tool = toolOf(player, "kite")
			local hand = tool and tool:FindFirstChild("Handle")
			if tool == nil or hand == nil or root == nil then
				notify(player, "Hold the kite to fly it.")
				return false
			end
			local m = Instance.new("Model")
			m.Name = "Kite"
			for _, c in tool:GetChildren() do
				if c:IsA("BasePart") then
					local p = c:Clone()
					p.Anchored = true
					for _, w in p:GetChildren() do
						if w:IsA("WeldConstraint") then
							w:Destroy()
						end
					end
					p.Parent = m
				end
			end
			m.Parent = folder
			local first = m:FindFirstChildWhichIsA("BasePart") :: BasePart
			m.PrimaryPart = first
			local a0 = Instance.new("Attachment")
			a0.Parent = hand
			local a1 = Instance.new("Attachment")
			a1.Parent = first
			local beam = Instance.new("Beam")
			beam.Attachment0 = a0
			beam.Attachment1 = a1
			beam.Width0, beam.Width1 = 0.05, 0.05
			beam.Color = ColorSequence.new(Color3.fromRGB(240, 240, 230))
			beam.CurveSize0 = -4
			beam.FaceCamera = true
			beam.Parent = first
			-- the tool's own model is hidden while its copy flies (the string runs from the hand)
			for _, c in tool:GetChildren() do
				if c:IsA("BasePart") then
					c.Transparency = 1
				end
			end
			table.insert(kites, { player = player, model = m, a0 = a0, a1 = a1, t = 0 })
			notify(player, "Up she goes! Use it again to reel it in.")
		end
		return true
	end

	local service = ItemService.new({
		inventory = opts.inventory,
		now = function(): number
			return os.clock()
		end,
		pose = function(player: any): ItemService.Pose?
			local r = rootOf(player)
			if r == nil then
				return nil
			end
			local look = r.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
			return { x = r.Position.X, y = r.Position.Y, z = r.Position.Z, lx = flat.X, lz = flat.Z }
		end,
		speciesOf = function(player: any): string?
			local a = actorOf(player)
			return if a and a.body then a.species else nil
		end,
		night = function(): boolean
			local ok, h = pcall(function()
				return clock:game().hour
			end)
			local hour = if ok then h else 12
			return hour < 6 or hour >= 19.5
		end,
		zoneAt = function(x: number, z: number): string?
			return ItemService.kiteZoneAt(opts.zones, x, z)
		end,
		nearby = nearby,
		filter = function(player: any, text: string): string?
			if typeof(player) ~= "Instance" then
				return nil
			end
			local ok, result = pcall(function()
				local f = TextService:FilterStringAsync(text, (player :: Player).UserId)
				return f:GetNonChatStringForBroadcastAsync()
			end)
			return if ok then result else nil
		end,
		notify = notify,
		refuse = function(player: any, words: string)
			opts.fire(player, { kind = "refused", text = words })
		end,
		act = act,
	})

	local function step()
		-- kites: up on the string, swaying downwind; reeled in on a second use, out of the zone or without a flier
		local K = ItemWorld.KITE
		for i = #kites, 1, -1 do
			local k = kites[i]
			local root = rootOf(k.player)
			local inZone = root ~= nil
				and ItemService.kiteZoneAt(opts.zones, root.Position.X, root.Position.Z) ~= nil
				and toolOf(k.player, "kite") ~= nil
			if not inZone then
				kiteDown(k)
			end
			k.t += 0.1
			local up = math.min(1, k.t / K.launchSecs)
			if k.reel then
				k.reel += 0.1
				up = math.max(0, 1 - k.reel / K.reelSecs) * math.min(1, k.t / K.launchSecs)
			end
			if root then
				local sway = math.sin(k.t * math.pi * 2 * K.swayHz) * K.sway
				local wx, wz = K.wind[1], K.wind[2]
				local pos = root.Position
					+ Vector3.new(
						wx * K.back * up - wz * sway * up,
						K.height * up + 2,
						wz * K.back * up + wx * sway * up
					)
				local face = CFrame.lookAt(pos, root.Position) * CFrame.Angles(0, 0, math.sin(k.t * 1.3) * 0.25)
				k.model:PivotTo(face)
			end
			if (k.reel and k.reel >= K.reelSecs) or root == nil then
				k.model:Destroy()
				k.a0:Destroy()
				local tool = toolOf(k.player, "kite")
				for _, c in (if tool then tool:GetChildren() else {}) :: { Instance } do
					if c:IsA("BasePart") then
						c.Transparency = 0
					end
				end
				table.remove(kites, i)
			end
		end
		-- whoopee cushions: the next person within a stud and a half (not the one who put it down) sets it off
		for i = #cushions, 1, -1 do
			local c = cushions[i]
			if c.part.Parent == nil then
				table.remove(cushions, i)
				continue
			end
			if not c.armed then
				continue
			end
			local p = c.part.Position
			for _, t in nearby(p.X, p.Z, 1.5) do
				if t.kind == "human" and t.player ~= c.owner then
					c.armed = false
					playCue(ItemRules.CUES.whoopee_cushion, c.part)
					c.part.Size = Vector3.new(0.1, 1.2, 1.2)
					if t.player then
						notify(t.player, "PFFFT! Somebody left a whoopee cushion.")
					end
					if typeof(c.owner) == "Instance" and c.owner.Parent == Players then
						notify(c.owner, "Your whoopee cushion went off!")
					end
					break
				end
			end
		end
		-- baits: the birds hop about the pile; it is gone when its time is up
		local now = os.clock()
		for i = #baits, 1, -1 do
			local b = baits[i]
			b.t += 0.1
			if now >= b.untilT or b.part.Parent == nil then
				b.part:Destroy()
				for _, bird in b.birds do
					bird:Destroy()
				end
				table.remove(baits, i)
				continue
			end
			local c = b.part.Position
			for j, bird in b.birds do
				local a = b.t * 0.4 + j * 2.1
				local hop = math.max(0, math.sin(b.t * 6 + j)) * 0.4
				bird.CFrame = CFrame.new(c + Vector3.new(math.cos(a) * 2.2, 0.25 + hop, math.sin(a) * 2.2))
			end
		end
	end

	if opts.heartbeat ~= false then
		local acc = 0
		table.insert(
			conns,
			game:GetService("RunService").Heartbeat:Connect(function(dt: number)
				acc += dt
				if acc >= 0.1 then
					acc = 0
					step()
				end
			end)
		)
	end

	return {
		service = service,
		use = function(player: any, itemId: string, payload: { [string]: any }?): (boolean, string?)
			return service:use(player, itemId, payload)
		end,
		step = step,
		stop = function()
			for _, c in conns do
				c:Disconnect()
			end
			folder:Destroy()
		end,
	}
end

return ItemWorld
