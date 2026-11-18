--!strict
-- tests/isolated/yard_hazards.luau: cases for tests/unit/yard_hazards.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Server/Wildlife/YardHazards on that fake engine with the town's real brain scheduler and threat grid: eight
-- plain-part dogs and five kennels; a brain each on the scheduler; nobody near, a dog stands still; a player near,
-- it moves; a computer squirrel in its yard is chased and bolts at the bark, a player's is told, people near a
-- bark at the rodent notice it; a dog treat (Items/ItemWorld calm_dog) sits the nearest dog down.
-- Interface: return function(t) (the spec shape)
local FakeEngine = require("@tests/lib/FakeEngine")
local YardHazards = require("@server/Wildlife/YardHazards")
local YardDogs = require("@shared/Wildlife/YardDogs")
local BrainScheduler = require("@server/Actors/BrainScheduler")
local Perception = require("@server/Actors/Perception")
local ItemWorld = require("@server/Items/ItemWorld")
local roblox = require("@lune/roblox")

type Rig = {
	world: any,
	dogs: any,
	fired: { any },
	focus: { { x: number, z: number } },
	frame: (secs: number) -> (),
	squirrel: (id: number, x: number, z: number, variant: string?) -> any,
	human: (id: number, x: number, z: number) -> any,
	events: { [number]: { any } },
	held: { [number]: any },
}

local function rig(): Rig
	rawset(workspace, "BulkMoveTo", function(_self: any, parts: { any }, cfs: { any })
		for i, p in parts do
			p.CFrame = cfs[i]
		end
	end)
	local grid = Perception.newGrid(40)
	local actorsById: { [number]: any } = {}
	local ctx = {
		now = 0,
		rng = math.random,
		groundAt = function(): number
			return 0
		end,
		threats = grid,
		actorsById = actorsById,
		queryBuffer = table.create(32),
	}
	local scheduler = BrainScheduler.new(BrainScheduler.DEFAULTS)
	local focus: { { x: number, z: number } } = {}
	scheduler:setFocus(function()
		return focus
	end)
	local events: { [number]: { any } } = {}
	local world = {
		scheduler = scheduler,
		ctx = ctx,
		brains = {},
		actors = {},
		actorsById = actorsById,
		possessed = {},
		now = 0,
	}
	local held: { [number]: any } = {}
	local fired = {}
	local function brain(id: number): any
		events[id] = {}
		return {
			onEvent = function(_s: any, e: any)
				table.insert(events[id], e)
			end,
		}
	end
	local dogs = YardHazards.start({
		world = world,
		runtime = {
			byTownId = setmetatable({}, {
				__index = function(_t, id)
					return { townId = id }
				end,
			}),
		},
		possession = {
			controllerOf = function(_s: any, actor: any): any
				return held[actor.townId] or "ai"
			end,
		},
		fire = function(p: any, msg: any)
			table.insert(fired, { p, msg })
		end,
		groundAt = function(): number
			return 0
		end,
		night = function(): boolean
			return false
		end,
		heartbeat = false,
	})
	local r: Rig
	r = {
		world = world,
		dogs = dogs,
		fired = fired,
		focus = focus,
		events = events,
		held = held,
		frame = function(secs: number)
			for _ = 1, math.floor(secs / (1 / 15) + 0.5) do
				world.now += 1 / 15
				ctx.now = world.now
				scheduler:step(1 / 15, world.now, ctx :: any)
				dogs.step(1 / 15)
			end
		end,
		squirrel = function(id: number, x: number, z: number, variant: string?): any
			local a = { id = id, species = "squirrel", variant = variant or "grey", x = x, y = 0.5, z = z, hip = 0.5 }
			actorsById[id] = a
			table.insert(world.actors, a)
			world.brains[id] = brain(id)
			grid:set(id, x, z)
			return a
		end,
		human = function(id: number, x: number, z: number): any
			local a = { id = id, species = "human", x = x, y = 3, z = z, hip = 3 }
			actorsById[id] = a
			table.insert(world.actors, a)
			world.brains[id] = brain(id)
			return a
		end,
	}
	return r
end

local function bodyOf(i: number): any
	local folder = workspace:FindFirstChild(YardHazards.FOLDER)
	return folder:FindFirstChild(`Dog_{YardDogs.YARDS[i].id}`)
end

return function(t)
	t.test(
		"eight dogs of plain parts, five kennels, a brain each on the town's scheduler; stop takes them away",
		function()
			FakeEngine.with(function()
				local r = rig()
				local folder = workspace:FindFirstChild(YardHazards.FOLDER)
				local dogsN, kennels = 0, 0
				for _, m in folder:GetChildren() do
					if string.sub(m.Name, 1, 4) == "Dog_" then
						dogsN += 1
						t.eq(#m:GetChildren(), YardHazards.BODY_PARTS)
						for _, p in m:GetChildren() do
							t.eq(p.CanCollide, false, "a dog walls nobody off")
							t.eq(p.CastShadow, false)
						end
					elseif string.sub(m.Name, 1, 7) == "Kennel_" then
						kennels += 1
					end
				end
				t.eq(dogsN, 8)
				t.eq(kennels, 5, "a kennel where the town has no doghouse")
				t.eq(r.dogs.counts().parts, 8 * YardHazards.BODY_PARTS + 5 * 4)
				for i = 1, 8 do
					t.truthy(r.world.scheduler.byId[YardHazards.ID_BASE + i], `dog {i} on the scheduler`)
				end
				-- every dog stands on its yard's ground from the start
				for i, y in YardDogs.YARDS do
					local p = bodyOf(i).PrimaryPart.CFrame.Position
					t.truthy(YardDogs.inYard(y, p.X, p.Z), y.id)
					t.near(p.Y, YardDogs.HIP, 1e-6)
				end
				r.dogs.stop()
				t.eq(workspace:FindFirstChild(YardHazards.FOLDER), nil)
				t.eq(#r.world.scheduler.entries, 0)
			end)
		end
	)

	t.test("nobody near: a dog stands still and thinks nothing; a player near: it gets about", function()
		FakeEngine.with(function()
			local r = rig()
			local y = YardDogs.YARDS[1]
			local before = bodyOf(1).PrimaryPart.CFrame.Position
			r.frame(10)
			t.eq(bodyOf(1).PrimaryPart.CFrame.Position, before, "far from everyone: still")
			t.eq(r.dogs.counts().near, 0)
			table.insert(r.focus, { x = (y.x0 + y.x1) / 2, z = (y.z0 + y.z1) / 2 })
			r.frame(15)
			t.eq(r.dogs.counts().near, 1, "only the one with a player near")
			t.neq(bodyOf(1).PrimaryPart.CFrame.Position, before, "it moved")
			t.near(bodyOf(2).PrimaryPart.CFrame.Position.Y, YardDogs.HIP, 1e-4, "the others stand")
		end)
	end)

	t.test(
		"a squirrel in the yard: chased, it bolts at the bark; a player's is told; the rodent alerts people",
		function()
			FakeEngine.with(function()
				local r = rig()
				local y = YardDogs.YARDS[2]
				table.insert(r.focus, { x = y.x0, z = y.z0 })
				r.frame(2)
				r.squirrel(11, y.x0 + 3, y.z0 + 3)
				r.frame(1.5)
				t.eq(r.dogs.dogs[2].mode, "chase")
				t.eq(r.events[11][1] and r.events[11][1].type, "startle", "the computer squirrel bolts")
				-- a player on the rodent, and a person near the bark
				local rod = r.squirrel(12, y.x1 - 3, y.z1 - 3, "spicy")
				r.held[12] = { Name = "P" }
				r.human(13, y.x1 + 5, y.z1)
				r.human(14, y.x1 + 200, y.z1)
				r.world.actorsById[11] = nil
				r.world.ctx.threats:remove(11)
				r.frame(YardDogs.BARK_EVERY + 1)
				t.truthy(#r.fired >= 1, "the player is told")
				t.eq(r.fired[1][2].text, YardHazards.WORDS.chased)
				t.eq(r.events[13][1] and r.events[13][1].type, "witness", "a person near notices the rodent")
				t.eq(r.events[13][1].threat.x, rod.x)
				t.eq(#r.events[14], 0, "one far off does not")
				-- the dog never leaves its yard chasing
				local p = bodyOf(2).PrimaryPart.CFrame.Position
				t.truthy(YardDogs.inYard(y, p.X, p.Z))
			end)
		end
	)

	t.test("near and calm: a treat sits the dog down, no barking while it lasts", function()
		FakeEngine.with(function()
			local r = rig()
			local y = YardDogs.YARDS[3]
			local d = r.dogs.dogs[3]
			local near = r.dogs.near(d.x + 4, d.z, 12)
			t.eq(#near, 1)
			t.eq(near[1].kind, "dog")
			t.eq(near[1].id, 3)
			t.eq(#r.dogs.near(d.x + 40, d.z, 12), 0)
			t.truthy(r.dogs.calm(3, 120))
			t.falsy(r.dogs.calm(99, 120), "no such dog")
			table.insert(r.focus, { x = d.x, z = d.z })
			r.squirrel(21, y.x0 + 2, y.z0 + 2)
			r.frame(3)
			t.eq(d.mode, "calm")
			t.eq(#r.events[21], 0, "no bark at the squirrel")
		end)
	end)

	t.test("the dog treats in the hand: Items/ItemWorld gives the nearest dog the treat", function()
		FakeEngine.with(function()
			-- selene: allow(deprecated)
			local env = getfenv(0) :: any
			env.ColorSequence = roblox.ColorSequence
			rawset(game:GetService("Debris"), "AddItem", function() end)
			rawset(workspace, "GetServerTimeNow", function()
				return 0
			end)
			local p = FakeEngine.new("Player", "Giver")
			rawset(p, "UserId", 5)
			p.Parent = game:GetService("Players")
			local body = FakeEngine.model("GiverBody", roblox.CFrame.new(10, 3, 10), nil)
			local root = FakeEngine.part("HumanoidRootPart", roblox.CFrame.new(10, 3, 10), body)
			body.PrimaryPart = root
			rawset(p, "Character", body)
			local calmed = {}
			local notices = {}
			local world = ItemWorld.start({
				inventory = {
					count = function(): number
						return 1
					end,
					take = function(): boolean
						return true
					end,
				},
				possession = {
					actorOf = function(_s: any, pl: any): any
						return { species = "human", body = pl.Character }
					end,
				},
				runtime = nil,
				fire = function(_p: any, msg: any)
					table.insert(notices, msg.text)
				end,
				dogs = {
					near = function(x: number, z: number, r: number): { any }
						local out = {}
						for id, at in { { 14, 10 }, { 18, 10 } } do
							if (at[1] - x) ^ 2 + (at[2] - z) ^ 2 <= r * r then
								table.insert(out, { kind = "dog", id = id, x = at[1], y = 0, z = at[2] })
							end
						end
						return out
					end,
					calm = function(id: any, secs: number): boolean
						table.insert(calmed, { id, secs })
						return true
					end,
				},
				heartbeat = false,
			})
			local ok = world.use(p, "dog_treats")
			t.truthy(ok, "given")
			t.eq(calmed[1][1], 1, "the nearer dog")
			t.eq(calmed[1][2], 120)
			t.truthy(
				table.find(notices, "The dog sits and wags its tail. It will leave the squirrels alone for a while.")
			)
			world.stop()
		end)
	end)
end
