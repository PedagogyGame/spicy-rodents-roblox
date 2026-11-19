--!strict
-- ServerScriptService.Server.Wildlife.YardHazards
-- The town's yard dogs (Shared/Wildlife/YardDogs has the yards and the dog's mind; brief v2's backyard "dog
-- houses", v5.4's yard dogs). Eight friendly plain-part dogs, one to a yard; a kennel where the town has no
-- doghouse. (Yard cats' swat is not built: the town has no yard cats yet.)
--   * Each dog is a brain on the town's scheduler (TownAI world.scheduler, kind "Dog"): it thinks every
--     YardDogs.THINK seconds and only while a player is near (the scheduler's "near" tier, 150 studs); further off
--     it stands still. It sees squirrels through the town's threat grid (ctx.threats: a squirrel hidden in a
--     storm drain is not in it).
--   * Its body moves at MOVE_HZ, again only near a player: one BulkMoveTo for every near dog's parts. Poses: a
--     walking trot, sitting and wagging while a treat lasts, lying in front of its house at night, the head up for
--     a bark.
--   * A bark (YardDogs.BARK_EVERY apart, at a squirrel on the ground in its yard): the cue "Dogs.Bark" (the game's
--     own bark, Shared/Audio/Uploads "dog_bark": owner #36; silent until the lead uploads it), a computer squirrel
--     bolts (its brain's "startle", away from the dog), a player
--     on a squirrel or the rodent is told to clear off (a notice: no shove, no harm), and at the Spicy Rodent the
--     computer-run people within YardDogs.ALERT_RADIUS notice it (their brain's "witness": v5.4's bark alert).
--   * A dog treat (Items/ItemWorld "calm_dog", the corner store's dog treats): near(x, z, r) lists the dogs as
--     targets of kind "dog"; calm(id, secs) sits that dog down, wagging and deaf to squirrels, for the seconds.
-- Interface: start(opts) -> Handle { dogs, near(x, z, r) -> { Target }, calm(id, secs) -> boolean, step(dt)
--   (bodies: the Heartbeat does it), counts() -> { dogs, near, parts }, stop() }; MOVE_HZ; ID_BASE; SOUNDS;
--   FOLDER; WORDS
-- Engine only inside the functions; no side effects on require.

local Import = require("../Import")
local YardDogs = Import.shared("Wildlife/YardDogs") :: typeof(require("../../shared/Wildlife/YardDogs"))
local Clock = Import.shared("Time/Clock") :: typeof(require("../../shared/Time/Clock"))
local Uploads = Import.shared("Audio/Uploads") :: typeof(require("../../shared/Audio/Uploads"))

local YardHazards = {}

YardHazards.FOLDER = "YardDogs"
YardHazards.MOVE_HZ = 15 -- body updates a second for a dog near a player
YardHazards.ID_BASE = 900000 -- the dogs' ids on the town's scheduler (never a town actor's)
YardHazards.SOUNDS = table.freeze({
	["Dogs.Bark"] = Uploads.id("dog_bark"), -- the game's own friendly "woof woof" (owner #36: a custom upload)
})
YardHazards.WORDS = table.freeze({
	chased = "WOOF! A yard dog chases you out of its yard.",
})

type Dog = typeof(YardDogs.newDog(YardDogs.YARDS[1], 1))
-- (YardDogs' exported types do not cross the Import cast)
type Yard = typeof(YardDogs.YARDS[1])
type Squirrel = { id: any, x: number, y: number, z: number, ground: number, rodent: boolean }

export type Target = { kind: string, id: any, x: number, y: number, z: number, player: any? }
export type Handle = {
	dogs: { Dog },
	near: (x: number, z: number, r: number) -> { Target },
	calm: (id: any, secs: number) -> boolean,
	step: (dt: number) -> (),
	counts: () -> { dogs: number, near: number, parts: number },
	stop: () -> (),
}
export type StartOpts = {
	world: any, -- AI/TownAI World: scheduler, ctx, brains, actors, now
	runtime: any?, -- Actors/ActorsRuntime (byTownId): who holds a squirrel
	possession: any?, -- Actors/Possession (controllerOf)
	fire: (player: any, payload: { [string]: any }) -> (),
	groundAt: (x: number, z: number) -> number,
	night: (() -> boolean)?, -- default: the town's clock (before 6:00 or from 19:30)
	parent: Instance?,
	heartbeat: boolean?,
}

-- One part of a dog: name, size, offset from the root (front is -Z), which colour (1 fur, 2 ears, 3 dark, 4 collar)
-- stylua: ignore
local BODY = {
	{ "Body", { 1.6, 1.3, 3.0 }, { 0, 0, 0 }, 1 },
	{ "Head", { 1.2, 1.1, 1.2 }, { 0, 0.7, -1.75 }, 1 },
	{ "Snout", { 0.7, 0.5, 0.7 }, { 0, 0.45, -2.6 }, 1 },
	{ "Nose", { 0.32, 0.28, 0.2 }, { 0, 0.62, -2.98 }, 3 },
	{ "EarL", { 0.3, 0.6, 0.25 }, { -0.45, 1.3, -1.6 }, 2 },
	{ "EarR", { 0.3, 0.6, 0.25 }, { 0.45, 1.3, -1.6 }, 2 },
	{ "Collar", { 1.3, 0.25, 0.3 }, { 0, 0.35, -1.25 }, 4 },
	{ "LegFL", { 0.4, 1.0, 0.4 }, { -0.5, -0.8, -1.0 }, 1 },
	{ "LegFR", { 0.4, 1.0, 0.4 }, { 0.5, -0.8, -1.0 }, 1 },
	{ "LegBL", { 0.4, 1.0, 0.4 }, { -0.5, -0.8, 1.0 }, 1 },
	{ "LegBR", { 0.4, 1.0, 0.4 }, { 0.5, -0.8, 1.0 }, 1 },
	{ "Tail", { 0.25, 0.25, 1.1 }, { 0, 0.55, 1.75 }, 1 },
} :: { { any } }
YardHazards.BODY_PARTS = #BODY

local function newPart(name: string, size: Vector3, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
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

local function rgb(c: { number }, k: number?): Color3
	local f = k or 1
	return Color3.fromRGB(math.min(255, c[1] * f), math.min(255, c[2] * f), math.min(255, c[3] * f))
end

-- The part's place this frame: its rest offset, moved for the pose (legs trot, the tail wags, the head barks).
local function poseOf(name: string, rest: Vector3, dog: Dog, t: number, barking: boolean): CFrame
	local cf = CFrame.new(rest)
	local legs = string.sub(name, 1, 3) == "Leg"
	if dog.lying then
		if legs then
			-- paws out in front, back legs folded alongside
			local fwd = if rest.Z < 0 then -0.5 else 0.2
			return CFrame.new(rest.X * 1.1, -0.45, rest.Z + fwd) * CFrame.Angles(math.rad(90), 0, 0)
		elseif name == "Head" or name == "Snout" or name == "Nose" or name == "EarL" or name == "EarR" then
			return CFrame.new(rest + Vector3.new(0, -0.5, 0))
		end
		return cf
	end
	if legs and dog.speed > 0 then
		local front = rest.Z < 0
		local left = rest.X < 0
		local s = math.sin(t * (if dog.speed > YardDogs.WALK then 16 else 9)) * 0.45
		local swing = if front == left then s else -s
		return CFrame.new(rest + Vector3.new(0, 0.5, 0)) * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -0.5, 0)
	end
	if name == "Tail" then
		local wag = if dog.mode == "calm"
			then math.sin(t * 14) * 0.7
			elseif dog.mode == "chase" then math.sin(t * 9) * 0.3
			else 0
		return CFrame.new(rest) * CFrame.Angles(0, wag, 0) * CFrame.Angles(math.rad(-35), 0, 0)
	end
	if barking and (name == "Head" or name == "Snout" or name == "Nose" or name == "EarL" or name == "EarR") then
		return CFrame.new(rest + Vector3.new(0, 0.25, 0))
	end
	return cf
end

-- The root's frame: on the ground under the dog, facing its yaw; sitting tips it back, lying sets it down.
local function rootOf(dog: Dog, ground: number): CFrame
	local base = CFrame.new(dog.x, ground + YardDogs.HIP, dog.z) * CFrame.Angles(0, dog.yaw + math.pi, 0)
	if dog.lying then
		return base * CFrame.new(0, -0.75, 0)
	elseif dog.mode == "calm" then
		return base * CFrame.new(0, -0.3, 0.3) * CFrame.Angles(math.rad(22), 0, 0)
	end
	return base
end

-- A kennel for a yard the town gave no doghouse: a box, a pitched roof and a dark doorway, behind the home spot.
local function kennel(yard: Yard, groundAt: (number, number) -> number, parent: Instance): number
	local m = Instance.new("Model")
	m.Name = `Kennel_{yard.id}`
	local cx, cz = YardDogs.kennelOf(yard)
	assert(cx and cz, "a kennel only where the town has no doghouse")
	local side = YardDogs.KENNEL.half * 2
	local g = groundAt(cx, cz)
	local face = CFrame.new(cx, g, cz) * CFrame.Angles(0, math.atan2(yard.faceX, yard.faceZ) + math.pi, 0)
	local wood = Color3.fromRGB(150, 96, 60)
	local box = newPart("Box", Vector3.new(side, 2.6, side), wood, m)
	box.CFrame = face * CFrame.new(0, 1.3, 0)
	box.CanCollide = true
	box.CanQuery = true -- (a squirrel's casts find it, as a person's body bumps it)
	box.Material = Enum.Material.WoodPlanks
	local roof = Color3.fromRGB(122, 52, 44)
	for _, s in { -1, 1 } do
		local r = newPart("Roof", Vector3.new(2.4, 0.25, 3.9), roof, m)
		r.CFrame = face * CFrame.new(s * 0.95, 3.2, 0) * CFrame.Angles(0, 0, s * -math.rad(38))
	end
	local door = newPart("Door", Vector3.new(1.5, 1.8, 0.05), Color3.fromRGB(28, 22, 18), m)
	door.CFrame = face * CFrame.new(0, 0.95, -1.73)
	m.Parent = parent
	return 4
end

function YardHazards.start(opts: StartOpts): Handle
	local world = opts.world
	local folder = Instance.new("Folder")
	folder.Name = YardHazards.FOLDER
	folder.Parent = opts.parent or workspace
	local night = opts.night
	if night == nil then
		local clock = Clock.fromEngine()
		night = function(): boolean
			local ok, h = pcall(function()
				return clock:game().hour
			end)
			local hour = if ok then h else 12
			return hour < 6 or hour >= 19.5
		end
	end
	local isNight = night :: () -> boolean

	type Body = { model: Model, parts: { BasePart }, rest: { Vector3 }, names: { string }, bark: Sound }
	local dogs: { Dog } = {}
	local bodies: { Body } = {}
	local actors: { any } = {}
	local barkAt: { number } = {}
	local parts = 0

	-- who holds a town squirrel (nil: the computer)
	local function holderOf(id: any): any?
		local rt = opts.runtime
		local actor = rt and rt.byTownId and rt.byTownId[id]
		local holder = actor and opts.possession and opts.possession:controllerOf(actor)
		return if holder ~= nil and holder ~= "ai" then holder else nil
	end

	local function bark(dog: Dog, s: Squirrel)
		barkAt[dog.index] = world.now
		local snd = bodies[dog.index].bark
		if snd.SoundId ~= "" then
			snd:Play()
		end
		local player = holderOf(s.id)
		if player then
			opts.fire(player, { kind = "notice", text = YardHazards.WORDS.chased })
		else
			local b = world.brains and world.brains[s.id]
			if b then
				b:onEvent({ type = "startle", x = dog.x, z = dog.z }) -- (away from the dog)
			end
		end
		-- at the Spicy Rodent: the people near the bark notice it (v5.4: a bark put them on alert)
		if s.rodent then
			local r2 = YardDogs.ALERT_RADIUS * YardDogs.ALERT_RADIUS
			for _, a in world.actors do
				if a.species == "human" and not (world.possessed and world.possessed[a.id]) then
					local dx, dz = a.x - dog.x, a.z - dog.z
					if dx * dx + dz * dz <= r2 then
						local b = world.brains[a.id]
						if b then
							b:onEvent({ type = "witness", threat = { x = s.x, z = s.z }, alert = 3 })
						end
					end
				end
			end
		end
	end

	for i, yard in YardDogs.YARDS do
		local dog = YardDogs.newDog(yard, i)
		dogs[i] = dog
		local fur = YardDogs.FUR[(i - 1) % #YardDogs.FUR + 1]
		local ears = YardDogs.FUR[i % #YardDogs.FUR + 1]
		local colors = { rgb(fur), rgb(ears, 0.85), Color3.fromRGB(26, 22, 20), Color3.fromRGB(160, 64, 50) }
		local m = Instance.new("Model")
		m.Name = `Dog_{yard.id}`
		local list: { BasePart }, rest: { Vector3 }, names: { string } = {}, {}, {}
		for k, b in BODY do
			local size, at = b[2] :: { number }, b[3] :: { number }
			local p = newPart(b[1] :: string, Vector3.new(size[1], size[2], size[3]), colors[b[4] :: number], m)
			list[k], rest[k], names[k] = p, Vector3.new(at[1], at[2], at[3]), b[1] :: string
		end
		m.PrimaryPart = list[1]
		local snd = Instance.new("Sound")
		snd.Name = "Dogs.Bark"
		snd.SoundId = YardHazards.SOUNDS["Dogs.Bark"]
		snd.RollOffMaxDistance = 90
		snd.Parent = list[2]
		m:SetAttribute("Yard", yard.id)
		m.Parent = folder
		bodies[i] = { model = m, parts = list, rest = rest, names = names, bark = snd }
		parts += #list
		if yard.doghouse == nil then
			parts += kennel(yard, opts.groundAt, folder)
		end
		-- its brain on the town's scheduler
		local actor = {
			id = YardHazards.ID_BASE + i,
			species = "dog",
			variant = "yard",
			brainKind = "Dog",
			x = dog.x,
			y = YardDogs.HIP,
			z = dog.z,
			yaw = dog.yaw,
			speed = 0,
			hip = YardDogs.HIP,
			tier = "far",
			alert = 0,
			moved = 0,
		}
		actors[i] = actor
		local brain = {
			kind = "Dog",
			think = function(_self: any, _dt: number, ctx: any)
				if actor.tier ~= "near" then
					return -- nobody near: it stands
				end
				YardDogs.think(dog, ctx.now, {
					night = isNight(),
					squirrels = function(x: number, z: number, r: number): { Squirrel }
						local out: { Squirrel } = {}
						local buf = ctx.queryBuffer
						local n = ctx.threats:query(x, z, r, buf)
						for j = 1, n do
							local a = ctx.actorsById[buf[j]]
							if a then
								table.insert(out, {
									id = a.id,
									x = a.x,
									y = a.y - (a.hip or 0),
									z = a.z,
									ground = ctx.groundAt(a.x, a.z),
									rodent = a.variant == "spicy",
								})
							end
						end
						return out
					end,
					bark = bark,
				})
			end,
			suspend = function(_self: any): { [string]: any }
				return {}
			end,
			resume = function(_self: any, _s: any) end,
			onEvent = function(_self: any, evt: { [string]: any })
				if evt.type == "calm" and type(evt.untilTime) == "number" then
					YardDogs.calm(dog, evt.untilTime)
					dog.nextThink = 0
				end
			end,
		}
		world.scheduler:register(actor.id, brain :: any, actor :: any, world.now)
	end

	-- the bodies: every near dog moved and posed in one BulkMoveTo
	local clockT = 0
	local movedParts: { BasePart } = {}
	local movedFrames: { CFrame } = {}
	local function step(dt: number)
		clockT += dt
		table.clear(movedParts)
		table.clear(movedFrames)
		for i, dog in dogs do
			local actor = actors[i]
			if actor.tier ~= "near" then
				continue
			end
			YardDogs.move(dog, dt)
			actor.x, actor.z, actor.yaw, actor.speed = dog.x, dog.z, dog.yaw, dog.speed
			local body = bodies[i]
			local root = rootOf(dog, opts.groundAt(dog.x, dog.z))
			local barking = world.now - (barkAt[i] or -math.huge) < 0.4
			for k, p in body.parts do
				table.insert(movedParts, p)
				table.insert(movedFrames, root * poseOf(body.names[k], body.rest[k], dog, clockT + i, barking))
			end
		end
		if #movedParts > 0 then
			workspace:BulkMoveTo(movedParts, movedFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end
	-- every dog at its place once (a far one stands there until a player comes near)
	for i, dog in dogs do
		local body = bodies[i]
		local root = rootOf(dog, opts.groundAt(dog.x, dog.z))
		for k, p in body.parts do
			p.CFrame = root * poseOf(body.names[k], body.rest[k], dog, 0, false)
		end
	end

	local conns: { RBXScriptConnection } = {}
	if opts.heartbeat ~= false then
		local acc = 0
		table.insert(
			conns,
			game:GetService("RunService").Heartbeat:Connect(function(dt: number)
				acc += dt
				if acc >= 1 / YardHazards.MOVE_HZ then
					step(acc)
					acc = 0
				end
			end)
		)
	end

	return {
		dogs = dogs,
		near = function(x: number, z: number, r: number): { Target }
			local out: { Target } = {}
			for i, dog in dogs do
				local dx, dz = dog.x - x, dog.z - z
				if dx * dx + dz * dz <= r * r then
					table.insert(out, { kind = "dog", id = i, x = dog.x, y = opts.groundAt(dog.x, dog.z), z = dog.z })
				end
			end
			return out
		end,
		calm = function(id: any, secs: number): boolean
			local dog = dogs[id]
			if dog == nil then
				return false
			end
			YardDogs.calm(dog, world.now + secs)
			dog.nextThink = 0
			return true
		end,
		step = step,
		counts = function(): { dogs: number, near: number, parts: number }
			local near = 0
			for _, a in actors do
				if a.tier == "near" then
					near += 1
				end
			end
			return { dogs = #dogs, near = near, parts = parts }
		end,
		stop = function()
			for _, c in conns do
				c:Disconnect()
			end
			for _, a in actors do
				world.scheduler:unregister(a.id)
			end
			folder:Destroy()
		end,
	}
end

return YardHazards
